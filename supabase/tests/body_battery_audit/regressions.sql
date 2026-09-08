-- Synthetic time/evidence boundary tests. Runs after fixtures + findings.
insert into profiles values
('00000000-0000-0000-0000-000000000013','UTC',null),
('00000000-0000-0000-0000-000000000014','UTC',null),
('00000000-0000-0000-0000-000000000015','UTC',null),
('00000000-0000-0000-0000-000000000016','UTC',null),
('00000000-0000-0000-0000-000000000017','UTC',null);
insert into sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line,raw) values
('00000000-0000-0000-0000-000000000013','2026-09-04',152,152,0,'2026-09-04 04:00Z','2026-09-04 08:00Z','0:60,0:92',
 '{"line":[{"stage":0,"minutes":60,"offset_minutes":0},{"stage":0,"minutes":92,"offset_minutes":148}],"intervals":[{"start":"2026-09-04T04:00:00Z","end":"2026-09-04T05:00:00Z"},{"start":"2026-09-04T06:28:00Z","end":"2026-09-04T08:00:00Z"}]}'),
('00000000-0000-0000-0000-000000000014','2026-09-04',152,152,0,'2026-09-04 04:00Z','2026-09-04 08:00Z','0:60,0:92',
 '{"intervals":[{"start":"2026-09-04T04:00:00Z","end":"2026-09-04T05:00:00Z"},{"start":"2026-09-04T06:28:00Z","end":"2026-09-04T08:00:00Z"}]}'),
('00000000-0000-0000-0000-000000000015','2026-09-04',240,240,0,'2026-09-04 04:00Z','2026-09-04 10:00Z','bad',
 '{"line":[{"stage":"99999999999999999999999999","minutes":"99999999999999999999999999","offset_minutes":0}],"intervals":[{"start":"bad","end":"2026-99-99T08:00:00Z"}]}'),
