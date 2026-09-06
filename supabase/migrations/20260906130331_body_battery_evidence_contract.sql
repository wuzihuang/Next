-- Resolve old mis-keyed duplicates once, before every reserve/baseline read.
create or replace function nb.canonical_sleep_nights(p_user uuid,p_from date,p_to date)
returns setof public.sleep_nights language sql stable set search_path='' as $$
 with candidates as (
  select s,(s.wake_at at time zone p.timezone)::date wake_day
  from public.sleep_nights s cross join lateral nb.calculation_profile(p_user,s.user_day) p
  where s.user_id=p_user and s.user_day between p_from-1 and p_to+1
   and s.sleep_start is not null and s.wake_at>s.sleep_start
 ), chosen as (
  select distinct on(c.wake_day) c.* from candidates c where c.wake_day between p_from and p_to
  order by c.wake_day,((c.s).user_day=c.wake_day) desc,(c.s).wake_at desc,
   (c.s).total_minutes desc nulls last,(c.s).user_day desc
 ) select (jsonb_populate_record(null::public.sleep_nights,to_jsonb(c.s)||jsonb_build_object('user_day',c.wake_day))).* from chosen c;
$$;

-- Body Battery 2.1: use recorded time and expose the evidence behind each result.
-- No physiological coefficients change. Quiet rest remains a drain discount.
-- This migration queues ordered recomputation; it does not overwrite live scores in DDL.

create or replace function nb.bb_number(v text) returns numeric
language plpgsql immutable set search_path='' as $$
begin
 if length(v)>32 or v !~ '^-?[0-9]+([.][0-9]+)?$' then return null; end if;
 return v::numeric;
exception when others then return null;
end $$;
create or replace function nb.bb_instant(v text) returns timestamptz
language plpgsql stable set search_path='' as $$
begin
 if v !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([.][0-9]+)?(Z|[+-]\d{2}:\d{2})$' then return null; end if;
 return v::timestamptz;
exception when others then return null;
end $$;

-- A single bounded minute timeline shared by charging and night baselines.
-- Offset runs keep gaps. Older sequential runs are mapped over real intervals when
-- available. Aggregate duration alone cannot locate sleep inside a longer window.
create or replace function nb.sleep_evidence_minutes(p_user uuid,p_user_day date)
returns table(ts timestamptz,stage integer,q numeric,source text)
language sql stable set search_path='' as $$
 with night as materialized (
  select * from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) s where s.user_id=p_user and s.user_day=p_user_day
  and s.sleep_start is not null and s.wake_at>s.sleep_start
  and s.wake_at-s.sleep_start<=interval '48 hours'
 ), intervals as materialized (
  select greatest(n.sleep_start,nb.bb_instant(j->>'start')) lo,
         least(n.wake_at,nb.bb_instant(j->>'end')) hi
  from night n cross join lateral jsonb_array_elements(case when jsonb_typeof(n.raw->'intervals')='array' then n.raw->'intervals' else '[]'::jsonb end) j
  where nb.bb_instant(j->>'start') is not null and nb.bb_instant(j->>'end')>nb.bb_instant(j->>'start')
 ), interval_minutes as materialized (
  select distinct g.t from intervals i cross join lateral generate_series(i.lo,i.hi-interval '1 minute',interval '1 minute') g(t)
 ), located as materialized (
  select m.t,row_number() over(order by m.t)-1 idx from interval_minutes m
  union all
  select g.t,row_number() over(order by g.t)-1 from night n
  cross join lateral generate_series(n.sleep_start,n.wake_at-interval '1 minute',interval '1 minute') g(t)
  where not exists(select 1 from intervals)
 ), raw_runs as materialized (
  select j.ordinality ord,nb.bb_number(j.v->>'stage') st,nb.bb_number(j.v->>'minutes') mins,
         nb.bb_number(j.v->>'offset_minutes') offs
  from night n cross join lateral jsonb_array_elements(case when jsonb_typeof(n.raw->'line')='array' then n.raw->'line' else '[]'::jsonb end) with ordinality j(v,ordinality)
 ), raw_ok as (
  select count(*)>0 and bool_and(coalesce(st between 0 and 4 and st=trunc(st) and mins between 1 and 2880 and mins=trunc(mins)
    and offs between 0 and 2880 and offs=trunc(offs),false)) ok from raw_runs
 ), legacy_tokens as materialized (
  select u.ordinality ord,u.token from night n cross join lateral unnest(string_to_array(coalesce(n.sleep_line,''),',')) with ordinality u(token,ordinality)
 ), legacy_ok as (
  select count(*)>0 and bool_and(token ~ '^[0-4]:[1-9][0-9]{0,3}$'
    and coalesce(nb.bb_number(split_part(token,':',2))<=2880,false)) ok from legacy_tokens
 ), legacy_runs as (
  select ord,nb.bb_number(split_part(token,':',1)) st,nb.bb_number(split_part(token,':',2)) mins,
   coalesce(sum(nb.bb_number(split_part(token,':',2))) over(order by ord rows between unbounded preceding and 1 preceding),0) offs
  from legacy_tokens where (select ok from legacy_ok) and not (select ok from raw_ok)
 ), staged as (
  select n.sleep_start+(r.offs+m.idx)*interval '1 minute' t,r.st::integer st,'offset_line'::text src
  from night n cross join raw_runs r cross join lateral generate_series(0,least(2880,greatest(0,r.mins))::integer-1) m(idx)
  where (select ok from raw_ok)
  union all
  select l.t,r.st::integer,'legacy_line' from legacy_runs r join located l on l.idx>=r.offs and l.idx<r.offs+r.mins
 ), valid_staged as materialized (
  select s.t,max(s.st) st,min(s.src) src from staged s cross join night n
  where s.t>=n.sleep_start and s.t<n.wake_at
   and (not exists(select 1 from intervals) or exists(select 1 from intervals i where s.t>=i.lo and s.t<i.hi))
  group by s.t
 ), fallback as (
  select l.t,least(1,greatest(0,n.total_minutes)::numeric/nullif(count(*) over(),0)) fraction,
    (1.25*coalesce(n.deep_minutes,0)+0.85*coalesce(n.light_minutes,0)
      +greatest(0,n.total_minutes-coalesce(n.deep_minutes,0)-coalesce(n.light_minutes,0)))
       /nullif(n.total_minutes,0)::numeric weight
  from located l cross join night n where not exists(select 1 from valid_staged)
   and n.total_minutes>0
   and (exists(select 1 from intervals) or n.total_minutes>=extract(epoch from(n.wake_at-n.sleep_start))/60)
 )
 select v.t,v.st,case v.st when 0 then 1.25 when 1 then 0.85 when 2 then 1.00 when 3 then 0.15 else 0 end,v.src from valid_staged v
 union all
 select f.t,1,f.fraction*f.weight,'aggregate_intervals' from fallback f;
