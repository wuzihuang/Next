-- Integrate the independently introduced oxygen lifecycle without restoring an
-- unconditional raw-sample delete or bypassing private-object account cleanup.
create or replace function public.prune_retention() returns void
language plpgsql security definer set search_path='' as $$
begin
 delete from public.screen_frames where created_at < now()-interval '90 days';
 delete from public.analytics_events where server_ts < now()-interval '180 days';
 delete from public.oxygen_samples where ts < now()-interval '400 days';
 -- raw_samples leave hot storage only through the verified archive finalizer.
end $$;
revoke all on function public.prune_retention() from public,anon,authenticated;

-- Keep legacy deletion for accounts with no objects, including oxygen cascading,
-- while routing archived accounts to the endpoint which removes Storage objects.
alter function public.account_delete(text) set schema nb;
alter function nb.account_delete(text) rename to account_delete_legacy_oxygen;
revoke all on function nb.account_delete_legacy_oxygen(text) from public,anon,authenticated;
create function public.account_delete(confirm text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare owner_id uuid:=auth.uid();
begin
 if owner_id is null then return jsonb_build_object('error','UNAUTHENTICATED'); end if;
 if confirm is distinct from 'DELETE' then return jsonb_build_object('error','E_SCHEMA'); end if;
 perform 1 from public.profiles where user_id=owner_id for update;
 if exists(select 1 from public.sample_archives where user_id=owner_id)
 or exists(select 1 from storage.objects where bucket_id='sample-history' and name like owner_id::text||'/%') then
   return jsonb_build_object('error','USE_ACCOUNT_DELETE_ENDPOINT');
 end if;
 return nb.account_delete_legacy_oxygen(confirm);
end $$;
revoke all on function public.account_delete(text) from public,anon;
grant execute on function public.account_delete(text) to authenticated;

-- Preserve the other migration's oxygen decoder. Add the lifecycle guard to its
-- current function definition instead of copying a second sensor implementation.
do $$
declare definition text; anchor text:='  if u is null then raise exception ''UNAUTHENTICATED'' using errcode=''28000''; end if;';
begin
 definition:=pg_get_functiondef('public.ingest_band_domain(text,text,date,text,timestamptz,timestamptz,jsonb,text,text)'::regprocedure);
 if position('ACCOUNT_DELETING' in definition)=0 then
   if position(anchor in definition)=0 then raise exception 'INGEST_GUARD_ANCHOR_MISSING'; end if;
   definition:=replace(definition,anchor,anchor||E'\n  perform 1 from public.profiles where user_id=u for share;\n  if exists(select 1 from public.profiles where user_id=u and deletion_requested_at is not null)\n    then raise exception ''ACCOUNT_DELETING'' using errcode=''42501''; end if;');
   execute definition;
 end if;
end $$;
