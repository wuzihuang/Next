-- F3 §05 · the home screen reads daily_results and nothing else. Until now a row for today
-- only appeared when the hourly cron came round (nb-settle, minute 07), so a band synced at
-- 10:12 was on the server and not on the screen until 11:07 — on a phone that looked exactly
-- like the numbers being made up. settle_now() lets the app ask for its own day, and only its
-- own days, the moment it has stored a page. The computation is still nb.settle_day, the same
-- function the cron calls; nothing is computed on the phone (F2 rule 02).

create or replace function public.settle_now(p_days integer default 1)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := (select auth.uid());
  v_tz    text;
  v_today date;
  v_back  integer;
begin
  if v_user is null then
    raise exception 'UNAUTHENTICATED' using errcode = '28000';
  end if;
  select timezone into v_tz from public.profiles where user_id = v_user;
  -- No profile yet → nothing to compute against; the caller gets 0, not an error.
  if v_tz is null then return 0; end if;
  v_today := nb.user_day_of(now(), v_tz);
  -- Today and up to fourteen days back: a first sync pulls what the band still holds
  -- (watchDataDayNumber, seven on a HOOP), and the settle has to cover the same window.
  v_back := least(greatest(coalesce(p_days, 1), 0), 14);
  return nb.recompute_range(v_user, v_today - v_back, v_today, 'app');
end;
$$;

revoke execute on function public.settle_now(integer) from public, anon;
grant execute on function public.settle_now(integer) to authenticated;

-- ---------------------------------------------------------------- hr_rest · a first week

-- HR_REST stays frozen for the week: the previous ISO week's nights, as before. But a first
-- week has no previous week, and a null here meant no zones, no load and no ring for up to
-- thirteen days on a real band. With nothing to freeze, the seven user days ending at the day
-- itself stand in; the moment a full previous week exists the frozen value takes over again.
-- ⚠️ heart > 0: the band reports 0 for a tick with nothing on the wrist. A zero is not a
-- resting heart rate, and in the lowest decile it would have been the whole answer.
create or replace function nb.hr_rest(p_user uuid, p_user_day date, p_tz text)
returns numeric
language sql
stable
set search_path = ''
as $$
  with week_start as (
    select (p_user_day - ((extract(isodow from p_user_day)::int) - 1))::date as d
  ),
  frozen as (
    select (select starts_at from nb.user_day_bounds((select d from week_start) - 7, p_tz)) as lo,
           (select ends_at   from nb.user_day_bounds((select d from week_start) - 1, p_tz)) as hi
  ),
  recent as (
    select (select starts_at from nb.user_day_bounds(p_user_day - 6, p_tz)) as lo,
           (select ends_at   from nb.user_day_bounds(p_user_day, p_tz)) as hi
  ),
  frozen_nightly as (
    select heart
    from public.raw_samples, frozen
    where user_id = p_user
      and ts >= frozen.lo and ts < frozen.hi
      and heart is not null and heart > 0
      and extract(hour from ts at time zone p_tz) between 0 and 6
  ),
  recent_nightly as (
    select heart
    from public.raw_samples, recent
    where user_id = p_user
      and ts >= recent.lo and ts < recent.hi
      and heart is not null and heart > 0
      and extract(hour from ts at time zone p_tz) between 0 and 6
  ),
  nightly as (
    select heart from frozen_nightly
    union all
    select heart from recent_nightly where not exists (select 1 from frozen_nightly)
  ),
  lowest as (
    select heart from nightly
    order by heart
    limit greatest(1, (select count(*) / 10 from nightly))
  )
  select percentile_cont(0.5) within group (order by heart) from lowest;
$$;
