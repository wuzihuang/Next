-- #30 · follow-up to 20260912150000: the training ticks once per settle, the canonical
-- night once per evidence call.
--
-- After the memos a closed day settles in 4.8 s (track_functions, same account, same day):
--
--   reserve_replay_uncached            1 call    2.0 s   the recursive walk itself, 1.2 s
--   night_evidence_parts_at_uncached  16 calls   1.9 s   canonical_sleep_nights 84×, 0.9 s of it
--   training_load_ticks                5 calls   1.8 s   compute_training, compute_segments ×2,
--                                                        training_evidence, activity_ticks
--
-- Under the phone's 8 s budget settle_now stops at 4 s, so at 4.8 s a day every foreground
-- settles exactly one day; a band that re-syncs last night keeps the account dirty two or
-- three days back, and today waits for the third foreground or the hour. At ~3 s a day the
-- same call settles two.
--
--   1 · `training_load_ticks` is built once per settle_day. Its five callers all run inside
--       settle_day (the two triggers on daily_training included), and only there is the memo
--       used: sport_heart_rate_samples carries no invalidation trigger, so outside a settle two
--       calls in one transaction may legitimately see different facts and go to the engine
--       every time. settle_day marks the day it is on in `nb.settling_day` and clears the mark
--       when it returns; the engine keeps its body as `training_load_ticks_uncached`.
--   2 · `night_evidence_parts_at_uncached` read the canonical night five times per call
--       (the native HRV, the retractions, the "explicit empty" check and twice for wake_at).
--       One materialised `night` CTE feeds all five. Same rows, same filters.
--
-- ⚠️ Results are unchanged by construction; verified the same way as 20260912150000, old
-- code against new in one rolled-back transaction on the two live accounts.
-- ⚠️ A renamed engine keeps its ACL; a freshly created wrapper does not, and 20260912150000
-- left `nb.night_evidence_parts_at` executable by anon and authenticated. Both wrappers are
-- revoked here to what their engines have (training_load_evidence.sql asserts it).

-- 1 · the training ticks, once per settle_day ---------------------------------------
alter function nb.training_load_ticks(uuid,date) rename to training_load_ticks_uncached;

create function nb.training_load_ticks(p_user uuid,p_user_day date)
returns table(ts timestamptz,heart smallint,steps integer,z smallint,raw numeric,zone_seconds numeric[],
 observed_seconds numeric,hr_seconds numeric,movement_seconds numeric,hr_weighted_sum numeric,hr_peak smallint)
language plpgsql stable set search_path='' as $$
declare hit jsonb;
begin
 if current_setting('nb.settling_day',true) is distinct from p_user::text||'/'||p_user_day::text then
  return query select * from nb.training_load_ticks_uncached(p_user,p_user_day); return;
 end if;
 hit:=nullif(current_setting('nb.training_ticks_memo',true),'')::jsonb;
 if hit is null then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into hit from nb.training_load_ticks_uncached(p_user,p_user_day) t;
  perform set_config('nb.training_ticks_memo',hit::text,true);
 end if;
 return query select * from jsonb_to_recordset(hit) as t(ts timestamptz,heart smallint,steps integer,z smallint,
  raw numeric,zone_seconds numeric[],observed_seconds numeric,hr_seconds numeric,movement_seconds numeric,
  hr_weighted_sum numeric,hr_peak smallint);
end $$;

revoke execute on function nb.training_load_ticks(uuid,date) from public, anon, authenticated;
revoke execute on function nb.night_evidence_parts_at(uuid,date,timestamptz) from public, anon, authenticated;

do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.settle_day(uuid,date)'::regprocedure);
 patched:=replace(def,'begin'||chr(10)||'  select * into v_train   from nb.compute_training(p_user, p_user_day);',
  'begin'||chr(10)||
  '  perform set_config(''nb.settling_day'', p_user::text||''/''||p_user_day::text, true);'||chr(10)||
  '  perform set_config(''nb.training_ticks_memo'', '''', true);'||chr(10)||
  '  select * into v_train   from nb.compute_training(p_user, p_user_day);');
 if patched=def then raise exception 'SETTLE_DAY_ENTRY_ANCHOR_MISSING'; end if; def:=patched;
 patched:=replace(def,'  return v_id;'||chr(10)||'end;',
  '  perform set_config(''nb.settling_day'', '''', true); perform set_config(''nb.training_ticks_memo'', '''', true);'||chr(10)||
  '  return v_id;'||chr(10)||'end;');
 if patched=def then raise exception 'SETTLE_DAY_RETURN_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

-- 2 · the canonical night, once per evidence call ------------------------------------
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.night_evidence_parts_at_uncached(uuid,date,timestamptz)'::regprocedure);
 patched:=replace(def,' with minutes as materialized ('||chr(10),
  ' with night as materialized ('||chr(10)||
  '  select * from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) n where n.user_id=p_user and n.user_day=p_user_day'||chr(10)||
  ' ), minutes as materialized ('||chr(10));
 if patched=def then raise exception 'EVIDENCE_FIRST_CTE_ANCHOR_MISSING'; end if; def:=patched;
 patched:=replace(def,'from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) n cross join lateral','from night n cross join lateral');
 if patched=def then raise exception 'EVIDENCE_NATIVE_ANCHOR_MISSING'; end if; def:=patched;
 patched:=replace(def,'from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) s'||chr(10),'from night s'||chr(10));
 if patched=def then raise exception 'EVIDENCE_INVALIDATED_ANCHOR_MISSING'; end if; def:=patched;
 patched:=replace(def,'not exists(select 1 from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) s where s.raw->''hrv''=''[]''::jsonb)',
  'not exists(select 1 from night s where s.raw->''hrv''=''[]''::jsonb)');
 if patched=def then raise exception 'EVIDENCE_EMPTY_ANCHOR_MISSING'; end if; def:=patched;
 patched:=replace(def,'(select s.wake_at from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) s)','(select s.wake_at from night s)');
 if patched=def then raise exception 'EVIDENCE_WAKE_ANCHOR_MISSING'; end if; def:=patched;
 if position('canonical_sleep_nights(p_user,p_user_day,p_user_day)' in replace(def,'select * from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) n where','')) > 0 then
  raise exception 'EVIDENCE_CANONICAL_READ_LEFT_BEHIND';
 end if;
 execute def;
end $$;
