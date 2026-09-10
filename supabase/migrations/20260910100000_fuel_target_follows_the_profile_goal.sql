-- #26 · the day's intake target belongs to the profile goal, and there is exactly one of it.
--
-- The goal chosen at onboarding — CUT / RECOMP / BULK — is the whole of what the user
-- agreed to. TARGET_IN is that goal applied to the day's own burn basis, `E_OUT_FULL + Δ`,
-- and every surface that prints an intake number reads that one column. What the product
-- decided on this issue is one number: the CUT offset is −500, not −600.
--
-- −600 was a textbook figure, not this product's. It is a kilo a week on paper, which is
-- steeper than what a wrist can vouch for on a burn basis that is itself a fortnight's
-- median; and on the accounts where the basis sits near the basal figure the budget was
-- being pulled down to the `greatest(v_target, v_bmr)` floor, so the deficit the user was
-- promised silently became whatever the floor allowed. −500 keeps the deficit inside what
-- the basis can carry. RECOMP (−380) and BULK (+300) are unchanged.
--
-- ⚠️ TARGET_IN is rebuilt from the rounded macro split, so the served deficit lands within
-- one 20 kcal step of `basis − 500` — the same rounding the carbohydrate floor works in
-- (20260908160000). A body whose protein and fat allowance cannot fit inside the budget
-- still lands above it, and that overshoot is visible in FAT_G rather than hidden here.
--
-- ⚠️ Nothing else derives an intake number. The phone reads `day_fuel.target_in`; the AI
-- reads the same row through `find day` and the fuel sources. A second formula anywhere —
-- client-side, or spoken by the model out of a BMR multiplier of its own — is the bug this
-- issue is about, and it is a prompt rule (functions/_shared/prompt.ts, coach.ts), not a
-- second implementation.

do $do$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.compute_fuel(uuid,date)'::regprocedure);
  -- Re-runnable: a later migration that rewrites this body whole reinstates −600, and
  -- this file has to be able to patch that body again.
  if position('when ''CUT'' then -600' in definition) = 0 then return; end if;
  patched := replace(definition, 'when ''CUT'' then -600', 'when ''CUT'' then -500');
  if patched = definition then raise exception 'FUEL_CUT_OFFSET_ANCHOR_MISSING'; end if;
  execute patched;
end $do$;

-- The budget changed for every stored day, so every published day is stale. Patch the
-- version string rather than restating it: other calibrations move their own component.
do $do$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.calculation_version()'::regprocedure);
  patched := replace(definition, 'fuel-1.1', 'fuel-1.2');
  if patched = definition then raise exception 'FUEL_VERSION_PATCH_MISSING'; end if;
  execute patched;
end $do$;

select nb.invalidate_calculation(user_id, min(user_day))
from public.daily_results group by user_id;
