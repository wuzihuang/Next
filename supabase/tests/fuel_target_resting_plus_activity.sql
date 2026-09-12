begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(14);

-- #29 · TARGET is this day's resting figure plus the activity the band has measured so
-- far plus the goal, and the resting figure is the body scan's when there is one.
--
-- A · 97 kg male, BULK, scanned (2229) — the account the 2705 came from.
-- B · the same body, BULK, never scanned: Mifflin.
-- C · 75 kg male, CUT, band on but still: resting − 500 is under the male floor.
-- D · 60 kg female, CUT, still: under the female floor.
-- E · 97 kg male, RECOMP, scanned, with a scan taken tomorrow that must not reach back.
insert into auth.users(id) values
 ('29290000-0000-4000-8000-000000000001'),
 ('29290000-0000-4000-8000-000000000002'),
 ('29290000-0000-4000-8000-000000000003'),
 ('29290000-0000-4000-8000-000000000004'),
 ('29290000-0000-4000-8000-000000000005');
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date,goal) values
 ('29290000-0000-4000-8000-000000000001','UTC','male',180,'1990-01-01','BULK'),
 ('29290000-0000-4000-8000-000000000002','UTC','male',180,'1990-01-01','BULK'),
 ('29290000-0000-4000-8000-000000000003','UTC','male',180,'1990-01-01','CUT'),
 ('29290000-0000-4000-8000-000000000004','UTC','female',165,'1990-01-01','CUT'),
 ('29290000-0000-4000-8000-000000000005','UTC','male',180,'1990-01-01','RECOMP');
insert into public.weigh_ins(user_id,measured_at,weight_kg,source,client_op_id) values
 ('29290000-0000-4000-8000-000000000001','2026-08-31 09:00+00',97,'manual',gen_random_uuid()),
 ('29290000-0000-4000-8000-000000000002','2026-08-31 09:00+00',97,'manual',gen_random_uuid()),
 ('29290000-0000-4000-8000-000000000003','2026-08-31 09:00+00',75,'manual',gen_random_uuid()),
 ('29290000-0000-4000-8000-000000000004','2026-08-31 09:00+00',60,'manual',gen_random_uuid()),
 ('29290000-0000-4000-8000-000000000005','2026-08-31 09:00+00',97,'manual',gen_random_uuid());
insert into public.body_composition(user_id,measured_at,user_day,measurement_source,input_weight_kg,body_fat_pct,lean_body_mass_kg,bmr_kcal) values
 -- Two scans, the later one wins.
 ('29290000-0000-4000-8000-000000000001','2026-09-04 09:36+00','2026-09-04','device_bia',97,32.3,65.6,2161),
 ('29290000-0000-4000-8000-000000000001','2026-09-10 09:36+00','2026-09-10','device_bia',97,32.3,65.6,2229),
 -- E scanned last week, and again tomorrow.
 ('29290000-0000-4000-8000-000000000005','2026-09-08 09:36+00','2026-09-08','device_bia',97,32.3,65.6,2200),
 ('29290000-0000-4000-8000-000000000005','2026-09-16 09:36+00','2026-09-16','device_bia',97,32.3,65.6,2600);

-- A and E walk a little all fortnight and today; C and D wear the band but do not move.
insert into public.raw_samples(user_id,ts,sampled_tz,step)
select u, ts, 'UTC', 60
from unnest(array['29290000-0000-4000-8000-000000000001'::uuid,'29290000-0000-4000-8000-000000000005']) u
cross join generate_series(timestamptz '2026-09-01 00:00+00', timestamptz '2026-09-15 11:55+00', interval '5 minutes') ts;
insert into public.raw_samples(user_id,ts,sampled_tz,step)
select u, ts, 'UTC', 0
from unnest(array['29290000-0000-4000-8000-000000000003'::uuid,'29290000-0000-4000-8000-000000000004']) u
cross join generate_series(timestamptz '2026-09-01 00:00+00', timestamptz '2026-09-15 11:55+00', interval '5 minutes') ts;

select set_config('nb.calculation_as_of','2026-09-15 12:00+00',true);
select set_config('nb.calculation_day','2026-09-15',true);

