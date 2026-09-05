begin;
select plan(6);
insert into auth.users(id) values('bbbbbbbb-1111-1111-1111-111111111111');
insert into public.profiles(user_id) values('bbbbbbbb-1111-1111-1111-111111111111') on conflict do nothing;
insert into public.raw_samples(user_id,ts,src,sampled_tz,heart) values('bbbbbbbb-1111-1111-1111-111111111111','2020-01-01','band','UTC',65);
create temp table hydration_rows as select jsonb_agg(to_jsonb(s)) rows from public.raw_samples s where user_id='bbbbbbbb-1111-1111-1111-111111111111';
create temp table hydration_id as select public.prepare_sample_archive('bbbbbbbb-1111-1111-1111-111111111111',
'{"user_id":"bbbbbbbb-1111-1111-1111-111111111111","domain":"raw_samples","checksum":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","row_count":1,"range_start":"2020-01-01","range_end":"2020-01-01","format_version":1}',
'bbbbbbbb-1111-1111-1111-111111111111/history.gz') id;
select public.finalize_sample_archive('bbbbbbbb-1111-1111-1111-111111111111',(select id from hydration_id),repeat('a',64),(select rows from hydration_rows));
create temp table hydration_revision as select input_revision from nb.calculation_work where user_id='bbbbbbbb-1111-1111-1111-111111111111';
select is(public.hydrate_sample_archive('bbbbbbbb-1111-1111-1111-111111111111',(select id from hydration_id),repeat('a',64),(select rows from hydration_rows)),1,'verified historical input returns to hot tier');
select is(public.hydrate_sample_archive('bbbbbbbb-1111-1111-1111-111111111111',(select id from hydration_id),repeat('a',64),(select rows from hydration_rows)),0,'hydration retry is idempotent');
select is((select input_revision from nb.calculation_work where user_id='bbbbbbbb-1111-1111-1111-111111111111'),(select input_revision from hydration_revision),'tier move does not invalidate logical calculation');
select throws_ok($$select public.release_sample_hydration('bbbbbbbb-1111-1111-1111-111111111111',(select id from hydration_id),repeat('a',64),(select rows from hydration_rows))$$,'P0001','RECOVERY_IN_PROGRESS','dirty calculation preserves hydrated inputs');
update public.raw_samples set heart=72 where user_id='bbbbbbbb-1111-1111-1111-111111111111';
select public.hydrate_sample_archive('bbbbbbbb-1111-1111-1111-111111111111',(select id from hydration_id),repeat('a',64),(select rows from hydration_rows));
select is((select heart::int from public.raw_samples where user_id='bbbbbbbb-1111-1111-1111-111111111111'),72,'hydration never overwrites a hot correction');
update nb.calculation_work set dirty_from=null where user_id='bbbbbbbb-1111-1111-1111-111111111111';
select is(public.release_sample_hydration('bbbbbbbb-1111-1111-1111-111111111111',(select id from hydration_id),repeat('a',64),(select rows from hydration_rows)),0,'cleanup preserves corrected hot rows without creating another archive');
select * from finish();
rollback;
