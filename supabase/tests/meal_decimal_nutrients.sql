begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(12);
insert into auth.users(id) values ('07070707-0000-4000-8000-000000000021');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
  ('07070707-0000-4000-8000-000000000021','test','granted','test','en');
select set_config('request.jwt.claim.sub','07070707-0000-4000-8000-000000000021',true);
select set_config('nb.decimal_meal',jsonb_build_object(
  'user_day',nb.user_day_of(now(),'UTC'),'slot','LUNCH','name','Yoghurt',
  'kcal',123.4,'protein_g',23.6,'carb_g',8.2,'fat_g',2.5,'fiber_g',1.3,'sodium_mg',45.7)::text,true);
set local role authenticated;
select lives_ok($$select public.apply_meal_operation('07070707-0000-4000-8000-000000000022','create',
  '07070707-0000-4000-8000-000000000023',current_setting('nb.decimal_meal')::jsonb)$$,
  'fractional meals can be written');
select is((select kcal from public.meals),123.4::numeric,'energy retains decimals');
select is((select protein_g from public.meals),23.6::numeric,'macros retain decimals');
select is((select sodium_mg from public.meals),45.7::numeric,'micronutrients retain decimals');
select is((select sugar_g from public.meals),null::numeric,'missing nutrients remain unknown');
select is(public.apply_meal_operation('07070707-0000-4000-8000-000000000022','create',
  '07070707-0000-4000-8000-000000000023',current_setting('nb.decimal_meal')::jsonb)->>'replay','true',
  'identical decimal retry is idempotent');
select throws_ok($$select public.apply_meal_operation('07070707-0000-4000-8000-000000000022','create',
  '07070707-0000-4000-8000-000000000023',current_setting('nb.decimal_meal')::jsonb || '{"protein_g":23.7}')$$,
  'OPERATION_CONFLICT','fractional differences are not silently acknowledged');
select throws_ok($$select public.apply_meal_operation('07070707-0000-4000-8000-000000000024','create',
  '07070707-0000-4000-8000-000000000025',current_setting('nb.decimal_meal')::jsonb || '{"protein_g":-0.1}')$$,
  'INVALID_MEAL','negative fractions are rejected');
select throws_ok($$select public.apply_meal_operation('07070707-0000-4000-8000-000000000024','create',
  '07070707-0000-4000-8000-000000000025',current_setting('nb.decimal_meal')::jsonb || '{"kcal":100000.1}')$$,
  'INVALID_MEAL','fractional values retain upper bounds');
select lives_ok($$select public.apply_meal_operation('07070707-0000-4000-8000-000000000024','amend',
  '07070707-0000-4000-8000-000000000023',current_setting('nb.decimal_meal')::jsonb ||
  '{"id":"07070707-0000-4000-8000-000000000025","protein_g":11.8,"kcal":61.7}')$$,
  'amendments retain fractional values');
select is((select protein_g from public.meals where deleted_at is null),11.8::numeric,'amended decimal survives readback');
select set_config('request.jwt.claim.sub','07070707-0000-4000-8000-000000000099',true);
select is((select count(*)::int from public.meals),0,'another account cannot read fractional records');
reset role;
select * from finish();
rollback;
