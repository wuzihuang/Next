begin;
select no_plan();
insert into auth.users(id) values
 ('20260920-0000-4000-8000-000000000001'),('20260920-0000-4000-8000-000000000002');
insert into public.profiles(user_id,timezone,birth_date) values
 ('20260920-0000-4000-8000-000000000001','UTC','1990-01-01'),
 ('20260920-0000-4000-8000-000000000002','America/New_York','1990-01-01');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
 ('20260920-0000-4000-8000-000000000001','test','granted','test','en'),
 ('20260920-0000-4000-8000-000000000002','test','granted','test','en');
select set_config('nb.calculation_as_of','2026-09-20 12:00+00',true);
select set_config('nb.calculation_day','2026-09-20',true);
insert into public.raw_samples(user_id,ts,sampled_tz,heart,met,step) values
 ('20260920-0000-4000-8000-000000000001','2026-09-19 10:00+00','UTC',140,3.5,0),
 ('20260920-0000-4000-8000-000000000001','2026-09-19 10:05+00','UTC',140,3.5,0);
create temp table original as
 select sum(raw) raw from nb.training_ledger('20260920-0000-4000-8000-000000000001','2026-09-19');
create temp table original_revision as select input_revision from nb.calculation_work
 where user_id='20260920-0000-4000-8000-000000000001';
create temp table receipts(receipt jsonb);
grant all on receipts to authenticated;
select set_config('request.jwt.claim.sub','20260920-0000-4000-8000-000000000001',true);
set local role authenticated;
insert into receipts values(public.log_sport_session('2026-09-19','10:02','10:07',1,'20260920-0000-4000-8000-000000000011'));
select is((select receipt->>'data_status' from receipts),'complete','a declared workout attaches the existing five-minute observations');
select is((select (receipt->>'observed_seconds')::numeric from receipts),300::numeric,'partial tick edges are clipped to the requested seconds');
select is((select (receipt->>'hr_seconds')::numeric from receipts),300::numeric,'HR coverage comes from the existing observations');
select ok((select (receipt->>'load_delta')::numeric>0 from receipts),'receipt exposes its contribution to the daily curve');
select is(public.log_sport_session('2026-09-19','10:02','10:07',1,'20260920-0000-4000-8000-000000000011')->>'replay','true','retry acknowledges the same operation');
select throws_ok($$select public.log_sport_session('2026-09-19','10:02','10:08',1,'20260920-0000-4000-8000-000000000011')$$,
 '23505','SPORT_OPERATION_CONFLICT','same request ID cannot change the recorded facts');
select throws_ok($$select public.log_sport_session('2026-09-19','10:06','10:09',1,gen_random_uuid())$$,
 '22023','SPORT_WINDOW_OVERLAP','overlapping manual declarations cannot double claim observations');
select throws_ok($$select public.log_sport_session('2026-09-19','24:00','01:00',1,gen_random_uuid())$$,
 '22023','INVALID_SPORT_WINDOW','24:00 is rejected instead of changing its date');
select throws_ok($$select public.log_sport_session('2026-09-19','10:00','10:00',1,gen_random_uuid())$$,
 '22023','INVALID_SPORT_WINDOW','equal endpoints cannot silently mean an entire day');
select throws_ok($$select public.log_sport_session('2026-09-20','13:00','14:00',1,gen_random_uuid())$$,
 '22023','SPORT_IN_FUTURE','future interval cannot be reported as completed');
select throws_ok($$select public.log_sport_session('2026-08-01','10:00','11:00',1,gen_random_uuid())$$,
 '22023','SPORT_TOO_OLD','the ordered replay is bounded to thirty days');
select throws_ok($$select public.log_sport_session('2026-09-19','12:00','13:00',-1,gen_random_uuid())$$,
 '22023','INVALID_SPORT_WINDOW','invalid mode is rejected');
select throws_ok($$insert into public.manual_sport_sessions(user_id,id,user_day,started_at,ended_at,timezone,request_payload)
 values(auth.uid(),gen_random_uuid(),'2026-09-19','2026-09-19 01:00Z','2026-09-19 02:00Z','UTC','{}')$$,
 '42501',null,'clients cannot bypass the validated command with direct inserts');
reset role;
select is((select count(*) from public.manual_sport_sessions where user_id='20260920-0000-4000-8000-000000000001'),1::bigint,'replays and rejected operations create no extra sessions');
select ok((select dirty_from<='2026-09-19'::date from nb.calculation_work where user_id='20260920-0000-4000-8000-000000000001'),
 'manual declarations invalidate the start user day for chronological replay');
