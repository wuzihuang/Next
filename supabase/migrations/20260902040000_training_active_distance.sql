-- 补屏 B · NO TARGET rule 10 · 「Active minutes 的定义落死：5 分钟原始点里 met ≥ 3 的点数 × 5。它是
-- 无量纲比值，没有体重照样[真]」— and distance is the band's own count. Both are true without a
-- weight, which is the whole point of that screen, so they are settled numbers, not client maths.
--
-- Kept out of compute_training on purpose: that function is 120 lines of load model and this is
-- two sums. A BEFORE trigger fills them from raw_samples for the row's own user day.
alter table public.daily_training
  add column if not exists active_minutes smallint,
  add column if not exists distance_m     integer;

create or replace function nb.fill_training_extras()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_day date; v_tz text; v_lo timestamptz; v_hi timestamptz;
begin
  select d.user_day, p.timezone into v_day, v_tz
  from public.daily_results d join public.profiles p on p.user_id = d.user_id
  where d.id = new.result_id;
  if v_tz is null then return new; end if;
  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(v_day, v_tz);

  select (count(*) filter (where met >= 3))::smallint * 5, sum(dis)::integer
    into new.active_minutes, new.distance_m
  from public.raw_samples
  where user_id = new.user_id and ts >= v_lo and ts < v_hi;
  -- No points at all → both null. Silence, not a zero.
  if not exists (select 1 from public.raw_samples where user_id = new.user_id and ts >= v_lo and ts < v_hi) then
    new.active_minutes := null; new.distance_m := null;
  end if;
  return new;
end;
$$;

drop trigger if exists daily_training_extras on public.daily_training;
create trigger daily_training_extras
  before insert or update on public.daily_training
  for each row execute function nb.fill_training_extras();
