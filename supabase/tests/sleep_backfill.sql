begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id) values
 ('20200920-0000-4000-8000-000000000001'),('20200920-0000-4000-8000-000000000002');
insert into public.profiles(user_id,timezone,birth_date) values
 ('20200920-0000-4000-8000-000000000001','UTC','1990-01-01'),
 ('20200920-0000-4000-8000-000000000002','America/New_York','1990-01-01');
insert into public.consents(user_id,consent_version,choice,decided_at,text_sha256,locale)
select id,'v1','granted','2026-09-01','sha','zh-CN' from auth.users
where id in ('20200920-0000-4000-8000-000000000001','20200920-0000-4000-8000-000000000002');
select set_config('nb.calculation_as_of','2026-09-20 12:00+00',true);
select set_config('nb.calculation_day','2026-09-20',true);
select set_config('request.jwt.claim.sub','20200920-0000-4000-8000-000000000001',true);
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv) values
 ('20200920-0000-4000-8000-000000000001','2026-09-19 22:30+00','UTC',58,35),
 ('20200920-0000-4000-8000-000000000001','2026-09-19 23:00+00','UTC',60,40),
 ('20200920-0000-4000-8000-000000000001','2026-09-19 23:30+00','UTC',62,45),
 ('20200920-0000-4000-8000-000000000002','2026-09-19 23:00+00','UTC',99,99);
select lives_ok($$select public.create_sleep_window('2026-09-20','22:00','07:00')$$,'a missing night can be reported');
select lives_ok($$select public.create_sleep_window('2026-09-20','22:00','07:00')$$,'same-window creation is idempotent');
select is((select count(*) from public.sleep_nights where user_id='20200920-0000-4000-8000-000000000001'),1::bigint,'retry creates one row');
select results_eq($$select total_minutes,deep_minutes,light_minutes,wake_count,raw->>'source'
 from public.sleep_nights where user_id='20200920-0000-4000-8000-000000000001'$$,
 $$select 540::smallint,null::smallint,null::smallint,null::smallint,'user_reported'::text$$,'reported duration has unknown architecture');
select is((select count(*) from nb.sleep_evidence_minutes('20200920-0000-4000-8000-000000000001','2026-09-20')),0::bigint,'manual duration never becomes measured light sleep');
select is((select count(*) from nb.sleep_observations('20200920-0000-4000-8000-000000000001','2026-09-20','rhr')),3::bigint,'manual night recovers actual heart samples with account isolation');
select is((select count(*) from nb.sleep_observations('20200920-0000-4000-8000-000000000001','2026-09-20','hrv')),3::bigint,'manual night recovers actual HRV');
select is((select architecture_score from nb.night_score_parts('20200920-0000-4000-8000-000000000001','2026-09-20')),null::numeric,'unknown stages cannot produce architecture score');
select is((select inputs->>'duration_basis' from nb.night_score_parts('20200920-0000-4000-8000-000000000001','2026-09-20')),'user_reported','score labels reported duration');
select throws_ok($$select public.create_sleep_window('2026-09-20','23:00','07:00')$$,'23505','SLEEP_NIGHT_EXISTS','creation never overwrites another window');
select lives_ok($$select public.correct_sleep_window('2026-09-20','23:00','07:00')$$,'reported night can be corrected');
select is((select total_minutes from public.sleep_nights where user_id='20200920-0000-4000-8000-000000000001'),480::smallint,'reported duration follows correction');
select lives_ok($$select public.clear_sleep_correction('2026-09-20')$$,'clear restores reported original');
select is((select total_minutes from public.sleep_nights where user_id='20200920-0000-4000-8000-000000000001'),540::smallint,'original reported duration restored');

-- A sparse band night: all stages have original offsets, physiology has exact native
-- points and explicitly revoked minutes. The expanded edges also contain coarse data.
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,wake_count,sleep_start,wake_at,raw)
values ('20200920-0000-4000-8000-000000000001','2026-09-19',60,30,30,0,'2026-09-18 23:00+00','2026-09-19 00:00+00',
 '{"intervals":[{"start":"2026-09-18T23:00:00Z","end":"2026-09-19T00:00:00Z"}],"line":[{"stage":0,"minutes":30,"offset_minutes":0},{"stage":1,"minutes":30,"offset_minutes":30}],"hrv":[{"ts":"2026-09-18T23:00:00Z","rmssd_ms":50}],"hrv_invalidated":[{"ts":"2026-09-18T23:30:00Z","observed_at":"2026-09-19T00:01:00Z"}]}'::jsonb);
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv) values
 ('20200920-0000-4000-8000-000000000001','2026-09-18 22:30+00','UTC',58,35),
 ('20200920-0000-4000-8000-000000000001','2026-09-18 23:00+00','UTC',60,99),
 ('20200920-0000-4000-8000-000000000001','2026-09-18 23:15+00','UTC',61,40),
 ('20200920-0000-4000-8000-000000000001','2026-09-18 23:30+00','UTC',62,45);
