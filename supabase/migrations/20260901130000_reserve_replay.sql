-- 13 · BODY BATTERY, replayed.
--
-- The first cut of nb.compute_reserve invented its own coefficients. Board 13 prints them,
-- and F2 §02 defers to it ("系数与式子在 13 板首发，本表不重写"), so this replaces the
-- formula wholesale with the board's:
--
--   drain(t) = k_b + k_a · max(0, met − 1.0) + k_s · max(0, stress − 40) / 60
--     k_b = 0.30   waking basal, per tick
--     k_a = 0.22   per MET over 1, per tick
--     k_s = 0.25   the ceiling of the stress term, reached at stress = 100
--   sleep ticks do not drain, they charge
--   a resting waking tick (HR ≤ RHR+5 and met < 1.2 and steps = 0) drains half the basal
--     and is allowed to take charge_rest
--
--   charge(t)      = k_c · q(t) · M      sleep ticks
--   charge_rest(t) = k_r                 waking resting ticks
--     k_c = 0.75, q = deep 1.25 / light 0.85 / awake-in-bed 0.15
--     k_r = 0.25, capped by a 25-points-a-day budget
--     M = clamp(m_HRV · m_RHR, 0.65, 1.30), computed once a night
--
-- ⚠️ 1CO9 · BB(t) is a pure function of the tick stream, replayed from the last anchor —
-- never a scalar mutated in place. The band is an offline device and data arrives days
-- late; an incremental model can never catch up, and the app and the server would then
-- hold two different numbers for the same person. The price is 288 points every time.

-- ---------------------------------------------------------------- nb.night_rhr

-- Resting heart rate for a night: the 5th percentile of heartValue over that night's
-- sleep ticks. Not a mean — one restless hour would drag a mean up by several bpm.
create or replace function nb.night_rhr(p_user uuid, p_user_day date, p_tz text)
returns numeric
language sql
stable
set search_path = ''
as $$
  select percentile_cont(0.05) within group (order by rs.heart)
  from public.raw_samples rs, nb.user_day_bounds(p_user_day, p_tz) b
  where rs.user_id = p_user
    and rs.ts >= b.starts_at and rs.ts < b.ends_at
    and coalesce(rs.sleep_states, 0) <> 0
    and rs.heart is not null;
$$;

-- ---------------------------------------------------------------- nb.charge_multiplier

-- M = clamp(m_HRV · m_RHR, 0.65, 1.30), one value for the whole night.
--
-- ⚠️ 1CT0 · on iOS the HRV array is routinely empty — the library only fills it after
-- startReadOriginData has finished, and retrying a hundred times returns the same empty
-- array while flattening the battery. So m_HRV degrades to 1.00, which means "neither add
-- nor subtract", not "use the average". A night with sleep ticks and a heart rate always
-- produces a score.
--
-- m_RHR mirrors m_HRV's shape against the same 14-night window. A resting heart rate
-- below your own baseline is the good direction, so z carries the opposite sign.
create or replace function nb.charge_multiplier(p_user uuid, p_user_day date, p_tz text)
returns numeric
language plpgsql
stable
set search_path = ''
as $$
declare
  v_rhr  numeric;
  v_mean numeric;
  v_sd   numeric;
  v_n    integer;
  v_z    numeric;
begin
  v_rhr := nb.night_rhr(p_user, p_user_day, p_tz);
  if v_rhr is null then return 1.00; end if;

  select count(*), avg(r), stddev_samp(r) into v_n, v_mean, v_sd
  from (
    select nb.night_rhr(p_user, d::date, p_tz) as r
    from generate_series(p_user_day - 14, p_user_day - 1, interval '1 day') d
  ) s where r is not null;

  -- Fewer than five nights is not a baseline. 1.00 until it is one.
  if coalesce(v_n, 0) < 5 or coalesce(v_sd, 0) < 0.5 then return 1.00; end if;

  v_z := (v_mean - v_rhr) / v_sd;
  return least(1.30, greatest(0.65,
    1.00 * least(1.25, greatest(0.75, 1.00 + 0.25 * v_z))));
end;
$$;

-- ---------------------------------------------------------------- nb.reserve_replay

