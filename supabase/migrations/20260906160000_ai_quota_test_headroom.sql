-- The daily AI allowance was three hard-coded numbers (10 a day, rolling to 20,
-- 200 fen a day) buried in two functions, so exhausting it during a manual test
-- meant no ASR and no answers until the next user day. The three numbers move
-- onto the balance row, per user, and the shipping values become the column
-- defaults — a launch migration tightens the defaults again rather than editing
-- function bodies.
alter table nb.ai_quotas
  alter column remaining set default 10,
  add column daily_grant integer not null default 10 check(daily_grant > 0),
  add column grant_cap integer not null default 20 check(grant_cap > 0),
  add column spend_cap_fen numeric(20,6) not null default 200 check(spend_cap_fen > 0);
alter table nb.ai_quotas drop constraint ai_quotas_remaining_check;
alter table nb.ai_quotas add constraint ai_quotas_remaining_check
  check (remaining >= 0 and remaining <= grant_cap);

create or replace function nb.consume_ai_quota(p_owner uuid, p_endpoint text, p_today date, p_cap_fen integer)
returns jsonb
language plpgsql security definer set search_path='' as $$
declare elapsed integer; available integer; current nb.ai_quotas%rowtype; today date:=p_today;
begin
 if p_endpoint not in ('turn','meal','asr') then raise exception 'UNKNOWN_ENDPOINT' using errcode='22023'; end if;
 if p_owner is null or not exists(select 1 from auth.users where id=p_owner)
 then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 if today is null then today:=(timezone('utc', now()))::date; end if;
 select * into current from nb.ai_quotas where user_id=p_owner for update;
 if not found then
  -- remaining, daily_grant, grant_cap and spend_cap_fen all come from the
  -- column defaults, so a first request is admitted on the current allowance.
  insert into nb.ai_quotas(user_id,settled_day,spent_fen,spent_day)
   values(p_owner,today,0,today)
   returning * into current;
 end if;
 elapsed:=today-current.settled_day;
 if elapsed<0 then
  return jsonb_build_object('allowed',false,'reason','count','remaining',0);
 end if;
 if elapsed>0 then
  available:=least(current.grant_cap, current.remaining + elapsed*current.daily_grant);
  current.remaining:=available;
  current.settled_day:=today;
 end if;
 if current.spent_day is distinct from today then
  current.spent_fen:=0;
  current.spent_day:=today;
 end if;
 if current.remaining<1 then
  update nb.ai_quotas set remaining=current.remaining, settled_day=current.settled_day,
   spent_fen=current.spent_fen, spent_day=current.spent_day where user_id=p_owner;
  return jsonb_build_object('allowed',false,'reason','count','remaining',0);
 end if;
 -- p_cap_fen stays in the signature for callers that still pass it, but the row
 -- is the authority: a raised test ceiling must not be undone by an old caller.
 if current.spent_fen>=greatest(current.spend_cap_fen, coalesce(p_cap_fen,0)) then
  update nb.ai_quotas set remaining=current.remaining, settled_day=current.settled_day,
   spent_fen=current.spent_fen, spent_day=current.spent_day where user_id=p_owner;
  return jsonb_build_object('allowed',false,'reason','spend','remaining',current.remaining);
 end if;
 current.remaining:=current.remaining-1;
 update nb.ai_quotas set remaining=current.remaining, settled_day=current.settled_day,
  spent_fen=current.spent_fen, spent_day=current.spent_day where user_id=p_owner;
 return jsonb_build_object('allowed',true,'remaining',current.remaining,'spent_fen',current.spent_fen);
end $$;

