-- bb-3.0: observed physiological strain and restorative rest at any hour.
-- Product estimation parameters, not a clinically calibrated energy measurement.
-- Keep the authoritative replay, clock, archive recovery and four-term ledger.

create function nb.reserve_rates(heart numeric, hrv numeric, stress numeric, steps numeric, met numeric,
 resting numeric, maximum numeric, reference_heart numeric, reference_hrv numeric, auxiliary numeric)
returns table(movement numeric, strain numeric, rest numeric, recovery numeric)
language sql immutable set search_path='' as $$
 with h as (
  select least(1,greatest(0,(heart-resting)/greatest(1,maximum-resting))) hrr,
   case when met is not null or steps is not null then greatest(
    least(1,greatest(0,(coalesce(met,1)-1.2)/0.3)),least(1,greatest(0,coalesce(steps,0)/25))) else 1 end activity
 ), move as (
  select greatest(coalesce((select y0+(y1-y0)*(h.hrr-x0)/(x1-x0)
   from (values (0::numeric,0.30::numeric,0::numeric,0.06::numeric),
    (0.30,0.40,0.06,0.30),(0.40,0.55,0.30,1.20),(0.55,0.70,1.20,3.60),
    (0.70,0.85,3.60,6.40),(0.85,1.01,6.40,6.40)) k(x0,x1,y0,y1)
   where h.hrr>=x0 and h.hrr<x1),0)*h.activity,
   least(6.4,0.12*greatest(0,coalesce(met,1)-1)),least(6.4,coalesce(steps,0)/800*0.60)) movement
  from h
 ), signals as (
  select array(select v from (values
   (case when stress is not null then least(1,greatest(0,(stress-40)/50)) end),
   (case when heart is not null then least(1,greatest(0,(heart-reference_heart-5)/30)) end),
   (case when hrv is not null and reference_hrv>0 then least(1,greatest(0,(0.90-hrv/reference_hrv)/0.50)) end)
  ) s(v) where v is not null order by v desc) a,
  array(select v from (values
   (case when stress is not null then least(1,greatest(0,(50-stress)/25)) end),
   (case when hrv is not null and reference_hrv>0 then least(1,greatest(0,(hrv/reference_hrv-0.65)/0.35)) end)
  ) c(v) where v is not null) calm
 ), intensity as (
  select least(1,coalesce(a[1],0)+0.15*coalesce(a[2],0)) intensity,calm from signals
 ), shaped as (
  select m.movement,i.*,power(1-i.intensity,2)*(1-0.6*auxiliary) recovery,
   case when heart is not null then least(1,greatest(0,(resting+15-heart)/12)) else 0 end heart_calm,
   case when met is not null or steps is not null then least(
    least(1,greatest(0,(1.5-coalesce(met,1))/0.3)),least(1,greatest(0,(25-coalesce(steps,0))/20))) else 0 end motion_calm
  from move m cross join intensity i
 ) select s.movement,(0.65*s.intensity*s.intensity+0.15*auxiliary*s.intensity)*greatest(0.2,1-s.movement/3.6),
  s.heart_calm*s.motion_calm*coalesce((select min(c) from unnest(s.calm) c),1)
   *case cardinality(s.calm) when 2 then 1 when 1 then 0.8 else 0.55 end*s.recovery,s.recovery
 from shaped s;
$$;