$$;

-- Coverage counts the actual sleep minutes, not the first-to-last span. A five-minute
-- fallback observation covers only its own slot. Native minute HRV takes precedence.
create or replace function nb.night_evidence_parts_at(p_user uuid,p_user_day date,p_as_of timestamptz)
returns table(hrv numeric,rhr numeric,hrv_bucket_count integer,hrv_tick_count integer,
 expected_minutes integer,hrv_minutes integer,rhr_minutes integer,hrv_coverage numeric,
 rhr_coverage numeric,hrv_longest_gap integer,rhr_longest_gap integer,hrv_eligible boolean,rhr_eligible boolean,hrv_source text)
language sql stable set search_path='' as $$
 with minutes as materialized (
  select m.ts from nb.sleep_evidence_minutes(p_user,p_user_day) m where m.stage<>4
 ), native as materialized (
  select distinct on (nb.bb_instant(j->>'ts')) nb.bb_instant(j->>'ts') ts,nb.bb_number(j->>'rmssd_ms') h
  from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) n cross join lateral jsonb_array_elements(case when jsonb_typeof(n.raw->'hrv')='array' then n.raw->'hrv' else '[]'::jsonb end) j
  where n.user_id=p_user and n.user_day=p_user_day and nb.bb_number(j->>'rmssd_ms') between 1 and 300
   and nb.bb_instant(j->>'ts')<p_as_of
   and exists(select 1 from minutes m where m.ts=nb.bb_instant(j->>'ts'))
  order by nb.bb_instant(j->>'ts'),nb.bb_number(j->>'rmssd_ms')
 ), raw as materialized (
  select distinct on(r.ts) r.ts,r.hrv,r.heart from public.raw_samples r
  where r.user_id=p_user and r.ts<p_as_of and r.ts>=(select min(m.ts)-interval '5 minutes' from minutes m)
    and r.ts<=(select max(m.ts) from minutes m)
    and exists(select 1 from minutes m where m.ts=r.ts)
  order by r.ts,(r.src='band') desc
 ), covered as materialized (
  select m.ts,case when exists(select 1 from native v where date_bin(interval '5 minutes',v.ts,'2000-01-01'::timestamptz)=date_bin(interval '5 minutes',m.ts,'2000-01-01'::timestamptz)) then n.h else case when r.hrv between 1 and 300 and not exists(select 1 from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) s where s.raw->'hrv'='[]'::jsonb) then r.hrv end end h,
    case when r.heart between 25 and 240 then r.heart end heart,
    case when exists(select 1 from native v where date_bin(interval '5 minutes',v.ts,'2000-01-01'::timestamptz)=date_bin(interval '5 minutes',m.ts,'2000-01-01'::timestamptz)) then n.ts else r.ts end hts,r.ts rts
  from minutes m left join native n on n.ts=m.ts
  left join raw r on r.ts=date_bin(interval '5 minutes',m.ts,'2000-01-01'::timestamptz)
 ), ticks as (
  select distinct c.hts,c.h from covered c where c.h is not null
 ), buckets as (
  select percentile_cont(0.5) within group(order by t.h) v
  from ticks t group by date_bin(interval '15 minutes',t.hts,(select min(m.ts) from minutes m))
 ), hr_ticks as (
  select distinct c.rts,c.heart from covered c where c.heart is not null
 ), groups as (
  select c.*,sum(case when c.h is not null then 1 else 0 end) over(order by c.ts) hg,
    sum(case when c.heart is not null then 1 else 0 end) over(order by c.ts) rg from covered c
 ), stats as (
  select count(*)::integer n,count(c.h)::integer hn,count(c.heart)::integer rn,
    coalesce((select max(g.n) from(select count(*)::integer n from groups where h is null group by hg)g),0) hgap,
    coalesce((select max(g.n) from(select count(*)::integer n from groups where heart is null group by rg)g),0) rgap
  from covered c
 )
 select round((select percentile_cont(0.5) within group(order by b.v)::numeric from buckets b),2),
  (select percentile_cont(0.05) within group(order by h.heart)::numeric from hr_ticks h),
  (select count(*)::integer from buckets),(select count(*)::integer from ticks),s.n,s.hn,s.rn,
  coalesce(s.hn::numeric/nullif(s.n,0),0),coalesce(s.rn::numeric/nullif(s.n,0),0),s.hgap,s.rgap,
  s.hn>=60 and s.hn::numeric/nullif(s.n,0)>=0.5 and s.hgap<=90 and (select s.wake_at from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) s)<=p_as_of,
  s.rn>=60 and s.rn::numeric/nullif(s.n,0)>=0.5 and s.rgap<=90 and (select s.wake_at from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) s)<=p_as_of,
  case when exists(select 1 from native) and exists(select 1 from ticks t where not exists(select 1 from native n where n.ts=t.hts)) then 'mixed_rmssd' when exists(select 1 from native) then 'minute_rmssd' else 'five_minute_rmssd' end from stats s;
