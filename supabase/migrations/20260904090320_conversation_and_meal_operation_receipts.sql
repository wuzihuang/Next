-- Atomic, account-owned receipts and conversation records. Never grant the model admin access.
create table public.meal_operations (
  user_id uuid not null references auth.users(id) on delete cascade,
  operation_id uuid not null,
  kind text not null check (kind in ('create','amend','delete')),
  meal_id uuid not null,
  payload jsonb not null,
  accepted_at timestamptz not null default now(),
  primary key (user_id, operation_id)
);
alter table public.meal_operations enable row level security;
create policy meal_operations_read on public.meal_operations for select to authenticated
  using ((select auth.uid()) = user_id);
grant select on public.meal_operations to authenticated;

create or replace function public.apply_meal_operation(
  p_operation_id uuid, p_kind text, p_meal_id uuid, p_payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_existing public.meal_operations%rowtype;
  v_meal public.meals%rowtype;
  v_target uuid;
  v_row jsonb;
  v_today date;
  v_zone text;
begin
  if v_user is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
  if exists (select 1 from public.profiles where user_id=v_user and deletion_requested_at is not null)
    then raise exception 'ACCOUNT_DELETING' using errcode='42501'; end if;
  if p_operation_id is null or p_meal_id is null or p_kind not in ('create','amend','delete')
    or p_kind is null or p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'INVALID_OPERATION' using errcode='22023';
  end if;
  -- Withdrawal stops new collection and amendments. Explicit removal remains available.
  if p_kind <> 'delete' and coalesce((select choice from public.consents
    where user_id=v_user order by decided_at desc,id desc limit 1),'') <> 'granted' then
    raise exception 'CONSENT_WITHDRAWN' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text || ':meals', 0));
  select * into v_existing from public.meal_operations
    where user_id=v_user and operation_id=p_operation_id;
  if found then
    if v_existing.kind <> p_kind or v_existing.meal_id <> p_meal_id or v_existing.payload <> p_payload then
      raise exception 'OPERATION_CONFLICT' using errcode='23505';
    end if;
    return jsonb_build_object('operation_id',p_operation_id,'client_op_id',p_operation_id,
      'meal_id',p_meal_id,'id',case when p_kind='amend' then (p_payload->>'id')::uuid else p_meal_id end,'replay',true);
  end if;
  if p_kind in ('amend','delete') then
    select * into v_meal from public.meals where user_id=v_user and id=p_meal_id for update;
    if not found then raise exception 'MEAL_NOT_FOUND' using errcode='P0002'; end if;
    select coalesce(timezone,'UTC') into v_zone from public.profiles where user_id=v_user;
    v_today := nb.user_day_of(now(),coalesce(v_zone,'UTC'));
    if v_meal.user_day < v_today-6 or v_meal.user_day > v_today then
      raise exception 'MEAL_EDIT_WINDOW_CLOSED' using errcode='22023';
    end if;
    if p_kind='amend' and v_meal.deleted_at is not null then
      raise exception 'MEAL_ALREADY_DELETED' using errcode='22023';
    end if;
  end if;
  if p_kind in ('create','amend') then
    v_row := p_payload;
    v_target := case when p_kind='create' then p_meal_id else (v_row->>'id')::uuid end;
    if v_target is null or (p_kind='amend' and v_target=p_meal_id)
      or jsonb_typeof(v_row->'user_day') is distinct from 'string'
      or jsonb_typeof(v_row->'slot') is distinct from 'string'
      or jsonb_typeof(v_row->'name') is distinct from 'string'
      or jsonb_typeof(v_row->'kcal') is distinct from 'number'
      or coalesce(v_row->>'slot','') not in ('BREAKFAST','LUNCH','DINNER','SNACK')
      or coalesce(v_row->>'kcal','') !~ '^[0-9]+$'
      or (v_row->>'kcal')::numeric not between 1 and 100000
      or length(coalesce(v_row->>'name','')) not between 1 and 8000
      or coalesce(v_row->>'confidence','MEDIUM') not in ('LOW','MEDIUM','HIGH')
      or length(coalesce(v_row->>'model_version','')) > 256 then
      raise exception 'INVALID_MEAL' using errcode='22023';
    end if;
    if exists(select 1 from jsonb_each(v_row) e where e.key in ('protein_g','carb_g','fat_g')
      and (jsonb_typeof(e.value) <> 'number' or e.value::text !~ '^[0-9]+$'
        or (case when jsonb_typeof(e.value)='number' then e.value::text::numeric else -1 end) not between 0 and 100000)) then
      raise exception 'INVALID_MEAL' using errcode='22023';
    end if;
    if p_kind='amend' and (v_row->>'user_day')::date <> v_meal.user_day then
      raise exception 'MEAL_DAY_CHANGED' using errcode='22023';
    end if;
    -- Legacy create retries get an acknowledgment only if the accepted payload matches.
    if p_kind='create' then
      select * into v_meal from public.meals where user_id=v_user and client_op_id=p_operation_id;
      if found then
        if v_meal.id <> v_target or v_meal.user_day <> (v_row->>'user_day')::date
          or v_meal.slot <> v_row->>'slot' or v_meal.kcal is distinct from (v_row->>'kcal')::integer
          or v_meal.text_input is distinct from v_row->>'name'
          or v_meal.protein_g is distinct from (v_row->>'protein_g')::integer
          or v_meal.carb_g is distinct from (v_row->>'carb_g')::integer
          or v_meal.fat_g is distinct from (v_row->>'fat_g')::integer
          or v_meal.model_version is distinct from v_row->>'model_version'
          or v_meal.confidence is distinct from coalesce(v_row->>'confidence','MEDIUM') then
          raise exception 'OPERATION_CONFLICT' using errcode='23505';
        end if;
      else
        insert into public.meals(id,user_id,user_day,slot,text_input,kcal,protein_g,carb_g,fat_g,
          confidence,model_version,client_op_id)
        values(v_target,v_user,(v_row->>'user_day')::date,v_row->>'slot',v_row->>'name',
          (v_row->>'kcal')::integer,(v_row->>'protein_g')::integer,(v_row->>'carb_g')::integer,
          (v_row->>'fat_g')::integer,coalesce(v_row->>'confidence','MEDIUM'),v_row->>'model_version',p_operation_id);
      end if;
    else
      update public.meals set deleted_at=coalesce(deleted_at,now()) where user_id=v_user and id=p_meal_id;
      insert into public.meals(id,user_id,user_day,slot,text_input,kcal,protein_g,carb_g,fat_g,
        confidence,model_version,client_op_id)
      values(v_target,v_user,(v_row->>'user_day')::date,v_row->>'slot',v_row->>'name',
        (v_row->>'kcal')::integer,(v_row->>'protein_g')::integer,(v_row->>'carb_g')::integer,
        (v_row->>'fat_g')::integer,coalesce(v_row->>'confidence','MEDIUM'),v_row->>'model_version',p_operation_id);
    end if;
  else
    v_target := p_meal_id;
    update public.meals set deleted_at=coalesce(deleted_at,now()) where user_id=v_user and id=p_meal_id;
  end if;
  insert into public.meal_operations(user_id,operation_id,kind,meal_id,payload)
    values(v_user,p_operation_id,p_kind,p_meal_id,p_payload);
  return jsonb_build_object('operation_id',p_operation_id,'client_op_id',p_operation_id,
    'meal_id',p_meal_id,'id',v_target,'replay',false);