-- The resting figure ------------------------------------------------------------
select is((select r.source from nb.resting_kcal('29290000-0000-4000-8000-000000000001','2026-09-15') r), 'BODY_SCAN',
  'a scanned body rests on its scan');
select is((select r.kcal from nb.resting_kcal('29290000-0000-4000-8000-000000000001','2026-09-15') r), 2229::numeric,
  'the latest scan wins, unsmoothed');
select is((select r.source from nb.resting_kcal('29290000-0000-4000-8000-000000000002','2026-09-15') r), 'MIFFLIN',
  'a body never scanned rests on Mifflin');
select is((select round(r.kcal) from nb.resting_kcal('29290000-0000-4000-8000-000000000002','2026-09-15') r), 1920::numeric,
  'Mifflin for 97 kg, 180 cm, 36 y, male is 1920');
select is((select r.kcal from nb.resting_kcal('29290000-0000-4000-8000-000000000005','2026-09-15') r), 2200::numeric,
  'a scan taken tomorrow does not reach back into today');

-- One ledger: OUT rests on the same figure TARGET does.
select is((select c.bmr_full from nb.fuel_components('29290000-0000-4000-8000-000000000001','2026-09-15') c), 2229,
  'fuel_components publishes the scan as the whole day''s resting figure');

-- TARGET = resting + activity so far + goal ---------------------------------------
-- Rebuilt from the rounded macro split, so within one 20 kcal step.
create or replace function pg_temp.served(p_user uuid, p_day date) returns numeric language sql as $$
  select (select f.target_in from nb.compute_fuel(p_user, p_day) f)
       - (select c.bmr_full + coalesce(c.active_kcal, 0) from nb.fuel_components(p_user, p_day) c);
$$;
select cmp_ok(abs(pg_temp.served('29290000-0000-4000-8000-000000000001','2026-09-15') - 300), '<=', 20::numeric,
  'BULK is served resting + activity so far + 300');
select cmp_ok((select c.active_kcal from nb.fuel_components('29290000-0000-4000-8000-000000000001','2026-09-15') c), '>', 0,
  'and there was activity to add by noon');
select cmp_ok(abs(pg_temp.served('29290000-0000-4000-8000-000000000005','2026-09-15') + 380), '<=', 20::numeric,
  'RECOMP is served resting + activity so far − 380');

-- A settled day is resting + the whole day's activity + goal: the instant is its end.
select cmp_ok(abs(pg_temp.served('29290000-0000-4000-8000-000000000001','2026-09-14') - 300), '<=', 20::numeric,
  'yesterday''s target is its own whole day plus the goal');
select cmp_ok((select c.active_kcal from nb.fuel_components('29290000-0000-4000-8000-000000000001','2026-09-14') c),
  '>', (select c.active_kcal from nb.fuel_components('29290000-0000-4000-8000-000000000001','2026-09-15') c),
  'and a whole day carries more activity than half of one');

-- The target climbs with the day: a hard morning is money in the budget, not noise.
create temporary table before_walk as
  select f.target_in from nb.compute_fuel('29290000-0000-4000-8000-000000000001','2026-09-15') f;
update public.raw_samples set step = 900
 where user_id = '29290000-0000-4000-8000-000000000001'
   and ts >= '2026-09-15 07:00+00' and ts < '2026-09-15 09:00+00';
select cmp_ok((select f.target_in from nb.compute_fuel('29290000-0000-4000-8000-000000000001','2026-09-15') f),
  '>', (select target_in + 200 from before_walk),
  'two hours of brisk walking raise today''s target by what they burned');

-- The floor is absolute, by sex — not the basal figure -----------------------------
select cmp_ok(abs((select f.target_in from nb.compute_fuel('29290000-0000-4000-8000-000000000003','2026-09-15') f) - 1500)::numeric, '<=', 20::numeric,
  'a still male CUT stops at 1500, under his resting figure');
select cmp_ok(abs((select f.target_in from nb.compute_fuel('29290000-0000-4000-8000-000000000004','2026-09-15') f) - 1200)::numeric, '<=', 20::numeric,
  'a still female CUT stops at 1200');

select * from finish();
rollback;
