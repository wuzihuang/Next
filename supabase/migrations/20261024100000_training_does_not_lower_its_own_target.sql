-- target-1.3: one continuous composition of the sleep-led base and current readiness.
--
-- target-1.2 had four defects (supabase/tests/training_target_composition.sql):
-- 1. Recorded movement was priced twice. It added to the day's load, and its readiness
--    cost lowered the same day's target. Following a 14.6 base with one zone-3 run cut
--    the target to 13.0 at load 13.3 and finished at load 14.7 against a 12.8 target.
-- 2. The limit switched on at one point: readiness 60 -> 59 moved a target 14.2 -> 11.4.
-- 3. That switch read the instantaneous reading, so a rebound skipped the 15-minute
--    average that limits every other rise.
-- 4. The base's short-night guard stopped at six hours: 5h59 capped at 11.0, 6h00 gave 13.2.
--
-- Fatigue is readiness with the movement cost recorded since the final wake added back.
-- Sleep, quiet rest, time awake and physiological strain still move it; today's recorded
-- activity does not, because the load ring already counts it. Falls follow the latest
-- reading, rises the 15-minute average. The target-1.2 thresholds stay: no cut while
-- fatigue is at least 60 and within 8 of the morning. Past either one the reserve limit
-- phases in over 5 readiness points; beyond that band the result equals target-1.2,
-- min(base, limit). Completed load is never rewritten. These are product parameters,
-- not a validated exercise prescription.
create function nb.compose_training_target(p_base numeric,p_morning numeric,p_fatigue numeric)
returns table(target numeric,reserve_limit numeric,limit_weight numeric)
language sql immutable set search_path='' as $$
 with cap as (select (nb.reserve_training_target(p_fatigue,p_fatigue,null)->>'value')::numeric value),
 weight as (select coalesce(greatest(least(1,greatest(0,(p_morning-p_fatigue-8)/5)),
   least(1,greatest(0,(60-p_fatigue)/5))),0) value)
 select round(p_base-w.value*greatest(0,p_base-coalesce(c.value,p_base)),1),c.value,w.value
 from cap c cross join weight w;
$$;

create or replace function nb.training_target(p_user uuid,p_user_day date,p_wake smallint)
returns jsonb language plpgsql stable set search_path='' as $$
declare base jsonb; reserve record; limit_info jsonb; proposed numeric; load numeric;
 lo timestamptz; wake_tick timestamptz; reading record; fatigue numeric; composed record;
begin
 base:=nb.training_recovery_target(p_user,p_user_day,p_wake);
 select * into reserve from nb.training_reserve(p_user,p_user_day);
 limit_info:=reserve.drivers->'training_target';
 proposed:=(base->>'target')::numeric;
 select b.starts_at into lo from nb.calculation_profile(p_user,p_user_day) p
  cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b;
 select date_bin(interval '5 minutes',s.wake_at-interval '1 microsecond',lo) into wake_tick
 from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) s
 where s.user_id=p_user and s.user_day=p_user_day and s.wake_at<=nb.calculation_instant(p_user,p_user_day);
 -- The replay is the settlement's memoized ledger; d_active is its movement term.
 with replay as materialized (select * from nb.reserve_replay(p_user,p_user_day)),
 at_wake as (select coalesce((select x.d_active from replay x where x.ts<=wake_tick order by x.ts desc limit 1),0) active),
 readings as (
  select x.ts,x.value,case when x.ts>wake_tick then greatest(0,w.active-x.d_active) else 0 end cost
  from replay x cross join at_wake w
 ), latest as (select * from readings order by ts desc limit 1)
 select l.value+l.cost fatigue,l.cost,
  (select avg(r.value+r.cost) from readings r where r.ts>l.ts-interval '15 minutes' and r.ts<=l.ts) smoothed
 into reading from latest l;
 fatigue:=coalesce(least(reading.fatigue,reading.smoothed),
  least((limit_info->>'reserve')::numeric,(limit_info->>'smoothed_reserve')::numeric));
 if fatigue is not null then fatigue:=least(100,greatest(0,fatigue)); end if;
 select * into composed from nb.compose_training_target(proposed,reserve.wake_value,fatigue);
 select t.training_load into load from nb.compute_training(p_user,p_user_day) t;
 return base||jsonb_build_object('version','target-1.3','base_target',proposed,
  'target',composed.target,'lower',case when composed.target is not null then greatest(0,composed.target-2) end,
  'upper',case when composed.target is not null then least(20,composed.target+2) end,
  'current_reserve',reserve.current_value,'reserve_limit',composed.reserve_limit,
  'reserve_fresh',coalesce((limit_info->>'fresh')::boolean,false),
  'fatigue_reserve',round(fatigue,1),'movement_cost',round(reading.cost,1),
  'limit_weight',round(composed.limit_weight,2),
  'remaining',case when composed.target is not null and load is not null then greatest(0,composed.target-load) end,
  'observed_at',limit_info->'observed_at','reserve_estimated',reserve.drivers->'assumed_anchor',
  'limited',coalesce((base->>'limited')::boolean,true) or coalesce((reserve.drivers->>'assumed_anchor')::boolean,true),
  'reserve_adjustment',case when composed.target is not null then composed.target-proposed end);
end;
$$;

-- Sleep restriction costs performance in a graded, near-linear way with no threshold at
-- six hours (Van Dongen 2003, doi:10.1093/sleep/26.2.117; Belenky 2003,
-- doi:10.1046/j.1365-2869.2003.00337.x). Six hours in the cited meta-analysis is its
-- inclusion criterion, not a physiological line. The guard keeps 8 at four hours or less
-- and rises linearly to the 16 maximum at 7.5 hours, where the duration score reaches 100.
do $$ declare definition text; patched text; begin
 definition:=pg_get_functiondef('nb.training_recovery_target(uuid,date,smallint)'::regprocedure);
 patched:=replace(definition,
  'if sleep_minutes<360 then target:=least(target,8+3*greatest(0,sleep_minutes-240)/120); end if;',
  'if sleep_minutes<450 then target:=least(target,8+8*greatest(0,sleep_minutes-240)/210); end if;');
 if patched=definition then raise exception 'TARGET_1_3_SHORT_NIGHT_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

do $$ declare definition text; patched text; begin
 definition:=pg_get_functiondef('nb.calculation_version()'::regprocedure);
 patched:=replace(definition,'target-1.2','target-1.3');
 if patched=definition then raise exception 'TARGET_1_3_VERSION_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

select nb.invalidate_calculation(user_id,min(user_day)) from public.daily_results group by user_id;

revoke all on function nb.compose_training_target(numeric,numeric,numeric),nb.training_target(uuid,date,smallint)
 from public,anon,authenticated;
