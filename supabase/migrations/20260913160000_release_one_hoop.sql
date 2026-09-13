-- Close one binding, retaining its observations and historical wear segments.
create or replace function public.release_device(p_device_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid(); dev public.devices%rowtype; remaining uuid;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode = '28000'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text, 74));
  select * into dev from public.devices where id = p_device_id and user_id = u for update;
  if not found then raise exception 'DEVICE_NOT_BOUND' using errcode = '42501'; end if;
  if dev.unbound_at is not null then return public.wear_timeline(); end if;
  update public.devices set unbound_at = now() where id = dev.id;
  select id into remaining from public.devices
    where user_id = u and unbound_at is null order by slot nulls last, bound_at limit 1;
  -- Anchor even an already-worn survivor: replacing slot A must not implicitly steal
  -- the wrist from a remaining B that had never needed an explicit declaration.
  if remaining is not null then
    insert into public.wear_events(user_id, device_id, effective_at, source)
      values (u, remaining, now(), 'release');
  end if;
  -- No reprojection: the surviving band starts now, never across the released history.
  return public.wear_timeline();
end $$;
revoke all on function public.release_device(uuid) from public, anon;
grant execute on function public.release_device(uuid) to authenticated;

-- A delayed historical upload still belongs to the wearer at its timestamp after B
-- is released. Keep the established wrapper but remove its current-binding shortcut.
do $$
declare definition text;
begin
  definition := pg_get_functiondef('public.ingest_band_domain(text,text,date,text,timestamptz,timestamptz,jsonb,text,text,timestamptz)'::regprocedure);
  if position('where user_id = u and unbound_at is null and slot = ''B''' in definition) = 0 then
    raise exception 'Expected dual-device ingestion guard not found';
  end if;
  execute replace(definition,
    'where user_id = u and unbound_at is null and slot = ''B''',
    'where user_id = u and slot = ''B''');
end $$;
