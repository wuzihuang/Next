-- sleep-v1.2: one recorded night, one clock and visible evidence for every input.
-- Original sleep rows are retained. No clinical coverage threshold is introduced:
-- two independent samples (HRV: two 15-minute buckets) is an engineering minimum.
-- Reviewed latest definitions: score 20260905100000 + REM/version patch 20260905100002;
-- shared HRV/RHR now belong to bb-2.1 (20260906130331). Dedicated sleep-score functions
-- below intentionally leave those shared functions and night_hrv/reserve_daily untouched.
-- Do not replace recompute_range or change its revision/recovery machinery.

create or replace function nb.sleep_json_instant(v text) returns timestamptz
language plpgsql immutable set search_path='' as $$
begin
 if v is null or v !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}(:?\d{2})?)$' then return null; end if;
 return v::timestamptz;
exception when invalid_datetime_format or datetime_field_overflow then return null;
end $$;

create or replace function nb.sleep_json_number(v text) returns numeric
language plpgsql immutable set search_path='' as $$
begin
 if v is null or v !~ '^[0-9]+(\.[0-9]+)?$' or length(v)>32 then return null; end if;
 return v::numeric;
end $$;

-- A legacy copy filed under yesterday must not become a second night or a baseline
-- sample. A later sync may upload that source row again; this read rule still rejects it.
-- The finite 48-hour bound protects minute expansion from owner-writable invalid spans.
create or replace function nb.sleep_night_is_canonical(p_user uuid,p_day date)
returns boolean language sql stable set search_path='' as $$
 select coalesce((select s.total_minutes>0 and
   case when (s.sleep_start is not null and not isfinite(s.sleep_start))
       or (s.wake_at is not null and not isfinite(s.wake_at)) then false
     when s.sleep_start is null or s.wake_at is null then true
     else s.wake_at>s.sleep_start and s.wake_at-s.sleep_start<=interval '48 hours' end and
   (s.wake_at is null or (s.wake_at at time zone coalesce(p.timezone,'UTC'))::date=s.user_day)
 from public.sleep_nights s
 left join lateral nb.calculation_profile(p_user,p_day) p on true
 where s.user_id=p_user and s.user_day=p_day),false);
$$;

-- Merge overlapping segments and clip them to the original recorded bounds. An explicit
-- empty/invalid interval array is not permission to fill its gaps with the outer window.
create or replace function nb.sleep_windows(p_user uuid,p_day date)
returns table(starts_at timestamptz,ends_at timestamptz)
language sql stable set search_path='' as $$
 with night as materialized (
  select * from public.sleep_nights where user_id=p_user and user_day=p_day
   and nb.sleep_night_is_canonical(p_user,p_day) and wake_at>sleep_start
 ), candidates as (
  select n.sleep_start,n.wake_at,
    nb.sleep_json_instant(e->>'start') lo,nb.sleep_json_instant(e->>'end') hi
  from night n cross join lateral jsonb_array_elements(
    case when jsonb_typeof(n.raw->'intervals')='array' then n.raw->'intervals'
         when n.raw ? 'intervals' then '[]'::jsonb
         else jsonb_build_array(jsonb_build_object('start',n.sleep_start,'end',n.wake_at)) end) e
 ), merged as (
  select range_agg(tstzrange(greatest(lo,sleep_start),least(hi,wake_at),'[)')) ranges
  from candidates where lo is not null and hi is not null
   and least(hi,wake_at)>greatest(lo,sleep_start)
 ) select lower(r),upper(r) from merged cross join lateral unnest(ranges) r;
$$;

