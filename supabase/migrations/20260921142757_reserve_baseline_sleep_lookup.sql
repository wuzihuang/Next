-- Match each sample against the union of sleep-minute windows once. The open
-- lower / closed upper bounds preserve ts <= minute < ts + five minutes,
-- including off-grid samples, gaps and exact boundary timestamps. No scoring
-- formula, source preference or account filter changes.
CREATE OR REPLACE FUNCTION nb.reserve_baseline(p_user uuid, p_day date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 with profile as materialized (
  select p.timezone,b.starts_at lo,nb.calculation_instant(p_user,p_day) instant
  from nb.calculation_profile(p_user,p_day) p
  cross join lateral nb.user_day_bounds(p_day,p.timezone) b
 ), nights as materialized (
  select d::date as day,e.* from generate_series(p_day-14,p_day-1,interval '1 day') d
  cross join lateral nb.night_evidence_parts_at(p_user,d::date,(select instant from profile)) e
 ), sleep as materialized (
  select n.user_day,m.ts from nb.canonical_sleep_nights(p_user,p_day-14,p_day) n
  cross join lateral nb.sleep_evidence_minutes(p_user,n.user_day) m
  where m.stage<>4
 ), sleep_lookup as materialized (
  select range_agg(tstzrange(m.ts-interval '5 minutes',m.ts,'(]')) covered from sleep m
 ), points as materialized (
  select distinct on(s.ts) s.*,(s.ts at time zone p.timezone)::date as day,
   coalesce((select covered @> s.ts from sleep_lookup),false) sleeping
  from public.raw_samples s cross join profile p
  where s.user_id=p_user and s.ts>=(p_day-14)::timestamp at time zone p.timezone
    and s.ts<p.lo and s.ts<p.instant
  order by s.ts,(s.src='band') desc,s.src
 ), quiet as materialized (
  select s.* from points s where not s.sleeping and s.heart between 30 and 120
   and (s.step between 0 and 25 or s.met between 0.5 and 1.5)
   and (s.step is null or s.step between 0 and 25) and (s.met is null or s.met between 0.5 and 1.5)
 ), daily as (
  select day,
   case when count(*)>=6 then percentile_cont(0.5) within group(order by heart)::numeric end heart,
   case when count(*) filter(where hrv between 1 and 300)>=6
    then percentile_cont(0.5) within group(order by hrv) filter(where hrv between 1 and 300)::numeric end hrv,
   case when count(*) filter(where temp between 10 and 50)>=6
    then percentile_cont(0.5) within group(order by temp) filter(where temp between 10 and 50)::numeric end temp
  from quiet group by day
 ), night_temp as (
  select m.user_day as day,percentile_cont(0.5) within group(order by s.temp)::numeric temp
  from sleep m join points s on m.ts=s.ts and s.temp between 10 and 50
  group by m.user_day having count(*)>=36 and count(*)*5>=0.6*(select count(*) from sleep x where x.user_day=m.user_day)
 ), medians as (
  select
   (select percentile_cont(0.5) within group(order by rhr)::numeric from nights where rhr_eligible and rhr between 30 and 120 having count(*)>=5) resting,
   (select percentile_cont(0.5) within group(order by hrv)::numeric from nights where hrv_eligible and hrv between 1 and 300 having count(*)>=5) sleep_hrv,
   (select percentile_cont(0.5) within group(order by heart)::numeric from daily having count(heart)>=5) day_heart,
   (select percentile_cont(0.5) within group(order by hrv)::numeric from daily having count(hrv)>=5) day_hrv,
   (select percentile_cont(0.5) within group(order by temp)::numeric from daily having count(temp)>=5) day_temp,
   (select percentile_cont(0.5) within group(order by temp)::numeric from night_temp having count(*)>=5) sleep_temp
 ) select jsonb_build_object(
  'resting_heart',coalesce(m.resting,55),'resting_estimated',m.resting is null,
  'day_heart',coalesce(m.day_heart,m.resting+10,65),'day_hrv',m.day_hrv,'sleep_hrv',m.sleep_hrv,
  'day_temperature',m.day_temp,'sleep_temperature',m.sleep_temp,
  'day_temperature_scale',greatest(0.5,(select 3*percentile_cont(0.5) within group(order by abs(d.temp-m.day_temp)) from daily d)),
  'sleep_temperature_scale',greatest(0.5,(select 3*percentile_cont(0.5) within group(order by abs(n.temp-m.sleep_temp)) from night_temp n)),
  'rhr_nights',(select count(*) from nights where rhr_eligible and rhr between 30 and 120),
  'sleep_hrv_nights',(select count(*) from nights where hrv_eligible and hrv between 1 and 300),
  'day_hrv_days',(select count(hrv) from daily),'day_heart_days',(select count(heart) from daily),
  'day_temperature_days',(select count(temp) from daily),'sleep_temperature_nights',(select count(*) from night_temp))
 from medians m;
$function$;

-- A composite expansion otherwise repeats the JSON conversion for every column,
-- including the HRV array. Populate each chosen night once before expanding it.
CREATE OR REPLACE FUNCTION nb.canonical_sleep_nights(p_user uuid, p_from date, p_to date)
 RETURNS SETOF sleep_nights
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 with candidates as (
  select s,(s.wake_at at time zone p.timezone)::date wake_day
  from public.sleep_nights s cross join lateral nb.calculation_profile(p_user,s.user_day) p
  where s.user_id=p_user and s.user_day between p_from-1 and p_to+1
   and s.sleep_start is not null and s.wake_at>s.sleep_start
 ), chosen as (
  select distinct on(c.wake_day) c.* from candidates c where c.wake_day between p_from and p_to
  order by c.wake_day,((c.s).user_day=c.wake_day) desc,(c.s).wake_at desc,
   (c.s).total_minutes desc nulls last,(c.s).user_day desc
 ), populated as materialized (
  select jsonb_populate_record(null::public.sleep_nights,to_jsonb(c.s)||jsonb_build_object('user_day',c.wake_day)) s from chosen c
 ) select (p.s).* from populated p;
$function$;
