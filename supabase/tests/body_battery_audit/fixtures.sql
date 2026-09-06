-- Synthetic observations; no user data. Production functions come from build_harness.py.
create table audit_observations(name text primary key, value jsonb not null);
insert into profiles values
('00000000-0000-0000-0000-000000000001','UTC',null),
('00000000-0000-0000-0000-000000000002','UTC',null),
('00000000-0000-0000-0000-000000000003','UTC',null),
('00000000-0000-0000-0000-000000000004','UTC',null),
('00000000-0000-0000-0000-000000000005','UTC',null);
insert into sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line) values
('00000000-0000-0000-0000-000000000001','2026-09-04',240,240,0,'2026-09-04 04:00Z','2026-09-04 08:00Z','0:240'),
('00000000-0000-0000-0000-000000000002','2026-09-04',235,235,0,'2026-09-04 04:00Z','2026-09-04 08:00Z','0:30,4:5,0:205'),
('00000000-0000-0000-0000-000000000003','2026-09-04',360,360,0,'2026-09-03 21:00Z','2026-09-04 03:00Z','0:360'),
('00000000-0000-0000-0000-000000000004','2026-09-04',480,480,0,'2026-09-03 22:00Z','2026-09-04 06:00Z','0:480');
insert into audit_observations select 'unbroken_4h',to_jsonb(r) from nb.compute_reserve('00000000-0000-0000-0000-000000000001','2026-09-04')r;
insert into audit_observations select 'wake_5min_then_sleep',to_jsonb(r) from nb.compute_reserve('00000000-0000-0000-0000-000000000002','2026-09-04')r;
do $$ begin perform nb.audit_save('00000000-0000-0000-0000-000000000003','2026-09-03'); end $$;
insert into raw_samples(user_id,ts,heart,stress,met) select '00000000-0000-0000-0000-000000000003',t,100,50,1 from generate_series('2026-09-04 06:00Z'::timestamptz,'2026-09-04 06:55Z'::timestamptz,interval '5min') t;
insert into audit_observations select 'early_wake_read_0700',to_jsonb(r) from nb.compute_reserve('00000000-0000-0000-0000-000000000003','2026-09-04')r;
insert into raw_samples(user_id,ts,heart,stress,met) select '00000000-0000-0000-0000-000000000003',t,100,50,1 from generate_series('2026-09-04 07:00Z'::timestamptz,'2026-09-04 16:55Z'::timestamptz,interval '5min') t;
insert into audit_observations select 'early_wake_read_1700',to_jsonb(r) from nb.compute_reserve('00000000-0000-0000-0000-000000000003','2026-09-04')r;
insert into audit_observations select 'first_night_prior_day_anchor',jsonb_build_object('anchor',nb.reserve_anchor('00000000-0000-0000-0000-000000000004','2026-09-03'));
do $$ begin perform nb.audit_save('00000000-0000-0000-0000-000000000004','2026-09-03'); end $$;
insert into audit_observations select 'first_night_8h_result',to_jsonb(r) from nb.compute_reserve('00000000-0000-0000-0000-000000000004','2026-09-04')r;
insert into audit_observations select 'first_night_8h_expected_from20',jsonb_build_object('value',95-(95-20)*exp(-0.011*1.25*96));
insert into raw_samples(user_id,ts,heart,stress,step,met) select '00000000-0000-0000-0000-000000000005',t,55,20,0,1 from generate_series('2026-09-04 04:00Z'::timestamptz,'2026-09-04 05:55Z'::timestamptz,interval '5min') t;
insert into audit_observations select 'quiet_120min',to_jsonb(r) from nb.compute_reserve('00000000-0000-0000-0000-000000000005','2026-09-04')r;

