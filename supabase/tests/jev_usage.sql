-- ADR 0031 · what the routing provider costs, and how an attempt is booked.
--
-- Three claims: Jev is priced as Jev and not at the '*' fallback; the same attempt cannot
-- charge the day twice while a real retry can; an attempt whose cost we never learned is
-- recorded as an estimate that still counts against the spend cap.
begin;
select plan(16);

insert into auth.users(id) values('eeeeeeee-1111-1111-1111-111111111111');
insert into public.profiles(user_id,timezone) values('eeeeeeee-1111-1111-1111-111111111111','Asia/Shanghai')
on conflict(user_id) do update set timezone=excluded.timezone;
insert into nb.ai_quotas(user_id,remaining,settled_day,spent_fen,spent_day,daily_grant,grant_cap,spend_cap_fen)
values('eeeeeeee-1111-1111-1111-111111111111',10,
       nb.user_day('eeeeeeee-1111-1111-1111-111111111111'),0,
       nb.user_day('eeeeeeee-1111-1111-1111-111111111111'),10,20,200)
on conflict(user_id) do update set remaining=excluded.remaining,settled_day=excluded.settled_day,
 spent_fen=excluded.spent_fen,spent_day=excluded.spent_day,daily_grant=excluded.daily_grant,
 grant_cap=excluded.grant_cap,spend_cap_fen=excluded.spend_cap_fen;

-- ---------------------------------------------------------------- the price exists
select is((select prompt_fen_per_million from nb.ai_price_book where model_id='jev-1.13.0'),31,
 'the routing provider has its own price, not the catch-all');
select isnt((select prompt_fen_per_million from nb.ai_price_book where model_id='jev-1.13.0'),
 (select prompt_fen_per_million from nb.ai_price_book where model_id='*'),
 'and it is not the price of another provider');
select is((select completion_fen_per_million from nb.ai_price_book where model_id='jev-1.13.0'),0,
 'output tokens are free, as published');

set local role service_role;
-- A real routing batch: 1304 input tokens, 354 output. 1304 × 31 / 1e6 = 0.040424 fen.
select public.record_ai_usage_trusted('eeeeeeee-1111-1111-1111-111111111111','turn','jev-1.13.0',
 1304,0,354,null,1032,0,'jev:route:1','11111111-aaaa-4aaa-8aaa-111111111111','reported');
reset role;
select is((select cost_fen from nb.ai_model_calls where attempt_id='11111111-aaaa-4aaa-8aaa-111111111111'),
 0.040424::numeric,'a routing batch is billed on input tokens alone');
select is((select spent_fen from nb.ai_quotas where user_id='eeeeeeee-1111-1111-1111-111111111111'),
 0.040424::numeric,'and it lands on the day''s spend');

-- ---------------------------------------------------------------- idempotent per attempt
set local role service_role;
select public.record_ai_usage_trusted('eeeeeeee-1111-1111-1111-111111111111','turn','jev-1.13.0',
 1304,0,354,null,1032,0,'jev:route:1','11111111-aaaa-4aaa-8aaa-111111111111','reported');
reset role;
select is((select count(*)::int from nb.ai_model_calls where attempt_id='11111111-aaaa-4aaa-8aaa-111111111111'),1,
 'the same attempt recorded twice is one row');
select is((select spent_fen from nb.ai_quotas where user_id='eeeeeeee-1111-1111-1111-111111111111'),
 0.040424::numeric,'and it does not charge the day twice');

-- A genuine retry is a different attempt under the same logical call, and it is billed.
set local role service_role;
select public.record_ai_usage_trusted('eeeeeeee-1111-1111-1111-111111111111','turn','jev-1.13.0',
 1304,0,354,null,1200,0,'jev:route:1','11111111-aaaa-4aaa-8aaa-222222222222','reported');
reset role;
select is((select count(*)::int from nb.ai_model_calls where logical_call_id='jev:route:1'),2,
 'a retry is another attempt of the same logical call');
select is((select spent_fen from nb.ai_quotas where user_id='eeeeeeee-1111-1111-1111-111111111111'),
 0.080848::numeric,'and the retry is charged');

-- ---------------------------------------------------------------- unknown cost
set local role service_role;
select public.record_ai_usage_trusted('eeeeeeee-1111-1111-1111-111111111111','turn','jev-1.13.0',
 2500,0,0,null,1500,0,'jev:route:2','11111111-aaaa-4aaa-8aaa-333333333333','unknown');
reset role;
select is((select cost_state from nb.ai_model_calls where attempt_id='11111111-aaaa-4aaa-8aaa-333333333333'),
 'unknown','an attempt with no usage is marked as an estimate');
select ok((select spent_fen from nb.ai_quotas where user_id='eeeeeeee-1111-1111-1111-111111111111') > 0.080848::numeric,
 'and the estimate still counts against the day''s spend');

set local role service_role;
select throws_ok(
 $$select public.record_ai_usage_trusted('eeeeeeee-1111-1111-1111-111111111111','turn','jev-1.13.0',1,0,0,null,1,0,'x','11111111-aaaa-4aaa-8aaa-444444444444','guessed')$$,
 '22023','INVALID_COST_STATE','a cost state outside the two real ones is refused');
reset role;

select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='record_ai_usage_trusted'),1,
 'only one accounting signature exists, so old callers remain unambiguous');
select ok(not has_function_privilege('anon',
 'public.record_ai_usage_trusted(uuid,text,text,integer,integer,integer,uuid,integer,numeric,text,uuid,text)','execute'),
 'anonymous callers cannot record trusted usage');
select ok(not has_function_privilege('authenticated',
 'public.record_ai_usage_trusted(uuid,text,text,integer,integer,integer,uuid,integer,numeric,text,uuid,text)','execute'),
 'authenticated callers cannot submit trusted usage');
select ok(has_function_privilege('service_role',
 'public.record_ai_usage_trusted(uuid,text,text,integer,integer,integer,uuid,integer,numeric,text,uuid,text)','execute'),
 'server accounting remains callable');
select * from finish();
rollback;
