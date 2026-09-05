-- Open-day Daily Direction.
--
-- compute_fuel left daily_direction null until the next 04:00. The heat map treated
-- null as GREY_NOTHING, so a day with two meal slots, band coverage, and a live
-- balance stayed an empty square until tomorrow. F0 D05: the cell colours from the
-- first sealed day; F2's close rule freezes the official DAY_CLOSED event, it does
-- not blank the map. Colour now uses the same elapsed BALANCE the fuel page shows.

create or replace function nb.compute_fuel(p_user uuid, p_user_day date)
returns table (
  intake_state text,
  kcal_in      integer,
  kcal_out     integer,
  balance      integer,
  target_in    integer,
  protein_g    integer,
  fat_g        integer,
  carb_g       integer,
  direction    text,
  slot_states  jsonb
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz       text;
  v_lo       timestamptz;
  v_hi       timestamptz;
  v_weight   numeric;
  v_height   numeric;
  v_age      numeric;
  v_sex      text;
  v_goal     text;
  v_bmr      numeric;
  v_active   numeric;
  v_elapsed  numeric;
  v_in       integer;
  v_slots    integer;
  v_coverage numeric;
  v_state    text;
  v_p        integer;
  v_f        integer;
  v_c        integer;
  v_target   numeric;
  v_out      integer;
  v_balance  integer;
begin
  select p.timezone, p.height_cm, p.sex, p.goal,
         extract(year from age(p.birth_date))
    into v_tz, v_height, v_sex, v_goal, v_age
  from public.profiles p where p.user_id = p_user;
  if v_tz is null then return; end if;

  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);

  select w.weight_kg into v_weight
  from public.weigh_ins w
  where w.user_id = p_user and w.measured_at < v_lo
  order by w.measured_at desc limit 1;

  if v_weight is null or v_height is null or v_age is null then
    v_bmr := null;
  else
    v_bmr := 10 * v_weight + 6.25 * v_height - 5 * v_age
             + case when v_sex = 'male' then 5 else -161 end;
  end if;

  select coalesce(sum(greatest(0, met - 1) * 1.05 * coalesce(v_weight, 0) * (5.0 / 60)), 0)
    into v_active
  from public.raw_samples
  where user_id = p_user and ts >= v_lo and ts < v_hi;

  select count(*)::numeric / 288 into v_coverage
  from public.raw_samples
  where user_id = p_user and ts >= v_lo and ts < v_hi;

  v_elapsed := least(1440, greatest(0,
                 extract(epoch from (least(now(), v_hi) - v_lo)) / 60));

  select sum(m.kcal), count(distinct m.slot)
    into v_in, v_slots
  from public.meals m
  where m.user_id = p_user and m.user_day = p_user_day and m.deleted_at is null
    and m.model_version is distinct from 'seed';

  v_state := case
    when v_slots is null or v_slots = 0 then 'UNLOGGED'
    when v_slots >= 4 then 'CONFIRMED'
    else 'PARTIAL'
  end;

  if v_weight is not null and v_bmr is not null then
    v_target := v_bmr * 1.35 + case v_goal
                  when 'CUT' then -600 when 'BULK' then 300 else -380 end;
    v_p := round((v_weight * case v_goal
             when 'CUT' then 2.0 when 'BULK' then 1.6 else 1.9 end) / 5) * 5;
    v_f := round((v_weight * case v_goal
             when 'BULK' then 0.9 else 0.8 end) / 5) * 5;
    v_c := greatest(100, round((v_target - 4 * v_p - 9 * v_f) / 4 / 5) * 5);
    v_target := 4 * v_p + 9 * v_f + 4 * v_c;
  end if;

  if v_bmr is not null then
    v_out := round(v_bmr * v_elapsed / 1440 + v_active)::integer;
  end if;
  if v_state <> 'UNLOGGED' and v_bmr is not null then
    v_balance := coalesce(v_in, 0) - v_out;
  end if;

  return query select
    v_state,
    case when v_state = 'UNLOGGED' then null else coalesce(v_in, 0) end,
    v_out,
    v_balance,
    round(v_target)::integer, v_p, v_f, v_c,
    case
      when v_state = 'UNLOGGED' then 'GREY_NOTHING'
      when v_state = 'PARTIAL' and v_slots < 2 then 'GREY_NOTHING'
      when coalesce(v_coverage, 0) < 0.5 then 'GREY_NO_BURN'
      when v_bmr is null then 'GREY_NO_BURN'
      when v_balance <= -150 then 'DEFICIT'
      when v_balance >= 150 then 'SURPLUS'
      else 'LEVEL'
    end,
    coalesce((
      select jsonb_object_agg(sl.name, coalesce(st.state, 'OPEN'))
      from unnest(array['BREAKFAST', 'LUNCH', 'DINNER', 'SNACK']) as sl(name)
      left join lateral (
        select 'CONFIRMED'::text as state
        from public.meals mm
        where mm.user_id = p_user and mm.user_day = p_user_day
          and mm.slot = sl.name and mm.deleted_at is null
          and mm.model_version is distinct from 'seed'
        limit 1
      ) st on true
    ), '{}'::jsonb);
end;
$$;

-- Same-version bug: the open day was stored as a null direction. Recompute the
-- window the band still holds so today's cell is the live balance, not an empty square.
do $$
declare
  profile record;
  v_today date;
begin
  for profile in
    select p.user_id, p.timezone
    from public.profiles p
    where p.timezone is not null
  loop
    v_today := nb.user_day_of(now(), profile.timezone);
    perform nb.recompute_range(
      profile.user_id,
      v_today - 14,
      v_today,
      'open-day daily_direction'
    );
  end loop;
end;
$$;
