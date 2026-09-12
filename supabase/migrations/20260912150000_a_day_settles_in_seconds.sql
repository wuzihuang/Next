-- #30 · A day settles in seconds, not in forty.
--
-- On 2026-09-12 the body battery on the phone was —— while the band was uploading a full
-- day: 288 ticks with a heart rate on every one. Nothing was wrong with the data or with
-- the formula (settled by hand, the day read 57). The day was never settled, because
-- settling one day had come to cost 40 s (measured: `recompute_range` on a closed day,
-- 40.6 s), and neither caller can afford that:
--
--   · settle_now runs as `authenticated`, whose statement_timeout is 8 s. Every call the
--     phone made was cancelled inside the replay and rolled back. It never published a row.
--   · nb-settle runs hourly with 70 % of 120 s for every account together. At 40 s a day
--     that is two days an hour across the whole user base. This account was dirty from
--     09-08; 11:07 settled 09-06/07, 13:07 settled 09-08/09, and today's row — written at
--     09:07, eighteen minutes before the day's first tick arrived — stayed
--     worn=false / reserve_score=null with nobody ever coming back for it.
--
-- Where the 41.6 s went (track_functions on one settle_day of a closed day):
--
--   night_evidence_parts_at        230 calls   27.5 s     15 distinct nights
--   calculation_instant         27 393 calls   11.1 s     evaluated per row
--   bb_instant               1 093 396 calls    9.0 s     inside the 230 above
--   canonical_sleep_nights       1 081 calls    8.3 s     five per night evidence call
--   reserve_replay_uncached          2 calls   12.2 s     the night spans two user days
--
-- The evidence for one night is asked for by hr_rest (7 nights, called from the training
-- ticks and the training evidence), by the replay (the night plus 14 baseline nights), and
-- by the charge multiplier (15 more per night the day touches). Each call re-parsed the
-- night's native HRV JSON and re-read the canonical night. The answer for a night does not
-- change between those calls: nothing that it reads changes inside the transaction.
--
-- What this migration does:
--
--   1 · `night_evidence_parts_at` remembers its answer for the transaction, keyed by
--       user / night / as-of / input revision. The revision comes from calculation_work,
--       which every fact trigger advances, so a fact written later in the same transaction
--       (the tests do this) misses the memo. The engine keeps its body under
--       `night_evidence_parts_at_uncached`.
--   2 · `reserve_replay` remembers a day's replay the same way (plus the anchor and the
--       clock it was replayed under), keeping the three newest days. The replay of the day
--       the night started on is therefore built once, when that day was settled, and
--       reused when the next day's morning charge is summed. The `nb.replay_key`
--       publication cache that settle_day pre-warmed becomes a special case of this memo;
--       the wrapper still honours the key so the audit harness's assertion holds.
--   3 · `reserve_replay_uncached` and `training_observations` compute the calculation
--       instant once instead of once per raw sample.
--   4 · `recompute_range` clears both memos when it takes an account's lock, so settle_all
--       never carries one account's memo into the next.
--   5 · `settle_now` hands recompute_range a deadline at half the caller's statement
--       budget, exactly as settle_all does with 70 % of its own. Under the phone's 8 s that
--       is 4 s: the loop settles at least one day, stops at the deadline, records the resume
--       point in calculation_work.dirty_from and commits. The next foreground (which the
--       app already triggers while calculation_status says pending) resumes from there.
--       With no statement budget (tests, service role) nothing changes.
--
-- Memos live in transaction-local settings, the pattern `nb.replay_key` already used:
-- they die with the transaction, cost no catalog rows, and are visible inside STABLE SQL
-- functions (verified: a set_config(…, true) made inside a STABLE plpgsql function with a
-- SET clause survives the function's exit and the transaction's rollback discards it).
--
-- ⚠️ Results are unchanged by construction: a memo returns what the engine returned. The
-- verification in the ADR compares every published field of every day for the two live
-- accounts before and after, in one rolled-back transaction.
-- ⚠️ The 6-hour withdrawal to —— (CONTEXT「身体电量窗」) is untouched; so is ADR 0026,
-- which fixes ticks not arriving. This fixes ticks that arrived and were never settled.

-- 1 · night evidence, once per night per transaction --------------------------------
alter function nb.night_evidence_parts_at(uuid,date,timestamptz) rename to night_evidence_parts_at_uncached;

create function nb.night_evidence_parts_at(p_user uuid,p_user_day date,p_as_of timestamptz)
returns table(hrv numeric,rhr numeric,hrv_bucket_count integer,hrv_tick_count integer,expected_minutes integer,
 hrv_minutes integer,rhr_minutes integer,hrv_coverage numeric,rhr_coverage numeric,hrv_longest_gap integer,
 rhr_longest_gap integer,hrv_eligible boolean,rhr_eligible boolean,hrv_source text)