-- The 288 points themselves, plus the four attribution terms carried alongside so the
-- detail page's rows and the curve can never disagree — they are the same sum.
--
-- ⚠️ 1CTK · the curve stops at the last real tick. Nothing is extrapolated forward.
create or replace function nb.reserve_replay(p_user uuid, p_user_day date)
returns table (
  ts        timestamptz,
  value     numeric,
  asleep    boolean,
  d_charge  numeric,   -- last night
  d_basal   numeric,   -- just being awake, net of the resting top-up
  d_active  numeric,   -- moving around
  d_stress  numeric    -- stress
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz     text;
  v_lo     timestamptz;
  v_hi     timestamptz;
  v_anchor numeric;
  v_m      numeric;
  v_rhr    numeric;
begin
  select timezone into v_tz from public.profiles where user_id = p_user;
  if v_tz is null then return; end if;
  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);

  -- The anchor is where the day opened at 04:00: yesterday's closing value.
  -- ⚠️ 1CK4 · a cold start assumes the jar held 20, and the detail page must say so in
  -- words rather than present it as a measurement.
  select rd.current_value into v_anchor
  from public.reserve_daily rd
  join public.daily_results dr on dr.id = rd.result_id
  where dr.user_id = p_user and dr.user_day = p_user_day - 1;
  v_anchor := coalesce(v_anchor, 20);

  v_m   := nb.charge_multiplier(p_user, p_user_day, v_tz);
  v_rhr := coalesce(nb.night_rhr(p_user, p_user_day, v_tz),
                    nb.night_rhr(p_user, p_user_day - 1, v_tz),
                    55);

  return query
  with tick as (
    select rs.ts as t,
           coalesce(rs.sleep_states, 0) as stage,
           coalesce(rs.met, 1.0) as met,
           coalesce(rs.stress, 0)::numeric as stress,
           coalesce(rs.step, 0) as step,
           rs.heart
    from public.raw_samples rs
    where rs.user_id = p_user and rs.ts >= v_lo and rs.ts < v_hi and rs.ts <= now()
  ),
  marked as (
    select t.*,
           t.stage <> 0 as asleep,
           (t.stage = 0 and t.heart is not null and t.heart <= v_rhr + 5
            and t.met < 1.2 and t.step = 0) as resting
    from tick t
  ),
  term as (
    select m.t,
           m.asleep,
           -- sleep-stage quality: 1 deep · 2 light · 3 awake in bed
           case when m.asleep
                then 0.75 * (case m.stage when 1 then 1.25 when 2 then 0.85 else 0.15 end) * v_m
                else 0 end as charge,
           case when not m.asleep and m.resting then 0.25 else 0 end as rest_raw,
           case when m.asleep then 0 when m.resting then 0.5 * 0.30 else 0.30 end as basal,
           case when m.asleep then 0 else 0.22 * greatest(0, m.met - 1.0) end as active,
           case when m.asleep then 0 else 0.25 * greatest(0, m.stress - 40) / 60.0 end as strain
    from marked m
  ),
  budget as (
    -- k_r is capped by a 25-points-a-day budget: charge the difference between the
    -- running total before and after this tick, so the cap bites mid-tick if it must.
    select term.*,
           least(25, sum(rest_raw) over (order by t rows between unbounded preceding and current row))
             - least(25, coalesce(sum(rest_raw) over (order by t rows between unbounded preceding and 1 preceding), 0))
             as rest
    from term
  ),
  run as (
    select b.t,
           b.asleep,
           sum(b.charge) over w as c_charge,
           sum(b.basal - b.rest) over w as c_basal,
           sum(b.active) over w as c_active,
           sum(b.strain) over w as c_strain
    from budget b
    window w as (order by b.t rows between unbounded preceding and current row)
  )
  select r.t,
         least(100, greatest(0, v_anchor + r.c_charge - r.c_basal - r.c_active - r.c_strain)),
         r.asleep,
         r.c_charge, -r.c_basal, -r.c_active, -r.c_strain
  from run r
  order by r.t;
end;
$$;

-- ---------------------------------------------------------------- nb.compute_reserve

