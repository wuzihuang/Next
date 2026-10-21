begin;
select plan(20);

insert into auth.users(id) values
  ('aaaaaaaa-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-000000000002');
insert into public.profiles(user_id,timezone,birth_date) values
  ('aaaaaaaa-0000-4000-8000-000000000001','UTC','1990-01-01'),
  ('aaaaaaaa-0000-4000-8000-000000000002','UTC','1990-01-01');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
  ('aaaaaaaa-0000-4000-8000-000000000001','test','granted','test','en'),
  ('aaaaaaaa-0000-4000-8000-000000000002','test','granted','test','en');

create function pg_temp.bundle_domain(
  p_domain text,p_ts text,p_status text default 'complete',p_receipts jsonb default '[]'::jsonb
) returns jsonb language sql as $$
  select jsonb_build_object(
    'p_device_key','bundle-band',
    'p_domain',p_domain,
    'p_day','2026-09-01',
    'p_timezone','UTC',
    'p_start','2026-09-01T00:00:00Z',
    'p_end','2026-09-02T00:00:00Z',
    'p_observed_at','2026-09-02T12:00:00Z',
    'p_mapping_version',case when p_domain='origin' then 'veepoo-rmssd-v1' else 'veepoo-rmssd-v2' end,
    'p_status',p_status,
    'p_samples',case p_domain
      when 'origin' then jsonb_build_array(jsonb_build_object(
        'ts',p_ts,'heart',70,'step',10,'user_id',auth.uid(),'src','band','sampled_tz','UTC'))
      when 'hrv' then jsonb_build_array(jsonb_build_object('ts',p_ts,'hrv',42))
      when 'temperature' then jsonb_build_array(jsonb_build_object('ts',p_ts,'temp',36.5))
      else '[]'::jsonb end,
    'p_receipts',p_receipts
  );
$$;

create function pg_temp.bundle_delta(p jsonb) returns jsonb language sql as $$
  select public.ingest_band_delta(
    p->>'p_device_key',p->>'p_domain',(p->>'p_day')::date,p->>'p_timezone',
    (p->>'p_start')::timestamptz,(p->>'p_end')::timestamptz,p->'p_samples',
    p->>'p_status',p->>'p_mapping_version',(p->>'p_observed_at')::timestamptz,p->'p_receipts');
$$;

create function pg_temp.bundle_cron_command_ok() returns boolean language plpgsql as $$
declare valid boolean;
begin
  if to_regclass('cron.job') is null then return true; end if;
  execute 'select exists(select 1 from cron.job where jobname=''nb-settle'' and trim(command)=''call nb.settle_accounts(2)'')'
    into valid;
  return valid;
end $$;

select set_config('request.jwt.claim.sub','aaaaaaaa-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('bundle.first',public.ingest_band_bundle(
  jsonb_build_array(
    pg_temp.bundle_domain('origin','2026-09-01T01:00:00Z'),
    pg_temp.bundle_domain('hrv','2026-09-01T02:00:00Z'),
    pg_temp.bundle_domain('sleep','2026-09-01T04:00:00Z','pending_sleep')),
  jsonb_build_object('user_id',auth.uid(),'user_day','2026-09-01','device_key','bundle-band',
    'total_minutes',420,'deep_minutes',120,'light_minutes',300,'wake_count',0,
    'sleep_line','0:120,1:300','raw','{}'::jsonb))::text,true);

select set_config('request.jwt.claim.sub','aaaaaaaa-0000-4000-8000-000000000002',true);
select set_config('bundle.direct',(
  select jsonb_build_object('results',jsonb_build_array(
    pg_temp.bundle_delta(pg_temp.bundle_domain('origin','2026-09-01T01:00:00Z')),
    pg_temp.bundle_delta(pg_temp.bundle_domain('hrv','2026-09-01T02:00:00Z')),
    pg_temp.bundle_delta(pg_temp.bundle_domain('sleep','2026-09-01T04:00:00Z','complete'))),
    'sleep',public.publish_sleep_night(jsonb_build_object(
    'user_id',auth.uid(),'user_day','2026-09-01','device_key','bundle-band',
    'total_minutes',420,'deep_minutes',120,'light_minutes',300,'wake_count',0,
    'sleep_line','0:120,1:300','raw','{}'::jsonb))))::text,true);
reset role;

select is(jsonb_array_length(current_setting('bundle.first')::jsonb->'results'),3,
  'a sleep row and three ordered domain results are returned');
select is(
  (current_setting('bundle.first')::jsonb->'sleep'->'ok'->0)-'user_id',
  (current_setting('bundle.direct')::jsonb->'sleep'->0)-'user_id',
  'the bundled sleep acknowledgment matches the direct publisher');
select is((current_setting('bundle.first')::jsonb->'results'->0->'ok')-'receipts',
  (current_setting('bundle.direct')::jsonb->'results'->0)-'receipts',
  'the bundled origin acknowledgment matches apart from account-scoped receipts');
select is(current_setting('bundle.first')::jsonb->'results'->1->'ok',
  current_setting('bundle.direct')::jsonb->'results'->1,'the bundled HRV acknowledgment matches');
select is(current_setting('bundle.first')::jsonb->'results'->2->'ok'->>'status',
  'complete','pending_sleep is stored with complete status after sleep succeeds');
