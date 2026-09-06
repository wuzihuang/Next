-- ADR 0018 · read → act → render.
--
-- Four things the turn did not have: a memory of the person, a session to summarize it
-- from, a plan row per user day with the user's own ticks, and a parking place for a turn
-- that is waiting on the phone. Everything the model reads still goes through the caller's
-- JWT; the parking place and the memory writer are the only service-role paths.

-- ---------------------------------------------------------------- memory

create table public.user_memory (
  user_id        uuid primary key references auth.users (id) on delete cascade,
  summary        text not null default '',
  facts          jsonb not null default '[]'::jsonb,
  token_estimate integer not null default 0,
  updated_at     timestamptz not null default now()
);
alter table public.user_memory enable row level security;
-- The person may read and erase it. Only the summarizer writes it.
create policy user_memory_select on public.user_memory for select to authenticated using (user_id = auth.uid());
create policy user_memory_delete on public.user_memory for delete to authenticated using (user_id = auth.uid());
grant select, delete on public.user_memory to authenticated;

-- Withdrawing consent erases the memory: it was distilled from health conversations.
create or replace function nb.forget_on_consent_withdrawn() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.choice <> 'granted' then
    delete from public.user_memory where user_id = new.user_id;
  end if;
  return new;
end $$;
drop trigger if exists consents_forget_memory on public.consents;
create trigger consents_forget_memory after insert on public.consents
  for each row execute function nb.forget_on_consent_withdrawn();

-- ---------------------------------------------------------------- sessions

create table public.ai_sessions (
  id            uuid primary key,
  user_id       uuid not null references auth.users (id) on delete cascade,
  surface       text not null check (surface in ('panel', 'chat', 'plan')),
  started_at    timestamptz not null default now(),
  last_turn_at  timestamptz not null default now(),
  closed_at     timestamptz,
  summarized_at timestamptz
);
create index ai_sessions_user_open_idx on public.ai_sessions (user_id, last_turn_at desc) where summarized_at is null;
alter table public.ai_sessions enable row level security;
create policy ai_sessions_select on public.ai_sessions for select to authenticated using (user_id = auth.uid());
grant select on public.ai_sessions to authenticated;

alter table public.ai_turns add column if not exists session_id uuid;
create index if not exists ai_turns_session_idx on public.ai_turns (session_id, created_at);

-- Called at the top of every turn. Bookkeeping, never a gate.
create function public.touch_ai_session(p_session uuid, p_surface text)
returns void language plpgsql security definer set search_path='' as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  if p_session is null or p_surface not in ('panel','chat','plan') then raise exception 'INVALID_SESSION' using errcode='22023'; end if;
  insert into public.ai_sessions (id, user_id, surface) values (p_session, u, p_surface)
  on conflict (id) do update set last_turn_at = now(), closed_at = null
  where public.ai_sessions.user_id = u and public.ai_sessions.summarized_at is null;
end $$;

create function public.attach_turn_session(p_turn uuid, p_session uuid)
returns void language plpgsql security definer set search_path='' as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  update public.ai_turns set session_id = p_session where id = p_turn and user_id = u
    and exists (select 1 from public.ai_sessions where id = p_session and user_id = u);
end $$;

-- The phone closes a session when the user leaves Chat. Idle sessions close on their own
-- in ai_sessions_due.
create function public.close_ai_session(p_session uuid)
returns void language plpgsql security definer set search_path='' as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  update public.ai_sessions set closed_at = coalesce(closed_at, now()) where id = p_session and user_id = u;
end $$;

-- Sessions the summarizer should fold into memory: closed, or idle for p_idle_minutes,
-- and not yet summarized. Sessions with no persisted turn are dropped instead.
create function public.ai_sessions_due(p_idle_minutes integer default 30)
returns setof uuid language plpgsql security definer set search_path='' as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  delete from public.ai_sessions s where s.user_id = u and s.summarized_at is null
    and s.last_turn_at < now() - interval '1 day'
    and not exists (select 1 from public.ai_turns t where t.session_id = s.id);
  return query select s.id from public.ai_sessions s where s.user_id = u and s.summarized_at is null
    and (s.closed_at is not null or s.last_turn_at < now() - make_interval(mins => greatest(1, p_idle_minutes)))
    and exists (select 1 from public.ai_turns t where t.session_id = s.id)
    order by s.last_turn_at limit 5;
end $$;

-- The transcript the summarizer reads: the user's words and the frame's text slots, in order.
create function public.ai_session_transcript(p_session uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid := auth.uid(); v jsonb;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  if not exists (select 1 from public.ai_sessions where id = p_session and user_id = u) then
    raise exception 'SESSION_NOT_FOUND' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'at', to_char(t.created_at, 'YYYY-MM-DD'),
      'source', coalesce(s.surface, 'panel'),
      'user', left(t.user_text, 2000),
      'assistant', left(concat_ws(' · ', f.widget_tree->>'title', f.widget_tree->>'sentence', f.widget_tree->'data'->>'sub',
        f.widget_tree->'data'->>'summary', f.widget_tree->>'footer'), 4000)
    ) order by t.created_at), '[]'::jsonb) into v
  from public.ai_turns t
  join public.ai_sessions s on s.id = t.session_id
  left join public.screen_frames f on f.id = t.frame_id
  where t.session_id = p_session and t.user_id = u;
  return v;
