-- Minimal stand-in for the parts of the HOOP schema that 20260905100000_night_score.sql
-- touches. Column types copied from the real migrations.
create schema if not exists auth;
create schema if not exists nb;

create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  timezone text,
  deletion_requested_at timestamptz
);

create table public.sleep_nights (
  user_id uuid not null references auth.users(id) on delete cascade,
  user_day date not null,
  total_minutes smallint, deep_minutes smallint, light_minutes smallint, wake_count smallint,
  sleep_line text, sleep_start timestamptz, wake_at timestamptz,
  raw jsonb not null default '{}'::jsonb,
  primary key (user_id, user_day)
);

create table public.night_hrv (
  user_id uuid not null references auth.users(id) on delete cascade,
  user_day date not null,
  rmssd_ms numeric(6,2) not null check (rmssd_ms between 1 and 300),
  bucket_count smallint not null default 1, rr_count integer not null default 2,
  sampled_tz text not null default 'Asia/Shanghai', source text not null default 'band_rr',
  collected_at timestamptz not null default now(),
  primary key (user_id, user_day)
);

create table public.oxygen_samples (
  user_id uuid not null references auth.users(id) on delete cascade,
  ts timestamptz not null, spo2 smallint not null check (spo2 between 50 and 100),
  sampled_tz text not null default 'Asia/Shanghai', src text not null default 'band',
  primary key (user_id, ts, src)
);

create table public.daily_results (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  user_day date not null, algo_version text, computed_at timestamptz not null default now(),
  unique (user_id, user_day)
);

create table public.reserve_daily (
  result_id uuid primary key references public.daily_results(id) on delete cascade,
  night_inputs jsonb not null default '{}'::jsonb
);

create table public.recompute_log (
  id bigserial primary key, algo_version text, reason text, rows_touched int,
  logged_at timestamptz not null default now()
);

-- Tables the erasure function names but this harness does not otherwise exercise.
create table public.screen_frames    (user_id uuid);
create table public.ai_turns         (user_id uuid);
create table public.analytics_events (user_id uuid);
create table public.call_changes     (user_id uuid);
create table public.meals            (user_id uuid);
create table public.weigh_ins        (user_id uuid);
create table public.body_composition (user_id uuid);
create table public.response_samples (user_id uuid);
create table public.raw_samples      (user_id uuid);
create table public.reserve_samples  (user_id uuid);
create table public.sync_runs        (user_id uuid);
create table public.device_capabilities (user_id uuid);
create table public.devices          (user_id uuid);

create function nb.settle_day(p_user uuid, p_user_day date) returns void
  language sql as $$ select $$;
create function nb.refresh_night_hrv(p_user uuid, p_user_day date) returns void
  language sql as $$ select $$;

create role authenticated;
create role anon;