end;
$$;
revoke all on function public.apply_meal_operation(uuid,text,uuid,jsonb) from public,anon;
grant execute on function public.apply_meal_operation(uuid,text,uuid,jsonb) to authenticated;

create table public.conversations (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  summary text not null default '' check(length(summary)<=8192),
  summary_through bigint,
  last_query_context jsonb check(last_query_context is null or (jsonb_typeof(last_query_context)='object' and octet_length(last_query_context::text)<=36000)),
  unique(id,user_id)
);
create table public.conversation_messages (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null,
  sequence bigint generated always as identity,
  role text not null check(role in ('user','assistant')),
  content text not null check(length(content)<=16000),
  created_at timestamptz not null default now(),
  foreign key(conversation_id,user_id) references public.conversations(id,user_id) on delete cascade
);
create index conversation_messages_recent on public.conversation_messages(user_id,conversation_id,sequence desc);
alter table public.ai_turns add column conversation_id uuid;
alter table public.ai_turns add foreign key(conversation_id,user_id) references public.conversations(id,user_id) on delete cascade;
alter table public.conversations enable row level security;
alter table public.conversation_messages enable row level security;
create policy conversations_read on public.conversations for select to authenticated using ((select auth.uid())=user_id);
create policy conversation_messages_read on public.conversation_messages for select to authenticated using ((select auth.uid())=user_id);
grant select on public.conversations,public.conversation_messages to authenticated;

