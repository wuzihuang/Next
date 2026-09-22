-- #32: a saved weigh-in is an input to the next settlement, including today's.
-- Keep the calculation instant and day-end bounds, so later measurements never
-- reach backwards into history. The resting source (including a body scan) and
-- all calorie formulas remain unchanged.
do $migration$
declare name text; definition text; patched text;
begin
  foreach name in array array['resting_kcal', 'fuel_components', 'compute_fuel'] loop
    definition := pg_get_functiondef(format('nb.%I(uuid,date)',name)::regprocedure);
    patched := regexp_replace(definition,
      'order by \(w\.measured_at\s*<\s*v_lo\) desc,\s*case when w\.measured_at\s*<\s*v_lo then w\.measured_at end desc,\s*w\.measured_at asc',
      'order by w.measured_at desc, w.id desc');
    if patched = definition then
      raise exception 'LATEST_PROFILE_WEIGHT_ANCHOR_MISSING: %',name;
    end if;
    patched := replace(patched,
      '-- Same weight the rest of the ledger uses: the latest before the day, else the first' || chr(10) || '  -- during it.',
      '-- Same weight as the rest of the ledger: latest known at the calculation instant.');
    execute patched;
  end loop;
end;
$migration$;

-- The published input weight must describe the same calculation as its numbers.
do $migration$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.on_fuel_settled()'::regprocedure);
  patched := replace(definition,
    'where w.user_id = new.user_id and w.measured_at < v_lo',
    'where w.user_id = new.user_id and w.measured_at <= nb.calculation_instant(new.user_id,v_day)
    and w.measured_at < (select ends_at from nb.user_day_bounds(v_day,v_tz))');
  if patched = definition then raise exception 'PUBLISHED_WEIGHT_ANCHOR_MISSING'; end if;
  patched := replace(patched,
    'from public.profiles p where p.user_id = new.user_id',
    'from nb.calculation_profile(new.user_id,v_day) p');
  execute patched;
end;
$migration$;

-- A profile save can arrive inside the current minute. The minute-rounded clock
-- must not publish an old weight and then mark that dirty input as consumed.
do $migration$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('nb.recompute_range(uuid,date,date,text)'::regprocedure);
  patched := replace(definition,
    'tick:=least(hi,date_bin(interval ''1 minute'',now(),''2000-01-01''::timestamptz));',
    'tick:=least(hi,date_bin(interval ''1 minute'',now(),''2000-01-01''::timestamptz));
   tick:=greatest(tick,coalesce((select max(i.measured_at) from public.weigh_ins i
     where i.user_id=p_user and i.measured_at<=now() and i.measured_at<hi),tick));');
  if patched = definition then raise exception 'PROFILE_WEIGHT_SETTLEMENT_CLOCK_ANCHOR_MISSING'; end if;
  execute patched;
end;
$migration$;
