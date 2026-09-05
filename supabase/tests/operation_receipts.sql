begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(15);
insert into auth.users(id) values ('03030303-0000-4000-8000-000000000001'),('03030303-0000-4000-8000-000000000002');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values ('03030303-0000-4000-8000-000000000001','test','granted','test','en');
select set_config('request.jwt.claim.sub','03030303-0000-4000-8000-000000000001',true);
select set_config('nb.meal_payload',jsonb_build_object('user_day',nb.user_day_of(now(),'UTC'),
 'slot','LUNCH','name','Rice','kcal',500,'protein_g',20,'carb_g',80,'fat_g',10,
 'confidence','MEDIUM','model_version','test-v1')::text,true);
set local role authenticated;
select is(public.apply_meal_operation('03030303-0000-4000-8000-000000000003','create',
 '03030303-0000-4000-8000-000000000004',current_setting('nb.meal_payload')::jsonb)->>'id',
 '03030303-0000-4000-8000-000000000004','authenticated create acknowledges the exact row');
select is(public.apply_meal_operation('03030303-0000-4000-8000-000000000003','create',
 '03030303-0000-4000-8000-000000000004',current_setting('nb.meal_payload')::jsonb)->>'replay','true',
 'lost-response retry returns the original receipt');
select is((select count(*)::integer from public.meals),1,'retry does not duplicate intake');
select throws_ok($$select public.apply_meal_operation('03030303-0000-4000-8000-000000000003','create',
 '03030303-0000-4000-8000-000000000004',current_setting('nb.meal_payload')::jsonb || '{"kcal":600}')$$,
 '23505','OPERATION_CONFLICT','changed payload under same id is rejected');
select throws_ok($$select public.apply_meal_operation('03030303-0000-4000-8000-000000000008','create',
 '03030303-0000-4000-8000-000000000009',current_setting('nb.meal_payload')::jsonb || '{"kcal":null}')$$,
 '22023','INVALID_MEAL','direct RPC cannot bypass kcal validation');
select is(public.apply_meal_operation('03030303-0000-4000-8000-000000000005','amend',
 '03030303-0000-4000-8000-000000000004',current_setting('nb.meal_payload')::jsonb ||
 '{"id":"03030303-0000-4000-8000-000000000006","kcal":600,"model_version":"manual-v1"}') ->> 'id',
 '03030303-0000-4000-8000-000000000006','amendment acknowledges a new immutable record');
select is((select kcal from public.meals where id='03030303-0000-4000-8000-000000000004'),500,
 'original estimate remains unchanged after amendment');
select is((select sum(kcal)::integer from public.meals where deleted_at is null),600,
 'visible intake counts only the replacement');
select is(public.apply_meal_operation('03030303-0000-4000-8000-000000000007','delete',
 '03030303-0000-4000-8000-000000000006','{}')->>'operation_id',
 '03030303-0000-4000-8000-000000000007','delete acknowledges its exact operation');
select is((select count(*)::integer from public.meals where deleted_at is null),0,'delete removes meal from visible intake');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale,decided_at)
 values ('03030303-0000-4000-8000-000000000001','test','withdrawn','test','en',now()+interval '1 second');
select throws_ok($$select public.apply_meal_operation('03030303-0000-4000-8000-000000000008','create',
 '03030303-0000-4000-8000-000000000009',current_setting('nb.meal_payload')::jsonb)$$,
 '42501','CONSENT_WITHDRAWN','withdrawal blocks queued collection at the server boundary');
select lives_ok($$select public.apply_meal_operation('03030303-0000-4000-8000-000000000008','delete',
 '03030303-0000-4000-8000-000000000006','{}')$$,'withdrawal still permits explicit meal removal');
select set_config('request.jwt.claim.sub','03030303-0000-4000-8000-000000000002',true);
select is((select count(*)::integer from public.meal_operations),0,'receipt RLS isolates accounts');
select throws_ok($$select public.apply_meal_operation('03030303-0000-4000-8000-000000000008','delete',
 '03030303-0000-4000-8000-000000000004','{}')$$,'P0002','MEAL_NOT_FOUND','another account cannot delete the meal');
select ok(not has_function_privilege('anon','public.apply_meal_operation(uuid,text,uuid,jsonb)','execute'),
 'anonymous clients cannot operate meal receipts');
reset role;
select * from finish();
rollback;
