-- ADR 0032 · an assistant's OAuth token reaches only what the `mcp` function needs.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(25);

insert into auth.users(id) values ('ac000000-0000-4000-8000-000000000001');

create function pg_temp.as_request(p_claims jsonb, p_method text, p_path text) returns void
language sql as $$
  select set_config('request.jwt.claims', coalesce(p_claims::text, ''), true),
         set_config('request.method', p_method, true),
         set_config('request.path', p_path, true);
$$;

select is(
  (select rolconfig @> array['pgrst.db_pre_request=public.mcp_request_gate'] from pg_roles where rolname = 'authenticator'),
  true, 'PostgREST runs the gate before every request');

set local role authenticated;

-- App sessions and anonymous requests are never touched.
select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated"}', 'GET', '/conversations');
select lives_ok($$select public.mcp_request_gate()$$, 'an app session passes on any path');
select pg_temp.as_request(null, 'POST', '/rpc/anything');
select lives_ok($$select public.mcp_request_gate()$$, 'a request without claims passes');
select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","client_id":""}', 'GET', '/conversations');
select lives_ok($$select public.mcp_request_gate()$$, 'an empty client_id is an app session');

-- An assistant with no recorded grant reaches nothing.
select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated","client_id":"gpt"}', 'GET', '/daily_results');
select throws_ok($$select public.mcp_request_gate()$$, '42501', 'MCP_GRANT_MISSING', 'no grant, no reads');
select throws_ok($$select public.touch_mcp_grant()$$, '42501', 'MCP_GRANT_MISSING', 'no grant, no touch');
select throws_ok($$select public.record_mcp_grant('gpt', 'ChatGPT', true)$$, '42501', 'FIRST_PARTY_ONLY',
  'an assistant cannot grant itself access');

-- The consent page, on the app account's own session, records a read-only grant.
select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated"}', 'POST', '/rpc/record_mcp_grant');
select is((public.record_mcp_grant('gpt', 'ChatGPT', false)) ->> 'can_write', 'false', 'the consent page records the grant');
select throws_ok($$select public.touch_mcp_grant()$$, '42501', 'OAUTH_CLIENT_ONLY', 'an app session is not an assistant');
select is((select count(*) from public.mcp_grants), 1::bigint, 'the owner can see the grant');

select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated","client_id":"gpt"}', 'GET', '/daily_results');
select lives_ok($$select public.mcp_request_gate()$$, 'reads the MCP needs are allowed');
select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated","client_id":"gpt"}', 'GET', '/meals');
select lives_ok($$select public.mcp_request_gate()$$, 'meals can be read');
select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated","client_id":"gpt"}', 'GET', '/conversations');
select throws_ok($$select public.mcp_request_gate()$$, '42501', 'MCP_PATH_NOT_ALLOWED', 'AI conversations are out of reach');
select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated","client_id":"gpt"}', 'PATCH', '/meals');
select throws_ok($$select public.mcp_request_gate()$$, '42501', 'MCP_PATH_NOT_ALLOWED', 'tables are never written directly');
select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated","client_id":"gpt"}', 'POST', '/rpc/export_all');
select throws_ok($$select public.mcp_request_gate()$$, '42501', 'MCP_PATH_NOT_ALLOWED', 'the full export is out of reach');
select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated","client_id":"gpt"}', 'POST', '/rpc/apply_meal_plate');
select throws_ok($$select public.mcp_request_gate()$$, '42501', 'MCP_WRITE_NOT_GRANTED', 'meal writes need the write grant');
select is((public.touch_mcp_grant()) ->> 'can_write', 'false', 'touch reports the grant as read-only');

-- The owner turns meal logging on in the app.
select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated"}', 'POST', '/rpc/set_mcp_grant_write');
select lives_ok($$select public.set_mcp_grant_write('gpt', true)$$, 'the owner allows meal logging');
select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated","client_id":"gpt"}', 'POST', '/rpc/apply_meal_plate');
select lives_ok($$select public.mcp_request_gate()$$, 'meal writes pass with the write grant');
select throws_ok($$select public.set_mcp_grant_write('gpt', true)$$, '42501', 'FIRST_PARTY_ONLY',
  'an assistant cannot change its own grant');

-- Revoking in the app shuts the next request, before the access token expires.
select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated"}', 'POST', '/rpc/revoke_mcp_grant');
select is((public.revoke_mcp_grant('gpt')) ->> 'revoked', 'true', 'the owner revokes');
select pg_temp.as_request('{"sub":"ac000000-0000-4000-8000-000000000001","role":"authenticated","client_id":"gpt"}', 'GET', '/daily_results');
select throws_ok($$select public.mcp_request_gate()$$, '42501', 'MCP_GRANT_MISSING', 'a revoked grant reaches nothing');

reset role;

-- PostgREST can embed any table related by foreign key; the readable tables must not lead
-- to conversation, memory or other AI tables.
select set_eq(
  $$select distinct c.conrelid::regclass::text from pg_constraint c
    where c.contype = 'f' and c.confrelid in (
      'public.daily_results'::regclass, 'public.weigh_ins'::regclass, 'public.body_composition'::regclass,
      'public.sleep_nights'::regclass, 'public.night_score'::regclass, 'public.oxygen_samples'::regclass,
      'public.raw_samples'::regclass, 'public.meals'::regclass,
      'public.response_samples'::regclass, 'public.balance_checks'::regclass,
      'public.sport_session_recaps'::regclass, 'public.manual_sport_sessions'::regclass,
      'public.sport_heart_rate_samples'::regclass, 'public.sport_energy_samples'::regclass,
      'public.reserve_samples'::regclass, 'public.night_hrv'::regclass)$$,
  $$select unnest(array['day_fuel', 'daily_training', 'reserve_daily', 'body_composition'])$$,
  'only the settlement children and body composition hang off the readable tables');

select ok((nb.consume_request_budget('ac000000-0000-4000-8000-000000000001', 'mcp') ->> 'allowed')::boolean,
  'the mcp endpoint has a request budget');

select is(
  (select permissive from pg_policies where schemaname = 'storage' and tablename = 'objects'
     and policyname = 'oauth_clients_have_no_storage'),
  'RESTRICTIVE', 'storage refuses assistant tokens');

select * from finish();
rollback;
