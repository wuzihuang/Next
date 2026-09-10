-- The budget promised a deficit it did not deliver, and the fortnight it reads from
-- counted half-worn days as if they were whole ones. Four changes, one migration,
-- because all four land on the same two numbers: TARGET_IN and the burn behind it.
--
-- #1 A CUT could not hold the budget it had just been pinned to. compute_fuel derived
-- carbohydrate from the budget, floored it at 100 g, and then rebuilt the budget out of
-- the floored macros — so the floor's shortfall came back as calories. It bites the
-- bodies whose basal figure is low against their own protein and fat allowance, which
-- is to say short, older or heavy ones, and it is silent. Simulated against the live
-- formula, budget pinned to basal in each case:
--   70 kg / 160 cm / 60 y / female  basal 1239, served 1455  (+216)
--  110 kg / 175 cm / 50 y / male    basal 1949, served 2090  (+141)
--   85 kg / 165 cm / 45 y / male    basal 1661, served 1710   (+49)
-- The 100 g floor stays — it is a real nutritional floor — but fat gives way to it
-- now, down to 0.5 g/kg, and carbohydrate takes the remainder, so what is left of the
-- gap is one 20 kcal rounding step instead of two hundred kilocalories.
-- ⚠️ A body whose allowance still cannot fit inside the budget lands above it: the
-- 70 kg case above ends at 1275, and the 36 kcal is the 0.5 g/kg fat floor, visible in
-- FAT_G rather than hidden in the calorie number.
-- ⚠️ RECOMP and BULK sit above the carbohydrate floor and do not move at all: the
-- 97 kg BULK budget is 2665 before and after.
--
-- #2 measured_burn counted a day as measured at 50% band coverage, then added a
-- WHOLE day of basal to the activity of half a day. Every partially worn day therefore
-- dragged the median down, and the budget with it. Coverage now has to reach 75%, and
-- the activity of a short day is carried to the full day before the median sees it.
-- ⚠️ Bounded on purpose: at the 75% gate the carry is at most 1.33x, and the median
-- of up to fourteen days absorbs a day whose missing quarter was unlike its observed
-- three quarters.
--
-- #3 The third measured day still replaces the estimate outright, and the step is
-- still visible — one account went 2945 -> 2685 overnight. A ramp between the two was
-- written and then thrown away: day-to-day burn on that account has an SD near 250, so
-- a four-day median carries a standard error near 156, while the 1.35 multiplier is
-- wrong by 285 on the same account and by far more across a population. Blending
-- towards the worse estimator to smooth a chart is not a calibration, and on that
-- account it would have pushed the budget back up to 2905 before letting it slide
-- down again. What the step actually lacked was an explanation, which is #4b below.
--
-- #4 measured_burn recomputed fourteen days of components out of raw_samples on every
-- call, and settle calls compute_fuel twice per day (once directly, once from
-- on_fuel_settled) — 28 replays of the same fortnight per settled day. Those
-- components are already published in day_fuel. Reading them gives the identical
-- median (verified on production: 2368.5 either way) at 24 ms instead of 186 ms.
-- ⚠️ The stored row is a cache, not the definition: a day with no settled row is
-- still computed, which is what keeps the pgTAP fixtures — which never settle — honest.
-- ⚠️ The old comment claimed reading day_fuel would break replay. It is the other way
-- round: fuel_components reads live raw_samples, so a late band upload silently
-- rewrites an old day's budget. recompute_range replays chronologically, so by the
-- time day D is settled its fortnight is already published.
--
-- #4b And since the fortnight now has one function that knows both the answer and the
-- evidence behind it, day_fuel publishes that basis and the number of measured days it
-- rests on. A budget can then be accounted for on the page that prints it, which is
-- the whole of what #3 was reaching for.

-- One definition of "this day carries an energy observation", used by the three
-- places that were each counting it their own way.
create or replace function nb.energy_slots(p_user uuid, p_day date)
returns integer language sql stable set search_path='' as $$
  select count(distinct date_bin(interval '5 minutes', s.ts, b.starts_at))::integer
  from nb.calculation_profile(p_user, p_day) p
  cross join lateral nb.user_day_bounds(p_day, p.timezone) b
  left join public.raw_samples s
    on s.user_id = p_user and s.ts >= b.starts_at and s.ts < b.ends_at
   and s.ts <= nb.calculation_instant(p_user, p_day)
   and nb.activity_met(s.met, s.step) is not null;
$$;

-- The budget's basis: the measured median where a fortnight is known, the textbook
-- multiplier where it is not. Returns the parts as well as the answer, so that a
-- budget can be accounted for on screen rather than only in this file.
create or replace function nb.burn_baseline(p_user uuid, p_user_day date, p_bmr numeric)
returns table(basis numeric, measured_kcal numeric, measured_days integer)
language plpgsql stable set search_path='' as $$
declare
  v_tz       text;
  v_burn     numeric;
  v_days     integer;
  v_estimate numeric := p_bmr * 1.35;