-- Same signature as before; the body is now an aggregate over the replay.
--
-- ⚠️ 1CUP · the four rows must close: charge + basal + activity + stress = BB(now) −
-- BB(anchor), within 0.5. If they do not, the whole attribution block goes unrendered and
-- BB_ATTRIBUTION_MISMATCH is raised. There is no OTHER row to absorb the difference, so
-- drivers comes back empty and the page simply omits the card.
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
  v_anchor numeric;
  v_sleep  record;
  v_r      record;
  v_a      integer;      -- the anchor as printed
  v_cur    integer;      -- BODY_BATTERY(now) as printed
  r1 integer; r2 integer; r3 integer; r4 integer;
  v_resid  integer;
  v_assumed boolean;
begin
  select timezone into v_tz from public.profiles where user_id = p_user;
  if v_tz is null then return; end if;

  select * into v_sleep from public.sleep_nights
  where user_id = p_user and user_day = p_user_day;
  -- No night on record → no number at all. The page stays blank rather than
  -- inventing a starting point.
  if v_sleep is null or coalesce(v_sleep.total_minutes, 0) = 0 then return; end if;

  select rd.current_value into v_anchor
  from public.reserve_daily rd
  join public.daily_results dr on dr.id = rd.result_id
  where dr.user_id = p_user and dr.user_day = p_user_day - 1;
  v_assumed := v_anchor is null;
  v_anchor := coalesce(v_anchor, 20);

  -- One replay, read four ways.
  --
  -- BB_WAKE is the value at the moment you woke — the end of the day's *first* sleep run,
  -- not its last. ⚠️ A user day cut at 04:00 opens in the middle of one night and closes
  -- in the middle of the next, so the last sleep tick of the day is 03:55 tomorrow, hours
  -- after the target it feeds was already set. Reading that end pins BB_WAKE at whatever
  -- the night charged it to and TARGET_LOAD goes with it.
  --
  -- BB_WAKE is frozen for the day and only TARGET_LOAD reads it; BODY_BATTERY(t) is the
  -- separate, live symbol.
  with r as materialized (select * from nb.reserve_replay(p_user, p_user_day))
  select
    (select x.value from r x
      where x.asleep and not exists (select 1 from r p where p.ts < x.ts and not p.asleep)
      order by x.ts desc limit 1) as wake,
    (select min(x.value) from r x)                                      as lo,
    (select x.value    from r x order by x.ts desc limit 1)             as cur,
    (select x.d_charge from r x order by x.ts desc limit 1)             as c1,
    (select x.d_basal  from r x order by x.ts desc limit 1)             as c2,
    (select x.d_active from r x order by x.ts desc limit 1)             as c3,
    (select x.d_stress from r x order by x.ts desc limit 1)             as c4
  into v_r;

  if v_r.cur is null then return; end if;

  -- ⚠️ 1CUP · the four rows must close within 0.5 of BB(now) − BB(anchor). They do not
  -- get an OTHER row to absorb a difference: if they miss, the whole block goes away.
  if abs((v_r.c1 + v_r.c2 + v_r.c3 + v_r.c4) - (v_r.cur - v_anchor)) > 0.5 then
    return query select round(coalesce(v_r.wake, v_r.cur))::smallint,
                        round(v_r.cur)::smallint,
                        round(coalesce(v_r.lo, v_r.cur))::smallint,
                        '{}'::jsonb;
    return;
  end if;

  -- Rounding is done as a set, not row by row: four independent rounds can leave the
  -- printed rows a point short of the printed total, and a user who adds up four numbers
  -- on screen and gets a different answer has caught us lying.
  v_a := round(v_anchor); v_cur := round(v_r.cur);
  r1 := round(v_r.c1); r2 := round(v_r.c2); r3 := round(v_r.c3); r4 := round(v_r.c4);
  v_resid := (v_cur - v_a) - (r1 + r2 + r3 + r4);
  -- The residual is at most a point or two; it goes on the largest row, where it is
  -- proportionally invisible.
  if abs(v_r.c1) >= greatest(abs(v_r.c2), abs(v_r.c3), abs(v_r.c4)) then r1 := r1 + v_resid;
  elsif abs(v_r.c2) >= greatest(abs(v_r.c3), abs(v_r.c4)) then r2 := r2 + v_resid;
  elsif abs(v_r.c3) >= abs(v_r.c4) then r3 := r3 + v_resid;
  else r4 := r4 + v_resid;
  end if;

  return query select
    round(coalesce(v_r.wake, v_r.cur))::smallint,
    v_cur::smallint,
    round(coalesce(v_r.lo, v_r.cur))::smallint,
    -- ⚠️ 1CK4 · a cold start derives BB from the assumption that the jar held 20. The detail
    -- page has to say that in words rather than present it as something we measured.
    jsonb_build_object('anchor', v_a, 'assumed_anchor', v_assumed, 'last_night', r1,
                       'awake', r2, 'movement', r3, 'stress', r4);
