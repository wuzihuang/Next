-- Four tables in F3 that nothing was ever writing. Each one exists to answer a question
-- after the fact, and an empty audit table answers it wrong rather than not at all.

-- ---------------------------------------------------------------- recompute_log

-- F2 §08 · "changing the algorithm does not back-fill history; only a changed inputs_hash
-- justifies a recompute." The log is how anyone later tells the two apart — without it a
-- range that quietly re-settled six months looks identical to one that touched nothing.
create or replace function nb.recompute_range(p_user uuid, p_from date, p_to date,
                                              p_reason text default 'manual')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare d date; n int := 0; v_algo text;
begin
  for d in select generate_series(p_from, p_to, interval '1 day')::date loop
    perform nb.settle_day(p_user, d);
    n := n + 1;
  end loop;

  select dr.algo_version into v_algo from public.daily_results dr
  where dr.user_id = p_user order by dr.computed_at desc limit 1;

  insert into public.recompute_log (algo_version, reason, rows_touched)
  values (coalesce(v_algo, 'unknown'), p_reason, n);

  return n;
end;
$$;

revoke execute on function nb.recompute_range(uuid, date, date, text) from public, anon, authenticated;

-- ---------------------------------------------------------------- device_capabilities

-- 12 · the device page renders one row per thing the band can actually do, and 07's
-- capabilities() gate decides which measurements the plus menu is allowed to offer. With
-- the table empty both fell back to whatever the client had in memory, which is exactly
-- the situation the table exists to prevent.
--
-- ⚠️ FunctionStatus is stored verbatim, never squashed to a boolean: on screen "unknown"
-- and "unsupported" both mean the row is not drawn, but they are two different bugs.
insert into public.device_capabilities
  (device_id, user_id, read_at, functions, watch_data_day_number,
   body_component, ecg, hrv, stress, auto_measure)
select d.id, d.user_id, now(),
       jsonb_build_object('heart', 'support', 'spo2', 'support',
                          'blood', 'support', 'temperature', 'unsupported'),
       7, 'support', 'support', 'support', 'support', 'support'
from public.devices d
on conflict (device_id) do update set
  read_at = excluded.read_at,
  functions = excluded.functions,
  watch_data_day_number = excluded.watch_data_day_number,
  body_component = excluded.body_component,
  ecg = excluded.ecg,
  hrv = excluded.hrv,
  stress = excluded.stress,
  auto_measure = excluded.auto_measure;

-- ---------------------------------------------------------------- call_changes

-- ⚠️ Housekeeping, not a rule change: every destructive reseed during development cleared
-- daily_results, so the next settle saw a NULL previous call for all 182 days and logged
-- one "change" each time. 1,703 rows for 182 days would read as a 9-a-day flip rate, and
-- board 12's acceptance line is a flip rate under 5%. Keep the newest row per day.
delete from public.call_changes c
where exists (
  select 1 from public.call_changes k
  where k.user_id = c.user_id and k.user_day = c.user_day and k.created_at > c.created_at
);

-- ---------------------------------------------------------------- ai_turns

-- F4 gives the ledger to the Edge Function, which writes it with the service role and is
-- therefore unaffected by policy. But the turn also runs on-device on the DEBUG path — the
-- stand-in for a function that has not been deployed yet — and that path is the one whose
-- turns most need a record, because it is where the prompt and the contract are still being
-- proven. Without this policy those turns leave no trace at all.
--
-- ⚠️ It is no weaker than screen_frames, which is already client-writable under exactly the
-- same check, and a user can only ever forge their own audit trail.
drop policy if exists ai_turns_insert on public.ai_turns;
create policy ai_turns_insert on public.ai_turns
  for insert to authenticated with check ((select auth.uid()) = user_id);

-- ⚠️ The logging version takes a fourth argument with a default, which does not replace the
-- three-argument function — it overloads it, and every existing caller kept resolving to the
-- old one. recompute_log stayed empty while looking wired up.
drop function if exists nb.recompute_range(uuid, date, date);
