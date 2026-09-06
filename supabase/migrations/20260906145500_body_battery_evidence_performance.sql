-- A minute with five-minute fallback must check HRV retractions. Expand the
-- corrected night's invalidation list once, rather than merging its full HRV
-- JSON again for every fallback minute. This preserves the bb-2.1 result.
do $$ declare def text; patched text; begin
 def:=pg_get_functiondef('nb.night_evidence_parts_at(uuid,date,timestamptz)'::regprocedure);
 patched:=replace(def,' ), covered as materialized (',$patch$
 ), invalidated as materialized (
  select nb.bb_instant(i->>'ts') ts
  from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) s
  cross join lateral jsonb_array_elements(coalesce(nb.merge_sleep_hrv('{}'::jsonb,s.raw,s.sleep_start,s.wake_at)->'hrv_invalidated','[]'::jsonb)) i
 ), covered as materialized ($patch$);
 if patched=def then raise exception 'BODY_BATTERY_INVALIDATION_CTE_ANCHOR_MISSING'; end if;
 def:=patched;
 patched:=replace(def,
  $old$and not exists(select 1 from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) s cross join lateral jsonb_array_elements(coalesce(nb.merge_sleep_hrv('{}'::jsonb,s.raw,s.sleep_start,s.wake_at)->'hrv_invalidated','[]'::jsonb)) i where nb.bb_instant(i->>'ts')=m.ts)$old$,
  'and not exists(select 1 from invalidated i where i.ts=m.ts)');
 if patched=def then raise exception 'BODY_BATTERY_INVALIDATION_LOOKUP_ANCHOR_MISSING'; end if;
 execute patched;
end $$;