$$;
create or replace function nb.night_evidence_parts(p_user uuid,p_user_day date) returns table(hrv numeric,rhr numeric,hrv_bucket_count integer,hrv_tick_count integer,
 expected_minutes integer,hrv_minutes integer,rhr_minutes integer,hrv_coverage numeric,
 rhr_coverage numeric,hrv_longest_gap integer,rhr_longest_gap integer,hrv_eligible boolean,rhr_eligible boolean,hrv_source text)
language sql stable set search_path='' as $$ select * from nb.night_evidence_parts_at(p_user,p_user_day,nb.calculation_clock()); $$;
create or replace function nb.night_hrv_parts(p_user uuid,p_user_day date)
returns table(rmssd_ms numeric,bucket_count integer,tick_count integer)
language sql stable set search_path='' as $$
 select h.hrv,h.hrv_bucket_count,h.hrv_tick_count from nb.night_evidence_parts(p_user,p_user_day) h;
$$;
create or replace function nb.night_rhr(p_user uuid,p_user_day date,p_tz text)
returns numeric language sql stable set search_path='' as $$
 select n.rhr from nb.night_evidence_parts(p_user,p_user_day) n;
$$;

create or replace function nb.charge_multiplier_at(p_user uuid,p_user_day date,p_tz text,p_as_of timestamptz)
returns numeric language plpgsql stable set search_path='' as $$
declare cur record; b record; mh numeric:=1; mr numeric:=1;
begin
 select * into cur from nb.night_evidence_parts_at(p_user,p_user_day,p_as_of);
 with nights as materialized (
  select n.* from generate_series(p_user_day-14,p_user_day-1,interval '1 day') d
  cross join lateral nb.night_evidence_parts_at(p_user,d::date,p_as_of) n
 ) select count(hrv) filter(where hrv_eligible) hn,avg(hrv) filter(where hrv_eligible) hm,
   stddev_samp(hrv) filter(where hrv_eligible) hs,count(rhr) filter(where rhr_eligible) rn,
   avg(rhr) filter(where rhr_eligible) rm,stddev_samp(rhr) filter(where rhr_eligible) rs into b from nights;
 -- Baseline eligibility is an engineering quality gate: >=60 covered minutes,
 -- >=50% of actual sleep minutes, and no missing run longer than 90 minutes.
 -- The floor makes constant baselines continuous with low-variance baselines.
 if cur.hrv_eligible and b.hn>=5 then mh:=least(1.25,greatest(0.75,1+0.25*(cur.hrv-b.hm)/greatest(coalesce(b.hs,0),0.5))); end if;
 if cur.rhr_eligible and b.rn>=5 then mr:=least(1.25,greatest(0.75,1+0.25*(b.rm-cur.rhr)/greatest(coalesce(b.rs,0),0.5))); end if;
 return least(1.30,greatest(0.65,mh*mr));
