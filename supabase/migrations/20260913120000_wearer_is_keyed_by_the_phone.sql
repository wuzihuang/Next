-- The wearer is keyed by what the phone sends.
--
-- Found on the first real-device walk of two HOOPs, one wearer (20260913100000): the phone
-- keys every piece of evidence by its CoreBluetooth peripheral UUID (`BoundBand.identifier`),
-- while `devices.ble_identifier` holds the MAC the firmware reports. The wearer rule compared
-- the two and never matched, so the worn band's own ticks were held as standby.
--
-- `devices.client_key` is the key this phone uses for the band. The phone claims it when it
-- registers or loads the set; until it has, the MAC stands in (single-band accounts never
-- reach the comparison at all).

alter table public.devices add column if not exists client_key text;

create or replace function nb.wearer_device_key(p_user uuid, p_at timestamptz) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select coalesce(d.client_key, d.ble_identifier) from public.wear_events w
       join public.devices d on d.id = w.device_id
      where w.user_id = p_user and w.effective_at <= p_at
        and d.bound_at <= p_at and (d.unbound_at is null or d.unbound_at > p_at)
      order by w.effective_at desc, w.recorded_at desc limit 1),
    (select coalesce(d.client_key, d.ble_identifier) from public.devices d
      where d.user_id = p_user and d.bound_at <= p_at
        and (d.unbound_at is null or d.unbound_at > p_at)
      order by d.slot nulls last, d.bound_at limit 1));
$$;

create or replace function public.wear_timeline() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'events', coalesce((select jsonb_agg(jsonb_build_object(
        'id', w.id, 'device_id', w.device_id, 'slot', d.slot, 'device_key', coalesce(d.client_key, d.ble_identifier),
        'effective_at', w.effective_at, 'recorded_at', w.recorded_at, 'source', w.source)
        order by w.effective_at desc, w.recorded_at desc)
      from public.wear_events w join public.devices d on d.id = w.device_id
      where w.user_id = auth.uid()), '[]'::jsonb),
    'wearing', (select jsonb_build_object('device_key', nb.wearer_device_key(auth.uid(), now()))),
    'devices', coalesce((select jsonb_agg(jsonb_build_object(
        'id', d.id, 'slot', d.slot, 'device_key', coalesce(d.client_key, d.ble_identifier),
        'ble_identifier', d.ble_identifier, 'client_key', d.client_key, 'device_number', d.device_number,
        'firmware_version', d.firmware_version, 'battery_percent', d.battery_percent,
        'battery_level', d.battery_level, 'battery_is_percent', d.battery_is_percent,
        'bound_at', d.bound_at, 'last_origin_sync_at', d.last_origin_sync_at,
        'standby_samples', (select count(*) from public.band_standby_samples b
                             where b.user_id = d.user_id and b.device_key = coalesce(d.client_key, d.ble_identifier)))
        order by d.slot)
      from public.devices d where d.user_id = auth.uid() and d.unbound_at is null), '[]'::jsonb));
$$;

-- The phone names the key it uses for one of its bands. Ticks that were held because the
-- key was unknown are re-projected so the wearer's own record is whole again.
create or replace function public.claim_device_key(p_device_id uuid, p_client_key text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); dev public.devices%rowtype; moved integer := 0; since timestamptz;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode = '28000'; end if;
  if p_client_key is null or length(p_client_key) = 0 or length(p_client_key) > 128 then
    raise exception 'INVALID_CLIENT_KEY' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text, 74));
  select * into dev from public.devices where id = p_device_id and user_id = u and unbound_at is null;
  if not found then raise exception 'DEVICE_NOT_BOUND' using errcode = '42501'; end if;
  if dev.client_key is distinct from p_client_key then
    update public.devices set client_key = p_client_key where id = dev.id;
    select min(ts) into since from public.band_standby_samples where user_id = u and device_key = p_client_key;
    if since is not null then moved := nb.reproject_wear(u, since, now()); end if;
  end if;
  return public.wear_timeline() || jsonb_build_object('moved', moved);
end $$;
revoke all on function public.claim_device_key(uuid, text) from public, anon;
grant execute on function public.claim_device_key(uuid, text) to authenticated;
