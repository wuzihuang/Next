-- Synthetic regression fixtures. All facts and calculated outputs roll back.
begin;
select no_plan();
select set_config('nb.calculation_as_of','2026-09-04 10:00+00',true);
select set_config('nb.calculation_day','2026-09-04',true);
insert into auth.users(id) values
 ('96170800-0000-4000-8000-000000000001'),
 ('96170800-0000-4000-8000-000000000002'),
 ('96170800-0000-4000-8000-000000000003');
insert into public.profiles(user_id,timezone,birth_date) values
 ('96170800-0000-4000-8000-000000000001','UTC','1996-01-01'),
 ('96170800-0000-4000-8000-000000000002','UTC','1996-01-01'),
 ('96170800-0000-4000-8000-000000000003','UTC','1996-01-01')
on conflict(user_id) do update set timezone='UTC',birth_date='1996-01-01';

insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line) values
 ('96170800-0000-4000-8000-000000000001','2026-09-04',300,300,0,'2026-09-04 04:06+00','2026-09-04 09:11+00','0:30,4:5,0:270'),
 ('96170800-0000-4000-8000-000000000002','2026-09-04',360,360,0,'2026-09-03 21:00+00','2026-09-04 03:00+00','0:360');
create temporary table morning_targets as
 select p.user_id,c.wake_value,c.current_value,nb.target_load(c.wake_value) target
 from public.profiles p cross join lateral nb.compute_reserve(p.user_id,'2026-09-04') c
 where p.user_id in ('96170800-0000-4000-8000-000000000001','96170800-0000-4000-8000-000000000002');
select is((select wake_value from morning_targets where user_id='96170800-0000-4000-8000-000000000001'),
 (select round(value)::smallint from nb.reserve_replay('96170800-0000-4000-8000-000000000001','2026-09-04') where ts='2026-09-04 09:10+00'),
 'late sleep and a nighttime awakening use the actual final wake bucket');
select ok((select wake_value is not null from morning_targets where user_id='96170800-0000-4000-8000-000000000002'),
 'a wake in the small hours still supplies the morning target');
-- ADR 0020 · the user day opens at midnight, so a 03:00 wake is this day's own. It used
-- to fall on the far side of the 04:00 seam and had to be read from the preceding day.
select is((select wake_value from morning_targets where user_id='96170800-0000-4000-8000-000000000002'),
 (select round(value)::smallint from nb.reserve_replay('96170800-0000-4000-8000-000000000002','2026-09-04') where ts='2026-09-04 02:55+00'),
 'a small-hours wake is found in this user day replay, not the preceding one');

insert into public.raw_samples(user_id,ts,sampled_tz,heart,step,met)
 select p.user_id,t,'UTC',150,200,2 from public.profiles p
 cross join generate_series('2026-09-04 10:00+00'::timestamptz,'2026-09-04 17:55+00'::timestamptz,interval '5 minutes') t
 where p.user_id in ('96170800-0000-4000-8000-000000000001','96170800-0000-4000-8000-000000000002');
select set_config('nb.calculation_as_of','2026-09-04 18:00+00',true);
select ok((select bool_and(c.current_value<m.current_value) from morning_targets m
 cross join lateral nb.compute_reserve(m.user_id,'2026-09-04') c),'daytime activity changes current reserve');
select ok((select bool_and(c.wake_value=m.wake_value and nb.target_load(c.wake_value)=m.target)
 from morning_targets m cross join lateral nb.compute_reserve(m.user_id,'2026-09-04') c),
 'daytime drain cannot move either morning target');
select is((select wake_value from nb.compute_reserve('96170800-0000-4000-8000-000000000003','2026-09-04')),
 null::smallint,'no recorded night cannot borrow current reserve as a target');

-- A duplicate source row must not manufacture a second baseline night.
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line)
 select user_id,'2026-09-03',total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line
 from public.sleep_nights where user_id='96170800-0000-4000-8000-000000000001' and user_day='2026-09-04';
select is((select count(*) from nb.canonical_sleep_nights('96170800-0000-4000-8000-000000000001','2026-09-02','2026-09-04')),1::bigint,
 'one real night filed under two dates remains one night');
