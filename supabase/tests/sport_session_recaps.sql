begin;
select no_plan();
insert into auth.users(id,is_anonymous) values
 ('20260921-0000-4000-8000-000000000001',false),
 ('20260921-0000-4000-8000-000000000002',false),
 ('20260921-0000-4000-8000-000000000003',true);
insert into public.profiles(user_id,timezone,birth_date)
 select id,'UTC','1990-01-01' from auth.users where id in
 ('20260921-0000-4000-8000-000000000001','20260921-0000-4000-8000-000000000002','20260921-0000-4000-8000-000000000003');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale,decided_at)
 select id,'test','granted','test','en','2026-09-20' from auth.users where id in
 ('20260921-0000-4000-8000-000000000001','20260921-0000-4000-8000-000000000002','20260921-0000-4000-8000-000000000003');
create temp table before_work as select * from nb.calculation_work
 where user_id='20260921-0000-4000-8000-000000000001';
create temp table fixture(payload jsonb);
insert into fixture values('{
 "title":"Strength","seconds":600,"avgHR":0,"peakHR":0,"kcal":0,
 "caloriesEstimated":false,"hasCalories":false,"curve":[],"curvePoints":[],
 "zoneMinutes":[0,0,0,0,0],"aerobicMinutes":0,"anaerobicMinutes":0,
 "conclusion":"No heart rate recorded","restHR":60,"maxHR":190,
 "sessionID":"20260921-0000-4000-8000-000000000011",
 "ownerUserID":"20260921-0000-4000-8000-000000000002"
}');
grant select on fixture to authenticated;
select set_config('request.jwt.claim.sub','20260921-0000-4000-8000-000000000001',true);
set local role authenticated;
select is(public.save_sport_recap('20260921-0000-4000-8000-000000000011',
 '2026-09-20 10:00Z','2026-09-20 10:10Z',(select payload from fixture))->>'replay',
 'false','finished no-HR session is saved');
select is((select payload from public.sport_session_recaps),(select payload from fixture),
 'raw recap fields round trip, including missing evidence and curve format');
select is((select user_id from public.sport_session_recaps),auth.uid(),
 'payload ownerUserID cannot choose the row owner');
select is(public.save_sport_recap('20260921-0000-4000-8000-000000000011',
 '2026-09-20 10:00Z','2026-09-20 10:10Z',(select payload from fixture))->>'replay',
 'true','identical retry is acknowledged without a second row');
select throws_ok($$select public.save_sport_recap('20260921-0000-4000-8000-000000000011',
 '2026-09-20 10:00Z','2026-09-20 10:10Z','{"seconds":601}')$$,
 '23505','SPORT_RECAP_CONFLICT','retry cannot replace saved presentation facts');
select throws_ok($$select public.save_sport_recap('20260921-0000-4000-8000-000000000011',
 '2026-09-20 10:00Z','2026-09-20 10:11Z',(select payload from fixture))$$,
 '23505','SPORT_RECAP_CONFLICT','retry cannot change the finished interval');
select throws_ok($$insert into public.sport_session_recaps(user_id,id,started_at,ended_at,payload)
 values(auth.uid(),gen_random_uuid(),'2026-09-20 10:00Z','2026-09-20 10:10Z','{}')$$,
 '42501',null,'direct inserts cannot bypass the upload command');
select throws_ok($$update public.sport_session_recaps set payload='{}'$$,
 '42501',null,'client cannot mutate a saved recap');
select throws_ok($$delete from public.sport_session_recaps$$,
 '42501',null,'client cannot erase individual saved recaps');
select throws_ok($$select public.save_sport_recap(null,'2026-09-20 10:00Z','2026-09-20 10:10Z','{}')$$,
 '22023','INVALID_SPORT_RECAP_WINDOW','null identity is rejected');
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),null,'2026-09-20 10:10Z','{}')$$,
 '22023','INVALID_SPORT_RECAP_WINDOW','null timestamp is rejected');
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),'2026-09-20 10:00Z','infinity','{}')$$,
 '22023','INVALID_SPORT_RECAP_WINDOW','infinite timestamp is rejected');
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),'2026-09-20 10:00Z','2026-09-20 09:00Z','{}')$$,
 '22023','INVALID_SPORT_RECAP_WINDOW','reversed interval is rejected');
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),'2026-09-19 10:00Z','2026-09-20 10:01Z','{}')$$,
 '22023','INVALID_SPORT_RECAP_WINDOW','session is bounded to 24 hours');
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),now(),now()+interval '1 hour','{}')$$,
 '22023','INVALID_SPORT_RECAP_WINDOW','future session is not a finished recap');
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),'2026-09-20 10:00Z','2026-09-20 10:10Z',null)$$,
 '22023','INVALID_SPORT_RECAP_PAYLOAD','null payload is rejected');
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),'2026-09-20 10:00Z','2026-09-20 10:10Z','[]')$$,
 '22023','INVALID_SPORT_RECAP_PAYLOAD','array payload is rejected');
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),'2026-09-20 10:00Z','2026-09-20 10:10Z',
 jsonb_build_object('large',repeat('x',1048576)))$$,
 '22023','INVALID_SPORT_RECAP_PAYLOAD','payload size is bounded');