select throws_ok($$select public.create_sleep_window('2026-09-19','23:00','00:00')$$,'23505','SLEEP_NIGHT_EXISTS','creation cannot overwrite measured night even with same window');
select lives_ok($$select public.correct_sleep_window('2026-09-19','22:00','01:00')$$,'a band window can expand to recover available observations');
select is((select count(*) from nb.sleep_observations('20200920-0000-4000-8000-000000000001','2026-09-19','rhr')),4::bigint,'corrected physiology uses full new window');
select is((select count(*) from nb.sleep_observations('20200920-0000-4000-8000-000000000001','2026-09-19','hrv')),3::bigint,'HRV fills missing edges and minutes while excluding revoked minute');
select is((select v from nb.sleep_observations('20200920-0000-4000-8000-000000000001','2026-09-19','hrv') where ts='2026-09-18 23:00+00'),50::numeric,'native HRV wins over coarse sample in same minute');
select is((select count(*) from nb.sleep_evidence_minutes('20200920-0000-4000-8000-000000000001','2026-09-19')),60::bigint,'extension never manufactures stages');
select is((nb.sleep_window_receipt('20200920-0000-4000-8000-000000000001','2026-09-19')->>'unstaged_minutes')::int,120,'receipt accounts for unknown stages');
select is((select raw->'line'->0->>'offset_minutes' from public.sleep_nights where user_id='20200920-0000-4000-8000-000000000001' and user_day='2026-09-19'),'0','original line offsets unchanged');
select is((select architecture_score from nb.night_score_parts('20200920-0000-4000-8000-000000000001','2026-09-19')),null::numeric,'partial stages cannot imply full-window architecture');
select lives_ok($$select public.correct_sleep_window('2026-09-19','03:00','06:00')$$,'fully uncovered correction is explicit user-reported sleep');
select is((select count(*) from nb.sleep_evidence_minutes('20200920-0000-4000-8000-000000000001','2026-09-19')),0::bigint,'uncovered correction has no fabricated charge evidence');
select lives_ok($$select public.clear_sleep_correction('2026-09-19')$$,'measured night correction clears');
select results_eq($$select sleep_start,wake_at,total_minutes,deep_minutes,raw?'recorded_start' from public.sleep_nights
 where user_id='20200920-0000-4000-8000-000000000001' and user_day='2026-09-19'$$,
 $$select '2026-09-18 23:00+00'::timestamptz,'2026-09-19 00:00+00'::timestamptz,60::smallint,30::smallint,false$$,'clear restores original measured window and totals');

-- A later device read enriches the reported window without moving it. Its original
-- window becomes the receipt used by clear, and its stage offsets remain absolute.
select lives_ok($$select public.create_sleep_window('2026-09-18','22:00','07:00')$$,'reported night reserves its window against later sync');
select lives_ok($$select public.publish_sleep_night('{"user_day":"2026-09-18","sleep_start":"2026-09-17T23:00:00Z","wake_at":"2026-09-18T06:00:00Z","total_minutes":420,"deep_minutes":120,"light_minutes":300,"wake_count":0,"raw":{"line":[{"stage":0,"minutes":120,"offset_minutes":0},{"stage":1,"minutes":300,"offset_minutes":120}]}}'::jsonb)$$,
 'later device sync contributes measured stages');
select results_eq($$select sleep_start,wake_at,nb.bb_instant(raw->>'recorded_start'),coalesce(raw->>'source','band')
 from public.sleep_nights where user_id='20200920-0000-4000-8000-000000000001' and user_day='2026-09-18'$$,
 $$select '2026-09-17 22:00+00'::timestamptz,'2026-09-18 07:00+00'::timestamptz,'2026-09-17 23:00+00'::timestamptz,'band'::text$$,
 'device sync retains reported bounds and remembers measured bounds');
select is((select count(*) from nb.sleep_evidence_minutes('20200920-0000-4000-8000-000000000001','2026-09-18')),420::bigint,
 'real device stages enrich a previously unstaged reported night');
select lives_ok($$select public.clear_sleep_correction('2026-09-18')$$,'clear after device sync restores device window');
select results_eq($$select sleep_start,wake_at,total_minutes from public.sleep_nights
 where user_id='20200920-0000-4000-8000-000000000001' and user_day='2026-09-18'$$,
 $$select '2026-09-17 23:00+00'::timestamptz,'2026-09-18 06:00+00'::timestamptz,420::smallint$$,
 'clear uses measured window after manual night is enriched');

insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line,raw)
values('20200920-0000-4000-8000-000000000001','2026-09-17',120,60,60,
 '2026-09-16 22:00+00','2026-09-17 02:00+00','0:60,1:60',
 '{"intervals":[{"start":"2026-09-16T22:00:00Z","end":"2026-09-16T23:00:00Z"},{"start":"2026-09-17T01:00:00Z","end":"2026-09-17T02:00:00Z"}]}'::jsonb);
select lives_ok($$select public.correct_sleep_window('2026-09-17','00:00','02:00')$$,'legacy gapped stage line can be corrected');
select is((select stage from nb.sleep_evidence_minutes('20200920-0000-4000-8000-000000000001','2026-09-17') where ts='2026-09-17 01:00+00'),1,
 'legacy stages stay anchored to original intervals before clipping');
select is((select count(*) from nb.sleep_evidence_minutes('20200920-0000-4000-8000-000000000001','2026-09-17')),60::bigint,
 'legacy interval gap remains unmeasured after correction');

select throws_ok($$select public.create_sleep_window('2026-09-20','11:00','13:00')$$,'22023','FUTURE_SLEEP_WINDOW','future end is rejected even on today');
select throws_ok($$select public.create_sleep_window('2026-08-19','23:00','07:00')$$,'22023','CORRECTION_TOO_OLD','creation is bounded to recent 30 days');
select throws_ok($$select public.create_sleep_window('2026-09-18','23:00','23:00:00')$$,'22023','END_BEFORE_START','equivalent wall times do not create 24-hour sleep');
select throws_ok($$select public.create_sleep_window('2026-09-18','25:00','07:00')$$,'22023','BAD_TIME','malformed time gets typed validation error');
select set_config('request.jwt.claim.sub','20200920-0000-4000-8000-000000000002',true);
select throws_ok($$select public.correct_sleep_window('2026-09-19','22:00','07:00')$$,'22023','NO_SLEEP_NIGHT','another account cannot correct first account night');
select lives_ok($$select public.create_sleep_window('2026-09-20','23:00','07:00')$$,'second account can independently report same day');
select is((select sleep_start from public.sleep_nights where user_id='20200920-0000-4000-8000-000000000002'),'2026-09-20 03:00+00'::timestamptz,'reported clock resolves in owner timezone');
select set_config('nb.calculation_as_of','2026-03-09 12:00+00',true);
select results_eq($$select * from nb.resolve_reported_sleep_window('20200920-0000-4000-8000-000000000002','2026-03-08','23:00','07:00')$$,
 $$select '2026-03-08 04:00+00'::timestamptz,'2026-03-08 11:00+00'::timestamptz$$,'DST crossing uses previous local calendar date');
select throws_ok($$select * from nb.resolve_reported_sleep_window('20200920-0000-4000-8000-000000000002','2026-03-08','02:30','07:00')$$,'22023','BAD_TIME','nonexistent DST clock is not silently shifted');
update public.profiles set deletion_requested_at=now() where user_id='20200920-0000-4000-8000-000000000002';
select throws_ok($$select public.create_sleep_window('2026-03-08','23:00','07:00')$$,'42501','ACCOUNT_DELETING','deleting account cannot create');
update public.profiles set deletion_requested_at=null where user_id='20200920-0000-4000-8000-000000000002';
insert into public.consents(user_id,consent_version,choice,decided_at,text_sha256,locale)
values('20200920-0000-4000-8000-000000000002','v1','withdrawn',now(),'sha','zh-CN');
select throws_ok($$select public.create_sleep_window('2026-03-08','23:00','07:00')$$,'42501','CONSENT_WITHDRAWN','withdrawn consent cannot create');
select set_config('request.jwt.claim.sub','',true);
select throws_ok($$select public.create_sleep_window('2026-09-18','23:00','07:00')$$,'28000','UNAUTHENTICATED','no owner cannot create');
select ok(not has_function_privilege('anon','public.create_sleep_window(date,text,text)','execute'),'anonymous role cannot call creation');
select ok(not has_function_privilege('authenticated','nb.sleep_window_receipt(uuid,date)','execute'),'cross-user internal receipt is not exposed');
select ok(not (select prosecdef from pg_proc where oid='public.create_sleep_window(date,text,text)'::regprocedure),'creation API is security invoker');
select ok(not (select prosecdef from pg_proc where oid='public.correct_sleep_window(date,text,text)'::regprocedure),'correction API is security invoker');
select ok(not has_function_privilege('anon','health_commands.create_sleep_window(date,text,text)','execute'),'anonymous role cannot invoke private command');
select * from finish();
rollback;
