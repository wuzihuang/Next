-- #30 · third pass: the replay walks its ticks once, a night's HRV is merged once, and a
-- closed night's evidence is the same under any later as-of.
--
-- With the memos in place a closed day settled in 3.7 s. Timed piece by piece on the live
-- account (rolled back):
--
--   reserve_replay_uncached, memo warm                    1264 ms
--   the same with `numbered as materialized`               165 ms
--   night_evidence_parts_at_uncached, one night             91 ms  × 16 nights a day
--
-- The replay is `with recursive … replay as (… join numbered x on x.n = r.n + 1)`. `numbered`
-- was a plain CTE referenced once, so the planner inlined it into the recursive term, and every
-- one of the 288 iterations re-ran tick_grid → observed → fused → feature — 288 index lookups
-- into raw_samples per step, 83 000 a day. Materialising it computes the chain once.
--
-- In the evidence engine the same night's HRV JSON was merged twice (native points, then the
-- retractions) and each native point parsed its timestamp five times and its value three. The
-- `night` CTE now carries the merged JSON; the native CTE parses each point once through a
-- lateral subselect held back from pull-up with `offset 0`.
--
-- The wrapper's key normalises the as-of for closed nights. Every as-of-dependent term in the
-- engine (`ts < p_as_of` on native points and raw samples, `wake_at <= p_as_of` on
-- eligibility) is decided once wake_at has passed, because the covered minutes end at wake_at.
-- So when every candidate row's wake_at is at or before the as-of the answer is the same under
-- any later as-of, and a settle that catches up three days computes each baseline night once
-- instead of once per day. Nights still in progress keep the exact as-of.
--
-- ⚠️ Results are unchanged by construction; verified as before, old against new in one
-- rolled-back transaction on the two live accounts, every published field equal.

-- 1 · the replay's numbered ticks, once ----------------------------------------------
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.reserve_replay_uncached(uuid,date)'::regprocedure);
 patched:=replace(def,'  numbered as ('||chr(10),'  numbered as materialized ('||chr(10));
 if patched=def then raise exception 'REPLAY_NUMBERED_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

-- 2 · the night's HRV merged once, each point parsed once ---------------------------------
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.night_evidence_parts_at_uncached(uuid,date,timestamptz)'::regprocedure);
 patched:=replace(def,
  '  select * from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) n where n.user_id=p_user and n.user_day=p_user_day'||chr(10),
  '  select n.*,nb.merge_sleep_hrv(''{}''::jsonb,n.raw,n.sleep_start,n.wake_at) merged'||chr(10)||
  '  from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) n where n.user_id=p_user and n.user_day=p_user_day'||chr(10));
 if patched=def then raise exception 'EVIDENCE_NIGHT_ANCHOR_MISSING'; end if; def:=patched;
 patched:=replace(def,
  '  select distinct on (nb.bb_instant(j->>''ts'')) nb.bb_instant(j->>''ts'') ts,nb.bb_number(j->>''rmssd_ms'') h'||chr(10)||
  '  from night n cross join lateral jsonb_array_elements(case when jsonb_typeof(n.raw->''hrv'')=''array'' then nb.merge_sleep_hrv(''{}''::jsonb,n.raw,n.sleep_start,n.wake_at)->''hrv'' else ''[]''::jsonb end) j'||chr(10)||
  '  where n.user_id=p_user and n.user_day=p_user_day and nb.bb_number(j->>''rmssd_ms'') between 1 and 300'||chr(10)||
  '   and nb.bb_instant(j->>''ts'')<p_as_of'||chr(10)||
  '   and exists(select 1 from minutes m where m.ts=nb.bb_instant(j->>''ts''))'||chr(10)||
  '  order by nb.bb_instant(j->>''ts''),nb.bb_number(j->>''rmssd_ms'')'||chr(10),
  '  select distinct on (x.ts) x.ts,x.h'||chr(10)||
  '  from night n cross join lateral jsonb_array_elements(case when jsonb_typeof(n.raw->''hrv'')=''array'' then n.merged->''hrv'' else ''[]''::jsonb end) j'||chr(10)||
  '  cross join lateral (select nb.bb_instant(j->>''ts'') ts,nb.bb_number(j->>''rmssd_ms'') h offset 0) x'||chr(10)||
  '  where n.user_id=p_user and n.user_day=p_user_day and x.h between 1 and 300'||chr(10)||
  '   and x.ts<p_as_of'||chr(10)||
  '   and exists(select 1 from minutes m where m.ts=x.ts)'||chr(10)||
  '  order by x.ts,x.h'||chr(10));
 if patched=def then raise exception 'EVIDENCE_NATIVE_ANCHOR_MISSING'; end if; def:=patched;
 patched:=replace(def,
  '  cross join lateral jsonb_array_elements(coalesce(nb.merge_sleep_hrv(''{}''::jsonb,s.raw,s.sleep_start,s.wake_at)->''hrv_invalidated'',''[]''::jsonb)) i',
  '  cross join lateral jsonb_array_elements(coalesce(s.merged->''hrv_invalidated'',''[]''::jsonb)) i');
 if patched=def then raise exception 'EVIDENCE_INVALIDATED_ANCHOR_MISSING'; end if; def:=patched;
 if (length(def)-length(replace(def,'merge_sleep_hrv','')))/length('merge_sleep_hrv')<>1 then
  raise exception 'EVIDENCE_MERGE_STILL_REPEATED';
 end if;
 execute def;
end $$;

-- 3 · a closed night's evidence keyed without its as-of ----------------------------------
create or replace function nb.night_evidence_parts_at(p_user uuid,p_user_day date,p_as_of timestamptz)
returns table(hrv numeric,rhr numeric,hrv_bucket_count integer,hrv_tick_count integer,expected_minutes integer,
 hrv_minutes integer,rhr_minutes integer,hrv_coverage numeric,rhr_coverage numeric,hrv_longest_gap integer,
 rhr_longest_gap integer,hrv_eligible boolean,rhr_eligible boolean,hrv_source text)
language plpgsql stable set search_path='' as $$
declare k text; memo jsonb; hit jsonb; closed_by timestamptz;
begin
 -- The canonical night for this day comes from the rows a day either side; once the last of
 -- them has woken the engine's every as-of comparison is settled.
 select greatest(max(s.wake_at),max(s.corrected_end)) into closed_by from public.sleep_nights s
  where s.user_id=p_user and s.user_day between p_user_day-1 and p_user_day+1;
 k:=p_user::text||'/'||p_user_day::text||'/'
   ||case when closed_by is not null and closed_by<=p_as_of then 'closed' else coalesce(p_as_of::text,'') end||'/'
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
revoke execute on function nb.night_evidence_parts_at(uuid,date,timestamptz) from public, anon, authenticated;
