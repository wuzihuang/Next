-- The band's BIA returns more than fat, lean and BMR. These four are the ones the home
-- body page shows. Nullable: rows written before this migration, and scans where the
-- firmware sent an empty string, stay empty rather than becoming a number.
alter table public.body_composition
  add column muscle_mass_kg numeric(5, 2),
  add column body_water_pct numeric(4, 2),
  add column bone_mass_kg   numeric(4, 2),
  add column protein_pct    numeric(4, 2);
