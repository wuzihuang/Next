-- F3 §04 · what runs where.
-- Anything replayable lives in Postgres: the same inputs must always give the same answer.
-- Anything uncertain, unrepayable or billable lives in an Edge Function.
--
-- F2 rule 02 · every derived number is computed here and written to daily_results.
-- The client never holds a second implementation.

create schema if not exists nb;

-- ---------------------------------------------------------------- the calendar

-- F2 rule 03 · one calendar. The user day runs local 04:00 → 04:00.
-- dayOffset is a paging parameter for the SDK and appears nowhere else.
create or replace function nb.user_day_bounds(p_user_day date, p_tz text)
returns table (starts_at timestamptz, ends_at timestamptz)
language sql
immutable
set search_path = ''
as $$
  select ((p_user_day + time '04:00') at time zone p_tz),
         ((p_user_day + 1 + time '04:00') at time zone p_tz);
$$;

create or replace function nb.user_day_of(p_ts timestamptz, p_tz text)
returns date
language sql
immutable
set search_path = ''
as $$
  select (((p_ts at time zone p_tz) - interval '4 hours')::date);
$$;

-- ---------------------------------------------------------------- zones and load

-- F2 §03 · one set of boundaries used twice: the zone the screen shows and the weight
-- the load is integrated with are the same five numbers.
create or replace function nb.zone_of(p_hrr numeric)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select case
    when p_hrr >= 0.85 then 5
    when p_hrr >= 0.70 then 4
    when p_hrr >= 0.55 then 3
    when p_hrr >= 0.40 then 2
    when p_hrr >= 0.30 then 1
    else 0
  end::smallint;
$$;

create or replace function nb.zone_weight(p_zone smallint)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select (array[0.00, 0.15, 0.50, 1.20, 3.00, 6.00])[p_zone + 1];
$$;

-- Tanaka. ⚠️ It underestimates HR_MAX for well-trained people, so zones run high and load
-- runs large. V1 accepts that error, but no copy is allowed to call this "your max heart rate".
create or replace function nb.hr_max(p_birth_date date)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select round(208 - 0.7 * extract(year from age(p_birth_date))::numeric);
$$;

-- HR_REST · the median of the lowest decile inside the sleep window over the last seven
-- user days. ⚠️ Frozen for the week and recomputed at Monday 04:00: if it moved daily,
-- the floor of Z2 would move daily and no two weeks could ever be compared.
create or replace function nb.hr_rest(p_user uuid, p_user_day date, p_tz text)
returns numeric
language sql
stable
set search_path = ''
as $$
  with week_start as (
    select (p_user_day - ((extract(isodow from p_user_day)::int) - 1))::date as d
  ),
  window_bounds as (
    select (select starts_at from nb.user_day_bounds((select d from week_start) - 7, p_tz)) as lo,
           (select ends_at   from nb.user_day_bounds((select d from week_start) - 1, p_tz)) as hi
  ),
  nightly as (
    select heart
    from public.raw_samples, window_bounds
    where user_id = p_user
      and ts >= window_bounds.lo and ts < window_bounds.hi
      and heart is not null
      and extract(hour from ts at time zone p_tz) between 0 and 6
  ),
  lowest as (
    select heart from nightly
    order by heart
    limit greatest(1, (select count(*) / 10 from nightly))
  )
  select percentile_cont(0.5) within group (order by heart) from lowest;
$$;

-- ---------------------------------------------------------------- compute_training