end $$;

revoke all on function public.touch_ai_session(uuid,text), public.attach_turn_session(uuid,uuid),
  public.close_ai_session(uuid), public.ai_sessions_due(integer), public.ai_session_transcript(uuid) from public, anon;
grant execute on function public.touch_ai_session(uuid,text), public.attach_turn_session(uuid,uuid),
  public.close_ai_session(uuid), public.ai_sessions_due(integer), public.ai_session_transcript(uuid) to authenticated;

-- The summarizer (service role, owner-scoped) writes memory and stamps the session.
create function public.write_user_memory_trusted(p_owner uuid, p_session uuid, p_summary text, p_facts jsonb, p_tokens integer)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_owner is null or not exists (select 1 from auth.users where id = p_owner) then
    raise exception 'UNAUTHENTICATED' using errcode='28000';
  end if;
  if p_summary is null or length(p_summary) > 4000 or p_facts is null or jsonb_typeof(p_facts) <> 'array' then
    raise exception 'INVALID_MEMORY' using errcode='22023';
  end if;
  -- Consent may have been withdrawn while the model ran: the trigger erased the memory and
  -- this write must not bring it back.
  if (select choice from public.consents where user_id = p_owner order by decided_at desc, id desc limit 1) is distinct from 'granted' then
    update public.ai_sessions set summarized_at = now() where id = p_session and user_id = p_owner;
    return;
  end if;
  insert into public.user_memory (user_id, summary, facts, token_estimate, updated_at)
  values (p_owner, p_summary, p_facts, coalesce(p_tokens, 0), now())
  on conflict (user_id) do update set summary = excluded.summary, facts = excluded.facts,
    token_estimate = excluded.token_estimate, updated_at = now();
  update public.ai_sessions set summarized_at = now(), closed_at = coalesce(closed_at, now())
    where id = p_session and user_id = p_owner;
end $$;
revoke all on function public.write_user_memory_trusted(uuid,uuid,text,jsonb,integer) from public, anon, authenticated;
grant execute on function public.write_user_memory_trusted(uuid,uuid,text,jsonb,integer) to service_role;

-- The summary call is accounted like any model call, under its own endpoint.
alter table nb.ai_model_calls drop constraint if exists ai_model_calls_endpoint_check;
alter table nb.ai_model_calls add constraint ai_model_calls_endpoint_check check (endpoint in ('turn','meal','asr','memory'));

create or replace function public.record_ai_usage_trusted(
 p_owner uuid,p_endpoint text,p_model text,p_prompt integer,p_cached integer,
 p_completion integer,p_turn uuid,p_latency integer,p_audio_seconds numeric default 0
) returns void language plpgsql security definer set search_path='' as $$
declare book nb.ai_price_book%rowtype; fen numeric(20,6); today date;
begin
 if p_owner is null or not exists(select 1 from auth.users where id=p_owner) then
  raise exception 'UNAUTHENTICATED' using errcode='28000';
 end if;
 if p_endpoint not in ('turn','meal','asr','memory') then raise exception 'UNKNOWN_ENDPOINT' using errcode='22023'; end if;
 if p_prompt is null or p_cached is null or p_completion is null or least(p_prompt,p_cached,p_completion)<0 then
  raise exception 'INVALID_USAGE' using errcode='22023';
 end if;
 if p_audio_seconds is null or p_audio_seconds<0 then raise exception 'INVALID_USAGE' using errcode='22023'; end if;
 select * into book from nb.ai_price_book where model_id=p_model;
 if not found and p_model like 'qwen3-asr-flash-%' then
  select * into book from nb.ai_price_book where model_id=case
   when p_model like 'qwen3-asr-flash-realtime-%' then 'qwen3-asr-flash-realtime' else 'qwen3-asr-flash' end;
 end if;
 if not found then select * into book from nb.ai_price_book where model_id='*'; end if;
 -- Cast before multiplication: big model/token counts must not overflow int4.
 fen:=(p_prompt::numeric*book.prompt_fen_per_million + p_cached::numeric*book.cached_fen_per_million
   + p_completion::numeric*book.completion_fen_per_million)/1000000 + p_audio_seconds*book.audio_fen_per_second;
 today:=nb.user_day(p_owner);
 insert into nb.ai_model_calls(user_id,user_day,endpoint,turn_id,model_id,prompt_tokens,cached_tokens,completion_tokens,cost_fen,latency_ms,audio_seconds)
 values(p_owner,today,p_endpoint,p_turn,p_model,p_prompt,p_cached,p_completion,fen,p_latency,p_audio_seconds);
 -- A row born here takes the same defaults as one born in the admission path.
 insert into nb.ai_quotas(user_id,settled_day,spent_fen,spent_day)
 values(p_owner,today,fen,today)
 on conflict(user_id) do update set
 spent_fen=case when nb.ai_quotas.spent_day=today then nb.ai_quotas.spent_fen+fen else fen end,
 spent_day=today;
