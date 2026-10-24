-- One band, one account, for uploads and claims too (ADR 0003, follows 20261024150000).
--
-- 20261024150000 stops a second account binding a held band, but nothing asked an upload
-- whose band it came from. A build from before that change, signed in to a second account on
-- a phone that kept the first account's binding, keeps filing the first account's band into
-- the second; it can also claim the first account's key for its own row and look like the
-- holder.
--
-- A phone names a band by the key it files evidence under: the firmware MAC (Android, and iOS
-- sets restored by MAC) or that phone's CoreBluetooth alias (iOS). A devices row only carries
-- the key of the phone that claimed it last, so every key a row has carried is kept in
-- nb.device_keys. A key another account holds now is refused for uploads, sleep nights and
-- claims alike. A key nobody holds is taken as before. The simulator's two mock bands and
-- anything that is neither a MAC nor a CoreBluetooth UUID are no one's key.

create or replace function nb.band_key(p text) returns text
language sql immutable set search_path = '' as $$
  select coalesce(nb.band_hardware_key(p),
    case when p ~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
         then upper(p) end)
$$;
revoke all on function nb.band_key(text) from public, anon, authenticated;

create table nb.device_keys (
  device_id     uuid not null references public.devices (id) on delete cascade,
  band_key      text not null,
  first_seen_at timestamptz not null default now(),
  primary key (device_id, band_key)
);
create index device_keys_band_key_idx on nb.device_keys (band_key);
alter table nb.device_keys enable row level security;
revoke all on table nb.device_keys from public, anon, authenticated;
comment on table nb.device_keys is
  'Every key a devices row has carried (its ble_identifier and each phone''s client_key), normalized by nb.band_key. Decides whose band an upload or a claim names.';

create or replace function nb.devices_remember_keys() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into nb.device_keys (device_id, band_key)
  select new.id, k from (values (nb.band_key(new.ble_identifier)), (nb.band_key(new.client_key))) v(k)
   where k is not null
  on conflict do nothing;
  return null;
end $$;
revoke all on function nb.devices_remember_keys() from public, anon, authenticated;
drop trigger if exists devices_remember_keys on public.devices;
create trigger devices_remember_keys after insert or update of ble_identifier, client_key
  on public.devices for each row execute function nb.devices_remember_keys();

insert into nb.device_keys (device_id, band_key)
select d.id, k from public.devices d
 cross join lateral (values (nb.band_key(d.ble_identifier)), (nb.band_key(d.client_key))) v(k)
 where k is not null
on conflict do nothing;

-- True when another account holds the band `p_key` names and this one does not. An account's
-- own band counts while bound, and after its release for anything that began before the
-- release: a late upload of its own history.
create or replace function nb.band_key_held_elsewhere(p_user uuid, p_key text, p_at timestamptz)
returns boolean language sql stable set search_path = '' as $$
  select coalesce((
    select not exists (
             select 1 from nb.device_keys k join public.devices d on d.id = k.device_id
              where k.band_key = b.key and d.user_id = p_user
                and (d.unbound_at is null or coalesce(p_at, now()) < d.unbound_at))
       and exists (
             select 1 from nb.device_keys k join public.devices d on d.id = k.device_id
              where k.band_key = b.key and d.user_id <> p_user and d.unbound_at is null)
      from (select nb.band_key(p_key) as key) b
     where b.key is not null), false)
$$;
revoke all on function nb.band_key_held_elsewhere(uuid, text, timestamptz) from public, anon, authenticated;

-- A phone claims only its own band's key, through claim_device_key or a direct patch alike.
create or replace function nb.devices_client_key_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.unbound_at is null and nb.band_key_held_elsewhere(new.user_id, new.client_key, null) then
    raise exception 'DEVICE_OWNED_ELSEWHERE' using errcode = '23505',
      hint = 'The band is bound to another account. It has to be released there first.';
  end if;
  return new;
end $$;
revoke all on function nb.devices_client_key_owner() from public, anon, authenticated;
drop trigger if exists devices_client_key_owner on public.devices;
create trigger devices_client_key_owner before insert or update of client_key, unbound_at
  on public.devices for each row execute function nb.devices_client_key_owner();

-- Every domain, delta and bundle upload goes through ingest_band_domain; sleep goes through
-- publish_sleep_night. Both refuse a band another account holds, whichever build sends it.
do $do$
declare
  definition text;
  anchor text := 'begin
  -- Sleep never comes through here;';
begin
  definition := pg_get_functiondef('public.ingest_band_domain(text,text,date,text,timestamptz,timestamptz,jsonb,text,text,timestamptz)'::regprocedure);
  if (length(definition) - length(replace(definition, anchor, ''))) / length(anchor) <> 1 then
    raise exception 'Expected band ingestion entry not found';
  end if;
  execute replace(definition, anchor, $chk$begin
  -- One band, one account (20261024170000).
  if u is not null and nb.band_key_held_elsewhere(u, p_device_key, p_start) then
    raise exception 'DEVICE_OWNED_ELSEWHERE' using errcode = '42501',
      hint = 'The band is bound to another account.';
  end if;
  -- Sleep never comes through here;$chk$);

  definition := pg_get_functiondef('public.publish_sleep_night(jsonb)'::regprocedure);
  anchor := '
  if night.device_key is not null then';
  if (length(definition) - length(replace(definition, anchor, ''))) / length(anchor) <> 1 then
    raise exception 'Expected sleep publication guard not found';
  end if;
  execute replace(definition, anchor, $chk$
  -- One band, one account (20261024170000).
  if nb.band_key_held_elsewhere(u, night.device_key, coalesce(night.wake_at, night.sleep_start)) then
    raise exception 'DEVICE_OWNED_ELSEWHERE' using errcode = '42501',
      hint = 'The band is bound to another account.';
  end if;
  if night.device_key is not null then$chk$);
end $do$;
