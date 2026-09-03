-- Body Battery v2: use Veepoo's real sleep-line stages and every measured daytime signal.
--
-- The SDK's accurate sleep stage ids are 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake.
-- raw_samples.sleep_states is empty on HOOP firmware; the authoritative stages live in
-- sleep_nights.sleep_line. The old replay treated stage 0 as awake, so a deep night spent
-- 0.30 points every five minutes until the score reached zero.

create or replace function nb.reserve_anchor(p_user uuid, p_user_day date)
returns numeric
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (
      select rd.current_value::numeric
      from public.reserve_daily rd
      join public.daily_results dr on dr.id = rd.result_id
      where dr.user_id = p_user and dr.user_day = p_user_day - 1
    ),
    case when exists (
      select 1 from public.sleep_nights s
      where s.user_id = p_user and s.user_day = p_user_day
        and coalesce(s.total_minutes, 0) > 0
        and s.sleep_start is not null and s.wake_at is not null
        and s.wake_at > s.sleep_start
    ) then 20::numeric else 50::numeric end
  );
$$;

create or replace function nb.reserve_replay(p_user uuid, p_user_day date)
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
  from public.profiles p where p.user_id = p_user;
  if v_tz is null then return; end if;
  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);

  v_anchor := nb.reserve_anchor(p_user, p_user_day);

  v_rhr    := coalesce(nb.night_rhr(p_user, p_user_day, v_tz),
                       nb.hr_rest(p_user, p_user_day, v_tz), 55);
  v_hr_max := coalesce(nb.hr_max(v_birth), 190);

  select avg(h) into v_hrv_base
  from (
    select nb.night_hrv(p_user, d::date) as h
    from generate_series(p_user_day - 14, p_user_day - 1, interval '1 day') d
  ) history
  where h is not null;

  return query
  with recursive
  night as (
    select s.user_day, s.sleep_start, s.wake_at, s.sleep_line,
           coalesce(nb.charge_multiplier(p_user, s.user_day, v_tz), 1) as multiplier,
           case when coalesce(s.total_minutes, 0) > 0
                then (1.25 * coalesce(s.deep_minutes, 0)
                    + 0.85 * coalesce(s.light_minutes, 0)
                    + greatest(0, s.total_minutes
                        - coalesce(s.deep_minutes, 0)
                        - coalesce(s.light_minutes, 0)))
                     / s.total_minutes::numeric
                else 0 end as fallback_q
    from public.sleep_nights s
    -- One 04:00→04:00 user day intersects two wake-keyed nights: this morning's
    -- 04:00→wake segment and tonight's sleep-start→04:00 segment.
    where s.user_id = p_user
      and s.user_day between p_user_day and p_user_day + 1
  ),
  parsed_run as (
    select n.user_day, n.sleep_start, n.wake_at, n.multiplier, u.ordinality,
           split_part(u.token, ':', 1)::integer as stage,
           split_part(u.token, ':', 2)::integer as minutes
    from night n
    cross join lateral unnest(string_to_array(coalesce(n.sleep_line, ''), ','))
      with ordinality as u(token, ordinality)
    where u.token ~ '^[0-4]:[1-9][0-9]*$'
  ),
  run_offset as (
    select r.*,
           coalesce(sum(r.minutes) over (
             partition by r.user_day
             order by r.ordinality
             rows between unbounded preceding and 1 preceding
           ), 0)::integer as starts_minute
    from parsed_run r
  ),
  sleep_minute as (
    select r.sleep_start
             + (r.starts_minute + minute.index) * interval '1 minute' as at,
           r.stage,
           (case r.stage
             when 0 then 1.25
             when 1 then 0.85
             when 2 then 1.00
             when 3 then 0.15
             else 0.00
           end * r.multiplier)::numeric as recovery
    from run_offset r
    cross join lateral generate_series(0, r.minutes - 1) as minute(index)
    where r.sleep_start is not null
  ),
  sleep_tick as (
    select date_bin(interval '5 minutes', m.at, v_lo) as t,
           least(1, count(*)::numeric / 5) as recorded_fraction,
           least(1, (count(*) filter (where m.stage <> 4))::numeric / 5) as sleep_fraction,
           sum(m.recovery) / 5 as recovery_effect
    from sleep_minute m
    group by 1
  ),
  fallback_minute as (
    select minute.at,
           n.fallback_q * n.multiplier as recovery
    from night n
    cross join lateral generate_series(
      greatest(n.sleep_start, v_lo),
      least(n.wake_at - interval '1 minute', v_hi - interval '1 minute'),
      interval '1 minute'
    ) as minute(at)
    where nullif(n.sleep_line, '') is null
      and n.sleep_start is not null and n.wake_at is not null
      and n.wake_at > v_lo and n.sleep_start < v_hi
  ),
  fallback_tick as (
    select date_bin(interval '5 minutes', m.at, v_lo) as t,
           least(1, count(*)::numeric / 5) as recorded_fraction,
           least(1, count(*)::numeric / 5) as sleep_fraction,
           sum(m.recovery) / 5 as recovery_effect
    from fallback_minute m
    group by 1
  ),
  sleep_evidence as (
    select evidence.t,
           least(1, sum(evidence.recorded_fraction)) as recorded_fraction,
           least(1, sum(evidence.sleep_fraction)) as sleep_fraction,
           sum(evidence.recovery_effect) as recovery_effect
    from (
      select * from sleep_tick
      union all
      select * from fallback_tick
    ) evidence
    group by evidence.t
  ),
  tick_grid as (
    select generate_series(
      v_lo,
      least(v_hi - interval '5 minutes', date_bin(interval '5 minutes', now(), v_lo)),
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
             and coalesce(f.stress, 0) <= 35
             and (f.hrv is null or v_hrv_base is null or f.hrv >= v_hrv_base * 0.90)
             and f.move < 0.03 and coalesce(f.step, 0) = 0 as quiet
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
        case when x.quiet and quiet.next_quiet_minutes >= 20
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

-- A recorded night improves the anchor and freezes BB_WAKE, but it is not permission to have
-- a current score. Daytime wrist signals can start from a neutral, explicitly assumed 50.
create or replace function nb.compute_reserve(p_user uuid, p_user_day date)
returns table (
  wake_value     smallint,
  current_value  smallint,
  min_value      smallint,
  drivers        jsonb
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz        text;
  v_anchor    numeric;
  v_previous  numeric;
  v_r         record;
  v_has_night boolean;
  v_a         integer;
  v_cur       integer;
  r1 integer; r2 integer; r3 integer; r4 integer;
  v_resid     integer;
  v_assumed   boolean;
begin
  select timezone into v_tz from public.profiles where user_id = p_user;
  if v_tz is null then return; end if;

  select exists (
    select 1 from public.sleep_nights s
    where s.user_id = p_user and s.user_day = p_user_day
      and coalesce(s.total_minutes, 0) > 0
      and s.sleep_start is not null and s.wake_at is not null
      and s.wake_at > s.sleep_start
  ) into v_has_night;

  select rd.current_value into v_previous
  from public.reserve_daily rd
  join public.daily_results dr on dr.id = rd.result_id
  where dr.user_id = p_user and dr.user_day = p_user_day - 1;
  v_assumed := v_previous is null;
  v_anchor := nb.reserve_anchor(p_user, p_user_day);

  with r as materialized (select * from nb.reserve_replay(p_user, p_user_day))
  select
    (select x.value from r x
      where x.asleep and not exists (
        select 1 from r p where p.ts < x.ts and not p.asleep
      )
      order by x.ts desc limit 1) as wake,
    (select min(x.value) from r x) as lo,
    (select x.value from r x order by x.ts desc limit 1) as cur,
    (select x.d_charge from r x order by x.ts desc limit 1) as c1,
    (select x.d_basal from r x order by x.ts desc limit 1) as c2,
    (select x.d_active from r x order by x.ts desc limit 1) as c3,
    (select x.d_stress from r x order by x.ts desc limit 1) as c4
  into v_r;

  -- No wrist or sleep evidence is still unknown. Sleep is no longer the hard gate.
  if v_r.cur is null then return; end if;

  if abs((v_r.c1 + v_r.c2 + v_r.c3 + v_r.c4) - (v_r.cur - v_anchor)) > 0.5 then
    return query select
      case when v_has_night then round(coalesce(v_r.wake, v_r.cur))::smallint end,
      round(v_r.cur)::smallint,
      round(coalesce(v_r.lo, v_r.cur))::smallint,
      '{}'::jsonb;
    return;
  end if;

  v_a := round(v_anchor);
  v_cur := round(v_r.cur);
  r1 := round(v_r.c1);
  r2 := round(v_r.c2);
  r3 := round(v_r.c3);
  r4 := round(v_r.c4);
  v_resid := (v_cur - v_a) - (r1 + r2 + r3 + r4);
  if abs(v_r.c1) >= greatest(abs(v_r.c2), abs(v_r.c3), abs(v_r.c4)) then
    r1 := r1 + v_resid;
  elsif abs(v_r.c2) >= greatest(abs(v_r.c3), abs(v_r.c4)) then
    r2 := r2 + v_resid;
  elsif abs(v_r.c3) >= abs(v_r.c4) then
    r3 := r3 + v_resid;
  else
    r4 := r4 + v_resid;
  end if;

  return query select
    case when v_has_night then round(coalesce(v_r.wake, v_r.cur))::smallint end,
    v_cur::smallint,
    round(coalesce(v_r.lo, v_r.cur))::smallint,
    jsonb_build_object(
      'anchor', v_a,
      'assumed_anchor', v_assumed,
      'last_night', r1,
      'awake', r2,
      'movement', r3,
      'stress', r4
    );
end;
$$;

-- Keep the audit token honest without duplicating the large settle_day body in this migration.
do $$
declare
  definition text;
begin
  select pg_get_functiondef('nb.settle_day(uuid,date)'::regprocedure) into definition;
  if definition is not null then
    definition := replace(definition, 'bb-1.4', 'bb-2.0');
    definition := replace(
      definition,
      'if v_reserve.wake_value is not null then',
      'if v_reserve.current_value is not null then'
    );
    execute definition;
  end if;
end;
$$;
