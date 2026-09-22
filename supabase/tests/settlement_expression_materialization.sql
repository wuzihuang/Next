-- The phone's settle request must finish with a realistic baseline and live workout.
begin;
select plan(6);
insert into auth.users(id) values ('26260000-0000-4000-8000-000000000020');
insert into public.profiles(user_id,timezone,birth_date,sex,height_cm)
values ('26260000-0000-4000-8000-000000000020','UTC','1990-01-01','male',180);
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,wake_count,sleep_start,wake_at,sleep_line)
select '26260000-0000-4000-8000-000000000020',d::date,480,100,280,1,d,d+interval '8 hours','0:100,1:280,2:100'
from generate_series('2026-08-18'::timestamptz,'2026-09-15'::timestamptz,interval '1 day') d;
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met)
select '26260000-0000-4000-8000-000000000020',t,'UTC',
 case when extract(hour from t)<8 then 55 else 75 end,50,25,
 case when extract(hour from t)<8 then 0 else 30 end,case when extract(hour from t)<8 then 1 else 1.3 end
from generate_series('2026-08-18'::timestamptz,'2026-09-15 19:55+00'::timestamptz,interval '5 minutes') t;
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sport_mode,sampled_tz)
select '26260000-0000-4000-8000-000000000020',gen_random_uuid(),
 '26260000-0000-4000-8000-000000000021','26260000-0000-4000-8000-000000000022',t,155,1,'UTC'
from generate_series('2026-09-15 18:00+00'::timestamptz,'2026-09-15 19:00+00'::timestamptz,interval '10 seconds') t;
-- Same-bucket overlapping HR/MET sessions exercise timestamp precedence,
-- UUID tie breaks, different interval boundaries and independent signal owners.
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sport_mode,sampled_tz)
select '26260000-0000-4000-8000-000000000020',md5('hr/'||j||'/'||i)::uuid,
 md5('hr-session/'||j)::uuid,md5('hr-continuity/'||j)::uuid,
 '2026-09-15 18:00Z'::timestamptz+(i*10+case when j=3 then 3 else 0 end)*interval '1 second',
 (130+j*10)::smallint,1,'UTC'
from generate_series(1,3) j cross join generate_series(0,3) i;
insert into public.sport_energy_samples(user_id,id,session_id,continuity_id,observed_at,sport_mode,sampled_tz)
select '26260000-0000-4000-8000-000000000020',md5('met/'||j||'/'||i)::uuid,
 md5('met-session/'||j)::uuid,md5('met-continuity/'||j)::uuid,
 '2026-09-15 18:00Z'::timestamptz+(i*10+case when j=3 then 6 else 0 end)*interval '1 second',
 25,'UTC'
from generate_series(1,3) j cross join generate_series(0,3) i;
select set_config('nb.calculation_as_of','2026-09-15 20:00+00',true);
select set_config('nb.calculation_day','2026-09-15',true);

-- A compatible close reproduces the history catch-up path, not a fresh seed.
insert into public.daily_results(id,user_id,user_day,algo_version)
values ('26260000-0000-4000-8000-000000000023','26260000-0000-4000-8000-000000000020','2026-09-14',nb.calculation_version());
insert into public.reserve_daily(result_id,user_id,wake_value,min_value,current_value,drain_drivers)
values ('26260000-0000-4000-8000-000000000023','26260000-0000-4000-8000-000000000020',51,51,51,
 '{"close_value":50.123456789012,"assumed_anchor":true,"anchor_origin":"first_sleep_20"}');
do $$ declare def text; begin
 def:=pg_get_functiondef('nb.training_observed_ledger(uuid,date)'::regprocedure);
 def:=replace(def,'FUNCTION nb.training_observed_ledger(', 'FUNCTION pg_temp.ledger_before(');
 def:=replace(def,$anchor$ ), owners as materialized (
  select distinct on(s.ts,s.a,s.b,i.kind) s.ts,s.a,s.b,i.kind,i.id,i.heart,i.met,i.session_id,i.sport_mode
  from spans s join pieces i on i.ts=s.ts and i.piece_a<=s.a and i.piece_b>=s.b
  where s.b>s.a
  order by s.ts,s.a,s.b,i.kind,i.observed_at desc,i.id desc
 ), owned as (
$anchor$,$anchor$ ), owned as (
$anchor$);
 def:=replace(def,$anchor$  left join owners h on h.ts=s.ts and h.a=s.a and h.b=s.b and h.kind='hr'
  left join owners e on e.ts=s.ts and e.a=s.a and e.b=s.b and e.kind='met'$anchor$,$anchor$  left join lateral(select i.* from pieces i where i.ts=s.ts and i.kind='hr'
   and i.piece_a<=s.a and i.piece_b>=s.b order by i.observed_at desc,i.id desc limit 1) h on true
  left join lateral(select i.* from pieces i where i.ts=s.ts and i.kind='met'
   and i.piece_a<=s.a and i.piece_b>=s.b order by i.observed_at desc,i.id desc limit 1) e on true$anchor$);
 execute def; end $$;