-- TRAINING_LOAD = 21 × (1 − e^(−RAW/60)); monotonic within the day, and the asymptote
-- means the ring can never actually reach 21 — 20.9 is the largest number it can show.
create or replace function nb.compute_training(p_user uuid, p_user_day date)
returns table (
  training_load numeric,
  zone_minutes  smallint[],
  peak_hr       smallint,
  coverage      numeric,
  curve         jsonb
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz    text;
  v_birth date;
  v_max   numeric;
  v_rest  numeric;
  v_lo    timestamptz;
  v_hi    timestamptz;
begin
  select timezone, birth_date into v_tz, v_birth
  from public.profiles where user_id = p_user;
  if v_tz is null then return; end if;

  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);
  v_max := nb.hr_max(v_birth);
  v_rest := nb.hr_rest(p_user, p_user_day, v_tz);

  -- No birth date → no zones and no load. The block is not rendered, not zeroed.
  if v_max is null or v_rest is null or v_max <= v_rest then return; end if;

  return query
  with pts as (
    select ts, heart,
           least(1, greatest(0, (heart - v_rest) / (v_max - v_rest))) as hrr
    from public.raw_samples
    where user_id = p_user and ts >= v_lo and ts < v_hi and heart is not null
  ),
  zoned as (
    select ts, heart, nb.zone_of(hrr) as z, nb.zone_weight(nb.zone_of(hrr)) as w from pts
  ),
  raw_load as (
    select coalesce(sum(w * 5), 0) as raw from zoned
  ),
  mins as (
    -- ⚠️ Any zone duration can only be a multiple of five; the points are five minutes apart.
    select array[
      (select count(*) * 5 from zoned where z = 1),
      (select count(*) * 5 from zoned where z = 2),
      (select count(*) * 5 from zoned where z = 3),
      (select count(*) * 5 from zoned where z = 4),
      (select count(*) * 5 from zoned where z = 5)
    ]::smallint[] as m
  ),
  cumulative as (
    select ts, sum(w * 5) over (order by ts) as running_raw from zoned
  ),
  running as (
    select jsonb_agg(jsonb_build_array(
             extract(epoch from ts)::bigint,
             least(20.9, round(21 * (1 - exp(-running_raw / 60.0)), 1))
           ) order by ts) as c
    from cumulative
  )
  select least(20.9, round(21 * (1 - exp(-(select raw from raw_load) / 60.0)), 1)),
         (select m from mins),
         (select max(heart)::smallint from zoned),
         -- 288 five-minute points make a full day
         round((select count(*) from zoned)::numeric / 288, 2),
         coalesce((select c from running), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------- compute_reserve

-- 13 · discharge is three independent terms added together, never a product: the detail
-- page has to list those three lines, and a multiplicative model cannot be taken apart.
create or replace function nb.compute_reserve(p_user uuid, p_user_day date)
returns table (
  wake_value    smallint,
  current_value smallint,
  min_value     smallint,
  drivers       jsonb
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz     text;
  v_lo     timestamptz;
  v_hi     timestamptz;
  v_sleep  record;
  v_wake   numeric;
  v_awake  numeric := 0;
  v_move   numeric := 0;
  v_stress numeric := 0;
  v_prev   numeric;
  v_q      numeric;
  v_m      numeric;
  v_ticks  numeric;
  v_rest   numeric := 0;
begin
  select timezone into v_tz from public.profiles where user_id = p_user;
  if v_tz is null then return; end if;
  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);

  select * into v_sleep from public.sleep_nights
  where user_id = p_user and user_day = p_user_day;

  select rd.current_value into v_prev from public.reserve_daily rd
  join public.daily_results dr on dr.id = rd.result_id
  where dr.user_id = p_user and dr.user_day = p_user_day - 1;

  -- No night on record → no number at all. The page stays blank rather than
  -- inventing a starting point. ⚠️ A cold start's first night begins at 20.
  if v_sleep is null or coalesce(v_sleep.total_minutes, 0) = 0 then return; end if;

  -- charge · 0.75 per tick × quality × multiplier. Quality rides on the deep share;
  -- the multiplier is clamped to 0.65–1.30 so one strange night cannot double the day.
  v_ticks := v_sleep.total_minutes / 5.0;
  v_q := 0.80 + 0.45 * least(1, coalesce(v_sleep.deep_minutes, 0)::numeric
                                / greatest(1, v_sleep.total_minutes));
  v_m := least(1.30, greatest(0.65, 1.00 - 0.06 * coalesce(v_sleep.wake_count, 0)));

  -- The top-up shrinks as the battery approaches the 95 ceiling, which is what gives the
  -- curve a fixed point instead of a one-way ramp. ⚠️ The factor is 1.0 at the cold-start
  -- value of 20, so both anchors in 13's table (+61 and +36) are reproduced exactly.
  v_wake := least(95, coalesce(v_prev, 20)
                      + 0.75 * v_ticks * v_q * v_m
                        * greatest(0.25, (95 - coalesce(v_prev, 20)) / 75.0));

  -- discharge · three independent terms added together, never a product.
  -- Sleeping ticks do not spend the battery; only the waking day does.
  select coalesce(sum(case when coalesce(rs.sleep_states, 0) = 0 then 0.30 else 0 end), 0),
         coalesce(sum(case when coalesce(rs.sleep_states, 0) = 0
                           then 0.22 * greatest(0, rs.met - 1) else 0 end), 0),
         -- 0.25 per tick above the stress floor of 40, capped at 24 a day
         least(24, coalesce(sum(case when rs.stress > 40 and coalesce(rs.sleep_states, 0) = 0
                                     then 0.25 else 0 end), 0)),
         -- the daily resting-recharge budget of 25: quiet waking time puts a little back,
         -- which is what stops the curve from running monotonically into the floor
         least(25, coalesce(sum(case when coalesce(rs.sleep_states, 0) = 0
                                       and rs.met < 1.15 and coalesce(rs.stress, 0) <= 40
                                     then 0.30 else 0 end), 0))
    into v_awake, v_move, v_stress, v_rest
  from public.raw_samples rs
  where rs.user_id = p_user and rs.ts >= v_lo and rs.ts < v_hi
    -- only the part of the day that has actually happened
    and rs.ts <= now();

  return query select
    round(v_wake)::smallint,
    least(100, greatest(0, round(v_wake - v_awake - v_move - v_stress + v_rest)))::smallint,
    least(100, greatest(0, round(v_wake - v_awake - v_move - v_stress + v_rest)))::smallint,
    -- 13 · the four rows the detail page lists, and they must add up to the number on top
    jsonb_build_object(
      'last_night', round(v_wake - coalesce(v_prev, 20)),
      'awake',      -round(v_awake - v_rest),
      'movement',   -round(v_move),
      'stress',     -round(v_stress));
end;
$$;

-- 13 · Sec 04 — nine bands, no interpolation inside a band.
create or replace function nb.target_load(p_wake smallint)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case
    when p_wake is null then null
    when p_wake < 20  then 4.0
    when p_wake < 30  then 6.0
    when p_wake < 40  then 8.0
    when p_wake < 50  then 10.0
    when p_wake < 60  then 11.5
    when p_wake < 70  then 13.0
    when p_wake < 80  then 14.5
    when p_wake < 90  then 16.0
    else 18.0
  end;
$$;

-- ---------------------------------------------------------------- compute_fuel

-- F2 §04 · P → F → C, in that order. P and F round to 5, C eats the remainder, and the
-- displayed TARGET_IN is then rewritten as 4P + 9F + 4C.
-- ⚠️ Rounding TARGET_IN to 50 first and computing macros after leaves the add-back short
-- by a dozen kcal every single day.
create or replace function nb.compute_fuel(p_user uuid, p_user_day date)
returns table (
  intake_state text,
  kcal_in      integer,
  kcal_out     integer,
  balance      integer,
  target_in    integer,
  protein_g    integer,
  fat_g        integer,
  carb_g       integer,
  direction    text,
  slot_states  jsonb
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz       text;
  v_lo       timestamptz;
  v_hi       timestamptz;
  v_weight   numeric;
  v_height   numeric;
  v_age      numeric;
  v_sex      text;
  v_goal     text;
  v_bmr      numeric;
  v_active   numeric;
  v_elapsed  numeric;
  v_in       integer;
  v_slots    integer;
  v_coverage numeric;
  v_state    text;
  v_p        integer;
  v_f        integer;
  v_c        integer;
  v_target   numeric;
begin
  select p.timezone, p.height_cm, p.sex, p.goal,
         extract(year from age(p.birth_date))
    into v_tz, v_height, v_sex, v_goal, v_age
  from public.profiles p where p.user_id = p_user;
  if v_tz is null then return; end if;

  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);

  -- WEIGHT_KG · the most recent entry strictly before this day's 04:00, never one after it.
  select w.weight_kg into v_weight
  from public.weigh_ins w
  where w.user_id = p_user and w.measured_at < v_lo
  order by w.measured_at desc limit 1;

  -- Mifflin-St Jeor. ⚠️ Never the BIA's own basalMetabolicRate: electrode contact can move
  -- it by tens of kcal, and a budget that changes with grip is a bug nobody can find.
  if v_weight is null or v_height is null or v_age is null then
    v_bmr := null;
  else
    v_bmr := 10 * v_weight + 6.25 * v_height - 5 * v_age
             + case when v_sex = 'male' then 5 else -161 end;
  end if;

  -- E_ACTIVE · MET integration. ⚠️ Never OriginData.calValue: it already contains the
  -- vendor's own basal figure, and adding it to our BMR double-counts.
  select coalesce(sum(greatest(0, met - 1) * 1.05 * coalesce(v_weight, 0) * (5.0 / 60)), 0)
    into v_active
  from public.raw_samples
  where user_id = p_user and ts >= v_lo and ts < v_hi;

  select count(*)::numeric / 288 into v_coverage
  from public.raw_samples
  where user_id = p_user and ts >= v_lo and ts < v_hi;

  v_elapsed := least(1440, greatest(0,
                 extract(epoch from (least(now(), v_hi) - v_lo)) / 60));

  select sum(m.kcal), count(distinct m.slot)
    into v_in, v_slots
  from public.meals m
  where m.user_id = p_user and m.user_day = p_user_day and m.deleted_at is null;

  v_state := case
    when v_slots is null or v_slots = 0 then 'UNLOGGED'
    when v_slots >= 4 then 'CONFIRMED'
    else 'PARTIAL'
  end;

  -- F2 §04 · macros from weight and goal
  if v_weight is not null and v_bmr is not null then
    v_target := v_bmr * 1.35 + case v_goal
                  when 'CUT' then -600 when 'BULK' then 300 else -380 end;
    v_p := round((v_weight * case v_goal
             when 'CUT' then 2.0 when 'BULK' then 1.6 else 1.9 end) / 5) * 5;
    v_f := round((v_weight * case v_goal
             when 'BULK' then 0.9 else 0.8 end) / 5) * 5;
    -- carb floor 100 g; take it out of fat first, never produce a negative carb figure
    v_c := greatest(100, round((v_target - 4 * v_p - 9 * v_f) / 4 / 5) * 5);
    v_target := 4 * v_p + 9 * v_f + 4 * v_c;
  end if;

  return query select
    v_state,
    case when v_state = 'UNLOGGED' then null else coalesce(v_in, 0) end,
    case when v_bmr is null then null
         else round(v_bmr * v_elapsed / 1440 + v_active)::integer end,
    case when v_state = 'UNLOGGED' or v_bmr is null then null
         else (coalesce(v_in, 0) - round(v_bmr * v_elapsed / 1440 + v_active))::integer end,
    round(v_target)::integer, v_p, v_f, v_c,
    -- F2 §06 · three tiers plus two greys, and never the quadrant palette.
    case
      when now() < v_hi then null                              -- the day has not closed
      when v_state = 'UNLOGGED' then 'GREY_NOTHING'
      when v_state = 'PARTIAL' and v_slots < 2 then 'GREY_NOTHING'
      when coalesce(v_coverage, 0) < 0.5 then 'GREY_NO_BURN'
      when v_bmr is null then 'GREY_NO_BURN'
      when (coalesce(v_in, 0) - round(v_bmr + v_active)) <= -150 then 'DEFICIT'
      when (coalesce(v_in, 0) - round(v_bmr + v_active)) >= 150 then 'SURPLUS'
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
        limit 1
      ) st on true
    ), '{}'::jsonb);