create or replace function nb.conversation_actor() returns uuid
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid();
begin
 if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 if exists(select 1 from public.profiles where user_id=u and deletion_requested_at is not null)
 then raise exception 'ACCOUNT_DELETING' using errcode='42501'; end if;
 if (select choice from public.consents where user_id=u order by decided_at desc,id desc limit 1) is distinct from 'granted'
 then raise exception 'CONSENT_WITHDRAWN' using errcode='42501'; end if;
 return u;
end $$;
revoke all on function nb.conversation_actor() from public,anon,authenticated;

create or replace function public.conversation_context(p_conversation uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=nb.conversation_actor(); v jsonb;
begin
 if p_conversation is null then raise exception 'INVALID_CONVERSATION' using errcode='22023'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('role',role,'content',left(content,2000) || case when length(content)>2000 then E'\n[truncated excerpt]' else '' end) order by sequence),'[]'::jsonb) into v
 from (select role,content,sequence from public.conversation_messages
 where user_id=u and conversation_id=p_conversation order by sequence desc limit 24) messages;
 return v;
end $$;
revoke all on function public.conversation_context(uuid) from public,anon;
grant execute on function public.conversation_context(uuid) to authenticated;

create or replace function public.conversation_summary(p_conversation uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=nb.conversation_actor(); v jsonb;
begin
 if p_conversation is null then raise exception 'INVALID_CONVERSATION' using errcode='22023'; end if;
 select jsonb_build_object('kind','user_excerpt_v1','text',summary,'throughSequence',summary_through,'lastQueryContext',last_query_context) into v
 from public.conversations where user_id=u and id=p_conversation;
 return v;
end $$;
revoke all on function public.conversation_summary(uuid) from public,anon;
grant execute on function public.conversation_summary(uuid) to authenticated;

create or replace function public.record_ai_turn(p_turn uuid,p_text text,p_envelope jsonb,p_trace jsonb,
 p_latency integer,p_model text,p_conversation uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=nb.conversation_actor(); v_frame uuid; v_old public.ai_turns%rowtype;
 v_answer text; v_ttl integer:=20; v_threshold bigint; v_summary text;
begin
 if p_turn is null or p_text is null or length(p_text)>8000 or p_envelope is null
 or jsonb_typeof(p_envelope)<>'object' or octet_length(p_envelope::text)>500000
 or p_trace is null or jsonb_typeof(p_trace)<>'array' or octet_length(p_trace::text)>500000
 or p_latency is null or p_latency<0 or p_latency>3600000
 or p_model is null or length(p_model) not between 1 and 100 then
 raise exception 'INVALID_TURN' using errcode='22023'; end if;
 if p_envelope ? 'ttl_min' then
  if coalesce(p_envelope->>'ttl_min','') !~ '^[0-9]{1,4}$' then raise exception 'INVALID_TURN' using errcode='22023'; end if;
  v_ttl:=(p_envelope->>'ttl_min')::integer;
  if v_ttl not between 1 and 1440 then raise exception 'INVALID_TURN' using errcode='22023'; end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_turn::text,0));
 select * into v_old from public.ai_turns where id=p_turn;
 if found then
  if v_old.user_id<>v_user or v_old.user_text is distinct from p_text
   or v_old.conversation_id is distinct from p_conversation then
   raise exception 'TURN_CONFLICT' using errcode='23505'; end if;
  return jsonb_build_object('frame_id',v_old.frame_id,'replay',true);
 end if;
 if p_conversation is not null then
  insert into public.conversations(id,user_id) values(p_conversation,v_user) on conflict(id) do nothing;
  perform 1 from public.conversations where id=p_conversation and user_id=v_user for update;
  if not found then raise exception 'CONVERSATION_NOT_FOUND' using errcode='42501'; end if;
 end if;
 insert into public.screen_frames(user_id,trigger,widget_tree,model_version,latency_ms,expires_at)
 values(v_user,'turn',p_envelope,p_model,p_latency,now()+make_interval(mins=>v_ttl)) returning id into v_frame;
 insert into public.ai_turns(id,user_id,user_text,tool_trace,frame_id,model_version,latency_ms,outcome,conversation_id)
 values(p_turn,v_user,p_text,p_trace,v_frame,p_model,p_latency,'ok',p_conversation);
 if p_conversation is not null then
  v_answer:=coalesce(p_envelope#>>'{data,sub}',p_envelope->>'sentence','');
  insert into public.conversation_messages(id,user_id,conversation_id,role,content)
  values(md5(p_turn::text||':user')::uuid,v_user,p_conversation,'user',p_text),
   (md5(p_turn::text||':assistant')::uuid,v_user,p_conversation,'assistant',left(v_answer,16000));
  -- Deterministic bounded memory: excerpts of older user requests, never invented facts
  -- or assistant-generated numbers. Full originals remain in message history.
  select sequence into v_threshold from public.conversation_messages
   where user_id=v_user and conversation_id=p_conversation order by sequence desc offset 24 limit 1;
  if v_threshold is not null then
   select left(string_agg('['||sequence::text||'] '||left(content,300)||case when length(content)>300 then ' [excerpt]' else '' end,E'\n' order by sequence),8192)
   into v_summary from (select sequence,content from public.conversation_messages
    where user_id=v_user and conversation_id=p_conversation and sequence<=v_threshold and role='user'
    order by sequence desc limit 24) older;
  end if;
  update public.conversations set updated_at=now(),summary=coalesce(v_summary,''),summary_through=v_threshold
   where id=p_conversation and user_id=v_user;
 end if;
 return jsonb_build_object('frame_id',v_frame,'replay',false);
end $$;
revoke all on function public.record_ai_turn(uuid,text,jsonb,jsonb,integer,text,uuid) from public,anon;
grant execute on function public.record_ai_turn(uuid,text,jsonb,jsonb,integer,text,uuid) to authenticated;

-- Keep the resolved calendar request with the durable turn, so a date-less follow-up
-- after midnight retains its original interval. This is metadata, not a bulk read.
create or replace function public.record_ai_turn_context(p_turn uuid,p_text text,p_envelope jsonb,p_trace jsonb,
 p_latency integer,p_model text,p_conversation uuid default null,p_query_context jsonb default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb; v_from date; v_to date; v_day date;
begin
 if p_query_context is not null then
  if p_conversation is null or jsonb_typeof(p_query_context)<>'object'
   or octet_length(p_query_context::text)>36000
   or (p_query_context - array['dayKey','from','to','queryText','explicitRange']) <> '{}'::jsonb
   or jsonb_typeof(p_query_context->'dayKey') is distinct from 'string'
   or jsonb_typeof(p_query_context->'from') is distinct from 'string'
   or jsonb_typeof(p_query_context->'to') is distinct from 'string'
   or jsonb_typeof(p_query_context->'queryText') is distinct from 'string'
   or length(p_query_context->>'queryText')>8000
   or jsonb_typeof(p_query_context->'explicitRange') is distinct from 'boolean'
   or (p_query_context->>'dayKey') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or (p_query_context->>'from') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or (p_query_context->>'to') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
   raise exception 'INVALID_QUERY_CONTEXT' using errcode='22023';
  end if;
  begin
   v_from:=(p_query_context->>'from')::date;
   v_to:=(p_query_context->>'to')::date;
   v_day:=(p_query_context->>'dayKey')::date;
  exception when datetime_field_overflow or invalid_datetime_format then
   raise exception 'INVALID_QUERY_CONTEXT' using errcode='22023';
  end;
  if v_from>v_to or v_to-v_from>=3660 or v_day<>v_to then
   raise exception 'INVALID_QUERY_CONTEXT' using errcode='22023';
  end if;
 end if;
 v_result:=public.record_ai_turn(p_turn,p_text,p_envelope,p_trace,p_latency,p_model,p_conversation);
 if p_query_context is not null and not (v_result->>'replay')::boolean then
  update public.conversations set last_query_context=p_query_context
   where id=p_conversation and user_id=auth.uid();
 end if;
 return v_result;
end $$;
revoke all on function public.record_ai_turn_context(uuid,text,jsonb,jsonb,integer,text,uuid,jsonb) from public,anon;
grant execute on function public.record_ai_turn_context(uuid,text,jsonb,jsonb,integer,text,uuid,jsonb) to authenticated;