select is((select count(*) from nb.night_evidence('96170800-0000-4000-8000-000000000001','2026-09-02','2026-09-04')),1::bigint,
 'training baseline adapter also reads the canonical night');

-- Three genuine hour-long nights establish HRR; a single tiny fragment does not.
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line)
 select '96170800-0000-4000-8000-000000000003',d::date,60,60,0,d,d+interval '1 hour','0:60'
 from generate_series('2026-08-25 00:00+00'::timestamptz,'2026-08-27 00:00+00'::timestamptz,interval '1 day') d;
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv)
 select n.user_id,t,'UTC',60,60 from public.sleep_nights n
 cross join lateral generate_series(n.sleep_start,n.wake_at-interval '5 minutes',interval '5 minutes') t
 where n.user_id='96170800-0000-4000-8000-000000000003';
select is(nb.hr_rest('96170800-0000-4000-8000-000000000003','2026-09-04','UTC'),60::numeric,
 'three qualified nights establish a measured resting baseline');
select is((select nights from nb.hr_rest_details('96170800-0000-4000-8000-000000000003','2026-09-04','UTC')),3,
 'baseline count contains independent qualified nights');
select is((select estimated from nb.hr_rest_details('96170800-0000-4000-8000-000000000003','2026-09-04','UTC')),false,
 'qualified preceding-week baseline is frozen for the week');
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line)
 values('96170800-0000-4000-8000-000000000003','2026-08-28',60,60,0,'2026-08-28 00:00+00','2026-08-28 01:00+00','0:60');
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv)
 values('96170800-0000-4000-8000-000000000003','2026-08-28 00:00+00','UTC',30,20);
select is((select nights from nb.hr_rest_details('96170800-0000-4000-8000-000000000003','2026-09-04','UTC')),3,
 'one five-minute reading is not an adequate baseline night');
select is(nb.hr_rest('96170800-0000-4000-8000-000000000001','2026-09-04','UTC'),null::numeric,
 'insufficient nights stay unknown instead of supplying a made-up HRR baseline');

insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line)
 select '96170800-0000-4000-8000-000000000003',d::date,60,60,0,d,d+interval '1 hour','0:60'
 from unnest(array['2026-08-29 00:00+00'::timestamptz,'2026-08-30 00:00+00'::timestamptz]) d;
-- ADR 0020 · this night is a Body Battery input, not a training observation. It ends
-- exactly at midnight so its readings stay outside 2026-09-04's own coverage window and
-- test 21 below keeps isolating the four training ticks. Before the seam moved, an
-- 00:00-01:00 night was already on the far side of it.
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line)
 values('96170800-0000-4000-8000-000000000003','2026-09-04',60,60,0,'2026-09-03 23:00+00','2026-09-04 00:00+00','0:60');
insert into public.raw_samples(user_id,ts,sampled_tz,heart,hrv)
 select n.user_id,t,'UTC',case when n.user_day='2026-09-04' then 90 else 60 end,
 case when n.user_day='2026-09-04' then 20 else 60 end from public.sleep_nights n
 cross join lateral generate_series(n.sleep_start,n.wake_at-interval '5 minutes',interval '5 minutes') t
 where n.user_id='96170800-0000-4000-8000-000000000003' and n.user_day in('2026-08-29','2026-08-30','2026-09-04');
select is(nb.charge_multiplier('96170800-0000-4000-8000-000000000003','2026-09-04','UTC'),0.65::numeric,
 'a constant qualified baseline still responds to a measured adverse change');
select is(nb.night_inputs('96170800-0000-4000-8000-000000000003','2026-09-04')->>'rhr_nights','5',
 'UI night count retains shared quality gates');
select ok(nb.night_inputs('96170800-0000-4000-8000-000000000003','2026-09-04') ? 'rhr_coverage',
 'training changes preserve Body Battery coverage details');
select is(nb.hr_rest('96170800-0000-4000-8000-000000000003','2026-09-04','UTC'),60::numeric,
 'current night does not silently replace the frozen exercise baseline');

