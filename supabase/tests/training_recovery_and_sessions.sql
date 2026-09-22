begin;
select plan(37);
insert into auth.users(id) values ('15150000-0000-4000-8000-000000000001');
insert into public.profiles(user_id,timezone,birth_date)
values ('15150000-0000-4000-8000-000000000001','UTC','1990-01-01');
select set_config('nb.calculation_as_of','2026-09-15 18:00+00',true);
select set_config('nb.calculation_day','2026-09-15',true);
insert into public.raw_samples(user_id,ts,sampled_tz,step,met)
values ('15150000-0000-4000-8000-000000000001','2026-09-15 09:00+00','UTC',0,1);
create temp table before_workout as
select * from nb.compute_training('15150000-0000-4000-8000-000000000001','2026-09-15');
-- A genuine 30-minute strength session, with no optical HR, steps or origin MET.
insert into public.sport_energy_samples(user_id,id,session_id,continuity_id,observed_at,sport_mode,sampled_tz)
select '15150000-0000-4000-8000-000000000001',gen_random_uuid(),
 '15150000-0000-4000-8000-000000000002','15150000-0000-4000-8000-000000000003',
 '2026-09-15 10:00+00'::timestamptz + i*interval '10 seconds',25,'UTC'
from generate_series(0,180) i;
select cmp_ok((select training_load from nb.compute_training('15150000-0000-4000-8000-000000000001','2026-09-15')),
 '>',(select training_load from before_workout),'recorded strength exercise increases today load without HR');
select is((nb.training_evidence('15150000-0000-4000-8000-000000000001','2026-09-15')->'sessions'->0->>'observed_seconds')::numeric,
 1800::numeric,'training publication identifies the actual recorded session duration');
select cmp_ok((nb.training_evidence('15150000-0000-4000-8000-000000000001','2026-09-15')->'sessions'->0->>'load_delta')::numeric,
 '>',0::numeric,'training publication exposes the positive session contribution');
insert into public.sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,wake_count,sleep_start,wake_at,sleep_line)
values ('15150000-0000-4000-8000-000000000001','2026-09-15',480,100,280,1,
 '2026-09-14 23:00+00','2026-09-15 07:00+00','0:100 1:280 2:100');
select nb.refresh_night_score('15150000-0000-4000-8000-000000000001','2026-09-15');
select ok((nb.training_evidence('15150000-0000-4000-8000-000000000001','2026-09-15')->'target'->>'target')::numeric>0,
 'a recorded completed night publishes a recovery-driven target');
select is((nb.training_evidence('15150000-0000-4000-8000-000000000001','2026-09-15')->'target'->>'sleep_minutes')::numeric,
 480::numeric,'the target exposes its sleep duration input');
select is((select (curve->-1->>1)::numeric from nb.compute_training('15150000-0000-4000-8000-000000000001','2026-09-15')),
 (select training_load from nb.compute_training('15150000-0000-4000-8000-000000000001','2026-09-15')),'curve endpoint agrees with the increased day load');
select is((select sum((s->>'delta')::numeric) from jsonb_array_elements(nb.compute_segments('15150000-0000-4000-8000-000000000001','2026-09-15')) s),
 (select training_load from nb.compute_training('15150000-0000-4000-8000-000000000001','2026-09-15')),'contribution rows still reconcile to the day load');

-- Appending a workout must leave the already-earned earlier contribution intact.
create temp table first_session as select nb.training_sessions('15150000-0000-4000-8000-000000000001','2026-09-15')->0 row;
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sport_mode,sampled_tz)
select '15150000-0000-4000-8000-000000000001',gen_random_uuid(),
 '15150000-0000-4000-8000-000000000004','15150000-0000-4000-8000-000000000005',
 '2026-09-15 11:00+00'::timestamptz+i*interval '10 seconds',140,1,'UTC' from generate_series(0,60) i;
select is((nb.training_sessions('15150000-0000-4000-8000-000000000001','2026-09-15')->0->>'load_delta')::numeric,
 (select (row->>'load_delta')::numeric from first_session),'later workouts do not retrospectively shrink the first workout share');
