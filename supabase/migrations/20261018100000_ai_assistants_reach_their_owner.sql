-- ADR 0032 · A person can connect ChatGPT, Claude, Cursor or Grok to their own data over MCP.
-- Supabase Auth's OAuth 2.1 server issues the assistant an ordinary Supabase JWT plus a
-- `client_id` claim. Ordinary means it would open every table and Edge Function the app can
-- reach, so three walls keep it to the `mcp` Edge Function's reads and meal writes:
--   1. `mcp_grants`: the consent page records each approval; no live row, no access, and
--      `can_write` decides meal writes. Revoking here takes effect on the next request,
--      not when the hour-long access token expires.
--   2. `mcp_request_gate`: PostgREST's pre-request hook. A token carrying `client_id` may
--      only GET the tables the MCP reads and POST the RPCs it calls. App sessions carry
--      no `client_id` and pass straight through.
--   3. Storage refuses OAuth tokens outright (meal photos, sample archives).

create table public.mcp_grants (
  user_id      uuid not null references auth.users (id) on delete cascade,
  client_id    text not null check (length(client_id) between 1 and 128),
  client_name  text not null default '' check (length(client_name) <= 200),
  can_write    boolean not null default false,
  granted_at   timestamptz not null default now(),
  revoked_at   timestamptz,
  last_used_at timestamptz,
  primary key (user_id, client_id)
);
alter table public.mcp_grants enable row level security;
revoke all on public.mcp_grants from public, anon, authenticated;
grant select on public.mcp_grants to authenticated;
create policy mcp_grants_select on public.mcp_grants for select to authenticated
  using (user_id = (select auth.uid()));

