-- Wrist optical meal-response history. Dedicated table, not raw_samples.
-- Column and table names never say glucose. Vendor scalars stay internal; screens
-- print only the unitless RESPONSE index.

create table public.response_samples (
  user_id     uuid not null references auth.users (id) on delete cascade,
  ts          timestamptz not null,
  optical     double precision not null check (optical > 0 and optical < 100000),
  sampled_tz  text not null,
  src         text not null default 'band',
  primary key (user_id, ts, src)
);
comment on table public.response_samples is
  'Wrist optical meal-response scalars from the band history. Not a blood test; not a lab unit.';
create index response_samples_user_ts_idx on public.response_samples (user_id, ts);

alter table public.response_samples enable row level security;
create policy own_read on public.response_samples
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.response_samples to authenticated;

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
  v_spo2 smallint; v_optical double precision;
  result_status text;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  perform 1 from public.profiles where user_id=u for share;
  if exists(select 1 from public.profiles where user_id=u and deletion_requested_at is not null)
    then raise exception 'ACCOUNT_DELETING' using errcode='42501'; end if;
  if (select choice from public.consents where user_id=u order by decided_at desc limit 1) is distinct from 'granted'
    then raise exception 'CONSENT_REQUIRED' using errcode='42501'; end if;
  if p_domain not in ('origin','hrv','temperature','rr','sleep','oxygen','response') or p_status not in ('complete','not_collected','unsupported','failed','partial')
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
      if p_domain='response' then
        v_optical:=(s->>'optical')::double precision;
        if v_optical is null or v_optical <= 0 or v_optical >= 100000 or v_optical = 'NaN'::float8 then
          rejected:=rejected+1; continue;
        end if;
        insert into public.response_samples(user_id,ts,optical,sampled_tz,src)
          values(u,t,v_optical,p_timezone,'band') on conflict do nothing;
        get diagnostics n=row_count;
        if n=1 then inserted:=inserted+1;
        elsif exists(select 1 from public.response_samples where user_id=u and ts=t and src='band' and optical=v_optical)
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

create or replace function public.prune_retention() returns void
language plpgsql security definer set search_path='' as $$
begin
 delete from public.screen_frames where created_at < now()-interval '90 days';
 delete from public.analytics_events where server_ts < now()-interval '180 days';
 delete from public.oxygen_samples where ts < now()-interval '400 days';
 delete from public.response_samples where ts < now()-interval '400 days';
end $$;
revoke all on function public.prune_retention() from public,anon,authenticated;

create or replace function public.export_all()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles p where p.user_id = (select auth.uid())),
    'days', (select coalesce(jsonb_agg(to_jsonb(d) order by d.user_day), '[]'::jsonb)
             from public.daily_results d where d.user_id = (select auth.uid())),
    'weigh_ins', (select coalesce(jsonb_agg(to_jsonb(w) order by w.measured_at), '[]'::jsonb)
                  from public.weigh_ins w where w.user_id = (select auth.uid())),
    'composition', (select coalesce(jsonb_agg(to_jsonb(b) order by b.measured_at), '[]'::jsonb)
                    from public.body_composition b where b.user_id = (select auth.uid())),
    'night_hrv', (select coalesce(jsonb_agg(to_jsonb(h) order by h.user_day), '[]'::jsonb)
                  from public.night_hrv h where h.user_id = (select auth.uid())),
    'oxygen_samples', (select coalesce(jsonb_agg(to_jsonb(o) order by o.ts), '[]'::jsonb)
                       from public.oxygen_samples o where o.user_id = (select auth.uid())),
    'response_samples', (select coalesce(jsonb_agg(jsonb_build_object('ts', r.ts) order by r.ts), '[]'::jsonb)
                         from public.response_samples r where r.user_id = (select auth.uid())),
    'meals', (select coalesce(jsonb_agg(to_jsonb(m) order by m.logged_at), '[]'::jsonb)
              from public.meals m where m.user_id = (select auth.uid()) and m.deleted_at is null));
$$;

create or replace function nb.account_delete_legacy_oxygen(confirm text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null then return jsonb_build_object('error', 'UNAUTHENTICATED'); end if;
  if confirm is distinct from 'DELETE' then return jsonb_build_object('error', 'E_SCHEMA'); end if;

  update public.profiles set deletion_requested_at = now() where user_id = v_user;
  delete from public.screen_frames where user_id = v_user;
  delete from public.ai_turns where user_id = v_user;
  delete from public.analytics_events where user_id = v_user;
  delete from public.call_changes where user_id = v_user;
  delete from public.meals where user_id = v_user;
  delete from public.weigh_ins where user_id = v_user;
  delete from public.body_composition where user_id = v_user;
  delete from public.oxygen_samples where user_id = v_user;
  delete from public.response_samples where user_id = v_user;
  delete from public.raw_samples where user_id = v_user;
  delete from public.reserve_samples where user_id = v_user;
  delete from public.sleep_nights where user_id = v_user;
  delete from public.night_hrv where user_id = v_user;
  delete from public.daily_results where user_id = v_user;
  delete from public.sync_runs where user_id = v_user;
  delete from public.device_capabilities where user_id = v_user;
  delete from public.devices where user_id = v_user;
  delete from public.profiles where user_id = v_user;
  delete from auth.users where id = v_user;
  return jsonb_build_object('deleted', true);
end;
$$;

create unique index if not exists banned_phrases_pattern_uidx
  on public.banned_phrases (pattern);

insert into public.banned_phrases (pattern, reason, replace_with) values
  ('(?i)\bglucose\b', '04C · wrist optical meal response is never a blood test', 'RESPONSE'),
  ('(?i)mmol\s*/?\s*l', '04C · meal response never prints a concentration', 'RESPONSE'),
  ('(?i)mg\s*/\s*dl', '04C · meal response never prints a concentration', 'RESPONSE'),
  ('血糖', '04C · glossary is 进餐反应, never 血糖', 'RESPONSE'),
  ('(?i)\bspike\b', '04C · the index is not a spike', 'RESPONSE')
on conflict (pattern) do nothing;