select results_eq(
 $$select * from pg_temp.ledger_before('26260000-0000-4000-8000-000000000020','2026-09-15') order by starts_at,ends_at$$,
 $$select * from nb.training_observed_ledger('26260000-0000-4000-8000-000000000020','2026-09-15') order by starts_at,ends_at$$,
 'every owned interval, heart and movement signal remains exactly equal');

-- Reconstruct the original evaluation plan, retaining exactly the same formulas.
do $$ declare def text; begin
 def:=pg_get_functiondef('nb.reserve_replay_uncached(uuid,date)'::regprocedure);
 def:=replace(def,'FUNCTION nb.reserve_replay_uncached(', 'FUNCTION pg_temp.replay_before(');
 def:=replace(def,$anchor$  offset 0) q$anchor$,$anchor$  ) q$anchor$);
 def:=replace(def,$anchor$  offset 0) raw$anchor$,$anchor$  ) raw$anchor$);
 def:=replace(def,$anchor$  offset 0) soft$anchor$,$anchor$  ) soft$anchor$);
 def:=replace(def,$anchor$  cross join lateral (select raw.awake*soft.k awake,raw.movement*soft.k movement,raw.strain*soft.k strain offset 0) eff$anchor$,$anchor$  cross join lateral (select raw.awake*soft.k awake,raw.movement*soft.k movement,raw.strain*soft.k strain) eff$anchor$);
 def:=replace(def,$anchor$  offset 0) scale$anchor$,$anchor$  ) scale$anchor$);
 execute def;
 def:=pg_get_functiondef('nb.training_contributions(uuid,date)'::regprocedure);
 def:=replace(def,'FUNCTION nb.training_contributions(', 'FUNCTION pg_temp.contributions_before(');
 def:=replace(def,'), scored as materialized (','), scored as (');
 execute def;
end $$;
select results_eq(
 $$select * from pg_temp.replay_before('26260000-0000-4000-8000-000000000020','2026-09-15') order by ts$$,
 $$select * from nb.reserve_replay_uncached('26260000-0000-4000-8000-000000000020','2026-09-15') order by ts$$,
 'every replay point and cumulative contribution remains exactly equal');
select results_eq(
 $$select * from pg_temp.contributions_before('26260000-0000-4000-8000-000000000020','2026-09-15') order by starts_at,ends_at$$,
 $$select * from nb.training_contributions('26260000-0000-4000-8000-000000000020','2026-09-15') order by starts_at,ends_at$$,
 'all session attribution and displayed deltas remain exactly equal');
do $$ declare started timestamptz:=clock_timestamp(); begin
 perform nb.settle_day('26260000-0000-4000-8000-000000000020','2026-09-15');
 perform set_config('nb.test_expression_seconds',extract(epoch from(clock_timestamp()-started))::text,true);
end $$;
select cmp_ok(current_setting('nb.test_expression_seconds')::numeric,'<',8::numeric,
 'complete realistic day settlement stays within the phone timeout');
select ok((select current_value is not null from public.reserve_daily where user_id='26260000-0000-4000-8000-000000000020' and result_id<>(select id from public.daily_results where user_id='26260000-0000-4000-8000-000000000020' and user_day='2026-09-14')),
 'settlement publishes reserve with the historical anchor');
select ok(not has_function_privilege('authenticated','nb.reserve_replay_uncached(uuid,date)','EXECUTE')
 and not has_function_privilege('authenticated','nb.training_contributions(uuid,date)','EXECUTE'),
 'internal calculation functions remain private');
select * from finish();
rollback;
