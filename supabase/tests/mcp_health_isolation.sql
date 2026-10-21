begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id) values
  ('ac200000-0000-4000-8000-000000000001'),
  ('ac200000-0000-4000-8000-000000000002');
insert into public.profiles(user_id,timezone,height_cm) values
  ('ac200000-0000-4000-8000-000000000001','UTC',170),
  ('ac200000-0000-4000-8000-000000000002','UTC',190)
on conflict(user_id) do update set height_cm=excluded.height_cm;
insert into public.mcp_grants(user_id,client_id,can_write) values
  ('ac200000-0000-4000-8000-000000000001','review',false),
  ('ac200000-0000-4000-8000-000000000002','review',false);
insert into public.raw_samples(user_id,ts,sampled_tz,heart,src) values
  ('ac200000-0000-4000-8000-000000000001',now(),'UTC',72,'band');
insert into public.response_samples(user_id,ts,optical,sampled_tz) values
  ('ac200000-0000-4000-8000-000000000001',now(),23,'UTC');
insert into public.body_composition(user_id,measured_at,user_day,measurement_source,input_weight_kg,muscle_mass_kg) values
  ('ac200000-0000-4000-8000-000000000001',now(),current_date,'device_bia',70,30);
insert into public.balance_checks(user_id,measured_at,user_day,lead,rest_share,sd1_ms,sd2_ms,sdnn_ms,beat_count,client_op_id) values
  ('ac200000-0000-4000-8000-000000000001',now(),current_date,'even',50,25,25,30,20,gen_random_uuid());
insert into public.sport_session_recaps(user_id,id,started_at,ended_at,payload) values
  ('ac200000-0000-4000-8000-000000000001',gen_random_uuid(),now()-interval '1 hour',now(),'{}');
insert into public.manual_sport_sessions(user_id,id,user_day,started_at,ended_at,timezone,request_payload) values
  ('ac200000-0000-4000-8000-000000000001',gen_random_uuid(),current_date,now()-interval '1 hour',now(),'UTC','{}');
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sampled_tz) values
  ('ac200000-0000-4000-8000-000000000001',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),now(),100,'UTC');
insert into public.sport_energy_samples(user_id,id,session_id,continuity_id,observed_at,sport_mode,sampled_tz) values
  ('ac200000-0000-4000-8000-000000000001',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),now(),25,'UTC');
insert into public.reserve_samples(user_id,ts,value) values
  ('ac200000-0000-4000-8000-000000000001',now(),55);
insert into public.night_hrv(user_id,user_day,rmssd_ms,bucket_count,sampled_tz,source) values
  ('ac200000-0000-4000-8000-000000000001',current_date,40,3,'UTC','band_rr');

create function pg_temp.check_health_reads() returns setof text language plpgsql as $$
declare t text;
begin
  foreach t in array array['raw_samples','response_samples','body_composition','balance_checks',
    'sport_session_recaps','manual_sport_sessions','sport_heart_rate_samples',
    'sport_energy_samples','reserve_samples','night_hrv'] loop
    perform set_config('request.path','/'||t,true);
    perform set_config('request.method','GET',true);
    return next lives_ok('select public.mcp_request_gate()',t||' is readable through the OAuth gate');
    return query execute format('select is((select count(*)::int from public.%I),%s,%L)',t,
      case when auth.uid()='ac200000-0000-4000-8000-000000000001'::uuid then 1 else 0 end,
      t||' returns only owner rows');
    perform set_config('request.method','POST',true);
    return next throws_ok('select public.mcp_request_gate()','42501','MCP_PATH_NOT_ALLOWED',t||' cannot be written by OAuth');
  end loop;
end $$;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"ac200000-0000-4000-8000-000000000001","role":"authenticated","client_id":"review"}',true);
select * from pg_temp.check_health_reads();
select is(public.mcp_health_profile()->>'heightCm','170.0','profile belongs to first owner');
select set_config('request.jwt.claims',
  '{"sub":"ac200000-0000-4000-8000-000000000002","role":"authenticated","client_id":"review"}',true);
select * from pg_temp.check_health_reads();
select is(public.mcp_health_profile()->>'heightCm','190.0','profile belongs to second owner');
select ok(not (public.mcp_health_profile() ?| array['user_id','email','deletion_requested_at','field_sources']),
  'health profile excludes account and administration fields');
select set_config('request.method','GET',true);
select set_config('request.path','/profiles',true);
select throws_ok('select public.mcp_request_gate()','42501','MCP_PATH_NOT_ALLOWED','raw profile and its foreign-key relationships stay closed');
select set_config('request.path','/rpc/log_mcp_meal',true);
select set_config('request.method','POST',true);
select throws_ok('select public.mcp_request_gate()','42501','MCP_WRITE_NOT_GRANTED','new writer requires explicit permission');
reset role;
select * from finish();
rollback;
