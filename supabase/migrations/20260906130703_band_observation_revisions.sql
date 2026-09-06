-- Device reads carry a stable observed_at captured before reading the SDK. Upload
-- receipt time is never a device clock; a queued retry cannot become a new read.
-- Identity stays auth.uid(), mutations retain the account/consent/advisory locks.
-- RR extensions preserve every accepted original-index/value pair. Nullable new
-- columns keep format-1 archives readable with jsonb_populate_recordset; archive
-- full-record equality and hot-first hydration preserve corrected hot evidence.
-- Origin aggregates may arrive before the device has finished a slot. Keep bounded
-- full-page rereads and accept newer observations only from the same source/mapping.
-- The clock below orders SDK database snapshots; it is not a device sensor clock.
create table public.band_origin_corrections (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_key text not null, ts timestamptz not null, mapping_version text not null,
  previous_read_at timestamptz, read_at timestamptz not null,
  received_at timestamptz not null default now(), changes jsonb not null,
  primary key(user_id,device_key,ts,mapping_version,read_at)
);
comment on table public.band_origin_corrections is
  'Changed origin fields with before/after values; account-private audit of ordered SDK rereads.';
alter table public.band_origin_corrections enable row level security;
create policy own_read on public.band_origin_corrections for select to authenticated
  using(user_id=(select auth.uid()));
revoke all on public.band_origin_corrections from public,anon,authenticated;
grant select on public.band_origin_corrections to authenticated;


alter table public.band_rr_evidence add column rr_indices integer[];
alter table public.band_rr_evidence add column observed_at timestamptz;
comment on column public.band_rr_evidence.rr_indices is
  'Zero-based original SDK RR positions, strictly increasing. NULL means legacy contiguous assumption; discarded historical gaps cannot be reconstructed.';
comment on column public.band_rr_evidence.observed_at is
  'Client device-read start persisted through outbox retries, not upload receipt time.';
create function nb.valid_rr_indices(p_indices integer[],p_count integer) returns boolean
language sql immutable set search_path='' as $$
 select p_indices is null or (cardinality(p_indices)=p_count and array_ndims(p_indices)=1
   and not exists(select 1 from generate_subscripts(p_indices,1) i
     where p_indices[i] is null or p_indices[i]<0 or p_indices[i]>4095
       or (i>array_lower(p_indices,1) and p_indices[i]<=p_indices[i-1])));
$$;
revoke all on function nb.valid_rr_indices(integer[],integer) from public,anon,authenticated;
alter table public.band_rr_evidence add constraint band_rr_indices_valid
  check(nb.valid_rr_indices(rr_indices,cardinality(rr_ms)));

-- Supabase default ACLs can grant ALL on new public tables. RLS alone is not
-- this write boundary: the legacy raw own-INSERT policy accepts arbitrary rows,
-- and TRUNCATE is not governed by RLS. Current clients write through the bounded
-- ingestor; service/archive routines keep their existing owner/service privileges.
revoke all on public.raw_samples,public.band_rr_evidence from public,anon,authenticated;
grant select on public.raw_samples,public.band_rr_evidence to authenticated;
-- These retired null-fill RPCs have no device/read-clock/consent checks. In
-- particular fill_hrv could resurrect a retracted value despite table revocation.
-- Keep the definitions for service maintenance, but close the legacy client doors.
revoke all on function public.fill_hrv(jsonb),public.fill_dis(jsonb),public.fill_temp(jsonb)
  from public,anon,authenticated;
grant execute on function public.fill_hrv(jsonb),public.fill_dis(jsonb),public.fill_temp(jsonb) to service_role;

