-- Shared AI allowance: 10 turns a day, unused rolls to a cap of 20, plus a
-- daily fen ceiling. Token rows are the only cost ledger; Edge Functions stay
-- stateless. meal and asr join the 60-second burst table so the expensive
-- paths cannot bypass the counter.

alter table nb.request_budgets drop constraint request_budgets_endpoint_check;
alter table nb.request_budgets add constraint request_budgets_endpoint_check
  check (endpoint in (
    'metric-read','meal-commit','meal-operation','turn','archive-data',
    'export','account-delete','meal','asr'
  ));

create or replace function nb.consume_request_budget(p_owner uuid, p_endpoint text)
returns jsonb
language plpgsql security definer set search_path='' as $$
declare cap integer; instant timestamptz:=clock_timestamp(); accepted integer; window_at timestamptz;
begin
 cap:=case p_endpoint when 'metric-read' then 60 when 'meal-commit' then 30
 when 'meal-operation' then 30 when 'turn' then 20 when 'meal' then 20
 when 'asr' then 20 when 'archive-data' then 6
 when 'export' then 2 when 'account-delete' then 6 else null end;
 if cap is null then raise exception 'UNKNOWN_ENDPOINT' using errcode='22023'; end if;
 if p_owner is null or not exists(select 1 from auth.users where id=p_owner)
 then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 insert into nb.request_budgets(user_id,endpoint,window_start,used) values(p_owner,p_endpoint,instant,1)
 on conflict(user_id,endpoint) do update set
 window_start=case when nb.request_budgets.window_start<=instant-interval '60 seconds' then instant else nb.request_budgets.window_start end,
 used=case when nb.request_budgets.window_start<=instant-interval '60 seconds' then 1 else nb.request_budgets.used+1 end
 where nb.request_budgets.window_start<=instant-interval '60 seconds' or nb.request_budgets.used<cap
 returning used,window_start into accepted,window_at;
 if accepted is null then
   select window_start into window_at from nb.request_budgets where user_id=p_owner and endpoint=p_endpoint;
 end if;
 return jsonb_build_object('allowed',accepted is not null,'remaining',case when accepted is null then 0 else cap-accepted end,
 'retry_after',greatest(1,ceil(extract(epoch from window_at+interval '60 seconds'-instant)))::integer);
end $$;

create table nb.ai_price_book (
 model_id text primary key,
 prompt_fen_per_million integer not null,
 cached_fen_per_million integer not null,
 completion_fen_per_million integer not null
);
alter table nb.ai_price_book enable row level security;
revoke all on nb.ai_price_book from public,anon,authenticated;
insert into nb.ai_price_book(model_id,prompt_fen_per_million,cached_fen_per_million,completion_fen_per_million)
 values ('qwen3.8-flash',80,10,270),('*',80,10,270);

create table nb.ai_quotas (
 user_id uuid primary key references auth.users(id) on delete cascade,
 remaining integer not null check(remaining>=0 and remaining<=20),
 settled_day date not null,
 spent_fen bigint not null default 0 check(spent_fen>=0),
 spent_day date not null
);
alter table nb.ai_quotas enable row level security;
revoke all on nb.ai_quotas from public,anon,authenticated;

create function nb.user_day(p_owner uuid, p_at timestamptz default now())
returns date
language plpgsql stable set search_path='' as $$
declare tz text := 'UTC'; local_ts timestamp;
begin
  select timezone into tz from public.profiles where user_id = p_owner;
  tz := coalesce(nullif(tz, ''), 'UTC');
  local_ts := p_at at time zone tz;
  if extract(hour from local_ts) < 4 then
    return (local_ts::date - 1);
  end if;
  return local_ts::date;
end $$;
revoke all on function nb.user_day(uuid, timestamptz) from public,anon,authenticated;

create table nb.ai_model_calls (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 user_day date not null,
 endpoint text not null check(endpoint in ('turn','meal','asr')),
 turn_id uuid,
 model_id text not null,
 prompt_tokens integer not null default 0 check(prompt_tokens>=0),
 cached_tokens integer not null default 0 check(cached_tokens>=0),
 completion_tokens integer not null default 0 check(completion_tokens>=0),
 cost_fen integer not null default 0 check(cost_fen>=0),
 latency_ms integer
);
create index ai_model_calls_user_day_idx on nb.ai_model_calls(user_id,user_day);
alter table nb.ai_model_calls enable row level security;
revoke all on nb.ai_model_calls from public,anon,authenticated;

create view nb.ai_usage_daily
with (security_invoker = true) as
 select user_id, user_day,
  count(*)::integer as calls,
  coalesce(sum(prompt_tokens),0)::bigint as prompt_tokens,
  coalesce(sum(cached_tokens),0)::bigint as cached_tokens,
  coalesce(sum(completion_tokens),0)::bigint as completion_tokens,
  coalesce(sum(cost_fen),0)::bigint as cost_fen
 from nb.ai_model_calls
 group by user_id, user_day;
revoke all on nb.ai_usage_daily from public,anon,authenticated;
grant select on nb.ai_usage_daily to service_role;