create or replace function public.consume_ai_quota_trusted(p_owner uuid,p_endpoint text,p_operation uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare today date; decision jsonb; balance nb.ai_quotas%rowtype; attempts integer;
begin
 if p_owner is null or not exists(select 1 from auth.users where id=p_owner) then
  raise exception 'UNAUTHENTICATED' using errcode='28000';
 end if;
 if p_endpoint not in ('turn','meal','asr') then raise exception 'UNKNOWN_ENDPOINT' using errcode='22023'; end if;
 if p_operation is null then raise exception 'MISSING_OPERATION' using errcode='22023'; end if;
 today:=nb.user_day(p_owner);
 -- Create-before-lock avoids first-request races on a newly registered user.
 insert into nb.ai_quotas(user_id,settled_day,spent_fen,spent_day)
 values(p_owner,today,0,today) on conflict(user_id) do nothing;
 select * into balance from nb.ai_quotas where user_id=p_owner for update;
 if exists(select 1 from nb.ai_operations where user_id=p_owner and operation_id=p_operation) then
  -- ASR and answer are one operation. Re-entry still checks spend, including
  -- when the previous stage used the last remaining count.
  if balance.spent_day=today and balance.spent_fen>=balance.spend_cap_fen then
   return jsonb_build_object('allowed',false,'reason','spend');
  end if;
  select coalesce((admissions->>p_endpoint)::integer,0) into attempts
   from nb.ai_operations where user_id=p_owner and operation_id=p_operation;
  if attempts>=2 then return jsonb_build_object('allowed',false,'reason','unavailable'); end if;
  update nb.ai_operations set admissions=jsonb_set(admissions,array[p_endpoint],to_jsonb(attempts+1))
   where user_id=p_owner and operation_id=p_operation;
  return jsonb_build_object('allowed',true,'remaining',balance.remaining);
 end if;
 decision:=nb.consume_ai_quota(p_owner,p_endpoint,today,null);
 if (decision->>'allowed')::boolean then
  insert into nb.ai_operations(user_id,operation_id,admissions) values(p_owner,p_operation,jsonb_build_object(p_endpoint,1));
 end if;
 return decision;
end $$;

create or replace function public.check_ai_spend_trusted(p_owner uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare today date; balance nb.ai_quotas%rowtype;
begin
 if p_owner is null or not exists(select 1 from auth.users where id=p_owner) then
  raise exception 'UNAUTHENTICATED' using errcode='28000';
 end if;
 today:=nb.user_day(p_owner);
 select * into balance from nb.ai_quotas where user_id=p_owner;
 if not found then return jsonb_build_object('allowed',false,'reason','unavailable'); end if;
 if balance.spent_day=today and balance.spent_fen>=balance.spend_cap_fen then
  return jsonb_build_object('allowed',false,'reason','spend');
 end if;
 return jsonb_build_object('allowed',true,'remaining',balance.remaining);
end $$;

create or replace function public.record_ai_usage_trusted(
 p_owner uuid,p_endpoint text,p_model text,p_prompt integer,p_cached integer,
 p_completion integer,p_turn uuid,p_latency integer,p_audio_seconds numeric default 0
) returns void language plpgsql security definer set search_path='' as $$
declare book nb.ai_price_book%rowtype; fen numeric(20,6); today date;
begin
 if p_owner is null or not exists(select 1 from auth.users where id=p_owner) then
  raise exception 'UNAUTHENTICATED' using errcode='28000';
 end if;
 if p_endpoint not in ('turn','meal','asr') then raise exception 'UNKNOWN_ENDPOINT' using errcode='22023'; end if;
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

-- DEV ONLY, revert before launch: this project is the hand-test environment, so
-- every account gets room to talk to the app all day, and today's balance is
-- refilled for whoever already ran out.
alter table nb.ai_quotas alter column remaining set default 5000;
alter table nb.ai_quotas alter column daily_grant set default 1000;
alter table nb.ai_quotas alter column grant_cap set default 5000;
alter table nb.ai_quotas alter column spend_cap_fen set default 50000;
update nb.ai_quotas set daily_grant=1000, grant_cap=5000, spend_cap_fen=50000,
 remaining=5000, settled_day=nb.user_day(user_id), spent_fen=0, spent_day=nb.user_day(user_id);
