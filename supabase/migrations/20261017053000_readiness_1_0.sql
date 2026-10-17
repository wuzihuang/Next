-- readiness-1.0 / target-1.2
-- Daytime readiness stays put through ordinary waking life. It moves when sleep,
-- quiet rest, real training, or measured physiological strain says so.
-- Table names stay reserve_*. The published score is a 0–100 state, not a percent.

-- Stress burden starts at 45, matching the readiness intensity term (stress-45)/45.
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.reserve_rates(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric)'::regprocedure);
 patched:=replace(def,'(stress-40)/50','(stress-45)/45');
 if patched=def then raise exception 'READINESS_STRESS_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

create or replace function nb.reserve_replay_uncached(p_user uuid,p_user_day date)
returns table(ts timestamptz,value numeric,asleep boolean,d_charge numeric,d_basal numeric,d_active numeric,d_stress numeric)
language plpgsql stable set search_path='' as $$
declare
 v_tz text; v_birth date; v_lo timestamptz; v_hi timestamptz; v_instant timestamptz;
 v_anchor numeric; v_base jsonb; v_rhr numeric; v_hr_max numeric; v_slept numeric; v_debt numeric;
 v_debt_unit numeric; v_short boolean; v_early numeric; v_late numeric; v_wake timestamptz;
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
  select case when v_instant>=v_lo+interval '8 hours' and count(distinct date_bin(interval '5 minutes',s.ts,v_lo))>=48
   then 1.6 else 1 end into v_debt from public.raw_samples s
  where s.user_id=p_user and s.ts>=v_lo and s.ts<v_lo+interval '8 hours' and s.ts<v_instant
   and (s.heart between 30 and 250 or s.hrv between 1 and 300 or s.stress between 1 and 100
    or s.step>0 or s.met between 1.05 and 25);
 end if;
 v_debt_unit:=least(1,greatest(0,(least(coalesce(v_debt,1),1.6)-1)/0.6));
 v_short:=(coalesce(v_slept,0)>0 and v_slept<390) or coalesce(v_debt,1)>=1.6;
 v_early:=case when v_short then 0.04+0.04*v_debt_unit else 0.02 end;
 v_late:=0.10+0.05*v_debt_unit;
 select s.wake_at into v_wake from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) s
  where s.user_id=p_user and s.user_day=p_user_day;
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
   case when s.heart is not null then least(1,greatest(0,(s.heart-v_rhr)/greatest(1,v_hr_max-v_rhr))) else 0 end hrr,
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
   0::numeric d_charge,0::numeric d_basal,0::numeric d_active,0::numeric d_stress,
   0::numeric quiet_minutes,0::numeric awake_minutes,null::numeric morning
  union all
  select x.n,x.t,least(100,greatest(0,r.value+raw.charge+raw.rest-(eff.awake+eff.movement+eff.strain)*scale.k)),
   x.sleep_fraction>=0.5,x.worn,r.d_charge+raw.charge+raw.rest,
   r.d_basal-eff.awake*scale.k,r.d_active-eff.movement*scale.k,r.d_stress-eff.strain*scale.k,
   q.minutes,clock.awake,latched.morning
  from replay r join numbered x on x.n=r.n+1
  cross join lateral (
   select case when x.worn and x.sleep_fraction=0 and x.rest>0 then r.quiet_minutes+5 else 0 end minutes
  offset 0) q
  cross join lateral (
   select case when x.sleep_fraction>=0.5 then 0 else r.awake_minutes+5 end awake
  offset 0) clock
  cross join lateral (
   select case
    when r.morning is not null then r.morning
    when v_wake is not null and x.t>=date_bin(interval '5 minutes',v_wake,v_lo) then least(90,r.value)
    else null end morning
  offset 0) latched
  cross join lateral (
   select greatest(0,95-r.value)*(1-exp(-0.011*x.recovery_effect*x.sleep_recovery)) charge,
    case when q.minutes>20 then greatest(0,coalesce(latched.morning,90)-r.value)
     *(1-exp(-0.006*x.rest*least(1,(q.minutes-20)/20))) else 0 end rest,
    case
     when not x.worn or x.sleep_fraction>=0.5 then 0
     when q.minutes>20 and x.rest>0 and x.sleep_fraction=0 then 0
     else (case
      when r.awake_minutes/60>=14 then v_late
      when r.awake_minutes/60<=10 then v_early
      else v_early+(v_late-v_early)*((r.awake_minutes/60-10)/4)
     end)*x.awake_fraction
    end awake,
    case
     when not x.worn then 0
     when x.fine_movement>0 then greatest(x.movement*x.awake_fraction,x.fine_movement)*0.38
     when x.hrr<0.30 and coalesce(x.met,1)<2.0 then 0
     else x.movement*x.awake_fraction*0.38
    end movement,
    case when x.worn then x.strain*x.awake_fraction+0.75*x.sleep_strain*x.sleep_fraction else 0 end strain
  offset 0) raw
  cross join lateral (
   select (0.35+0.65*r.value/100)*case when raw.awake+raw.movement+raw.strain>0 then
    (1-exp(-0.0065*(raw.awake+raw.movement+raw.strain)))/(0.0065*(raw.awake+raw.movement+raw.strain)) else 1 end k
  offset 0) soft
  cross join lateral (select raw.awake*soft.k awake,raw.movement*soft.k movement,raw.strain*soft.k strain offset 0) eff
  cross join lateral (
   select case when eff.awake+eff.movement+eff.strain>0
    then least(1,(r.value+raw.charge+raw.rest)/(eff.awake+eff.movement+eff.strain)) else 1 end k
  offset 0) scale
 )
 select r.t,trunc(r.value,24),r.in_sleep,trunc(r.d_charge,24),trunc(r.d_basal,24),trunc(r.d_active,24),trunc(r.d_stress,24)
 from replay r where r.n>0 and r.observed order by r.t;