end $$;
create or replace function nb.charge_multiplier(p_user uuid,p_user_day date,p_tz text) returns numeric language sql stable set search_path='' as $$ select nb.charge_multiplier_at(p_user,p_user_day,p_tz,nb.calculation_clock()); $$;
create or replace function nb.night_inputs(p_user uuid,p_user_day date)
returns jsonb language plpgsql stable set search_path='' as $$
declare cur record; b record; tz text;
begin
 select p.timezone into tz from nb.calculation_profile(p_user,p_user_day) p;
 if tz is null then return '{}'::jsonb; end if;
 select * into cur from nb.night_evidence_parts(p_user,p_user_day);
 with nights as materialized (
  select n.* from generate_series(p_user_day-14,p_user_day-1,interval '1 day') d
  cross join lateral nb.night_evidence_parts(p_user,d::date) n
 ) select count(hrv) filter(where hrv_eligible) hn,avg(hrv) filter(where hrv_eligible) hm,
   count(rhr) filter(where rhr_eligible) rn,avg(rhr) filter(where rhr_eligible) rm into b from nights;
 return jsonb_build_object('rhr',round(cur.rhr),'rhr_base',round(b.rm),'rhr_nights',b.rn,
  'hrv',round(cur.hrv),'hrv_base',round(b.hm),'hrv_nights',b.hn,
  'multiplier',round(nb.charge_multiplier(p_user,p_user_day,tz),2),
  'hrv_coverage',cur.hrv_coverage,'rhr_coverage',cur.rhr_coverage,
  'hrv_bucket_count',cur.hrv_bucket_count,'hrv_tick_count',cur.hrv_tick_count,
  'expected_minutes',cur.expected_minutes,'hrv_minutes',cur.hrv_minutes,'rhr_minutes',cur.rhr_minutes,
  'hrv_longest_gap',cur.hrv_longest_gap,'rhr_longest_gap',cur.rhr_longest_gap,
  'hrv_eligible',cur.hrv_eligible,'rhr_eligible',cur.rhr_eligible,'hrv_source',cur.hrv_source);
end $$;

-- A previous close is eligible only when it was produced by this algorithm. Cold
-- starts carry their origin through every derived close; rounding happens at display.
create or replace function nb.reserve_anchor_info(p_user uuid,p_user_day date)
returns table(value numeric,assumed boolean,origin text)
language plpgsql stable set search_path='' as $$
declare lo timestamptz; hi timestamptz; s timestamptz; previous record; back numeric;
begin
 select b.starts_at,b.ends_at into lo,hi from nb.calculation_profile(p_user,p_user_day) p
 cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b;
 select coalesce(nb.bb_number(rd.drain_drivers->>'close_value'),rd.current_value) val,
  coalesce((rd.drain_drivers->>'assumed_anchor')::boolean,true) assumed,
  coalesce(rd.drain_drivers->>'anchor_origin','legacy_assumption') origin into previous
 from public.reserve_daily rd join public.daily_results dr on dr.id=rd.result_id
 where dr.user_id=p_user and dr.user_day=p_user_day-1 and dr.algo_version like '%bb-2.1%'
 and rd.current_value is not null;
 if previous.val is not null then return query select previous.val,previous.assumed,previous.origin; return; end if;
 select min(n.sleep_start) into s from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day+1) n
 where n.user_id=p_user and n.user_day between p_user_day and p_user_day+1
 and n.sleep_start<hi and n.wake_at>lo and exists(select 1 from nb.sleep_evidence_minutes(p_user,n.user_day));
 if s<lo and s>=lo-interval '48 hours' then
  -- Rebuild the preceding sleep segment when no compatible close exists. Recursion
  -- ends on the day containing sleep_start, where the documented seed is 20.
  select r.value into back from nb.reserve_replay(p_user,p_user_day-1) r order by r.ts desc limit 1;
 end if;
 return query select coalesce(back,case when s is not null then 20::numeric else 50::numeric end),true,
  case when s is not null then 'first_sleep_20' else 'first_observation_50' end;
