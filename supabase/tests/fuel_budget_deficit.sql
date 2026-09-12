begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(6);

-- A · a short, older, heavier body on a CUT: the one whose basal figure is low against
-- its own protein and fat allowance, and the only shape the carbohydrate floor reaches.
-- B · a walker wearing the band all day. C · the same walker, same rate, wearing it for
-- eighteen hours. D · the same walker at fourteen hours, which is not a measured day.
insert into auth.users(id) values
 ('0a0a0a0a-0000-4000-8000-000000000001'),
 ('0a0a0a0a-0000-4000-8000-000000000002'),
 ('0a0a0a0a-0000-4000-8000-000000000003'),
 ('0a0a0a0a-0000-4000-8000-000000000004');
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date,goal) values
 ('0a0a0a0a-0000-4000-8000-000000000001','UTC','female',160,'1966-01-01','CUT'),
 ('0a0a0a0a-0000-4000-8000-000000000002','UTC','male',180,'1990-01-01','RECOMP'),
 ('0a0a0a0a-0000-4000-8000-000000000003','UTC','male',180,'1990-01-01','RECOMP'),
 ('0a0a0a0a-0000-4000-8000-000000000004','UTC','male',180,'1990-01-01','RECOMP');
insert into public.weigh_ins(user_id,measured_at,weight_kg,source,client_op_id) values
 ('0a0a0a0a-0000-4000-8000-000000000001','2026-08-31 09:00+00',70,'manual','0a0a0a0a-0000-4000-8000-000000000011'),
 ('0a0a0a0a-0000-4000-8000-000000000002','2026-08-31 09:00+00',75,'manual','0a0a0a0a-0000-4000-8000-000000000012'),
 ('0a0a0a0a-0000-4000-8000-000000000003','2026-08-31 09:00+00',75,'manual','0a0a0a0a-0000-4000-8000-000000000013'),
 ('0a0a0a0a-0000-4000-8000-000000000004','2026-08-31 09:00+00',75,'manual','0a0a0a0a-0000-4000-8000-000000000014');

-- Fourteen whole user days, midnight to midnight, so the fortnight behind 09-15 is full.
insert into public.raw_samples(user_id,ts,sampled_tz,step)
select '0a0a0a0a-0000-4000-8000-000000000001', ts, 'UTC', 0
from generate_series(timestamptz '2026-09-01 00:00+00', timestamptz '2026-09-14 23:55+00', interval '5 minutes') ts;
insert into public.raw_samples(user_id,ts,sampled_tz,step)
select '0a0a0a0a-0000-4000-8000-000000000002', ts, 'UTC', 60
from generate_series(timestamptz '2026-09-01 00:00+00', timestamptz '2026-09-14 23:55+00', interval '5 minutes') ts;
-- 230 of 288 slots is 79.9% — above the 75% gate. 173 is 60.1%, below it.
insert into public.raw_samples(user_id,ts,sampled_tz,step)
select '0a0a0a0a-0000-4000-8000-000000000003', ts, 'UTC', 60
from generate_series(timestamptz '2026-09-01 00:00+00', timestamptz '2026-09-14 23:55+00', interval '5 minutes') ts
where extract(hour from ts)*12 + floor(extract(minute from ts)/5) < 230;
insert into public.raw_samples(user_id,ts,sampled_tz,step)
select '0a0a0a0a-0000-4000-8000-000000000004', ts, 'UTC', 60
from generate_series(timestamptz '2026-09-01 00:00+00', timestamptz '2026-09-14 23:55+00', interval '5 minutes') ts
where extract(hour from ts)*12 + floor(extract(minute from ts)/5) < 173;

select set_config('nb.calculation_as_of','2026-09-15 12:00+00',true);
select set_config('nb.calculation_day','2026-09-15',true);

-- #1 · a CUT pinned to its floor must stay pinned to it. The carbohydrate floor used to
-- hand back its own shortfall as calories: this body was served 1455 against a basal
-- 1239. What may remain is the 0.5 g/kg fat floor, one fat step wide. (Since #29 the
-- floor is the female 1200, which for this body lands in the same place.)
select ok((select (select target_in from nb.compute_fuel('0a0a0a0a-0000-4000-8000-000000000001','2026-09-15'))
                - (select bmr_full from nb.fuel_components('0a0a0a0a-0000-4000-8000-000000000001','2026-09-15')) <= 45),
  'a budget pinned to basal does not climb to whatever the floored macros add up to');
select is((select carb_g from nb.compute_fuel('0a0a0a0a-0000-4000-8000-000000000001','2026-09-15')), 100,
  'carbohydrate still never goes below a hundred grams');
select is((select fat_g from nb.compute_fuel('0a0a0a0a-0000-4000-8000-000000000001','2026-09-15')), 35,
  'fat gives way to that floor but stops at half a gram per kilo');

-- #2 · a whole day of basal was being added to the activity of a part day. An eighteen
-- hour day now measures as what it is: the same day, worn for eighteen hours.
select ok((select abs(nb.measured_burn('0a0a0a0a-0000-4000-8000-000000000003','2026-09-15')
                    - nb.measured_burn('0a0a0a0a-0000-4000-8000-000000000002','2026-09-15')) <= 2),
  'a day worn for eighteen hours measures the same as the day worn throughout');
select is(nb.measured_burn('0a0a0a0a-0000-4000-8000-000000000004','2026-09-15'), null::numeric,
  'fourteen hours of band is not a measured day');

-- #4b · the budget has to be able to say what it was built on.
select ok((select b.measured_days = 14
             and b.basis = b.measured_kcal
           from nb.burn_baseline('0a0a0a0a-0000-4000-8000-000000000002','2026-09-15',1700) b),
  'the basis is published with the fortnight it rests on');

select * from finish();
rollback;