end;
$$;

-- ---------------------------------------------------------------- reserve_samples

-- The curve the detail page draws. Replaced wholesale on every settle, because BB(t) is a
-- pure function of the ticks: rewriting points in place is exactly the incremental model
-- 1CO9 rules out.
create or replace function nb.materialize_reserve_curve(p_user uuid, p_user_day date)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_tz text;
  v_lo timestamptz;
  v_hi timestamptz;
begin
  select timezone into v_tz from public.profiles where user_id = p_user;
  if v_tz is null then return; end if;
  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);

  delete from public.reserve_samples s
  where s.user_id = p_user and s.ts >= v_lo and s.ts < v_hi;

  insert into public.reserve_samples (user_id, ts, value, source)
  select p_user, r.ts, round(r.value)::smallint, 'model'
  from nb.reserve_replay(p_user, p_user_day) r
  on conflict (user_id, ts) do update set value = excluded.value;
end;
$$;

-- The curve is written whenever the day's reserve row settles, rather than from inside
-- settle_day: one source, one instant, and no chance of a row existing without its curve.
create or replace function nb.on_reserve_settled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_day date;
begin
  select dr.user_day into v_day from public.daily_results dr where dr.id = new.result_id;
  if v_day is not null then
    perform nb.materialize_reserve_curve(new.user_id, v_day);
  end if;
  return null;
end;
$$;

drop trigger if exists reserve_daily_curve on public.reserve_daily;
create trigger reserve_daily_curve
after insert or update on public.reserve_daily
for each row execute function nb.on_reserve_settled();

-- ---------------------------------------------------------------- night inputs

-- 13 · LAST NIGHT'S INPUTS lists what the multiplier was computed from, with each
-- number's own 14-night baseline beside it. It is a trust card, so a value we do not
-- have has to be absent rather than plausible: ⚠️ on iOS the HRV array is routinely
-- empty (1CT0), and printing a number there would be the one lie this page cannot afford.
alter table public.reserve_daily
  add column if not exists night_inputs jsonb not null default '{}'::jsonb;

create or replace function nb.night_inputs(p_user uuid, p_user_day date)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz   text;
  v_rhr  numeric;
  v_base numeric;
  v_n    integer;
begin
  select timezone into v_tz from public.profiles where user_id = p_user;
  if v_tz is null then return '{}'::jsonb; end if;

  v_rhr := nb.night_rhr(p_user, p_user_day, v_tz);

  select count(*), avg(r) into v_n, v_base
  from (
    select nb.night_rhr(p_user, d::date, v_tz) as r
    from generate_series(p_user_day - 14, p_user_day - 1, interval '1 day') d
  ) s where r is not null;

  return jsonb_build_object(
    'rhr',        case when v_rhr is null then null else round(v_rhr) end,
    'rhr_base',   case when coalesce(v_n, 0) = 0 then null else round(v_base) end,
    'rhr_nights', coalesce(v_n, 0),
    -- No RMSSD anywhere in the pipeline yet: the band's HRV lands only after
    -- startReadOriginData completes, and the multiplier degrades to 1.00 without it.
    'hrv',        null,
    'hrv_base',   null,
    'multiplier', round(nb.charge_multiplier(p_user, p_user_day, v_tz), 2));
end;
$$;

create or replace function nb.on_reserve_settled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_day date;
begin
  select dr.user_day into v_day from public.daily_results dr where dr.id = new.result_id;
  if v_day is not null then
    perform nb.materialize_reserve_curve(new.user_id, v_day);
    if new.night_inputs = '{}'::jsonb then
      update public.reserve_daily set night_inputs = nb.night_inputs(new.user_id, v_day)
      where result_id = new.result_id;
    end if;
  end if;
  return null;
end;
$$;
