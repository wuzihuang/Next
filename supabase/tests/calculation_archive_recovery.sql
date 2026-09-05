begin;
select plan(12);
select ok(not has_function_privilege('authenticated','public.resume_calculation(uuid,integer)','EXECUTE'),'clients cannot assert recovered history');
-- Simulate a retained history that has aged into the archive tier after rollout.
update nb.calculation_history_coverage set reliable_from=now()-interval '500 days';
insert into auth.users(id) values('09090909-0000-0000-0000-000000000020');
insert into public.profiles(user_id,timezone,birth_date) values('09090909-0000-0000-0000-000000000020','UTC','1990-01-01');
select set_config('nb.recovery_day',(nb.user_day_of(now(),'UTC')-410)::text,true);
insert into public.raw_samples(user_id,ts,sampled_tz,heart,met)
values('09090909-0000-0000-0000-000000000020',current_setting('nb.recovery_day')::date+interval '8 hours','UTC',80,1);
create temporary table recovery_fixture as
select jsonb_agg(to_jsonb(s)) as rows from public.raw_samples s where user_id='09090909-0000-0000-0000-000000000020';
select set_config('nb.before_revision',(select input_revision::text from nb.calculation_work where user_id='09090909-0000-0000-0000-000000000020'),true);
select set_config('request.jwt.claim.sub','09090909-0000-0000-0000-000000000020',true);
set local role authenticated;
select is(public.settle_now(0),0,'normal settle leaves expired dependency pending');
reset role;
select set_config('nb.archive_id',public.prepare_sample_archive('09090909-0000-0000-0000-000000000020',
jsonb_build_object('user_id','09090909-0000-0000-0000-000000000020','domain','raw_samples',
'checksum',repeat('a',64),'row_count',1,'range_start',(select rows->0->>'ts' from recovery_fixture),
'range_end',(select rows->0->>'ts' from recovery_fixture),'format_version',1),
'09090909-0000-0000-0000-000000000020/recovery-test.gz')::text,true);
select is(public.finalize_sample_archive('09090909-0000-0000-0000-000000000020',current_setting('nb.archive_id')::uuid,repeat('a',64),(select rows from recovery_fixture)),1,'verified archival removes hot copy');
select is((select input_revision from nb.calculation_work where user_id='09090909-0000-0000-0000-000000000020'),current_setting('nb.before_revision')::bigint,'archive movement does not change input revision');
select ok((public.resume_calculation('09090909-0000-0000-0000-000000000020',2)->>'needs_archive')::boolean,'unhydrated archive requests recovery without replay');
select lives_ok($$select public.hydrate_sample_archive('09090909-0000-0000-0000-000000000020',current_setting('nb.archive_id')::uuid,repeat('a',64),(select rows from recovery_fixture))$$,'verified archive can restore original rows');
select is((select input_revision from nb.calculation_work where user_id='09090909-0000-0000-0000-000000000020'),current_setting('nb.before_revision')::bigint,'hydration does not invent a new fact revision');
create temporary table first_recovery as select public.resume_calculation('09090909-0000-0000-0000-000000000020',2) as result;
select is((select (result->>'rows_touched')::int from first_recovery),2,'recovery respects two-day batch budget');
select is((select (result->>'next_day')::date from first_recovery),current_setting('nb.recovery_day')::date+2,'recovery advances in chronological order');
select is((select count(*)::int from public.daily_results where user_id='09090909-0000-0000-0000-000000000020'),2,'first recovery publishes only bounded days');
do $$ declare r jsonb; i int:=0; begin
 loop
 r:=public.resume_calculation('09090909-0000-0000-0000-000000000020',14);
 exit when not (r->>'pending')::boolean;
 i:=i+1;if i>40 then raise exception 'RECOVERY_STALLED';end if;
 end loop;
end $$;
select ok((select dirty_from is null from nb.calculation_work where user_id='09090909-0000-0000-0000-000000000020'),'bounded retries finish the previously blocked chain');
set local role authenticated;
select ok((select bool_and(not pending and result_revision is not null) from public.calculation_status(current_date-2,current_date-1)),'normal UI reader receives ready recovered versions');
reset role;
select * from finish();
rollback;