select is(jsonb_array_length(public.export_all()->'sport_session_recaps'),1,'data export includes saved recaps');
reset role;
select is((select count(*) from public.sport_session_recaps),1::bigint,'retry and rejected requests add no rows');
select results_eq($$select * from nb.calculation_work where user_id='20260921-0000-4000-8000-000000000001'$$,
 $$select * from before_work$$,'recap storage does not invalidate the training ledger');
select is((select count(*) from public.sport_heart_rate_samples where user_id='20260921-0000-4000-8000-000000000001'),
 0::bigint,'recap storage fabricates no HR observations');
select is((select count(*) from public.manual_sport_sessions where user_id='20260921-0000-4000-8000-000000000001'),
 0::bigint,'recap storage does not declare manual training sessions');

select set_config('request.jwt.claim.sub','20260921-0000-4000-8000-000000000002',true);
set local role authenticated;
select is((select count(*) from public.sport_session_recaps),0::bigint,'another account cannot read the first recap');
select is(public.save_sport_recap('20260921-0000-4000-8000-000000000011',
 '2026-09-20 10:00Z','2026-09-20 10:10Z','{"title":"Other owner"}')->>'replay',
 'false','session UUID is scoped by account and cannot overwrite another owner');
select is((select count(*) from public.sport_session_recaps),1::bigint,'second account reads only its own recap');
reset role;
select is((select payload from public.sport_session_recaps where user_id='20260921-0000-4000-8000-000000000001'),
 (select payload from fixture),'same UUID in another account preserves original recap');

select set_config('request.jwt.claim.sub','20260921-0000-4000-8000-000000000003',true);
set local role authenticated;
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),'2026-09-20 10:00Z','2026-09-20 10:10Z','{}')$$,
 '28000','UNAUTHENTICATED','anonymous Supabase user cannot upload even with a profile and consent');
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),'2026-09-20 10:00Z','2026-09-20 10:10Z','{}')$$,
 '28000','UNAUTHENTICATED','missing authentication is rejected');
reset role;
set local role anon;
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),'2026-09-20 10:00Z','2026-09-20 10:10Z','{}')$$,
 '42501',null,'anon role cannot invoke the upload wrapper');
select throws_ok($$select * from public.sport_session_recaps$$,'42501',null,'anon role cannot read recaps');
reset role;

insert into public.consents(user_id,consent_version,choice,text_sha256,locale,decided_at)
 values('20260921-0000-4000-8000-000000000001','test','withdrawn','test','en','2026-09-21');
select set_config('request.jwt.claim.sub','20260921-0000-4000-8000-000000000001',true);
set local role authenticated;
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),'2026-09-20 10:00Z','2026-09-20 10:10Z','{}')$$,
 '42501','CONSENT_WITHDRAWN','withdrawn consent blocks new recaps');
select throws_ok($$select public.save_sport_recap('20260921-0000-4000-8000-000000000011',
 '2026-09-20 10:00Z','2026-09-20 10:10Z',(select payload from fixture))$$,
 '42501','CONSENT_WITHDRAWN','withdrawn consent also blocks upload retries');
reset role;
update public.profiles set deletion_requested_at=now() where user_id='20260921-0000-4000-8000-000000000002';
select set_config('request.jwt.claim.sub','20260921-0000-4000-8000-000000000002',true);
set local role authenticated;
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),'2026-09-20 10:00Z','2026-09-20 10:10Z','{}')$$,
 '42501','ACCOUNT_UNAVAILABLE','account deletion in progress blocks upload');
reset role;
update public.profiles set deletion_requested_at=null where user_id='20260921-0000-4000-8000-000000000002';
set local role authenticated;
select lives_ok($$select public.account_delete('DELETE')$$,'existing account deletion accepts the new recap relation');
reset role;
select is((select count(*) from public.sport_session_recaps where user_id='20260921-0000-4000-8000-000000000002'),
 0::bigint,'account deletion removes its saved recaps');
select is((select count(*) from public.sport_session_recaps where user_id='20260921-0000-4000-8000-000000000001'),
 1::bigint,'account deletion preserves another owner recaps');
set local role authenticated;
select throws_ok($$select public.save_sport_recap(gen_random_uuid(),'2026-09-20 10:00Z','2026-09-20 10:10Z','{}')$$,
 '28000','UNAUTHENTICATED','stale deleted-account token cannot recreate recaps');
reset role;
select * from finish();
rollback;
