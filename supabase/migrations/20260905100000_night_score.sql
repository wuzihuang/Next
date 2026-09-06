-- ================================================================ night_score
--
-- ADR 0008 · HOOP scores the night. The score is settled server-side once per night and
-- read back as thirty small rows, because the two inputs that make a night legible are the
-- two that cannot travel: overnight SpO2 lives as ~400 per-minute rows a night, and sleep
-- respiration lives only inside sleep_nights.raw, a 30-50 KB jsonb per night that PostgREST
-- cannot project without reading whole. Aggregating them here costs one index scan and
-- leaves the wire carrying a smallint.
--
-- The second reason is consistency: if the week window scored on a smaller input set than
-- the day window, one night would carry two different scores. It is settled once.

-- ---------------------------------------------------------------- scorers

-- A trapezoid: full marks across [full_lo, full_hi], falling linearly to zero at zero_lo and
-- zero_hi. A null bound means that side carries no penalty.
create or replace function nb.score_window(v numeric, zero_lo numeric, full_lo numeric,
                                           full_hi numeric, zero_hi numeric)
returns numeric
language sql
immutable
as $$
  select case
    when v is null then null
    when v >= full_lo and v <= full_hi then 100
    when v < full_lo then
      case when zero_lo is null then 100
           else greatest(0, 100 * (v - zero_lo) / nullif(full_lo - zero_lo, 0)) end
    else
      case when zero_hi is null then 100
           else greatest(0, 100 * (zero_hi - v) / nullif(zero_hi - full_hi, 0)) end
  end;
$$;

-- Duration is the one input everyone reads without being taught, so it gets explicit
-- anchors rather than a trapezoid: 4h→0, 5h→50, 6h→70, 7.5h→100, flat to 9.5h, then a mild
-- penalty that floors at 70. Sleeping too long is worth noticing and not worth punishing.
create or replace function nb.score_sleep_duration(v numeric)
returns numeric
language sql
immutable
as $$
  select case
    when v is null then null
    when v <= 240 then 0
    when v <  300 then 50 * (v - 240) / 60
    when v <  360 then 50 + 20 * (v - 300) / 60
    when v <  450 then 70 + 30 * (v - 360) / 90
    when v <= 570 then 100
    else greatest(70, 100 - 30 * (v - 570) / 120)
  end;
$$;

-- Minutes past 18:00 local, so an 01:20 bedtime and a 23:40 one are 100 minutes apart
-- rather than twenty-two hours.
create or replace function nb.evening_offset(p_at timestamptz, p_tz text)
returns numeric
language sql
immutable
as $$
  select case when p_at is null or p_tz is null then null else
    (((extract(hour from p_at at time zone p_tz) * 60
      + extract(minute from p_at at time zone p_tz)) - 1080)::int % 1440 + 1440) % 1440
  end;
$$;

-- Weighted mean over the members that exist, so a missing input shrinks the evidence
-- instead of scoring zero. Null when the group has nothing to say.
create or replace function nb.weighted_present(p_values numeric[], p_weights numeric[])
returns numeric
language sql
immutable
as $$
  select case when sum(w) is null or sum(w) = 0 then null else sum(v * w) / sum(w) end
  from unnest(p_values, p_weights) as t(v, w)
  where v is not null;
$$;

-- ---------------------------------------------------------------- per-night aggregates

-- Overnight SpO2 reduced to the two numbers the score needs. Clipped to the band's own
-- sleep window; a night without a window has no overnight oxygen by definition.
create or replace function nb.night_oxygen_stats(p_user uuid, p_user_day date)
returns table (spo2_min smallint, spo2_mean numeric, sample_count integer)
language sql
stable
security definer
set search_path = ''
as $$
  select min(o.spo2)::smallint, round(avg(o.spo2), 1), count(*)::integer
  from public.sleep_nights sn
  join public.oxygen_samples o
    on o.user_id = sn.user_id and o.ts >= sn.sleep_start and o.ts < sn.wake_at
  where sn.user_id = p_user and sn.user_day = p_user_day
    and sn.sleep_start is not null and sn.wake_at is not null
  having count(*) > 0;
$$;

-- Respiration exists only inside sleep_nights.raw. Reading it here is the whole reason the
-- score is settled server-side: the same value on the wire would drag the blob with it.
create or replace function nb.night_respiration_mean(p_user uuid, p_user_day date)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select round(avg((e->>'breaths_per_minute')::numeric), 1)
  from public.sleep_nights sn,
       lateral jsonb_array_elements(coalesce(sn.raw -> 'respiration', '[]'::jsonb)) e
  where sn.user_id = p_user and sn.user_day = p_user_day
    and (e ->> 'breaths_per_minute') ~ '^[0-9]+(\.[0-9]+)?$'
    and (e ->> 'breaths_per_minute')::numeric between 4 and 40;
