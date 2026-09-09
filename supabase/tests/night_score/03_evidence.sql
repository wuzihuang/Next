\set ON_ERROR_STOP on
-- Exercise actual source evidence, not precomputed night_hrv/reserve_daily fixtures.
do $$
declare u uuid:=t_user('minute-boundary'); p record;
begin
 perform t_night(u,'2026-09-06',304,60,1,null,'03:59');
 update public.sleep_nights set raw=jsonb_build_object('hrv',jsonb_build_array(
  jsonb_build_object('ts','2026-09-06T03:59:00+08:00','rmssd_ms',20),
  jsonb_build_object('ts','2026-09-06T04:01:00+08:00','rmssd_ms',24),
  jsonb_build_object('ts','2026-09-06T09:02:00+08:00','rmssd_ms',28),
  jsonb_build_object('ts','2026-09-06T09:04:00+08:00','rmssd_ms',200))) where user_id=u;
 insert into public.raw_samples(user_id,ts,hrv) values
  (u,'2026-09-06T03:55:00+08:00',20),(u,'2026-09-06T04:00:00+08:00',24),
  (u,'2026-09-06T09:00:00+08:00',114);
 perform nb.refresh_night_hrv(u,'2026-09-06');
 select * into p from nb.night_score_parts(u,'2026-09-06');
 assert (p.inputs->>'hrv_ms')::numeric=25,
   format('EXACT_MINUTE_BOUNDARY: expected 25 ms, got %s',p.inputs->>'hrv_ms');
 assert (p.inputs->>'hrv_sample_count')::int=3;
 assert (p.inputs->>'hrv_bucket_count')::int=2;
 assert (p.inputs->>'hrv_longest_gap_min')::numeric=300;
 assert p.inputs->>'hrv_source'='exact_minutes';
 -- An explicit empty exact array cannot resurrect old coarse samples.
 update public.sleep_nights set raw=raw||'{"hrv":[]}' where user_id=u;
 perform nb.refresh_night_hrv(u,'2026-09-06');
 select * into p from nb.night_score_parts(u,'2026-09-06');
 assert not(p.inputs?'hrv_ms') and (p.inputs->>'hrv_sample_count')::int=0;
 assert (select rmssd_ms from nb.sleep_score_hrv_parts(u,'2026-09-06')) is null;
 -- Historical rows without an exact channel retain a named legacy fallback.
 update public.sleep_nights set raw=raw-'hrv' where user_id=u;
 perform nb.refresh_night_hrv(u,'2026-09-06');
 select * into p from nb.night_score_parts(u,'2026-09-06');
 assert (p.inputs->>'hrv_ms')::numeric=69;
 assert p.inputs->>'hrv_source'='five_minute_fallback';
end $$;

do $$
declare u uuid:=t_user('bounded-untrusted-window'); p jsonb;
begin
 perform t_night(u,'2026-09-06',450,90,1);
 update public.sleep_nights set sleep_start='1900-01-01T00:00:00Z',wake_at='2026-09-06T06:00:00Z'
 where user_id=u;
 assert (select count(*) from nb.sleep_windows(u,'2026-09-06'))=0;
 assert (select count(*) from nb.night_score_parts(u,'2026-09-06'))=0,
   'An invalid multi-year window must not generate millions of minute rows or a score';
 p:=nb.sleep_evidence(u,'2026-09-06','hrv');
 assert (p->>'hrv_expected_minutes')::int=0 and (p->>'hrv_coverage')::numeric=0;
 update public.sleep_nights set sleep_start='infinity',wake_at=null where user_id=u;
 assert (select count(*) from nb.night_score_parts(u,'2026-09-06'))=0,
   'An infinite start cannot become a bedtime through the missing-wake legacy branch';
 update public.sleep_nights set sleep_start=null,wake_at='infinity' where user_id=u;
 assert (select count(*) from nb.night_score_parts(u,'2026-09-06'))=0;
end $$;

