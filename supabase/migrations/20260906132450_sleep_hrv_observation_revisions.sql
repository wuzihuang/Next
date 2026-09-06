-- Minute RMSSD correction is a versioned fact. Replaying an old band-sleep outbox
-- must not resurrect a minute invalidated by a newer RR read. Other sleep fields
-- still follow their existing upsert contract; overlapping corrections retain their
-- revision history, while non-overlapping windows are isolated.
create or replace function nb.merge_sleep_hrv(p_old jsonb,p_new jsonb,p_start timestamptz,p_wake timestamptz)
returns jsonb language sql stable set search_path='' as $$
 with snapshots as (
  select coalesce(p_old,'{}'::jsonb) raw,0 priority union all select coalesce(p_new,'{}'::jsonb),1
 ), points as (
  select j,nb.bb_instant(j->>'ts') ts,nb.bb_number(j->>'rmssd_ms') h,
    coalesce(nb.bb_instant(j->>'observed_at'),'-infinity'::timestamptz) observed,priority
  from snapshots s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.raw->'hrv')='array' then s.raw->'hrv' else '[]'::jsonb end) j
 ), valid as (
  select distinct on(ts) * from points where h between 1 and 300 and ts>=p_start and ts<p_wake
   and (observed='-infinity'::timestamptz or observed<=now()+interval '5 minutes')
  -- An unversioned retry cannot replace an already accepted unversioned point.
  order by ts,observed desc,priority asc
 ), revoked as (
  select j,nb.bb_instant(j->>'ts') ts,nb.bb_instant(j->>'observed_at') observed
  from snapshots s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.raw->'hrv_invalidated')='array' then s.raw->'hrv_invalidated' else '[]'::jsonb end) j
 ), tombstones as (
  select distinct on(ts) * from revoked where ts>=p_start and ts<p_wake
   and observed is not null and observed<=now()+interval '5 minutes' order by ts,observed desc
 ), kept as (
  select v.j,v.ts from valid v where not exists(select 1 from tombstones t where t.ts=v.ts and t.observed>=v.observed)
 )
 select coalesce(p_new,'{}'::jsonb)
  ||case when (exists(select 1 from snapshots where raw?'hrv') or exists(select 1 from tombstones))
    then jsonb_build_object('hrv',(select coalesce(jsonb_agg(k.j order by k.ts),'[]'::jsonb) from kept k)) else '{}'::jsonb end
  ||case when exists(select 1 from snapshots where raw?'hrv_invalidated') then jsonb_build_object('hrv_invalidated',(select coalesce(jsonb_agg(t.j order by t.ts),'[]'::jsonb) from tombstones t)) else '{}'::jsonb end;
$$;

create or replace function nb.preserve_sleep_hrv_revisions() returns trigger
language plpgsql security definer set search_path='' as $$
declare prior jsonb:='{}'::jsonb;
begin
 if tg_op='UPDATE' and old.user_id=new.user_id and old.user_day=new.user_day
   and old.sleep_start<new.wake_at and new.sleep_start<old.wake_at then prior:=old.raw; end if;
 new.raw:=nb.merge_sleep_hrv(prior,new.raw,new.sleep_start,new.wake_at);
 return new;
end $$;
create trigger preserve_sleep_hrv_revisions before insert or update of raw,sleep_start,wake_at
on public.sleep_nights for each row execute function nb.preserve_sleep_hrv_revisions();

-- Defensive reads also honor tombstones on rows accepted before this trigger.
-- Five-minute fallbacks cannot recreate an explicitly invalidated native minute.
do $$ declare def text; patched text;
begin
 def:=pg_get_functiondef('nb.night_evidence_parts_at(uuid,date,timestamptz)'::regprocedure);
 patched:=replace(def,'then n.raw->''hrv'' else',
  'then nb.merge_sleep_hrv(''{}''::jsonb,n.raw,n.sleep_start,n.wake_at)->''hrv'' else');
 if def=patched then raise exception 'SLEEP_HRV_NATIVE_PATCH_MISSING'; end if;
 def:=patched;
 patched:=replace(def,'then r.hrv end end h',
  'and not exists(select 1 from nb.canonical_sleep_nights(p_user,p_user_day,p_user_day) s cross join lateral jsonb_array_elements(coalesce(nb.merge_sleep_hrv(''{}''::jsonb,s.raw,s.sleep_start,s.wake_at)->''hrv_invalidated'',''[]''::jsonb)) i where nb.bb_instant(i->>''ts'')=m.ts) then r.hrv end end h');
 if def=patched then raise exception 'SLEEP_HRV_COARSE_PATCH_MISSING'; end if;
 execute patched;
end $$;
revoke all on function nb.merge_sleep_hrv(jsonb,jsonb,timestamptz,timestamptz),nb.preserve_sleep_hrv_revisions() from public,anon,authenticated;