$$;

-- Stage runs are stored as "stage:minutes" pairs. Only the line can answer REM and awake;
-- the row itself stores deep and light and nothing else.
create or replace function nb.sleep_line_minutes(p_line text, p_stage int)
returns integer
language sql
immutable
as $$
  select coalesce(sum(split_part(run, ':', 2)::int), 0)::int
  from unnest(string_to_array(coalesce(p_line, ''), ',')) run
  where run ~ '^[0-9]+:[0-9]+$' and split_part(run, ':', 1)::int = p_stage;
$$;

-- ---------------------------------------------------------------- the score

-- Four groups, weighted 25 / 25 / 35 / 15. Duration and architecture are scored against
-- fixed thresholds forever: a person who has slept five hours a night for three months must
-- not be handed a 95 for it. Recovery and regularity migrate to that person's own baseline
-- from the fourteenth night, because RMSSD ranges too widely between healthy people for a
-- population line to mean anything, and "on time" is only definable against yourself.
create or replace function nb.night_score_parts(p_user uuid, p_user_day date)
returns table (
  score numeric, duration_score numeric, architecture_score numeric,
  recovery_score numeric, regularity_score numeric, personal_weight numeric, inputs jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz         text;
  v_night      record;
  v_ox         record;
  v_resp       numeric;
  v_hrv        numeric;
  v_rhr        numeric;
  v_nights     integer;
  v_w          numeric;
  v_hrv_base   numeric;
  v_rhr_base   numeric;
  v_bed_median numeric;
  v_bed        numeric;
  v_bed_gap    numeric;
  v_deep_pct   numeric;
  v_light_pct  numeric;
  v_rem_pct    numeric;
  v_rem_min    integer;
  v_dur        numeric;
  v_arch       numeric;
  v_rec        numeric;
  v_reg        numeric;
  v_total      numeric;
begin
  select p.timezone into v_tz from public.profiles p where p.user_id = p_user;

  select sn.total_minutes, sn.deep_minutes, sn.light_minutes, sn.wake_count,
         sn.sleep_line, sn.sleep_start
    into v_night
  from public.sleep_nights sn
  where sn.user_id = p_user and sn.user_day = p_user_day;

  -- No night on record is not a bad night. It has no score at all.
  if v_night is null or coalesce(v_night.total_minutes, 0) <= 0 then
    return;
  end if;

  select * into v_ox from nb.night_oxygen_stats(p_user, p_user_day);
  v_resp := nb.night_respiration_mean(p_user, p_user_day);

  select nh.rmssd_ms into v_hrv from public.night_hrv nh
  where nh.user_id = p_user and nh.user_day = p_user_day;

  select (rd.night_inputs ->> 'rhr')::numeric into v_rhr
  from public.daily_results dr
  join public.reserve_daily rd on rd.result_id = dr.id
  where dr.user_id = p_user and dr.user_day = p_user_day
    and rd.night_inputs ? 'rhr';

  -- How much of this person we have seen. Fourteen nights before any calibration begins,
  -- fully personal by twenty-eight, linear between — a hard switch moves the score by ten
  -- points on a morning nothing happened.
  select count(*) into v_nights from public.sleep_nights sn
  where sn.user_id = p_user
    and sn.user_day between p_user_day - 28 and p_user_day - 1
    and coalesce(sn.total_minutes, 0) > 0;
  v_w := greatest(0, least(1, (v_nights - 14)::numeric / 14));

  select percentile_cont(0.5) within group (order by nh.rmssd_ms) into v_hrv_base
  from public.night_hrv nh
  where nh.user_id = p_user and nh.user_day between p_user_day - 28 and p_user_day - 1;

  select percentile_cont(0.5) within group (order by (rd.night_inputs ->> 'rhr')::numeric)
    into v_rhr_base
  from public.daily_results dr
  join public.reserve_daily rd on rd.result_id = dr.id
  where dr.user_id = p_user
    and dr.user_day between p_user_day - 28 and p_user_day - 1
    and rd.night_inputs ? 'rhr';

  v_hrv_base := 40 * (1 - v_w) + coalesce(v_hrv_base, 40) * v_w;
  v_rhr_base := 60 * (1 - v_w) + coalesce(v_rhr_base, 60) * v_w;

  -- ---- duration
  v_dur := nb.score_sleep_duration(v_night.total_minutes);

  -- ---- architecture
  v_deep_pct := case when v_night.deep_minutes is null then null
                     else 100.0 * v_night.deep_minutes / v_night.total_minutes end;
  -- Carried for the week and month windows, which draw stage proportions from these rows
  -- rather than re-fetching thirty nights of sleep_nights.
  v_light_pct := case when v_night.light_minutes is null then null
                      else 100.0 * v_night.light_minutes / v_night.total_minutes end;
  if v_night.sleep_line is null or v_night.sleep_line = '' then
    v_rem_min := null; v_rem_pct := null;
  else
    v_rem_min := nb.sleep_line_minutes(v_night.sleep_line, 2);
    v_rem_pct := 100.0 * v_rem_min / v_night.total_minutes;
  end if;

  v_arch := nb.weighted_present(
    array[nb.score_window(v_deep_pct, 0, 13, 23, 45),
          nb.score_window(v_rem_pct, 0, 20, 25, 50),
          case when v_night.wake_count is null then null
               else greatest(0, 100 - 20 * (greatest(v_night.wake_count, 1) - 1)) end],
    array[40, 40, 20]);

  -- ---- recovery
  v_rec := nb.weighted_present(
    array[nb.score_window(v_hrv, 0.4 * v_hrv_base, 0.9 * v_hrv_base, 1e9, null),
          nb.score_window(v_rhr, v_rhr_base - 25, v_rhr_base - 5, v_rhr_base + 5, v_rhr_base + 25),
          nb.score_window(v_ox.spo2_min, 88, 95, 100, null),
          nb.score_window(v_resp, 6, 12, 18, 30)],
    array[35, 25, 20, 20]);

  -- ---- regularity · silent until there is a baseline to be irregular against
  v_bed := nb.evening_offset(v_night.sleep_start, v_tz);
  if v_nights >= 14 and v_bed is not null then
    select percentile_cont(0.5) within group (order by nb.evening_offset(sn.sleep_start, v_tz))
      into v_bed_median
    from public.sleep_nights sn
    where sn.user_id = p_user
      and sn.user_day between p_user_day - 28 and p_user_day - 1
      and sn.sleep_start is not null;
    if v_bed_median is not null then
      v_bed_gap := abs(v_bed - v_bed_median);
      v_bed_gap := least(v_bed_gap, 1440 - v_bed_gap);
      v_reg := nb.score_window(v_bed_gap, null, 0, 30, 120);
    end if;
  end if;

  v_total := nb.weighted_present(array[v_dur, v_arch, v_rec, v_reg], array[25, 25, 35, 15]);
  if v_total is null then return; end if;

  return query select
    round(v_total), round(v_dur), round(v_arch), round(v_rec), round(v_reg), round(v_w, 2),
    jsonb_strip_nulls(jsonb_build_object(
      'duration_min', v_night.total_minutes,
      'deep_pct',     round(v_deep_pct, 1),
      'light_pct',    round(v_light_pct, 1),
      'rem_pct',      round(v_rem_pct, 1),
      'rem_min',      v_rem_min,
      'wakes',        v_night.wake_count,
      'hrv_ms',       v_hrv,
      'hrv_base',     round(v_hrv_base, 1),
      'rhr',          v_rhr,
      'rhr_base',     round(v_rhr_base, 1),
      'spo2_min',     v_ox.spo2_min,
      'spo2_mean',    v_ox.spo2_mean,
      'spo2_n',       v_ox.sample_count,
      'respiration',  v_resp,
      'bed_offset',   v_bed,
      'bed_median',   round(v_bed_median, 0),
      'baseline_nights', v_nights));
end;
$$;

-- ---------------------------------------------------------------- the row

-- A derived table, deliberately not a column on sleep_nights: that table's meaning is
-- "what the band reported", and a score recomputed on every algorithm change would have to
-- be UPDATEd into the middle of the raw record. This one can be rebuilt.
create table if not exists public.night_score (
  user_id            uuid not null references auth.users (id) on delete cascade,
  user_day           date not null,
  score              smallint not null check (score between 0 and 100),
  duration_score     smallint check (duration_score between 0 and 100),
  architecture_score smallint check (architecture_score between 0 and 100),
  recovery_score     smallint check (recovery_score between 0 and 100),
  regularity_score   smallint check (regularity_score between 0 and 100),
  personal_weight    numeric(3, 2) not null default 0 check (personal_weight between 0 and 1),
  inputs             jsonb not null default '{}'::jsonb,
  score_version      text not null,
  computed_at        timestamptz not null default now(),
  primary key (user_id, user_day)
);

comment on table public.night_score is
  'ADR 0008 · one settled sleep score per night. Derived: safe to truncate and rebuild.';
comment on column public.night_score.personal_weight is
  '0 = scored against population baselines, 1 = fully against this person''s own. Ramps 14 to 28 nights.';
comment on column public.night_score.inputs is
  'The measured values behind the score, including which were absent. A group score is a weighted mean over the inputs that existed.';

alter table public.night_score enable row level security;
create policy night_score_select on public.night_score
  for select to authenticated using ((select auth.uid()) = user_id);

-- Read-only to the client. Nothing about this row is the phone's to assert.
grant select on public.night_score to authenticated;

create or replace function nb.refresh_night_score(p_user uuid, p_user_day date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_parts record;
begin
  select * into v_parts from nb.night_score_parts(p_user, p_user_day);

  -- A night that lost its record loses its score with it, rather than leaving yesterday's
  -- number sitting there being read as today's.
  if v_parts.score is null then
    delete from public.night_score where user_id = p_user and user_day = p_user_day;
    return;
  end if;

  insert into public.night_score as n
    (user_id, user_day, score, duration_score, architecture_score, recovery_score,
     regularity_score, personal_weight, inputs, score_version, computed_at)
  values
    (p_user, p_user_day, v_parts.score, v_parts.duration_score, v_parts.architecture_score,
     v_parts.recovery_score, v_parts.regularity_score, v_parts.personal_weight,
     v_parts.inputs, 'sleep-v1', now())
  on conflict (user_id, user_day) do update set
    score              = excluded.score,
    duration_score     = excluded.duration_score,
    architecture_score = excluded.architecture_score,
    recovery_score     = excluded.recovery_score,
    regularity_score   = excluded.regularity_score,
    personal_weight    = excluded.personal_weight,
    inputs             = excluded.inputs,
    score_version      = excluded.score_version,
    computed_at        = excluded.computed_at;
end;
$$;

-- ---------------------------------------------------------------- refreshed with the day

-- Ordered after refresh_night_hrv: the score reads the row that call just wrote.
create or replace function nb.recompute_range(p_user uuid, p_from date, p_to date,
                                              p_reason text default 'manual')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare d date; n int := 0; v_algo text;
begin
  for d in select generate_series(p_from, p_to, interval '1 day')::date loop
    perform nb.refresh_night_hrv(p_user, d);
    perform nb.settle_day(p_user, d);
    perform nb.refresh_night_score(p_user, d);
    n := n + 1;
  end loop;

  select dr.algo_version into v_algo from public.daily_results dr
  where dr.user_id = p_user order by dr.computed_at desc limit 1;

  insert into public.recompute_log (algo_version, reason, rows_touched)
  values (coalesce(v_algo, 'unknown'), p_reason, n);

  return n;
end;
$$;

revoke execute on function nb.recompute_range(uuid, date, date, text) from public, anon, authenticated;
revoke execute on function nb.night_score_parts(uuid, date) from public, anon, authenticated;
revoke execute on function nb.refresh_night_score(uuid, date) from public, anon, authenticated;
revoke execute on function nb.night_oxygen_stats(uuid, date) from public, anon, authenticated;
revoke execute on function nb.night_respiration_mean(uuid, date) from public, anon, authenticated;

-- ---------------------------------------------------------------- erasure completeness

-- night_score cascades with auth.users, but the house pattern names every table explicitly
-- so that a reader of this function can see the whole footprint in one place.
create or replace function nb.account_delete_legacy_oxygen(confirm text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null then return jsonb_build_object('error', 'UNAUTHENTICATED'); end if;
  if confirm is distinct from 'DELETE' then return jsonb_build_object('error', 'E_SCHEMA'); end if;

  update public.profiles set deletion_requested_at = now() where user_id = v_user;
  delete from public.screen_frames where user_id = v_user;
  delete from public.ai_turns where user_id = v_user;
  delete from public.analytics_events where user_id = v_user;
  delete from public.call_changes where user_id = v_user;
  delete from public.meals where user_id = v_user;
  delete from public.weigh_ins where user_id = v_user;
  delete from public.body_composition where user_id = v_user;
  delete from public.oxygen_samples where user_id = v_user;
  delete from public.response_samples where user_id = v_user;
  delete from public.raw_samples where user_id = v_user;
  delete from public.reserve_samples where user_id = v_user;
  delete from public.night_score where user_id = v_user;
  delete from public.sleep_nights where user_id = v_user;
  delete from public.night_hrv where user_id = v_user;
  delete from public.daily_results where user_id = v_user;
  delete from public.sync_runs where user_id = v_user;
  delete from public.device_capabilities where user_id = v_user;
  delete from public.devices where user_id = v_user;
  delete from public.profiles where user_id = v_user;
  delete from auth.users where id = v_user;
  return jsonb_build_object('deleted', true);
end;
$$;

revoke all on function nb.account_delete_legacy_oxygen(text) from public, anon, authenticated;
