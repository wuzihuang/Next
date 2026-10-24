-- One band, one account (ADR 0003, owner ruling 2026-10-24).
--
-- An account may hold two bands (slots A / B, ADR 0029), but a band is held by exactly one
-- account at a time. Until now the only uniqueness was `(user_id, slot)`, and RLS hides
-- every other account's rows from the client, so nothing could stop a second account on
-- another phone — or on the same phone after a sign-out — from binding a band someone
-- else already holds.
--
-- The band's identity is the MAC the firmware reports. Both apps write it to
-- `ble_identifier` (iOS since 20260913120000 moved the CoreBluetooth UUID to `client_key`);
-- older rows that hold a UUID or a placeholder carry no hardware key and are left alone.
-- The simulator's two mock bands are shared by every demo account on purpose and never count.
--
-- A trigger, not an RPC, so the builds already in people's hands are held to the same
-- rule the moment this ships: their direct insert or patch fails instead of binding.

alter table public.devices add column if not exists hardware_key text;
comment on column public.devices.hardware_key is
  'Normalized firmware MAC (12 upper-case hex digits), derived from ble_identifier by trigger. At most one bound row per key across all accounts. Null when ble_identifier is not a MAC.';

create or replace function nb.band_hardware_key(p text) returns text
language sql immutable set search_path = '' as $$
  select case
    when p ~ '^[0-9A-Fa-f]{2}([:-]?[0-9A-Fa-f]{2}){5}$'
     and upper(pg_catalog.regexp_replace(p, '[:-]', '', 'g'))
         not in ('000000000000', 'FFFFFFFFFFFF', 'C42E8F1A739D', '8E41C02B771F')
    then upper(pg_catalog.regexp_replace(p, '[:-]', '', 'g'))
  end
$$;

-- Existing bound rows: the earliest binding of a band keeps it. A later duplicate is not
-- unbound here (ADR 0003 forbids inferring a transfer); it simply has no key, and the
-- notice below says how many there are so they can be settled by hand.
update public.devices d set hardware_key = nb.band_hardware_key(d.ble_identifier)
 where d.unbound_at is not null;
with ranked as (
  select id, nb.band_hardware_key(ble_identifier) as k,
         row_number() over (partition by nb.band_hardware_key(ble_identifier) order by bound_at, id) as n
    from public.devices where unbound_at is null)
update public.devices d set hardware_key = r.k
  from ranked r where d.id = r.id and r.k is not null and r.n = 1;
do $$
declare dupes integer;
begin
  select count(*) into dupes from public.devices
   where unbound_at is null and hardware_key is null and nb.band_hardware_key(ble_identifier) is not null;
  if dupes > 0 then
    raise notice 'one_band_one_account: % bound row(s) share a band with an earlier binding and were left without a hardware key', dupes;
  end if;
end $$;

create unique index if not exists devices_one_owner_per_band
  on public.devices (hardware_key) where unbound_at is null and hardware_key is not null;

-- Security definer: the holder may be another account, whose row RLS would hide.
create or replace function nb.devices_one_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
declare holder uuid;
begin
  new.hardware_key := nb.band_hardware_key(new.ble_identifier);
  if new.hardware_key is null or new.unbound_at is not null then return new; end if;
  -- Two phones pairing the same band at once: the second waits, then sees the first.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.hardware_key, 75));
  select user_id into holder from public.devices
   where hardware_key = new.hardware_key and unbound_at is null and id <> new.id
   limit 1;
  if holder is null then return new; end if;
  if holder <> new.user_id then
    raise exception 'DEVICE_OWNED_ELSEWHERE' using errcode = '23505',
      hint = 'The band is bound to another account. It has to be released there first.';
  end if;
  raise exception 'DEVICE_ALREADY_IN_SET' using errcode = '23505';
end $$;
revoke all on function nb.devices_one_owner() from public, anon, authenticated;

drop trigger if exists devices_one_owner on public.devices;
-- hardware_key is listed so a client cannot patch the derived key itself.
create trigger devices_one_owner before insert or update of ble_identifier, unbound_at, user_id, hardware_key
  on public.devices for each row execute function nb.devices_one_owner();
