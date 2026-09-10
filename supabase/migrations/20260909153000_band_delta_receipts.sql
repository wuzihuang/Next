-- A receipt represents server-confirmed measured content, never an upload clock.
-- Reobserving unchanged content still enters the existing ingestor, so its ordered
-- source clocks, repair status, dirty revisions and midnight mapping are preserved.
-- No durable receipt table: eviction/archiving/correction makes a reference miss
-- and the client retries the complete batch. Older clients keep their original RPC.

create function nb.band_delta_sample(p_domain text,p_sample jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare r public.raw_samples%rowtype; values_rr real[]; indices integer[];
begin
  if p_domain='rr' then
    select array_agg(value::real order by ordinal) into values_rr
      from jsonb_array_elements_text(p_sample->'rr_ms') with ordinality e(value,ordinal);
    if p_sample->'rr_indices' is not null and p_sample->'rr_indices'<>'null'::jsonb then
      select array_agg(value::integer order by ordinal) into indices
        from jsonb_array_elements_text(p_sample->'rr_indices') with ordinality e(value,ordinal);
    end if;
    return jsonb_build_object('rr_ms',values_rr,'rr_indices',indices);
  end if;
  -- Use the table's actual typmods (including HRV's stored precision), not a
  -- second hard-coded rounding implementation in the client or receipt layer.
  if p_domain='origin' then
    r:=jsonb_populate_record(null::public.raw_samples,jsonb_build_object(
      'heart',(p_sample->>'heart')::smallint,'step',(p_sample->>'step')::integer,
      'cal',(p_sample->>'cal')::integer,'dis',(p_sample->>'dis')::integer,
      'met',(p_sample->>'met')::numeric,'stress',(p_sample->>'stress')::smallint,
      'sleep_states',(p_sample->>'sleep_states')::smallint));
    return jsonb_build_object('heart',r.heart,'step',r.step,'cal',r.cal,'dis',r.dis,
      'met',r.met,'stress',r.stress,'sleep_states',r.sleep_states);
  elsif p_domain='temperature' then
    r:=jsonb_populate_record(null::public.raw_samples,jsonb_build_object('temp',(p_sample->>'temp')::numeric));
    return jsonb_build_object('temp',r.temp);
  elsif p_domain='hrv' then
    r:=jsonb_populate_record(null::public.raw_samples,jsonb_build_object('hrv',(p_sample->>'hrv')::numeric));
    return jsonb_build_object('hrv',r.hrv,'hrv_valid',p_sample->'hrv_valid' is distinct from 'false'::jsonb,
      'hrv_invalid_reason',case when p_sample->'hrv_valid'='false'::jsonb then p_sample->>'hrv_invalid_reason' end);
  end if;
  return null;
end $$;

create function nb.band_delta_stored_sample(
  p_user uuid,p_device_key text,p_domain text,p_timezone text,p_mapping_version text,p_ts timestamptz
) returns jsonb language plpgsql stable set search_path='' as $$
declare r public.raw_samples%rowtype; rr public.band_rr_evidence%rowtype;
  meta jsonb; source jsonb; field_name text; fields text[];
begin
  if p_domain='rr' then
    select * into rr from public.band_rr_evidence where user_id=p_user and device_key=p_device_key
      and ts=p_ts and mapping_version=p_mapping_version and sampled_tz=p_timezone;
    if not found then return null; end if;
    return jsonb_build_object('rr_ms',rr.rr_ms,'rr_indices',rr.rr_indices);
  end if;
  -- Oxygen/response rows have no device/mapper ownership. Do not manufacture it
  -- from the request; these small payloads and sleep continue using full samples.
  if p_domain not in ('origin','hrv','temperature') then return null; end if;
  select * into r from public.raw_samples where user_id=p_user and ts=p_ts and src='band'
    and sampled_tz=p_timezone;
  if not found then return null; end if;
  meta:=r.domain_sources->p_domain;
  if meta is null then return null; end if;
  if p_domain='origin' then
    if meta->>'device_key' is distinct from p_device_key
      or meta->>'mapping_version' is distinct from p_mapping_version then return null; end if;
    fields:=array['heart','step','cal','dis','met','stress','sleep_states'];
  else fields:=case p_domain when 'hrv' then array['hrv'] else array['temp'] end;
  end if;
  foreach field_name in array fields loop
    -- Empty origin fields remain explicitly null in its canonical snapshot, but
    -- existing values (and HRV retractions) must each have compatible provenance.
    if p_domain='origin' and to_jsonb(r)->field_name='null'::jsonb then continue; end if;
    source:=coalesce(meta->'fields'->field_name,meta-'fields');
    if source->>'device_key' is distinct from p_device_key
      or source->>'mapping_version' is distinct from p_mapping_version then return null; end if;
  end loop;
  if p_domain='hrv' and r.hrv is null then
    if meta->'hrv_valid' is distinct from 'false'::jsonb
      or meta->>'invalid_reason' is distinct from 'insufficient_adjacent_rr'
      or source->>'invalid_reason' is distinct from 'insufficient_adjacent_rr' then return null; end if;
    return nb.band_delta_sample(p_domain,jsonb_build_object('hrv',null,'hrv_valid',false,
      'hrv_invalid_reason','insufficient_adjacent_rr'));
  end if;
  return nb.band_delta_sample(p_domain,to_jsonb(r));
