-- The archive guard on account_delete, put back.
--
-- 20260904140000 split account deletion in two: nb.account_delete_legacy_oxygen owns the
-- domain list, and public.account_delete is a guard that refuses while the account still
-- owns sample archives ('USE_ACCOUNT_DELETE_ENDPOINT', so the endpoint can clear the
-- sample-history bucket first) before delegating to it. 20260905160000 added
-- public.balance_checks to the delete list by writing a fresh public.account_delete with
-- the whole body inline, and that body has no guard.
--
-- ⚠️ public.sample_archives cascades from auth.users, so the unguarded routine deletes the
-- rows that name the objects in the bucket. The files stay and nothing points at them any
-- more. supabase/tests/archive_lifecycle_compatibility.sql has been red on tests 1 and 2
-- since that migration landed.
--
-- ⚠️ The domain list is NOT restated here. Later migrations patch the deployed body by
-- anchoring on a delete line (20260906130513 adds sport_heart_rate_samples that way), so a
-- hardcoded list would silently drop whatever landed in between. The body that is deployed
-- now becomes the nb routine verbatim, and only the guard is written by hand.

do $$
declare definition text;
begin
  definition := pg_get_functiondef('public.account_delete(text)'::regprocedure);

  -- Already two-layered: nothing to move, and re-running must not wrap the guard in itself.
  if position('USE_ACCOUNT_DELETE_ENDPOINT' in definition) > 0 then return; end if;
  if position('delete from auth.users' in definition) = 0 then
    raise exception 'ACCOUNT_DELETE_BODY_UNRECOGNISED';
  end if;

  definition := replace(definition,
    'FUNCTION public.account_delete(confirm text)',
    'FUNCTION nb.account_delete_legacy_oxygen(confirm text)');
  if position('nb.account_delete_legacy_oxygen' in definition) = 0 then
    raise exception 'ACCOUNT_DELETE_SIGNATURE_UNRECOGNISED';
  end if;
  execute definition;
end $$;
revoke all on function nb.account_delete_legacy_oxygen(text) from public, anon, authenticated;

create or replace function public.account_delete(confirm text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare owner_id uuid := (select auth.uid());
begin
  if owner_id is null then return jsonb_build_object('error','UNAUTHENTICATED'); end if;
  if confirm is distinct from 'DELETE' then return jsonb_build_object('error','E_SCHEMA'); end if;
  perform 1 from public.profiles where user_id = owner_id for update;
  if exists(select 1 from public.sample_archives where user_id = owner_id)
  or exists(select 1 from storage.objects
             where bucket_id = 'sample-history' and name like owner_id::text || '/%') then
    return jsonb_build_object('error','USE_ACCOUNT_DELETE_ENDPOINT');
  end if;
  return nb.account_delete_legacy_oxygen(confirm);
end;
$$;
revoke all on function public.account_delete(text) from public, anon;
grant execute on function public.account_delete(text) to authenticated;