end $$;
create or replace function nb.reserve_anchor(p_user uuid,p_user_day date)
returns numeric language sql stable set search_path='' as $$
 select a.value from nb.reserve_anchor_info(p_user,p_user_day) a;
$$;

create or replace function nb.reserve_replay_uncached(p_user uuid, p_user_day date)
returns table (
  ts        timestamptz,
  value     numeric,
  asleep    boolean,
  d_charge  numeric,
  d_basal   numeric,
  d_active  numeric,
  d_stress  numeric
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz       text;
  v_birth    date;
  v_lo       timestamptz;
  v_hi       timestamptz;
  v_anchor   numeric;
  v_rhr      numeric;
  v_hr_max   numeric;
  v_hrv_base numeric;
begin
  select p.timezone, p.birth_date into v_tz, v_birth
  from nb.calculation_profile(p_user,p_user_day) p where p.user_id = p_user;
  if v_tz is null then return; end if;
  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);

  v_anchor := nb.reserve_anchor(p_user, p_user_day);

  v_rhr    := coalesce((select n.rhr from nb.night_evidence_parts_at(p_user,p_user_day,nb.calculation_instant(p_user,p_user_day)) n),
                       nb.hr_rest(p_user, p_user_day, v_tz), 55);
  v_hr_max := coalesce(nb.hr_max(v_birth), 190);

  with history as materialized (
    select n.hrv from generate_series(p_user_day-14,p_user_day-1,interval '1 day') d
    cross join lateral nb.night_evidence_parts_at(p_user,d::date,nb.calculation_instant(p_user,p_user_day)) n where n.hrv_eligible
  ) select avg(h.hrv) into v_hrv_base from history h;

  return query
  with recursive
  night as materialized (
    select s.user_day,nb.charge_multiplier_at(p_user,s.user_day,v_tz,nb.calculation_instant(p_user,p_user_day)) multiplier
    from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day+1) s where s.user_id=p_user
      and s.user_day between p_user_day and p_user_day+1
  ),
  sleep_minutes as materialized (
    select m.ts,max(m.stage) stage,max(m.q*n.multiplier) recovery
    from night n cross join lateral nb.sleep_evidence_minutes(p_user,n.user_day) m
    where m.ts>=v_lo and m.ts<v_hi group by m.ts
  ),
  sleep_evidence as materialized (
    select date_bin(interval '5 minutes',m.ts,v_lo) t,
      least(1,count(*)::numeric/5) recorded_fraction,
      least(1,count(*) filter(where m.stage<>4)::numeric/5) sleep_fraction,
      sum(case when m.stage=4 then 0 else m.recovery end)/5 recovery_effect
    from sleep_minutes m
    group by 1
  ),
  tick_grid as (
    select generate_series(
      v_lo,
      least(v_hi - interval '5 minutes', date_bin(interval '5 minutes', nb.calculation_instant(p_user,p_user_day), v_lo) - interval '5 minutes'),
      interval '5 minutes'
    ) as t
  ),
  observed as (
    select g.t,
           r.heart,
           r.hrv,
           r.stress,
           r.step,
           r.met,
           coalesce(st.recorded_fraction, 0) as recorded_fraction,
           coalesce(st.sleep_fraction, 0) as sleep_fraction,
           coalesce(st.recovery_effect, 0) as recovery_effect
    from tick_grid g
    left join lateral (
      select sample.heart, sample.hrv, sample.stress, sample.step, sample.met
      from public.raw_samples sample
      where sample.user_id = p_user and sample.ts = g.t
      order by (sample.src = 'band') desc
      limit 1
    ) r on true
    left join sleep_evidence st on st.t = g.t
  ),
  fused as (
    select o.*,
           o.heart is not null or o.hrv is not null or o.stress is not null
             or coalesce(o.step, 0) > 0 or coalesce(o.met, 0) > 1.05 as sensor_worn,
           greatest(
             case
               when o.heart is null or v_hr_max <= v_rhr then 0
               when (o.heart - v_rhr) / (v_hr_max - v_rhr) >= 0.85 then 0.75
               when (o.heart - v_rhr) / (v_hr_max - v_rhr) >= 0.70 then 0.38
               when (o.heart - v_rhr) / (v_hr_max - v_rhr) >= 0.55 then 0.16
               when (o.heart - v_rhr) / (v_hr_max - v_rhr) >= 0.40 then 0.06
               when (o.heart - v_rhr) / (v_hr_max - v_rhr) >= 0.30 then 0.02
               else 0
             end,
             least(0.75, 0.08 * greatest(0, coalesce(o.met, 1) - 1)),
             least(0.75, coalesce(o.step, 0)::numeric / 800 * 0.50)
           ) as move
    from observed o
  ),
  feature as (
    select f.*,
           f.recorded_fraction > 0 or f.sensor_worn as worn,
           greatest(0, case
             when f.sensor_worn then 1 - f.sleep_fraction
             else f.recorded_fraction - f.sleep_fraction
           end) as awake_fraction,
           (
             0.10 * greatest(0, coalesce(f.stress, 40) - 40) / 60
             + case when f.hrv is not null and v_hrv_base is not null and v_hrv_base > 0
                    then 0.08 * least(1, greatest(0, (v_hrv_base - f.hrv) / v_hrv_base))
                    else 0 end
           ) * greatest(0.25, 1 - f.move / 0.75) as strain,
           f.sleep_fraction = 0
             and f.sensor_worn
             and f.heart is not null and f.heart <= v_rhr + 8
             and f.stress is not null and f.stress <= 35
             and f.hrv is not null and v_hrv_base is not null and f.hrv >= v_hrv_base * 0.90
             and f.move < 0.03 and f.step is not null and f.step = 0 as quiet
    from fused f
  ),
  numbered as (
    select row_number() over (order by f.t)::integer as n, f.*
    from feature f
  ),
  replay as (
    select 0::integer as n, v_lo as t, v_anchor::numeric as value,
           false as in_sleep, false as observed,
           0::numeric as d_charge, 0::numeric as d_basal,
           0::numeric as d_active, 0::numeric as d_stress,
           0::numeric as quiet_minutes, 0::numeric as rest_used
    union all
    select x.n, x.t, step.next_value, x.sleep_fraction >= 0.5, x.worn,
           r.d_charge + step.effective_charge,
           r.d_basal - step.effective_awake + step.effective_rest,
           r.d_active - step.effective_move,
           r.d_stress - step.effective_strain,
           step.next_quiet_minutes,
           r.rest_used + step.effective_rest
    from replay r
    join numbered x on x.n = r.n + 1
    cross join lateral (
      select case when x.quiet then r.quiet_minutes + 5 else 0 end as next_quiet_minutes
    ) quiet
    cross join lateral (
      select case
        when x.recovery_effect > 0 then
          greatest(0, 95 - r.value)
            * (1 - exp(-0.011 * x.recovery_effect))
        else 0 end as raw_charge,
        case when x.worn then 0.12 * x.awake_fraction else 0 end as raw_awake,
        case when x.worn then x.move * x.awake_fraction else 0 end as raw_move,
        case when x.worn then x.strain * x.awake_fraction else 0 end as raw_strain,
        case when x.quiet and quiet.next_quiet_minutes > 20
                       and r.rest_used < 5 and r.value < 80
             then least(5 - r.rest_used, 0.05 * greatest(0, (80 - r.value) / 80))
             else 0 end as raw_rest
    ) raw
    cross join lateral (
      select case
        when raw.raw_awake + raw.raw_move + raw.raw_strain - raw.raw_rest > r.value
          then r.value / nullif(raw.raw_awake + raw.raw_move + raw.raw_strain - raw.raw_rest, 0)
        else 1 end as drain_scale
    ) scale
    cross join lateral (
      select least(100, greatest(0,
               r.value + raw.raw_charge
               - raw.raw_awake * scale.drain_scale
               - raw.raw_move * scale.drain_scale
               - raw.raw_strain * scale.drain_scale
               + raw.raw_rest * scale.drain_scale)) as next_value,
             raw.raw_charge as effective_charge,
             raw.raw_awake * scale.drain_scale as effective_awake,
             raw.raw_move * scale.drain_scale as effective_move,
             raw.raw_strain * scale.drain_scale as effective_strain,
             raw.raw_rest * scale.drain_scale as effective_rest,
             quiet.next_quiet_minutes
    ) step
  )
  select r.t, r.value, r.in_sleep, r.d_charge, r.d_basal, r.d_active, r.d_stress
  from replay r
  where r.n > 0 and r.observed
  order by r.t;