create or replace function nb.sleep_observations(p_user uuid,p_day date,p_domain text)
returns table(ts timestamptz,v numeric)
language sql stable set search_path='' as $$
 with night as materialized (
 select * from public.sleep_nights where user_id=p_user and user_day=p_day
   and nb.sleep_night_is_canonical(p_user,p_day)
   and exists(select 1 from nb.sleep_windows(p_user,p_day))
 ), windows as materialized (select * from nb.sleep_windows(p_user,p_day)),
 candidates as (
  select nb.sleep_json_instant(e->>'ts') ts,
    nb.sleep_json_number(e->>'rmssd_ms') v
  from night n cross join lateral jsonb_array_elements(
    case when p_domain='hrv' and jsonb_typeof(n.raw->'hrv')='array'
      then n.raw->'hrv' else '[]'::jsonb end) e
  union all
  select r.ts,r.hrv from night n join public.raw_samples r
   on r.user_id=n.user_id and r.ts>=n.sleep_start and r.ts<n.wake_at
  where p_domain='hrv' and not(n.raw ? 'hrv')
  union all
  select r.ts,r.heart::numeric from night n join public.raw_samples r
   on r.user_id=n.user_id and r.ts>=n.sleep_start and r.ts<n.wake_at
  where p_domain='rhr'
  union all
  select o.ts,o.spo2::numeric from night n join public.oxygen_samples o
   on o.user_id=n.user_id and o.ts>=n.sleep_start and o.ts<n.wake_at
  where p_domain='spo2'
  union all
  select nb.sleep_json_instant(e->>'ts'),nb.sleep_json_number(e->>'breaths_per_minute')
  from night n cross join lateral jsonb_array_elements(
    case when p_domain='respiration' and jsonb_typeof(n.raw->'respiration')='array'
      then n.raw->'respiration' else '[]'::jsonb end) e
 ), valid as (
  select c.ts,c.v from candidates c where exists(
    select 1 from windows w where c.ts>=w.starts_at and c.ts<w.ends_at)
   and case p_domain when 'hrv' then c.v between 1 and 300
     when 'rhr' then c.v>0 when 'spo2' then c.v between 50 and 100
     when 'respiration' then c.v between 4 and 40 else false end
 )
 -- Repeated timestamps/transport sources cannot turn one measurement into two samples.
 select valid.ts,percentile_cont(0.5) within group(order by valid.v)::numeric
 from valid group by valid.ts;
$$;

create or replace function nb.sleep_score_hrv_parts(p_user uuid,p_user_day date)
returns table(rmssd_ms numeric,bucket_count integer,tick_count integer)
language sql stable set search_path='' as $$
 with buckets as (
  select floor(extract(epoch from(o.ts-n.sleep_start))/900) bucket,
    percentile_cont(0.5) within group(order by o.v) v,count(*) n
  from nb.sleep_observations(p_user,p_user_day,'hrv') o
  join public.sleep_nights n on n.user_id=p_user and n.user_day=p_user_day
  group by 1
 ) select case when count(*)>=2 then round(
   percentile_cont(0.5) within group(order by v)::numeric,2) end,
   count(*)::int,coalesce(sum(n),0)::int from buckets;
$$;

create or replace function nb.sleep_score_rhr(p_user uuid,p_user_day date)
returns numeric language sql stable set search_path='' as $$
 select case when count(*)>=2 then
  percentile_cont(0.05) within group(order by v)::numeric end
 from nb.sleep_observations(p_user,p_user_day,'rhr');
$$;

create or replace function nb.night_oxygen_stats(p_user uuid,p_user_day date)
returns table(spo2_min smallint,spo2_mean numeric,sample_count integer)
language sql stable security definer set search_path='' as $$
 select case when count(*)>=2 then min(v)::smallint end,
  case when count(*)>=2 then round(avg(v),1) end,count(*)::int
 from nb.sleep_observations(p_user,p_user_day,'spo2');
$$;

create or replace function nb.night_respiration_mean(p_user uuid,p_user_day date)
returns numeric language sql stable security definer set search_path='' as $$
 select case when count(*)>=2 then round(avg(v),1) end
 from nb.sleep_observations(p_user,p_user_day,'respiration');
$$;