select is((select input_revision from nb.calculation_work where user_id='20260920-0000-4000-8000-000000000001'),
 (select input_revision+1 from original_revision),'retries and rejected operations invalidate no additional revisions');
select is((select sum(raw) from nb.training_ledger('20260920-0000-4000-8000-000000000001','2026-09-19')),
 (select raw*2.5 from original),'exercise promotion replaces the claimed half of two quarter-weight ticks exactly once');
select is((select sum((s->>'delta')::numeric) from jsonb_array_elements(nb.compute_segments('20260920-0000-4000-8000-000000000001','2026-09-19')) s),
 (select training_load from nb.compute_training('20260920-0000-4000-8000-000000000001','2026-09-19')),'session and ordinary activity contributions reconcile with the daily score');
select is((select count(*) from public.raw_samples where user_id='20260920-0000-4000-8000-000000000001'),2::bigint,'logging never inserts synthetic raw samples');
select is((select count(*) from public.sport_heart_rate_samples where user_id='20260920-0000-4000-8000-000000000001'),0::bigint,'logging never fabricates fine HR evidence');
set local role authenticated;
select is(public.log_sport_session('2026-09-19','11:00','12:00',25,'20260920-0000-4000-8000-000000000012')->>'data_status',
 'missing','a reported strength mode alone does not fabricate evidence');
select is(public.log_sport_session('2026-09-19','11:00','12:00',25,'20260920-0000-4000-8000-000000000012')->>'load_delta',
 null::text,'a workout with no measurements publishes unknown load');
select is(jsonb_array_length(public.export_all()->'manual_sport_sessions'),2,'export includes the declared records');
reset role;
insert into public.raw_samples(user_id,ts,sampled_tz,heart,met,step)
 values('20260920-0000-4000-8000-000000000001','2026-09-19 11:00Z','UTC',null,3.5,0);
select is((select s->>'data_status' from jsonb_array_elements(nb.training_sessions('20260920-0000-4000-8000-000000000001','2026-09-19')) s
 where s->>'session_id'='20260920-0000-4000-8000-000000000012'),'partial','a later sync fills the saved interval automatically');
select is((select (s->>'hr_seconds')::numeric from jsonb_array_elements(nb.training_sessions('20260920-0000-4000-8000-000000000001','2026-09-19')) s
 where s->>'session_id'='20260920-0000-4000-8000-000000000012'),0::numeric,'MET-only fill leaves HR absent');
select cmp_ok((select (s->>'load_delta')::numeric from jsonb_array_elements(nb.training_sessions('20260920-0000-4000-8000-000000000001','2026-09-19')) s
 where s->>'session_id'='20260920-0000-4000-8000-000000000012'),'>',0::numeric,'real MET supplies a load without invented optical heart rate');

-- Fine live observations keep ownership when the declared window surrounds them.
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sport_mode,sampled_tz)
select '20260920-0000-4000-8000-000000000001',gen_random_uuid(),'20260920-0000-4000-8000-000000000031',
 '20260920-0000-4000-8000-000000000032','2026-09-19 14:00Z'::timestamptz+i*interval '10 seconds',140,1,'UTC'
from generate_series(0,6) i;
create temp table live_before as select sum(raw) raw from nb.training_ledger('20260920-0000-4000-8000-000000000001','2026-09-19');
set local role authenticated;
select throws_ok($$select public.log_sport_session('2026-09-19','14:00','14:01',1,'20260920-0000-4000-8000-000000000013')$$,
 '22023','SPORT_WINDOW_OVERLAP','existing recorded workouts are not duplicated as empty manual sessions');
reset role;
select is((select sum(raw) from nb.training_ledger('20260920-0000-4000-8000-000000000001','2026-09-19')),
 (select raw from live_before),'already recorded sport seconds never accrue twice');
select is((select sum(hr_seconds) from nb.training_ledger('20260920-0000-4000-8000-000000000001','2026-09-19')
 where session_id='20260920-0000-4000-8000-000000000031'),60::numeric,'original live session retains its observed seconds');

