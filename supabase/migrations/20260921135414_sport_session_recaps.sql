-- Finished-session presentation facts are separate from training evidence. Saving
-- a recap must never settle a day or manufacture observations (including no-HR runs).
create table public.sport_session_recaps (
 user_id uuid not null references auth.users(id) on delete cascade,
 id uuid not null,
 started_at timestamptz not null,
 ended_at timestamptz not null,
 payload jsonb not null,
 created_at timestamptz not null default now(),
 primary key(user_id,id),
 check(isfinite(started_at) and isfinite(ended_at) and ended_at>=started_at
   and ended_at-started_at<=interval '24 hours'),
 check(jsonb_typeof(payload)='object' and octet_length(payload::text)<=1048576)
);
create index sport_session_recaps_recent on public.sport_session_recaps(user_id,started_at desc,id);
alter table public.sport_session_recaps enable row level security;
revoke all on public.sport_session_recaps from public,anon,authenticated;
grant select on public.sport_session_recaps to authenticated;
grant all on public.sport_session_recaps to service_role;
create policy sport_session_recaps_read on public.sport_session_recaps for select to authenticated
 using(user_id=(select auth.uid())
   and not coalesce(((select auth.jwt())->>'is_anonymous')::boolean,false));

-- The command alone may insert: clients cannot bypass the consent, account-state,
-- validation, or immutable-replay checks with a direct Data API write.
create function health_commands.save_sport_recap(p_id uuid,p_started_at timestamptz,
 p_ended_at timestamptz,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare owner uuid:=auth.uid(); previous public.sport_session_recaps%rowtype;
begin
 if owner is null or not exists(select 1 from auth.users u
  where u.id=owner and not coalesce(u.is_anonymous,false))
  then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 perform 1 from public.profiles where user_id=owner and deletion_requested_at is null for share;
 if not found then raise exception 'ACCOUNT_UNAVAILABLE' using errcode='42501'; end if;
 if (select choice from public.consents where user_id=owner order by decided_at desc,id desc limit 1)
  is distinct from 'granted' then raise exception 'CONSENT_WITHDRAWN' using errcode='42501'; end if;
 if p_id is null or p_started_at is null or p_ended_at is null
  or not isfinite(p_started_at) or not isfinite(p_ended_at)
  or p_ended_at<p_started_at or p_ended_at-p_started_at>interval '24 hours'
  or p_ended_at>now()+interval '5 minutes'
  then raise exception 'INVALID_SPORT_RECAP_WINDOW' using errcode='22023'; end if;
 if p_payload is null or jsonb_typeof(p_payload)<>'object'
  or octet_length(p_payload::text)>1048576
  then raise exception 'INVALID_SPORT_RECAP_PAYLOAD' using errcode='22023'; end if;
 -- Scope identity and serialization to the authenticated owner. Payload fields are
 -- presentation data only; ownerUserID is never an authorization input.
 perform pg_advisory_xact_lock(hashtextextended(owner::text||':sport-recap:'||p_id::text,0));
 select * into previous from public.sport_session_recaps where user_id=owner and id=p_id;
 if found then
  if previous.started_at<>p_started_at or previous.ended_at<>p_ended_at or previous.payload<>p_payload
   then raise exception 'SPORT_RECAP_CONFLICT' using errcode='23505'; end if;
  return jsonb_build_object('id',p_id,'replay',true);
 end if;
 insert into public.sport_session_recaps(user_id,id,started_at,ended_at,payload)
  values(owner,p_id,p_started_at,p_ended_at,p_payload);
 return jsonb_build_object('id',p_id,'replay',false);
end $$;
revoke all on function health_commands.save_sport_recap(uuid,timestamptz,timestamptz,jsonb) from public,anon;
grant execute on function health_commands.save_sport_recap(uuid,timestamptz,timestamptz,jsonb) to authenticated;
create function public.save_sport_recap(p_id uuid,p_started_at timestamptz,p_ended_at timestamptz,p_payload jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select health_commands.save_sport_recap(p_id,p_started_at,p_ended_at,p_payload);
$$;
revoke all on function public.save_sport_recap(uuid,timestamptz,timestamptz,jsonb) from public,anon;
grant execute on function public.save_sport_recap(uuid,timestamptz,timestamptz,jsonb) to authenticated;

-- Extend the existing lifecycle without replacing its evolving domain list.
do $$ declare definition text; begin
 definition:=pg_get_functiondef('public.export_all()'::regprocedure);
 if position('''balance_checks''' in definition)=0 then raise exception 'export_all anchor missing'; end if;
 execute replace(definition,'''balance_checks'',',
  '''sport_session_recaps'', (select coalesce(jsonb_agg(to_jsonb(s) order by s.started_at,s.id), ''[]''::jsonb) from public.sport_session_recaps s where s.user_id=(select auth.uid())), ''balance_checks'',');
 definition:=pg_get_functiondef('nb.account_delete_legacy_oxygen(text)'::regprocedure);
 if position('delete from public.balance_checks' in definition)=0 then raise exception 'account_delete anchor missing'; end if;
 execute replace(definition,'delete from public.balance_checks',
  'delete from public.sport_session_recaps where user_id=v_user; delete from public.balance_checks');
end $$;
