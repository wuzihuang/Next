-- Recursive numeric products can carry thousands of decimal places per tick.
-- Keep every recursive calculation unchanged; limit only the returned/cache rows
-- to 24 fractional digits. Truncation preserves direct rounding at coarser
-- precisions (including integer scores and the 12-digit next-day close) without
-- promoting a value just below a half-step. Derived arithmetic has < 1e-22 input
-- error, far below the 1e-6 attribution closure tolerance; raw unrounded fields
-- intentionally no longer expose thousands of non-significant decimal digits.
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.reserve_replay_uncached(uuid,date)'::regprocedure);
 patched:=replace(def,
  'select r.t,r.value,r.in_sleep,r.d_charge,r.d_basal,r.d_active,r.d_stress',
  'select r.t,trunc(r.value,24),r.in_sleep,trunc(r.d_charge,24),trunc(r.d_basal,24),trunc(r.d_active,24),trunc(r.d_stress,24)');
 if patched=def then raise exception 'RESERVE_REPLAY_OUTPUT_ANCHOR_MISSING'; end if;
 execute patched;
end $$;