select is((nb.training_sessions('15150000-0000-4000-8000-000000000001','2026-09-15')->1->>'raw_load')::numeric,
 12::numeric,'ten-minute explicit cardio earns full intensity immediately without a night baseline');
select is(nb.training_evidence('15150000-0000-4000-8000-000000000001','2026-09-15')->>'hr_zone_method',
 'age_max_estimate','age fallback is identified separately from personal resting HR');
select is((nb.training_evidence('15150000-0000-4000-8000-000000000001','2026-09-15')->>'hr_rest')::numeric,
 null::numeric,'age fallback never fabricates a resting baseline');
select is((select sum((s->>'displayed_delta')::numeric) from jsonb_array_elements(nb.training_sessions('15150000-0000-4000-8000-000000000001','2026-09-15')) s),
 (select training_load from nb.compute_training('15150000-0000-4000-8000-000000000001','2026-09-15')),'sequential session increments add to the compressed day score');
-- The same strength intervals arriving in another upload do not count twice.
create temp table earned as select sum(raw) raw from nb.training_ledger('15150000-0000-4000-8000-000000000001','2026-09-15');
insert into public.sport_energy_samples(user_id,id,session_id,continuity_id,observed_at,sport_mode,sampled_tz)
select user_id,gen_random_uuid(),session_id,continuity_id,observed_at,sport_mode,sampled_tz
 from public.sport_energy_samples where user_id='15150000-0000-4000-8000-000000000001';
select is((select sum(raw) from nb.training_ledger('15150000-0000-4000-8000-000000000001','2026-09-15')),
 (select raw from earned),'duplicate upload preserves load exactly');
-- Coarse evidence already covering the session cannot add a second workout.
insert into public.raw_samples(user_id,ts,sampled_tz,step,met)
select '15150000-0000-4000-8000-000000000001','2026-09-15 10:00+00'::timestamptz+i*interval '5 minutes','UTC',0,3.5
from generate_series(0,5) i;
select is((select sum(raw) from nb.training_ledger('15150000-0000-4000-8000-000000000001','2026-09-15')),
 (select raw from earned),'overlapping origin and strength evidence are priced once');
select is((nb.training_sessions('15150000-0000-4000-8000-000000000001','2026-09-15')->0->>'observed_seconds')::numeric,
 1800::numeric,'replayed receipts and coarse rows never inflate session duration');
-- Sleep controls the base at the same wake reserve; the separate live-reserve cap
-- may mask that change in the final target, so test the base sensitivity directly.
create temp table rested_target as select nb.training_recovery_target('15150000-0000-4000-8000-000000000001','2026-09-15',80::smallint) t;
update public.night_score set recovery_score=15 where user_id='15150000-0000-4000-8000-000000000001';
create temp table low_recovery as select nb.training_recovery_target('15150000-0000-4000-8000-000000000001','2026-09-15',80::smallint) t;
update public.night_score set recovery_score=95 where user_id='15150000-0000-4000-8000-000000000001';
select cmp_ok((select (t->>'target')::numeric from low_recovery),'<',
 (nb.training_recovery_target('15150000-0000-4000-8000-000000000001','2026-09-15',80::smallint)->>'target')::numeric,
 'worse overnight recovery lowers the base with wake reserve held constant');
update public.night_score set inputs=jsonb_set(inputs,'{duration_min}','240'),duration_score=25
 where user_id='15150000-0000-4000-8000-000000000001';
select cmp_ok((nb.training_target('15150000-0000-4000-8000-000000000001','2026-09-15',100::smallint)->>'target')::numeric,
 '<=',8::numeric,'a four-hour night caps guidance despite high recovery and wake reserve');
select cmp_ok((nb.training_recovery_target('15150000-0000-4000-8000-000000000001','2026-09-15',80::smallint)->>'target')::numeric,
 '<',(select (t->>'target')::numeric from rested_target),'shorter sleep reduces the same-wake base');