-- Robust matched-context history. Today's elevated resting pulse never becomes
-- its own normal. Daily medians prevent denser recording days dominating the baseline.
create function nb.reserve_baseline(p_user uuid,p_day date)
returns jsonb language sql stable set search_path='' as $$
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
 ), points as materialized (
  select distinct on(s.ts) s.*,(s.ts at time zone p.timezone)::date as day,
   exists(select 1 from sleep m where m.ts>=s.ts and m.ts<s.ts+interval '5 minutes') sleeping
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
$$;

create or replace function nb.reserve_replay_uncached(p_user uuid,p_user_day date)
returns table(ts timestamptz,value numeric,asleep boolean,d_charge numeric,d_basal numeric,d_active numeric,d_stress numeric)
language plpgsql stable set search_path='' as $$
declare
 v_tz text; v_birth date; v_lo timestamptz; v_hi timestamptz; v_instant timestamptz;
 v_anchor numeric; v_base jsonb; v_rhr numeric; v_hr_max numeric; v_slept numeric; v_debt numeric;
begin
 select p.timezone,p.birth_date into v_tz,v_birth from nb.calculation_profile(p_user,p_user_day) p;
 if v_tz is null then return; end if;
 select starts_at,ends_at into v_lo,v_hi from nb.user_day_bounds(p_user_day,v_tz);
 v_instant:=nb.calculation_instant(p_user,p_user_day);
 v_anchor:=nb.reserve_anchor(p_user,p_user_day);
 v_base:=nb.reserve_baseline(p_user,p_user_day);
 v_rhr:=(v_base->>'resting_heart')::numeric;
 v_hr_max:=coalesce(nb.hr_max(v_birth),190);
 select count(*) into v_slept from nb.sleep_evidence_minutes(p_user,p_user_day) m
 where m.stage<>4 and m.ts<v_instant;
 if v_slept>0 then
  v_debt:=1+0.6*least(1,greatest(0,(420-v_slept)/180));
 else
  -- Do not label the first few minutes after midnight as a whole sleepless night.
  -- Require the eight-hour observation window to have completed, and distinct slots.
  select case when v_instant>=v_lo+interval '8 hours' and count(distinct date_bin(interval '5 minutes',s.ts,v_lo))>=48
   then 1.6 else 1 end into v_debt from public.raw_samples s
  where s.user_id=p_user and s.ts>=v_lo and s.ts<v_lo+interval '8 hours' and s.ts<v_instant
   and (s.heart between 30 and 250 or s.hrv between 1 and 300 or s.stress between 1 and 100
    or s.step>0 or s.met between 1.05 and 25);
 end if;
 return query
 with recursive
 night as materialized (
  select s.user_day,nb.charge_multiplier_at(p_user,s.user_day,v_tz,v_instant) multiplier
  from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day+1) s
 ), sleep_minutes as materialized (
  select m.ts,max(m.stage) stage,max(m.q*n.multiplier) recovery
  from night n cross join lateral nb.sleep_evidence_minutes(p_user,n.user_day) m
  where m.ts>=v_lo and m.ts<least(v_hi,v_instant) group by m.ts
 ), sleep_evidence as materialized (
  select date_bin(interval '5 minutes',m.ts,v_lo) t,
   least(1,count(*)::numeric/5) recorded_fraction,
   least(1,count(*) filter(where m.stage<>4)::numeric/5) sleep_fraction,
   sum(case when m.stage=4 then 0 else m.recovery end)/5 recovery_effect
  from sleep_minutes m group by 1
 ), fine_heart as materialized (
  select f.ts,sum(extract(epoch from(f.ends_at-f.starts_at)))/300 fraction,
   sum(a.movement*extract(epoch from(f.ends_at-f.starts_at)))/300 movement
  from nb.training_heart_intervals(p_user,p_user_day) f
  cross join lateral nb.reserve_rates(f.heart,null,null,null,null,v_rhr,v_hr_max,v_rhr,null,0) a
  group by f.ts
 ), fine_energy as materialized (select * from nb.strength_energy_ticks(p_user,p_user_day)),
 fine as materialized (
  select coalesce(h.ts,e.ts) t,greatest(coalesce(h.fraction,0),coalesce(e.observed_seconds/300,0)) fraction,
   greatest(coalesce(h.movement,0),coalesce(0.12*e.excess_met_seconds/300,0)) movement
  from fine_heart h full join fine_energy e using(ts)
 ), tick_grid as (
  select generate_series(v_lo,
   least(v_hi-interval '5 minutes',greatest(date_bin(interval '5 minutes',v_instant,v_lo)-interval '5 minutes',
    coalesce((select max(f.t) from fine f),v_lo-interval '5 minutes'),
    coalesce((select max(date_bin(interval '5 minutes',s.ts,v_lo)) from public.raw_samples s
     where s.user_id=p_user and s.ts>=v_lo and s.ts<v_hi and s.ts<=v_instant),v_lo-interval '5 minutes'))),
   interval '5 minutes') t
 ), observed as materialized (
  select g.t,r.*,o.oxygen,coalesce(f.fraction,0) fine_fraction,coalesce(f.movement,0) fine_movement,
   coalesce(st.recorded_fraction,0) recorded_fraction,coalesce(st.sleep_fraction,0) sleep_fraction,
   coalesce(st.recovery_effect,0) recovery_effect
  from tick_grid g left join fine f on f.t=g.t
  left join lateral (
   select case when s.heart between 30 and 250 then s.heart end heart,
    case when s.hrv between 1 and 300 then s.hrv end hrv,
    case when s.stress between 1 and 100 then s.stress end stress,
    case when s.step>=0 then s.step end step,case when s.met between 0.5 and 25 then s.met end met,
    case when s.temp between 10 and 50 then s.temp end temp
   from public.raw_samples s where s.user_id=p_user and s.ts>=g.t and s.ts<g.t+interval '5 minutes' and s.ts<=v_instant
   order by(s.src='band') desc,s.ts desc,s.src limit 1
  ) r on true
  left join sleep_evidence st on st.t=g.t
  left join lateral (
   select percentile_cont(0.5) within group(order by s.spo2)::numeric oxygen
   from public.oxygen_samples s where s.user_id=p_user and s.ts>=g.t and s.ts<g.t+interval '5 minutes'
    and s.ts<v_instant and s.spo2 between 50 and 100
    and exists(select 1 from sleep_minutes m where m.ts=date_trunc('minute',s.ts) and m.stage<>4)
  ) o on true
 ), risks as (
  select o.*,
   o.heart is not null or o.hrv is not null or o.stress is not null or coalesce(o.step,0)>0 or coalesce(o.met,1)>1.05 sensor_worn,
   case when o.temp is not null and (v_base->>case when o.sleep_fraction>=0.5 then 'sleep_temperature' else 'day_temperature' end) is not null
    then least(1,greatest(0,(o.temp-(v_base->>case when o.sleep_fraction>=0.5 then 'sleep_temperature' else 'day_temperature' end)::numeric
     -(v_base->>case when o.sleep_fraction>=0.5 then 'sleep_temperature_scale' else 'day_temperature_scale' end)::numeric))) end temp_risk,
   case when o.sleep_fraction>=0.5 and o.oxygen is not null then least(1,greatest(0,(95-o.oxygen)/5)) end oxygen_risk
  from observed o
 ), sustained as (
  select r.*,
   greatest(case when count(r.temp_risk) over w=3
     and min((r.sleep_fraction>=0.5)::integer) over w=max((r.sleep_fraction>=0.5)::integer) over w
     and bool_and(r.sensor_worn or r.recorded_fraction>0) over w
    then min(r.temp_risk) over w else 0 end,
    case when count(r.oxygen_risk) over w=3 then min(r.oxygen_risk) over w else 0 end) auxiliary
  from risks r window w as(order by r.t rows between 2 preceding and current row)
 ), feature as (
  select s.*,s.recorded_fraction>0 or s.sensor_worn or s.fine_fraction>0 worn,
   greatest(s.fine_fraction,case when s.sensor_worn then 1-s.sleep_fraction else s.recorded_fraction-s.sleep_fraction end) awake_fraction,
   a.movement,a.strain,case when s.fine_movement>0 then 0 else a.rest end rest,n.strain sleep_strain,
   n.recovery*case when s.sleep_fraction>0 then greatest(0,s.sleep_fraction-s.fine_fraction)/s.sleep_fraction else 1 end sleep_recovery
  from sustained s cross join lateral nb.reserve_rates(s.heart,s.hrv,s.stress,s.step,s.met,v_rhr,v_hr_max,
   (v_base->>'day_heart')::numeric,(v_base->>'day_hrv')::numeric,s.auxiliary) a
  cross join lateral nb.reserve_rates(s.heart,s.hrv,s.stress,s.step,s.met,v_rhr,v_hr_max,
   v_rhr,(v_base->>'sleep_hrv')::numeric,s.auxiliary) n
 ), numbered as materialized (
  select row_number() over(order by f.t)::integer n,f.* from feature f
 ), replay as (
  select 0::integer n,v_lo t,v_anchor::numeric value,false in_sleep,false observed,
   0::numeric d_charge,0::numeric d_basal,0::numeric d_active,0::numeric d_stress,0::numeric quiet_minutes
  union all
  select x.n,x.t,least(100,greatest(0,r.value+raw.charge+raw.rest-(eff.awake+eff.movement+eff.strain)*scale.k)),
   x.sleep_fraction>=0.5,x.worn,r.d_charge+raw.charge+raw.rest,
   r.d_basal-eff.awake*scale.k,r.d_active-eff.movement*scale.k,r.d_stress-eff.strain*scale.k,q.minutes
  from replay r join numbered x on x.n=r.n+1
  cross join lateral (
   select case when x.worn and x.sleep_fraction=0 and x.rest>0 then r.quiet_minutes+5 else 0 end minutes
  ) q
  cross join lateral (
   select greatest(0,95-r.value)*(1-exp(-0.011*x.recovery_effect*x.sleep_recovery)) charge,
    case when q.minutes>20 then greatest(0,90-r.value)*(1-exp(-0.006*x.rest*least(1,(q.minutes-20)/20))) else 0 end rest,
    case when x.worn then 0.15*v_debt*(1-0.75*x.rest)*x.awake_fraction else 0 end awake,
    case when x.worn then greatest(x.movement*x.awake_fraction,x.fine_movement) else 0 end movement,
    case when x.worn then x.strain*x.awake_fraction+0.75*x.sleep_strain*x.sleep_fraction else 0 end strain
  ) raw
  cross join lateral (
   select (0.35+0.65*r.value/100)*case when raw.awake+raw.movement+raw.strain>0 then
    (1-exp(-0.0065*(raw.awake+raw.movement+raw.strain)))/(0.0065*(raw.awake+raw.movement+raw.strain)) else 1 end k
  ) soft
  cross join lateral (select raw.awake*soft.k awake,raw.movement*soft.k movement,raw.strain*soft.k strain) eff
  cross join lateral (
   select case when eff.awake+eff.movement+eff.strain>0
    then least(1,(r.value+raw.charge+raw.rest)/(eff.awake+eff.movement+eff.strain)) else 1 end k
  ) scale
 )
 select r.t,r.value,r.in_sleep,r.d_charge,r.d_basal,r.d_active,r.d_stress
 from replay r where r.n>0 and r.observed order by r.t;
