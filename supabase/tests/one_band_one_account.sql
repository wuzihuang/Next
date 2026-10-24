-- Disposable migrated database only; all fixtures roll back.
begin;
insert into auth.users(id) values ('99999999-9999-4999-9999-999999999911'), ('99999999-9999-4999-9999-999999999912');
select plan(1);
set local role authenticated;
create function pg_temp.assert_owner(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'ONE BAND ONE ACCOUNT: %', message; end if; end $$;
create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u, true)
$$;
create function pg_temp.fails_with(statement text, expected text) returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then
  return sqlerrm = expected;
end $$;
do $$
declare a_row uuid; b_row uuid; seed_a uuid; seed_b uuid;
begin
  perform pg_temp.as_user('99999999-9999-4999-9999-999999999911');
  insert into public.devices(user_id, ble_identifier, ble_identifier_kind)
  values (auth.uid(), 'AA:BB:CC:DD:EE:01', 'mac') returning id into a_row;
  perform pg_temp.assert_owner((select hardware_key from public.devices where id = a_row) = 'AABBCCDDEE01',
    'the MAC is normalized into the hardware key');
  -- The same band in the account's other slot is one band, not two.
  perform pg_temp.assert_owner(pg_temp.fails_with(
    format('insert into public.devices(user_id, ble_identifier, ble_identifier_kind, slot) values (%L, %L, %L, %L)',
           auth.uid(), 'aa-bb-cc-dd-ee-01', 'mac', 'B'), 'DEVICE_ALREADY_IN_SET'),
    'one band cannot fill both slots');

  perform pg_temp.as_user('99999999-9999-4999-9999-999999999912');
  -- Another account cannot bind it, whatever the separator or case.
  perform pg_temp.assert_owner(pg_temp.fails_with(
    format('insert into public.devices(user_id, ble_identifier, ble_identifier_kind) values (%L, %L, %L)',
           auth.uid(), 'aabbccddee01', 'mac'), 'DEVICE_OWNED_ELSEWHERE'),
    'a second account cannot bind a held band');
  insert into public.devices(user_id, ble_identifier, ble_identifier_kind)
  values (auth.uid(), 'AA:BB:CC:DD:EE:02', 'mac') returning id into b_row;
  -- Nor can it re-point its own row at the held band.
  perform pg_temp.assert_owner(pg_temp.fails_with(
    format('update public.devices set ble_identifier = %L where id = %L', 'AA:BB:CC:DD:EE:01', b_row),
    'DEVICE_OWNED_ELSEWHERE'), 'a patch cannot take a held band');
  -- The derived key cannot be written by hand to slip past the rule.
  update public.devices set hardware_key = null where id = b_row;
  perform pg_temp.assert_owner((select hardware_key from public.devices where id = b_row) = 'AABBCCDDEE02',
    'hardware_key always follows ble_identifier');
  -- The simulator seed is everyone's.
  insert into public.devices(user_id, ble_identifier, ble_identifier_kind, slot)
  values (auth.uid(), 'C4-2E-8F-1A-73-9D', 'uuid', 'B') returning id into seed_b;
  perform pg_temp.as_user('99999999-9999-4999-9999-999999999911');
  insert into public.devices(user_id, ble_identifier, ble_identifier_kind, slot)
  values (auth.uid(), 'C4-2E-8F-1A-73-9D', 'uuid', 'B') returning id into seed_a;
  perform pg_temp.assert_owner(seed_a is not null and seed_b is not null, 'the seed band is shared');

  -- Releasing hands the band back to nobody; then anyone may bind it.
  perform public.release_device(a_row);
  perform pg_temp.as_user('99999999-9999-4999-9999-999999999912');
  update public.devices set ble_identifier = 'AA:BB:CC:DD:EE:01' where id = b_row;
  perform pg_temp.assert_owner((select hardware_key from public.devices where id = b_row) = 'AABBCCDDEE01',
    'a released band can be bound by the next account');
  -- The first account cannot revive its released row over the new holder.
  perform pg_temp.as_user('99999999-9999-4999-9999-999999999911');
  perform pg_temp.assert_owner(pg_temp.fails_with(
    format('update public.devices set unbound_at = null where id = %L', a_row), 'DEVICE_OWNED_ELSEWHERE'),
    'a released row cannot be revived over the new holder');
end $$;
reset role;
-- Old rows keyed by a CoreBluetooth UUID carry no hardware key and are not compared.
select pg_temp.assert_owner(nb.band_hardware_key('6F1C2C9E-3A4B-4C5D-8E9F-0A1B2C3D4E5F') is null
  and nb.band_hardware_key('—') is null, 'a UUID or placeholder is not a hardware key');
select pass('one band is held by one account');
select * from finish();
rollback;