select is(nb.training_target('15150000-0000-4000-8000-000000000001','2026-09-14',100::smallint)->>'target',
 null::text,'no completed night yields no sleep-led target even with a wake number');
select set_config('nb.calculation_as_of','2026-09-15 06:00+00',true);
select is(nb.training_target('15150000-0000-4000-8000-000000000001','2026-09-15',100::smallint)->>'target',
 null::text,'an unfinished night cannot use its future score');
select set_config('nb.calculation_as_of','2026-09-15 18:00+00',true);
-- A real settlement refreshes the score before publishing its target in the same revision.
select nb.settle_day('15150000-0000-4000-8000-000000000001','2026-09-15');
select is((select (t.evidence->'target'->>'sleep_minutes')::numeric from public.daily_training t
 join public.daily_results d on d.id=t.result_id where d.user_id='15150000-0000-4000-8000-000000000001' and d.user_day='2026-09-15'),
 480::numeric,'settlement publishes the fresh sleep score, not a prior cached score');
select is((select t.evidence->'target' from public.daily_training t join public.daily_results d on d.id=t.result_id
 where d.user_id='15150000-0000-4000-8000-000000000001' and d.user_day='2026-09-15'),
 nb.training_evidence('15150000-0000-4000-8000-000000000001','2026-09-15')->'target','published and replayed target inputs agree');
select is((select sum((s->>'delta')::numeric) from jsonb_array_elements(nb.compute_segments('15150000-0000-4000-8000-000000000001','2026-09-15')) s),
 (select training_load from nb.compute_training('15150000-0000-4000-8000-000000000001','2026-09-15')),'all segment rows reconcile after multiple sessions');
-- A cross-midnight interval, a pause and a long gap. No invented tails.
insert into auth.users(id) values ('15150000-0000-4000-8000-000000000010');
insert into public.profiles(user_id,timezone,birth_date) values ('15150000-0000-4000-8000-000000000010','UTC','1990-01-01');
insert into public.sport_energy_samples(user_id,id,session_id,continuity_id,observed_at,sport_mode,sampled_tz)
select '15150000-0000-4000-8000-000000000010',gen_random_uuid(),'15150000-0000-4000-8000-000000000011',
 '15150000-0000-4000-8000-000000000012','2026-09-14 23:59:55+00'::timestamptz+i*interval '10 seconds',25,'UTC'
from generate_series(0,1) i;
select is((nb.training_sessions('15150000-0000-4000-8000-000000000010','2026-09-15')->0->>'observed_seconds')::numeric,
 5::numeric,'cross-midnight session contributes only this day seconds');
select is((nb.training_sessions('15150000-0000-4000-8000-000000000010','2026-09-14')->0->>'observed_seconds')::numeric,
 5::numeric,'the preceding day owns the other five seconds');
insert into public.sport_energy_samples(user_id,id,session_id,continuity_id,observed_at,sport_mode,sampled_tz) values
 ('15150000-0000-4000-8000-000000000010',gen_random_uuid(),'15150000-0000-4000-8000-000000000011',
 '15150000-0000-4000-8000-000000000012','2026-09-15 00:00:21+00',25,'UTC'),
 ('15150000-0000-4000-8000-000000000010',gen_random_uuid(),'15150000-0000-4000-8000-000000000011',
 '15150000-0000-4000-8000-000000000013','2026-09-15 00:00:25+00',25,'UTC');
select is((nb.training_sessions('15150000-0000-4000-8000-000000000010','2026-09-15')->0->>'observed_seconds')::numeric,
 5::numeric,'pause and a gap above 15 seconds never earn load');
select cmp_ok((nb.training_sessions('15150000-0000-4000-8000-000000000010','2026-09-15')->0->>'load_delta')::numeric,
 '>',0::numeric,'a contribution below 0.1 remains available instead of vanishing');
select is((nb.training_sessions('15150000-0000-4000-8000-000000000010','2026-09-15')->0->>'displayed_delta')::numeric,
 0::numeric,'small contributions do not invent a tenth on the displayed ring');
