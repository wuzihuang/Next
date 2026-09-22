-- Preserve nutrient fractions in each food record, including offline replay and favorites.
-- Display precision is one decimal; stored source values are not rounded on insertion.
-- Day-level energy/target summaries keep their established integer contract.
alter table public.meals
  alter column kcal type numeric using kcal::numeric,
  alter column protein_g type numeric using protein_g::numeric,
  alter column carb_g type numeric using carb_g::numeric,
  alter column fat_g type numeric using fat_g::numeric,
  alter column fiber_g type numeric using fiber_g::numeric,
  alter column sugar_g type numeric using sugar_g::numeric,
  alter column sodium_mg type numeric using sodium_mg::numeric;

-- Patch only number validation/casts in the installed writer, retaining its current
-- consent, owner, append-only and idempotency behavior (including intervening fixes).
do $$
declare definition text; patched text; nutrient text; anchor text;
begin
  definition := pg_get_functiondef('public.apply_meal_operation(uuid,text,uuid,jsonb)'::regprocedure);
  patched := replace(definition, '''^[0-9]+$''', '''^[0-9]+([.][0-9]+)?$''');
  if patched = definition then raise exception 'MEAL_DECIMAL_VALIDATION_ANCHOR_MISSING'; end if;
  foreach nutrient in array array['kcal','protein_g','carb_g','fat_g','fiber_g','sugar_g','sodium_mg'] loop
    anchor := '(v_row->>''' || nutrient || ''')::integer';
    if strpos(patched, anchor) = 0 then raise exception 'MEAL_DECIMAL_CAST_ANCHOR_MISSING: %', nutrient; end if;
    patched := replace(patched, anchor, '(v_row->>''' || nutrient || ''')::numeric');
  end loop;
  execute patched;
end $$;

-- Integer columns could never hold NaN/Infinity; numeric must retain that boundary.
alter table public.meals add constraint meals_nutrients_finite check (
  (kcal is null or kcal < 'Infinity'::numeric) and
  (protein_g is null or protein_g < 'Infinity'::numeric) and
  (carb_g is null or carb_g < 'Infinity'::numeric) and
  (fat_g is null or fat_g < 'Infinity'::numeric) and
  (fiber_g is null or fiber_g < 'Infinity'::numeric) and
  (sugar_g is null or sugar_g < 'Infinity'::numeric) and
  (sodium_mg is null or sodium_mg < 'Infinity'::numeric)
);
