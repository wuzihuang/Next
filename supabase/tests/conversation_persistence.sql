begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select plan(23);
insert into auth.users(id) values('04040404-0000-4000-8000-000000000001'),('04040404-0000-4000-8000-000000000002');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale,ms_on_screen)
values('04040404-0000-4000-8000-000000000001','test','granted','test','en-US',1000),('04040404-0000-4000-8000-000000000002','test','granted','test','en-US',1000);
select set_config('request.jwt.claim.sub','04040404-0000-4000-8000-000000000001',true);
set local role authenticated;
select is(public.record_ai_turn('04040404-0000-4000-8000-000000000003','Yesterday HRV','{"sentence":"65 ms","ttl_min":20}','[{"tool":"test"}]',10,'test','04040404-0000-4000-8000-000000000004')->>'replay','false','authenticated user saves turn');
select is(public.record_ai_turn('04040404-0000-4000-8000-000000000003','Yesterday HRV','{"sentence":"65 ms","ttl_min":20}','[{"tool":"test"}]',10,'test','04040404-0000-4000-8000-000000000004')->>'replay','true','same turn replays');
select is((select count(*)::integer from public.screen_frames),1,'replay has one frame');
select is(jsonb_array_length(public.conversation_context('04040404-0000-4000-8000-000000000004')),2,'replay has one pair of messages');
select throws_ok($$select public.record_ai_turn('04040404-0000-4000-8000-000000000003','Yesterday HRV','{}','[]',10,'test','04040404-0000-4000-8000-000000000005')$$,'23505','TURN_CONFLICT','turn cannot move conversations');
select throws_ok($$select public.record_ai_turn('04040404-0000-4000-8000-000000000006',null,'{}','[]',10,'test')$$,'22023','INVALID_TURN','null input rejected explicitly');
select throws_ok($$select public.record_ai_turn('04040404-0000-4000-8000-000000000006','test',null,'[]',10,'test')$$,'22023','INVALID_TURN','null envelope rejected explicitly');
select ok((select tool_trace='[{"tool":"test"}]'::jsonb from public.ai_turns limit 1),'trace stored in ai_turns');
select ok(not exists(select 1 from public.screen_frames where tool_calls is not null and tool_calls <> '[]'::jsonb),'frame does not duplicate trace');
select throws_ok($$select public.record_ai_turn('04040404-0000-4000-8000-000000000006','test','{}',null,10,'test')$$,'22023','INVALID_TURN','null trace rejected');
do $$ begin for i in 1..15 loop
 perform public.record_ai_turn(md5('conversation-test-'||i::text)::uuid,'User request '||i::text,'{"sentence":"Assistant claims 98765"}','[]',10,'test','04040404-0000-4000-8000-000000000004');
end loop; end $$;
select is(jsonb_array_length(public.conversation_context('04040404-0000-4000-8000-000000000004')),24,'recent context is bounded');
select ok((public.conversation_summary('04040404-0000-4000-8000-000000000004')->>'text') like '%User request 1%','older user requests survive in deterministic excerpt memory');
select ok((public.conversation_summary('04040404-0000-4000-8000-000000000004')->>'text') not like '%98765%','memory does not turn assistant claims into user facts');
select is((select count(*)::integer from public.conversation_messages),32,'bounded context retains original full message history');
select is(public.record_ai_turn_context('04040404-0000-4000-8000-000000000007','That week','{}','[]',10,'test','04040404-0000-4000-8000-000000000004',
 '{"dayKey":"2026-09-04","from":"2026-08-29","to":"2026-09-04","queryText":"weekly HRV","explicitRange":true}') ->> 'replay','false','query context persists atomically with completed turn');
select public.record_ai_turn_context('04040404-0000-4000-8000-000000000007','That week','{}','[]',10,'test','04040404-0000-4000-8000-000000000004',
 '{"dayKey":"2026-09-05","from":"2026-09-05","to":"2026-09-05","queryText":"changed","explicitRange":false}');
select is(public.conversation_summary('04040404-0000-4000-8000-000000000004')#>>'{lastQueryContext,from}','2026-08-29','replay cannot overwrite original query interval');
select throws_ok($$select public.record_ai_turn_context('04040404-0000-4000-8000-000000000008','test','{}','[]',10,'test','04040404-0000-4000-8000-000000000004',
 '{"dayKey":"2026-02-30","from":"2026-02-30","to":"2026-02-30","queryText":"test","explicitRange":true}')$$,'22023','INVALID_QUERY_CONTEXT','invalid dates cannot enter persisted query context');
select set_config('request.jwt.claim.sub','04040404-0000-4000-8000-000000000002',true);
select is(jsonb_array_length(public.conversation_context('04040404-0000-4000-8000-000000000004')),0,'other owner cannot read history');
select throws_ok($$select public.record_ai_turn('04040404-0000-4000-8000-000000000006','test','{}','[]',10,'test','04040404-0000-4000-8000-000000000004')$$,'42501','CONVERSATION_NOT_FOUND','other owner cannot append history');
reset role;
update public.consents set choice='withdrawn' where user_id='04040404-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub','04040404-0000-4000-8000-000000000001',true);
set local role authenticated;
select throws_ok($$select public.record_ai_turn('04040404-0000-4000-8000-000000000006','test','{}','[]',10,'test')$$,'42501','CONSENT_WITHDRAWN','withdrawn consent blocks new turn');
select throws_ok($$select public.conversation_context('04040404-0000-4000-8000-000000000004')$$,'42501','CONSENT_WITHDRAWN','withdrawn consent blocks history');
reset role;
update public.consents set choice='granted' where user_id='04040404-0000-4000-8000-000000000001';
insert into public.profiles(user_id,deletion_requested_at) values('04040404-0000-4000-8000-000000000001',now()) on conflict(user_id) do update set deletion_requested_at=now();
set local role authenticated;
select throws_ok($$select public.record_ai_turn('04040404-0000-4000-8000-000000000006','test','{}','[]',10,'test')$$,'42501','ACCOUNT_DELETING','deleting account blocks new turn');
reset role;
delete from auth.users where id='04040404-0000-4000-8000-000000000001';
select is((select count(*)::integer from public.conversation_messages),0,'account deletion removes messages');
select * from finish();
rollback;
