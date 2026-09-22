-- The phone's settle request must finish with a realistic baseline and live workout.
begin;
select plan(11);
insert into auth.users(id) values ('24240000-0000-4000-8000-000000000020');
insert into public.profiles(user_id,timezone,birth_date,sex,height_cm)
values ('24240000-0000-4000-8000-000000000020','UTC','1990-01-01','male',180);
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,wake_count,sleep_start,wake_at,sleep_line)
select '24240000-0000-4000-8000-000000000020',d::date,480,100,280,1,d,d+interval '8 hours','0:100,1:280,2:100'
from generate_series('2026-08-18'::timestamptz,'2026-09-15'::timestamptz,interval '1 day') d;
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met)
select '24240000-0000-4000-8000-000000000020',t,'UTC',
 case when extract(hour from t)<8 then 55 else 75 end,50,25,
 case when extract(hour from t)<8 then 0 else 30 end,case when extract(hour from t)<8 then 1 else 1.3 end
from generate_series('2026-08-18'::timestamptz,'2026-09-15 19:55+00'::timestamptz,interval '5 minutes') t;
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sport_mode,sampled_tz)
select '24240000-0000-4000-8000-000000000020',gen_random_uuid(),
 '24240000-0000-4000-8000-000000000021','24240000-0000-4000-8000-000000000022',t,155,1,'UTC'
from generate_series('2026-09-15 18:00+00'::timestamptz,'2026-09-15 19:00+00'::timestamptz,interval '10 seconds') t;
select set_config('nb.calculation_as_of','2026-09-15 20:00+00',true);
select set_config('nb.calculation_day','2026-09-15',true);

-- A compatible close reproduces the history catch-up path, not a fresh seed.
insert into public.daily_results(id,user_id,user_day,algo_version)
values ('24240000-0000-4000-8000-000000000023','24240000-0000-4000-8000-000000000020','2026-09-14',nb.calculation_version());
insert into public.reserve_daily(result_id,user_id,wake_value,min_value,current_value,drain_drivers)
values ('24240000-0000-4000-8000-000000000023','24240000-0000-4000-8000-000000000020',51,51,51,
 '{"close_value":50.123456789012,"assumed_anchor":true,"anchor_origin":"first_sleep_20"}');
-- Build the exact pre-change replay and its consumer under transaction-local names.
do $$ declare def text; original text; begin
 def:=pg_get_functiondef('nb.reserve_replay_uncached(uuid,date)'::regprocedure);
 def:=replace(def,'FUNCTION nb.reserve_replay_uncached(', 'FUNCTION pg_temp.replay_unbounded(');
 original:=def;
 def:=replace(def,
  'select r.t,trunc(r.value,24),r.in_sleep,trunc(r.d_charge,24),trunc(r.d_basal,24),trunc(r.d_active,24),trunc(r.d_stress,24)',
  'select r.t,r.value,r.in_sleep,r.d_charge,r.d_basal,r.d_active,r.d_stress');
 if def=original then raise exception 'REPLAY_REFERENCE_ANCHOR_MISSING'; end if;
 execute def;
 def:=pg_get_functiondef('nb.compute_reserve(uuid,date)'::regprocedure);
 def:=replace(def,'FUNCTION nb.compute_reserve(', 'FUNCTION pg_temp.reserve_unbounded(');
 def:=replace(def,'nb.reserve_replay(', 'pg_temp.replay_unbounded(');
 execute def;
end $$;
create temporary table replay_before on commit drop as
 select * from pg_temp.replay_unbounded('24240000-0000-4000-8000-000000000020','2026-09-15');
create temporary table replay_after on commit drop as
 select * from nb.reserve_replay('24240000-0000-4000-8000-000000000020','2026-09-15');
create temporary table reserve_before on commit drop as
 select * from pg_temp.reserve_unbounded('24240000-0000-4000-8000-000000000020','2026-09-15');
create temporary table reserve_after on commit drop as
 select * from nb.compute_reserve('24240000-0000-4000-8000-000000000020','2026-09-15');
select ok((select max(scale(value))>1000 from replay_before),'fixture reproduces recursive decimal growth');
select ok((select max(greatest(scale(value),scale(d_charge),scale(d_basal),scale(d_active),scale(d_stress)))<=24
 from replay_after),'every cached numeric has bounded precision');
select results_eq(
 $$select ts,round(value),asleep,round(d_charge),round(d_basal),round(d_active),round(d_stress) from replay_before order by ts$$,
 $$select ts,round(value),asleep,round(d_charge),round(d_basal),round(d_active),round(d_stress) from replay_after order by ts$$,
 'every curve point and integer contribution matches the full-precision replay');
select results_eq(
 $$select wake_value,current_value,min_value,drivers-'training_target' from reserve_before$$,
 $$select wake_value,current_value,min_value,drivers-'training_target' from reserve_after$$,
 'published reserve, integer attribution, twelve-place close, and evidence are unchanged');
select is((select (drivers->'training_target')-'reserve'-'smoothed_reserve' from reserve_after),
 (select (drivers->'training_target')-'reserve'-'smoothed_reserve' from reserve_before),
 'all published training recommendation values are unchanged');
select ok((select abs((a.drivers->'training_target'->>'reserve')::numeric-(b.drivers->'training_target'->>'reserve')::numeric)<1e-22
 and abs((a.drivers->'training_target'->>'smoothed_reserve')::numeric-(b.drivers->'training_target'->>'smoothed_reserve')::numeric)<1e-22
 from reserve_after a cross join reserve_before b),'raw target inputs differ by less than 1e-22');
select ok((select bool_and(round(v,p)=round(trunc(v,24),p))
 from (values (0.499999999999999999999999999999::numeric),(0.500000000000000000000000000001),
 (-0.499999999999999999999999999999),(-0.500000000000000000000000000001),
 (1.000000000000499999999999999999),(1.000000000000500000000000000001),
 (-1.000000000000499999999999999999),(-1.000000000000500000000000000001)) n(v)
 cross join (values(0),(12)) precision(p)),
 'truncation preserves both sides of positive and negative score/close half-step boundaries');
select cmp_ok((select pg_column_size(jsonb_agg(to_jsonb(r))) from replay_after r),'<',
 (select pg_column_size(jsonb_agg(to_jsonb(r)))/10 from replay_before r),
 'cached replay shrinks by at least tenfold');
do $$ declare started timestamptz:=clock_timestamp(); begin
 perform nb.settle_day('24240000-0000-4000-8000-000000000020','2026-09-15');
 perform set_config('nb.test_precision_settle_seconds',extract(epoch from(clock_timestamp()-started))::text,true);
end $$;
select cmp_ok(current_setting('nb.test_precision_settle_seconds')::numeric,'<',8::numeric,
 'history-anchored settlement fits the phone budget');
select results_eq(
 $$select s.ts,s.value::numeric from public.reserve_samples s where s.user_id='24240000-0000-4000-8000-000000000020'
 and s.ts>='2026-09-15'::timestamptz and s.ts<'2026-09-16'::timestamptz order by ts$$,
 $$select ts,round(value) from replay_before order by ts$$,
 'stored curve matches the full precision reference');
select ok(not has_function_privilege('authenticated','nb.reserve_replay_uncached(uuid,date)','EXECUTE'),
 'internal replay remains inaccessible to direct authenticated RPC');
select * from finish();
rollback;
