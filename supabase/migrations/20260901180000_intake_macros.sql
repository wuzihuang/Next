-- 12 · PROTEIN INTAKE is one of the four signals behind THE CALL, and it is a seven-day
-- figure in g/kg — not something a single day's meal list can answer. The day's own intake
-- macros belong next to its kcal so the app can average them over the window without
-- pulling six months of meal rows down the wire.
alter table public.day_fuel
  add column if not exists protein_in_g smallint,
  add column if not exists carb_in_g    smallint,
  add column if not exists fat_in_g     smallint,
  add column if not exists weight_kg    numeric(5, 2);

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
  where m.user_id = new.user_id and m.user_day = v_day and m.deleted_at is null;

  -- The weight the day's targets were computed against — the most recent entry strictly
  -- before this day's 04:00, the same one compute_fuel used.
  select p.timezone into v_tz from public.profiles p where p.user_id = new.user_id;
  select starts_at into v_lo from nb.user_day_bounds(v_day, v_tz);
  select w.weight_kg into new.weight_kg from public.weigh_ins w
  where w.user_id = new.user_id and w.measured_at < v_lo
  order by w.measured_at desc limit 1;

  return new;
end;
$$;
