begin;
select plan(27);

-- The same pure decision serves the RPC and the replay loop. The publication
-- clock advances by a minute; only the still-open day gets five-minute reuse.
create temporary table validity_cases(
 label text,changes jsonb,dirty date,profile_revision bigint,day_end timestamptz,
 as_of timestamptz,expected boolean);
insert into validity_cases values
 ('fresh open result','{}',null,7,'2026-09-09 00:00Z','2026-09-08 12:00Z',true),
 ('four minutes can be reused','{"calculation_as_of":"2026-09-08 11:56Z"}',null,7,'2026-09-09 00:00Z','2026-09-08 12:00Z',true),
 ('five minutes must refresh','{"calculation_as_of":"2026-09-08 11:55Z"}',null,7,'2026-09-09 00:00Z','2026-09-08 12:00Z',false),
 ('a closed day must reach midnight','{"calculation_as_of":"2026-09-08 23:59Z"}',null,7,'2026-09-09 00:00Z','2026-09-09 00:00Z',false),
 ('a complete closed day stays current','{"calculation_as_of":"2026-09-09 00:00Z"}',null,7,'2026-09-09 00:00Z','2026-09-10 12:00Z',true),
 ('missing clock is pending','{"calculation_as_of":null}',null,7,'2026-09-09 00:00Z','2026-09-08 12:00Z',false),
 ('missing publication is pending','{"result_revision":null}',null,7,'2026-09-09 00:00Z','2026-09-08 12:00Z',false),
 ('missing profile is pending','{}',null,null,'2026-09-09 00:00Z','2026-09-08 12:00Z',false),
 ('changed profile is pending','{}',null,8,'2026-09-09 00:00Z','2026-09-08 12:00Z',false),
 ('dirty frontier includes this day','{}','2026-09-08',7,'2026-09-09 00:00Z','2026-09-08 12:00Z',false),
 ('later dirty facts preserve this day','{}','2026-09-09',7,'2026-09-09 00:00Z','2026-09-08 12:00Z',true),
 ('old calculation version is pending','{"algo_version":"tl-2.2/bb-2.1/fuel-1.0/call-1.2/energy-1.1/calc-1"}',null,7,'2026-09-09 00:00Z','2026-09-08 12:00Z',false),
 ('all version components must match','{"algo_version":"tl-2.2/bb-2.2/fuel-0.9/call-1.2/energy-1.1/calc-1"}',null,7,'2026-09-09 00:00Z','2026-09-08 12:00Z',false),
 ('future clock cannot certify current output','{"calculation_as_of":"2026-09-08 12:01Z"}',null,7,'2026-09-09 00:00Z','2026-09-08 12:00Z',false);
select is(nb.calculation_result_is_current(jsonb_populate_record(null::public.daily_results,
 jsonb_build_object('user_day','2026-09-08','result_revision','08080808-0000-0000-0000-000000000001',
  'algo_version',nb.calculation_version(),'profile_revision',7,'calculation_as_of','2026-09-08 12:00Z')||c.changes),
 c.dirty,c.profile_revision,c.day_end,c.as_of),c.expected,c.label) from validity_cases c;

insert into auth.users(id) values('08080808-0000-0000-0000-000000000001');
insert into public.profiles(user_id,timezone,birth_date)
 values('08080808-0000-0000-0000-000000000001','UTC','1990-01-01');
select set_config('nb.validity_user','08080808-0000-0000-0000-000000000001',true);
select set_config('nb.validity_day',nb.user_day_of(now(),'UTC')::text,true);
select set_config('request.jwt.claim.sub',current_setting('nb.validity_user'),true);
set local role authenticated;
select is(public.settle_now(1),2,'real publication settles yesterday and today');
reset role;
select ok((select bool_and(r.algo_version=nb.calculation_version()) from public.daily_results r
 where r.user_id=current_setting('nb.validity_user')::uuid),'atomic writer publishes the shared version');

update public.daily_results set profile_revision=-1
 where user_id=current_setting('nb.validity_user')::uuid and user_day=current_setting('nb.validity_day')::date;
set local role authenticated;
select ok((select pending from public.calculation_status(current_setting('nb.validity_day')::date,
 current_setting('nb.validity_day')::date)),'RPC reports a mismatched profile pending');
select is(public.settle_now(0),1,'replay repairs exactly the mismatched profile');
reset role;

update public.daily_results set calculation_as_of=null
 where user_id=current_setting('nb.validity_user')::uuid and user_day=current_setting('nb.validity_day')::date;
set local role authenticated;
select ok((select pending from public.calculation_status(current_setting('nb.validity_day')::date,
 current_setting('nb.validity_day')::date)),'RPC fails closed on a missing clock');
select is(public.settle_now(0),1,'replay repairs the missing clock');
reset role;

update public.daily_results set calculation_as_of=calculation_as_of-interval '1 minute'
 where user_id=current_setting('nb.validity_user')::uuid and user_day=current_setting('nb.validity_day')::date-1;
set local role authenticated;
select ok((select pending from public.calculation_status(current_setting('nb.validity_day')::date-1,
 current_setting('nb.validity_day')::date-1)),'yesterday missing its final minute is pending');
select is(public.settle_now(1),1,'replay completes the previous day even inside the old freshness margin');
select is(public.settle_now(1),0,'ready output is reusable after repair');
reset role;

-- Changing one version owner changes both pending and the next publication.
create or replace function nb.calculation_version() returns text
language sql stable set search_path='' as $$
 select 'tl-2.2/bb-2.2/fuel-1.0/call-1.2/energy-1.1/calc-test'::text;
$$;
set local role authenticated;
select ok((select bool_and(pending) from public.calculation_status(current_setting('nb.validity_day')::date-1,
 current_setting('nb.validity_day')::date)),'one version change invalidates both days');
select is(public.settle_now(1),2,'both outdated versions replay');
reset role;
select ok((select bool_and(r.algo_version=nb.calculation_version()) from public.daily_results r
 where r.user_id=current_setting('nb.validity_user')::uuid),'publication uses the changed version without another writer patch');
select ok(not has_function_privilege('authenticated',
 'nb.calculation_result_is_current(public.daily_results,date,bigint,timestamptz,timestamptz)','execute')
 and not has_function_privilege('anon','nb.calculation_version()','execute'),
 'validity helpers remain private');

select * from finish();
rollback;
