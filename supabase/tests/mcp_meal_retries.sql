begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(15);

insert into auth.users(id) values
  ('ac100000-0000-4000-8000-000000000001'),
  ('ac100000-0000-4000-8000-000000000002');
insert into public.profiles(user_id,timezone) values
  ('ac100000-0000-4000-8000-000000000001','UTC'),
  ('ac100000-0000-4000-8000-000000000002','UTC')
on conflict (user_id) do update set timezone=excluded.timezone;
insert into public.consents(user_id,consent_version,choice,text_sha256,locale)
select id,'test','granted','test','en' from auth.users
where id in ('ac100000-0000-4000-8000-000000000001','ac100000-0000-4000-8000-000000000002');
insert into public.mcp_grants(user_id,client_id,client_name,can_write) values
  ('ac100000-0000-4000-8000-000000000001','assistant-a','Review',true),
  ('ac100000-0000-4000-8000-000000000001','assistant-b','Review',true),
  ('ac100000-0000-4000-8000-000000000002','assistant-a','Review',true);
select set_config('request.jwt.claims',
  '{"sub":"ac100000-0000-4000-8000-000000000001","role":"authenticated","client_id":"assistant-a"}',true);
select set_config('nb.mcp_items',
  '[{"name":"Yoghurt","portion":"100 g","kcal":123.4,"protein_g":10.5,"carb_g":8.2,"fat_g":3.1}]',true);
set local role authenticated;
select set_config('nb.mcp_receipt',public.log_mcp_meal(
  'ac100000-0000-4000-8000-000000000010',current_setting('nb.mcp_items')::jsonb)::text,true);
select is(current_setting('nb.mcp_receipt')::jsonb->>'day',current_date::text,'defaults to the owner local day');
select is((select count(*)::int from public.meals),1,'one plate is persisted');
select is((select kcal from public.meals),123.4::numeric,'decimal nutrition is preserved');
select is(public.log_mcp_meal('ac100000-0000-4000-8000-000000000010',current_setting('nb.mcp_items')::jsonb)->>'replay',
  'true','an identical request replays');
reset role;
update public.profiles set timezone='Pacific/Kiritimati' where user_id='ac100000-0000-4000-8000-000000000001';
update public.mcp_grants set client_name='Renamed' where user_id='ac100000-0000-4000-8000-000000000001';
set local role authenticated;
select is(public.log_mcp_meal('ac100000-0000-4000-8000-000000000010',current_setting('nb.mcp_items')::jsonb) - 'replay',
  current_setting('nb.mcp_receipt')::jsonb - 'replay','defaults and source stay frozen on replay after account changes');
select is((select count(*)::int from public.meals),1,'retry never creates another food');
select throws_ok($$select public.log_mcp_meal('ac100000-0000-4000-8000-000000000010',
  '[{"name":"Different food","kcal":10,"protein_g":1,"carb_g":1,"fat_g":1}]')$$,
  '23505','OPERATION_CONFLICT','a changed payload is not acknowledged or duplicated');
select throws_ok($$select public.log_mcp_meal(null,current_setting('nb.mcp_items')::jsonb)$$,
  '22023','INVALID_MEAL_REQUEST','a request id is mandatory');
select throws_ok($$select public.log_mcp_meal('ac100000-0000-4000-8000-000000000011',
  current_setting('nb.mcp_items')::jsonb,now()+interval '1 day')$$,
  '22023','INVALID_MEAL_TIME','future food is rejected');
select set_config('request.jwt.claims',
  '{"sub":"ac100000-0000-4000-8000-000000000002","role":"authenticated","client_id":"assistant-a"}',true);
select is((select count(*)::int from public.meals),0,'another owner cannot read the plate');
select throws_ok($$select public.apply_meal_operation('ac100000-0000-4000-8000-000000000020','delete',
  (current_setting('nb.mcp_receipt')::jsonb->'meal_ids'->>0)::uuid,'{}')$$,
  'P0002','MEAL_NOT_FOUND','another owner cannot delete the plate');
select isnt(public.log_mcp_meal('ac100000-0000-4000-8000-000000000010',current_setting('nb.mcp_items')::jsonb)->>'plate_id',
  current_setting('nb.mcp_receipt')::jsonb->>'plate_id','request ids are scoped to their owner');
reset role;
update public.mcp_grants set can_write=false where user_id='ac100000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok($$select public.log_mcp_meal('ac100000-0000-4000-8000-000000000010',current_setting('nb.mcp_items')::jsonb)$$,
  '42501','MCP_WRITE_NOT_GRANTED','write permission is checked even on replay');
reset role;
update public.mcp_grants set revoked_at=now() where user_id='ac100000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok($$select public.log_mcp_meal('ac100000-0000-4000-8000-000000000010',current_setting('nb.mcp_items')::jsonb)$$,
  '42501','MCP_GRANT_MISSING','revocation is checked even on replay');
select throws_ok($$select * from public.mcp_meal_requests$$,'42501',null,'receipts are not directly exposed');
reset role;
select * from finish();
rollback;
