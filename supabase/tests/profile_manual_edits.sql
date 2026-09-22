begin;
select plan(12);
select set_config('nb.test_day',nb.user_day_of(now(),'UTC')::text,true);
insert into auth.users(id) values ('32320000-0000-4000-8000-000000000001');
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date,goal,field_sources)
values ('32320000-0000-4000-8000-000000000001','UTC','male',180,'1990-01-01','BULK',
  '{"height_cm":"health","birth_date":"health"}');
insert into public.weigh_ins(user_id,measured_at,weight_kg,source,client_op_id)
values ('32320000-0000-4000-8000-000000000001',now()-interval '3 days',70,'health',gen_random_uuid());
insert into public.raw_samples(user_id,ts,sampled_tz,step)
values ('32320000-0000-4000-8000-000000000001',now()-interval '1 minute','UTC',60);
create temporary table original as
select r.kcal as resting, f.target_in
from nb.resting_kcal('32320000-0000-4000-8000-000000000001',current_setting('nb.test_day')::date) r
cross join nb.compute_fuel('32320000-0000-4000-8000-000000000001',current_setting('nb.test_day')::date) f;
create temporary table historical as
select r.kcal from nb.resting_kcal('32320000-0000-4000-8000-000000000001',current_setting('nb.test_day')::date-1) r;
select set_config('request.jwt.claim.sub','32320000-0000-4000-8000-000000000001',true);
set local role authenticated;
select lives_ok($$update public.profiles set height_cm=190, sex='female', birth_date='1995-01-01',
 field_sources=field_sources||'{"height_cm":"edit","sex":"edit","birth_date":"edit"}'::jsonb
 where user_id=auth.uid()$$,'body fields can be edited without Health permission');
select lives_ok($$insert into public.weigh_ins(user_id,measured_at,weight_kg,source,client_op_id)
values (auth.uid(),now(),100,'manual',gen_random_uuid())$$,
 'manual weight is accepted by the account-owned write path');
select ok(public.settle_now(0)>0,'next settlement publishes the changed body inputs');
reset role;
select is((select f.weight_kg from public.day_fuel f join public.daily_results r on r.id=f.result_id
 where r.user_id='32320000-0000-4000-8000-000000000001' and r.user_day=current_setting('nb.test_day')::date),100::numeric,
 'published fuel input weight matches the newly saved weight');
select is((select f.bmr_full_kcal from public.day_fuel f join public.daily_results r on r.id=f.result_id
 where r.user_id='32320000-0000-4000-8000-000000000001' and r.user_day=current_setting('nb.test_day')::date),
 (select round(c.kcal)::integer from nb.resting_kcal('32320000-0000-4000-8000-000000000001',current_setting('nb.test_day')::date) c),
 'published resting calories match the refreshed calculation');
select is((select height_cm from nb.calculation_profile('32320000-0000-4000-8000-000000000001',current_setting('nb.test_day')::date)),190::numeric,
 'current calculation profile reads edited height');
select is((select field_sources->>'birth_date' from public.profiles where user_id='32320000-0000-4000-8000-000000000001'),'edit',
 'manual field provenance survives the save');
select is((select r.kcal from nb.resting_kcal('32320000-0000-4000-8000-000000000001',current_setting('nb.test_day')::date) r),
 (1000+6.25*190-5*extract(year from age(current_setting('nb.test_day')::date,'1995-01-01'::date))-161)::numeric,
 'resting estimate immediately uses newest weight and edited body fields');
select cmp_ok((select f.target_in from nb.compute_fuel('32320000-0000-4000-8000-000000000001',current_setting('nb.test_day')::date) f),
 '>',(select target_in from original),'fuel target refreshes using the updated inputs');
select is((select r.kcal from nb.resting_kcal('32320000-0000-4000-8000-000000000001',current_setting('nb.test_day')::date-1) r),
 (select kcal from historical),'today''s body edits do not rewrite yesterday');
insert into public.weigh_ins(user_id,measured_at,weight_kg,source,client_op_id)
values ('32320000-0000-4000-8000-000000000001',now()+interval '1 day',200,'manual',gen_random_uuid());
select is((select r.kcal from nb.resting_kcal('32320000-0000-4000-8000-000000000001',current_setting('nb.test_day')::date) r),
 (1000+6.25*190-5*extract(year from age(current_setting('nb.test_day')::date,'1995-01-01'::date))-161)::numeric,
 'future weights never reach into the current calculation');
select ok(not has_function_privilege('authenticated','nb.resting_kcal(uuid,date)','EXECUTE'),
 'the internal calculation does not become a public cross-account API');
select * from finish();
rollback;