end;
$$;

create or replace function nb.compute_reserve(p_user uuid,p_user_day date)
returns table(wake_value smallint,current_value smallint,min_value smallint,drivers jsonb)
language plpgsql stable set search_path='' as $$
declare tz text; lo timestamptz; hi timestamptz; instant timestamptz; n record; a record; r record; ns record;
 inputs jsonb; cov jsonb; day_cov record; day_start timestamptz; confidence text;
 wa numeric; nc numeric; observed_at timestamptz; vals integer[]; residual integer; biggest integer;
begin
 select p.timezone into tz from nb.calculation_profile(p_user,p_user_day) p;
 if tz is null then return; end if;
 select b.starts_at,b.ends_at into lo,hi from nb.user_day_bounds(p_user_day,tz) b;
 instant:=nb.calculation_instant(p_user,p_user_day);
 select * into a from nb.reserve_anchor_info(p_user,p_user_day);
 select s.sleep_start,s.wake_at into n from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) s
 where s.user_id=p_user and s.user_day=p_user_day;
 with replay as materialized(select * from nb.reserve_replay(p_user,p_user_day)), last as (
  select * from replay order by ts desc limit 1
 ) select l.*,(select min(x.value) from replay x) low into r from last l;

 -- A morning belongs to the real final wake, including wakes before the 04:00 seam.
 -- The day curve is an accumulated ledger, so subtract its value immediately before
 -- sleep_start from its value at wake on each day; tonight never enters last night's sum.
 if n.wake_at is not null and n.wake_at<=instant and n.wake_at>n.sleep_start
 and n.wake_at-n.sleep_start<=interval '48 hours'
 and exists(select 1 from nb.sleep_evidence_minutes(p_user,p_user_day) m where m.ts>=n.wake_at-interval '5 minutes') then
  with days as (
   select d::date as user_day from generate_series(nb.user_day_of(n.sleep_start,tz),nb.user_day_of(n.wake_at-interval '1 microsecond',tz),interval '1 day') d
  ), rows as materialized (
   select d.user_day,x.* from days d cross join lateral nb.reserve_replay(p_user,d.user_day) x
  ), deltas as (
   select x.*,x.d_charge-coalesce(lag(x.d_charge) over(partition by x.user_day order by x.ts),0) charge from rows x
  ) select (select x.value from rows x where x.ts=date_bin(interval '5 minutes',n.wake_at-interval '1 microsecond',lo) order by x.ts desc limit 1) wake,
    (select sum(x.charge) from deltas x where x.ts>=date_bin(interval '5 minutes',n.sleep_start,lo) and x.ts<n.wake_at) charge into ns;
  wa:=ns.wake; nc:=ns.charge;
 end if;
 if r.value is null and wa is null then return; end if;
 observed_at:=case when r.ts is not null then least(r.ts+interval '5 minutes',instant) else n.wake_at end;
 if r.value is null then
  r.value:=a.value; r.low:=a.value; r.d_charge:=0; r.d_basal:=0; r.d_active:=0; r.d_stress:=0;
 end if;
 if abs(r.d_charge+r.d_basal+r.d_active+r.d_stress-(r.value-a.value))>0.000001 then
  raise exception 'BODY_BATTERY_ATTRIBUTION_DOES_NOT_CLOSE';
 end if;
 vals:=array[round(r.d_charge)::integer,round(r.d_basal)::integer,round(r.d_active)::integer,round(r.d_stress)::integer];
 residual:=round(r.value)::integer-round(a.value)::integer-(vals[1]+vals[2]+vals[3]+vals[4]);
 select i into biggest from unnest(array[abs(r.d_charge),abs(r.d_basal),abs(r.d_active),abs(r.d_stress)]) with ordinality v(x,i) order by x desc,i limit 1;
 vals[biggest]:=vals[biggest]+residual;
 inputs:=nb.night_inputs(p_user,p_user_day);
 day_start:=greatest(lo,case when wa is not null then n.wake_at else lo end);
 with grid as (
  select g.ts from generate_series(date_bin(interval '5 minutes',day_start,lo),least(hi,instant)-interval '5 minutes',interval '5 minutes') g(ts)
 ), evidence as (
  select g.ts,x.* from grid g left join lateral (
   select s.heart,s.hrv,s.stress,s.step,s.met from public.raw_samples s where s.user_id=p_user and s.ts=g.ts order by(s.src='band') desc limit 1
  ) x on true
 ) select count(*) expected,count(*) filter(where heart is not null or hrv is not null or stress is not null or coalesce(step,0)>0 or coalesce(met,0)>1.05) observed,
 count(heart)::numeric/nullif(count(*),0) heart,count(hrv)::numeric/nullif(count(*),0) hrv,count(stress)::numeric/nullif(count(*),0) stress into day_cov from evidence;
 cov:=jsonb_build_object('night_hrv',inputs->'hrv_coverage','night_rhr',inputs->'rhr_coverage',
  'night_expected_minutes',inputs->'expected_minutes','night_hrv_minutes',inputs->'hrv_minutes','night_rhr_minutes',inputs->'rhr_minutes',
  'night_hrv_longest_gap',inputs->'hrv_longest_gap','night_rhr_longest_gap',inputs->'rhr_longest_gap',
  'hrv_nights',inputs->'hrv_nights','rhr_nights',inputs->'rhr_nights',
  'day_expected_ticks',day_cov.expected,'day_observed_ticks',day_cov.observed,
  'day_heart',day_cov.heart,'day_hrv',day_cov.hrv,'day_stress',day_cov.stress);
 -- Engineering data sufficiency, not a confidence interval or clinical validation.
 -- Seed provenance stays explicit; confidence measures coverage, not seed accuracy.
 confidence:=case when (inputs->>'hrv_eligible')::boolean and (inputs->>'rhr_eligible')::boolean
   and (inputs->>'hrv_nights')::integer>=5 and (inputs->>'rhr_nights')::integer>=5
   and (day_cov.expected=0 or least(day_cov.heart,day_cov.hrv,day_cov.stress)>=0.5) then 'high'
  when wa is not null and (day_cov.expected=0 or coalesce(day_cov.heart,0)>=0.5) then 'medium' else 'low' end;
 return query select round(wa)::smallint,round(r.value)::smallint,round(coalesce(r.low,r.value))::smallint,
  jsonb_build_object('anchor',round(a.value),'assumed_anchor',a.assumed,'anchor_origin',a.origin,
   'close_value',round(r.value,12),'last_night',vals[1],'day_charge',vals[1],'night_charge',round(nc),
   'awake',vals[2],'movement',vals[3],'stress',vals[4],
   'wake_at',case when wa is not null then n.wake_at end,'observed_at',observed_at,
   'confidence',confidence,'coverage',cov,'algo_version','bb-2.1');
