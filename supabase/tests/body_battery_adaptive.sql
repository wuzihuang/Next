begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
select set_config('nb.calculation_as_of','2026-09-07 20:00+00',true);
select set_config('nb.calculation_day','2026-09-07',true);
create temporary table cohort as
 select name,md5('bb30/'||name)::uuid id from unnest(array[
 'rest','heart_only','elevated','strain','sleep','strained_sleep','temperature','oxygen','spike','missing']) name;
insert into auth.users(id) select id from cohort;
insert into profiles(user_id,timezone,birth_date) select id,'UTC','1990-01-01' from cohort;
insert into sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line)
 select c.id,d::date,420,0,420,d,d+interval '7 hours','1:420' from cohort c
 cross join generate_series('2026-09-01 00:00+00'::timestamptz,'2026-09-06 00:00+00',interval '1 day') d;
insert into raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met,temp)
 select c.id,t,'UTC',55,65,20,0,1,34 from cohort c
 join sleep_nights n on n.user_id=c.id
 cross join lateral generate_series(n.sleep_start,n.wake_at-interval '5 minutes',interval '5 minutes') t;
insert into raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met,temp)
 select c.id,d+t*interval '5 minutes','UTC',65,45,30,0,1,33 from cohort c
 cross join generate_series('2026-09-01 12:00+00'::timestamptz,'2026-09-06 12:00+00',interval '1 day') d
 cross join generate_series(0,23) t;
insert into daily_results(user_id,user_day,algo_version) select id,'2026-09-06',nb.calculation_version() from cohort;
insert into reserve_daily(result_id,user_id,current_value,drain_drivers)
 select d.id,d.user_id,60,jsonb_build_object('close_value',60,'assumed_anchor',false,'anchor_origin','fixture')
 from daily_results d join cohort c on c.id=d.user_id where d.user_day='2026-09-06';

-- Exact same stillness, different physiological responses. Missing is not calm.
insert into raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met,temp)
 select c.id,t,'UTC',case when c.name in ('elevated','strain') then 90 else 55 end,
  case when c.name='heart_only' then null when c.name='strain' then 18 else 50 end,
  case when c.name in ('heart_only','elevated') then null when c.name='strain' then 90 else 20 end,
  0,1,case when c.name='temperature' or (c.name='spike' and t='2026-09-07 08:30+00') then 34.5 else 33 end
 from cohort c cross join generate_series('2026-09-07 08:00+00'::timestamptz,'2026-09-07 19:55+00',interval '5 minutes') t
 where c.name not in ('sleep','strained_sleep','oxygen','missing');
-- A recorded daytime sleep interval uses its actual timestamps, with no night-only switch.
insert into sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line)
 select id,'2026-09-07',360,0,360,'2026-09-07 12:00+00','2026-09-07 18:00+00','1:360'
 from cohort where name in ('sleep','strained_sleep','oxygen');
insert into raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met,temp)
 select c.id,t,'UTC',case when c.name='strained_sleep' then 90 else 55 end,
  case when c.name='strained_sleep' then 20 else 65 end,case when c.name='strained_sleep' then 90 else 20 end,0,1,34
 from cohort c cross join generate_series('2026-09-07 12:00+00'::timestamptz,'2026-09-07 17:55+00',interval '5 minutes') t
 where c.name in ('sleep','strained_sleep','oxygen');
insert into oxygen_samples(user_id,ts,sampled_tz,spo2)
 select c.id,t,'UTC',92 from cohort c
 cross join generate_series('2026-09-07 12:00+00'::timestamptz,'2026-09-07 17:55+00',interval '5 minutes') t where c.name='oxygen';
create temporary table results as
 select c.name,c.id,r.* from cohort c cross join lateral nb.compute_reserve(c.id,'2026-09-07') r;
select diag(string_agg(name||'='||current_value,', ' order by name)) from results;
select cmp_ok((select current_value from results where name='rest'),'>',65::smallint,'sustained quiet daytime rest produces net charge');
select cmp_ok((select current_value from results where name='heart_only'),'>',60::smallint,'resting pulse plus movement evidence recovers without all autonomic channels');
select cmp_ok((select current_value from results where name='elevated'),'<',45::smallint,'non-exercise heart elevation consumes reserve below exercise zones');
select cmp_ok((select current_value from results where name='strain'),'<',20::smallint,'sustained severe strain can reach very low reserve');
select cmp_ok((select current_value from results where name='strained_sleep'),'<',60::smallint,'sleep with sustained severe strain may still lose reserve');
select cmp_ok((select current_value from results where name='sleep'),'>',70::smallint,'recorded daytime sleep charges');
select cmp_ok((select current_value from results where name='oxygen'),'<',(select current_value from results where name='sleep'),'persistent measured oxygen depression limits sleep recovery');
select cmp_ok((select current_value from results where name='temperature'),'<',(select current_value from results where name='rest'),'persistent personal skin-temperature elevation limits quiet recovery');
select is((select current_value from results where name='spike'),(select current_value from results where name='rest'),'one skin-temperature spike cannot change the score');
select is((select count(*) from results where name='missing'),0::bigint,'absent observations do not create a new battery reading');
select ok((select bool_and(abs(current_value-(drivers->>'anchor')::numeric-
 ((drivers->>'day_charge')::numeric+(drivers->>'awake')::numeric+(drivers->>'movement')::numeric+(drivers->>'stress')::numeric))<0.001)
 from results),'all published integer ledgers close, including empty reserve');
