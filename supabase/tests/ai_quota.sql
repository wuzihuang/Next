begin;
select plan(17);
insert into auth.users(id) values('dddddddd-1111-1111-1111-111111111111');
-- User-day boundaries are always taken from the DB, including when UTC has
-- crossed midnight but this user's 04:00 boundary has not.
insert into public.profiles(user_id,timezone) values('dddddddd-1111-1111-1111-111111111111','America/Los_Angeles')
on conflict(user_id) do update set timezone=excluded.timezone;
-- ⚠️ The three knobs are per-user since 20260906160000, and the column defaults are the
-- raised development ones (1000 a day against a 5000 cap). This suite is about the
-- mechanism — the daily grant, the cap it rolls up to, the spend ceiling that refuses
-- while count remains — so it pins its own numbers instead of asserting whatever the
-- current defaults happen to be. Ten a day, twenty in the bank, two yuan.
insert into nb.ai_quotas(user_id,remaining,settled_day,spent_fen,spent_day,daily_grant,grant_cap,spend_cap_fen)
values('dddddddd-1111-1111-1111-111111111111',10,
       nb.user_day('dddddddd-1111-1111-1111-111111111111'),0,
       nb.user_day('dddddddd-1111-1111-1111-111111111111'),10,20,200)
on conflict(user_id) do update set remaining=excluded.remaining,settled_day=excluded.settled_day,
 spent_fen=excluded.spent_fen,spent_day=excluded.spent_day,daily_grant=excluded.daily_grant,
 grant_cap=excluded.grant_cap,spend_cap_fen=excluded.spend_cap_fen;
set local role service_role;
select is((select count(*)::int from generate_series(1,10) g where (public.consume_ai_quota_trusted('dddddddd-1111-1111-1111-111111111111','turn',gen_random_uuid())->>'allowed')::boolean),10,'new day admits ten logical operations');
select is((public.consume_ai_quota_trusted('dddddddd-1111-1111-1111-111111111111','turn',gen_random_uuid())->>'allowed')::boolean,false,'eleventh operation is refused');
reset role;
update nb.ai_quotas set settled_day=nb.user_day(user_id)-1,remaining=5 where user_id='dddddddd-1111-1111-1111-111111111111';
set local role service_role;
select is((public.consume_ai_quota_trusted('dddddddd-1111-1111-1111-111111111111','asr','aaaaaaaa-1111-1111-1111-111111111111')->>'remaining')::int,14,'unused count rolls forward by ten');
select is((public.consume_ai_quota_trusted('dddddddd-1111-1111-1111-111111111111','turn','aaaaaaaa-1111-1111-1111-111111111111')->>'remaining')::int,14,'ASR and answer share one count');
select is((public.consume_ai_quota_trusted('dddddddd-1111-1111-1111-111111111111','asr','aaaaaaaa-1111-1111-1111-111111111111')->>'allowed')::boolean,true,'one ASR fallback remains allowed');
select is((public.consume_ai_quota_trusted('dddddddd-1111-1111-1111-111111111111','asr','aaaaaaaa-1111-1111-1111-111111111111')->>'allowed')::boolean,false,'operation id cannot admit unlimited ASR calls');
reset role;
update nb.ai_quotas set remaining=5,spent_fen=200,spent_day=nb.user_day(user_id) where user_id='dddddddd-1111-1111-1111-111111111111';
set local role service_role;
select is((public.consume_ai_quota_trusted('dddddddd-1111-1111-1111-111111111111','turn',gen_random_uuid())->>'reason'),'spend','spend cap refuses while count remains');
select is((public.check_ai_spend_trusted('dddddddd-1111-1111-1111-111111111111')->>'reason'),'spend','inter-step check blocks new model calls at the cap');
select is((public.consume_ai_quota_trusted('dddddddd-1111-1111-1111-111111111111','turn','aaaaaaaa-1111-1111-1111-111111111111')->>'reason'),'spend','same operation still checks spend');
reset role;
update nb.ai_quotas set settled_day=nb.user_day(user_id)-40,remaining=10,spent_fen=0,spent_day=nb.user_day(user_id)-40 where user_id='dddddddd-1111-1111-1111-111111111111';
set local role service_role;
select is((public.consume_ai_quota_trusted('dddddddd-1111-1111-1111-111111111111','turn',gen_random_uuid())->>'remaining')::int,19,'idle balance never exceeds twenty');
select public.record_ai_usage_trusted('dddddddd-1111-1111-1111-111111111111','turn','qwen3.8-flash',10,0,0,null,12);
select public.record_ai_usage_trusted('dddddddd-1111-1111-1111-111111111111','asr','qwen3-asr-flash-realtime',0,0,0,null,12,10);
reset role;
select is((select spent_fen from nb.ai_quotas where user_id='dddddddd-1111-1111-1111-111111111111'),0.330800::numeric,'fractional tokens and ASR seconds accumulate without per-call rounding');
select is((select min(user_day) from nb.ai_model_calls where user_id='dddddddd-1111-1111-1111-111111111111'),nb.user_day('dddddddd-1111-1111-1111-111111111111'),'recording shares the quota user-day');
select is((select count(*)::int from nb.ai_model_calls where user_id='dddddddd-1111-1111-1111-111111111111'),2,'each provider call is recorded');
select ok(not has_function_privilege('authenticated','public.consume_ai_quota_trusted(uuid,text,uuid)','execute'),'clients cannot grant their own quota');
select ok(not has_function_privilege('authenticated','public.record_ai_usage_trusted(uuid,text,text,integer,integer,integer,uuid,integer,numeric)','execute'),'clients cannot fabricate their own costs');
set local role service_role;
select throws_ok($$select public.consume_ai_quota_trusted('dddddddd-1111-1111-1111-111111111111','export',gen_random_uuid())$$,'22023','UNKNOWN_ENDPOINT','unknown endpoints fail closed');
select throws_ok($$select public.record_ai_usage_trusted('dddddddd-1111-1111-1111-111111111111','turn','qwen3.8-flash',-1,0,0,null,null)$$,'22023','INVALID_USAGE','negative provider usage is rejected');
reset role;
select * from finish();
rollback;