language plpgsql stable set search_path='' as $$
declare k text; memo jsonb; hit jsonb;
begin
 k:=p_user::text||'/'||p_user_day::text||'/'||coalesce(p_as_of::text,'')||'/'
   ||coalesce((select w.input_revision::text from nb.calculation_work w where w.user_id=p_user),'0');
 memo:=coalesce(nullif(current_setting('nb.night_evidence_memo',true),''),'{}')::jsonb;
 hit:=memo->k;
 if hit is null then
  select to_jsonb(e) into hit from nb.night_evidence_parts_at_uncached(p_user,p_user_day,p_as_of) e;
  if hit is null then return; end if;
  perform set_config('nb.night_evidence_memo',(memo||jsonb_build_object(k,hit))::text,true);
 end if;
 return query select * from jsonb_to_record(hit) as e(hrv numeric,rhr numeric,hrv_bucket_count integer,
  hrv_tick_count integer,expected_minutes integer,hrv_minutes integer,rhr_minutes integer,hrv_coverage numeric,
  rhr_coverage numeric,hrv_longest_gap integer,rhr_longest_gap integer,hrv_eligible boolean,rhr_eligible boolean,
  hrv_source text);
end $$;

-- 2 · the replay of a day, once per transaction -------------------------------------
create or replace function nb.reserve_replay(p_user uuid,p_user_day date)
returns table(ts timestamptz,value numeric,asleep boolean,d_charge numeric,d_basal numeric,d_active numeric,d_stress numeric)
language plpgsql stable set search_path='' as $$
declare k text; memo jsonb; hit jsonb;
begin
 -- The publication cache of 20260904085910: a caller that pinned a day's rows still gets them.
 if current_setting('nb.replay_key',true)=p_user::text||'/'||p_user_day::text then
  return query select * from jsonb_to_recordset(current_setting('nb.replay_data')::jsonb)
   as r(ts timestamptz,value numeric,asleep boolean,d_charge numeric,d_basal numeric,d_active numeric,d_stress numeric);
  return;
 end if;
 -- Day first so that the newest days sort last; the anchor is what the replay starts from
 -- and it moves when the previous day is settled in the same transaction.
 k:=p_user_day::text||'/'||p_user::text||'/'||coalesce(nb.calculation_instant(p_user,p_user_day)::text,'')||'/'
   ||coalesce(nb.calculation_clock()::text,'')||'/'
   ||coalesce((select w.input_revision::text from nb.calculation_work w where w.user_id=p_user),'0')||'/'
   ||coalesce(nb.reserve_anchor(p_user,p_user_day)::text,'');
 memo:=coalesce(nullif(current_setting('nb.reserve_replay_memo',true),''),'{}')::jsonb;
 hit:=memo->k;
 if hit is null then
  select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) into hit from nb.reserve_replay_uncached(p_user,p_user_day) r;
  memo:=memo||jsonb_build_object(k,hit);
  if (select count(*) from jsonb_object_keys(memo))>3 then
   select jsonb_object_agg(x.key,x.value) into memo
   from (select e.key,e.value from jsonb_each(memo) e order by e.key desc limit 3) x;
  end if;
  perform set_config('nb.reserve_replay_memo',memo::text,true);
 end if;
 return query select * from jsonb_to_recordset(hit)
  as r(ts timestamptz,value numeric,asleep boolean,d_charge numeric,d_basal numeric,d_active numeric,d_stress numeric);
end $$;

-- settle_day no longer pre-warms a one-day cache: compute_reserve's first replay fills the memo.
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.settle_day(uuid,date)'::regprocedure);
 patched:=replace(def,
  '  perform set_config(''nb.replay_key'', '''', true);'||chr(10)||
  '  perform set_config(''nb.replay_data'', (select coalesce(jsonb_agg(to_jsonb(r)), ''[]''::jsonb)::text from nb.reserve_replay_uncached(p_user,p_user_day) r), true);'||chr(10)||
  '  perform set_config(''nb.replay_key'', p_user::text||''/''||p_user_day::text, true);'||chr(10),
  '');
 if patched=def then raise exception 'SETTLE_DAY_PREWARM_ANCHOR_MISSING'; end if; def:=patched;
 patched:=replace(def,'  perform set_config(''nb.replay_key'', '''', true); return v_id;','  return v_id;');
 if patched=def then raise exception 'SETTLE_DAY_RETURN_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