end;
$$;

-- ---------------------------------------------------------------- compute_the_call

-- F2 §05 · nine combinations, complete. Both inside the bands is MEASURED, NO CHANGE —
-- not DRIFT, and not a failure.
create or replace function nb.compute_the_call(p_user uuid, p_user_day date)
returns table (
  out_call       text,
  out_confidence text,
  fat_delta      numeric,
  lean_delta     numeric,
  n_scans        integer
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_fat_now  numeric; v_fat_then numeric;
  v_lean_now numeric; v_lean_then numeric;
  v_n int; v_sigma numeric;
  v_fd numeric; v_ld numeric;
begin
  -- EMA α = 0.25 (N = 7); the first sample seeds directly, and changing measurement
  -- source must re-seed.
  with ordered as (
    select measured_at, fat_mass_kg, lean_body_mass_kg
    from public.body_composition
    where user_id = p_user and user_day <= p_user_day
    order by measured_at
  ),
  ema as (
    select measured_at, fat_mass_kg, lean_body_mass_kg,
           avg(fat_mass_kg) over (order by measured_at rows between 6 preceding and current row) as fe,
           avg(lean_body_mass_kg) over (order by measured_at rows between 6 preceding and current row) as le
    from ordered
  )
  select (select fe from ema order by measured_at desc limit 1),
         (select fe from ema where measured_at <= (now() - interval '7 days')
           order by measured_at desc limit 1),
         (select le from ema order by measured_at desc limit 1),
         (select le from ema where measured_at <= (now() - interval '7 days')
           order by measured_at desc limit 1),
         (select count(*) from ordered where measured_at >= now() - interval '7 days'),
         (select stddev_pop(fat_mass_kg - fe) from ema where measured_at >= now() - interval '7 days')
    into v_fat_now, v_fat_then, v_lean_now, v_lean_then, v_n, v_sigma;

  if v_fat_now is null or v_fat_then is null then return; end if;

  v_fd := v_fat_now - v_fat_then;
  v_ld := v_lean_now - v_lean_then;

  return query select
    case
      when v_ld >  0.10 and v_fd >  0.15 then 'BULK'
      when v_ld >  0.10                  then 'RECOMP'
      when v_ld < -0.10 and v_fd >  0.15 then 'DRIFT'
      when v_ld < -0.10                  then 'CUT'
      when v_fd < -0.15                  then 'CUT'
      when v_fd >  0.15                  then 'BULK'
      else 'NO_CHANGE'
    end,
    -- σ is a demotion condition, not a fourth tier. A large σ means the weigh-ins disagree
    -- with each other: having enough days is not the same as having enough evidence.
    case
      when v_n >= 7 and coalesce(v_sigma, 9) <= 0.35 then 'HIGH'
      when v_n >= 5 and coalesce(v_sigma, 9) <= 0.70 then 'MEDIUM'
      else 'PENDING'
    end,
    round(v_fd, 2), round(v_ld, 2), v_n;
end;
$$;

-- ---------------------------------------------------------------- settle_day

-- F3 §05 · "one source, one instant". One transaction: compute the four numbers, write
-- daily_results and take the result_id, overwrite the three detail tables with that same
-- result_id, commit. All four change together or none of them do.
-- Only daily_results carries computed_at.
create or replace function nb.settle_day(p_user uuid, p_user_day date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_train   record;
  v_reserve record;
  v_fuel    record;
  v_call    record;
  v_id      uuid;
  v_prev    text;
  v_algo    text := 'tl-2.1/bb-1.4/fuel-1.0/call-1.2';
  v_hash    text;
begin
  select * into v_train   from nb.compute_training(p_user, p_user_day);
  select * into v_reserve from nb.compute_reserve(p_user, p_user_day);
  select * into v_fuel    from nb.compute_fuel(p_user, p_user_day);
  select * into v_call    from nb.compute_the_call(p_user, p_user_day);

  v_hash := md5(coalesce(v_train.training_load::text, '') ||
                coalesce(v_reserve.wake_value::text, '') ||
                coalesce(v_fuel.kcal_in::text, '') ||
                coalesce(v_fuel.kcal_out::text, '') ||
                coalesce(v_call.fat_delta::text, ''));

  select dr.the_call into v_prev
  from public.daily_results dr
  where dr.user_id = p_user and dr.user_day = p_user_day;

  insert into public.daily_results as d
    (user_id, user_day, training_load, reserve_score, fuel_balance_kcal,
     daily_direction, the_call, the_call_confidence, algo_version, inputs_hash, computed_at)
  values
    (p_user, p_user_day, v_train.training_load, v_reserve.current_value, v_fuel.balance,
     v_fuel.direction, v_call.out_call, coalesce(v_call.out_confidence, 'PENDING'),
     v_algo, v_hash, now())
  on conflict (user_id, user_day) do update set
    training_load = excluded.training_load,
    reserve_score = excluded.reserve_score,
    fuel_balance_kcal = excluded.fuel_balance_kcal,
    daily_direction = excluded.daily_direction,
    the_call = excluded.the_call,
    the_call_confidence = excluded.the_call_confidence,
    algo_version = excluded.algo_version,
    inputs_hash = excluded.inputs_hash,
    computed_at = now()
  returning d.id into v_id;

  insert into public.daily_training (result_id, user_id, zone_minutes, peak_hr, session_count, curve)
  values (v_id, p_user, coalesce(v_train.zone_minutes, '{0,0,0,0,0}'), v_train.peak_hr, 0,
          coalesce(v_train.curve, '[]'::jsonb))
  on conflict (result_id) do update set
    zone_minutes = excluded.zone_minutes,
    peak_hr = excluded.peak_hr,
    curve = excluded.curve;

  if v_reserve.wake_value is not null then
    insert into public.reserve_daily (result_id, user_id, wake_value, min_value, current_value, drain_drivers)
    values (v_id, p_user, v_reserve.wake_value, v_reserve.min_value,
            v_reserve.current_value, v_reserve.drivers)
    on conflict (result_id) do update set
      wake_value = excluded.wake_value,
      min_value = excluded.min_value,
      current_value = excluded.current_value,
      drain_drivers = excluded.drain_drivers;
  end if;

  if v_fuel.intake_state is not null then
    insert into public.day_fuel (result_id, user_id, intake_state, kcal_in, kcal_out, slot_states)
    values (v_id, p_user, v_fuel.intake_state, v_fuel.kcal_in, v_fuel.kcal_out, v_fuel.slot_states)
    on conflict (result_id) do update set
      intake_state = excluded.intake_state,
      kcal_in = excluded.kcal_in,
      kcal_out = excluded.kcal_out,
      slot_states = excluded.slot_states;
  end if;

  -- 10 · the call is never allowed to change silently.
  if v_call.out_call is not null and v_call.out_call is distinct from v_prev then
    insert into public.call_changes (user_id, user_day, call, prev_call, reason, changed_by, algo_version)
    values (p_user, p_user_day, v_call.out_call, v_prev,
            format('fat %s kg / lean %s kg over 7d', v_call.fat_delta, v_call.lean_delta),
            'settle', v_algo);
  end if;

  return v_id;
end;
$$;

revoke execute on function nb.settle_day(uuid, date) from public, anon, authenticated;

-- F2 §08 · one call recomputes a range. Changing the algorithm does not back-fill history;
-- only a changed inputs_hash justifies a recompute.
create or replace function nb.recompute_range(p_user uuid, p_from date, p_to date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare d date; n int := 0;
begin
  for d in select generate_series(p_from, p_to, interval '1 day')::date loop
    perform nb.settle_day(p_user, d);
    n := n + 1;
  end loop;
  return n;
end;
$$;

revoke execute on function nb.recompute_range(uuid, date, date) from public, anon, authenticated;