end $$;

-- Keep publication, caching, historical profile/clock, archive recovery and locking.
-- Only the version predicate changes; old outputs remain pending until ordered replay.
do $$
declare def text; patched text; target text;
begin
 foreach target in array array['nb.settle_day(uuid,date)','nb.recompute_range(uuid,date,date,text)','public.calculation_status(date,date)'] loop
  def:=pg_get_functiondef(target::regprocedure);
  if target='nb.settle_day(uuid,date)' then
   patched:=replace(def,'bb-2.0','bb-2.1');
  elsif target='nb.recompute_range(uuid,date,date,text)' then
   patched:=replace(def,'r.algo_version like ''%/calc-1''','r.algo_version like ''%bb-2.1%/calc-1''');
  else
   patched:=replace(def,'r.algo_version not like ''%/calc-1''','r.algo_version not like ''%bb-2.1%/calc-1''');
  end if;
  if def=patched then raise exception 'BB21_VERSION_PATCH_MISSING: %',target; end if;
  execute patched;
 end loop;
end $$;

-- Input changes must invalidate the whole carry-forward chain, including archived
-- history. The existing recovery workflow hydrates old raw facts before replaying it.
insert into nb.calculation_work(user_id,dirty_from)
select user_id,min(user_day) from public.daily_results group by user_id
on conflict(user_id) do update set input_revision=nb.calculation_work.input_revision+1,
 dirty_from=least(nb.calculation_work.dirty_from,excluded.dirty_from);

revoke all on function nb.canonical_sleep_nights(uuid,date,date),nb.bb_number(text),nb.bb_instant(text),nb.sleep_evidence_minutes(uuid,date),
 nb.night_evidence_parts(uuid,date),nb.night_evidence_parts_at(uuid,date,timestamptz),nb.charge_multiplier_at(uuid,date,text,timestamptz),nb.reserve_anchor_info(uuid,date) from public,anon,authenticated;
