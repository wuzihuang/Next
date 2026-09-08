begin;
select plan(48);
insert into auth.users(id) values ('09060606-0000-0000-0000-000000000001');
insert into public.profiles(user_id,timezone,birth_date) values ('09060606-0000-0000-0000-000000000001','UTC','1990-01-01')
on conflict(user_id) do update set timezone='UTC',birth_date='1990-01-01';
select set_config('nb.calculation_as_of','2026-09-04 18:00+00',true);
select set_config('nb.calculation_day','2026-09-04',true);
select is((select training_load from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),null::numeric,'no data leaves training unknown');
select is((select coverage from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),0::numeric,'no data is zero coverage');
select is((select zone_minutes from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),null::smallint[],'unknown zones are not zero minutes');
-- Real sample timestamps; the second report proves only the preceding ten seconds.
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sampled_tz)
select '09060606-0000-0000-0000-000000000001',('09060606-1000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
'09060606-0000-0000-0000-000000000002','09060606-0000-0000-0000-000000000003',
'2026-09-04 10:00+00'::timestamptz+make_interval(secs=>i*10),200,'UTC' from generate_series(0,1) i;
select is((select sum(extract(epoch from(ends_at-starts_at))) from nb.training_heart_intervals('09060606-0000-0000-0000-000000000001','2026-09-04')),10::numeric,'two live reports establish ten seconds only');
select is((select training_load from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),null::numeric,'high frequency without resting baseline does not fabricate HRR');
select is((nb.training_evidence('09060606-0000-0000-0000-000000000001','2026-09-04')->>'hr_seconds')::numeric,10::numeric,'HR evidence survives unavailable baseline');
select is(nb.training_evidence('09060606-0000-0000-0000-000000000001','2026-09-04')->>'baseline_estimated','true','missing baseline is explicitly estimated');
-- Three actual one-hour sleep nights establish a qualified resting baseline.
insert into public.sleep_nights(user_id,user_day,total_minutes,sleep_start,wake_at,sleep_line)
select '09060606-0000-0000-0000-000000000001',d::date,60,d,d+interval '1 hour','1:60'
from generate_series('2026-08-25 00:00+00'::timestamptz,'2026-08-27 00:00+00'::timestamptz,interval '1 day') d;
insert into public.raw_samples(user_id,ts,sampled_tz,heart)
select '09060606-0000-0000-0000-000000000001',d+make_interval(mins=>tick*5),'UTC',60
from generate_series('2026-08-25 00:00+00'::timestamptz,'2026-08-27 00:00+00'::timestamptz,interval '1 day') d
cross join generate_series(0,11) tick;
select is(nb.hr_rest('09060606-0000-0000-0000-000000000001','2026-09-04','UTC'),60::numeric,'three observed sleep nights qualify resting HR');
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),0.25::numeric,'ten seconds in zone five is everyday movement: a quarter of 6 times 10/60');
select is((select training_load from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),0.1::numeric,'same existing nonlinear load conversion follows integration');
select is((select zone_minutes from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),array[0,0,0,0,0]::smallint[],'sub-minute evidence is never counted as five whole minutes');
select is((select zone_seconds[6] from nb.training_load_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),10::numeric,'exact zone seconds retained');
select is((select peak_hr from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),200::smallint,'live HR contributes actual peak');
-- Duplicate coverage from another workout session cannot double the contribution.
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sampled_tz)
select '09060606-0000-0000-0000-000000000001',('09060606-2000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
'09060606-0000-0000-0000-000000000004','09060606-0000-0000-0000-000000000005',
'2026-09-04 10:00+00'::timestamptz+make_interval(secs=>i*10),200,'UTC' from generate_series(0,1) i;
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),0.25::numeric,'overlapping sessions are counted once');
-- A later-started lower-HR interval overrides only the overlap.
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sampled_tz)
select '09060606-0000-0000-0000-000000000001',('09060606-3000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
'09060606-0000-0000-0000-000000000006','09060606-0000-0000-0000-000000000007',
'2026-09-04 10:00:05+00'::timestamptz+make_interval(secs=>i*10),60,'UTC' from generate_series(0,1) i;
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),0.125::numeric,'partial overlap chooses a single latest-start observation');
select is((nb.training_evidence('09060606-0000-0000-0000-000000000001','2026-09-04')->>'hr_seconds')::numeric,15::numeric,'overlap coverage is its union');
-- A full coarse slot already includes these 15 seconds: replace, do not append.
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step,met)
values('09060606-0000-0000-0000-000000000001','2026-09-04 10:00+00','UTC',200,500,3);
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),7.25::numeric,'fine HR replaces ten coarse high-HR seconds and MET is max once');
select is((nb.training_evidence('09060606-0000-0000-0000-000000000001','2026-09-04')->>'recorded_seconds')::numeric,300::numeric,'coarse and fine observation coverage do not add');
select is((nb.training_evidence('09060606-0000-0000-0000-000000000001','2026-09-04')->>'movement_seconds')::numeric,300::numeric,'coarse movement keeps its own single slot');
update public.raw_samples set heart=60,step=0,met=25 where user_id='09060606-0000-0000-0000-000000000001' and ts='2026-09-04 10:00+00';
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),2.25::numeric,'stronger movement contribution wins instead of adding to fine HR');
-- Incomplete and future coarse slots cannot affect score, evidence or steps.
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step,met) values
('09060606-0000-0000-0000-000000000001','2026-09-04 17:58+00','UTC',200,900,25),
('09060606-0000-0000-0000-000000000001','2026-09-04 18:05+00','UTC',200,900,25);
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),2.25::numeric,'future and unfinished coarse values excluded');
select is((select sum(steps) from nb.training_observations('09060606-0000-0000-0000-000000000001','2026-09-04')),0::bigint,'unfinished slot steps excluded by the same source');
-- Isolated, paused, and >15-second-separated observations prove no extra interval.
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sampled_tz) values
('09060606-0000-0000-0000-000000000001','09060606-4000-0000-0000-000000000001','09060606-0000-0000-0000-000000000008','09060606-0000-0000-0000-000000000009','2026-09-04 11:00+00',200,'UTC'),
('09060606-0000-0000-0000-000000000001','09060606-4000-0000-0000-000000000002','09060606-0000-0000-0000-000000000008','09060606-0000-0000-0000-000000000009','2026-09-04 11:00:16+00',200,'UTC'),
('09060606-0000-0000-0000-000000000001','09060606-4000-0000-0000-000000000003','09060606-0000-0000-0000-000000000008','09060606-0000-0000-0000-000000000010','2026-09-04 11:00:20+00',220,'UTC'),
('09060606-0000-0000-0000-000000000001','09060606-4000-0000-0000-000000000004','09060606-0000-0000-0000-000000000008','09060606-0000-0000-0000-000000000010','2026-09-04 18:00:05+00',200,'UTC');
select is((select sum(extract(epoch from(ends_at-starts_at))) from nb.training_heart_intervals('09060606-0000-0000-0000-000000000001','2026-09-04')),15::numeric,'pause, long gap, lone report and future sample establish no added coverage');
select is((select peak_hr from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),220::smallint,'lone report remains a peak observation without fabricated duration');
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),2.25::numeric,'report-only peak cannot increase load');
-- Cross-bucket integration is clipped exactly, including the 04:00 day boundary.
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sampled_tz)
select '09060606-0000-0000-0000-000000000001',('09060606-5000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
'09060606-0000-0000-0000-000000000011','09060606-0000-0000-0000-000000000012',
'2026-09-04 03:59:55+00'::timestamptz+make_interval(secs=>i*10),200,'UTC' from generate_series(0,1) i;
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04') where ts='2026-09-04 04:00+00'),0.125::numeric,'day start receives only five seconds from crossing interval');
-- Positive scores, curves and breakdown all consume this ledger.
select is((select (curve->-1->>1)::numeric from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),
(select training_load from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),'curve endpoint equals daily score');
select is((select sum((s->>'delta')::numeric) from jsonb_array_elements(nb.compute_segments('09060606-0000-0000-0000-000000000001','2026-09-04')) s),
(select training_load from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),'segment deltas equal daily score');
select ok((select bool_and(t.raw>=0) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04') t),'all contributions remain nonnegative');
-- A zero-filled coarse row does not prove either wear or movement coverage.
delete from public.raw_samples where user_id='09060606-0000-0000-0000-000000000001' and ts>='2026-09-04';
delete from public.sport_heart_rate_samples where user_id='09060606-0000-0000-0000-000000000001';
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step,met)
values('09060606-0000-0000-0000-000000000001','2026-09-04 10:00+00','UTC',0,0,0);
select is((select training_load from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),0::numeric,'known zero movement remains zero score');
select is((select coverage from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),0::numeric,'zero-filled rows never imply full evidence');
select is((select curve from nb.compute_training('09060606-0000-0000-0000-000000000001','2026-09-04')),'[]'::jsonb,'zero-filled placeholders cannot bridge missing curve intervals');
select is((nb.training_evidence('09060606-0000-0000-0000-000000000001','2026-09-04')->>'hr_seconds')::numeric,0::numeric,'zero HR is not a measurement');
select is((nb.training_evidence('09060606-0000-0000-0000-000000000001','2026-09-04')->>'movement_seconds')::numeric,0::numeric,'zero slots are not movement coverage');
update public.raw_samples set heart=60 where user_id='09060606-0000-0000-0000-000000000001' and ts='2026-09-04 10:00+00';
select is((nb.training_evidence('09060606-0000-0000-0000-000000000001','2026-09-04')->>'movement_seconds')::numeric,0::numeric,'HR-only row does not invent movement coverage');
select is((nb.training_evidence('09060606-0000-0000-0000-000000000001','2026-09-04')->>'hr_seconds')::numeric,300::numeric,'valid coarse HR covers its completed five-minute slot');
-- A sparse high-HR point in three buckets cannot become a 15-minute workout.
delete from public.raw_samples where user_id='09060606-0000-0000-0000-000000000001' and ts>='2026-09-04';
insert into public.sport_heart_rate_samples(user_id,id,session_id,continuity_id,observed_at,heart_rate,sampled_tz)
select '09060606-0000-0000-0000-000000000001',('09060606-6000-0000-0000-'||lpad((k*10+i)::text,12,'0'))::uuid,
'09060606-0000-0000-0000-000000000011',('09060606-6000-0000-0000-'||lpad(k::text,12,'0'))::uuid,
'2026-09-04 10:00+00'::timestamptz+make_interval(mins=>k*5,secs=>i*10),200,'UTC'
from generate_series(0,2) k cross join generate_series(0,1) i;
select ok(not exists(select 1 from jsonb_array_elements(nb.compute_segments('09060606-0000-0000-0000-000000000001','2026-09-04')) s where (s->>'all_day')::boolean=false),'three sparse buckets do not claim a 15-minute HR block');
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),0.75::numeric,'three ten-second bursts retain their actual load');
select ok(not has_function_privilege('authenticated','nb.training_load_ticks(uuid,date)','EXECUTE'),'new ledger is not an arbitrary-user client API');
select ok(not has_function_privilege('anon','nb.training_heart_intervals(uuid,date)','EXECUTE'),'fine HR helper stays private');
-- #23 · everyday movement and a real session are not the same rate. A tick earns its
-- full weight only inside a sustained block: a contiguous run of elevated ticks holding
-- at least fifteen minutes of elevated time, the same rule the segment ledger draws with.
delete from public.raw_samples where user_id='09060606-0000-0000-0000-000000000001' and ts>='2026-09-04';
delete from public.sport_heart_rate_samples where user_id='09060606-0000-0000-0000-000000000001';
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step,met)
select '09060606-0000-0000-0000-000000000001','2026-09-04 10:00+00'::timestamptz+make_interval(mins=>i*5),'UTC',200,0,1
from generate_series(0,1) i;
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),15::numeric,'ten elevated minutes stay everyday movement at a quarter weight');
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step,met)
select '09060606-0000-0000-0000-000000000001','2026-09-04 10:10+00'::timestamptz+make_interval(mins=>i*5),'UTC',200,0,1
from generate_series(0,1) i;
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),120::numeric,'twenty unbroken elevated minutes are a session and carry full weight');
delete from public.raw_samples where user_id='09060606-0000-0000-0000-000000000001' and ts>='2026-09-04';
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step,met)
values('09060606-0000-0000-0000-000000000001','2026-09-04 10:00+00','UTC',null,0,3);
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),0.1875::numeric,'movement with no heart-rate block is everyday movement');
-- #23 · the threshold sits at zone 2, not zone 1. Resting 60, max 183: 100 bpm is a
-- 33% reserve (Z1, 日常走动) and 115 bpm is 45% (Z2). An afternoon of moving furniture is
-- an unbroken run of Z1 and must not be paid like a session, or an ordinary working day
-- reaches 9.9 out of 21 — which is the defect this rule exists to remove.
delete from public.raw_samples where user_id='09060606-0000-0000-0000-000000000001' and ts>='2026-09-04';
insert into public.raw_samples(user_id,ts,sampled_tz,heart,step,met)
select '09060606-0000-0000-0000-000000000001','2026-09-04 10:00+00'::timestamptz+make_interval(mins=>i*5),'UTC',100,0,1
from generate_series(0,3) i;
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),0.75::numeric,'twenty unbroken minutes of zone one are labour, not a session');
select ok(not exists(select 1 from jsonb_array_elements(nb.compute_segments('09060606-0000-0000-0000-000000000001','2026-09-04')) s where (s->>'all_day')::boolean=false),'a zone-one run draws no ELEVATED HR block either');
update public.raw_samples set heart=115 where user_id='09060606-0000-0000-0000-000000000001'
 and ts>='2026-09-04 10:05+00' and ts<='2026-09-04 10:15+00';
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),8.25::numeric,'fifteen minutes of zone two inside the same run makes it a session');
select is((select count(*) from jsonb_array_elements(nb.compute_segments('09060606-0000-0000-0000-000000000001','2026-09-04')) s where (s->>'all_day')::boolean=false),1::bigint,'the block the card draws is the block the ledger paid for');
update public.raw_samples set heart=115 where user_id='09060606-0000-0000-0000-000000000001' and ts='2026-09-04 10:00+00';
update public.raw_samples set heart=100 where user_id='09060606-0000-0000-0000-000000000001' and ts='2026-09-04 10:05+00';
select is((select sum(raw) from nb.activity_ticks('09060606-0000-0000-0000-000000000001','2026-09-04')),8.25::numeric,'a dip to zone one inside a session does not split it');
select * from finish();
rollback;
