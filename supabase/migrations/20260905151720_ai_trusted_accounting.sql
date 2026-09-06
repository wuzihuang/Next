-- Only the Edge service may admit or bill AI operations. The caller cannot
-- select an accounting day or submit its own monetary amount.
revoke all on function public.consume_ai_quota(text) from public,anon,authenticated;
revoke all on function public.record_ai_usage(text,text,integer,integer,integer,integer,date,uuid,integer) from public,anon,authenticated;
drop function public.consume_ai_quota(text);
drop function public.record_ai_usage(text,text,integer,integer,integer,integer,date,uuid,integer);
drop function nb.record_ai_usage(uuid,text,text,integer,integer,integer,integer,date,uuid,integer);

drop view nb.ai_usage_daily;
alter table nb.ai_model_calls alter column cost_fen type numeric(20,6);
alter table nb.ai_model_calls add column audio_seconds numeric(20,6) not null default 0 check(audio_seconds>=0);
alter table nb.ai_price_book add column audio_fen_per_second numeric(10,6) not null default 0;
-- Beijing price list: https://help.aliyun.com/zh/model-studio/model-pricing
insert into nb.ai_price_book(model_id,prompt_fen_per_million,cached_fen_per_million,completion_fen_per_million,audio_fen_per_second)
values ('qwen3-asr-flash',0,0,0,0.022),('qwen3-asr-flash-realtime',0,0,0,0.033);
alter table nb.ai_quotas alter column spent_fen type numeric(20,6);
create view nb.ai_usage_daily with (security_invoker = true) as
 select user_id,user_day,count(*)::integer as calls,
 coalesce(sum(prompt_tokens),0)::bigint as prompt_tokens,
 coalesce(sum(cached_tokens),0)::bigint as cached_tokens,
 coalesce(sum(completion_tokens),0)::bigint as completion_tokens,
 coalesce(sum(audio_seconds),0) as audio_seconds,
 coalesce(sum(cost_fen),0) as cost_fen
 from nb.ai_model_calls group by user_id,user_day;
revoke all on nb.ai_usage_daily from public,anon,authenticated;
grant select on nb.ai_usage_daily to service_role;

create table nb.ai_operations (
 user_id uuid not null references auth.users(id) on delete cascade,
 operation_id uuid not null,
 created_at timestamptz not null default now(),
 admissions jsonb not null default '{}'::jsonb,
 primary key(user_id,operation_id)
);
alter table nb.ai_operations enable row level security;
revoke all on nb.ai_operations from public,anon,authenticated;

create function public.consume_ai_quota_trusted(p_owner uuid,p_endpoint text,p_operation uuid)
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
 insert into nb.ai_quotas(user_id,remaining,settled_day,spent_fen,spent_day)
 values(p_owner,10,today,0,today) on conflict(user_id) do nothing;
 select * into balance from nb.ai_quotas where user_id=p_owner for update;
 if exists(select 1 from nb.ai_operations where user_id=p_owner and operation_id=p_operation) then
  -- ASR and answer are one operation. Re-entry still checks spend, including
  -- when the previous stage used the last remaining count.
  if balance.spent_day=today and balance.spent_fen>=200 then
   return jsonb_build_object('allowed',false,'reason','spend');
  end if;
  select coalesce((admissions->>p_endpoint)::integer,0) into attempts
   from nb.ai_operations where user_id=p_owner and operation_id=p_operation;
  if attempts>=2 then return jsonb_build_object('allowed',false,'reason','unavailable'); end if;
  update nb.ai_operations set admissions=jsonb_set(admissions,array[p_endpoint],to_jsonb(attempts+1))
   where user_id=p_owner and operation_id=p_operation;
  return jsonb_build_object('allowed',true,'remaining',balance.remaining);
 end if;
 decision:=nb.consume_ai_quota(p_owner,p_endpoint,today,200);
 if (decision->>'allowed')::boolean then
  insert into nb.ai_operations(user_id,operation_id,admissions) values(p_owner,p_operation,jsonb_build_object(p_endpoint,1));
 end if;
 return decision;
end $$;
revoke all on function public.consume_ai_quota_trusted(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.consume_ai_quota_trusted(uuid,text,uuid) to service_role;

create function public.check_ai_spend_trusted(p_owner uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare today date; balance nb.ai_quotas%rowtype;
begin
 if p_owner is null or not exists(select 1 from auth.users where id=p_owner) then
  raise exception 'UNAUTHENTICATED' using errcode='28000';
 end if;
 today:=nb.user_day(p_owner);
 select * into balance from nb.ai_quotas where user_id=p_owner;
 if not found then return jsonb_build_object('allowed',false,'reason','unavailable'); end if;
 if balance.spent_day=today and balance.spent_fen>=200 then
  return jsonb_build_object('allowed',false,'reason','spend');
 end if;
 return jsonb_build_object('allowed',true,'remaining',balance.remaining);
end $$;
revoke all on function public.check_ai_spend_trusted(uuid) from public,anon,authenticated;
grant execute on function public.check_ai_spend_trusted(uuid) to service_role;

create function public.record_ai_usage_trusted(
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
 insert into nb.ai_quotas(user_id,remaining,settled_day,spent_fen,spent_day)
 values(p_owner,10,today,fen,today)
 on conflict(user_id) do update set
 spent_fen=case when nb.ai_quotas.spent_day=today then nb.ai_quotas.spent_fen+fen else fen end,
 spent_day=today;
end $$;
revoke all on function public.record_ai_usage_trusted(uuid,text,text,integer,integer,integer,uuid,integer,numeric) from public,anon,authenticated;
grant execute on function public.record_ai_usage_trusted(uuid,text,text,integer,integer,integer,uuid,integer,numeric) to service_role;
