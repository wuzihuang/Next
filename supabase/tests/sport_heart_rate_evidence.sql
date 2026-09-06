-- Run only in a disposable migrated database; all fixtures roll back.
begin;
insert into auth.users(id) values
  ('33333333-3333-4333-8333-333333333339'),('44444444-4444-4444-8444-444444444449');
insert into public.profiles(user_id,timezone) values
  ('33333333-3333-4333-8333-333333333339','UTC'),('44444444-4444-4444-8444-444444444449','UTC');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
  ('33333333-3333-4333-8333-333333333339','test','granted','test','en'),
  ('44444444-4444-4444-8444-444444444449','test','granted','test','en');
update nb.calculation_work set dirty_from=null where user_id='33333333-3333-4333-8333-333333333339';
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333339',true);
set local role authenticated;
do $$ declare result jsonb; batch jsonb:='[
 {"id":"55555555-5555-4555-8555-555555555550","session_id":"66666666-6666-4666-8666-666666666666","continuity_id":"77777777-7777-4777-8777-777777777777","observed_at":"2026-09-01T03:59:58.125Z","heart_rate":100,"sport_mode":1,"sampled_tz":"UTC","user_id":"44444444-4444-4444-8444-444444444449"},
 {"id":"55555555-5555-4555-8555-555555555551","session_id":"66666666-6666-4666-8666-666666666666","continuity_id":"77777777-7777-4777-8777-777777777777","observed_at":"2026-09-01T04:00:02.125Z","heart_rate":180,"sampled_tz":"UTC"}]';
begin
 result:=public.ingest_sport_heart_rate(batch);
 if result->>'inserted'<>'2' or jsonb_array_length(result->'acknowledged_ids')<>2 then
   raise exception 'batch not confirmed: %',result; end if;
 if exists(select 1 from public.sport_heart_rate_samples where user_id<>auth.uid()) then
   raise exception 'payload owner injection accepted'; end if;
 if not exists(select 1 from public.sport_heart_rate_samples where observed_at='2026-09-01T03:59:58.125Z'
   and heart_rate=100 and session_id='66666666-6666-4666-8666-666666666666'
   and continuity_id='77777777-7777-4777-8777-777777777777') then
   raise exception 'original timestamp or continuity lost'; end if;
 result:=public.ingest_sport_heart_rate(batch);
 if result->>'inserted'<>'0' or jsonb_array_length(result->'acknowledged_ids')<>2 then
   raise exception 'retry not idempotent: %',result; end if;
 begin
   perform public.ingest_sport_heart_rate(jsonb_set(batch,'{0,heart_rate}','130'));
   raise exception 'conflicting operation silently acknowledged';
 exception when unique_violation then null; end;
 begin
   perform public.ingest_sport_heart_rate(jsonb_set(batch,'{0,heart_rate}','251'));
   raise exception 'invalid HR accepted';
 exception when invalid_parameter_value then null; end;
 begin
   perform public.ingest_sport_heart_rate(jsonb_set(batch,'{0,sampled_tz}','"Not/A_Zone"'));
   raise exception 'invalid timezone accepted';
 exception when invalid_parameter_value then null; end;
 begin
   perform public.ingest_sport_heart_rate(jsonb_set(batch,'{0,observed_at}',to_jsonb((now()+interval '1 day')::text)));
   raise exception 'future observation accepted';
 exception when invalid_parameter_value then null; end;
 if jsonb_array_length(public.export_all()->'sport_heart_rate_samples')<>2 then
   raise exception 'compatibility export omitted observations'; end if;
end $$;
reset role;
do $$ begin
 if (select dirty_from from nb.calculation_work where user_id='33333333-3333-4333-8333-333333333339')<>'2026-08-31'::date then
   raise exception '04:00 lookbehind did not invalidate preceding user day'; end if;
 if (select input_revision from nb.calculation_work where user_id='33333333-3333-4333-8333-333333333339')<>2 then
   raise exception 'batch/retries invalidated more than once'; end if;
 if has_function_privilege('anon','public.ingest_sport_heart_rate(jsonb)','execute') then
   raise exception 'anonymous RPC exposure'; end if;
 if (select prosecdef from pg_proc where oid='public.ingest_sport_heart_rate(jsonb)'::regprocedure) then
   raise exception 'ingestion unexpectedly bypasses RLS'; end if;
end $$;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444449',true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.sport_heart_rate_samples)
   or jsonb_array_length(public.export_all()->'sport_heart_rate_samples')<>0 then
   raise exception 'cross-account export/read leak'; end if;
 begin
   insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sampled_tz)
     values('33333333-3333-4333-8333-333333333339',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),now(),100,'UTC');
   raise exception 'cross-account insert accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
insert into public.consents(user_id,consent_version,choice,text_sha256,locale,decided_at)
values('33333333-3333-4333-8333-333333333339','test','withdrawn','test','en',now()+interval '1 second');
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333339',true);
set local role authenticated;
do $$ begin
 begin
   perform public.ingest_sport_heart_rate('[]');
   raise exception 'withdrawn consent accepted ingestion';
 exception when insufficient_privilege then null; end;
 if jsonb_array_length(public.export_all()->'sport_heart_rate_samples')<>2 then
   raise exception 'withdrawal incorrectly removed export access'; end if;
end $$;
reset role;
update public.profiles set deletion_requested_at=now() where user_id='33333333-3333-4333-8333-333333333339';
set local role authenticated;
do $$ begin
 begin
   perform public.ingest_sport_heart_rate('[]');
   raise exception 'deleting account accepted ingestion';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
delete from auth.users where id='33333333-3333-4333-8333-333333333339';
do $$ begin
 if exists(select 1 from public.sport_heart_rate_samples where user_id='33333333-3333-4333-8333-333333333339') then
   raise exception 'deleted account retained sport observations'; end if;
end $$;
rollback;
