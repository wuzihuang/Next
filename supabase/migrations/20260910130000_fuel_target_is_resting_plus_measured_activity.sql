-- #29 · TARGET is the day's own resting figure plus the movement the band has measured
-- so far, and the resting figure is the one the body scan printed.
--
-- The 2705 on the fuel card was the median of six measured days from the previous
-- fortnight plus the BULK offset. It did not move when the wearer moved, and it was
-- built on a resting figure (Mifflin, 1965) that the body scan had contradicted on the
-- same screen an hour earlier (2229). What the product decided on this issue:
--
--   TARGET = resting for the whole day
--          + activity measured so far today
--          + the profile goal's offset (CUT −500 / RECOMP −380 / BULK +300)
--   never below 1500 kcal for a male profile, 1200 for a female one.
--
-- Resting is the most recent body-scan `bmr_kcal` at or before the day's calculation
-- instant, and Mifflin–St Jeor only for an account that has never scanned. It is one
-- figure for the whole ledger — fuel_components uses it for OUT, compute_fuel for
-- TARGET — because a target and a burn that disagree about resting are two ledgers.
--
-- ⚠️ The scan's figure is the device's own estimate (ADR 0004 still says so): five scans
-- of one body in six days ranged 2159–2240 with identical lean mass. The product chose
-- it because it is the number the wearer was shown; the latest scan wins, unsmoothed,
-- for the same reason. What can be improved is when to scan, not this formula.
-- ⚠️ Not wearing the band is not moving. No carry, no fortnight, no rhythm: a day the
-- band did not see contributes nothing, and the card says so with the coverage line.
-- ⚠️ A past day's instant is its own end, so a settled day is resting + the whole day's
-- activity + offset — which is the sentence #26 wrote and 20260906120500 replaced with a
-- median. burn_baseline and measured_burn stay defined (tests still read the fortnight)
-- but nothing on the fuel path calls them any more.
-- ⚠️ The BMR floor from 20260906120500 is gone. With resting as the starting point a CUT
-- would sit on it until 500 kcal of activity had been earned, which is the goal never
-- applying. The floor is now an absolute one, by profile sex.

-- ---------------------------------------------------------------- one offset, one floor

create or replace function nb.goal_offset(p_goal text) returns integer
language sql immutable set search_path='' as $$
  select case p_goal when 'CUT' then -500 when 'BULK' then 300 else -380 end;
$$;

create or replace function nb.intake_floor(p_sex text) returns integer
language sql immutable set search_path='' as $$
  select case when p_sex = 'male' then 1500 else 1200 end;
$$;

-- ---------------------------------------------------------------- the resting figure

-- Returns nothing (not a null row) when neither a scan nor a Mifflin body is known, so
-- callers read `select r.kcal into v` and get null the same way they always did.
create or replace function nb.resting_kcal(p_user uuid, p_user_day date)
returns table(kcal numeric, source text, measured_at timestamptz)
language plpgsql stable set search_path='' as $$
declare
  v_tz text; v_lo timestamptz; v_hi timestamptz; v_asof timestamptz;
  v_weight numeric; v_height numeric; v_age numeric; v_sex text;
  v_scan_kcal integer; v_scan_at timestamptz;
begin
  select p.timezone, p.height_cm, p.sex,
         extract(year from age(p_user_day::timestamp, p.birth_date::timestamp))
    into v_tz, v_height, v_sex, v_age
  from nb.calculation_profile(p_user, p_user_day) p;
  if v_tz is null then return; end if;
  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);
  v_asof := nb.calculation_instant(p_user, p_user_day);

  -- The latest scan the day could have seen. A scan taken this morning is this day's
  -- resting figure from midnight; a scan taken tomorrow never reaches back.
  select b.bmr_kcal, b.measured_at into v_scan_kcal, v_scan_at
  from public.body_composition b
  where b.user_id = p_user and b.measurement_source = 'device_bia'
    and b.bmr_kcal is not null and b.bmr_kcal > 0
    and b.measured_at <= v_asof
  order by b.measured_at desc limit 1;
  if v_scan_kcal is not null then
    return query select v_scan_kcal::numeric, 'BODY_SCAN'::text, v_scan_at;
    return;
  end if;

  -- Same weight the rest of the ledger uses: the latest before the day, else the first
  -- during it.
  select w.weight_kg into v_weight from public.weigh_ins w
  where w.user_id = p_user and w.measured_at <= v_asof and w.measured_at < v_hi
  order by (w.measured_at < v_lo) desc,
           case when w.measured_at < v_lo then w.measured_at end desc,
           w.measured_at asc
  limit 1;
  if v_weight is null or v_height is null or v_age is null or v_sex is null then return; end if;
  return query select
    (10 * v_weight + 6.25 * v_height - 5 * v_age
      + case when v_sex = 'male' then 5 else -161 end)::numeric,
    'MIFFLIN'::text, null::timestamptz;
