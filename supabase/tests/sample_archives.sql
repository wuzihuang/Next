begin;
select plan(11);
select has_table('public','sample_archives','archive manifest exists');
select ok(not has_function_privilege('authenticated','public.finalize_sample_archive(uuid,uuid,text,jsonb)','EXECUTE'),'user cannot assert verification or prune');
select ok(not has_function_privilege('anon','public.prepare_sample_archive(uuid,jsonb,text)','EXECUTE'),'anonymous cannot prepare archives');
insert into auth.users(id) values('aaaaaaaa-1111-1111-1111-111111111111');
insert into public.profiles(user_id) values('aaaaaaaa-1111-1111-1111-111111111111') on conflict(user_id) do nothing;
insert into public.raw_samples(user_id,ts,src,sampled_tz,heart) values('aaaaaaaa-1111-1111-1111-111111111111','2020-01-01','band','UTC',65);
select public.prune_retention();
select is((select count(*)::int from public.raw_samples where user_id='aaaaaaaa-1111-1111-1111-111111111111'),1,'retention preserves hot evidence without a verified object');
create temporary table archive_test_id as select public.prepare_sample_archive('aaaaaaaa-1111-1111-1111-111111111111',
'{"user_id":"aaaaaaaa-1111-1111-1111-111111111111","domain":"raw_samples","checksum":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","row_count":1,"range_start":"2020-01-01","range_end":"2020-01-01","format_version":1}',
'aaaaaaaa-1111-1111-1111-111111111111/test.gz') id;
create temporary table archive_test_rows as select jsonb_agg(to_jsonb(s)) rows from public.raw_samples s where user_id='aaaaaaaa-1111-1111-1111-111111111111';
update public.raw_samples set heart=70 where user_id='aaaaaaaa-1111-1111-1111-111111111111';
select is(public.finalize_sample_archive('aaaaaaaa-1111-1111-1111-111111111111',(select id from archive_test_id),repeat('a',64),(select rows from archive_test_rows)),0,'changed hot row survives finalization');
select is((select state from public.sample_archives where id=(select id from archive_test_id)),'verified','manifest publishes after verification');
select is(public.finalize_sample_archive('aaaaaaaa-1111-1111-1111-111111111111',(select id from archive_test_id),repeat('a',64),(select rows from archive_test_rows)),0,'finalization retry is idempotent');
create temporary table archive_test_retry as select public.prepare_sample_archive('aaaaaaaa-1111-1111-1111-111111111111',
'{"user_id":"aaaaaaaa-1111-1111-1111-111111111111","domain":"raw_samples","checksum":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_count":1,"range_start":"2020-01-01","range_end":"2020-01-01","format_version":1}',
'aaaaaaaa-1111-1111-1111-111111111111/retry.gz') id;
select is(public.finalize_sample_archive('aaaaaaaa-1111-1111-1111-111111111111',(select id from archive_test_retry),repeat('b',64),
 (select jsonb_agg(to_jsonb(s)) from public.raw_samples s where user_id='aaaaaaaa-1111-1111-1111-111111111111')),1,'unchanged verified row leaves hot tier');
select is((select count(*)::int from public.raw_samples where user_id='aaaaaaaa-1111-1111-1111-111111111111'),0,'verified payload replaces exact hot copy');
select public.prepare_sample_archive('aaaaaaaa-1111-1111-1111-111111111111',
'{"user_id":"aaaaaaaa-1111-1111-1111-111111111111","domain":"raw_samples","checksum":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","row_count":1,"range_start":"2020-01-01","range_end":"2020-01-01","format_version":1}',
'aaaaaaaa-1111-1111-1111-111111111111/pending.gz');
update public.profiles set deletion_requested_at=now() where user_id='aaaaaaaa-1111-1111-1111-111111111111';
select throws_ok($$select public.prepare_sample_archive('aaaaaaaa-1111-1111-1111-111111111111','{}','x')$$,'P0001','ACCOUNT_UNAVAILABLE','deleted account cannot start an archive');
select throws_ok($$insert into storage.objects(bucket_id,name) values('sample-history','aaaaaaaa-1111-1111-1111-111111111111/pending.gz')$$,'P0001','ACCOUNT_UNAVAILABLE','even service object insertion is blocked after tombstone');
select * from finish();
rollback;
