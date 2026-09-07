begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(3);
insert into auth.users(id) values ('05050505-0000-4000-8000-000000000001');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
  ('05050505-0000-4000-8000-000000000001','test','granted','test','en');
select set_config('request.jwt.claim.sub','05050505-0000-4000-8000-000000000001',true);
select set_config('nb.meal_payload',jsonb_build_object('user_day',nb.user_day_of(now(),'UTC'),
  'slot','LUNCH','name','Rice','kcal',500,'protein_g',20,'carb_g',80,'fat_g',10,
  'confidence','MEDIUM','model_version','test-v1')::text,true);
set local role authenticated;
select is(public.apply_meal_operation('05050505-0000-4000-8000-000000000003','create',
  '05050505-0000-4000-8000-000000000004',current_setting('nb.meal_payload')::jsonb)->>'id',
  '05050505-0000-4000-8000-000000000004','create still acknowledges when logged_at is omitted');
select is(public.apply_meal_operation('05050505-0000-4000-8000-000000000005','amend',
  '05050505-0000-4000-8000-000000000004',current_setting('nb.meal_payload')::jsonb ||
  '{"id":"05050505-0000-4000-8000-000000000006","kcal":600,"protein_g":28,"carb_g":40,"fat_g":12,
    "logged_at":"2026-09-06T16:40:00Z","model_version":"manual-v1"}') ->> 'id',
  '05050505-0000-4000-8000-000000000006','amendment acknowledges a replacement that keeps the clock');
select is((select logged_at from public.meals where id='05050505-0000-4000-8000-000000000006'),
  '2026-09-06T16:40:00Z'::timestamptz,
  'replacement stores the edited eating time instead of now()');
reset role;
select * from finish();
rollback;