end;
$$;

-- ---------------------------------------------------------------- OUT reads the same figure

do $do$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.fuel_components(uuid,date)'::regprocedure);
  if position('nb.resting_kcal' in definition) > 0 then return; end if;
  patched := replace(definition,
    ' if v_weight is not null and v_height is not null and v_age is not null and v_sex is not null then
  v_bmr:=10*v_weight+6.25*v_height-5*v_age+case when v_sex=''male'' then 5 else -161 end;
 end if;',
    ' select r.kcal into v_bmr from nb.resting_kcal(p_user,p_user_day) r;');
  if patched = definition then raise exception 'FUEL_COMPONENTS_RESTING_ANCHOR_MISSING'; end if;
  execute patched;
end $do$;

-- ---------------------------------------------------------------- TARGET

-- Rewritten whole from the live body (20260906115802 + the patches of 20260906120500,
-- 20260908160000 and 20260910100000): the basis and the floor are structural, not a
-- string. The signature is unchanged so settle_day, on_fuel_settled and every test keep
-- reading it as before.
create or replace function nb.compute_fuel(p_user uuid, p_user_day date)
 returns table(intake_state text, kcal_in integer, kcal_out integer, balance integer, target_in integer, protein_g integer, fat_g integer, carb_g integer, direction text, slot_states jsonb)
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  v_tz       text;
  v_lo       timestamptz;
  v_hi       timestamptz;
  v_weight   numeric;
  v_sex      text;
  v_goal     text;
  v_bmr      numeric;
  v_active   integer;
  v_in       integer;
  v_slots    integer;
  v_coverage numeric;
  v_state    text;
  v_p        integer;
  v_f        integer;
  v_c        integer;
  v_target   numeric;
  v_out      integer;
  v_balance  integer;
begin
  select p.timezone, p.sex, p.goal
    into v_tz, v_sex, v_goal
  from nb.calculation_profile(p_user, p_user_day) p where p.user_id = p_user;
  if v_tz is null then return; end if;

  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);

  select w.weight_kg into v_weight
  from public.weigh_ins w
  where w.user_id = p_user and w.measured_at <= nb.calculation_instant(p_user,p_user_day) and w.measured_at < v_hi
  order by (w.measured_at < v_lo) desc, case when w.measured_at < v_lo then w.measured_at end desc, w.measured_at asc limit 1;

  -- The whole day's resting figure: the body scan's, or Mifflin for a body never scanned.
  select r.kcal into v_bmr from nb.resting_kcal(p_user, p_user_day) r;

  -- Missing movement must not be published as a complete burn or a zero.
  -- Both consumers use the very same rounded components, including step fallback.
  select c.bmr_kcal + c.active_kcal, c.active_kcal into v_out, v_active
  from nb.fuel_components(p_user,p_user_day) c;

  select count(distinct date_bin(interval '5 minutes',s.ts,v_lo))::numeric
    / nullif(extract(epoch from(v_hi-v_lo))/300,0) into v_coverage
  from public.raw_samples s
  where s.user_id = p_user and s.ts >= v_lo and s.ts < v_hi
    and s.ts <= nb.calculation_instant(p_user,p_user_day)
    and nb.activity_met(s.met,s.step) is not null;

  select sum(m.kcal), count(distinct m.slot)
    into v_in, v_slots
  from public.meals m
  where m.user_id = p_user and m.user_day = p_user_day and m.deleted_at is null
    and m.model_version is distinct from 'seed';

  v_state := case when exists(select 1 from public.fasted_days f where f.user_id=p_user and f.user_day=p_user_day) then 'FASTED'
    when v_slots is null or v_slots = 0 then 'UNLOGGED'
    when v_slots >= 4 then 'CONFIRMED'
    else 'PARTIAL'
  end;

  -- Weight is still needed: the macro split is per kilo.
  if v_weight is not null and v_bmr is not null then
    -- Resting for the whole day, plus what the band has measured so far, plus the goal.
    -- Not wearing the band is not moving: an unobserved day adds nothing.
    v_target := v_bmr + coalesce(v_active, 0) + nb.goal_offset(v_goal);
    v_target := greatest(v_target, nb.intake_floor(v_sex));
    v_p := round((v_weight * case v_goal
             when 'CUT' then 2.0 when 'BULK' then 1.6 else 1.9 end) / 5) * 5;
    v_f := round((v_weight * case v_goal
             when 'BULK' then 0.9 else 0.8 end) / 5) * 5;
    v_c := round((v_target - 4 * v_p - 9 * v_f) / 4 / 5) * 5;
    -- The 100 g carbohydrate floor is real, but it is not extra calories. Fat gives
    -- way to it first, down to 0.5 g/kg and rounded down so it never overshoots, and
    -- carbohydrate then takes what is left: a budget pinned to the floor stays
    -- pinned to it instead of climbing to whatever the floored macros happened to add
    -- up to.
    if v_c < 100 then
      v_f := greatest(round((v_weight * 0.5) / 5) * 5,
                      floor((v_target - 4 * v_p - 400) / 9 / 5) * 5);
      v_c := greatest(100, round((v_target - 4 * v_p - 9 * v_f) / 4 / 5) * 5);
    end if;
    v_target := 4 * v_p + 9 * v_f + 4 * v_c;
  end if;

  if v_state <> 'UNLOGGED' and v_out is not null then
    v_balance := coalesce(v_in, 0) - v_out;
  end if;

  return query select
    v_state,
    case when v_state = 'UNLOGGED' then null else coalesce(v_in, 0) end,
    v_out,
    v_balance,
    round(v_target)::integer, v_p, v_f, v_c,
    case
      when v_state = 'UNLOGGED' then 'GREY_NOTHING'
      when v_state = 'PARTIAL' and v_slots < 2 then 'GREY_NOTHING'
      when coalesce(v_coverage, 0) < 0.5 then 'GREY_NO_BURN'
      when v_out is null then 'GREY_NO_BURN'
      when v_balance <= -150 then 'DEFICIT'
      when v_balance >= 150 then 'SURPLUS'
      else 'LEVEL'
    end,
    coalesce((
      select jsonb_object_agg(sl.name, coalesce(st.state, 'OPEN'))
      from unnest(array['BREAKFAST', 'LUNCH', 'DINNER', 'SNACK']) as sl(name)
      left join lateral (
        select 'CONFIRMED'::text as state
        from public.meals mm
        where mm.user_id = p_user and mm.user_day = p_user_day
          and mm.slot = sl.name and mm.deleted_at is null
          and mm.model_version is distinct from 'seed'
        limit 1
      ) st on true
    ), '{}'::jsonb);
