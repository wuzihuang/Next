-- Overnight SpO2 lives in its own history table. It is not restored onto raw_samples:
-- F5 dropped that column, and origin ticks are five-minute PPG, not the oxygen domain.
-- ADR-0002: mean / min / curve may land on the sleep page; apnea grades may not.

create table public.oxygen_samples (
  user_id     uuid not null references auth.users (id) on delete cascade,
  ts          timestamptz not null,
  spo2        smallint not null check (spo2 between 50 and 100),
  sampled_tz  text not null,
  src         text not null default 'band',
  primary key (user_id, ts, src)
);
comment on table public.oxygen_samples is
  'Overnight automatic SpO2 from the band oxygen history. Not origin ticks; not an apnea grade.';
create index oxygen_samples_user_ts_idx on public.oxygen_samples (user_id, ts);

alter table public.oxygen_samples enable row level security;
create policy own_read on public.oxygen_samples
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.oxygen_samples to authenticated;

create or replace function public.ingest_band_domain(
  p_device_key text, p_domain text, p_day date, p_timezone text,
  p_start timestamptz, p_end timestamptz, p_samples jsonb,
  p_status text default 'complete', p_mapping_version text default 'veepoo-rmssd-v1'
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid(); s jsonb; t timestamptz; old public.raw_samples%rowtype;
  inserted integer:=0; completed integer:=0; unchanged integer:=0; rejected integer:=0;
  changed boolean; n integer; affected date[]:='{}'; rrs real[];
  h smallint; steps integer; calories integer; distance integer; metabolic numeric;
  temperature numeric; variability numeric; pressure smallint; stage smallint;
  v_spo2 smallint;
  result_status text;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  if (select choice from public.consents where user_id=u order by decided_at desc limit 1) is distinct from 'granted'
    then raise exception 'CONSENT_REQUIRED' using errcode='42501'; end if;
  if p_domain not in ('origin','hrv','temperature','rr','sleep','oxygen') or p_status not in ('complete','not_collected','unsupported','failed','partial')
    or p_device_key is null or length(p_device_key) not between 1 and 200
    or p_mapping_version is null or length(p_mapping_version) not between 1 and 80
    or p_day is null or p_start is null or p_end is null or p_end<=p_start
    or p_end-p_start>interval '26 hours'
    or not exists(select 1 from pg_catalog.pg_timezone_names where name=p_timezone)
    or p_samples is null or jsonb_typeof(p_samples)<>'array' or jsonb_array_length(p_samples)>5000
    or octet_length(p_samples::text)>4000000 then
      raise exception 'INVALID_DOMAIN_BATCH' using errcode='22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text,74));
  insert into public.band_ingestion_sources(user_id,device_key,mapping_version,metadata)
    values(u,p_device_key,p_mapping_version,jsonb_build_object('source','band','rr_unit','ms','quality','validated','timezone_basis','phone_mapping_at_read'))
    on conflict do nothing;
  for s in select value from jsonb_array_elements(p_samples) loop
    begin
      t:=(s->>'ts')::timestamptz;
      if t is null or t<p_start or t>=p_end or t>now()+interval '5 minutes' then
        rejected:=rejected+1; continue;
      end if;
      if p_domain='rr' then
        select array_agg(value::real order by ordinal) into rrs
          from jsonb_array_elements_text(s->'rr_ms') with ordinality e(value,ordinal);
        if cardinality(rrs) is null or cardinality(rrs) not between 1 and 4096
          or exists(select 1 from unnest(rrs) x where x<250 or x>2500 or x='NaN'::real) then
          rejected:=rejected+1; continue;
        end if;
        insert into public.band_rr_evidence(user_id,device_key,ts,mapping_version,rr_ms,sampled_tz)
          values(u,p_device_key,t,p_mapping_version,rrs,p_timezone) on conflict do nothing;
        get diagnostics n=row_count;
        if n=1 then inserted:=inserted+1;
        elsif exists(select 1 from public.band_rr_evidence where user_id=u and device_key=p_device_key
          and ts=t and mapping_version=p_mapping_version and rr_ms=rrs) then unchanged:=unchanged+1;
        else rejected:=rejected+1; end if;
        continue;
      end if;
      if p_domain='oxygen' then
        v_spo2:=(s->>'spo2')::smallint;
        if v_spo2 not between 50 and 100 then rejected:=rejected+1; continue; end if;
        insert into public.oxygen_samples(user_id,ts,spo2,sampled_tz,src)
          values(u,t,v_spo2,p_timezone,'band') on conflict do nothing;
        get diagnostics n=row_count;
        if n=1 then inserted:=inserted+1;
        elsif exists(select 1 from public.oxygen_samples where user_id=u and ts=t and src='band' and spo2=v_spo2)
          then unchanged:=unchanged+1;
        else rejected:=rejected+1; end if;
        continue;
      end if;
      if p_domain='sleep' then rejected:=rejected+1; continue; end if;
      h:=null; steps:=null; calories:=null; distance:=null; metabolic:=null; temperature:=null; variability:=null; pressure:=null; stage:=null;
      if p_domain='origin' then
        h:=(s->>'heart')::smallint; steps:=(s->>'step')::integer; calories:=(s->>'cal')::integer;
        distance:=(s->>'dis')::integer; metabolic:=(s->>'met')::numeric;
        pressure:=(s->>'stress')::smallint; stage:=(s->>'sleep_states')::smallint;
      elsif p_domain='temperature' then temperature:=(s->>'temp')::numeric;
      elsif p_domain='hrv' then variability:=(s->>'hrv')::numeric;
      end if;
      if h not between 1 and 250 or steps<0 or calories<0 or distance<0 or metabolic not between 0 and 100
        or pressure not between 0 and 100 or stage not between 0 and 4
        or temperature not between 10 and 50 or variability not between 1 and 300
        or coalesce(h::text,steps::text,calories::text,distance::text,metabolic::text,pressure::text,stage::text,temperature::text,variability::text) is null then
          rejected:=rejected+1; continue;
      end if;
      select * into old from public.raw_samples where user_id=u and ts=t and src='band' for update;
      if not found then
        insert into public.raw_samples(user_id,ts,src,sampled_tz,heart,step,cal,dis,met,temp,hrv,stress,sleep_states,ingestion_device_key,mapping_version,domain_sources)
          values(u,t,'band',p_timezone,h,steps,calories,distance,metabolic,temperature,variability,pressure,stage,p_device_key,p_mapping_version,jsonb_build_object(p_domain,jsonb_build_object('device_key',p_device_key,'mapping_version',p_mapping_version,'received_at',now())));
        inserted:=inserted+1; changed:=true;
      else
        changed:=(old.heart is null and h is not null) or (old.step is null and steps is not null)
          or (old.cal is null and calories is not null) or ((old.dis is null or old.dis=0) and distance>0)
          or (old.met is null and metabolic is not null) or (old.temp is null and temperature is not null)
          or (old.hrv is null and variability is not null) or (old.stress is null and pressure is not null)
          or (old.sleep_states is null and stage is not null);
        if coalesce(changed,false) then
          update public.raw_samples set heart=coalesce(heart,h),step=coalesce(step,steps),cal=coalesce(cal,calories),
            dis=case when dis is null or dis=0 then coalesce(distance,dis) else dis end,
            met=coalesce(met,metabolic),temp=coalesce(temp,temperature),hrv=coalesce(hrv,variability),
            stress=coalesce(stress,pressure),sleep_states=coalesce(sleep_states,stage),
            domain_sources=domain_sources || jsonb_build_object(p_domain,jsonb_build_object('device_key',p_device_key,'mapping_version',p_mapping_version,'received_at',now()))
            where user_id=u and ts=t and src='band';
          completed:=completed+1;
        else unchanged:=unchanged+1; end if;
      end if;
      if coalesce(changed,false) then affected:=array_append(affected,((t at time zone coalesce(old.sampled_tz,p_timezone))-interval '4 hours')::date); end if;
    exception when invalid_text_representation or numeric_value_out_of_range or datetime_field_overflow or check_violation then
      rejected:=rejected+1;
    end;
  end loop;
  result_status:=case when rejected>0 then 'partial' when p_status='complete' and jsonb_array_length(p_samples)=0 and p_domain<>'sleep' then 'not_collected' else p_status end;
  insert into public.sync_domain_status(user_id,device_key,user_day,domain,status,acknowledged_start,acknowledged_end,repair_start,repair_end)
    values(u,p_device_key,p_day,p_domain,result_status,
      case when result_status in ('complete','not_collected','unsupported') then p_start end,
      case when result_status in ('complete','not_collected','unsupported') then p_end end,
      case when result_status in ('failed','partial') then p_start end,
      case when result_status in ('failed','partial') then p_end end)
    on conflict(user_id,device_key,user_day,domain) do update set status=excluded.status,attempted_at=now(),
      acknowledged_start=coalesce(excluded.acknowledged_start,sync_domain_status.acknowledged_start),
      acknowledged_end=coalesce(excluded.acknowledged_end,sync_domain_status.acknowledged_end),
      repair_start=excluded.repair_start,repair_end=excluded.repair_end;
  return jsonb_build_object('inserted',inserted,'completed',completed,'unchanged',unchanged,'rejected',rejected,
    'affected_days',coalesce((select jsonb_agg(distinct x order by x) from unnest(affected) x),'[]'::jsonb),'status',result_status);
end $$;
