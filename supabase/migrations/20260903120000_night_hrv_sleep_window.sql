-- The night's HRV, taken over the night the band actually recorded.
--
-- Until now the phone computed it over a fixed 00:00–11:59 window and uploaded one number.
-- On the night of 2026-09-03 the user slept 02:13 → 09:03, so that window carried two hours
-- awake before sleep and three hours awake after waking: 55.98 ms against 51.0 ms over the
-- real window. The window was a stand-in for a night nobody knew, and both halves of it are
-- known now — sleep_nights.sleep_start/wake_at since 20260903090000, and every tick's RMSSD
-- in raw_samples.hrv since 20260903100000.
--
-- ⚠️ The phone cannot do this correctly and is no longer asked to. A night that begins before
-- midnight lies in the previous calendar day, which is a different SDK page and a different
-- user day; a sync reading today's page alone cannot see its own night's first half. The
-- server sees absolute instants and has no such seam.
--
-- The rule is otherwise unchanged, so only the window moved: 15-minute buckets across the
-- night, the median inside each bucket, then the median of the bucket medians. No sleep
-- record means no night, exactly as nb.reserve already treats a night it does not have.

create or replace function nb.night_hrv_parts(p_user uuid, p_user_day date)
returns table (rmssd_ms numeric, bucket_count integer, tick_count integer)
language sql
stable
set search_path = ''
as $$
  with night as (
    select s.sleep_start, s.wake_at
    from public.sleep_nights s
    where s.user_id = p_user
      and s.user_day = p_user_day
      and s.sleep_start is not null
      and s.wake_at is not null
  ),
  ticks as (
    select r.hrv,
           floor(extract(epoch from (r.ts - n.sleep_start)) / 900)::integer as bucket
    from public.raw_samples r
    cross join night n
    where r.user_id = p_user
      and r.ts >= n.sleep_start
      and r.ts <  n.wake_at
      and r.hrv is not null
      -- The same 1–300 ms band the bridge trusts, so a tick chart and this number never
      -- disagree about which readings were plausible.
      and r.hrv between 1 and 300
  ),
  buckets as (
    select percentile_cont(0.5) within group (order by t.hrv) as v, count(*) as n
    from ticks t
    group by t.bucket
  )
  select round(percentile_cont(0.5) within group (order by b.v)::numeric, 2),
         count(b.v)::integer,
         coalesce(sum(b.n), 0)::integer
  from buckets b;
$$;

create or replace function nb.night_hrv(p_user uuid, p_user_day date)
returns numeric
language sql
stable
set search_path = ''
as $$
  select p.rmssd_ms from nb.night_hrv_parts(p_user, p_user_day) p;
$$;

-- ---------------------------------------------------------------- the export's own row

-- night_hrv is one of the five files in the data export, so the table keeps being written —
-- by the server now, which is the only place the number can be got right. rr_count was the
-- phone's count of RR intervals and there is no honest server value for it: a null is what
-- we know. bucket_count becomes the number of 15-minute buckets the night was built from.

alter table public.night_hrv alter column rr_count drop not null;
alter table public.night_hrv drop constraint if exists night_hrv_rr_count_check;
alter table public.night_hrv add constraint night_hrv_rr_count_check
  check (rr_count is null or rr_count > 1);
alter table public.night_hrv drop constraint if exists night_hrv_source_check;
alter table public.night_hrv add constraint night_hrv_source_check
  check (source in ('band_rr', 'band_rr_window'));

comment on column public.night_hrv.rr_count is
  'RR intervals behind the night, when a client counted them. Null for server-derived rows.';
comment on column public.night_hrv.source is
  'band_rr: the phone''s fixed 00:00-11:59 window, before 2026-09-03. band_rr_window: the band''s own sleep window.';

