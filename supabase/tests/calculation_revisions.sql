begin;
select plan(24);
select set_config('nb.test_day',nb.user_day_of(now(),'UTC')::text,true);
select has_function('public', 'calculation_status', array['date','date']);
select has_column('public', 'daily_results', 'result_revision', 'result revision exists');
select has_column('public', 'daily_results', 'calculation_as_of', 'calculation instant exists');
select ok(not has_function_privilege('anon', 'public.settle_now(integer)', 'EXECUTE'), 'anonymous cannot settle');
select is(nb.user_day_of('2026-03-08 04:59+00', 'America/New_York'), '2026-03-07'::date, 'DST before midnight remains previous day');
select is(nb.user_day_of('2026-03-08 05:00+00', 'America/New_York'), '2026-03-08'::date, 'DST midnight starts day');
-- The spring-forward hour itself is inside the new day, not straddling a 04:00 seam.
select is(nb.user_day_of('2026-03-08 07:59+00', 'America/New_York'), '2026-03-08'::date, 'the skipped hour stays on its own day');
insert into auth.users(id) values('09090909-0000-0000-0000-000000000001'),('09090909-0000-0000-0000-000000000002');
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date) values
 ('09090909-0000-0000-0000-000000000001','UTC','male',180,'1990-01-01'),
 ('09090909-0000-0000-0000-000000000002','UTC','female',170,'1990-01-01') on conflict(user_id) do nothing;
insert into public.weigh_ins(user_id,measured_at,weight_kg,source,client_op_id)
 values('09090909-0000-0000-0000-000000000001',now()-interval '8 days',75,'manual','09090909-0000-0000-0000-000000000003');
insert into public.raw_samples(user_id,ts,sampled_tz,heart,met)
 values('09090909-0000-0000-0000-000000000001',now()-interval '1 hour','UTC',80,1.2);
-- Count the actual expensive replay at its existing seam, with no persistent instrumentation.
create temporary sequence replay_calls;
grant all on sequence replay_calls to postgres;
do $$ declare f text; begin
 f:=pg_get_functiondef('nb.reserve_replay_uncached(uuid,date)'::regprocedure);
 f:=replace(f,'begin'||chr(10),'begin'||chr(10)||'perform nextval(''pg_temp.replay_calls'');'||chr(10));
 execute f;
end $$;
select set_config('request.jwt.claim.sub','09090909-0000-0000-0000-000000000001',true);
set local role authenticated;
select set_config('nb.expected_replays',public.settle_now(2)::text,true);
select ok(current_setting('nb.expected_replays')::int>0,'first authenticated settle publishes');
reset role;
select is((select last_value::int from replay_calls),current_setting('nb.expected_replays')::int,'one expensive Body Battery replay per published day');
set local role authenticated;
select is(public.settle_now(2),0,'identical dependencies in same time bucket do not replay');
select ok((select bool_and(result_revision is not null and not pending) from public.calculation_status(current_setting('nb.test_day')::date-2,current_setting('nb.test_day')::date-1)),'closed results have revision and are ready');
create temporary table saved_calculation as select user_day,result_revision,calculation_as_of from public.calculation_status(current_setting('nb.test_day')::date-2,current_setting('nb.test_day')::date-1);
reset role;
create temporary table saved_fuel as select d.user_day,f.bmr_kcal from public.daily_results d join public.day_fuel f on f.result_id=d.id where d.user_id='09090909-0000-0000-0000-000000000001' and d.user_day=current_setting('nb.test_day')::date-2;
update public.profiles set height_cm=190 where user_id='09090909-0000-0000-0000-000000000001';
set local role authenticated;
select ok(public.settle_now(2)>=1,'profile changes refresh current day');
select ok((select bool_and(s.result_revision=c.result_revision) from saved_calculation s join public.calculation_status(current_setting('nb.test_day')::date-2,current_setting('nb.test_day')::date-1) c using(user_day)),'profile changes preserve closed result revisions');
reset role;
insert into public.meals(user_id,user_day,slot,kcal,client_op_id)
 values('09090909-0000-0000-0000-000000000001',current_setting('nb.test_day')::date-2,'LUNCH',500,'09090909-0000-0000-0000-000000000004');
set local role authenticated;
select ok((select bool_and(pending) from public.calculation_status(current_setting('nb.test_day')::date-2,current_setting('nb.test_day')::date-1)),'late facts mark dependent dates pending');
select ok(public.settle_now(0)>=2,'today-only app request drains older dirty dependencies');
select ok((select bool_and(s.result_revision<>c.result_revision) from saved_calculation s join public.calculation_status(current_setting('nb.test_day')::date-2,current_setting('nb.test_day')::date-1) c using(user_day)),'late fact changes following result revisions');
select is(public.settle_now(2),0,'settled history stays unchanged');
reset role;
select ok((select bool_and(s.bmr_kcal=f.bmr_kcal) from saved_fuel s join public.daily_results d on d.user_day=s.user_day and d.user_id='09090909-0000-0000-0000-000000000001' join public.day_fuel f on f.result_id=d.id),'late replay retains effective historical profile');
update public.daily_results set calculation_as_of=calculation_as_of-interval '5 minutes'
 where user_id='09090909-0000-0000-0000-000000000001' and user_day=current_setting('nb.test_day')::date;
set local role authenticated;
select ok((select pending from public.calculation_status(current_setting('nb.test_day')::date,current_setting('nb.test_day')::date)),'elapsed time bucket marks current result stale');
select is(public.settle_now(0),1,'current-day time dependency refreshes without new sample');
reset role;
insert into public.meals(user_id,user_day,slot,kcal,client_op_id)
 values('09090909-0000-0000-0000-000000000001',current_setting('nb.test_day')::date-500,'LUNCH',500,'09090909-0000-0000-0000-000000000005');
set local role authenticated;
select is(public.settle_now(0),0,'expired required input prevents partial replay');
select ok((select pending from public.calculation_status(current_setting('nb.test_day')::date,current_setting('nb.test_day')::date)),'expired dependency stays pending until archive recovery');
reset role;
select set_config('request.jwt.claim.sub','09090909-0000-0000-0000-000000000002',true);
set local role authenticated;
select ok((select bool_and(result_revision is null) from public.calculation_status(current_setting('nb.test_day')::date-2,current_setting('nb.test_day')::date-1)),'second account cannot read first account revisions');
select throws_ok($$select public.calculation_status(current_setting('nb.test_day')::date,current_setting('nb.test_day')::date-1)$$,'22023','INVALID_RANGE','invalid bounds rejected');
reset role;
select * from finish();
rollback;
