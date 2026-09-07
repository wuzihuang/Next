begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(8);

-- 1 · walker, 2 · no band data, 3 · fully sedentary fortnight. Same body, same goal.
insert into auth.users(id) values
 ('08080808-0000-4000-8000-000000000001'),
 ('08080808-0000-4000-8000-000000000002'),
 ('08080808-0000-4000-8000-000000000003'),
 ('08080808-0000-4000-8000-000000000004');
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date,goal) values
 ('08080808-0000-4000-8000-000000000001','UTC','male',180,'1990-01-01','RECOMP'),
 ('08080808-0000-4000-8000-000000000002','UTC','male',180,'1990-01-01','RECOMP'),
 ('08080808-0000-4000-8000-000000000003','UTC','male',180,'1990-01-01','CUT'),
 ('08080808-0000-4000-8000-000000000004','UTC','male',180,'1990-01-01','RECOMP')
on conflict(user_id) do update set timezone='UTC',sex='male',height_cm=180,birth_date='1990-01-01';
insert into public.weigh_ins(user_id,measured_at,weight_kg,source,client_op_id) values
 ('08080808-0000-4000-8000-000000000001','2026-08-31 09:00+00',75,'manual','08080808-0000-4000-8000-000000000011'),
 ('08080808-0000-4000-8000-000000000002','2026-08-31 09:00+00',75,'manual','08080808-0000-4000-8000-000000000012'),
 ('08080808-0000-4000-8000-000000000003','2026-08-31 09:00+00',75,'manual','08080808-0000-4000-8000-000000000013'),
 ('08080808-0000-4000-8000-000000000004','2026-08-31 09:00+00',75,'manual','08080808-0000-4000-8000-000000000014');

-- A full fortnight of five-minute ticks: 288 per user day, so coverage is never the reason.
insert into public.raw_samples(user_id,ts,sampled_tz,step)
select '08080808-0000-4000-8000-000000000001', ts, 'UTC', 60
from generate_series(timestamptz '2026-09-01 04:00+00', timestamptz '2026-09-15 03:55+00', interval '5 minutes') ts;
insert into public.raw_samples(user_id,ts,sampled_tz,step)
select '08080808-0000-4000-8000-000000000003', ts, 'UTC', 0
from generate_series(timestamptz '2026-09-01 04:00+00', timestamptz '2026-09-15 03:55+00', interval '5 minutes') ts;
-- A row can carry valid heart evidence without carrying an energy observation.
-- One observed zero-step slot per day must not make the other 143 HR-only slots count.
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step)
select '08080808-0000-4000-8000-000000000004',ts,'UTC',60,
  case when extract(hour from ts)=4 and extract(minute from ts)=0 then 0 end
from generate_series(timestamptz '2026-09-01 04:00+00', timestamptz '2026-09-15 03:55+00', interval '5 minutes') ts;

select set_config('nb.calculation_as_of','2026-09-15 12:00+00',true);
select set_config('nb.calculation_day','2026-09-15',true);

select ok((select nb.measured_burn('08080808-0000-4000-8000-000000000001','2026-09-15')
           > (select bmr_full from nb.fuel_components('08080808-0000-4000-8000-000000000001','2026-09-14'))),
  'a walked fortnight measures above the basal figure');
select is(nb.measured_burn('08080808-0000-4000-8000-000000000002','2026-09-15'), null::numeric,
  'no band days is unknown, never a fabricated multiplier');
select ok((select nb.measured_burn('08080808-0000-4000-8000-000000000001','2026-09-15')
           > nb.measured_burn('08080808-0000-4000-8000-000000000003','2026-09-15')),
  'the walker measures more than the sedentary body of the same size');
select is(nb.measured_burn('08080808-0000-4000-8000-000000000004','2026-09-15'),null::numeric,
  'HR-only rows cannot disguise one usable energy slot as a measured day');

-- Today's own burn must not move the budget: it reads the fourteen days behind it,
-- or the remaining-budget number would climb every time the user goes for a walk.
create temporary table walked_burn as
 select nb.measured_burn('08080808-0000-4000-8000-000000000001','2026-09-15') as kcal;
insert into public.raw_samples(user_id,ts,sampled_tz,step)
select '08080808-0000-4000-8000-000000000001', ts, 'UTC', 900
from generate_series(timestamptz '2026-09-15 04:00+00', timestamptz '2026-09-15 11:55+00', interval '5 minutes') ts;
select is(nb.measured_burn('08080808-0000-4000-8000-000000000001','2026-09-15'),
          (select kcal from walked_burn),
  'a hard morning does not raise today’s own budget');
-- The budget follows the burn: same body, same goal, different fortnight of movement.
select ok((select (select target_in from nb.compute_fuel('08080808-0000-4000-8000-000000000001','2026-09-15'))
           > (select target_in from nb.compute_fuel('08080808-0000-4000-8000-000000000003','2026-09-15'))),
  'the walked fortnight budgets more than the still one');
select ok((select (select target_in from nb.compute_fuel('08080808-0000-4000-8000-000000000003','2026-09-15'))
           >= (select bmr_full from nb.fuel_components('08080808-0000-4000-8000-000000000003','2026-09-14'))),
  'a CUT on a still fortnight never budgets below basal');
select ok((select (select target_in from nb.compute_fuel('08080808-0000-4000-8000-000000000002','2026-09-15')) is not null),
  'an account without band history still gets a budget');

select * from finish();
rollback;
