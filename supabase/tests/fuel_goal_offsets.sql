begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(6);

-- #26 · the same body on each of the three profile goals, so the only thing under test is
-- the offset the goal applies to the day's burn basis. Fourteen whole worn days put that
-- basis on the measured median rather than the BMR multiplier, which is what TARGET is
-- told to rest on. D is the same body living a quieter fortnight: its basis sits close
-- enough to the basal figure that a five-hundred deficit would go under it.
insert into auth.users(id) values
 ('26260000-0000-4000-8000-000000000001'),
 ('26260000-0000-4000-8000-000000000002'),
 ('26260000-0000-4000-8000-000000000003'),
 ('26260000-0000-4000-8000-000000000004');
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date,goal) values
 ('26260000-0000-4000-8000-000000000001','UTC','male',180,'1990-01-01','CUT'),
 ('26260000-0000-4000-8000-000000000002','UTC','male',180,'1990-01-01','RECOMP'),
 ('26260000-0000-4000-8000-000000000003','UTC','male',180,'1990-01-01','BULK'),
 ('26260000-0000-4000-8000-000000000004','UTC','male',180,'1990-01-01','CUT');
insert into public.weigh_ins(user_id,measured_at,weight_kg,source,client_op_id)
select u, '2026-08-31 09:00+00', 75, 'manual', gen_random_uuid()
from unnest(array['26260000-0000-4000-8000-000000000001'::uuid,'26260000-0000-4000-8000-000000000002',
                  '26260000-0000-4000-8000-000000000003','26260000-0000-4000-8000-000000000004']) u;
insert into public.raw_samples(user_id,ts,sampled_tz,step)
select u, ts, 'UTC', 200
from unnest(array['26260000-0000-4000-8000-000000000001'::uuid,'26260000-0000-4000-8000-000000000002',
                  '26260000-0000-4000-8000-000000000003']) u
cross join generate_series(timestamptz '2026-09-01 00:00+00', timestamptz '2026-09-14 23:55+00', interval '5 minutes') ts;
insert into public.raw_samples(user_id,ts,sampled_tz,step)
select '26260000-0000-4000-8000-000000000004', ts, 'UTC', 60
from generate_series(timestamptz '2026-09-01 00:00+00', timestamptz '2026-09-14 23:55+00', interval '5 minutes') ts;

select set_config('nb.calculation_as_of','2026-09-15 12:00+00',true);
select set_config('nb.calculation_day','2026-09-15',true);

-- TARGET is rebuilt from the rounded macro split, so it lands within one 20 kcal step of
-- `basis + Δ`. Anything wider than that is the offset itself having moved.
-- ⚠️ burn_baseline's third argument only feeds the fallback estimate; with fourteen
-- measured days the basis is the median and the argument does not enter it.
create or replace function pg_temp.served(p_user uuid) returns numeric language sql as $$
  select (select f.target_in from nb.compute_fuel(p_user,'2026-09-15') f)
       - (select b.basis from nb.burn_baseline(p_user,'2026-09-15',
            (select c.bmr_full from nb.fuel_components(p_user,'2026-09-15') c)) b);
$$;

select cmp_ok(abs(pg_temp.served('26260000-0000-4000-8000-000000000001') + 500), '<=', 20::numeric,
  'a CUT is served its own burn basis less five hundred');
select cmp_ok(abs(pg_temp.served('26260000-0000-4000-8000-000000000002') + 380), '<=', 20::numeric,
  'RECOMP keeps its three hundred and eighty');
select cmp_ok(abs(pg_temp.served('26260000-0000-4000-8000-000000000003') - 300), '<=', 20::numeric,
  'BULK keeps its three hundred');

-- The gap between two goals is the gap between two offsets, whatever the basis is.
select cmp_ok(
  abs(((select f.target_in from nb.compute_fuel('26260000-0000-4000-8000-000000000003','2026-09-15') f)
     - (select f.target_in from nb.compute_fuel('26260000-0000-4000-8000-000000000001','2026-09-15') f))::numeric - 800),
  '<=', 40::numeric, 'eight hundred kilocalories separate BULK from CUT');

-- One owner. The fuel card, the detail page and the AI all read this one number, and it
-- is the macro split it publishes — never a second figure standing beside it.
select is(
  (select f.target_in from nb.compute_fuel('26260000-0000-4000-8000-000000000001','2026-09-15') f),
  (select (4*f.protein_g + 9*f.fat_g + 4*f.carb_g)::integer from nb.compute_fuel('26260000-0000-4000-8000-000000000001','2026-09-15') f),
  'TARGET is the macro split it publishes, not a second figure beside it');

-- The deficit is applied to the basis, but it never digs under the basal figure: a quiet
-- fortnight is served its basal figure, not basis − 500.
select is(
  (select f.target_in from nb.compute_fuel('26260000-0000-4000-8000-000000000004','2026-09-15') f),
  (select round(c.bmr_full)::integer from nb.fuel_components('26260000-0000-4000-8000-000000000004','2026-09-15') c),
  'a CUT on a quiet fortnight still stops at the basal figure');

select * from finish();
rollback;