do $$
declare u uuid:=t_user('disjoint-windows'); p record;
begin
 perform t_night(u,'2026-09-06',120,24,1,null,'00:00');
 update public.sleep_nights set wake_at='2026-09-06T03:00:00+08:00',raw='{
 "intervals":[{"start":"2026-09-06T00:00:00+08:00","end":"2026-09-06T01:00:00+08:00"},
              {"start":"2026-09-06T02:00:00+08:00","end":"2026-09-06T03:00:00+08:00"}],
 "hrv":[{"ts":"2026-09-06T00:00:00+08:00","rmssd_ms":20},
        {"ts":"2026-09-06T00:00:00+08:00","rmssd_ms":20},
        {"ts":"2026-09-06T01:15:00+08:00","rmssd_ms":200},
        {"ts":"2026-09-06T02:00:00+08:00","rmssd_ms":40},
        {"ts":"2026-09-06T03:00:00+08:00","rmssd_ms":200}],
 "respiration":[{"ts":"2026-09-06T00:00:00+08:00","breaths_per_minute":17},
        {"ts":"2026-09-06T00:00:00+08:00","breaths_per_minute":17},
        {"ts":"2026-09-06T01:15:00+08:00","breaths_per_minute":40},
        {"ts":"2026-09-06T02:00:00+08:00","breaths_per_minute":19},
        {"ts":"2026-09-06T03:00:00+08:00","breaths_per_minute":40},
        {"ts":"invalid","breaths_per_minute":15},
        {"ts":"2026-09-06T00:01:00+08:00","breaths_per_minute":255}]}'
 where user_id=u;
 insert into public.raw_samples(user_id,ts,heart) values
  (u,'2026-09-06T00:00:00+08:00',60),(u,'2026-09-06T01:15:00+08:00',20),
  (u,'2026-09-06T02:00:00+08:00',60);
 insert into public.oxygen_samples(user_id,ts,spo2) values
  (u,'2026-09-06T00:00:00+08:00',96),(u,'2026-09-06T01:15:00+08:00',50),
  (u,'2026-09-06T02:00:00+08:00',98),(u,'2026-09-06T03:00:00+08:00',50);
 select * into p from nb.night_score_parts(u,'2026-09-06');
 assert (p.inputs->>'hrv_ms')::numeric=30 and (p.inputs->>'rhr')::numeric=60;
 assert (p.inputs->>'spo2_min')::numeric=96 and (p.inputs->>'spo2_mean')::numeric=97;
 assert (p.inputs->>'respiration')::numeric=18;
 assert (p.inputs->>'sleep_segment_count')::int=2;
 assert (p.inputs->>'sleep_recorded_minutes')::int=120 and (p.inputs->>'sleep_gap_minutes')::int=60;
 assert (p.inputs->>'hrv_sample_count')::int=2 and (p.inputs->>'hrv_expected_minutes')::int=120;
 assert (p.inputs->>'hrv_coverage')::numeric=0.0167;
 assert (p.inputs->>'hrv_bucket_coverage')::numeric=0.25;
 assert (p.inputs->>'hrv_longest_gap_min')::int=59;
 assert (p.inputs->>'rhr_expected_samples')::int=24;
 assert (p.inputs->>'rhr_longest_gap_min')::int=55;
 assert (p.inputs->>'spo2_sample_count')::int=2 and (p.inputs->>'respiration_sample_count')::int=2;
 -- Explicit empty intervals suppress all sensor channels; no outer-window fallback.
 update public.sleep_nights set raw=raw||'{"intervals":[]}' where user_id=u;
 select * into p from nb.night_score_parts(u,'2026-09-06');
 assert p.recovery_score is null and (p.inputs->>'hrv_sample_count')::int=0;
end $$;