-- Coverage describes sampling slots, not continuous monitoring or clinical validity.
-- HRV reports measured-minute occupancy and a separate 15-minute bucket coverage; RHR
-- uses the five-minute origin grid, oxygen/respiration use recorded-minute slots.
create or replace function nb.sleep_evidence(p_user uuid,p_day date,p_domain text)
returns jsonb language sql stable set search_path='' as $$
 with windows as materialized (select * from nb.sleep_windows(p_user,p_day)),
 night as (select sleep_start,raw from public.sleep_nights where user_id=p_user and user_day=p_day),
 points as materialized (select * from nb.sleep_observations(p_user,p_day,p_domain)),
 settings as (select case when p_domain='rhr' or (p_domain='hrv' and not(raw?'hrv'))
   then 5 else 1 end step from night),
 minute_slots as materialized (
  select distinct g ts from windows w cross join lateral
    generate_series(w.starts_at,w.ends_at-interval '1 microsecond',interval '1 minute') g
 ), expected as (
  select count(*)::int minutes,
    count(distinct floor(extract(epoch from(m.ts-n.sleep_start))/900))::int buckets
  from minute_slots m cross join night n
 ), counts as (
  select count(*)::int samples,
    count(distinct date_bin(interval '1 minute',p.ts,'2000-01-01'::timestamptz))::int minutes,
    count(distinct floor(extract(epoch from(p.ts-n.sleep_start))/900))::int buckets
  from points p cross join night n
 ), expected_rhr as (
  select count(*)::int slots from windows w cross join lateral generate_series(
    date_bin(interval '5 minutes',w.starts_at,'2000-01-01'::timestamptz),
    w.ends_at-interval '1 microsecond',interval '5 minutes') g where g>=w.starts_at
 ), gap_marks as (
  select w.starts_at,w.ends_at,w.starts_at-make_interval(mins=>s.step) ts
    from windows w cross join settings s
  union
  select w.starts_at,w.ends_at,p.ts from windows w join points p
    on p.ts>=w.starts_at and p.ts<w.ends_at
  union select starts_at,ends_at,ends_at from windows
 ), gaps as (
  select greatest(0,extract(epoch from(lead(ts) over(
    partition by starts_at,ends_at order by ts)-ts))/60-s.step) gap
  from gap_marks cross join settings s
 )
 select jsonb_build_object(
   p_domain||'_sample_count',c.samples,
   p_domain||'_expected_minutes',e.minutes,
   p_domain||'_expected_samples',case when p_domain='rhr' then r.slots else e.minutes end,
   p_domain||'_longest_gap_min',coalesce((select ceil(max(gap)) from gaps),0),
   p_domain||'_coverage',round(least(1,coalesce(case p_domain
     when 'hrv' then c.minutes::numeric/nullif(e.minutes,0)
     when 'rhr' then c.samples::numeric/nullif(r.slots,0)
     else c.minutes::numeric/nullif(e.minutes,0) end,0)),4),
   p_domain||'_sufficient',case when p_domain='hrv' then c.buckets>=2 else c.samples>=2 end)
   || case when p_domain='hrv' then jsonb_build_object(
     'hrv_bucket_count',c.buckets,'hrv_expected_buckets',e.buckets,
     'hrv_bucket_coverage',coalesce(round(c.buckets::numeric/nullif(e.buckets,0),4),0),
     'hrv_source_exact',case when n.raw?'hrv' then 1 else 0 end,
     'hrv_source',case when n.raw?'hrv' then 'exact_minutes' else 'five_minute_fallback' end)
     else '{}'::jsonb end
 from expected e cross join counts c cross join expected_rhr r cross join night n;
$$;

-- Preserve the four group formulas, thresholds and record-duration convention from v1.1.
create or replace function nb.night_score_parts(p_user uuid,p_user_day date)
returns table(score numeric,duration_score numeric,architecture_score numeric,
 recovery_score numeric,regularity_score numeric,personal_weight numeric,inputs jsonb)
