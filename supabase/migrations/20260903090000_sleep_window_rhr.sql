-- The night's own window on sleep_nights, and nb.night_rhr reads inside it.
--
-- raw_samples.sleep_states is null on every row this SDK produces (the original-data
-- dictionary carries no sleep key), so the old `coalesce(sleep_states, 0) <> 0` filter
-- matched nothing and night_rhr was null for every user day. The band's accurate sleep
-- record says when the night began and ended; the app now sends both, and the 5th
-- percentile is taken between them. Rows without a window keep the old rule.

alter table public.sleep_nights
  add column if not exists sleep_start timestamptz,
  add column if not exists wake_at     timestamptz;

comment on column public.sleep_nights.sleep_start is 'Band''s own 入睡时间 for the night that ended on user_day.';
comment on column public.sleep_nights.wake_at     is 'Band''s own 起床时间 on the morning of user_day.';

create or replace function nb.night_rhr(p_user uuid, p_user_day date, p_tz text)
returns numeric
language sql
stable
set search_path = ''
as $$
  with night as (
    select s.sleep_start, s.wake_at
    from public.sleep_nights s
    where s.user_id = p_user and s.user_day = p_user_day
  ),
  bounds as (
    select b.starts_at, b.ends_at from nb.user_day_bounds(p_user_day, p_tz) b
  )
  select percentile_cont(0.05) within group (order by rs.heart)
  from public.raw_samples rs
  cross join bounds b
  left join night n on true
  where rs.user_id = p_user
    and rs.heart is not null
    and case
          when n.sleep_start is not null and n.wake_at is not null
            then rs.ts >= n.sleep_start and rs.ts < n.wake_at
          else rs.ts >= b.starts_at and rs.ts < b.ends_at
               and coalesce(rs.sleep_states, 0) <> 0
        end;
$$;