end;
$$;

-- Keep yesterday's close only when it was published by this model.
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.reserve_anchor_info(uuid,date)'::regprocedure);
 patched:=replace(def,'%bb-3.0%','%readiness-1.0%');
 if patched=def then raise exception 'READINESS_ANCHOR_VERSION_MISSING'; end if;
 execute patched;
end $$;

do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.compute_reserve(uuid,date)'::regprocedure);
 patched:=replace(def,'''bb-3.0''','''readiness-1.0''');
 if patched=def then raise exception 'READINESS_ALGO_VERSION_MISSING'; end if;
 execute patched;
end $$;

-- target-1.2: ordinary days keep the morning training target.
-- A drop of more than 8 from morning readiness, or a current score under 60, applies the cap.
create or replace function nb.training_target(p_user uuid,p_user_day date,p_wake smallint)
returns jsonb language plpgsql stable set search_path='' as $$
declare base jsonb; reserve record; limit_info jsonb; proposed numeric; final_target numeric; load numeric;
 cap numeric; current_reserve smallint; morning smallint; keep_base boolean;
begin
 base:=nb.training_recovery_target(p_user,p_user_day,p_wake);
 select * into reserve from nb.training_reserve(p_user,p_user_day);
 limit_info:=reserve.drivers->'training_target';
 proposed:=(base->>'target')::numeric;
 cap:=(limit_info->>'value')::numeric;
 current_reserve:=reserve.current_value;
 morning:=reserve.wake_value;
 final_target:=proposed;
 keep_base:=current_reserve is not null and current_reserve>=60
  and (morning is null or morning-current_reserve<=8);
 if proposed is not null and cap is not null and not keep_base then
  final_target:=least(proposed,cap);
 end if;
 select t.training_load into load from nb.compute_training(p_user,p_user_day) t;
 return base||jsonb_build_object('version','target-1.2','base_target',proposed,
  'target',final_target,'lower',case when final_target is not null then greatest(0,final_target-2) end,
  'upper',case when final_target is not null then least(20,final_target+2) end,
  'current_reserve',reserve.current_value,'reserve_limit',limit_info->'value','reserve_fresh',coalesce((limit_info->>'fresh')::boolean,false),
  'remaining',case when final_target is not null and load is not null then greatest(0,final_target-load) end,
  'observed_at',limit_info->'observed_at','reserve_estimated',reserve.drivers->'assumed_anchor',
  'limited',coalesce((base->>'limited')::boolean,true) or coalesce((reserve.drivers->>'assumed_anchor')::boolean,true),
  'reserve_adjustment',case when final_target is not null then final_target-proposed end);
end;
$$;

do $$ declare definition text; patched text; begin
 definition:=pg_get_functiondef('nb.calculation_version()'::regprocedure);
 patched:=replace(replace(definition,'bb-3.0','readiness-1.0'),'target-1.1','target-1.2');
 if patched=definition or position('readiness-1.0' in patched)=0 or position('target-1.2' in patched)=0 then
  raise exception 'READINESS_CALCULATION_VERSION_MISSING';
 end if;
 execute patched;
end $$;

select nb.invalidate_calculation(user_id,min(user_day)) from public.daily_results group by user_id;

revoke all on function nb.reserve_replay_uncached(uuid,date),nb.training_target(uuid,date,smallint)
 from public,anon,authenticated;
