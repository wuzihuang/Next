-- Photo writes and consent changes take the same profile lock as account deletion.
-- RLS scopes callers; the trigger also protects uploads performed by Storage's
-- service role, and observes a tombstone/withdrawal committed while it was waiting.
create function nb.lock_meal_consent_owner() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.profiles where user_id=new.user_id for update;
  return new;
end $$;
revoke all on function nb.lock_meal_consent_owner() from public,anon,authenticated;
create trigger consents_serialize_meal_collection before insert on public.consents
for each row execute function nb.lock_meal_consent_owner();

create function nb.guard_meal_photo() returns trigger
language plpgsql security definer set search_path='' as $$
declare photo_owner uuid;
begin
  if tg_op='UPDATE' and old.bucket_id='meal-photos'
     and (new.bucket_id,new.name) is distinct from (old.bucket_id,old.name) then
    raise exception 'MEAL_PHOTO_PATH_IMMUTABLE' using errcode='42501';
  end if;
  if new.bucket_id<>'meal-photos' then return new; end if;
  -- Exactly one leaf keeps the endpoint's prefix listing exhaustive (no directories).
  if new.name !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$' then
    raise exception 'INVALID_MEAL_PHOTO_PATH' using errcode='22023';
  end if;
  photo_owner:=split_part(new.name,'/',1)::uuid;
  perform 1 from public.profiles where user_id=photo_owner and deletion_requested_at is null for share;
  if not found then raise exception 'ACCOUNT_UNAVAILABLE' using errcode='42501'; end if;
  if (select choice from public.consents where user_id=photo_owner order by decided_at desc,id desc limit 1)
     is distinct from 'granted' then
    raise exception 'CONSENT_WITHDRAWN' using errcode='42501';
  end if;
  return new;
end $$;
revoke all on function nb.guard_meal_photo() from public,anon,authenticated;
create trigger meal_photo_active_owner before insert or update on storage.objects
for each row execute function nb.guard_meal_photo();

-- The upload uses upsert, which requires UPDATE as well as INSERT and SELECT.
-- Both sides retain owner checks; the trigger serializes the eligibility decision.
create policy meal_photo_update on storage.objects for update to authenticated
using(bucket_id='meal-photos' and split_part(name,'/',1)=(select auth.uid())::text)
with check(bucket_id='meal-photos' and split_part(name,'/',1)=(select auth.uid())::text);

-- Patch the established wrapper, preserving all archive/account lifecycle changes.
do $$ declare definition text; patched text; begin
  definition:=pg_get_functiondef('public.account_delete(text)'::regprocedure);
  patched:=replace(definition, 'bucket_id = ''sample-history''',
    'bucket_id in (''sample-history'', ''meal-photos'')');
  if patched=definition then raise exception 'MEAL_PHOTO_DELETE_GUARD_ANCHOR_MISSING'; end if;
  execute patched;
end $$;

-- Favorites are account data too; export the current owner's complete saved plates.
do $$ declare definition text; patched text; begin
  definition:=pg_get_functiondef('public.export_all()'::regprocedure);
  patched:=replace(definition, '''meals'',',
    '''meal_favorites'', (select coalesce(jsonb_agg(to_jsonb(f) order by f.created_at,f.id), ''[]''::jsonb) from public.meal_favorites f where f.user_id=(select auth.uid())), ''meals'',');
  if patched=definition then raise exception 'MEAL_FAVORITES_EXPORT_ANCHOR_MISSING'; end if;
  execute patched;
end $$;
