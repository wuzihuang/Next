-- At most seven rows per account: fixed endpoint keys reuse their window rather than
-- accumulating request logs. Auth deletion cascades; clients cannot write counters.
create table nb.request_budgets (
 user_id uuid not null references auth.users(id) on delete cascade,
 endpoint text not null check(endpoint in ('metric-read','meal-commit','meal-operation','turn','archive-data','export','account-delete')),
 window_start timestamptz not null,
 used integer not null check(used>0),
 primary key(user_id,endpoint)
);
alter table nb.request_budgets enable row level security;
revoke all on nb.request_budgets from public,anon,authenticated;

create function nb.consume_request_budget(p_owner uuid,p_endpoint text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cap integer; instant timestamptz:=clock_timestamp(); accepted integer; window_at timestamptz;
begin
 cap:=case p_endpoint when 'metric-read' then 60 when 'meal-commit' then 30
 when 'meal-operation' then 30 when 'turn' then 20 when 'archive-data' then 6
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
revoke all on function nb.consume_request_budget(uuid,text) from public,anon,authenticated;
create function public.consume_request_budget(p_endpoint text) returns jsonb
language sql security definer set search_path='' as $$
 select nb.consume_request_budget(auth.uid(),p_endpoint);
$$;
revoke all on function public.consume_request_budget(text) from public,anon;
grant execute on function public.consume_request_budget(text) to authenticated;
create function public.consume_internal_request_budget(p_owner uuid,p_endpoint text) returns jsonb
language sql security definer set search_path='' as $$
 select nb.consume_request_budget(p_owner,p_endpoint);
$$;
revoke all on function public.consume_internal_request_budget(uuid,text) from public,anon,authenticated;
grant execute on function public.consume_internal_request_budget(uuid,text) to service_role;