create function nb.consume_ai_quota(p_owner uuid, p_endpoint text, p_today date, p_cap_fen integer)
returns jsonb
language plpgsql security definer set search_path='' as $$
declare grant_n integer:=10; cap_n integer:=20; elapsed integer; available integer;
        current nb.ai_quotas%rowtype; today date:=p_today;
begin
 if p_endpoint not in ('turn','meal','asr') then raise exception 'UNKNOWN_ENDPOINT' using errcode='22023'; end if;
 if p_owner is null or not exists(select 1 from auth.users where id=p_owner)
 then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 if today is null then today:=(timezone('utc', now()))::date; end if;
 select * into current from nb.ai_quotas where user_id=p_owner for update;
 if not found then
  insert into nb.ai_quotas(user_id,remaining,settled_day,spent_fen,spent_day)
   values(p_owner,grant_n,today,0,today)
   returning * into current;
 end if;
 elapsed:=today-current.settled_day;
 if elapsed<0 then
  return jsonb_build_object('allowed',false,'reason','count','remaining',0);
 end if;
 if elapsed>0 then
  available:=least(cap_n, current.remaining + elapsed*grant_n);
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
 if current.spent_fen>=p_cap_fen then
  update nb.ai_quotas set remaining=current.remaining, settled_day=current.settled_day,
   spent_fen=current.spent_fen, spent_day=current.spent_day where user_id=p_owner;
  return jsonb_build_object('allowed',false,'reason','spend','remaining',current.remaining);
 end if;
 current.remaining:=current.remaining-1;
 update nb.ai_quotas set remaining=current.remaining, settled_day=current.settled_day,
  spent_fen=current.spent_fen, spent_day=current.spent_day where user_id=p_owner;
 return jsonb_build_object('allowed',true,'remaining',current.remaining,'spent_fen',current.spent_fen);
end $$;
revoke all on function nb.consume_ai_quota(uuid,text,date,integer) from public,anon,authenticated;

create function public.consume_ai_quota(p_endpoint text)
returns jsonb
language sql security definer set search_path='' as $$
 select nb.consume_ai_quota(auth.uid(), p_endpoint, nb.user_day(auth.uid()), 200);
$$;
revoke all on function public.consume_ai_quota(text) from public,anon;
grant execute on function public.consume_ai_quota(text) to authenticated;

create function nb.record_ai_usage(
 p_owner uuid, p_endpoint text, p_model text, p_prompt integer, p_cached integer,
 p_completion integer, p_cost_fen integer, p_user_day date, p_turn uuid, p_latency integer
) returns void
language plpgsql security definer set search_path='' as $$
declare book nb.ai_price_book%rowtype; fen integer; today date;
begin
 if p_owner is null then raise exception 'UNAUTHENTICATED' using errcode='28000'; end if;
 if p_endpoint not in ('turn','meal','asr') then raise exception 'UNKNOWN_ENDPOINT' using errcode='22023'; end if;
 select * into book from nb.ai_price_book where model_id=p_model;
 if not found then select * into book from nb.ai_price_book where model_id='*'; end if;
 fen:=coalesce(nullif(p_cost_fen,0), 0);
 if fen=0 then
  fen:=ceil(((greatest(coalesce(p_prompt,0),0)*coalesce(book.prompt_fen_per_million,0))
   +(greatest(coalesce(p_cached,0),0)*coalesce(book.cached_fen_per_million,0))
   +(greatest(coalesce(p_completion,0),0)*coalesce(book.completion_fen_per_million,0)))/1000000.0);
 end if;
 today:=coalesce(p_user_day, nb.user_day(p_owner));
 insert into nb.ai_model_calls(
  user_id,user_day,endpoint,turn_id,model_id,prompt_tokens,cached_tokens,completion_tokens,cost_fen,latency_ms)
  values(
   p_owner,today,p_endpoint,p_turn,p_model,
   greatest(coalesce(p_prompt,0),0),greatest(coalesce(p_cached,0),0),
   greatest(coalesce(p_completion,0),0),fen,p_latency);
 update nb.ai_quotas
    set spent_fen = case when spent_day is distinct from today then fen else spent_fen + fen end,
        spent_day = today
  where user_id=p_owner;
end $$;
revoke all on function nb.record_ai_usage(uuid,text,text,integer,integer,integer,integer,date,uuid,integer) from public,anon,authenticated;

create function public.record_ai_usage(
 p_endpoint text, p_model text, p_prompt integer, p_cached integer,
 p_completion integer, p_cost_fen integer, p_user_day date, p_turn uuid, p_latency integer
) returns void
language sql security definer set search_path='' as $$
 select nb.record_ai_usage(
  auth.uid(), p_endpoint, p_model, p_prompt, p_cached, p_completion,
  p_cost_fen, p_user_day, p_turn, p_latency);
$$;
revoke all on function public.record_ai_usage(text,text,integer,integer,integer,integer,date,uuid,integer) from public,anon;
grant execute on function public.record_ai_usage(text,text,integer,integer,integer,integer,date,uuid,integer) to authenticated;
