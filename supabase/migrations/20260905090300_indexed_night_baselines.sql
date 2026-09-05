-- Preserve night percentiles and baseline formulas while bounding every raw read.
-- A CASE combining sleep-window and fallback-day predicates prevented the timestamp
-- index from bounding scans, multiplied by repeated evaluation of baseline functions.
create or replace function nb.night_rhr(p_user uuid,p_user_day date,p_tz text)
returns numeric language plpgsql stable set search_path='' as $$
declare lo timestamptz; hi timestamptz; result numeric;
begin
 select s.sleep_start,s.wake_at into lo,hi from public.sleep_nights s
 where s.user_id=p_user and s.user_day=p_user_day;
 if lo is not null and hi is not null then
   select percentile_cont(0.05) within group(order by r.heart) into result
   from public.raw_samples r where r.user_id=p_user and r.ts>=lo and r.ts<hi
   and r.heart is not null;
 else
   select b.starts_at,b.ends_at into lo,hi from nb.user_day_bounds(p_user_day,p_tz) b;
   select percentile_cont(0.05) within group(order by r.heart) into result
   from public.raw_samples r where r.user_id=p_user and r.ts>=lo and r.ts<hi
   and r.heart is not null and coalesce(r.sleep_states,0)<>0;
 end if;
 return result;
end $$;

-- Keep each existing body (including profile-history semantics), replacing only
-- baseline evaluation plans. MATERIALIZED also includes null nights exactly once.
do $$
declare target text; definition text; previous text;
begin
 foreach target in array array['nb.charge_multiplier(uuid,date,text)','nb.night_inputs(uuid,date)'] loop
  definition:=pg_get_functiondef(target::regprocedure);
  previous:=definition;
  definition:=replace(definition,
    E'  select count(*), avg(h), stddev_samp(h) into v_hrv_n, v_hrv_mean, v_hrv_sd\n  from (\n    select nb.night_hrv(p_user, d::date) as h\n    from generate_series(p_user_day - 14, p_user_day - 1, interval ''1 day'') d\n  ) s where h is not null;',
    E'  with nights as materialized (select nb.night_hrv(p_user,d::date) h from generate_series(p_user_day-14,p_user_day-1,interval ''1 day'') d)\n  select count(*),avg(h),stddev_samp(h) into v_hrv_n,v_hrv_mean,v_hrv_sd from nights where h is not null;');
  definition:=replace(definition,
    E'  select count(*), avg(r), stddev_samp(r) into v_rhr_n, v_rhr_mean, v_rhr_sd\n  from (\n    select nb.night_rhr(p_user, d::date, p_tz) as r\n    from generate_series(p_user_day - 14, p_user_day - 1, interval ''1 day'') d\n  ) s where r is not null;',
    E'  with nights as materialized (select nb.night_rhr(p_user,d::date,p_tz) r from generate_series(p_user_day-14,p_user_day-1,interval ''1 day'') d)\n  select count(*),avg(r),stddev_samp(r) into v_rhr_n,v_rhr_mean,v_rhr_sd from nights where r is not null;');
  definition:=replace(definition,
    E'  select count(*), avg(r) into v_rhr_n, v_rhr_base\n  from (\n    select nb.night_rhr(p_user, d::date, v_tz) as r\n    from generate_series(p_user_day - 14, p_user_day - 1, interval ''1 day'') d\n  ) s where r is not null;',
    E'  with nights as materialized (select nb.night_rhr(p_user,d::date,v_tz) r from generate_series(p_user_day-14,p_user_day-1,interval ''1 day'') d)\n  select count(*),avg(r) into v_rhr_n,v_rhr_base from nights where r is not null;');
  definition:=replace(definition,
    E'  select count(*), avg(h) into v_hrv_n, v_hrv_base\n  from (\n    select nb.night_hrv(p_user, d::date) as h\n    from generate_series(p_user_day - 14, p_user_day - 1, interval ''1 day'') d\n  ) s where h is not null;',
    E'  with nights as materialized (select nb.night_hrv(p_user,d::date) h from generate_series(p_user_day-14,p_user_day-1,interval ''1 day'') d)\n  select count(*),avg(h) into v_hrv_n,v_hrv_base from nights where h is not null;');
  if definition=previous then raise exception 'NIGHT_BASELINE_PATCH_MISSING: %',target; end if;
  execute definition;
 end loop;
end $$;

-- The single profile baseline must not be re-evaluated for every tick/expression.
-- In dense activity data, CTE inlining expanded hr_rest thousands of times.
do $$ declare definition text; patched text; begin
 definition:=pg_get_functiondef('nb.activity_ticks(uuid,date)'::regprocedure);
 patched:=replace(definition,'with profile as (','with profile as materialized (');
 patched:=replace(patched,'), points as (','), points as materialized (');
 if patched=definition then raise exception 'ACTIVITY_BASELINE_PATCH_MISSING'; end if;
 execute patched;
end $$;
