-- The hourly settle (pg_cron → nb.settle_all → nb.recompute_range) is one statement
-- under the hosted statement_timeout of 120 s. Since the 2026-09-06 evidence releases a
-- day settles in 6–15 s, and the post-release replay left every account dirty from
-- 08-30/09-01, so the run needed several minutes, was cancelled at 120 s, rolled back
-- every day it had settled, and the backlog never shrank: from 14:07 UTC on 09-06 no
-- cron run succeeded, and no account got a sleep score or body battery for a new day.
--
-- Fix: the caller can hand recompute_range a deadline (session setting
-- nb.calculation_deadline). The loop always settles at least one day, stops once the
-- deadline has passed, records the first unsettled day in calculation_work.dirty_from
-- and returns normally, so the transaction commits and the next run resumes there.
-- Without a deadline the function behaves exactly as before. settle_all derives the
-- deadline from statement_timeout and serves the least recently settled account first,
-- so one large backlog cannot starve the others.
--
-- Patched by text replacement on the production body (like 20260906221000) so it layers
-- on whatever later release last touched the function; each anchor must match once.

do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.recompute_range(uuid,date,date,text)'::regprocedure);
 if position('nb.calculation_deadline' in def)>0 then return; end if;

 patched:=replace(def,'recovery_to date; last_day date;',
                      'recovery_to date; last_day date; deadline timestamptz; next_day date;');
 if patched=def then raise exception 'SETTLE_BUDGET_DECLARE_ANCHOR_MISSING'; end if; def:=patched;

 patched:=replace(def,' previous_day:=current_setting(''nb.calculation_day'',true);',
  ' previous_day:=current_setting(''nb.calculation_day'',true);'||chr(10)||
  ' deadline:=nullif(current_setting(''nb.calculation_deadline'',true),'''')::timestamptz;');
 if patched=def then raise exception 'SETTLE_BUDGET_READ_ANCHOR_MISSING'; end if; def:=patched;

 -- After the "already settled" skip, before any work for day d: at least one day per call.
 patched:=replace(def,'   perform set_config(''nb.calculation_day'',d::text,true);',
  '   if deadline is not null and last_day is not null and clock_timestamp()>deadline then next_day:=d; exit; end if;'||chr(10)||
  '   perform set_config(''nb.calculation_day'',d::text,true);');
 if patched=def then raise exception 'SETTLE_BUDGET_LOOP_ANCHOR_MISSING'; end if; def:=patched;

 patched:=replace(def,
  'update nb.calculation_work set dirty_from=case when recovery_to is not null and last_day<today then last_day+1 else null end where user_id=p_user;',
  'update nb.calculation_work set dirty_from=case when next_day is not null then next_day when recovery_to is not null and last_day<today then last_day+1 else null end where user_id=p_user;');
 if patched=def then raise exception 'SETTLE_BUDGET_DIRTY_ANCHOR_MISSING'; end if; def:=patched;

 patched:=replace(def,'values(''calculation-revisions-1'',p_reason,n);',
  'values(''calculation-revisions-1'',p_reason||case when next_day is not null then '' (deadline, resumes ''||next_day||'')'' else '''' end,n);');
 if patched=def then raise exception 'SETTLE_BUDGET_LOG_ANCHOR_MISSING'; end if; def:=patched;

 execute def;
end $$;

create or replace function nb.settle_all(p_days integer default 2)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare u record; n integer := 0; budget interval; deadline timestamptz;
begin
  -- 70 % of the statement budget for settling, the rest for the day that overruns it.
  budget := coalesce(nullif(current_setting('statement_timeout', true), ''), '0')::interval;
  if budget <= interval '0' then budget := interval '2 minutes'; end if;
  deadline := clock_timestamp() + budget * 0.7;
  perform set_config('nb.calculation_deadline', deadline::text, true);
  -- Least recently settled first: an account skipped this hour is served first next hour.
  for u in
    select p.user_id, p.timezone from public.profiles p
    where p.deletion_requested_at is null
    order by (select max(r.computed_at) from public.daily_results r where r.user_id = p.user_id) asc nulls first,
             p.user_id
  loop
    exit when clock_timestamp() > deadline;
    -- Each user's own calendar. A single UTC date would settle the wrong day for
    -- everyone east or west of Greenwich.
    perform nb.recompute_range(
      u.user_id,
      (timezone(u.timezone, now()))::date - p_days,
      (timezone(u.timezone, now()))::date,
      'cron');
    n := n + 1;
  end loop;
  perform set_config('nb.calculation_deadline', '', true);
  return n;
end;
$$;
revoke execute on function nb.settle_all(integer) from public, anon, authenticated;
