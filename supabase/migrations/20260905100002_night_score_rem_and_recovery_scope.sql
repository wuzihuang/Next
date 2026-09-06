-- ⚠️ Two corrections to 20260905100000 / 20260905100001, both found in review.
--
-- 1 · A night whose stage line carries no REM runs was scored 0 % REM rather than "not
--     measured". `nb.sleep_line_minutes` returns coalesce(sum(...), 0), so a line filed by
--     accurateType 0 firmware — deep and light only, which this band does on ordinary
--     nights between accurateType 1 ones — produced v_rem_pct = 0.0 and scored zero on a
--     window whose floor is 0 %. That costs the architecture group 40 % of its weight and
--     the night about ten points, for something the band never claimed. ADR 0008's own rule
--     is that a missing input renormalises inside its group; this makes REM obey it.
--
-- 2 · 20260905100001 restored nb.recompute_range from 20260904085910 verbatim, which
--     dropped the archive-recovery patch 20260904091133 had applied on top of it — the same
--     mistake, one layer up. Without it public.resume_calculation inserts a row into
--     nb.calculation_recovery_scope that the function no longer reads: a user whose
--     dirty_from is older than 385 days can never replay (rows_touched 0, pending true,
--     forever), and a partial batch clears dirty_from wholesale, marking the days it never
--     replayed clean. Both patches below are anchored string replacements rather than fresh
--     copies, precisely so the next edit to either function does not repeat this.

-- ---------------------------------------------------------------- 1 · REM is absent, not zero

do $$
declare f text; patched text;
begin
  f := pg_get_functiondef('nb.night_score_parts(uuid,date)'::regprocedure);
  if position('if v_rem_min = 0 then v_rem_min := null; end if;' in f) > 0 then return; end if;
  patched := replace(f,
    'v_rem_pct := 100.0 * v_rem_min / v_night.total_minutes;',
    '-- A line with no stage-2 runs is a night the firmware filed without REM staging'
    || chr(10) || '    -- (accurateType 0), not a night that had no REM. It is an absent input.'
    || chr(10) || '    if v_rem_min = 0 then v_rem_min := null; end if;'
    || chr(10) || '    v_rem_pct := case when v_rem_min is null then null'
    || chr(10) || '                      else 100.0 * v_rem_min / v_night.total_minutes end;');
  if patched = f then raise exception 'NIGHT_SCORE_REM_ANCHOR_MISSING'; end if;
  execute patched;
end $$;

-- The scoring changed, so the version changes and every night on record is recomputed.
-- A stored score whose algorithm no longer exists is the thing ADR 0008 forbids: two
-- windows over the same night disagreeing because one of them was settled last week.
do $$
declare f text; patched text;
begin
  f := pg_get_functiondef('nb.refresh_night_score(uuid,date)'::regprocedure);
  patched := replace(f, '''sleep-v1''', '''sleep-v1.1''');
  if patched = f then raise exception 'NIGHT_SCORE_VERSION_ANCHOR_MISSING'; end if;
  execute patched;
end $$;

do $$
declare r record;
begin
  for r in select sn.user_id, sn.user_day from public.sleep_nights sn
           where coalesce(sn.total_minutes, 0) > 0
           order by sn.user_id, sn.user_day loop
    perform nb.refresh_night_score(r.user_id, r.user_day);
  end loop;
end $$;

-- ---------------------------------------------------------------- 2 · recovery scope, again

-- Verbatim the five replacements from 20260904091133, re-applied to whatever the current
-- definition is. It is a no-op when the patch is already in place, so it is safe to apply
-- on a database that never lost it.
do $$
declare f text; p regprocedure := to_regprocedure('nb.recompute_range(uuid,date,date,text)');
begin
  if p is null then raise notice 'recompute_range absent, skipping recovery-scope patch'; return; end if;
  f := pg_get_functiondef(p);
  -- Already patched.
  if position('nb.calculation_recovery_scope' in f) > 0 then return; end if;
  -- Not the reproducible-revisions body at all — the scoring fixture stands this feature's
  -- tables up alone and keeps 20260905100000's plain copy, which has no recovery to scope.
  -- Every real database has carried the revisions body since 20260904085910.
  if position('nb.calculation_work' in f) = 0 then
    raise notice 'recompute_range is not the revisions body, skipping recovery-scope patch';
    return;
  end if;
  if position('if w.dirty_from<today-385 then return 0; end if;' in f) = 0 then
    raise exception 'CALCULATION_RECOVERY_PATCH_ANCHOR_MISSING';
  end if;
  f := replace(f, 'previous_asof text; previous_day text;',
   'previous_asof text; previous_day text; recovery_to date; last_day date;');
  f := replace(f, 'if w.dirty_from<today-385 then return 0; end if;',
   'select through_day into recovery_to from nb.calculation_recovery_scope where transaction_id=txid_current() and user_id=p_user;' || chr(10) ||
   ' if w.dirty_from<today-385 and recovery_to is null then return 0; end if;');
  f := replace(f, 'lo:=greatest(lo,today-385);',
   'if recovery_to is null then lo:=greatest(lo,today-385); end if;');
  f := replace(f, 'least(greatest(p_to,case when w.dirty_from is not null then today else p_to end),today)',
   'least(greatest(p_to,case when w.dirty_from is not null then today else p_to end),today,coalesce(recovery_to,today))');
  f := replace(f, '   n:=n+1;', '   last_day:=d; n:=n+1;');
  f := replace(f, 'update nb.calculation_work set dirty_from=null where user_id=p_user;',
   'update nb.calculation_work set dirty_from=case when recovery_to is not null and last_day<today then last_day+1 else null end where user_id=p_user;');
  execute f;
end $$;

do $$ begin
  if to_regprocedure('nb.recompute_range(uuid,date,date,text)') is not null then
    execute 'revoke execute on function nb.recompute_range(uuid, date, date, text) from public, anon, authenticated';
  end if;
end $$;

revoke execute on function nb.night_score_parts(uuid, date) from public, anon, authenticated;
revoke execute on function nb.refresh_night_score(uuid, date) from public, anon, authenticated;
