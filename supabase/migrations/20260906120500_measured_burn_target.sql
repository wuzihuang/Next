-- TARGET_IN from this person's measured burn, not from a textbook multiplier.
--
-- F2 §04 built the budget as BMR × 1.35 + goal offset. 1.35 is a table value for
-- "moderately active" and it is the one number on the fuel page the band never
-- touches: a 2,000-step day and a 20,000-step day printed the same 2,945. The page
-- already shows kcal_out = BMR + MET-integrated active every day, so the budget now
-- reads from the same components — the median of the last fourteen measured days —
-- and only falls back to 1.35 when there is not enough band coverage to know.
--
-- ⚠️ Median, not today's burn: a target that climbs while the user walks turns the
-- remaining-budget number into something nobody can plan a dinner against.
-- ⚠️ Derived from nb.fuel_components, never from stored day_fuel rows: recomputing an
-- old day must give the same answer as the first computation did.

create or replace function nb.measured_burn(p_user uuid, p_user_day date)
returns numeric
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz   text;
  v_burn numeric;
  v_days integer;
begin
  select p.timezone into v_tz from nb.calculation_profile(p_user, p_user_day) p;
  if v_tz is null then return null; end if;

  with days as (
    select (p_user_day - g)::date as d from generate_series(1, 14) g
  ),
  measured as (
    select
      (select c.bmr_full + c.active_kcal from nb.fuel_components(p_user, days.d) c) as total,
      -- 288 five-minute ticks is a full day; the GREY_NO_BURN rule's half-day is the floor.
      (select count(*) from public.raw_samples s, nb.user_day_bounds(days.d, v_tz) b
        where s.user_id = p_user and s.ts >= b.starts_at and s.ts < b.ends_at) as ticks
    from days
  )
  select percentile_cont(0.5) within group (order by total), count(*)
    into v_burn, v_days
  from measured
  where total is not null and ticks >= 144;

  -- Under three measured days the median is an accident, not a habit.
  if coalesce(v_days, 0) < 3 then return null; end if;
  return v_burn;
end;
$$;
revoke all on function nb.measured_burn(uuid, date) from public, anon, authenticated;

-- Preserve every fix already text-patched into compute_fuel (activity_met components,
-- calculation-revision weight lookup, the fasted day) and change only the budget line.
-- ⚠️ Re-runnable on purpose: a later migration that rewrites compute_fuel whole puts
-- 1.35 back, and this file has to be able to patch that body again.
do $$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.compute_fuel(uuid,date)'::regprocedure);
  if position('measured_burn' in definition) > 0 then return; end if;

  patched := replace(definition, 'v_bmr * 1.35',
    'coalesce(nb.measured_burn(p_user, p_user_day), v_bmr * 1.35)');
  if patched = definition then raise exception 'MEASURED_BURN_TARGET_PATCH_MISSING'; end if;
  definition := patched;

  -- A CUT day on a quiet week must still not budget below the basal figure.
  patched := replace(definition,
    'when ''CUT'' then -600 when ''BULK'' then 300 else -380 end;',
    'when ''CUT'' then -600 when ''BULK'' then 300 else -380 end;
    v_target := greatest(v_target, v_bmr);');
  if patched = definition then raise exception 'MEASURED_BURN_FLOOR_PATCH_MISSING'; end if;

  execute patched;
end $$;

-- The budget changes for every stored day, so every cached result is stale.
select nb.invalidate_calculation(user_id, min(user_day)) from public.daily_results group by user_id;
