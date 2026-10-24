-- Disposable migrated database only; all fixtures roll back.
-- DELETE EVERYTHING (20261024120000): one delete of the auth user takes every row the account
-- has, because every table that names a user cascades from auth.users.
begin;
insert into auth.users(id) values ('99999999-9999-4999-9999-999999999931'), ('99999999-9999-4999-9999-999999999932');
insert into public.profiles(user_id,timezone) values
 ('99999999-9999-4999-9999-999999999931','UTC'), ('99999999-9999-4999-9999-999999999932','UTC') on conflict do nothing;
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
 ('99999999-9999-4999-9999-999999999931','test','granted','test','en'),
 ('99999999-9999-4999-9999-999999999932','test','granted','test','en');
select plan(1);
create function pg_temp.assert_purge(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'PURGE ACCOUNT: %', message; end if; end $$;
create function pg_temp.fails_with(statement text, expected text) returns boolean language plpgsql as $$
begin
  execute statement;
  return false;
exception when others then
  return sqlerrm = expected;
end $$;
-- Every row that names the account by user_id, in any public or nb table.
create function pg_temp.rows_of(u uuid) returns bigint language plpgsql as $$
declare t record; n bigint; total bigint := 0;
begin
  for t in select c.table_schema, c.table_name from information_schema.columns c
             join information_schema.tables tb on tb.table_schema = c.table_schema and tb.table_name = c.table_name
            where c.column_name = 'user_id' and c.table_schema in ('public','nb') and tb.table_type = 'BASE TABLE' loop
    execute format('select count(*) from %I.%I where user_id = $1', t.table_schema, t.table_name) into n using u;
    total := total + n;
  end loop;
  return total;
end $$;
-- A band and a few minutes of it, through the same calls the phone makes.
create function pg_temp.wear(u text, mac text) returns void language plpgsql as $$
declare at timestamptz := now() - interval '12 hours';
begin
  perform set_config('request.jwt.claim.sub', u, true);
  insert into public.devices(user_id, ble_identifier, ble_identifier_kind) values (auth.uid(), mac, 'mac');
  perform public.ingest_band_domain(mac, 'origin', at::date, 'UTC', date_trunc('day', at), date_trunc('day', at) + interval '1 day',
    (select jsonb_agg(jsonb_build_object('ts', at + m * interval '5 minutes', 'user_id', auth.uid(), 'sampled_tz', 'UTC',
       'src', 'band', 'heart', 70 + m, 'step', 10 * m)) from generate_series(0, 5) m));
end $$;

-- The purge relies on the cascade, so a table that names a user without it fails here first.
select pg_temp.assert_purge(not exists (
  select 1 from pg_attribute a
    join pg_class cl on cl.oid = a.attrelid and cl.relkind in ('r','p') and not cl.relispartition
    join pg_namespace n on n.oid = cl.relnamespace and n.nspname in ('public','nb')
   where a.attname = 'user_id' and not a.attisdropped
     and not exists (select 1 from pg_constraint con where con.conrelid = cl.oid and con.contype = 'f'
                       and con.confrelid = 'auth.users'::regclass and con.confdeltype = 'c'
                       and a.attnum = any(con.conkey))), 'every user_id column cascades from auth.users');
select pg_temp.assert_purge(not exists (
  select 1 from pg_constraint con join pg_namespace n on n.oid = con.connamespace
   where con.contype = 'f' and con.confrelid = 'auth.users'::regclass and n.nspname in ('public','nb')
     and con.confdeltype <> 'c'), 'every reference to auth.users cascades');

set local role authenticated;
select pg_temp.wear('99999999-9999-4999-9999-999999999931', 'AA:BB:CC:DD:EE:31');
select pg_temp.wear('99999999-9999-4999-9999-999999999932', 'AA:BB:CC:DD:EE:32');
reset role;
create temp table kept as select pg_temp.rows_of('99999999-9999-4999-9999-999999999932') as n;
select pg_temp.assert_purge(pg_temp.rows_of('99999999-9999-4999-9999-999999999931') > 10
  and (select n from kept) > 10, 'both accounts hold rows before the purge');
select pg_temp.assert_purge(exists (select 1 from public.raw_samples where user_id = '99999999-9999-4999-9999-999999999931'),
  'the purged account has band samples');

set local role service_role;
select pg_temp.assert_purge(public.purge_account('99999999-9999-4999-9999-999999999931')->>'deleted' = 'true',
  'the purge reports the account gone');
reset role;
select pg_temp.assert_purge(not exists (select 1 from auth.users where id = '99999999-9999-4999-9999-999999999931'),
  'the auth user is gone');
select pg_temp.assert_purge(pg_temp.rows_of('99999999-9999-4999-9999-999999999931') = 0,
  'no table keeps a row of the account');
select pg_temp.assert_purge(not exists (select 1 from public.devices d where d.ble_identifier = 'AA:BB:CC:DD:EE:31'),
  'its band is free again');
select pg_temp.assert_purge(pg_temp.rows_of('99999999-9999-4999-9999-999999999932') = (select n from kept),
  'the other account is untouched');
select pg_temp.assert_purge(not exists (select 1 from nb.calculation_maintenance), 'the maintenance window is closed');

select pg_temp.assert_purge(not has_function_privilege('anon', 'public.purge_account(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.purge_account(uuid)', 'execute')
  and has_function_privilege('service_role', 'public.purge_account(uuid)', 'execute'), 'only the service role may purge');
select pg_temp.assert_purge(pg_temp.fails_with('select public.purge_account(null)', 'UNAUTHENTICATED'), 'a missing owner is refused');
select pass('DELETE EVERYTHING takes every row of the account and nothing else');
select * from finish();
rollback;
