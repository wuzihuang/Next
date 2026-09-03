-- Dev seed meals (model_version = 'seed') must never enter fuel state or AI reads.
-- Same marker as supabase/seed/cleanup-dev-samples.sql.

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

  return query select
    v_state,
    case when v_state = 'UNLOGGED' then null else coalesce(v_in, 0) end,
    case when v_bmr is null then null
         else round(v_bmr * v_elapsed / 1440 + v_active)::integer end,
    case when v_state = 'UNLOGGED' or v_bmr is null then null
         else (coalesce(v_in, 0) - round(v_bmr * v_elapsed / 1440 + v_active))::integer end,
    round(v_target)::integer, v_p, v_f, v_c,
    case
      when now() < v_hi then null
      when v_state = 'UNLOGGED' then 'GREY_NOTHING'
      when v_state = 'PARTIAL' and v_slots < 2 then 'GREY_NOTHING'
      when coalesce(v_coverage, 0) < 0.5 then 'GREY_NO_BURN'
      when v_bmr is null then 'GREY_NO_BURN'
      when (coalesce(v_in, 0) - round(v_bmr + v_active)) <= -150 then 'DEFICIT'
      when (coalesce(v_in, 0) - round(v_bmr + v_active)) >= 150 then 'SURPLUS'
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

create or replace function nb.on_fuel_settled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_day date; v_f record; v_c record; v_tz text; v_lo timestamptz;
begin
  select dr.user_day into v_day from public.daily_results dr where dr.id = new.result_id;
  if v_day is null then return new; end if;

  select * into v_f from nb.compute_fuel(new.user_id, v_day);
  select * into v_c from nb.fuel_components(new.user_id, v_day);

  new.target_in := v_f.target_in;
  new.protein_g := v_f.protein_g;
  new.fat_g     := v_f.fat_g;
  new.carb_g    := v_f.carb_g;
  new.bmr_kcal      := v_c.bmr_kcal;
  new.active_kcal   := v_c.active_kcal;
  new.bmr_full_kcal := v_c.bmr_full;

  select sum(m.protein_g), sum(m.carb_g), sum(m.fat_g)
    into new.protein_in_g, new.carb_in_g, new.fat_in_g
  from public.meals m
  where m.user_id = new.user_id and m.user_day = v_day and m.deleted_at is null
    and m.model_version is distinct from 'seed';

  select p.timezone into v_tz from public.profiles p where p.user_id = new.user_id;
  select starts_at into v_lo from nb.user_day_bounds(v_day, v_tz);
  select w.weight_kg into new.weight_kg from public.weigh_ins w
  where w.user_id = new.user_id and w.measured_at < v_lo
  order by w.measured_at desc limit 1;

  return new;
end;
$$;