do $$
declare u uuid:=t_user('minimum-independent-evidence'); p record;
begin
 perform t_night(u,'2026-09-06',450,90,1);
 update public.sleep_nights set raw=jsonb_build_object(
  'hrv',jsonb_build_array(jsonb_build_object('ts',sleep_start,'rmssd_ms',80),
    jsonb_build_object('ts',sleep_start+interval '1 minute','rmssd_ms',80)),
  'respiration',jsonb_build_array(jsonb_build_object('ts',sleep_start,'breaths_per_minute',15),
    jsonb_build_object('ts',sleep_start,'breaths_per_minute',15))) where user_id=u;
 insert into public.raw_samples(user_id,ts,heart) select u,sleep_start,60 from public.sleep_nights where user_id=u;
 insert into public.oxygen_samples(user_id,ts,spo2) select u,sleep_start,99 from public.sleep_nights where user_id=u;
 select * into p from nb.night_score_parts(u,'2026-09-06');
 assert p.recovery_score is null, 'A single independent sample is not a nightly statistic';
 assert not(p.inputs?'hrv_ms') and not(p.inputs?'rhr') and not(p.inputs?'spo2_min') and not(p.inputs?'respiration');
 assert (p.inputs->>'hrv_sample_count')::int=2 and (p.inputs->>'hrv_bucket_count')::int=1;
 assert not (p.inputs->>'hrv_sufficient')::boolean;
 assert (p.inputs->>'respiration_sample_count')::int=1;
 assert (p.inputs->>'respiration_longest_gap_min')::int=449;
end $$;

do $$
declare u uuid:=t_user('independent-history'); p record; i int;
begin
 for i in 1..28 loop
  perform t_night(u,'2026-09-06'::date-i,450,90,1);
  perform t_rhr(u,'2026-09-06'::date-i,52);
 end loop;
 perform t_hrv(u,'2026-09-05',25); -- One valid HRV night among 28 complete sleep windows.
 perform t_night(u,'2026-09-06',450,90,1);
 perform t_hrv(u,'2026-09-06',25); perform t_rhr(u,'2026-09-06',52);
 select * into p from nb.night_score_parts(u,'2026-09-06');
 assert (p.inputs->>'baseline_hrv_nights')::int=1;
 assert (p.inputs->>'baseline_rhr_nights')::int=28;
 assert (p.inputs->>'baseline_bed_nights')::int=28;
 assert (p.inputs->>'hrv_base')::numeric=40 and (p.inputs->>'rhr_base')::numeric=52;
 assert (p.inputs->>'hrv_personal_weight')::numeric=0 and (p.inputs->>'rhr_personal_weight')::numeric=1;
 assert p.personal_weight=0, 'Global personalization must not claim HRV is calibrated';
end $$;

do $$
declare u uuid; n int; p record;
begin
 select user_id into u from t_backfill;
 assert (select count(*) from public.sleep_nights where user_id=u)=2,'Retain both original source rows';
 assert (select count(*) from public.night_score where user_id=u)=1,'Backfill must remove duplicate derived score';
 assert (select count(*) from public.night_hrv where user_id=u)=2,'Shared Body Battery HRV rows must remain untouched';
 assert (select score_version from public.night_score where user_id=u)='sleep-v1.3';
 assert (select min(rmssd_ms) from public.night_hrv where user_id=u)=99;
 assert (select rmssd_ms from nb.sleep_score_hrv_parts(u,'2026-09-06'))=30;
 -- Re-uploading/recalculating the erroneous date cannot revive a second score.
 update public.sleep_nights set total_minutes=450 where user_id=u and user_day='2026-09-05';
 perform nb.refresh_night_score(u,'2026-09-05'); perform nb.refresh_night_hrv(u,'2026-09-05');
 assert not exists(select 1 from public.night_score where user_id=u and user_day='2026-09-05');
 perform t_night(u,'2026-09-07',450,90,1);
 select * into p from nb.night_score_parts(u,'2026-09-07');
 assert (p.inputs->>'baseline_hrv_nights')::int=1 and (p.inputs->>'baseline_bed_nights')::int=1;
 assert (select definition from t_migration_guards)=pg_get_functiondef('nb.recompute_range(uuid,date,date,text)'::regprocedure),
   'Evidence migration must preserve recompute revision/recovery machinery';
 assert (select definition from t_shared_function_guards where name='nb.night_hrv_parts(uuid,date)')=
   pg_get_functiondef('nb.night_hrv_parts(uuid,date)'::regprocedure);
 assert (select definition from t_shared_function_guards where name='nb.night_rhr(uuid,date,text)')=
   pg_get_functiondef('nb.night_rhr(uuid,date,text)'::regprocedure);
 assert not has_function_privilege('authenticated','nb.sleep_observations(uuid,date,text)','execute');
 assert not has_function_privilege('anon','nb.sleep_evidence(uuid,date,text)','execute');
end $$;
