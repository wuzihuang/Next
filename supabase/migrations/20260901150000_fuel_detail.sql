-- 09 / 10 · WHERE THE BURN GOES, and the targets the macro bars are measured against.
--
-- compute_fuel already derives all of this — the Mifflin baseline, the MET-integrated
-- active burn, the P → F → C target split — and then settle_day threw everything but
-- kcal_in and kcal_out away. The app was left drawing its own 1,900 / 145 / 195 / 60,
-- which is not this person's split: at 75.6 kg and 182 cm the carbs are 215, not 195.
-- ⚠️ Two different answers to "what is my protein target" is the fastest way to lose a
-- page whose entire job is arithmetic the user can check.

alter table public.day_fuel
  add column if not exists bmr_kcal    integer,
  add column if not exists active_kcal integer,
  add column if not exists target_in   integer,
  add column if not exists protein_g   integer,
  add column if not exists fat_g       integer,
  add column if not exists carb_g      integer;

-- The baseline and the active burn separately, because 10 lists them as separate rows and
-- their sum has to be the kcal_out printed above them.
create or replace function nb.fuel_components(p_user uuid, p_user_day date)
returns table (bmr_kcal integer, active_kcal integer, bmr_full integer)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tz text; v_lo timestamptz; v_hi timestamptz;
  v_weight numeric; v_height numeric; v_age numeric; v_sex text;
  v_bmr numeric; v_active numeric; v_elapsed numeric;
begin
  select p.timezone, p.height_cm, p.sex, extract(year from age(p.birth_date))
    into v_tz, v_height, v_sex, v_age
  from public.profiles p where p.user_id = p_user;
  if v_tz is null then return; end if;
  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);

  select w.weight_kg into v_weight from public.weigh_ins w
  where w.user_id = p_user and w.measured_at < v_lo
  order by w.measured_at desc limit 1;
  if v_weight is null or v_height is null or v_age is null then return; end if;

  v_bmr := 10 * v_weight + 6.25 * v_height - 5 * v_age
           + case when v_sex = 'male' then 5 else -161 end;

  -- ⚠️ Never OriginData.calValue: it already contains the vendor's own basal figure, and
  -- adding it to our BMR double-counts the day.
  select coalesce(sum(greatest(0, met - 1) * 1.05 * v_weight * (5.0 / 60)), 0) into v_active
  from public.raw_samples
  where user_id = p_user and ts >= v_lo and ts < v_hi and ts <= now();

  v_elapsed := least(1440, greatest(0, extract(epoch from (least(now(), v_hi) - v_lo)) / 60));

  return query select round(v_bmr * v_elapsed / 1440)::integer,
                      round(v_active)::integer,
                      round(v_bmr)::integer;
end;
$$;

-- BEFORE, so the values land in NEW rather than as a second UPDATE that would re-enter
-- this trigger, and so a day that re-settles gets fresh figures.
create or replace function nb.on_fuel_settled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_day date; v_f record; v_c record;
begin
  select dr.user_day into v_day from public.daily_results dr where dr.id = new.result_id;
  if v_day is null then return new; end if;

  select * into v_f from nb.compute_fuel(new.user_id, v_day);
  select * into v_c from nb.fuel_components(new.user_id, v_day);

  new.target_in := v_f.target_in;
  new.protein_g := v_f.protein_g;
  new.fat_g     := v_f.fat_g;
  new.carb_g    := v_f.carb_g;
  new.bmr_kcal    := v_c.bmr_kcal;
  new.active_kcal := v_c.active_kcal;
  return new;
end;
$$;

drop trigger if exists day_fuel_detail on public.day_fuel;
create trigger day_fuel_detail
before insert or update on public.day_fuel
for each row execute function nb.on_fuel_settled();

-- The whole day's baseline, not just the part that has elapsed: 10's header is an estimate
-- of where the day lands, and it cannot be recovered from a figure that has already been
-- scaled by the clock.
alter table public.day_fuel add column if not exists bmr_full_kcal integer;

create or replace function nb.on_fuel_settled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_day date; v_f record; v_c record;
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
  return new;
end;
$$;
