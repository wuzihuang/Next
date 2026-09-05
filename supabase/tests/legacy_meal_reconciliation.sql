begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select plan(4);
insert into auth.users(id) values ('04040404-0000-4000-8000-000000000001');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale)
values ('04040404-0000-4000-8000-000000000001','test','granted','test','en');
select set_config('request.jwt.claim.sub','04040404-0000-4000-8000-000000000001',true);
select set_config('nb.meal_payload','{"user_day":"2026-09-04","slot":"DINNER","name":"Test dinner","kcal":1200,"protein_g":45,"carb_g":80,"fat_g":75,"confidence":"LOW","model_version":"qwen3.8-flash/2026-09"}',true);
insert into public.meals(id,user_id,client_op_id,user_day,slot,text_input,kcal,protein_g,carb_g,fat_g,confidence,model_version)
values ('04040404-0000-4000-8000-000000000002','04040404-0000-4000-8000-000000000001',
'04040404-0000-4000-8000-000000000003','2026-09-04','DINNER','Test dinner',1200,45,80,75,'LOW','qwen3.8-flash/2026-09');
set local role authenticated;
select throws_ok($$select public.apply_meal_operation('04040404-0000-4000-8000-000000000003','create',
'04040404-0000-4000-8000-000000000004',current_setting('nb.meal_payload')::jsonb)$$,
'23505','OPERATION_CONFLICT','original local id reproduces legacy cloud conflict');
select is(public.apply_meal_operation('04040404-0000-4000-8000-000000000003','create',
'04040404-0000-4000-8000-000000000002',current_setting('nb.meal_payload')::jsonb)->>'id',
'04040404-0000-4000-8000-000000000002','verified canonical id acknowledges existing meal');
select is((select count(*)::integer from public.meals),1,'canonical replay does not duplicate or delete the meal');
select is(public.apply_meal_operation('04040404-0000-4000-8000-000000000003','create',
'04040404-0000-4000-8000-000000000002',current_setting('nb.meal_payload')::jsonb)->>'replay','true','canonical retry remains idempotent');
reset role;
select * from finish();
rollback;
