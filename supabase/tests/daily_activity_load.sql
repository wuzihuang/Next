begin;
select plan(36);
insert into auth.users(id) values ('06060606-0000-0000-0000-000000000001');
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date) values ('06060606-0000-0000-0000-000000000001','UTC','male',180,'1990-01-01') on conflict(user_id) do update set timezone='UTC',sex='male',height_cm=180,birth_date='1990-01-01';
select set_config('nb.calculation_as_of','2026-09-04 18:00+00',true);
select set_config('nb.calculation_day','2026-09-04',true);
select is((select training_load from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04')),null::numeric,'no activity is missing, not a fabricated zero');
insert into public.raw_samples(user_id,ts,sampled_tz,step) values ('06060606-0000-0000-0000-000000000001','2026-09-04 10:00+00','UTC',500);
select ok((select training_load>0 from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04')),'walking moves load without last week resting HR');
select is((select sum((s->>'delta')::numeric) from jsonb_array_elements(nb.compute_segments('06060606-0000-0000-0000-000000000001','2026-09-04')) s),(select training_load from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04')),'segment shares equal ring');
create temporary table walking_load as select training_load from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04');
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step) values ('06060606-0000-0000-0000-000000000001','2026-09-04 19:00+00','UTC',180,500);
select is((select training_load from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04')),(select training_load from walking_load),'future activity excluded');
insert into public.weigh_ins(user_id,measured_at,weight_kg,source,client_op_id) values ('06060606-0000-0000-0000-000000000001','2026-09-04 09:00+00',75,'manual','06060606-0000-0000-0000-000000000002');
select ok((select bmr_full>0 from nb.fuel_components('06060606-0000-0000-0000-000000000001','2026-09-04')),'first same-day weigh-in supplies baseline');
select ok((select active_kcal>0 from nb.fuel_components('06060606-0000-0000-0000-000000000001','2026-09-04')),'steps supply explicitly estimated active burn without MET');
select is((select kcal_out from nb.compute_fuel('06060606-0000-0000-0000-000000000001','2026-09-04')),(select bmr_kcal+active_kcal from nb.fuel_components('06060606-0000-0000-0000-000000000001','2026-09-04')),'fuel header equals components exactly');
select is((select bmr_full from nb.fuel_components('06060606-0000-0000-0000-000000000001','2026-09-04')),1700,'resting baseline uses the effective age, height, sex and weight');
insert into public.body_composition(user_id,measured_at,user_day,measurement_source,input_weight_kg,bmr_kcal)
values('06060606-0000-0000-0000-000000000001','2026-09-04 09:00+00','2026-09-04','device_bia',75,2100);
select is((select bmr_full from nb.fuel_components('06060606-0000-0000-0000-000000000001','2026-09-04')),1700,'unvalidated device BMR remains a reference, not a silent baseline override');
create temporary table before_future_met as select kcal_out from nb.compute_fuel('06060606-0000-0000-0000-000000000001','2026-09-04');
update public.raw_samples set met=10 where user_id='06060606-0000-0000-0000-000000000001' and ts='2026-09-04 19:00+00';
select is((select kcal_out from nb.compute_fuel('06060606-0000-0000-0000-000000000001','2026-09-04')),(select kcal_out from before_future_met),'future MET cannot leak into total while components exclude it');
select is((select bmr_full from nb.fuel_components('06060606-0000-0000-0000-000000000001','2026-09-03')),null::integer,'later weight cannot fill past day');
update public.raw_samples set step=0 where user_id='06060606-0000-0000-0000-000000000001' and ts='2026-09-04 10:00+00';
select is((select training_load from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04')),0.0::numeric,'observed zero movement is real zero');
update public.raw_samples set step=null,hrv=20 where user_id='06060606-0000-0000-0000-000000000001' and ts='2026-09-04 10:00+00';
select is((select training_load from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04')),null::numeric,'HRV alone does not invent activity');
select is((select active_kcal from nb.fuel_components('06060606-0000-0000-0000-000000000001','2026-09-04')),null::integer,'missing movement is unknown active calories');
select is((select kcal_out from nb.compute_fuel('06060606-0000-0000-0000-000000000001','2026-09-04')),null::integer,'unknown active energy is not a complete total');
-- HRR needs three qualified nights, not a single incidental heart reading.
insert into public.sleep_nights(user_id,user_day,total_minutes,sleep_start,wake_at,sleep_line)
select '06060606-0000-0000-0000-000000000001',d::date,60,d,d+interval '1 hour','1:60'
from generate_series('2026-08-25 00:00+00'::timestamptz,'2026-08-27 00:00+00'::timestamptz,interval '1 day') d;
insert into public.raw_samples(user_id,ts,sampled_tz,heart)
select '06060606-0000-0000-0000-000000000001',d+make_interval(mins=>tick*5),'UTC',60
from generate_series('2026-08-25 00:00+00'::timestamptz,'2026-08-27 00:00+00'::timestamptz,interval '1 day') d
cross join generate_series(0,11) tick;
update public.raw_samples set heart=165,step=500 where user_id='06060606-0000-0000-0000-000000000001' and ts='2026-09-04 10:00+00';
select ok((select training_load>(select training_load from walking_load) from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04')),'higher exercise HR gives greater pressure than ordinary walking');
create temporary table exercise_load as select training_load from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04');
update public.raw_samples set hrv=100 where user_id='06060606-0000-0000-0000-000000000001' and ts='2026-09-04 10:00+00';
select is((select training_load from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04')),(select training_load from exercise_load),'daytime HRV does not multiply physical work');
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step) select '06060606-0000-0000-0000-000000000001',ts,'UTC',165,500 from generate_series('2026-09-04 10:05+00'::timestamptz,'2026-09-04 10:20+00'::timestamptz,interval '5 minutes') ts;
select ok((select training_load>(select training_load from exercise_load) and training_load<=20.9 from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04')),'additional recorded work increases load within cap');
select is((select sum((s->>'delta')::numeric) from jsonb_array_elements(nb.compute_segments('06060606-0000-0000-0000-000000000001','2026-09-04')) s),(select training_load from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04')),'exercise breakdown equals total');
select ok((select bool_and(v>=previous) from (select (x->>1)::numeric v,lag((x->>1)::numeric) over(order by (x->>0)::bigint) previous from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04') t cross join lateral jsonb_array_elements(t.curve) x) points),'curve is monotonic');
delete from public.raw_samples where user_id='06060606-0000-0000-0000-000000000001' and ts>='2026-09-04';
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step) select '06060606-0000-0000-0000-000000000001','2026-09-04 10:00+00'::timestamptz + make_interval(hours=>block,mins=>tick*5),'UTC',165,500 from generate_series(0,2) block cross join generate_series(0,2) tick;
select is((select sum((s->>'delta')::numeric) from jsonb_array_elements(nb.compute_segments('06060606-0000-0000-0000-000000000001','2026-09-04')) s),(select training_load from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04')),'three isolated exercise blocks allocate rounding remainder');
insert into public.raw_samples(user_id,ts,sampled_tz,heart) values ('06060606-0000-0000-0000-000000000001','2026-09-04 13:00+00','UTC',60);
select is((select s->>'steps' from jsonb_array_elements(nb.compute_segments('06060606-0000-0000-0000-000000000001','2026-09-04')) s where (s->>'all_day')::boolean),null::text,'HR-only ordinary tick does not fabricate zero steps');
select ok((select bool_and((s->>'delta')::numeric>=0) and sum((s->>'delta')::numeric)=(select training_load from nb.compute_training('06060606-0000-0000-0000-000000000001','2026-09-04')) from jsonb_array_elements(nb.compute_segments('06060606-0000-0000-0000-000000000001','2026-09-04')) s),'zero movement remainder stays nonnegative and reconciles');
delete from public.raw_samples where user_id='06060606-0000-0000-0000-000000000001' and ts>='2026-09-04';
insert into public.raw_samples(user_id,ts,sampled_tz,cal,met)
select '06060606-0000-0000-0000-000000000001','2026-09-04 10:00+00'::timestamptz + make_interval(mins=>tick*5),'UTC',50000,3
from generate_series(0,11) tick;
select is((select active_kcal from nb.fuel_components('06060606-0000-0000-0000-000000000001','2026-09-04')),158,'one hour at 3 MET and 75 kg stays in kcal scale');
update public.raw_samples set cal=1000000 where user_id='06060606-0000-0000-0000-000000000001' and ts>='2026-09-04';
select is((select active_kcal from nb.fuel_components('06060606-0000-0000-0000-000000000001','2026-09-04')),158,'vendor cal counter never changes active kcal');
update public.raw_samples set met=26,step=500 where user_id='06060606-0000-0000-0000-000000000001' and ts>='2026-09-04';
select is((select active_kcal from nb.fuel_components('06060606-0000-0000-0000-000000000001','2026-09-04')),158,'out-of-range MET falls back to bounded steps estimate');
select ok(not has_function_privilege('authenticated','nb.fuel_components(uuid,date)','EXECUTE'),'clients cannot calculate another account energy directly');
select ok(not has_function_privilege('anon','nb.compute_fuel(uuid,date)','EXECUTE'),'anonymous clients cannot calculate another account fuel');
insert into auth.users(id) values ('06060606-0000-0000-0000-000000000003');
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date)
values('06060606-0000-0000-0000-000000000003','America/New_York','male',180,'1990-01-01')
on conflict(user_id) do update set timezone='America/New_York',sex='male',height_cm=180,birth_date='1990-01-01';
insert into public.weigh_ins(user_id,measured_at,weight_kg,source,client_op_id)
values('06060606-0000-0000-0000-000000000003','2026-03-06 09:00+00',75,'manual','06060606-0000-0000-0000-000000000004');
select set_config('nb.calculation_as_of','2026-03-08 08:00+00',true);
select is((select bmr_kcal from nb.fuel_components('06060606-0000-0000-0000-000000000003','2026-03-07')),1700,'23-hour spring user day ends at the full daily baseline');
select set_config('nb.calculation_as_of','2026-10-31 20:30+00',true);
select is((select bmr_kcal from nb.fuel_components('06060606-0000-0000-0000-000000000003','2026-10-31')),850,'half of the 25-hour autumn user day uses half the daily baseline');

-- Explicit strength modes use their observed live intervals in the same energy ledger.
insert into auth.users(id) values ('06060606-0000-0000-0000-000000000010');
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date)
values('06060606-0000-0000-0000-000000000010','UTC','male',180,'1990-01-01');
insert into public.weigh_ins(user_id,measured_at,weight_kg,source,client_op_id)
values('06060606-0000-0000-0000-000000000010','2026-09-01 09:00+00',75,'manual',
 '06060606-0000-0000-0000-000000000011');
select set_config('nb.calculation_as_of','2026-09-04 18:00+00',true);
insert into public.sport_energy_samples(user_id,id,session_id,continuity_id,
 observed_at,sport_mode,sampled_tz) values
 ('06060606-0000-0000-0000-000000000010','06060606-0000-0000-0000-000000000012',
  '06060606-0000-0000-0000-000000000013','06060606-0000-0000-0000-000000000014',
  '2026-09-04 12:00:00+00',25,'UTC'),
 ('06060606-0000-0000-0000-000000000010','06060606-0000-0000-0000-000000000015',
  '06060606-0000-0000-0000-000000000013','06060606-0000-0000-0000-000000000014',
  '2026-09-04 12:00:10+00',25,'UTC');
select is((select active_kcal from nb.fuel_components(
 '06060606-0000-0000-0000-000000000010','2026-09-04')),1,
 'observed weightlifting seconds produce net activity energy without steps or origin MET');
insert into public.sport_energy_samples(user_id,id,session_id,continuity_id,
 observed_at,sport_mode,sampled_tz) values
 ('06060606-0000-0000-0000-000000000010','06060606-0000-0000-0000-000000000016',
  '06060606-0000-0000-0000-000000000017','06060606-0000-0000-0000-000000000018',
  '2026-09-04 12:00:00+00',25,'UTC'),
 ('06060606-0000-0000-0000-000000000010','06060606-0000-0000-0000-000000000019',
  '06060606-0000-0000-0000-000000000017','06060606-0000-0000-0000-000000000018',
  '2026-09-04 12:00:10+00',25,'UTC');
select is((select active_kcal from nb.fuel_components(
 '06060606-0000-0000-0000-000000000010','2026-09-04')),1,
 'overlapping strength sessions own each second once');
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step,met)
values('06060606-0000-0000-0000-000000000010','2026-09-04 12:00+00','UTC',120,0,3);
select is((select active_kcal from nb.fuel_components(
 '06060606-0000-0000-0000-000000000010','2026-09-04')),13,
 'strength energy replaces the overlapping origin seconds instead of being added twice');
select ok(not has_function_privilege('authenticated','nb.strength_energy_ticks(uuid,date)','EXECUTE'),
 'clients cannot calculate another account strength energy directly');
select is((nb.energy_distribution('06060606-0000-0000-0000-000000000010','2026-09-04')->0->>'strength_weight')::numeric,
 25::numeric,'published curve retains 10 seconds of net 2.5 MET strength energy');
select is((nb.energy_distribution('06060606-0000-0000-0000-000000000010','2026-09-04')->0->>'origin_weight')::numeric,
 580::numeric,'published curve removes the same 10 seconds from the 2 net MET origin slot');
select * from finish();
rollback;
