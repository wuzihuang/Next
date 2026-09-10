begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(7);

-- #23 / #24 · the calibration 20260908090000 was written to hit, held here so it cannot
-- drift back. Three bodies, one profile, one day:
--   A · a four-hour night and an ordinary working day on its feet
--   B · the same day with one hour of real training in the evening
--   C · no sleep at all, band worn right through
-- Each starts the day where the issue starts it: yesterday closed full.
insert into auth.users(id) select u from unnest(array[
 '24240000-0000-4000-8000-000000000001'::uuid,'24240000-0000-4000-8000-000000000002','24240000-0000-4000-8000-000000000003']) u;
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date,goal)
select u,'UTC','male',180,'1990-01-01','RECOMP' from unnest(array[
 '24240000-0000-4000-8000-000000000001'::uuid,'24240000-0000-4000-8000-000000000002','24240000-0000-4000-8000-000000000003']) u;
insert into public.daily_results(user_id,user_day,algo_version)
select u,'2026-09-14',nb.calculation_version() from unnest(array[
 '24240000-0000-4000-8000-000000000001'::uuid,'24240000-0000-4000-8000-000000000002','24240000-0000-4000-8000-000000000003']) u;
insert into public.reserve_daily(result_id,user_id,wake_value,min_value,current_value,drain_drivers)
select d.id,d.user_id,100,100,100,
 jsonb_build_object('close_value',100,'assumed_anchor',false,'anchor_origin','test')
from public.daily_results d where d.user_day='2026-09-14';

insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,wake_count,sleep_start,wake_at,raw)
select u,'2026-09-15',240,60,180,0,'2026-09-15 02:00+00','2026-09-15 06:00+00',
 jsonb_build_object('line',jsonb_build_array(
   jsonb_build_object('stage',0,'minutes',60,'offset_minutes',0),
   jsonb_build_object('stage',1,'minutes',180,'offset_minutes',60)))
from unnest(array['24240000-0000-4000-8000-000000000001'::uuid,'24240000-0000-4000-8000-000000000002']) u;

-- Ordinary labour: on the feet all day, heart a little above rest, never in a zone.
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met)
select u, ts, 'UTC',
  case when ts >= '2026-09-15 02:00+00' and ts < '2026-09-15 06:00+00' then 52 else 78 end,
  case when ts >= '2026-09-15 02:00+00' and ts < '2026-09-15 06:00+00' then 45 else 38 end,
  case when ts >= '2026-09-15 02:00+00' and ts < '2026-09-15 06:00+00' then 25 else 45 end,
  case when ts >= '2026-09-15 02:00+00' and ts < '2026-09-15 06:00+00' then 0 else 45 end,
  case when ts >= '2026-09-15 02:00+00' and ts < '2026-09-15 06:00+00' then 0.9 else 1.7 end
from unnest(array['24240000-0000-4000-8000-000000000001'::uuid,'24240000-0000-4000-8000-000000000002']) u
cross join generate_series(timestamptz '2026-09-15 00:00+00', timestamptz '2026-09-15 23:55+00', interval '5 minutes') ts;
update public.raw_samples set heart=155, met=9, step=650, stress=60
 where user_id='24240000-0000-4000-8000-000000000002'
   and ts >= '2026-09-15 18:00+00' and ts < '2026-09-15 19:00+00';
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met)
select '24240000-0000-4000-8000-000000000003', ts, 'UTC', 78, 38, 45, 45, 1.7
from generate_series(timestamptz '2026-09-15 00:00+00', timestamptz '2026-09-15 23:55+00', interval '5 minutes') ts;

select set_config('nb.calculation_as_of','2026-09-15 23:59+00',true);
select set_config('nb.calculation_day','2026-09-15',true);

create or replace function pg_temp.reserve(p_user uuid, p_day date) returns integer language sql as $$
  select r.current_value::integer from nb.compute_reserve(p_user,p_day) r;
$$;
create or replace function pg_temp.load(p_user uuid) returns numeric language sql as $$
  select t.training_load from nb.compute_training(p_user,'2026-09-15') t;
$$;
-- The ring's own curve, so an hour can be priced against an hour.
create or replace function pg_temp.load_at(p_user uuid, p_at timestamptz) returns numeric language sql as $$
  select max((p->>1)::numeric) from nb.compute_training(p_user,'2026-09-15') t
  cross join lateral jsonb_array_elements(t.curve) p
  where to_timestamp((p->>0)::bigint) <= p_at;
$$;

-- #24 · a short night and a day of work has to describe that day. It used to land near 60
-- whatever the night had been.
select cmp_ok(pg_temp.reserve('24240000-0000-4000-8000-000000000001','2026-09-15'), '<=', 45,
  'a four-hour night and an ordinary day ends the day well below the old sixty');
select cmp_ok(pg_temp.reserve('24240000-0000-4000-8000-000000000001','2026-09-15'), '>=', 20,
  'and not so low that an ordinary day reads as an emergency');
select cmp_ok(pg_temp.reserve('24240000-0000-4000-8000-000000000002','2026-09-15'), '<=',
  pg_temp.reserve('24240000-0000-4000-8000-000000000001','2026-09-15') - 15,
  'one hour of real training costs the day a great deal more than the same hour of work');
select cmp_ok(pg_temp.reserve('24240000-0000-4000-8000-000000000002','2026-09-15'), '<=', 20,
  'a short night plus a workout ends near empty');

-- A day awake from full still has charge left; it is the second sleepless day that reaches
-- zero, which is what "really did not sleep" means and what the floor of 0.35 allows.
select cmp_ok(pg_temp.reserve('24240000-0000-4000-8000-000000000003','2026-09-15'), '<=', 35,
  'a whole day with no sleep at all drains most of a full battery');

-- #23 · ordinary life must not climb the ring the way training does. Everything outside a
-- session enters the ledger at a quarter weight, so an hour of work and an hour of
-- training can no longer be worth the same.
select cmp_ok(pg_temp.load('24240000-0000-4000-8000-000000000001'), '<=', 6::numeric,
  'a whole day on the feet, never in a zone, stays in the low end of the ring');
select cmp_ok(
  pg_temp.load_at('24240000-0000-4000-8000-000000000002','2026-09-15 19:00+00')
    - pg_temp.load_at('24240000-0000-4000-8000-000000000002','2026-09-15 18:00+00'),
  '>=', 5 * pg_temp.load('24240000-0000-4000-8000-000000000001') / 18,
  'the training hour is worth at least five ordinary hours of the same day');

select * from finish();
rollback;
