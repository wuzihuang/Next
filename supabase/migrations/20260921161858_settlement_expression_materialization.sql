-- Preserve the arithmetic and numeric precision while evaluating each recursive
-- intermediate once. Inlining the lateral expressions duplicates numeric exp,
-- products and divisions throughout each tick. OFFSET 0 keeps these one-row
-- subqueries as evaluation boundaries; it discards no rows.
do $$ declare def text; old text; replacement text; patched text; begin
 def:=pg_get_functiondef('nb.reserve_replay_uncached(uuid,date)'::regprocedure);
 old:=$anchor$  ) q$anchor$; replacement:=$anchor$  offset 0) q$anchor$;
 patched:=replace(def,old,replacement);
 if patched=def then raise exception 'REPLAY_EXPRESSION_ANCHOR_MISSING: %',old; end if;
 def:=patched;
 old:=$anchor$  ) raw$anchor$; replacement:=$anchor$  offset 0) raw$anchor$;
 patched:=replace(def,old,replacement);
 if patched=def then raise exception 'REPLAY_EXPRESSION_ANCHOR_MISSING: %',old; end if;
 def:=patched;
 old:=$anchor$  ) soft$anchor$; replacement:=$anchor$  offset 0) soft$anchor$;
 patched:=replace(def,old,replacement);
 if patched=def then raise exception 'REPLAY_EXPRESSION_ANCHOR_MISSING: %',old; end if;
 def:=patched;
 old:=$anchor$  cross join lateral (select raw.awake*soft.k awake,raw.movement*soft.k movement,raw.strain*soft.k strain) eff$anchor$; replacement:=$anchor$  cross join lateral (select raw.awake*soft.k awake,raw.movement*soft.k movement,raw.strain*soft.k strain offset 0) eff$anchor$;
 patched:=replace(def,old,replacement);
 if patched=def then raise exception 'REPLAY_EXPRESSION_ANCHOR_MISSING: %',old; end if;
 def:=patched;
 old:=$anchor$  ) scale$anchor$; replacement:=$anchor$  offset 0) scale$anchor$;
 patched:=replace(def,old,replacement);
 if patched=def then raise exception 'REPLAY_EXPRESSION_ANCHOR_MISSING: %',old; end if;
 def:=patched;
 execute def;
 def:=pg_get_functiondef('nb.training_contributions(uuid,date)'::regprocedure);
 patched:=replace(def,'), scored as (','), scored as materialized (');
 if patched=def then raise exception 'TRAINING_SCORE_ANCHOR_MISSING'; end if;
 execute patched;
end $$;

-- Resolve fine-sample ownership once with an equality join on the five-minute
-- bucket. The old correlated lookups scanned every day's piece for every span.
-- DISTINCT ON retains the same newest observation / UUID winner for each signal.
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.training_observed_ledger(uuid,date)'::regprocedure);
 patched:=replace(def,$anchor$ ), owned as (
$anchor$,$anchor$ ), owners as materialized (
  select distinct on(s.ts,s.a,s.b,i.kind) s.ts,s.a,s.b,i.kind,i.id,i.heart,i.met,i.session_id,i.sport_mode
  from spans s join pieces i on i.ts=s.ts and i.piece_a<=s.a and i.piece_b>=s.b
  where s.b>s.a
  order by s.ts,s.a,s.b,i.kind,i.observed_at desc,i.id desc
 ), owned as (
$anchor$);
 if patched=def then raise exception 'TRAINING_OWNER_ANCHOR_MISSING'; end if;
 def:=patched;
 patched:=replace(def,$anchor$  left join lateral(select i.* from pieces i where i.ts=s.ts and i.kind='hr'
   and i.piece_a<=s.a and i.piece_b>=s.b order by i.observed_at desc,i.id desc limit 1) h on true
  left join lateral(select i.* from pieces i where i.ts=s.ts and i.kind='met'
   and i.piece_a<=s.a and i.piece_b>=s.b order by i.observed_at desc,i.id desc limit 1) e on true$anchor$,$anchor$  left join owners h on h.ts=s.ts and h.a=s.a and h.b=s.b and h.kind='hr'
  left join owners e on e.ts=s.ts and e.a=s.a and e.b=s.b and e.kind='met'$anchor$);
 if patched=def then raise exception 'TRAINING_OWNER_ANCHOR_MISSING'; end if;
 def:=patched;
 execute def;
end $$;