select is((select status from public.sync_domain_status
  where user_id='aaaaaaaa-0000-4000-8000-000000000001'
    and device_key='bundle-band' and user_day='2026-09-01' and domain='sleep'),
  'complete','the persisted sleep domain status is complete');
select is(
  (select samples from (select r.user_id,jsonb_agg(to_jsonb(r)-'user_id' order by r.ts) samples
    from public.raw_samples r group by r.user_id) domain_rows
    where user_id='aaaaaaaa-0000-4000-8000-000000000001'),
  (select samples from (select r.user_id,jsonb_agg(to_jsonb(r)-'user_id' order by r.ts) samples
    from public.raw_samples r group by r.user_id) domain_rows
    where user_id='aaaaaaaa-0000-4000-8000-000000000002'),
  'the bundled rows match the individual domain rows');
select is(
  (select to_jsonb(s)-'user_id' from public.sleep_nights s
    where s.user_id='aaaaaaaa-0000-4000-8000-000000000001'),
  (select to_jsonb(s)-'user_id' from public.sleep_nights s
    where s.user_id='aaaaaaaa-0000-4000-8000-000000000002'),
  'the bundled sleep row matches the direct sleep row');

select set_config('request.jwt.claim.sub','aaaaaaaa-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('bundle.invalid',public.ingest_band_bundle(jsonb_build_array(
  pg_temp.bundle_domain('hrv','2026-09-01T05:00:00Z'),
  jsonb_set(pg_temp.bundle_domain('hrv','2026-09-01T06:00:00Z'),'{p_domain}','"invalid"'),
  pg_temp.bundle_domain('temperature','2026-09-01T07:00:00Z')),null)::text,true);
select is(current_setting('bundle.invalid')::jsonb->'results'->1->'error'->>'code','22023',
  'one invalid domain is isolated with SQLSTATE 22023');
select is((select count(*)::integer from public.raw_samples where user_id=auth.uid()
  and ts in ('2026-09-01T05:00:00Z','2026-09-01T07:00:00Z')),2,
  'valid domains persist around the isolated invalid entry');

select set_config('bundle.stale',public.ingest_band_bundle(jsonb_build_array(
  jsonb_set(pg_temp.bundle_domain('origin','2026-09-01T01:00:00Z','complete',
    jsonb_build_array(jsonb_build_object('ts','2026-09-01T01:00:00Z','receipt',repeat('0',64)))),
    '{p_samples}','[]'::jsonb),
  pg_temp.bundle_domain('hrv','2026-09-01T08:00:00Z')),null)::text,true);
select is(current_setting('bundle.stale')::jsonb->'results'->0->'ok'->'needs_samples',
  '["2026-09-01T01:00:00Z"]'::jsonb,'a stale receipt asks only its domain for full samples');
select is(current_setting('bundle.stale')::jsonb->'results'->1->'ok'->>'inserted','1',
  'another domain ingests while a receipt is stale');

select set_config('bundle.budget',public.ingest_band_bundle(jsonb_build_array(
  pg_temp.bundle_domain('hrv','2026-09-01T09:00:00Z'),
  pg_temp.bundle_domain('hrv','2026-09-01T10:00:00Z'),
  pg_temp.bundle_domain('hrv','2026-09-01T11:00:00Z')),null,0)::text,true);
select is(current_setting('bundle.budget')::jsonb->'results'->0->'ok'->>'inserted','1',
  'a zero budget still processes the first domain');
select is(current_setting('bundle.budget')::jsonb->'results'->1,
  '{"deferred":true}'::jsonb,'the zero budget defers later domains');

select set_config('bundle.sleep_error',public.ingest_band_bundle(jsonb_build_array(
  pg_temp.bundle_domain('sleep','2026-09-01T12:00:00Z','pending_sleep')),
  jsonb_build_object('user_id','aaaaaaaa-0000-4000-8000-000000000002',
    'user_day','2026-09-01','total_minutes',420,'deep_minutes',120,'light_minutes',300,
    'wake_count',0,'sleep_line','0:120,1:300','raw','{}'::jsonb))::text,true);
select is(current_setting('bundle.sleep_error')::jsonb->'results'->0->'ok'->>'status',
  'failed','pending_sleep is stored as failed when the sleep publication errors');
select is((select status from public.sync_domain_status
  where user_id='aaaaaaaa-0000-4000-8000-000000000001'
    and device_key='bundle-band' and user_day='2026-09-01' and domain='sleep'),
  'failed','the persisted sleep domain status follows the sleep error');
reset role;

select ok(not has_function_privilege('anon',
  'public.ingest_band_bundle(jsonb,jsonb,integer)','EXECUTE'),
  'anon cannot execute ingest_band_bundle');
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('bundle.settle',public.settle_now(0)::text,true);
reset role;
select ok(current_setting('bundle.settle')::integer>=0,'settle_now returns a nonnegative result when not busy');
select ok(pg_temp.bundle_cron_command_ok(),
  'nb-settle schedules only the top-level settle_accounts call');

insert into public.mcp_grants(user_id,client_id,client_name,can_write)
values('aaaaaaaa-0000-4000-8000-000000000001','bundle-test','Bundle test',true);
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated","client_id":"bundle-test"}',true);
select set_config('request.method','POST',true);
select set_config('request.path','/rpc/ingest_band_bundle',true);
select throws_ok($$select public.mcp_request_gate()$$,'42501','MCP_PATH_NOT_ALLOWED',
  'the MCP gate refuses the new upload RPC');

select * from finish();
rollback;
