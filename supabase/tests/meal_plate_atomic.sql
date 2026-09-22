begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(11);
insert into auth.users(id) values ('07070707-0000-4000-8000-000000000011');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
  ('07070707-0000-4000-8000-000000000011','test','granted','test','en');
select set_config('request.jwt.claim.sub','07070707-0000-4000-8000-000000000011',true);
select set_config('nb.items', jsonb_build_array(
  jsonb_build_object('user_day',nb.user_day_of(now(),'UTC'),'slot','BREAKFAST','name','Egg','kcal',90,
    'protein_g',8,'carb_g',1,'fat_g',6,'portion','1 egg'),
  jsonb_build_object('user_day',nb.user_day_of(now(),'UTC'),'slot','BREAKFAST','name','Rice','kcal',200,
    'protein_g',4,'carb_g',42,'fat_g',1,'portion','1 bowl'),
  jsonb_build_object('user_day',nb.user_day_of(now(),'UTC'),'slot','BREAKFAST','name','Water','kcal',0,
    'protein_g',0,'carb_g',0,'fat_g',0,'portion','1 glass'))::text, true);
set local role authenticated;
select set_config('nb.receipt', public.apply_meal_plate('07070707-0000-4000-8000-0000000000bb',current_setting('nb.items')::jsonb)::text,true);
select is(jsonb_array_length(current_setting('nb.receipt')::jsonb->'meal_ids'),3,'a plate returns every food id including zero kcal');
select is((select count(*)::int from public.meals),3,'each food is its own persisted row');
select is((select sum(kcal)::int from public.meals),290,'persisted items sum to the displayed plate total');
select is(public.apply_meal_plate('07070707-0000-4000-8000-0000000000bb',current_setting('nb.items')::jsonb)->'meal_ids',
  current_setting('nb.receipt')::jsonb->'meal_ids','a response-loss retry returns the same canonical ids');
select is((select count(*)::int from public.meals),3,'retry never duplicates foods');
select throws_ok($$select public.apply_meal_plate('07070707-0000-4000-8000-0000000000bb',current_setting('nb.items')::jsonb - 2)$$,
  'OPERATION_CONFLICT','a truncated retry is not a different successful plate');
select throws_ok($$select public.apply_meal_plate('07070707-0000-4000-8000-0000000000cc',
  current_setting('nb.items')::jsonb || '[{"name":"invalid"}]'::jsonb)$$,
  'INVALID_MEAL','a later invalid item rejects the whole plate');
select is((select count(*)::int from public.meals),3,'a late validation failure leaves no partial plate');
select lives_ok($$select public.apply_meal_operation('07070707-0000-4000-8000-000000000012','amend',
  (current_setting('nb.receipt')::jsonb->'meal_ids'->>0)::uuid,
  current_setting('nb.items')::jsonb->0 || '{"id":"07070707-0000-4000-8000-000000000013","kcal":80}')$$,
  'one food can be amended independently');
select is((select sum(kcal)::int from public.meals where deleted_at is null),280,'amending one food recomputes the active item total');
reset role;
insert into public.consents(user_id,consent_version,choice,text_sha256,locale,decided_at) values
  ('07070707-0000-4000-8000-000000000011','test','withdrawn','test','en',now()+interval '1 second');
set local role authenticated;
select throws_ok($$select public.apply_meal_plate('07070707-0000-4000-8000-0000000000dd',current_setting('nb.items')::jsonb)$$,
  'CONSENT_WITHDRAWN','consent withdrawal prevents cloud writes');
reset role;
select * from finish();
rollback;