end;
$$;

-- A current recommendation for the day's total load. Completed load never falls;
-- exceeding this recommendation leaves zero additional load to pursue.
create function nb.reserve_training_target(p_current numeric,p_smoothed numeric,p_load numeric)
returns jsonb language sql immutable set search_path='' as $$
 with reserve as (select least(100,greatest(0,least(p_current,coalesce(p_smoothed,p_current)))) b),
 goal as (
  select round(k.y0+(k.y1-k.y0)*(r.b-k.x0)/(k.x1-k.x0),1) value
  from reserve r cross join (values (0::numeric,20::numeric,0::numeric,4::numeric),
   (20,30,4,6),(30,40,6,8),(40,50,8,10),(50,60,10,11.5),(60,70,11.5,13),
   (70,80,13,14.5),(80,90,14.5,16),(90,101,16,18.2)) k(x0,x1,y0,y1)
  where r.b>=k.x0 and r.b<k.x1 and p_current is not null
 ) select jsonb_build_object('value',g.value,'optimal_low',greatest(0,g.value-2.5),
   'optimal_high',least(20,g.value+2.5),'remaining',case when p_load is not null then greatest(0,g.value-p_load) end,
   'basis','current_reserve','reserve',p_current,'smoothed_reserve',p_smoothed)
 from goal g;