create or replace function nb.refresh_night_hrv(p_user uuid, p_user_day date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz    text;
  v_parts record;
begin
  select p.timezone into v_tz from public.profiles p where p.user_id = p_user;
  if v_tz is null then return; end if;

  select * into v_parts from nb.night_hrv_parts(p_user, p_user_day);

  -- Nothing to say tonight. A row from the old window would otherwise sit there being read
  -- as though it meant the same thing.
  if v_parts.rmssd_ms is null then
    delete from public.night_hrv where user_id = p_user and user_day = p_user_day;
    return;
  end if;

  insert into public.night_hrv as h
    (user_id, user_day, rmssd_ms, bucket_count, rr_count, sampled_tz, source, collected_at)
  values
    (p_user, p_user_day, v_parts.rmssd_ms, v_parts.bucket_count, null, v_tz,
     'band_rr_window', now())
  on conflict (user_id, user_day) do update set
    rmssd_ms     = excluded.rmssd_ms,
    bucket_count = excluded.bucket_count,
    rr_count     = null,
    sampled_tz   = excluded.sampled_tz,
    source       = excluded.source,
    collected_at = now();
end;
$$;

revoke execute on function nb.refresh_night_hrv(uuid, date) from public, anon, authenticated;

-- ---------------------------------------------------------------- what the algorithm reads

-- Both of these read the function, never the table: the table is refreshed at settle, while
-- fill_hrv can land a night's ticks at any sync, and the multiplier must not be a settle
-- behind the data it is weighing.

create or replace function nb.charge_multiplier(p_user uuid, p_user_day date, p_tz text)
returns numeric
language plpgsql
stable
set search_path = ''
as $$
declare
  v_hrv      numeric;
  v_hrv_mean numeric;
  v_hrv_sd   numeric;
  v_hrv_n    integer;
  v_rhr      numeric;
  v_rhr_mean numeric;
  v_rhr_sd   numeric;
  v_rhr_n    integer;
  v_m_hrv    numeric := 1.00;
  v_m_rhr    numeric := 1.00;
begin
  v_hrv := nb.night_hrv(p_user, p_user_day);
  select count(*), avg(h), stddev_samp(h) into v_hrv_n, v_hrv_mean, v_hrv_sd
  from (
    select nb.night_hrv(p_user, d::date) as h
    from generate_series(p_user_day - 14, p_user_day - 1, interval '1 day') d
  ) s where h is not null;
  if v_hrv is not null and coalesce(v_hrv_n, 0) >= 5 and coalesce(v_hrv_sd, 0) >= 0.5 then
    v_m_hrv := least(1.25, greatest(0.75,
      1.00 + 0.25 * ((v_hrv - v_hrv_mean) / v_hrv_sd)));
  end if;

  v_rhr := nb.night_rhr(p_user, p_user_day, p_tz);
  select count(*), avg(r), stddev_samp(r) into v_rhr_n, v_rhr_mean, v_rhr_sd
  from (
    select nb.night_rhr(p_user, d::date, p_tz) as r
    from generate_series(p_user_day - 14, p_user_day - 1, interval '1 day') d
  ) s where r is not null;
  if v_rhr is not null and coalesce(v_rhr_n, 0) >= 5 and coalesce(v_rhr_sd, 0) >= 0.5 then
    v_m_rhr := least(1.25, greatest(0.75,
      1.00 + 0.25 * ((v_rhr_mean - v_rhr) / v_rhr_sd)));
  end if;

  return least(1.30, greatest(0.65, v_m_hrv * v_m_rhr));
end;
$$;

create or replace function nb.night_inputs(p_user uuid, p_user_day date)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz       text;
  v_rhr      numeric;
  v_rhr_base numeric;
  v_rhr_n    integer;
  v_hrv      numeric;
  v_hrv_base numeric;
  v_hrv_n    integer;
begin
  select timezone into v_tz from public.profiles where user_id = p_user;
  if v_tz is null then return '{}'::jsonb; end if;

  v_rhr := nb.night_rhr(p_user, p_user_day, v_tz);
  select count(*), avg(r) into v_rhr_n, v_rhr_base
  from (
    select nb.night_rhr(p_user, d::date, v_tz) as r
    from generate_series(p_user_day - 14, p_user_day - 1, interval '1 day') d
  ) s where r is not null;

  v_hrv := nb.night_hrv(p_user, p_user_day);
  select count(*), avg(h) into v_hrv_n, v_hrv_base
  from (
    select nb.night_hrv(p_user, d::date) as h
    from generate_series(p_user_day - 14, p_user_day - 1, interval '1 day') d
  ) s where h is not null;

  return jsonb_build_object(
    'rhr',        case when v_rhr is null then null else round(v_rhr) end,
    'rhr_base',   case when coalesce(v_rhr_n, 0) = 0 then null else round(v_rhr_base) end,
    'rhr_nights', coalesce(v_rhr_n, 0),
    'hrv',        case when v_hrv is null then null else round(v_hrv) end,
    'hrv_base',   case when coalesce(v_hrv_n, 0) = 0 then null else round(v_hrv_base) end,
    'hrv_nights', coalesce(v_hrv_n, 0),
    'multiplier', round(nb.charge_multiplier(p_user, p_user_day, v_tz), 2));
end;
$$;

-- ---------------------------------------------------------------- refreshed with the day

-- Every settle, from the cron and from the app's own settle_now, goes through here. The row
-- follows the ticks: a night whose HRV arrives an hour late is right at the next sync.

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

-- Internal to the compute path, like every other nb.* helper: reached through the security
-- definer functions above, never called by a client.
revoke execute on function nb.night_hrv_parts(uuid, date) from public, anon, authenticated;
revoke execute on function nb.night_hrv(uuid, date) from public, anon, authenticated;
