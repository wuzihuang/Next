-- public.account_delete raises on every call, and has since the guard was written.
--
-- 20260906140000 wrote the guard by hand with a plpgsql variable named `owner_id`, then
-- used it inside a sub-select over storage.objects:
--
--   declare owner_id uuid := (select auth.uid());
--   ...
--   or exists(select 1 from storage.objects
--              where bucket_id = 'sample-history' and name like owner_id::text || '/%')
--
-- storage-api added `storage.objects.owner_id text` in its tenant migration 0018
-- (add_owner_id_column_deprecate_owner); this project is at 0064, so the column is there.
-- Inside that sub-select `owner_id` names both the variable and the column, and plpgsql
-- resolves the collision by refusing: 42702, column reference "owner_id" is ambiguous.
--
-- ⚠️ It is a *plan-time* error, so it is not limited to accounts that own archives. Every
-- authenticated caller of public.account_delete gets it — an account with no archive and
-- no object in the bucket included. The in-app delete RPC has been dead since that
-- migration landed. It went unnoticed because supabase/tests only ever stands
-- storage.objects up as `(bucket_id text, name text)`, and a stub without the column has
-- no collision to find.
--
-- The variable is renamed rather than the statement re-qualified: the whole body reads as
-- one owner, and `#variable_conflict use_variable` would silently pick a winner instead of
-- removing the ambiguity. Patched by anchored replacement, not restated, because the
-- deployed body is the one later migrations keep amending.

do $$
declare definition text; patched text;
begin
  definition := pg_get_functiondef('public.account_delete(text)'::regprocedure);

  -- Already renamed: re-running must be a no-op.
  if position('owner_id' in definition) = 0 then return; end if;

  if position('declare owner_id uuid := (select auth.uid());' in definition) = 0 then
    raise exception 'ACCOUNT_DELETE_OWNER_ANCHOR_MISSING';
  end if;
  -- A later body may want storage.objects.owner_id for its own sake. A qualified
  -- reference would be rewritten by the substitution below, so refuse instead of
  -- corrupting it; whoever wrote it gets to decide what the variable is called.
  if definition ~ '\.owner_id' then
    raise exception 'ACCOUNT_DELETE_OWNER_QUALIFIED_REFERENCE_PRESENT';
  end if;

  patched := regexp_replace(definition, '\mowner_id\M', 'v_owner', 'g');

  -- The guard and the delegation are the point of this function; a substitution that
  -- lost either of them is not the function we meant to keep.
  if position('USE_ACCOUNT_DELETE_ENDPOINT' in patched) = 0
     or position('nb.account_delete_legacy_oxygen' in patched) = 0
     or position('storage.objects' in patched) = 0 then
    raise exception 'ACCOUNT_DELETE_BODY_LOST_IN_PATCH';
  end if;
  if position('owner_id' in patched) > 0 then
    raise exception 'ACCOUNT_DELETE_OWNER_STILL_AMBIGUOUS';
  end if;

  execute patched;
end $$;

-- pg_get_functiondef reproduces the grants' target but not the grants; restate the ones
-- 20260906140000 set, so a database that replays only this file lands in the same place.
revoke all on function public.account_delete(text) from public, anon;
grant execute on function public.account_delete(text) to authenticated;
