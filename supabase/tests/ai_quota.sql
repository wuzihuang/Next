begin;
select plan(8);
insert into auth.users(id) values('dddddddd-1111-1111-1111-111111111111');
select set_config('request.jwt.claim.sub','dddddddd-1111-1111-1111-111111111111',true);
set local role authenticated;
select is((select count(*)::int from generate_series(1,10) g where (public.consume_ai_quota('turn')->>'allowed')::boolean),10,'a new day admits ten AI turns');
select is((public.consume_ai_quota('turn')->>'allowed')::boolean,false,'the eleventh turn in one day is refused');
select is((public.consume_ai_quota('meal')->>'allowed')::boolean,false,'meal shares the same daily allowance');
reset role;
update nb.ai_quotas set settled_day=current_date-1, remaining=5 where user_id='dddddddd-1111-1111-1111-111111111111';
set local role authenticated;
select is((public.consume_ai_quota('asr')->>'remaining')::int,14,'unused turns roll forward by ten');
reset role;
update nb.ai_quotas set remaining=5, spent_fen=200, spent_day=current_date
 where user_id='dddddddd-1111-1111-1111-111111111111';
set local role authenticated;
select is((public.consume_ai_quota('turn')->>'reason'),'spend','a spent fen ceiling refuses while count remains');
reset role;
update nb.ai_quotas set settled_day=current_date-40, remaining=10, spent_fen=0, spent_day=current_date-40
 where user_id='dddddddd-1111-1111-1111-111111111111';
set local role authenticated;
select is((public.consume_ai_quota('turn')->>'remaining')::int,19,'idle balance never exceeds twenty');
select public.record_ai_usage('turn','qwen3.8-flash',1000000,0,0,80,current_date,null,12);
select is((select cost_fen from nb.ai_model_calls where user_id='dddddddd-1111-1111-1111-111111111111' limit 1),80,'recorded cost uses the published price book');
reset role;
select throws_ok($$select public.consume_ai_quota('export')$$,'22023','UNKNOWN_ENDPOINT','quota endpoints cannot be chosen by the caller');
delete from auth.users where id='dddddddd-1111-1111-1111-111111111111';
select * from finish();
rollback;