-- Replace the old arity, retaining its defaulted call shape without PostgREST
-- overload ambiguity. The optional timestamp activates ordered corrections.
drop function public.ingest_band_domain(text,text,date,text,timestamptz,timestamptz,jsonb,text,text);
create function public.ingest_band_domain(
  p_device_key text, p_domain text, p_day date, p_timezone text,
  p_start timestamptz, p_end timestamptz, p_samples jsonb,
  p_status text default 'complete', p_mapping_version text default 'veepoo-rmssd-v1',
  p_observed_at timestamptz default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid(); s jsonb; t timestamptz; old public.raw_samples%rowtype;
  inserted integer:=0; completed integer:=0; unchanged integer:=0; rejected integer:=0;
  changed boolean; n integer; affected date[]:='{}'; rrs real[];
  h smallint; steps integer; calories integer; distance integer; metabolic numeric;
  temperature numeric; variability numeric; pressure smallint; stage smallint;
  v_spo2 smallint; v_optical double precision;
  result_status text; rr_old public.band_rr_evidence%rowtype; indices integer[]; previous_indices integer[];
  candidate jsonb; merged jsonb; domain_meta jsonb; field_sources jsonb; prior_source jsonb;
  field_name text; field_value jsonb; prior_time timestamptz; next_source jsonb;
  same_source boolean; can_replace boolean; conflict_found boolean; metadata_changed boolean;
  domain_fields text[]; invalidate_hrv boolean; observation_at timestamptz;
  old_origin_time timestamptz; origin_owner text; origin_mapping text; origin_delta jsonb;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  perform 1 from public.profiles where user_id=u for share;
  if exists(select 1 from public.profiles where user_id=u and deletion_requested_at is not null)
    then raise exception 'ACCOUNT_DELETING' using errcode='42501'; end if;
  if (select choice from public.consents where user_id=u order by decided_at desc limit 1) is distinct from 'granted'
    then raise exception 'CONSENT_REQUIRED' using errcode='42501'; end if;
  if p_domain is null or p_status is null or p_domain not in ('origin','hrv','temperature','rr','sleep','oxygen','response') or p_status not in ('complete','not_collected','unsupported','failed','partial')
    or p_device_key is null or length(p_device_key) not between 1 and 200
    or p_mapping_version is null or length(p_mapping_version) not between 1 and 80
    or (p_observed_at is not null and (not isfinite(p_observed_at) or p_observed_at>now()+interval '5 minutes'))
    or p_day is null or p_start is null or p_end is null or not isfinite(p_start) or not isfinite(p_end) or p_end<=p_start
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
      if jsonb_typeof(s) is distinct from 'object' or t is null or not isfinite(t)
        or t<p_start or t>=p_end or t>now()+interval '5 minutes'
        or (p_observed_at is not null and t>p_observed_at+interval '5 minutes') then
        rejected:=rejected+1; continue;
      end if;
      observation_at:=p_observed_at;
      if p_domain='origin' then
        -- Origin is a completed SDK snapshot. Per-row read time is more precise
        -- than the batch start and remains attached to queued historical pages.
        observation_at:=coalesce((s->>'origin_read_at')::timestamptz,p_observed_at);
        if t+interval '5 minutes'>now()
          or (s ? 'user_id' and s->>'user_id' is distinct from u::text)
          or (observation_at is not null and (not isfinite(observation_at)
            or observation_at>now() or observation_at<t+interval '5 minutes')) then
          rejected:=rejected+1; continue;
        end if;
      end if;
      if p_domain='rr' then
        if jsonb_typeof(s->'rr_ms') is distinct from 'array' then rejected:=rejected+1; continue; end if;
        select array_agg(value::real order by ordinal) into rrs
          from jsonb_array_elements_text(s->'rr_ms') with ordinality e(value,ordinal);
        if cardinality(rrs) is null or cardinality(rrs) not between 1 and 4096
          or exists(select 1 from unnest(rrs) x where x is null or x<250 or x>2500 or x='NaN'::real) then
          rejected:=rejected+1; continue;
        end if;
        if s ? 'rr_indices' and s->'rr_indices'<>'null'::jsonb then
          if jsonb_typeof(s->'rr_indices') is distinct from 'array' then rejected:=rejected+1; continue; end if;
          select array_agg(value::integer order by ordinal) into indices
            from jsonb_array_elements_text(s->'rr_indices') with ordinality e(value,ordinal);
          if indices is null or not nb.valid_rr_indices(indices,cardinality(rrs)) then rejected:=rejected+1; continue; end if;
        else
          -- Keep NULL on disk for old payloads/archives: original gaps are unknown.
          indices:=null;
        end if;
        select * into rr_old from public.band_rr_evidence
          where user_id=u and device_key=p_device_key and ts=t and mapping_version=p_mapping_version for update;
        if not found then
          insert into public.band_rr_evidence(user_id,device_key,ts,mapping_version,rr_ms,sampled_tz,rr_indices,observed_at)
            values(u,p_device_key,t,p_mapping_version,rrs,p_timezone,indices,p_observed_at);
          inserted:=inserted+1;
        elsif rr_old.rr_ms=rrs and rr_old.rr_indices is not distinct from indices then
          unchanged:=unchanged+1;
        else
          -- An extension retains every old (original index, RR) fact. Conflicting
          -- revisions need a new mapper version; never erase earlier RR evidence.
          previous_indices:=coalesce(rr_old.rr_indices,array(select generate_series(0,cardinality(rr_old.rr_ms)-1)));
          indices:=coalesce(indices,array(select generate_series(0,cardinality(rrs)-1)));
          if cardinality(rrs)>cardinality(rr_old.rr_ms)
            and p_observed_at is not null
            and (rr_old.observed_at is null or p_observed_at>rr_old.observed_at)
            and rr_old.sampled_tz=p_timezone
            and not exists(select * from unnest(previous_indices,rr_old.rr_ms)
              except select * from unnest(indices,rrs)) then
            update public.band_rr_evidence set rr_ms=rrs,rr_indices=indices,observed_at=p_observed_at
              where user_id=u and device_key=p_device_key and ts=t and mapping_version=p_mapping_version;
            completed:=completed+1;
          elsif cardinality(rrs)<=cardinality(rr_old.rr_ms)
            and not exists(select * from unnest(indices,rrs)
              except select * from unnest(previous_indices,rr_old.rr_ms)) then
            unchanged:=unchanged+1;
          else rejected:=rejected+1; end if;
        end if;
        continue;
      end if;
      if p_domain='oxygen' then
        v_spo2:=(s->>'spo2')::smallint;
        if v_spo2 is null or v_spo2 not between 50 and 100 then rejected:=rejected+1; continue; end if;
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
      invalidate_hrv:=p_domain='hrv' and s->'hrv_valid'='false'::jsonb;
      if coalesce(invalidate_hrv,false) and (p_mapping_version<>'veepoo-rmssd-v2'
        or p_observed_at is null or variability is not null
        or s->>'hrv_invalid_reason' is distinct from 'insufficient_adjacent_rr') then
        rejected:=rejected+1; continue;
      end if;
      if h not between 1 and 250 or steps<0 or calories<0 or distance<0 or metabolic not between 0 and 100
        or pressure not between 0 and 100 or stage not between 0 and 4
        or temperature not between 10 and 50 or variability not between 1 and 300
        or (coalesce(h::text,steps::text,calories::text,distance::text,metabolic::text,pressure::text,stage::text,temperature::text,variability::text) is null and not coalesce(invalidate_hrv,false)) then
          rejected:=rejected+1; continue;
      end if;
      candidate:=jsonb_strip_nulls(jsonb_build_object('heart',h,'step',steps,'cal',calories,'dis',distance,
        'met',metabolic,'temp',temperature,'hrv',variability,'stress',pressure,'sleep_states',stage));
      -- Compare the same stored precision on retries (e.g. numeric(4,2) MET).
      candidate:=jsonb_strip_nulls(to_jsonb(jsonb_populate_record(null::public.raw_samples,candidate)));
      if coalesce(invalidate_hrv,false) then candidate:=jsonb_build_object('hrv',null); end if;
      select * into old from public.raw_samples where user_id=u and ts=t and src='band' for update;
      if not found then
        field_sources:='{}';
        for field_name in select jsonb_object_keys(candidate) loop
          field_sources:=field_sources || jsonb_build_object(field_name,jsonb_strip_nulls(jsonb_build_object(
            'device_key',p_device_key,'mapping_version',p_mapping_version,'observed_at',observation_at,'received_at',now(),
            'invalid_reason',case when coalesce(invalidate_hrv,false) then 'insufficient_adjacent_rr' end)));
        end loop;
        insert into public.raw_samples(user_id,ts,src,sampled_tz,heart,step,cal,dis,met,temp,hrv,stress,sleep_states,ingestion_device_key,mapping_version,domain_sources)
          values(u,t,'band',p_timezone,h,steps,calories,distance,metabolic,temperature,variability,pressure,stage,p_device_key,p_mapping_version,
            jsonb_build_object(p_domain,jsonb_build_object('fields',field_sources) ||
              case when p_domain='origin' then jsonb_strip_nulls(jsonb_build_object('device_key',p_device_key,
                'mapping_version',p_mapping_version,'read_at',observation_at,'received_at',now())) else '{}'::jsonb end ||
              case when p_domain='hrv' then jsonb_strip_nulls(jsonb_build_object('hrv_valid',variability is not null,
                'observed_at',observation_at,'invalid_reason',case when coalesce(invalidate_hrv,false) then 'insufficient_adjacent_rr' end))
              else '{}'::jsonb end));
        inserted:=inserted+1; changed:=true;
      else
        domain_meta:=coalesce(old.domain_sources->p_domain,'{}');
        if coalesce(domain_meta->>'device_key',old.ingestion_device_key) is not null
          and coalesce(domain_meta->>'device_key',old.ingestion_device_key)<>p_device_key then
          rejected:=rejected+1; continue;
        end if;
        if p_domain='origin' then
          origin_owner:=coalesce(domain_meta->>'device_key',old.ingestion_device_key);
          origin_mapping:=coalesce(domain_meta->>'mapping_version',old.mapping_version);
          old_origin_time:=coalesce((domain_meta->>'read_at')::timestamptz,
            (domain_meta->>'observed_at')::timestamptz,
            (select max((e.value->>'observed_at')::timestamptz) from jsonb_each(coalesce(domain_meta->'fields','{}')) e));
          if domain_meta<>'{}' and (origin_owner is distinct from p_device_key
            or origin_mapping is distinct from p_mapping_version or old.sampled_tz<>p_timezone) then
            rejected:=rejected+1; continue;
          end if;
          if observation_at is not null and domain_meta='{}'
            and coalesce(old.heart::text,old.step::text,old.cal::text,old.dis::text,old.met::text,
              old.stress::text,old.sleep_states::text) is not null then
            rejected:=rejected+1; continue;
          end if;
          -- A full origin snapshot supersedes its entire earlier snapshot. In
          -- contrast, independent HRV/temperature streams merge per field below.
          if old_origin_time is not null and (observation_at is null or observation_at<old_origin_time) then
            unchanged:=unchanged+1; continue;
          end if;
          if old_origin_time is not null and observation_at=old_origin_time
            and exists(select 1 from jsonb_each(candidate) e where e.value is distinct from to_jsonb(old)->e.key) then
            rejected:=rejected+1; continue;
          end if;
        end if;
        merged:=to_jsonb(old); field_sources:=coalesce(domain_meta->'fields','{}');
        domain_fields:=case p_domain when 'origin' then array['heart','step','cal','dis','met','stress','sleep_states']
          when 'hrv' then array['hrv'] else array['temp'] end;
        -- Materialize the provenance of existing fields before filling any gaps.
        -- Unknown legacy measurements must not acquire ownership from a new field.
        foreach field_name in array domain_fields loop
          if merged->field_name is distinct from 'null'::jsonb and not field_sources ? field_name then
            field_sources:=field_sources || jsonb_build_object(field_name,domain_meta-'fields');
          end if;
        end loop;
        changed:=false; metadata_changed:=false; conflict_found:=false;
        for field_name,field_value in select key,value from jsonb_each(candidate) loop
          prior_source:=coalesce(field_sources->field_name,'{}');
          prior_time:=coalesce((prior_source->>'observed_at')::timestamptz,(prior_source->>'read_at')::timestamptz);
          same_source:=prior_source->>'device_key'=p_device_key;
          can_replace:=coalesce(same_source,false) and observation_at is not null
            and (prior_time is null or observation_at>prior_time)
            and (prior_source->>'mapping_version'=p_mapping_version
              or (prior_source->>'mapping_version'='veepoo-rmssd-v1' and p_mapping_version='veepoo-rmssd-v2'));
          if (merged->field_name='null'::jsonb and not prior_source ? 'invalid_reason') or can_replace then
            changed:=changed or merged->field_name is distinct from field_value;
            merged:=jsonb_set(merged,array[field_name],field_value);
            next_source:=jsonb_strip_nulls(jsonb_build_object('device_key',p_device_key,
              'mapping_version',p_mapping_version,'observed_at',observation_at,'received_at',now(),
              'invalid_reason',case when coalesce(invalidate_hrv,false) then 'insufficient_adjacent_rr' end));
            field_sources:=field_sources || jsonb_build_object(field_name,next_source);
            metadata_changed:=true;
          elsif coalesce(same_source,false) and observation_at=prior_time
            and merged->field_name is distinct from field_value then
            conflict_found:=true;
          end if;
        end loop;
        if conflict_found then rejected:=rejected+1; continue; end if;
        if changed or metadata_changed then
          if p_domain='origin' and changed and observation_at is not null then
            select coalesce(jsonb_object_agg(e.key,jsonb_build_object('before',to_jsonb(old)->e.key,'after',e.value)),'{}')
              into origin_delta from jsonb_each(merged) e
              where e.key=any(domain_fields) and e.value is distinct from to_jsonb(old)->e.key;
            insert into public.band_origin_corrections(user_id,device_key,ts,mapping_version,previous_read_at,read_at,changes)
              values(u,p_device_key,t,p_mapping_version,old_origin_time,observation_at,origin_delta);
          end if;
          update public.raw_samples set heart=(merged->>'heart')::smallint,step=(merged->>'step')::integer,
            cal=(merged->>'cal')::integer,dis=(merged->>'dis')::integer,met=(merged->>'met')::numeric,
            temp=(merged->>'temp')::numeric,hrv=(merged->>'hrv')::numeric,stress=(merged->>'stress')::smallint,
            sleep_states=(merged->>'sleep_states')::smallint,
            domain_sources=domain_sources || jsonb_build_object(p_domain,jsonb_build_object('fields',field_sources) ||
              case when p_domain='origin' then jsonb_strip_nulls(jsonb_build_object('device_key',p_device_key,
                'mapping_version',p_mapping_version,'read_at',observation_at,'received_at',now())) else '{}'::jsonb end ||
              case when p_domain='hrv' then jsonb_strip_nulls(jsonb_build_object('hrv_valid',merged->'hrv'<>'null'::jsonb,
                'observed_at',field_sources->'hrv'->'observed_at','invalid_reason',field_sources->'hrv'->'invalid_reason'))
              else '{}'::jsonb end)
            where user_id=u and ts=t and src='band';
          -- A newer equal measurement still advances its source clock so a delayed
          -- intermediate read cannot overwrite it. This is a new evidence revision.
          if changed then completed:=completed+1; else unchanged:=unchanged+1; end if;
          changed:=true;
        else unchanged:=unchanged+1; end if;
      end if;
      if changed then affected:=array_append(affected,((t at time zone coalesce(old.sampled_tz,p_timezone))-interval '4 hours')::date); end if;
    exception when invalid_text_representation or numeric_value_out_of_range or datetime_field_overflow or invalid_parameter_value or check_violation then
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

revoke all on function public.ingest_band_domain(text,text,date,text,timestamptz,timestamptz,jsonb,text,text,timestamptz) from public,anon;
grant execute on function public.ingest_band_domain(text,text,date,text,timestamptz,timestamptz,jsonb,text,text,timestamptz) to authenticated;