language plpgsql stable security definer set search_path='' as $$
declare
 v_tz text; n public.sleep_nights%rowtype; ox record;
 hrv numeric; rhr numeric; resp numeric; hrv_base numeric; rhr_base numeric;
 hrv_n int; rhr_n int; bed_n int; hrv_w numeric; rhr_w numeric; w numeric;
 bed numeric; bed_median numeric; bed_gap numeric;
 deep_pct numeric; light_pct numeric; rem_min int; rem_pct numeric;
 dur numeric; arch numeric; rec numeric; reg numeric; total numeric; evidence jsonb;
begin
 if not nb.sleep_night_is_canonical(p_user,p_user_day) then return; end if;
 select * into n from public.sleep_nights where user_id=p_user and user_day=p_user_day;
 select timezone into v_tz from nb.calculation_profile(p_user,p_user_day);
 select p.rmssd_ms into hrv from nb.sleep_score_hrv_parts(p_user,p_user_day) p;
 -- Retain the integer RHR scoring convention, but recompute from the same sleep segments.
 rhr:=round(nb.sleep_score_rhr(p_user,p_user_day));
 resp:=nb.night_respiration_mean(p_user,p_user_day);
 select * into ox from nb.night_oxygen_stats(p_user,p_user_day);

 with prior as materialized (
  select sn.user_day,sn.sleep_start from public.sleep_nights sn
  where sn.user_id=p_user and sn.user_day between p_user_day-28 and p_user_day-1
   and nb.sleep_night_is_canonical(p_user,sn.user_day)
   and exists(select 1 from nb.sleep_windows(p_user,sn.user_day))
 ), measured as materialized (
  select p.sleep_start,h.rmssd_ms hrv,round(nb.sleep_score_rhr(p_user,p.user_day)) rhr
  from prior p cross join lateral nb.sleep_score_hrv_parts(p_user,p.user_day) h
 )
 select count(m.hrv),count(m.rhr),count(m.sleep_start),
  percentile_cont(0.5) within group(order by m.hrv),
  percentile_cont(0.5) within group(order by m.rhr),
  percentile_cont(0.5) within group(order by nb.evening_offset(m.sleep_start,v_tz))
 into hrv_n,rhr_n,bed_n,hrv_base,rhr_base,bed_median from measured m;
 hrv_w:=greatest(0,least(1,(hrv_n-14)::numeric/14));
 rhr_w:=greatest(0,least(1,(rhr_n-14)::numeric/14));
 hrv_base:=40*(1-hrv_w)+coalesce(hrv_base,40)*hrv_w;
 rhr_base:=60*(1-rhr_w)+coalesce(rhr_base,60)*rhr_w;
 w:=case when hrv is not null and rhr is not null then least(hrv_w,rhr_w)
   when hrv is not null then hrv_w when rhr is not null then rhr_w
   else greatest(0,least(1,(bed_n-14)::numeric/14)) end;

 dur:=nb.score_sleep_duration(n.total_minutes);
 deep_pct:=100.0*n.deep_minutes/n.total_minutes;
 light_pct:=100.0*n.light_minutes/n.total_minutes;
 rem_min:=case when coalesce(n.sleep_line,'')='' then null
   else nullif(nb.sleep_line_minutes(n.sleep_line,2),0) end;
 rem_pct:=100.0*rem_min/n.total_minutes;
 arch:=nb.weighted_present(array[
   nb.score_window(deep_pct,0,13,23,45),nb.score_window(rem_pct,0,20,25,50),
   case when n.wake_count is null then null else greatest(0,100-20*(greatest(n.wake_count,1)-1)) end],
   array[40,40,20]);
 rec:=nb.weighted_present(array[
   nb.score_window(hrv,0.4*hrv_base,0.9*hrv_base,1e9,null),
   nb.score_window(rhr,rhr_base-25,rhr_base-5,rhr_base+5,rhr_base+25),
   nb.score_window(ox.spo2_min,88,95,100,null),nb.score_window(resp,6,12,18,30)],
   array[35,25,20,20]);
 bed:=nb.evening_offset(n.sleep_start,v_tz);
 if bed_n>=14 and bed is not null and bed_median is not null then
  bed_gap:=abs(bed-bed_median); bed_gap:=least(bed_gap,1440-bed_gap);
  reg:=nb.score_window(bed_gap,null,0,30,120);
 end if;
 total:=nb.weighted_present(array[dur,arch,rec,reg],array[25,25,35,15]);
 if total is null then return; end if;
 select jsonb_build_object('sleep_segment_count',count(*),
  'sleep_recorded_minutes',coalesce(sum(extract(epoch from(ends_at-starts_at))/60),0)::int,
  'sleep_elapsed_minutes',(extract(epoch from(n.wake_at-n.sleep_start))/60)::int,
  'sleep_gap_minutes',(extract(epoch from(n.wake_at-n.sleep_start))/60-
     coalesce(sum(extract(epoch from(ends_at-starts_at))/60),0))::int) into evidence
 from nb.sleep_windows(p_user,p_user_day);
 evidence:=evidence||nb.sleep_evidence(p_user,p_user_day,'hrv')
   ||nb.sleep_evidence(p_user,p_user_day,'rhr')||nb.sleep_evidence(p_user,p_user_day,'spo2')
   ||nb.sleep_evidence(p_user,p_user_day,'respiration');
 return query select round(total),round(dur),round(arch),round(rec),round(reg),round(w,2),
  jsonb_strip_nulls(jsonb_build_object(
   'duration_min',n.total_minutes,'duration_basis','recorded_segments','duration_recorded',1,
   'deep_pct',round(deep_pct,1),'light_pct',round(light_pct,1),
   'rem_pct',round(rem_pct,1),'rem_min',rem_min,'wakes',n.wake_count,
   'hrv_ms',hrv,'hrv_base',round(hrv_base,1),'rhr',rhr,'rhr_base',round(rhr_base,1),
   'spo2_min',ox.spo2_min,'spo2_mean',ox.spo2_mean,'spo2_n',ox.sample_count,
   'respiration',resp,'bed_offset',bed,
   'bed_median',case when bed_n>=14 then round(bed_median) end,'baseline_nights',bed_n,
   'baseline_hrv_nights',hrv_n,'baseline_rhr_nights',rhr_n,'baseline_bed_nights',bed_n,
   'hrv_personal_weight',round(hrv_w,2),'rhr_personal_weight',round(rhr_w,2))||evidence);