select is((select (drivers->'physiology_baseline'->>'day_hrv')::numeric from results where name='rest'),45::numeric,'daytime HRV uses daytime history');
select is((select (drivers->'physiology_baseline'->>'sleep_hrv')::numeric from results where name='rest'),65::numeric,'sleep HRV has a distinct baseline');
select is((select (drivers->'physiology_baseline'->>'resting_heart')::numeric from results where name='strained_sleep'),55::numeric,'today elevated resting pulse does not normalize itself');
select is((select (drivers->'physiology_baseline'->>'sleep_temperature')::numeric from results where name='rest'),34::numeric,'night skin temperature uses actual sleep context');
select is((select (drivers->'physiology_baseline'->>'day_temperature')::numeric from results where name='rest'),33::numeric,'day skin temperature does not use the warmer night baseline');
select cmp_ok((select (drivers->'training_target'->>'value')::numeric from results where name='strain'),'<',
 (select (drivers->'training_target'->>'value')::numeric from results where name='rest'),'current strain lowers the server-published reserve limit');
select is((select (drivers->'training_target'->>'remaining')::numeric from results where name='strain'),0::numeric,'no additional load is recommended once current guidance is exceeded');
select is((select (drivers->'training_target'->>'fresh')::boolean from results where name='sleep'),false,
 'a battery observation older than ninety minutes is explicitly stale');
-- An unrecorded future sample cannot change this as-of replay.
insert into raw_samples(user_id,ts,sampled_tz,heart,hrv,stress,step,met)
 select id,'2026-09-07 21:00+00','UTC',200,10,100,1000,15 from cohort where name='rest';
select is((select r.current_value from cohort c cross join lateral nb.compute_reserve(c.id,'2026-09-07') r where c.name='rest'),
 (select current_value from results where name='rest'),'future facts do not leak into current battery');
select ok(not has_function_privilege('anon','nb.reserve_baseline(uuid,date)','execute'),'anonymous clients cannot read personal baselines');
select ok(not has_function_privilege('authenticated','nb.reserve_replay_uncached(uuid,date)','execute'),'replay is private to the authorized settlement pipeline');
-- Fine sport observations contribute their bounded time even without origin ticks.
insert into sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sport_mode,sampled_tz)
 select c.id,gen_random_uuid(),md5('bb30/fine-session')::uuid,md5('bb30/fine-run')::uuid,
  '2026-09-07 19:00+00'::timestamptz+i*interval '10 seconds',150,1,'UTC'
 from cohort c cross join generate_series(0,180) i where c.name='missing';
create temporary table fine_result as select r.* from cohort c
 cross join lateral nb.compute_reserve(c.id,'2026-09-07') r where c.name='missing';
select cmp_ok((select current_value from fine_result),'<',60::smallint,'bounded sport HR alone drains the battery');
select cmp_ok((select current_value from fine_result),'>',35::smallint,'thirty observed minutes are not expanded into hours');
insert into sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sport_mode,sampled_tz)
 select c.id,gen_random_uuid(),md5('bb30/fine-session')::uuid,md5('bb30/fine-run')::uuid,
  '2026-09-07 19:00+00'::timestamptz+i*interval '10 seconds',150,1,'UTC'
 from cohort c cross join generate_series(0,180) i where c.name='missing';
select is((select r.current_value from cohort c cross join lateral nb.compute_reserve(c.id,'2026-09-07') r where c.name='missing'),
 (select current_value from fine_result),'repeated fine HR reports cannot bill the workout twice');
insert into sport_energy_samples(user_id,id,session_id,continuity_id,observed_at,sport_mode,sampled_tz)
 select c.id,gen_random_uuid(),md5('bb30/strength')::uuid,md5('bb30/strength-run')::uuid,
  '2026-09-07 19:00+00'::timestamptz+i*interval '10 seconds',25,'UTC'
 from cohort c cross join generate_series(0,180) i where c.name='rest';
select cmp_ok((select r.current_value from cohort c cross join lateral nb.compute_reserve(c.id,'2026-09-07') r where c.name='rest'),'<',
 (select current_value from results where name='rest'),'recorded strength activity prevents quiet charging despite low origin HR');
-- Complete but invalid historical measurements must not become a personal normal.
update raw_samples set heart=10,hrv=1000 where user_id=(select id from cohort where name='missing')
 and ts<'2026-09-07 00:00+00';
select is((select (nb.reserve_baseline(id,'2026-09-07')->>'resting_estimated')::boolean
 from cohort where name='missing'),true,'invalid historical resting pulse keeps the baseline explicitly estimated');
select is((select nb.reserve_baseline(id,'2026-09-07')->>'sleep_hrv'
 from cohort where name='missing'),null::text,'invalid historical HRV cannot become a recovery baseline');
select * from finish();
rollback;