end;
$function$;

revoke all on function nb.goal_offset(text), nb.intake_floor(text),
 nb.resting_kcal(uuid,date), nb.fuel_components(uuid,date), nb.compute_fuel(uuid,date)
from public, anon, authenticated;

-- ---------------------------------------------------------------- published beside the number

alter table public.day_fuel
  add column if not exists resting_source      text,
  add column if not exists resting_measured_at timestamptz,
  add column if not exists goal_offset_kcal    smallint;

comment on column public.day_fuel.bmr_full_kcal is
  'The whole day''s resting figure TARGET_IN and OUT were built on: the latest body scan''s
   bmr_kcal at or before the day''s instant, else Mifflin–St Jeor. See resting_source.';
comment on column public.day_fuel.resting_source is
  'BODY_SCAN when bmr_full_kcal is the band''s BIA estimate, MIFFLIN when it is the formula.';
comment on column public.day_fuel.resting_measured_at is
  'When that body scan was taken. Null for MIFFLIN.';
comment on column public.day_fuel.goal_offset_kcal is
  'The profile goal''s offset applied on top of resting + activity: CUT −500, RECOMP −380, BULK +300.';
comment on column public.day_fuel.target_basis_kcal is
  'resting + activity measured so far (bmr_full_kcal + active_kcal): TARGET_IN before the goal
   offset, the floor and the macro rounding.';
comment on column public.day_fuel.target_basis_days is
  'Retired with fuel-2.0. The basis is this day''s own, not a fortnight''s; always null now.';

do $do$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.on_fuel_settled()'::regprocedure);
  if position('resting_source' in definition) > 0 then return; end if;
  patched := replace(definition,
    '  select round(b.basis)::integer, b.measured_days
    into new.target_basis_kcal, new.target_basis_days
  from nb.burn_baseline(new.user_id, v_day, v_c.bmr_full) b;',
    '  new.target_basis_kcal := v_c.bmr_full + coalesce(v_c.active_kcal, 0);
  new.target_basis_days := null;
  select r.source, r.measured_at into new.resting_source, new.resting_measured_at
  from nb.resting_kcal(new.user_id, v_day) r;
  select nb.goal_offset(p.goal) into new.goal_offset_kcal
  from nb.calculation_profile(new.user_id, v_day) p;');
  if patched = definition then raise exception 'FUEL_SETTLED_BASIS_ANCHOR_MISSING'; end if;
  execute patched;
end $do$;

-- ---------------------------------------------------------------- every published day is stale

-- OUT changes for every account that has scanned (resting moved), TARGET for everyone.
do $do$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.calculation_version()'::regprocedure);
  patched := replace(replace(definition, 'fuel-1.2', 'fuel-2.0'), 'energy-1.1', 'energy-1.2');
  if patched = definition then raise exception 'FUEL_VERSION_PATCH_MISSING'; end if;
  execute patched;
end $do$;

select nb.invalidate_calculation(user_id, min(user_day))
from public.daily_results group by user_id;