end $$;

-- ---------------------------------------------------------------- plans

create table public.daily_plans (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  user_day      date not null,
  title         text not null check (length(title) <= 40),
  summary       text not null check (length(summary) <= 400),
  tasks         jsonb not null check (jsonb_typeof(tasks) = 'array' and jsonb_array_length(tasks) between 1 and 5),
  read_from     date not null,
  read_to       date not null,
  -- No foreign key: plan.render runs inside the turn, before the ai_turns row is written.
  turn_id       uuid,
  model_version text,
  created_at    timestamptz not null default now(),
  unique (user_id, user_day)
);
alter table public.daily_plans enable row level security;
create policy daily_plans_select on public.daily_plans for select to authenticated using (user_id = auth.uid());
create policy daily_plans_insert on public.daily_plans for insert to authenticated with check (user_id = auth.uid());
create policy daily_plans_update on public.daily_plans for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update on public.daily_plans to authenticated;

-- A tick is the user's own claim, one per task per day. The next day's plan reads it.
create table public.plan_task_checks (
  user_id    uuid not null references auth.users (id) on delete cascade,
  user_day   date not null,
  task_id    text not null check (length(task_id) <= 24),
  checked_at timestamptz not null default now(),
  primary key (user_id, user_day, task_id)
);
alter table public.plan_task_checks enable row level security;
create policy plan_task_checks_select on public.plan_task_checks for select to authenticated using (user_id = auth.uid());
create policy plan_task_checks_insert on public.plan_task_checks for insert to authenticated with check (user_id = auth.uid());
create policy plan_task_checks_delete on public.plan_task_checks for delete to authenticated using (user_id = auth.uid());
grant select, insert, delete on public.plan_task_checks to authenticated;

-- ---------------------------------------------------------------- suspended turns

-- A turn waiting on the phone. The conversation, the workflow and the ledger, under the
-- lease that owns the turn; the resume reclaims the turn and reads it back.
create table nb.ai_turn_states (
  turn_id    uuid primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  state      jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create index ai_turn_states_expiry on nb.ai_turn_states (expires_at);
alter table nb.ai_turn_states enable row level security;
revoke all on nb.ai_turn_states from public, anon, authenticated, service_role;

create function public.save_ai_turn_state(p_turn uuid, p_lease uuid, p_state jsonb, p_ttl_seconds integer default 300)
returns void language plpgsql security definer set search_path='' as $$
declare u uuid := auth.uid(); lease nb.ai_turn_leases%rowtype;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  if p_turn is null or p_lease is null or p_state is null or jsonb_typeof(p_state) <> 'object'
     or octet_length(p_state::text) > 2000000 then
    raise exception 'INVALID_STATE' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_turn::text, 0));
  select * into lease from nb.ai_turn_leases where turn_id = p_turn;
  if not found or lease.user_id <> u or lease.lease_id <> p_lease or lease.expires_at <= clock_timestamp() then
    raise exception 'TURN_LEASE_LOST' using errcode='55000';
  end if;
  -- Bounded cleanup on the way in, like the leases.
  delete from nb.ai_turn_states where expires_at < clock_timestamp() - interval '1 hour';
  insert into nb.ai_turn_states (turn_id, user_id, state, expires_at)
  values (p_turn, u, p_state, clock_timestamp() + make_interval(secs => least(greatest(p_ttl_seconds, 30), 900)))
  on conflict (turn_id) do update set state = excluded.state, expires_at = excluded.expires_at, created_at = now();
end $$;

create function public.load_ai_turn_state(p_turn uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid := auth.uid(); v jsonb;
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  select state into v from nb.ai_turn_states where turn_id = p_turn and user_id = u and expires_at > clock_timestamp();
  return v;
end $$;

create function public.clear_ai_turn_state(p_turn uuid)
returns void language plpgsql security definer set search_path='' as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  delete from nb.ai_turn_states where turn_id = p_turn and user_id = u;
end $$;

revoke all on function public.save_ai_turn_state(uuid,uuid,jsonb,integer), public.load_ai_turn_state(uuid),
  public.clear_ai_turn_state(uuid) from public, anon;
grant execute on function public.save_ai_turn_state(uuid,uuid,jsonb,integer), public.load_ai_turn_state(uuid),
  public.clear_ai_turn_state(uuid) to authenticated;

-- The phone erases memory through one call; the REST client has no delete verb.
create function public.forget_user_memory()
returns void language plpgsql security definer set search_path='' as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  delete from public.user_memory where user_id = u;
  update public.ai_sessions set summarized_at = coalesce(summarized_at, now()) where user_id = u;
end $$;
revoke all on function public.forget_user_memory() from public, anon;
grant execute on function public.forget_user_memory() to authenticated;
