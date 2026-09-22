-- 一次估算是一盘饭：组、份量、照片、微量三项随写入落行，且照片路径必须属于写它的人。
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(7);
insert into auth.users(id) values ('07070707-0000-4000-8000-000000000001');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
  ('07070707-0000-4000-8000-000000000001','test','granted','test','en');
select set_config('request.jwt.claim.sub','07070707-0000-4000-8000-000000000001',true);
select set_config('nb.plate', jsonb_build_object(
  'user_day', nb.user_day_of(now(),'UTC'), 'slot','LUNCH', 'name','米饭', 'kcal',200,
  'protein_g',4, 'carb_g',44, 'fat_g',1, 'confidence','MEDIUM', 'model_version','test-v1',
  'meal_group_id','07070707-0000-4000-8000-0000000000aa', 'portion','1 碗',
  'photo_path','07070707-0000-4000-8000-000000000001/plate.jpg',
  'sodium_mg',2)::text, true);
set local role authenticated;

select is(public.apply_meal_operation('07070707-0000-4000-8000-000000000003','create',
  '07070707-0000-4000-8000-000000000004', current_setting('nb.plate')::jsonb)->>'id',
  '07070707-0000-4000-8000-000000000004', 'a plate row is written');

select is((select portion from public.meals where id='07070707-0000-4000-8000-000000000004'),
  '1 碗', 'the portion the model estimated is kept rather than dropped');
select is((select meal_group_id from public.meals where id='07070707-0000-4000-8000-000000000004'),
  '07070707-0000-4000-8000-0000000000aa'::uuid, 'every row of one estimate shares its group');
select is((select sodium_mg from public.meals where id='07070707-0000-4000-8000-000000000004'),
  2::numeric, 'a micronutrient the model knew is stored');
-- ⚠️ Absent is absent. A column nobody reported must stay null: 0 is what this product
-- writes when a parser fails, not when a nutrient is unknown.
select is((select fiber_g from public.meals where id='07070707-0000-4000-8000-000000000004'),
  null, 'a micronutrient nobody reported stays null, never 0');

-- A photo path is inside the writer's own prefix or it is not a photo path at all.
select throws_ok($$select public.apply_meal_operation(
  '07070707-0000-4000-8000-000000000005','create','07070707-0000-4000-8000-000000000006',
  current_setting('nb.plate')::jsonb || '{"photo_path":"99999999-0000-4000-8000-000000000009/stolen.jpg"}')$$,
  'INVALID_MEAL', 'a photo path belonging to someone else is refused');

-- The append-only trigger has to know about the new columns, or they are quietly mutable.
select throws_ok($$update public.meals set portion='10 碗'
  where id='07070707-0000-4000-8000-000000000004'$$,
  'meals is append-only: an edit is a soft delete plus a new row',
  'the plate fields are as immutable as the nutrients beside them');

reset role;
select * from finish();
rollback;
