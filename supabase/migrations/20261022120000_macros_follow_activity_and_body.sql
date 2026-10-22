-- Macros follow today's activity and the body they feed (ADR 0033).
--
-- Until now TARGET moved with the band but the split under it did not: protein and fat were
-- a fixed g/kg of scale weight per goal (CUT 2.0 / 0.8, RECOMP 1.9 / 0.8, BULK 1.6 / 0.9),
-- and carbohydrate took whatever was left. A training day only ever grew the carbohydrate,
-- a rest day kept the full protein, and a heavy body was asked for protein and fat by the
-- kilo of its fat mass.
--
-- Now, in one pure function:
--   reference kg  scale weight, but never more than the same lean mass at a healthy body
--                 fat (male 18 %, female 28 %) from the latest band scan; unscanned, never
--                 more than BMI 25 at the profile height.
--   activity      t = 0 at ≤ 4 kcal/kg of measured active burn, 1 at ≥ 12 kcal/kg.
--   protein       per reference kg: CUT 1.8, RECOMP 1.7, BULK 1.6, plus 0.4 × t.
--   fat           the goal's share (CUT 25 %, RECOMP 27 %, BULK 30 %) of the day without its
--                 activity, never under male 0.6 / female 0.8 g per reference kg nor under
--                 20 % of TARGET. Activity energy goes to protein and carbohydrate, not fat.
--   carbohydrate  what is left, so it carries the activity; never under 100 g. In a squeezed
--                 budget fat gives way first, down to 0.5 g/kg, exactly as before.
-- TARGET is still rebuilt from the rounded split, within one 20 kcal step of the formula.

create or replace function nb.macro_split(
  p_weight_kg numeric, p_height_cm numeric, p_sex text, p_goal text,
  p_lean_kg numeric, p_active_kcal numeric, p_target numeric)
 returns table(protein_g integer, fat_g integer, carb_g integer, kcal integer,
               reference_kg numeric, activity numeric)
 language plpgsql
 immutable
 set search_path to ''
as $function$
declare
  v_ref    numeric;
  v_t      numeric;
  v_active numeric := greatest(coalesce(p_active_kcal, 0), 0);
  v_p      integer;
  v_f      integer;
  v_c      integer;
begin
  if p_weight_kg is null or p_target is null then return; end if;

  -- Protein and fat are asked for by the kilo of the body that uses them, not of its fat.
  v_ref := p_weight_kg;
  if p_lean_kg is not null and p_lean_kg > 0 then
    v_ref := least(v_ref, p_lean_kg / (1 - case when p_sex = 'female' then 0.28 else 0.18 end));
  elsif p_height_cm is not null and p_height_cm > 0 then
    v_ref := least(v_ref, 25 * (p_height_cm / 100) ^ 2);
  end if;

  -- Scale weight, not reference: the burn is the whole body moving.
  v_t := least(greatest((v_active / p_weight_kg - 4) / 8, 0), 1);

  v_p := round(v_ref * (case p_goal when 'CUT' then 1.8 when 'BULK' then 1.6 else 1.7 end
                        + 0.4 * v_t) / 5) * 5;
  v_f := round(greatest(
           v_ref * case when p_sex = 'female' then 0.8 else 0.6 end,
           greatest(p_target - v_active, 0)
             * case p_goal when 'CUT' then 0.25 when 'BULK' then 0.30 else 0.27 end / 9,
           0.20 * p_target / 9
         ) / 5) * 5;
  v_c := round((p_target - 4 * v_p - 9 * v_f) / 4 / 5) * 5;
  -- The 100 g carbohydrate floor is real, but it is not extra calories. Fat gives way to
  -- it first, down to 0.5 g/kg and rounded down so it never overshoots, and carbohydrate
  -- then takes what is left: a budget pinned to the floor stays pinned to it.
  if v_c < 100 then
    v_f := greatest(round((v_ref * 0.5) / 5) * 5,
                    least(v_f, floor((p_target - 4 * v_p - 400) / 9 / 5) * 5));
    v_c := greatest(100, round((p_target - 4 * v_p - 9 * v_f) / 4 / 5) * 5);
  end if;

  return query select v_p, v_f, v_c, 4 * v_p + 9 * v_f + 4 * v_c,
    round(v_ref, 1), round(v_t, 2);
end;
$function$;

revoke all on function nb.macro_split(numeric,numeric,text,text,numeric,numeric,numeric)
from public, anon, authenticated;

-- compute_fuel hands its split to macro_split, with the latest scan's lean mass and height.
do $migration$
declare definition text; patched text; head int; tail int;
  old_split constant text := '    v_p := round((v_weight * case v_goal';
  old_end   constant text := '    v_target := 4 * v_p + 9 * v_f + 4 * v_c;';
begin
  definition := pg_get_functiondef('nb.compute_fuel(uuid,date)'::regprocedure);
  head := position(old_split in definition);
  tail := position(old_end in definition);
  if head = 0 or tail = 0 or tail < head then raise exception 'MACRO_SPLIT_ANCHOR_MISSING'; end if;
  patched := substr(definition, 1, head - 1)
    || '    select s.protein_g, s.fat_g, s.carb_g, s.kcal into v_p, v_f, v_c, v_target
    from nb.macro_split(v_weight,
      (select p.height_cm from nb.calculation_profile(p_user, p_user_day) p),
      v_sex, v_goal,
      (select b.lean_body_mass_kg from public.body_composition b
        where b.user_id = p_user and b.measurement_source = ''device_bia''
          and b.lean_body_mass_kg > 0
          and b.measured_at <= nb.calculation_instant(p_user, p_user_day)
        order by b.measured_at desc limit 1),
      v_active, v_target) s;'
    || substr(definition, tail + length(old_end));
  -- The comment above the old block now describes macro_split, not this function.
  patched := replace(patched,
    '  -- Weight is still needed: the macro split is per kilo.',
    '  -- Weight is still needed: the macro split is per kilo (nb.macro_split).');
  execute patched;
end;
$migration$;

-- Every published split is stale: protein and fat move for everyone.
do $migration$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.calculation_version()'::regprocedure);
  patched := replace(definition, 'fuel-2.0', 'fuel-2.1');
  if patched = definition then raise exception 'FUEL_VERSION_PATCH_MISSING'; end if;
  execute patched;
end;
$migration$;

select nb.invalidate_calculation(user_id, min(user_day))
from public.daily_results group by user_id;