insert into profiles values
('00000000-0000-0000-0000-000000000006','UTC',null),
('00000000-0000-0000-0000-000000000007','UTC',null),
('00000000-0000-0000-0000-000000000008','UTC',null),
('00000000-0000-0000-0000-000000000009','UTC',null);
insert into sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line) values
('00000000-0000-0000-0000-000000000006','2026-09-04',240,240,0,'2026-09-04 04:00Z','2026-09-04 08:00Z','BROKEN'),
('00000000-0000-0000-0000-000000000007','2026-09-04',240,240,0,'2026-09-04 04:00Z','2026-09-04 08:00Z',null),
('00000000-0000-0000-0000-000000000008','2026-09-04',240,240,0,'2026-09-04 04:00Z','2026-09-04 10:00Z',null);
insert into audit_observations select 'malformed_line_disables_fallback',jsonb_build_object('count',count(*)) from nb.reserve_replay('00000000-0000-0000-0000-000000000006','2026-09-04');
insert into audit_observations select '4h_sleep_in_4h_window',to_jsonb(r) from nb.compute_reserve('00000000-0000-0000-0000-000000000007','2026-09-04')r;
insert into audit_observations select '4h_sleep_in_6h_window',to_jsonb(r) from nb.compute_reserve('00000000-0000-0000-0000-000000000008','2026-09-04')r;
insert into sleep_nights(user_id,user_day,total_minutes,deep_minutes,sleep_start,wake_at,sleep_line)
select '00000000-0000-0000-0000-000000000009',d::date,480,480,d+'04:00'::time,d+'12:00'::time,'0:480' from generate_series('2026-08-21'::date,'2026-09-04'::date,interval '1 day')d;
insert into raw_samples(user_id,ts,heart,hrv)
select '00000000-0000-0000-0000-000000000009',d+'05:00'::time,case when d::date='2026-09-04' then 90 else 60 end,case when d::date='2026-09-04' then 20 else 60 end from generate_series('2026-08-21'::date,'2026-09-04'::date,interval '1 day')d;
insert into audit_observations select 'one_tick_each_night_14_flat_baseline',nb.night_inputs('00000000-0000-0000-0000-000000000009','2026-09-04');
update raw_samples set hrv=hrv+extract(day from ts)::integer%3,heart=heart+extract(day from ts)::integer%3 where user_id='00000000-0000-0000-0000-000000000009' and ts<'2026-09-04';
insert into audit_observations select 'one_tick_each_night_14_variable_baseline',nb.night_inputs('00000000-0000-0000-0000-000000000009','2026-09-04');

insert into profiles values ('00000000-0000-0000-0000-000000000010','UTC',null),('00000000-0000-0000-0000-000000000011','UTC',null),('00000000-0000-0000-0000-000000000012','UTC',null);
insert into raw_samples(user_id,ts,heart,hrv,stress,step,met)
select '00000000-0000-0000-0000-000000000010','2026-09-04 04:00Z'::timestamptz+n*interval '5min',55+n%130,20+n%70,n%100,n%500,(n%130)/10.0 from generate_series(0,287)n;
insert into sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line) values ('00000000-0000-0000-0000-000000000010','2026-09-04',96,30,20,'2026-09-04 04:00Z','2026-09-04 06:00Z','0:30,1:20,2:46,4:24');
insert into audit_observations select 'mixed_288tick_invariants',jsonb_build_object('count',count(*),'min',min(value),'max',round(max(value),6),'max_closure_error',round(max(abs(d_charge+d_basal+d_active+d_stress-(value-20))),12)) from nb.reserve_replay('00000000-0000-0000-0000-000000000010','2026-09-04');
insert into audit_observations select 'no_evidence',jsonb_build_object('count',count(*)) from nb.compute_reserve('00000000-0000-0000-0000-000000000011','2026-09-04');
insert into raw_samples(user_id,ts,heart) values ('00000000-0000-0000-0000-000000000012','2026-09-04 04:00Z',70),('00000000-0000-0000-0000-000000000012','2026-09-04 20:00Z',70);
insert into audit_observations select '2_worn_ticks_16h_gap',jsonb_build_object('count',count(*),'final',min(value),'basal',min(d_basal)) from nb.reserve_replay('00000000-0000-0000-0000-000000000012','2026-09-04');