begin
  select p.timezone into v_tz from nb.calculation_profile(p_user, p_user_day) p;
  if v_tz is null then return; end if;

  with days as materialized (
    select (p_user_day-g)::date d,
      round(extract(epoch from(b.ends_at-b.starts_at))/300)::integer full_slots
    from generate_series(1,14) g
    cross join lateral nb.user_day_bounds((p_user_day-g)::date, v_tz) b
  ), published as (
    select r.user_day d, f.bmr_full_kcal, f.active_kcal, f.energy_slots
    from public.daily_results r
    join public.day_fuel f on f.result_id = r.id
    where r.user_id = p_user and r.user_day between p_user_day-14 and p_user_day-1
  ), measured as (
    select days.full_slots,
      coalesce(p.energy_slots, nb.energy_slots(p_user, days.d)) slots,
      coalesce(p.bmr_full_kcal,
        (select c.bmr_full from nb.fuel_components(p_user, days.d) c)) bmr_full,
      coalesce(p.active_kcal,
        (select c.active_kcal from nb.fuel_components(p_user, days.d) c)) active
    from days left join published p on p.d = days.d
  )
  select percentile_cont(0.5) within group (
           order by bmr_full + active * full_slots::numeric / nullif(slots,0)),
         count(*)
    into v_burn, v_days
  from measured
  where bmr_full is not null and active is not null
    and slots >= ceil(full_slots * 0.75);

  -- Under three measured days the median is an accident, not a habit.
  if coalesce(v_days,0) < 3 then
    return query select v_estimate, null::numeric, coalesce(v_days,0);
  else
    return query select v_burn, v_burn, v_days;
  end if;
end;
$$;

-- Kept as the fortnight's own answer, unblended, because that is what it has always
-- meant and what the fixtures assert about.
create or replace function nb.measured_burn(p_user uuid, p_user_day date)
returns numeric language sql stable set search_path='' as $$
  select b.measured_kcal from nb.burn_baseline(p_user, p_user_day, null) b;
$$;

revoke all on function nb.energy_slots(uuid,date),
 nb.burn_baseline(uuid,date,numeric), nb.measured_burn(uuid,date)
from public, anon, authenticated;

-- Two seams in compute_fuel, patched rather than rewritten so that whatever else has
-- been text-patched into this body survives.
do $do$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.compute_fuel(uuid,date)'::regprocedure);
  -- Re-runnable: a later migration that rewrites this body whole puts both seams back,
  -- and this file has to be able to patch that body again.
  if position('burn_baseline' in definition) > 0 then return; end if;

  patched := replace(definition,
    'coalesce(nb.measured_burn(p_user, p_user_day), v_bmr * 1.35)',
    '(select b.basis from nb.burn_baseline(p_user, p_user_day, v_bmr) b)');
  if patched = definition then raise exception 'FUEL_BASIS_ANCHOR_MISSING'; end if;
  definition := patched;

  patched := replace(definition,
    '    v_c := greatest(100, round((v_target - 4 * v_p - 9 * v_f) / 4 / 5) * 5);
    v_target := 4 * v_p + 9 * v_f + 4 * v_c;',
    '    v_c := round((v_target - 4 * v_p - 9 * v_f) / 4 / 5) * 5;
    -- The 100 g carbohydrate floor is real, but it is not extra calories. Fat gives
    -- way to it first, down to 0.5 g/kg and rounded down so it never overshoots, and
    -- carbohydrate then takes what is left: a budget pinned to the basal figure stays
    -- pinned to it instead of climbing to whatever the floored macros happened to add
    -- up to.
    if v_c < 100 then
      v_f := greatest(round((v_weight * 0.5) / 5) * 5,
                      floor((v_target - 4 * v_p - 400) / 9 / 5) * 5);
      v_c := greatest(100, round((v_target - 4 * v_p - 9 * v_f) / 4 / 5) * 5);
    end if;
    v_target := 4 * v_p + 9 * v_f + 4 * v_c;');
  if patched = definition then raise exception 'FUEL_CARB_FLOOR_ANCHOR_MISSING'; end if;

  execute patched;
end $do$;

-- Where the number came from, published beside the number itself. Without this the
-- only way to learn why TARGET_IN moved was to read the migration.
alter table public.day_fuel
  add column if not exists target_basis_kcal integer,
  add column if not exists target_basis_days smallint,
  add column if not exists energy_slots smallint;

comment on column public.day_fuel.target_basis_kcal is
  'The burn TARGET_IN was built on, before the goal offset and the macro split.';
comment on column public.day_fuel.target_basis_days is
  'Qualifying measured days in the fortnight behind that basis. Under three of them the
   basis is still the BMR multiplier estimate, which is nb.burn_baseline own gate.';
comment on column public.day_fuel.energy_slots is
  'Five-minute slots of this day that carry an energy observation.';

do $do$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.on_fuel_settled()'::regprocedure);
  if position('target_basis_kcal' in definition) > 0 then return; end if;
  patched := replace(definition,
    '  new.bmr_full_kcal := v_c.bmr_full;',
    '  new.bmr_full_kcal := v_c.bmr_full;
  new.energy_slots := nb.energy_slots(new.user_id, v_day);
  select round(b.basis)::integer, b.measured_days
    into new.target_basis_kcal, new.target_basis_days
  from nb.burn_baseline(new.user_id, v_day, v_c.bmr_full) b;');
  if patched = definition then raise exception 'FUEL_BASIS_PUBLICATION_ANCHOR_MISSING'; end if;
  execute patched;
end $do$;

-- The budget formula changed, so every published day is stale.
create or replace function nb.calculation_version() returns text
language sql stable set search_path='' as $$
 select 'tl-2.2/bb-2.2/fuel-1.1/call-1.2/energy-1.1/calc-1'::text;
$$;

select nb.invalidate_calculation(user_id, min(user_day))
from public.daily_results group by user_id;
