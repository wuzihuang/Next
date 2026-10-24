-- Disposable migrated database only; all fixtures roll back.
-- One band, one account, for uploads and claims (20261024170000).
begin;
insert into auth.users(id) values
 ('99999999-9999-4999-9999-999999999941'), ('99999999-9999-4999-9999-999999999942'), ('99999999-9999-4999-9999-999999999943');
insert into public.profiles(user_id,timezone) values
 ('99999999-9999-4999-9999-999999999941','UTC'), ('99999999-9999-4999-9999-999999999942','UTC') on conflict do nothing;
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
 ('99999999-9999-4999-9999-999999999941','test','granted','test','en'),
 ('99999999-9999-4999-9999-999999999942','test','granted','test','en');
-- A third account holds the simulator's mock band, which every demo account shares.
insert into public.devices(user_id, ble_identifier, ble_identifier_kind)
values ('99999999-9999-4999-9999-999999999943', 'C4-2E-8F-1A-73-9D', 'uuid');
select plan(1);
set local role authenticated;
create function pg_temp.assert_keys(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'BAND KEYS: %', message; end if; end $$;
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
-- One origin tick filed under `key`, `ago` before now, in that day's batch.
create function pg_temp.upload(key text, ago interval) returns jsonb language sql as $$
  select public.ingest_band_domain(key, 'origin', (now() - ago)::date, 'UTC',
    date_trunc('day', now() - ago), date_trunc('day', now() - ago) + interval '1 day',
    jsonb_build_array(jsonb_build_object('ts', now() - ago, 'user_id', auth.uid(), 'sampled_tz', 'UTC',
      'src', 'band', 'heart', 72, 'step', 5)))
$$;
do $$
declare
  a_alias constant text := 'A1A1A1A1-0000-4000-8000-000000000041';
  a_second_phone constant text := 'A2A2A2A2-0000-4000-8000-000000000041';
  b_alias constant text := 'B1B1B1B1-0000-4000-8000-000000000042';
  a_row uuid; b_row uuid; b_second uuid; r jsonb;
begin
  perform pg_temp.as_user('99999999-9999-4999-9999-999999999941');
  insert into public.devices(user_id, ble_identifier, ble_identifier_kind, client_key)
  values (auth.uid(), 'AA:BB:CC:DD:EE:41', 'mac', a_alias) returning id into a_row;
  r := pg_temp.upload(a_alias, interval '12 hours');
  perform pg_temp.assert_keys(r->>'inserted' = '1', 'the holder uploads under its phone''s alias');
  r := pg_temp.upload('aa-bb-cc-dd-ee-41', interval '11 hours');
  perform pg_temp.assert_keys(r->>'inserted' = '1', 'and under its MAC in any spelling');

  perform pg_temp.as_user('99999999-9999-4999-9999-999999999942');
  perform pg_temp.assert_keys(pg_temp.fails_with(format('select pg_temp.upload(%L, %L)', a_alias, '12 hours'),
    'DEVICE_OWNED_ELSEWHERE'), 'another account cannot upload under the holder''s alias');
  perform pg_temp.assert_keys(pg_temp.fails_with(format('select pg_temp.upload(%L, %L)', 'aabbccddee41', '12 hours'),
    'DEVICE_OWNED_ELSEWHERE'), 'nor under its MAC');
  perform pg_temp.assert_keys(pg_temp.fails_with(format('select public.publish_sleep_night(%L::jsonb)',
    jsonb_build_object('user_day', (now() - interval '13 hours')::date, 'total_minutes', 400, 'deep_minutes', 90,
      'light_minutes', 300, 'wake_count', 1, 'device_key', a_alias,
      'sleep_start', now() - interval '20 hours', 'wake_at', now() - interval '13 hours')),
    'DEVICE_OWNED_ELSEWHERE'), 'nor file a night under it');
  r := pg_temp.upload('C0C0C0C0-0000-4000-8000-000000000043', interval '12 hours');
  perform pg_temp.assert_keys(r->>'inserted' = '1', 'a key nobody holds is taken as before');
  r := pg_temp.upload('C4-2E-8F-1A-73-9D', interval '10 hours');
  perform pg_temp.assert_keys(r->>'inserted' = '1', 'the mock band is no one''s key');

  -- Nor can it claim the holder's key for a row of its own, by RPC or by patch.
  insert into public.devices(user_id, ble_identifier, ble_identifier_kind)
  values (auth.uid(), 'AA:BB:CC:DD:EE:42', 'mac') returning id into b_row;
  perform pg_temp.assert_keys(pg_temp.fails_with(format('select public.claim_device_key(%L, %L)', b_row, a_alias),
    'DEVICE_OWNED_ELSEWHERE'), 'claim_device_key refuses the holder''s alias');
  perform pg_temp.assert_keys(pg_temp.fails_with(format('update public.devices set client_key = %L where id = %L',
    'AA-BB-CC-DD-EE-41', b_row), 'DEVICE_OWNED_ELSEWHERE'), 'a patch refuses the holder''s MAC');
  perform public.claim_device_key(b_row, b_alias);
  r := pg_temp.upload(b_alias, interval '9 hours');
  perform pg_temp.assert_keys(r->>'inserted' = '1', 'an account uploads under its own claimed key');

  -- A second phone of the holder claims the row; the first phone keeps uploading.
  perform pg_temp.as_user('99999999-9999-4999-9999-999999999941');
  perform public.claim_device_key(a_row, a_second_phone);
  r := pg_temp.upload(a_alias, interval '8 hours');
  perform pg_temp.assert_keys(r->>'inserted' = '1', 'a key the row carried before stays the holder''s');
  perform pg_temp.as_user('99999999-9999-4999-9999-999999999942');
  perform pg_temp.assert_keys(pg_temp.fails_with(format('select pg_temp.upload(%L, %L)', a_second_phone, '12 hours'),
    'DEVICE_OWNED_ELSEWHERE'), 'the second phone''s alias is the holder''s too');

  -- Released, the band moves on; the old holder keeps only its own history.
  perform pg_temp.as_user('99999999-9999-4999-9999-999999999941');
  perform public.release_device(a_row);
  perform pg_temp.as_user('99999999-9999-4999-9999-999999999942');
  insert into public.devices(user_id, ble_identifier, ble_identifier_kind)
  values (auth.uid(), 'AA:BB:CC:DD:EE:41', 'mac') returning id into b_second;
  r := pg_temp.upload('AA:BB:CC:DD:EE:41', interval '7 hours');
  perform pg_temp.assert_keys(r->>'inserted' = '1', 'the next holder uploads under the MAC');
  perform pg_temp.as_user('99999999-9999-4999-9999-999999999941');
  r := pg_temp.upload('AA:BB:CC:DD:EE:41', interval '6 hours');
  perform pg_temp.assert_keys(r->>'inserted' = '1', 'a late upload of the old holder''s own history is taken');
  perform pg_temp.assert_keys(pg_temp.fails_with(format(
    'select public.ingest_band_domain(%L, %L, current_date, %L, now() + interval %L, now() + interval %L, %L::jsonb)',
    'AA:BB:CC:DD:EE:41', 'origin', 'UTC', '1 minute', '1 hour', '[]'), 'DEVICE_OWNED_ELSEWHERE'),
    'but nothing that begins after the release');
end $$;
reset role;
select pg_temp.assert_keys(not has_table_privilege('authenticated', 'nb.device_keys', 'select')
  and not has_function_privilege('authenticated', 'nb.band_key_held_elsewhere(uuid,text,timestamptz)', 'execute'),
  'the key history is private');
select pg_temp.assert_keys(nb.band_key('aa:bb:cc:dd:ee:41') = 'AABBCCDDEE41'
  and nb.band_key('a1a1a1a1-0000-4000-8000-000000000041') = 'A1A1A1A1-0000-4000-8000-000000000041'
  and nb.band_key('C4-2E-8F-1A-73-9D') is null and nb.band_key('release-A') is null and nb.band_key(null) is null,
  'a key is a MAC or a CoreBluetooth UUID, and the mock band is neither');
select pass('a band another account holds is refused for uploads, nights and claims');
select * from finish();
rollback;
