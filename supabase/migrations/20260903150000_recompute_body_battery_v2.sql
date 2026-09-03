-- Body Battery v2 correction.
--
-- Deploying the new replay alone leaves existing bb-1.4 zeroes as the previous-day anchor.
-- Start a v2 chain only from another v2 result; the first affected day gets the documented
-- cold-start anchor, then the ordered recompute carries each corrected close into the next day.

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
      join public.profiles p on p.user_id = dr.user_id
      join lateral nb.user_day_bounds(dr.user_day, p.timezone) bounds on true
      where dr.user_id = p_user
        and dr.user_day = p_user_day - 1
        and dr.algo_version like '%bb-2.0%'
        and exists (
          select 1 from public.reserve_samples rs
          where rs.user_id = p_user
            and rs.ts >= bounds.starts_at
            and rs.ts < bounds.ends_at
        )
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

-- settle_day writes daily_results before its detail rows. When computation has no wrist/sleep
-- evidence, remove any detail and curve left by an older algorithm instead of relabelling those
-- artifacts as bb-2.0. This also protects every later app/cron historical recompute.
create or replace function nb.clear_unknown_reserve_artifacts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz text;
  v_lo timestamptz;
  v_hi timestamptz;
begin
  delete from public.reserve_daily rd where rd.result_id = new.id;

  select p.timezone into v_tz
  from public.profiles p
  where p.user_id = new.user_id;

  if v_tz is not null then
    select bounds.starts_at, bounds.ends_at into v_lo, v_hi
    from nb.user_day_bounds(new.user_day, v_tz) bounds;

    delete from public.reserve_samples rs
    where rs.user_id = new.user_id
      and rs.ts >= v_lo
      and rs.ts < v_hi;
  end if;

  return new;
end;
$$;

drop trigger if exists clear_unknown_reserve_artifacts on public.daily_results;
create trigger clear_unknown_reserve_artifacts
after insert or update on public.daily_results
for each row
when (new.reserve_score is null)
execute function nb.clear_unknown_reserve_artifacts();

revoke execute on function nb.clear_unknown_reserve_artifacts() from public, anon, authenticated;

-- This is an intentional bug-fix recompute, recorded with its own reason. Only today is
-- recomputed during deployment to keep the migration transaction short. Normal app/cron sync
-- subsequently rebuilds older days, while current Body Battery is corrected immediately.
do $$
declare
  profile record;
  v_today date;
  v_lo timestamptz;
  v_hi timestamptz;
begin
  for profile in
    select p.user_id, p.timezone
    from public.profiles p
    where p.timezone is not null
      and (
        exists (
          select 1 from public.raw_samples r
          where r.user_id = p.user_id and r.ts >= now() - interval '16 days'
        )
        or exists (
          select 1 from public.sleep_nights s
          where s.user_id = p.user_id and s.user_day >= current_date - 16
        )
      )
  loop
    v_today := nb.user_day_of(now(), profile.timezone);
    select bounds.starts_at, bounds.ends_at into v_lo, v_hi
    from nb.user_day_bounds(v_today, profile.timezone) bounds;

    -- Remove the stale detail and curve first. If today has evidence settle_day recreates both;
    -- otherwise daily_results.reserve_score becomes null instead of preserving a fake zero.
    delete from public.reserve_daily rd
    using public.daily_results dr
    where rd.result_id = dr.id
      and dr.user_id = profile.user_id
      and dr.user_day = v_today;

    delete from public.reserve_samples rs
    where rs.user_id = profile.user_id
      and rs.ts >= v_lo
      and rs.ts < v_hi;

    perform nb.recompute_range(
      profile.user_id,
      v_today,
      v_today,
      'bb-2.0 migration'
    );
  end loop;
end;
$$;