insert into public.raw_samples(user_id,ts,sampled_tz,heart,met,step)
select '20260920-0000-4000-8000-000000000001','2026-09-19 16:00Z'::timestamptz+i*interval '5 minutes','UTC',160,3.5,0
from generate_series(0,2) i;
create temp table sustained_before as select sum(raw) raw from nb.training_ledger('20260920-0000-4000-8000-000000000001','2026-09-19');
set local role authenticated;
select public.log_sport_session('2026-09-19','16:00','16:15',1,'20260920-0000-4000-8000-000000000015');
reset role;
select is((select sum(raw) from nb.training_ledger('20260920-0000-4000-8000-000000000001','2026-09-19')),
 (select raw from sustained_before),'labelling exercise that already earned full weight does not add load a second time');

-- Midnight belongs to each local user day, rather than adding a fixed UTC day.
insert into public.raw_samples(user_id,ts,sampled_tz,heart,met,step) values
 ('20260920-0000-4000-8000-000000000001','2026-09-18 23:55Z','UTC',140,3.5,0),
 ('20260920-0000-4000-8000-000000000001','2026-09-19 00:00Z','UTC',140,3.5,0);
set local role authenticated;
select is((public.log_sport_session('2026-09-18','23:57','00:03',0,'20260920-0000-4000-8000-000000000014')->>'observed_seconds')::numeric,
 360::numeric,'cross-midnight receipt combines only the two clipped user-day portions');
reset role;
select is((select (s->>'observed_seconds')::numeric from jsonb_array_elements(nb.training_sessions('20260920-0000-4000-8000-000000000001','2026-09-18')) s
 where s->>'session_id'='20260920-0000-4000-8000-000000000014'),180::numeric,'the first day owns only the minutes before midnight');
select is((select (s->>'observed_seconds')::numeric from jsonb_array_elements(nb.training_sessions('20260920-0000-4000-8000-000000000001','2026-09-19')) s
 where s->>'session_id'='20260920-0000-4000-8000-000000000014'),180::numeric,'the second day owns only the minutes after midnight');

select set_config('request.jwt.claim.sub','20260920-0000-4000-8000-000000000002',true);
set local role authenticated;
select is((select count(*) from public.manual_sport_sessions),0::bigint,'another account cannot read declarations');
select is(jsonb_array_length(public.export_all()->'manual_sport_sessions'),0,'another account cannot export declarations');
select is(public.log_sport_session('2026-09-19','17:00','18:00',0,'20260920-0000-4000-8000-000000000011')->>'replay',
 'false','request IDs are scoped to the account');
reset role;
select is((select started_at from public.manual_sport_sessions where user_id='20260920-0000-4000-8000-000000000002'),
 '2026-09-19 21:00Z'::timestamptz,'wall-clock speech is resolved using the profile timezone');
select set_config('nb.calculation_as_of','2026-03-10 12:00+00',true);
select set_config('nb.calculation_day','2026-03-10',true);
set local role authenticated;
select throws_ok($$select public.log_sport_session('2026-03-08','02:30','03:30',0,gen_random_uuid())$$,
 '22023','INVALID_SPORT_WINDOW','nonexistent spring-forward clock time is rejected');
select is((public.log_sport_session('2026-03-07','23:30','03:30',0,'20260920-0000-4000-8000-000000000021')->>'ended_at')::timestamptz,
 '2026-03-08 07:30Z'::timestamptz,'cross-midnight DST conversion uses the next local calendar day');
reset role;
select ok(not has_function_privilege('anon','public.log_sport_session(date,text,text,integer,uuid)','execute'),'anonymous requests cannot execute the command');
select ok(not has_function_privilege('authenticated','nb.training_observed_ledger(uuid,date)','execute'),'the arbitrary-user ledger remains private');
select ok(not (select prosecdef from pg_proc where oid='public.log_sport_session(date,text,text,integer,uuid)'::regprocedure),
 'the API wrapper is security invoker');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale,decided_at)
 values('20260920-0000-4000-8000-000000000002','test','withdrawn','test','en',now()+interval '1 second');
set local role authenticated;
select throws_ok($$select public.log_sport_session('2026-03-09','17:00','18:00',0,gen_random_uuid())$$,
 '42501','CONSENT_WITHDRAWN','withdrawal stops collection even through the private command');
select is(public.account_delete('DELETE')->>'deleted','true','the existing guarded account-delete RPC still succeeds');
reset role;
select is((select count(*) from public.manual_sport_sessions where user_id='20260920-0000-4000-8000-000000000002'),0::bigint,'account deletion cascades declared workouts');
select * from finish();
rollback;
