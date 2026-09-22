begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select plan(18);
insert into auth.users(id) values ('08080808-0000-4000-8000-000000000001'),('08080808-0000-4000-8000-000000000002');
insert into public.profiles(user_id) values ('08080808-0000-4000-8000-000000000001'),('08080808-0000-4000-8000-000000000002') on conflict do nothing;
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
 ('08080808-0000-4000-8000-000000000001','test','granted','test','en'),
 ('08080808-0000-4000-8000-000000000002','test','granted','test','en');
select set_config('request.jwt.claim.sub','08080808-0000-4000-8000-000000000001',true);
set local role authenticated;
select lives_ok($$insert into storage.objects(bucket_id,name) values('meal-photos','08080808-0000-4000-8000-000000000001/plate.jpg')$$,
 'an owner with consent can upload');
select lives_ok($$update storage.objects set metadata='{"size":12}' where bucket_id='meal-photos' and name='08080808-0000-4000-8000-000000000001/plate.jpg'$$,
 'upsert metadata is permitted for an eligible owner');
select is((select metadata->>'size' from storage.objects where name='08080808-0000-4000-8000-000000000001/plate.jpg'),'12','update actually changed its own row');
select throws_ok($$insert into storage.objects(bucket_id,name) values('meal-photos','08080808-0000-4000-8000-000000000002/stolen.jpg')$$,
 '42501',null,'a caller cannot upload into another account');
select throws_ok($$insert into storage.objects(bucket_id,name) values('meal-photos','08080808-0000-4000-8000-000000000001/nested/plate.jpg')$$,
 '22023','INVALID_MEAL_PHOTO_PATH','nested keys cannot escape exhaustive prefix cleanup');
select throws_ok($$update storage.objects set name='08080808-0000-4000-8000-000000000001/moved.jpg' where name='08080808-0000-4000-8000-000000000001/plate.jpg'$$,
 '42501','MEAL_PHOTO_PATH_IMMUTABLE','a persisted photo cannot be moved away from its ledger path');
select is(public.account_delete('DELETE')->>'error','USE_ACCOUNT_DELETE_ENDPOINT','legacy deletion refuses when only meal photos remain');
reset role;
select is((select count(*)::int from auth.users where id='08080808-0000-4000-8000-000000000001'),1,'blocked legacy deletion preserves the user');
insert into public.meal_favorites(id,user_id,label,items) values
 ('08080808-0000-4000-8000-000000000011','08080808-0000-4000-8000-000000000001','My plate','[{"name":"Egg","kcal":90}]'),
 ('08080808-0000-4000-8000-000000000012','08080808-0000-4000-8000-000000000002','Other plate','[{"name":"Rice","kcal":200}]');
set local role authenticated;
select is(jsonb_array_length(public.export_all()->'meal_favorites'),1,'export includes only the caller favorites');
select is(public.export_all()->'meal_favorites'->0->>'label','My plate','export retains saved plate content');
reset role;
insert into public.consents(user_id,consent_version,choice,text_sha256,locale,decided_at) values
 ('08080808-0000-4000-8000-000000000001','test','withdrawn','test','en',now()+interval '1 second');
set local role authenticated;
select throws_ok($$insert into storage.objects(bucket_id,name) values('meal-photos','08080808-0000-4000-8000-000000000001/denied.jpg')$$,
 '42501','CONSENT_WITHDRAWN','withdrawal blocks authenticated photo collection');
select throws_ok($$update storage.objects set metadata='{}' where name='08080808-0000-4000-8000-000000000001/plate.jpg'$$,
 '42501','CONSENT_WITHDRAWN','withdrawal also blocks replacement');
reset role;
set local role service_role;
select throws_ok($$insert into storage.objects(bucket_id,name) values('meal-photos','08080808-0000-4000-8000-000000000001/service-denied.jpg')$$,
 '42501','CONSENT_WITHDRAWN','service-role RLS bypass cannot bypass withdrawal');
reset role;
update public.profiles set deletion_requested_at=now() where user_id='08080808-0000-4000-8000-000000000002';
set local role service_role;
select throws_ok($$insert into storage.objects(bucket_id,name) values('meal-photos','08080808-0000-4000-8000-000000000002/tombstoned.jpg')$$,
 '42501','ACCOUNT_UNAVAILABLE','tombstone blocks service-role uploads');
select lives_ok($$delete from storage.objects where bucket_id='meal-photos' and name='08080808-0000-4000-8000-000000000001/plate.jpg'$$,
 'cleanup remains possible after withdrawal');
reset role;
select ok(not has_function_privilege('authenticated','nb.guard_meal_photo()','EXECUTE'),'private photo guard is not a callable authenticated RPC');
select ok(not has_function_privilege('anon','nb.lock_meal_consent_owner()','EXECUTE'),'private consent trigger is not a public RPC');
select is(public.account_delete('DELETE')->>'deleted','true','legacy deletion still succeeds once external photo bytes are gone');
select * from finish();
rollback;