$$;

-- Preserve the complete publication contract, adding one server-owned target.
CREATE OR REPLACE FUNCTION nb.compute_reserve(p_user uuid, p_user_day date)
 RETURNS TABLE(wake_value smallint, current_value smallint, min_value smallint, drivers jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare tz text; lo timestamptz; hi timestamptz; instant timestamptz; n record; a record; r record; ns record;
 inputs jsonb; cov jsonb; target jsonb; smoothed numeric; load numeric; baseline jsonb; day_cov record; day_start timestamptz; confidence text;
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

 -- A morning belongs to the real final wake, including early-morning wakes.
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
 -- Reductions follow the latest reserve; recovery raises the recommendation gradually.
 select avg(x.value) into smoothed from nb.reserve_replay(p_user,p_user_day) x
 where x.ts>r.ts-interval '15 minutes' and x.ts<=r.ts;
 select t.training_load into load from nb.compute_training(p_user,p_user_day) t;
 target:=nb.reserve_training_target(r.value,smoothed,load)||jsonb_build_object(
  'observed_at',observed_at,'morning_target',nb.target_load(round(wa)::smallint),
  'fresh',observed_at<=instant and observed_at>instant-interval '90 minutes','estimated_start',a.assumed);
 baseline:=nb.reserve_baseline(p_user,p_user_day);
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
   and (baseline->>'sleep_hrv_nights')::integer>=5 and (baseline->>'rhr_nights')::integer>=5
   and (day_cov.expected=0 or (least(day_cov.heart,day_cov.hrv,day_cov.stress)>=0.5
    and (baseline->>'day_hrv_days')::integer>=5 and (baseline->>'day_heart_days')::integer>=5)) then 'high'
  when wa is not null and (day_cov.expected=0 or coalesce(day_cov.heart,0)>=0.5) then 'medium' else 'low' end;
 return query select round(wa)::smallint,round(r.value)::smallint,round(coalesce(r.low,r.value))::smallint,
  jsonb_build_object('anchor',round(a.value),'assumed_anchor',a.assumed,'anchor_origin',a.origin,
   'close_value',round(r.value,12),'last_night',vals[1],'day_charge',vals[1],'night_charge',round(nc),
   'awake',vals[2],'movement',vals[3],'stress',vals[4],
   'wake_at',case when wa is not null then n.wake_at end,'observed_at',observed_at,
   'confidence',confidence,'coverage',cov,'algo_version','bb-3.0',
   'training_target',target,'physiology_baseline',baseline);
end $function$
;

CREATE OR REPLACE FUNCTION nb.reserve_anchor_info(p_user uuid, p_user_day date)
 RETURNS TABLE(value numeric, assumed boolean, origin text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare lo timestamptz; hi timestamptz; s timestamptz; previous record; back numeric;
begin
 select b.starts_at,b.ends_at into lo,hi from nb.calculation_profile(p_user,p_user_day) p
 cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b;
 select coalesce(nb.bb_number(rd.drain_drivers->>'close_value'),rd.current_value) val,
  coalesce((rd.drain_drivers->>'assumed_anchor')::boolean,true) assumed,
  coalesce(rd.drain_drivers->>'anchor_origin','legacy_assumption') origin into previous
 from public.reserve_daily rd join public.daily_results dr on dr.id=rd.result_id
 where dr.user_id=p_user and dr.user_day=p_user_day-1 and dr.algo_version like '%bb-3.0%'
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
end $function$
;

-- Invalidate the carry-forward chain; old estimates must not become new anchors.
do $$ declare original text; patched text; begin
 original:=pg_get_functiondef('nb.calculation_version()'::regprocedure);
 patched:=replace(original,'bb-2.2','bb-3.0');
 if patched=original then raise exception 'BB30_VERSION_ANCHOR_MISSING'; end if;
 execute patched;
end $$;
select nb.invalidate_calculation(user_id,min(user_day)) from public.daily_results group by user_id;

revoke all on function nb.reserve_rates(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric),
 nb.reserve_baseline(uuid,date),nb.reserve_training_target(numeric,numeric,numeric),
 nb.reserve_replay_uncached(uuid,date),nb.compute_reserve(uuid,date),nb.reserve_anchor_info(uuid,date)
 from public,anon,authenticated;