end $$;

-- Keep the established writer and its grants, replacing only the version literal.
do $$ declare definition text; patched text; begin
 definition:=pg_get_functiondef('nb.refresh_night_score(uuid,date)'::regprocedure);
 patched:=replace(definition,'''sleep-v1.1''','''sleep-v1.2''');
 if patched=definition then raise exception 'SLEEP_V12_VERSION_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

comment on column public.night_score.personal_weight is
 'Conservative minimum personalization weight among present HRV/RHR inputs; each has its own valid historical-night count in inputs.';
comment on column public.night_score.inputs is
 'Measured score inputs plus independent sample counts, sampling-slot coverage and within-segment gaps. Engineering minimum: HRV two 15-minute buckets; other physiology two distinct timestamps. No clinical adequacy claim.';

revoke execute on function nb.sleep_json_instant(text),nb.sleep_json_number(text),
 nb.sleep_night_is_canonical(uuid,date),nb.sleep_windows(uuid,date),
 nb.sleep_observations(uuid,date,text),nb.sleep_evidence(uuid,date,text),
 nb.sleep_score_hrv_parts(uuid,date),nb.sleep_score_rhr(uuid,date),
 nb.night_oxygen_stats(uuid,date),nb.night_respiration_mean(uuid,date),
 nb.night_score_parts(uuid,date) from public,anon,authenticated;

-- Rebuild only sleep scores. The shared night_hrv and Body Battery derivations retain
-- their owner's independent evidence/eligibility contract and need no invalidation here.
-- Erroneous-day copies lose the score only; no source sleep row is deleted.
do $$ declare r record; begin
 for r in select user_id,user_day from public.sleep_nights
   union select user_id,user_day from public.night_score loop
  perform nb.refresh_night_score(r.user_id,r.user_day);
 end loop;
end $$;
