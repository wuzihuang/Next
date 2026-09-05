-- Idempotent storage alone cannot stop two in-flight model calls. A short execution
-- lease serializes admission using the same advisory key as record_ai_turn.
create table nb.ai_turn_leases (
 turn_id uuid primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 lease_id uuid not null,
 request_hash text not null check(length(request_hash)=64),
 expires_at timestamptz not null
);
create index ai_turn_leases_expiry on nb.ai_turn_leases(expires_at);
alter table nb.ai_turn_leases enable row level security;
revoke all on nb.ai_turn_leases from public,anon,authenticated,service_role;

create function public.claim_ai_turn(p_turn uuid,p_text text,p_conversation uuid,p_lease uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid; saved public.ai_turns%rowtype; lease nb.ai_turn_leases%rowtype;
 request_hash text; instant timestamptz;
begin
 u:=nb.conversation_actor();
 if p_turn is null or p_lease is null or p_text is null or length(p_text)>8000 then
 raise exception 'INVALID_TURN' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_turn::text,0));
 -- Recheck after waiting for an in-flight record/claim transaction.
 u:=nb.conversation_actor();
 instant:=clock_timestamp();
 select * into saved from public.ai_turns where id=p_turn;
 if found then
   if saved.user_id<>u or saved.user_text is distinct from p_text
   or saved.conversation_id is distinct from p_conversation then
     raise exception 'TURN_CONFLICT' using errcode='23505';
   end if;
   return jsonb_build_object('status','replay','frame_id',saved.frame_id);
 end if;
 if p_conversation is not null and exists(select 1 from public.conversations where id=p_conversation and user_id<>u) then
 raise exception 'CONVERSATION_NOT_FOUND' using errcode='42501'; end if;
 request_hash:=encode(extensions.digest(convert_to(jsonb_build_array(p_text,p_conversation)::text,'UTF8'),'sha256'),'hex');
 select * into lease from nb.ai_turn_leases where turn_id=p_turn for update;
 if found then
   if lease.user_id<>u or lease.request_hash<>request_hash then
     raise exception 'TURN_CONFLICT' using errcode='23505'; end if;
   if lease.expires_at>instant then
     if lease.lease_id=p_lease then
       return jsonb_build_object('status','claimed','lease_id',lease.lease_id,'expires_at',lease.expires_at);
     end if;
     return jsonb_build_object('status','busy','retry_after',greatest(1,ceil(extract(epoch from lease.expires_at-instant))::integer));
   end if;
 end if;
 -- Bounded opportunistic cleanup. A day's grace keeps expired request hashes for
 -- retries, while each new admission removes up to 100 abandoned older leases.
 with expired as (
   select turn_id from nb.ai_turn_leases where expires_at<instant-interval '1 day' and turn_id<>p_turn
   order by expires_at limit 100 for update skip locked
 ) delete from nb.ai_turn_leases l using expired e where l.turn_id=e.turn_id;
 insert into nb.ai_turn_leases(turn_id,user_id,lease_id,request_hash,expires_at)
 values(p_turn,u,p_lease,request_hash,instant+interval '90 seconds')
 on conflict(turn_id) do update set lease_id=excluded.lease_id,expires_at=excluded.expires_at;
 return jsonb_build_object('status','claimed','lease_id',p_lease,'expires_at',instant+interval '90 seconds');
end;
$$;
create function public.release_ai_turn(p_turn uuid,p_lease uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); removed integer;
begin
 if u is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 if p_turn is null or p_lease is null then raise exception 'INVALID_TURN' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_turn::text,0));
 -- Release stays available after withdrawal so finally cleanup cannot strand work.
 delete from nb.ai_turn_leases where turn_id=p_turn and user_id=u and lease_id=p_lease;
 get diagnostics removed=row_count;
 return removed=1;
end;
$$;
revoke all on function public.claim_ai_turn(uuid,text,uuid,uuid),public.release_ai_turn(uuid,uuid) from public,anon;
grant execute on function public.claim_ai_turn(uuid,text,uuid,uuid),public.release_ai_turn(uuid,uuid) to authenticated;

-- Admission expiry must also fence publication: slow prefetch/model work cannot
-- publish after a later request reclaimed the lease. The row check and durable
-- receipt use one advisory lock and one database transaction.
create function public.record_claimed_ai_turn(p_lease uuid,p_turn uuid,p_text text,p_envelope jsonb,p_trace jsonb,
 p_latency integer,p_model text,p_conversation uuid default null,p_query_context jsonb default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=nb.conversation_actor(); lease nb.ai_turn_leases%rowtype; request_hash text;
begin
 if p_turn is null or p_lease is null then raise exception 'INVALID_TURN' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_turn::text,0));
 if exists(select 1 from public.ai_turns where id=p_turn) then
   -- The existing writer validates the accepted owner, text and conversation.
   return public.record_ai_turn_context(p_turn,p_text,p_envelope,p_trace,p_latency,p_model,p_conversation,p_query_context);
 end if;
 select * into lease from nb.ai_turn_leases where turn_id=p_turn for update;
 if not found or lease.user_id<>u or lease.lease_id<>p_lease or lease.expires_at<=clock_timestamp() then
   raise exception 'TURN_LEASE_LOST' using errcode='55000';
 end if;
 request_hash:=encode(extensions.digest(convert_to(jsonb_build_array(p_text,p_conversation)::text,'UTF8'),'sha256'),'hex');
 if lease.request_hash<>request_hash then raise exception 'TURN_CONFLICT' using errcode='23505'; end if;
 return public.record_ai_turn_context(p_turn,p_text,p_envelope,p_trace,p_latency,p_model,p_conversation,p_query_context);
end;
$$;
revoke all on function public.record_claimed_ai_turn(uuid,uuid,text,jsonb,jsonb,integer,text,uuid,jsonb) from public,anon;
grant execute on function public.record_claimed_ai_turn(uuid,uuid,text,jsonb,jsonb,integer,text,uuid,jsonb) to authenticated;