-- Recording, toggling and revoking are first-party acts: an assistant cannot widen its own grant.
create or replace function public.record_mcp_grant(p_client_id text, p_client_name text, p_can_write boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'UNAUTHENTICATED' using errcode = '28000'; end if;
  if nullif(auth.jwt() ->> 'client_id', '') is not null then
    raise exception 'FIRST_PARTY_ONLY' using errcode = '42501';
  end if;
  if p_client_id is null or length(p_client_id) not between 1 and 128 then
    raise exception 'INVALID_CLIENT' using errcode = '22023';
  end if;
  if exists (select 1 from public.profiles where user_id = v_user and deletion_requested_at is not null) then
    raise exception 'ACCOUNT_DELETING' using errcode = '42501';
  end if;
  insert into public.mcp_grants (user_id, client_id, client_name, can_write)
  values (v_user, p_client_id, left(coalesce(p_client_name, ''), 200), coalesce(p_can_write, false))
  on conflict (user_id, client_id) do update set
    client_name = excluded.client_name, can_write = excluded.can_write,
    granted_at = now(), revoked_at = null;
  return jsonb_build_object('client_id', p_client_id, 'can_write', coalesce(p_can_write, false));
end $$;

create or replace function public.set_mcp_grant_write(p_client_id text, p_can_write boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'UNAUTHENTICATED' using errcode = '28000'; end if;
  if nullif(auth.jwt() ->> 'client_id', '') is not null then
    raise exception 'FIRST_PARTY_ONLY' using errcode = '42501';
  end if;
  update public.mcp_grants set can_write = coalesce(p_can_write, false)
    where user_id = v_user and client_id = p_client_id and revoked_at is null;
  if not found then raise exception 'MCP_GRANT_MISSING' using errcode = 'P0002'; end if;
  return jsonb_build_object('client_id', p_client_id, 'can_write', coalesce(p_can_write, false));
end $$;

create or replace function public.revoke_mcp_grant(p_client_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'UNAUTHENTICATED' using errcode = '28000'; end if;
  if nullif(auth.jwt() ->> 'client_id', '') is not null then
    raise exception 'FIRST_PARTY_ONLY' using errcode = '42501';
  end if;
  update public.mcp_grants set revoked_at = coalesce(revoked_at, now()), can_write = false
    where user_id = v_user and client_id = p_client_id;
  return jsonb_build_object('client_id', p_client_id, 'revoked', found);
end $$;

-- The MCP function's one call per request: is this assistant still allowed, may it write,
-- and what does the account's access look like right now.
create or replace function public.touch_mcp_grant()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_client text := nullif(auth.jwt() ->> 'client_id', '');
  v_grant public.mcp_grants%rowtype;
begin
  if v_user is null then raise exception 'UNAUTHENTICATED' using errcode = '28000'; end if;
  if v_client is null then raise exception 'OAUTH_CLIENT_ONLY' using errcode = '42501'; end if;
  select * into v_grant from public.mcp_grants
    where user_id = v_user and client_id = v_client and revoked_at is null;
  if not found then raise exception 'MCP_GRANT_MISSING' using errcode = '42501'; end if;
  update public.mcp_grants set last_used_at = now()
    where user_id = v_user and client_id = v_client
      and (last_used_at is null or last_used_at < now() - interval '1 minute');
  return jsonb_build_object(
    'client_id', v_client,
    'client_name', v_grant.client_name,
    'can_write', v_grant.can_write,
    'timezone', (select timezone from public.profiles where user_id = v_user),
    'deleting', exists (select 1 from public.profiles where user_id = v_user and deletion_requested_at is not null),
    'consent', coalesce((select choice from public.consents where user_id = v_user
      order by decided_at desc, id desc limit 1), ''));
end $$;

revoke all on function public.record_mcp_grant(text, text, boolean) from public, anon;
revoke all on function public.set_mcp_grant_write(text, boolean) from public, anon;
revoke all on function public.revoke_mcp_grant(text) from public, anon;
revoke all on function public.touch_mcp_grant() from public, anon;
grant execute on function public.record_mcp_grant(text, text, boolean) to authenticated;
grant execute on function public.set_mcp_grant_write(text, boolean) to authenticated;
grant execute on function public.revoke_mcp_grant(text) to authenticated;
grant execute on function public.touch_mcp_grant() to authenticated;

-- ⚠️ Runs before every PostgREST request, app traffic included. The first branch must stay
-- the cheapest possible exit for a token without `client_id`, and nothing here may throw
-- for anon or app sessions.
-- The table list is also the embed surface: PostgREST can embed a table related by foreign
-- key, so none of these tables may gain a foreign key from conversation or AI tables
-- (supabase/tests/mcp_request_gate.sql checks this).
create or replace function public.mcp_request_gate()
returns void language plpgsql stable security definer set search_path = '' as $$
declare
  v_claims jsonb;
  v_client text;
  v_user uuid;
  v_write boolean;
  v_path text;
  v_method text;
begin
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  v_client := nullif(v_claims ->> 'client_id', '');
  if v_client is null then return; end if;
  begin
    v_user := (v_claims ->> 'sub')::uuid;
  exception when others then
    raise exception 'MCP_GRANT_MISSING' using errcode = '42501';
  end;
  select can_write into v_write from public.mcp_grants
    where user_id = v_user and client_id = v_client and revoked_at is null;
  if not found then raise exception 'MCP_GRANT_MISSING' using errcode = '42501'; end if;
  v_path := coalesce(current_setting('request.path', true), '');
  v_method := upper(coalesce(current_setting('request.method', true), ''));
  if v_method in ('GET', 'HEAD') and v_path in (
    '/daily_results', '/weigh_ins', '/body_composition', '/sleep_nights', '/night_score',
    '/oxygen_samples', '/raw_samples', '/meals') then
    return;
  end if;
  if v_method in ('GET', 'POST') and v_path in (
    '/rpc/touch_mcp_grant', '/rpc/consume_request_budget', '/rpc/calculation_status') then
    return;
  end if;
  if v_method = 'POST' and v_path in ('/rpc/apply_meal_plate', '/rpc/apply_meal_operation', '/rpc/settle_now') then
    if v_write then return; end if;
    raise exception 'MCP_WRITE_NOT_GRANTED' using errcode = '42501';
  end if;
  raise exception 'MCP_PATH_NOT_ALLOWED' using errcode = '42501';
end $$;
revoke all on function public.mcp_request_gate() from public;
grant execute on function public.mcp_request_gate() to anon, authenticated, service_role;

alter role authenticator set pgrst.db_pre_request = 'public.mcp_request_gate';
notify pgrst, 'reload config';

create policy oauth_clients_have_no_storage on storage.objects as restrictive for all to authenticated
  using (nullif((select auth.jwt()) ->> 'client_id', '') is null)
  with check (nullif((select auth.jwt()) ->> 'client_id', '') is null);

-- The budget function has been text-patched by several migrations; patch, do not restate.
do $do$
declare definition text; patched text;
begin
  select pg_get_constraintdef(oid) into definition from pg_constraint
    where conrelid = 'nb.request_budgets'::regclass and conname = 'request_budgets_endpoint_check';
  if position('''mcp''' in definition) = 0 then
    patched := replace(definition, '''feedback''::text', '''feedback''::text, ''mcp''::text');
    if patched = definition then raise exception 'REQUEST_BUDGET_CONSTRAINT_ANCHOR_MISSING'; end if;
    execute 'alter table nb.request_budgets drop constraint request_budgets_endpoint_check';
    execute 'alter table nb.request_budgets add constraint request_budgets_endpoint_check ' || patched;
  end if;
  definition := pg_get_functiondef('nb.consume_request_budget(uuid,text)'::regprocedure);
  if position('''mcp''' in definition) = 0 then
    patched := replace(definition, 'when ''feedback'' then 5', 'when ''feedback'' then 5 when ''mcp'' then 60');
    if patched = definition then raise exception 'REQUEST_BUDGET_ANCHOR_MISSING'; end if;
    execute patched;
  end if;
end $do$;
