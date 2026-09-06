create schema if not exists auth;
create schema if not exists nb;
create extension if not exists pgcrypto;

do $roles$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end;
$roles$;

create table auth.users (id uuid primary key);

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  timezone text not null default 'UTC',
  deletion_requested_at timestamptz
);

create table public.raw_samples (
  user_id uuid not null references auth.users(id) on delete cascade,
  ts timestamptz not null,
  sampled_tz text not null default 'UTC',
  heart smallint,
  step integer,
  met numeric(4, 2),
  stress smallint,
  hrv numeric(5, 1),
  src text not null default 'band',
  primary key (user_id, ts, src)
);

create table public.daily_results (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  user_day date not null,
  algo_version text not null default 'test',
  computed_at timestamptz not null default now(),
  unique (user_id, user_day)
);

create or replace function nb.user_day_bounds(p_user_day date, p_tz text)
returns table (starts_at timestamptz, ends_at timestamptz)
language sql
immutable
set search_path = ''
as $$
  select ((p_user_day + time '04:00') at time zone p_tz),
         ((p_user_day + 1 + time '04:00') at time zone p_tz);
$$;