('00000000-0000-0000-0000-000000000016','2026-09-04',120,120,0,'2026-09-04 04:00Z','2026-09-04 06:00Z','0:120','{}');
insert into raw_samples(user_id,ts,heart,hrv) select '00000000-0000-0000-0000-000000000013',t,60,20 from generate_series('2026-09-04 04:00Z'::timestamptz,'2026-09-04 07:55Z'::timestamptz,interval '5 minutes') t;
update raw_samples set heart=30,hrv=200 where user_id='00000000-0000-0000-0000-000000000013' and ts>='2026-09-04 05:00Z' and ts<'2026-09-04 06:28Z';
update sleep_nights s set raw=raw||jsonb_build_object('hrv',(select jsonb_agg(jsonb_build_object('ts',to_char(t at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'rmssd_ms',case when t>='2026-09-04 05:00Z' and t<'2026-09-04 06:28Z' then 200 else 60 end)) from generate_series('2026-09-04 04:00Z'::timestamptz,'2026-09-04 07:59Z'::timestamptz,interval '1 minute')t)) where s.user_id='00000000-0000-0000-0000-000000000013';
insert into raw_samples(user_id,ts,heart) values('00000000-0000-0000-0000-000000000015','2026-09-04 11:00Z',70);
-- Fully covered, constant historical baselines must still respond to a changed night.
insert into sleep_nights(user_id,user_day,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line)
select '00000000-0000-0000-0000-000000000017',d::date,120,120,0,d+'04:00'::time,d+'06:00'::time,'0:120' from generate_series('2026-08-21'::date,'2026-09-04'::date,interval '1 day')d;
insert into raw_samples(user_id,ts,heart,hrv)
select '00000000-0000-0000-0000-000000000017',d+interval '4 hours'+m*interval '5 minutes',case when d::date='2026-09-04' then 90 else 60 end,case when d::date='2026-09-04' then 20 else 60 end
from generate_series('2026-08-21'::date,'2026-09-04'::date,interval '1 day')d cross join generate_series(0,23)m;

do $$ declare a record; b record; j jsonb; q numeric; total integer; before numeric; after numeric;
begin
 select count(*) into total from nb.sleep_evidence_minutes('00000000-0000-0000-0000-000000000013','2026-09-04');
 perform audit_check('offset_preserves_88_minute_gap',total=152 and not exists(select 1 from nb.sleep_evidence_minutes('00000000-0000-0000-0000-000000000013','2026-09-04') where ts>='2026-09-04 05:00Z' and ts<'2026-09-04 06:28Z'),jsonb_build_object('minutes',total),'Raw offsets preserve all 152 minutes and leave the 88-minute gap uncharged.');
 perform audit_check('legacy_runs_map_over_actual_intervals',not exists((select ts,stage from nb.sleep_evidence_minutes('00000000-0000-0000-0000-000000000013','2026-09-04')) except (select ts,stage from nb.sleep_evidence_minutes('00000000-0000-0000-0000-000000000014','2026-09-04'))),'{}','Legacy runs are distributed over known intervals, without compressing their gaps.');
 select * into a from nb.night_evidence_parts('00000000-0000-0000-0000-000000000013','2026-09-04');
 perform audit_check('precise_minute_hrv_and_gap_exclusion',a.hrv=60 and a.hrv_tick_count=152 and a.hrv_source='minute_rmssd' and a.hrv_coverage=1 and a.rhr=60,to_jsonb(a),'Minute RMSSD supersedes coarse values; awake gaps contaminate neither HRV nor RHR.');
 select * into a from nb.compute_reserve('00000000-0000-0000-0000-000000000015','2026-09-04');
 perform audit_check('malformed_aggregate_has_no_fake_location',a.wake_value is null and a.drivers->>'night_charge' is null and a.current_value=50,to_jsonb(a),'Unlocatable 240/360-minute aggregate cannot forge sleep; the valid awake observation still drains from the assumed 50.');
 j:=nb.night_inputs('00000000-0000-0000-0000-000000000017','2026-09-04');
 perform audit_check('dense_constant_baseline_responds',j->>'hrv_nights'='14' and j->>'rhr_nights'='14' and (j->>'multiplier')::numeric=0.65,j,'Constant eligible baselines use the stable variance floor; adverse HRV/RHR changes lower M.');
 select * into a from nb.compute_reserve('00000000-0000-0000-0000-000000000004','2026-09-04');
 perform audit_check('whole_night_separate_from_day_ledger',(a.drivers->>'night_charge')::numeric>(a.drivers->>'day_charge')::numeric and a.drivers->>'day_charge'=a.drivers->>'last_night' and (a.drivers->>'assumed_anchor')::boolean and a.drivers->>'anchor_origin'='first_sleep_20',a.drivers,'Whole 22:00–06:00 charge includes pre-04:00 recovery; user-day attribution stays separately closed; seed origin survives.');
 -- Exactly 60/120 native minutes and max gap 60 are eligible; 59/120 is not.
 update sleep_nights s set raw=jsonb_build_object('hrv',(select jsonb_agg(jsonb_build_object('ts',to_char(t at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'rmssd_ms',60)) from generate_series('2026-09-04 04:00Z'::timestamptz,'2026-09-04 04:59Z'::timestamptz,interval '1 minute')t)) where s.user_id='00000000-0000-0000-0000-000000000016';
 select * into a from nb.night_evidence_parts('00000000-0000-0000-0000-000000000016','2026-09-04');
 perform audit_check('coverage_60_minute_50_percent_boundary',a.hrv_eligible and a.hrv_minutes=60 and a.hrv_coverage=0.5,to_jsonb(a),'The 60-minute and 50% eligibility boundary is inclusive.');
 update sleep_nights set raw=jsonb_set(raw,'{hrv}',(raw->'hrv')-59) where user_id='00000000-0000-0000-0000-000000000016';
 select * into a from nb.night_evidence_parts('00000000-0000-0000-0000-000000000016','2026-09-04');
 perform audit_check('coverage_59_minutes_is_ineligible',not a.hrv_eligible and a.hrv_minutes=59,to_jsonb(a),'59 minutes cannot qualify by rounding.');
 -- 180/270 valid minutes: longest missing run exactly 90 qualifies, 91 does not.
 update sleep_nights set total_minutes=270,deep_minutes=270,wake_at='2026-09-04 08:30Z',sleep_line='0:270',raw=jsonb_build_object('hrv',(select jsonb_agg(jsonb_build_object('ts',to_char(t at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'rmssd_ms',60)) from generate_series('2026-09-04 04:00Z'::timestamptz,'2026-09-04 06:59Z'::timestamptz,interval '1 minute')t)) where user_id='00000000-0000-0000-0000-000000000016';
 select * into a from nb.night_evidence_parts('00000000-0000-0000-0000-000000000016','2026-09-04');
 perform audit_check('coverage_90_minute_gap_boundary',a.hrv_eligible and a.hrv_longest_gap=90,to_jsonb(a),'A longest gap of exactly 90 minutes qualifies.');
 update sleep_nights set raw=jsonb_set(raw,'{hrv}',(raw->'hrv')-179) where user_id='00000000-0000-0000-0000-000000000016';
 select * into a from nb.night_evidence_parts('00000000-0000-0000-0000-000000000016','2026-09-04');
 perform audit_check('coverage_91_minute_gap_is_ineligible',not a.hrv_eligible and a.hrv_longest_gap=91,to_jsonb(a),'Adequate total coverage cannot hide a missing run over 90 minutes.');
 -- A historical wrong-day duplicate is one physical night, never two charges.
 select value into before from nb.reserve_replay('00000000-0000-0000-0000-000000000004','2026-09-03') order by ts desc limit 1;
 insert into sleep_nights select user_id,user_day-1,total_minutes,deep_minutes,light_minutes,sleep_start,wake_at,sleep_line,raw from sleep_nights where user_id='00000000-0000-0000-0000-000000000004' and user_day='2026-09-04';
 select value into after from nb.reserve_replay('00000000-0000-0000-0000-000000000004','2026-09-03') order by ts desc limit 1;
 perform audit_check('wrong_day_duplicate_never_double_charges',before=after,jsonb_build_object('before',round(before,4),'after',round(after,4)),'A wrong user_day alias of one physical night cannot add charge.');
 -- Native minutes take priority per slot; a single new minute does not erase all other coarse slots.
 update sleep_nights set raw=jsonb_set(raw,'{hrv}',jsonb_build_array((raw->'hrv')->0)) where user_id='00000000-0000-0000-0000-000000000013';
 select * into a from nb.night_evidence_parts('00000000-0000-0000-0000-000000000013','2026-09-04');
 perform audit_check('native_precedence_is_per_slot',a.hrv_source='mixed_rmssd' and a.hrv_coverage>0.9 and a.hrv_minutes=146,to_jsonb(a),'One native minute supersedes its coarse slot; unrelated coarse slots remain usable and samples outside the sleep intervals stay excluded.');
 update sleep_nights set raw=jsonb_set(raw,'{hrv}','[]') where user_id='00000000-0000-0000-0000-000000000013';
 select * into a from nb.night_evidence_parts('00000000-0000-0000-0000-000000000013','2026-09-04');
 perform audit_check('explicit_empty_native_is_no_measurement',a.hrv is null and a.hrv_minutes=0,to_jsonb(a),'Explicit empty native HRV must not resurrect old coarse HRV.');
 -- Future night samples cannot alter an earlier fixed calculation instant.
 perform set_config('nb.calculation_as_of','2026-09-04 05:00Z',true);
 select * into a from nb.night_evidence_parts('00000000-0000-0000-0000-000000000017','2026-09-04');
 perform audit_check('future_night_samples_excluded',a.rhr_minutes=60 and a.hrv_minutes=60 and not a.hrv_eligible and not a.rhr_eligible,to_jsonb(a),'An unfinished 04:00–06:00 night at 05:00 has only 60 observed minutes and cannot enter a baseline.');
 q:=nb.charge_multiplier('00000000-0000-0000-0000-000000000017','2026-09-04','UTC');
 update raw_samples set heart=30,hrv=200 where user_id='00000000-0000-0000-0000-000000000017' and ts>='2026-09-04 05:00Z';
 perform audit_check('future_samples_do_not_change_multiplier',q=nb.charge_multiplier('00000000-0000-0000-0000-000000000017','2026-09-04','UTC'),jsonb_build_object('multiplier',q),'Changing future samples does not change an as-of recovery multiplier.');
 perform set_config('nb.calculation_as_of','',true);
 -- Same transaction's cache wrapper must be the source seen by consumers.
 perform set_config('nb.replay_key','00000000-0000-0000-0000-000000000011/2026-09-04',true);
 perform set_config('nb.replay_data','[{"ts":"2026-09-04T08:00Z","value":42,"asleep":false,"d_charge":0,"d_basal":-8,"d_active":0,"d_stress":0}]',true);
 select value into q from nb.reserve_replay('00000000-0000-0000-0000-000000000011','2026-09-04');
 perform audit_check('transaction_replay_cache_preserved',q=42,jsonb_build_object('value',q),'The publication cache wrapper remains active after replacing only the uncached engine.');
 perform set_config('nb.replay_key','',true);
 -- Since 20260907040000 the horizon is decided by the data: the last complete slot, or
 -- the slot holding the newest real sample, whichever is later. Neither can start after
 -- the calculation instant, so 06:00 is reachable and 06:05 is not.
 perform set_config('nb.calculation_as_of','2026-09-04 06:00Z',true);
 select max(ts) into a from nb.reserve_replay('00000000-0000-0000-0000-000000000013','2026-09-04');
 perform audit_check('replay_respects_calculation_clock',a.max<='2026-09-04 06:00Z',to_jsonb(a),'No replay slot starts after the fixed calculation instant.');
 perform set_config('nb.calculation_as_of','',true);
end $$;
-- Quiet qualification requires measured stress/HRV/steps and only discounts time
-- strictly beyond twenty completed minutes.
insert into raw_samples(user_id,ts,heart,hrv,stress,step,met)
select '00000000-0000-0000-0000-000000000017',t,30,60,20,0,1
from generate_series('2026-09-04 09:00Z'::timestamptz,'2026-09-04 09:20Z'::timestamptz,interval '5 minutes')t;
-- Stated as slot-to-slot deltas rather than absolute points: an undiscounted slot differs
-- from the one before it only by the charge softener, far under one percent, so the check
-- survives recalibration of the basal rate itself.
do $$ declare b05 numeric; b10 numeric; b15 numeric; b20 numeric; d4 numeric; d5 numeric;
begin
 select d_basal into b05 from nb.reserve_replay('00000000-0000-0000-0000-000000000017','2026-09-04') where ts='2026-09-04 09:05Z';
 select d_basal into b10 from nb.reserve_replay('00000000-0000-0000-0000-000000000017','2026-09-04') where ts='2026-09-04 09:10Z';
 select d_basal into b15 from nb.reserve_replay('00000000-0000-0000-0000-000000000017','2026-09-04') where ts='2026-09-04 09:15Z';
 select d_basal into b20 from nb.reserve_replay('00000000-0000-0000-0000-000000000017','2026-09-04') where ts='2026-09-04 09:20Z';
 d4:=b15-b10; d5:=b20-b15;
 perform audit_check('quiet_twenty_minutes_has_no_early_discount',
  d4<0 and abs(d4-(b10-b05))<0.01*abs(b10-b05),
  jsonb_build_object('slot_20min',d4,'slot_15min',b10-b05),
  'Reaching twenty minutes qualifies only subsequent quiet time.');
 perform audit_check('quiet_twenty_five_minutes_discounts_only_last_slot',d5<0 and abs(d5)<0.95*abs(d4),
  jsonb_build_object('last_slot',d5,'previous_slot',d4),'Only the five minutes after the quiet threshold receive a drain discount.');
end $$;
select name,status from audit_findings order by status,name;
select name,observed,contract from audit_findings where status<>'CHECK_PASSED';