-- 3 · the calculation instant, once per replay and once per observation set ------------
do $$ declare def text; patched text; needle text:='nb.calculation_instant(p_user,p_user_day)'; hits integer; begin
 def:=pg_get_functiondef('nb.reserve_replay_uncached(uuid,date)'::regprocedure);
 hits:=(length(def)-length(replace(def,needle,'')))/length(needle);
 if hits<>7 then raise exception 'REPLAY_INSTANT_COUNT_% ',hits; end if;
 def:=replace(def,needle,'v_instant');
 patched:=replace(def,'  v_debt     numeric;'||chr(10)||'begin','  v_debt     numeric;'||chr(10)||'  v_instant  timestamptz;'||chr(10)||'begin');
 if patched=def then raise exception 'REPLAY_DECLARE_ANCHOR_MISSING'; end if; def:=patched;
 patched:=replace(def,'  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);',
  '  select starts_at, ends_at into v_lo, v_hi from nb.user_day_bounds(p_user_day, v_tz);'||chr(10)||
  '  v_instant := nb.calculation_instant(p_user,p_user_day);');
 if patched=def then raise exception 'REPLAY_BOUNDS_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

create or replace function nb.training_observations(p_user uuid,p_user_day date)
returns table(ts timestamptz,heart smallint,steps integer,met numeric,observed boolean)
language sql stable set search_path='' as $$
 with profile as materialized (
  select p.*,nb.calculation_instant(p_user,p_user_day) instant from nb.calculation_profile(p_user,p_user_day) p
 ),
 points as (
  select distinct on(date_bin(interval '5 minutes',s.ts,b.starts_at))
    date_bin(interval '5 minutes',s.ts,b.starts_at) t,s.heart,s.step,s.met
  from profile p cross join lateral nb.user_day_bounds(p_user_day,p.timezone) b
  join public.raw_samples s on s.user_id=p_user and s.ts>=b.starts_at and s.ts<b.ends_at
  where s.ts+interval '5 minutes'<=p.instant
  order by date_bin(interval '5 minutes',s.ts,b.starts_at),(s.src='band') desc,s.ts desc,s.src
 )
 select t,heart,step,met,
   heart between 1 and 250 or met between 0.5 and 25 or step>0
 from points;
$$;

-- 4 · one account's memo never reaches the next --------------------------------------
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.recompute_range(uuid,date,date,text)'::regprocedure);
 patched:=replace(def,' select * into w from nb.calculation_work where user_id=p_user for update;',
  ' select * into w from nb.calculation_work where user_id=p_user for update;'||chr(10)||
  ' perform set_config(''nb.night_evidence_memo'','''',true); perform set_config(''nb.reserve_replay_memo'','''',true);');
 if patched=def then raise exception 'RECOMPUTE_RANGE_LOCK_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

-- 5 · the phone's settle stops before its own statement budget ------------------------
create or replace function public.settle_now(p_days integer default 1)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user   uuid := (select auth.uid());
  v_tz     text;
  v_today  date;
  v_back   integer;
  v_budget interval;
  v_prior  text;
  v_n      integer;
begin
  if v_user is null then
    raise exception 'UNAUTHENTICATED' using errcode = '28000';
  end if;
  select timezone into v_tz from public.profiles where user_id = v_user;
  -- No profile yet → nothing to compute against; the caller gets 0, not an error.
  if v_tz is null then return 0; end if;
  v_today := nb.user_day_of(now(), v_tz);
  -- Today and up to fourteen days back: a first sync pulls what the band still holds
  -- (watchDataDayNumber, seven on a HOOP), and the settle has to cover the same window.
  v_back := least(greatest(coalesce(p_days, 1), 0), 14);
  -- The caller's role runs under a statement budget (8 s for the phone). Settle what fits
  -- in half of it, commit, and let calculation_work.dirty_from say where to resume; a
  -- budget of zero means no budget and the whole chain settles in one call, as before.
  v_budget := coalesce(nullif(current_setting('statement_timeout', true), ''), '0')::interval;
  v_prior := current_setting('nb.calculation_deadline', true);
  if v_budget > interval '0' then
    perform set_config('nb.calculation_deadline', (clock_timestamp() + v_budget * 0.5)::text, true);
  end if;
  v_n := nb.recompute_range(v_user, v_today - v_back, v_today, 'app');
  perform set_config('nb.calculation_deadline', coalesce(v_prior, ''), true);
  return v_n;
end;
$$;

revoke execute on function public.settle_now(integer) from public, anon;
grant execute on function public.settle_now(integer) to authenticated;
