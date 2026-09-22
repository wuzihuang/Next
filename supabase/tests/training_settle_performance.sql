-- The phone's settle request must finish with a realistic baseline and live workout.
begin;
select plan(3);
insert into auth.users(id) values ('15150000-0000-4000-8000-000000000020');
insert into public.profiles(user_id,timezone,birth_date,sex,height_cm)
values ('15150000-0000-4000-8000-000000000020','UTC','1990-01-01','male',180);
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,wake_count,sleep_start,wake_at,sleep_line)
select '15150000-0000-4000-8000-000000000020',d::date,480,100,280,1,d,d+interval '8 hours','0:100,1:280,2:100'
from generate_series('2026-08-18'::timestamptz,'2026-09-15'::timestamptz,interval '1 day') d;
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met)
select '15150000-0000-4000-8000-000000000020',t,'UTC',
 case when extract(hour from t)<8 then 55 else 75 end,50,25,
 case when extract(hour from t)<8 then 0 else 30 end,case when extract(hour from t)<8 then 1 else 1.3 end
from generate_series('2026-08-18'::timestamptz,'2026-09-15 19:55+00'::timestamptz,interval '5 minutes') t;
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sport_mode,sampled_tz)
select '15150000-0000-4000-8000-000000000020',gen_random_uuid(),
 '15150000-0000-4000-8000-000000000021','15150000-0000-4000-8000-000000000022',t,155,1,'UTC'
from generate_series('2026-09-15 18:00+00'::timestamptz,'2026-09-15 19:00+00'::timestamptz,interval '10 seconds') t;
select set_config('nb.calculation_as_of','2026-09-15 20:00+00',true);
select set_config('nb.calculation_day','2026-09-15',true);
do $$ declare started timestamptz:=clock_timestamp(); elapsed numeric; begin
 perform nb.settle_day('15150000-0000-4000-8000-000000000020','2026-09-15');
 elapsed:=extract(epoch from(clock_timestamp()-started));
 perform set_config('nb.test_training_settle_seconds',elapsed::text,true);
 raise notice 'Training + recovery settlement with 29 nights and one live workout: % seconds',elapsed;
end $$;
select cmp_ok(current_setting('nb.test_training_settle_seconds')::numeric,'<',8::numeric,
 'one realistic day fits the phone settlement time budget');
select is((select (t.evidence->'sessions'->0->>'observed_seconds')::numeric from public.daily_training t
 join public.daily_results d on d.id=t.result_id where d.user_id='15150000-0000-4000-8000-000000000020'),
 3600::numeric,'the fast publication includes the whole observed workout');
select ok(nullif(current_setting('nb.training_reserve_memo',true),'') is null
 and nullif(current_setting('nb.training_ledger_memo',true),'') is null,
 'settlement clears its memoized input results');
select * from finish();
rollback;
