begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(6);
insert into auth.users(id) values
 ('ae000000-0000-4000-8000-000000000001'),
 ('ae000000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ae000000-0000-4000-8000-000000000001', true);
select lives_ok($$insert into daily_plans(user_id,user_day,title,summary,tasks,read_from,read_to)
 values ('ae000000-0000-4000-8000-000000000001','2026-09-08','No adjustment','No actionable evidence','[]','2026-08-25','2026-09-08')$$,
 'an authenticated owner can save an honest empty result');
select lives_ok($$update daily_plans set tasks='[{"title":"A"}]' where user_day='2026-09-08'$$,
 'an owner can replace the result with a suggestion');
select lives_ok($$update daily_plans set tasks='[]' where user_day='2026-09-08'$$,
 'an owner can replace old suggestions with no actionable evidence');
select throws_ok($$update daily_plans set tasks='[1,2,3,4,5,6]'$$, '23514', null,
 'six suggestions still fail the bound');
select set_config('request.jwt.claim.sub', 'ae000000-0000-4000-8000-000000000002', true);
select is((select count(*) from daily_plans), 0::bigint, 'other accounts cannot read suggestions');
select throws_ok($$insert into daily_plans(user_id,user_day,title,summary,tasks,read_from,read_to)
 values ('ae000000-0000-4000-8000-000000000001','2026-09-09','Wrong owner','No','[]','2026-08-26','2026-09-09')$$, '42501', null,
 'other accounts cannot write suggestions for this owner');
select * from finish();
rollback;