end $$;

create function nb.band_delta_receipt(
  p_user uuid,p_device_key text,p_domain text,p_timezone text,p_mapping_version text,p_ts timestamptz,p_sample jsonb
) returns text language sql immutable set search_path='' as $$
  select encode(pg_catalog.sha256(convert_to(jsonb_build_object('version',1,'user_id',p_user,
    'device_key',p_device_key,'domain',p_domain,'timezone',p_timezone,'mapping_version',p_mapping_version,
    'ts',extract(epoch from p_ts),'sample',p_sample)::text,'UTF8')),'hex');
$$;

revoke all on function nb.band_delta_sample(text,jsonb),
  nb.band_delta_stored_sample(uuid,text,text,text,text,timestamptz),
  nb.band_delta_receipt(uuid,text,text,text,text,timestamptz,jsonb) from public,anon,authenticated;

-- Definer matches the existing bounded write boundary: table writes are private,
-- identity comes exclusively from auth.uid(), and helper functions stay private.
create function public.ingest_band_delta(
  p_device_key text,p_domain text,p_day date,p_timezone text,
  p_start timestamptz,p_end timestamptz,p_samples jsonb,
  p_status text default 'complete',p_mapping_version text default 'veepoo-rmssd-v1',
  p_observed_at timestamptz default null,p_receipts jsonb default '[]'
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  u uuid:=auth.uid(); s jsonb; t timestamptz; observation_at timestamptz;
  canonical jsonb; incoming jsonb; token text; missing jsonb:='[]'; receipts jsonb:='{}';
  expanded jsonb:='[]'; batch jsonb; ack jsonb; seen timestamptz[]:='{}';
  expanded_bytes integer; is_reference boolean;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  perform 1 from public.profiles where user_id=u for share;
  if exists(select 1 from public.profiles where user_id=u and deletion_requested_at is not null)
    then raise exception 'ACCOUNT_DELETING' using errcode='42501'; end if;
  if (select choice from public.consents where user_id=u order by decided_at desc limit 1) is distinct from 'granted'
    then raise exception 'CONSENT_REQUIRED' using errcode='42501'; end if;
  if p_domain is null or p_status is null or p_domain not in ('origin','hrv','temperature','rr','sleep','oxygen','response')
    or p_status not in ('complete','not_collected','unsupported','failed','partial')
    or p_device_key is null or length(p_device_key) not between 1 and 200
    or p_mapping_version is null or length(p_mapping_version) not between 1 and 80
    or (p_observed_at is not null and (not isfinite(p_observed_at) or p_observed_at>now()+interval '5 minutes'))
    or p_day is null or p_start is null or p_end is null or not isfinite(p_start) or not isfinite(p_end) or p_end<=p_start
    or p_end-p_start>interval '26 hours'
    or not exists(select 1 from pg_catalog.pg_timezone_names where name=p_timezone)
    or p_samples is null or jsonb_typeof(p_samples)<>'array'
    or p_receipts is null or jsonb_typeof(p_receipts)<>'array' then
    raise exception 'INVALID_DOMAIN_BATCH' using errcode='22023';
  end if;
  if jsonb_array_length(p_samples)+jsonb_array_length(p_receipts)>5000
    or octet_length(p_samples::text)+octet_length(p_receipts::text)>4000000 then
    raise exception 'INVALID_DOMAIN_BATCH' using errcode='22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text,74));
  expanded_bytes:=octet_length(p_samples::text);
  -- A batch must have one meaning per instant, including alternate timestamp
  -- spellings and collisions between full samples and compact references.
  for s,is_reference in
    select value,false from jsonb_array_elements(p_samples)
    union all select value,true from jsonb_array_elements(p_receipts)
  loop
    begin t:=(s->>'ts')::timestamptz;
    exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or invalid_parameter_value then
      if is_reference then raise exception 'INVALID_DOMAIN_BATCH' using errcode='22023'; end if;
      continue; -- The original ingestor reports malformed full samples individually.
    end;
    if t=any(seen) then raise exception 'DUPLICATE_DOMAIN_TIMESTAMP' using errcode='22023'; end if;
    if t is not null then seen:=array_append(seen,t); end if;
    if not is_reference then continue; end if;
    if jsonb_typeof(s) is distinct from 'object' or t is null or not isfinite(t)
      or t<p_start or t>=p_end or t>now()+interval '5 minutes'
      or (p_observed_at is not null and t>p_observed_at+interval '5 minutes')
      or jsonb_typeof(s->'receipt') is distinct from 'string'
      or s->>'receipt' !~ '^[0-9a-f]{64}$' then
      raise exception 'INVALID_DOMAIN_BATCH' using errcode='22023';
    end if;
    if p_domain='origin' then
      begin observation_at:=coalesce((s->>'origin_read_at')::timestamptz,p_observed_at);
      exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or invalid_parameter_value then
        raise exception 'INVALID_DOMAIN_BATCH' using errcode='22023';
      end;
      if t+interval '5 minutes'>now()
        or (observation_at is not null and (not isfinite(observation_at)
          or observation_at>now() or observation_at<t+interval '5 minutes')) then
        raise exception 'INVALID_DOMAIN_BATCH' using errcode='22023';
      end if;
    end if;
    canonical:=nb.band_delta_stored_sample(u,p_device_key,p_domain,p_timezone,p_mapping_version,t);
    token:=case when canonical is not null then
      nb.band_delta_receipt(u,p_device_key,p_domain,p_timezone,p_mapping_version,t,canonical) end;
    if token is null or token is distinct from s->>'receipt' then
      missing:=missing || jsonb_build_array(s->>'ts');
      continue;
    end if;
    incoming:=canonical || jsonb_build_object('ts',s->>'ts');
    if p_domain='origin' and s ? 'origin_read_at' then
      incoming:=incoming || jsonb_build_object('origin_read_at',s->'origin_read_at');
    end if;
    expanded_bytes:=expanded_bytes+octet_length(incoming::text)+2;
    if expanded_bytes>4000000 then raise exception 'INVALID_DOMAIN_BATCH' using errcode='22023'; end if;
    expanded:=expanded || jsonb_build_array(incoming);
  end loop;
  if jsonb_array_length(missing)>0 then
    -- Nothing in this batch (including new full samples or status) was ingested.
    return jsonb_build_object('inserted',0,'completed',0,'unchanged',0,'rejected',0,
      'affected_days','[]'::jsonb,'status','partial','receipts','{}'::jsonb,'needs_samples',missing);
  end if;
  batch:=p_samples || expanded;
  ack:=public.ingest_band_domain(p_device_key,p_domain,p_day,p_timezone,p_start,p_end,batch,
    p_status,p_mapping_version,p_observed_at);
  -- Counts alone cannot establish content equality: stale origin snapshots and
  -- RR subsets legitimately count as unchanged. Partial/rejected batches keep
  -- their normal retry behavior and conservatively receive no new receipts.
  if (ack->>'rejected')::integer=0 then
    -- Validated references already have a token. Echoing them in every response
    -- wastes most of their bandwidth savings; the client retains those receipts.
    for s in select value from jsonb_array_elements(p_samples) loop
      t:=(s->>'ts')::timestamptz;
      canonical:=nb.band_delta_stored_sample(u,p_device_key,p_domain,p_timezone,p_mapping_version,t);
      if canonical is null then continue; end if;
      incoming:=nb.band_delta_sample(p_domain,s);
      if incoming=canonical then
        token:=nb.band_delta_receipt(u,p_device_key,p_domain,p_timezone,p_mapping_version,t,canonical);
        incoming:=jsonb_build_object('ts',s->>'ts','receipt',token);
        if p_domain='origin' and s ? 'origin_read_at' then
          incoming:=incoming || jsonb_build_object('origin_read_at',s->'origin_read_at');
        end if;
        -- Scalar HRV/temperature can be smaller than a reference. Include room
        -- for the extra p_receipts array; mint only when compaction saves bytes.
        if octet_length(incoming::text)+24<octet_length(s::text) then
          receipts:=receipts || jsonb_build_object(s->>'ts',token);
        end if;
      end if;
    end loop;
  end if;
  return ack || jsonb_build_object('receipts',receipts,'needs_samples','[]'::jsonb);
end $$;

revoke all on function public.ingest_band_delta(text,text,date,text,timestamptz,timestamptz,jsonb,text,text,timestamptz,jsonb)
  from public,anon;
grant execute on function public.ingest_band_delta(text,text,date,text,timestamptz,timestamptz,jsonb,text,text,timestamptz,jsonb)
  to authenticated;