-- Mid-night, before this night's 00:00 wake. The instant sits ahead of the user day it
-- is asked about, exactly as the old 00:30-against-an-04:00-seam fixture did.
select set_config('nb.calculation_as_of','2026-09-03 23:30+00',true);
select is(nb.charge_multiplier('96170800-0000-4000-8000-000000000003','2026-09-04','UTC'),1::numeric,
 'an unfinished night cannot be used as a completed recovery input');
select set_config('nb.calculation_as_of','2026-09-04 18:00+00',true);
-- Exercise segmentation must never remove steps from the published daily total.
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step,met)
 select '96170800-0000-4000-8000-000000000003',t,'UTC',185,100,2
 from generate_series('2026-09-04 10:00+00'::timestamptz,'2026-09-04 10:10+00'::timestamptz,interval '5 minutes') t;
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step,met)
 values('96170800-0000-4000-8000-000000000003','2026-09-04 12:00+00','UTC',60,50,1);
select nb.settle_day('96170800-0000-4000-8000-000000000003','2026-09-04');
select is((select t.recorded_steps from public.daily_training t join public.daily_results d on d.id=t.result_id
 where d.user_id='96170800-0000-4000-8000-000000000003' and d.user_day='2026-09-04'),350,
 'normal settlement publishes steps from exercise and ordinary activity');
select is((select (s->>'steps')::integer from public.daily_training t join public.daily_results d on d.id=t.result_id
 cross join lateral jsonb_array_elements(t.segments) s
 where d.user_id='96170800-0000-4000-8000-000000000003' and d.user_day='2026-09-04' and (s->>'all_day')::boolean),50,
 'ordinary segment remains a subtotal, distinct from all-day recorded steps');
select is((select (t.evidence->>'recorded_minutes')::integer from public.daily_training t join public.daily_results d on d.id=t.result_id
 where d.user_id='96170800-0000-4000-8000-000000000003' and d.user_day='2026-09-04'),20,
 'normal settlement publishes coverage from the same training observations');
select ok(not has_function_privilege('authenticated','nb.hr_rest_details(uuid,date,text)','EXECUTE'),
 'clients cannot inspect another account baseline directly');
select ok(not has_function_privilege('anon','nb.training_evidence(uuid,date)','EXECUTE'),
 'anonymous clients cannot read training evidence directly');
-- ⚠️ These two used to grep `nb.settle_day` and `public.calculation_status` for the literal
-- `tl-2.2`. 20260908150000 moved the whole judgement into `nb.calculation_result_is_current`,
-- which compares a stored `algo_version` against `nb.calculation_version()`; neither of those
-- two bodies carries a version string any more, so the greps were asserting about a mechanism
-- that no longer exists. What they were for is asserted directly instead.
select ok(position('tl-2.2' in nb.calculation_version())>0,
 'published training has a distinct algorithm revision');
create or replace function pg_temp.settled_is_current(p_user uuid, p_day date) returns boolean
language sql as $$
 select nb.calculation_result_is_current(d, null::date, d.profile_revision,
   (select b.ends_at from nb.calculation_profile(p_user,p_day) p
     cross join lateral nb.user_day_bounds(p_day,p.timezone) b),
   nb.calculation_clock())
 from public.daily_results d where d.user_id=p_user and d.user_day=p_day;
$$;
-- ⚠️ A row settled by calling `nb.settle_day` directly carries a null `profile_revision`
-- (only `nb.recompute_range` sets `nb.profile_revision`), and a null never equals anything,
-- so such a row is never "current" whatever its version says. What the settle does own is
-- the stamp itself.
select is((select d.algo_version from public.daily_results d
  where d.user_id='96170800-0000-4000-8000-000000000003' and d.user_day='2026-09-04'),
 nb.calculation_version(), 'a settled day is stamped with the revision that settled it');
update public.daily_results set algo_version=replace(algo_version,'tl-2.2','tl-2.1')
 where user_id='96170800-0000-4000-8000-000000000003' and user_day='2026-09-04';
select ok(not pg_temp.settled_is_current('96170800-0000-4000-8000-000000000003','2026-09-04'),
 'old completed-day training remains pending until recomputed');
select * from finish();
rollback;