select ok(not has_function_privilege('authenticated','nb.training_ledger(uuid,date)','execute'),'load ledger is not an arbitrary-user API');
select ok(not has_function_privilege('anon','nb.training_target(uuid,date,smallint)','execute'),'recovery guidance remains private');
select ok(not has_function_privilege('authenticated','nb.training_sessions(uuid,date)','execute'),'session attribution uses the account-scoped publication API');


-- Historical-load adjustment has a quality gate and excludes today's own work.
-- Synthetic published history isolates the recommendation from raw-data replay.
select nb.refresh_night_score('15150000-0000-4000-8000-000000000001','2026-09-15');
create temp table before_history as select nb.training_recovery_target('15150000-0000-4000-8000-000000000001','2026-09-15',80::smallint) t;
alter table public.daily_training disable trigger user;
insert into public.daily_results(user_id,user_day,training_load,algo_version)
select '15150000-0000-4000-8000-000000000001',d::date,case when d>='2026-09-12' then 18 else 4 end,nb.calculation_version()
from generate_series('2026-09-03'::date,'2026-09-14'::date,interval '1 day') d;
insert into public.daily_training(user_id,result_id,evidence)
select d.user_id,d.id,'{"recorded_minutes":900,"elapsed_minutes":1440}'::jsonb
from public.daily_results d where d.user_id='15150000-0000-4000-8000-000000000001' and d.user_day<'2026-09-15';
alter table public.daily_training enable trigger user;
create temp table heavy_history as select nb.training_recovery_target('15150000-0000-4000-8000-000000000001','2026-09-15',80::smallint) t;
select cmp_ok((select (t->>'target')::numeric from heavy_history),'<',
 (select (t->>'target')::numeric from before_history),'recent heavier completed days lower the sleep-led target');
select is((select (t->>'history_days')::integer from heavy_history),12,'target counts only eligible historical days');
update public.daily_results set training_load=20.9 where user_id='15150000-0000-4000-8000-000000000001' and user_day='2026-09-15';
select is(nb.training_recovery_target('15150000-0000-4000-8000-000000000001','2026-09-15',80::smallint)->>'target',
 (select t->>'target' from heavy_history),'today load never raises or lowers its own recovery baseline');
alter table public.daily_training disable trigger user;
update public.daily_training set evidence='{"recorded_minutes":30,"elapsed_minutes":1440}'::jsonb
 where result_id in(select id from public.daily_results where user_id='15150000-0000-4000-8000-000000000001' and user_day<'2026-09-15');
alter table public.daily_training enable trigger user;
select is(nb.training_recovery_target('15150000-0000-4000-8000-000000000001','2026-09-15',80::smallint)->>'target',
 (select t->>'target' from before_history),'sparse historical recording cannot lower the target as if it were a complete training day');
select ok((t->>'base_target')::numeric>0 and (t->>'target')::numeric>0
 and (t->>'target')::numeric<=(t->>'base_target')::numeric and (t->>'reserve_fresh')::boolean=false,
 'stale reserve retains labelled guidance at or below the completed-night base')
from (select nb.training_evidence('15150000-0000-4000-8000-000000000001','2026-09-15')->'target' t) q;

-- Non-overlapping exercise inside one five-minute bucket must not compete.
create temp table small_strength as select nb.training_sessions('15150000-0000-4000-8000-000000000010','2026-09-15')->0 s;
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sport_mode,sampled_tz)
select '15150000-0000-4000-8000-000000000010',gen_random_uuid(),
 '15150000-0000-4000-8000-000000000014','15150000-0000-4000-8000-000000000015',
 '2026-09-15 00:01:00+00'::timestamptz+i*interval '10 seconds',180,1,'UTC' from generate_series(0,1) i;
select is((nb.training_sessions('15150000-0000-4000-8000-000000000010','2026-09-15')->0->>'load_delta')::numeric,
 (select (s->>'load_delta')::numeric from small_strength),'later cardio in the same bucket never erases the earlier strength contribution');

select * from finish();
rollback;
