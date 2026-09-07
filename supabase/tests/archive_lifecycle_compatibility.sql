begin;
select plan(6);
-- ⚠️ Tests 1 and 2 below call public.account_delete, which reads storage.objects. They can
-- only see a collision between one of its columns and a plpgsql variable if the table this
-- runs against actually has that column. A `storage.objects(bucket_id, name)` stub passes
-- them while the deployed function raises 42702 on every call, which is exactly how the
-- `owner_id` ambiguity survived from 20260906140000 to 20260907030000. Assert the shape
-- first, so a thin storage schema fails loudly here instead of hiding a live break.
select has_column('storage', 'objects', 'owner_id',
  'the runner has a real storage.objects, not a two-column stub');
select has_column('storage', 'objects', 'metadata',
  'the runner has a real storage.objects, not a two-column stub');
insert into auth.users(id) values('dddddddd-1111-1111-1111-111111111111');
insert into public.profiles(user_id) values('dddddddd-1111-1111-1111-111111111111') on conflict do nothing;
select public.prepare_sample_archive('dddddddd-1111-1111-1111-111111111111',
'{"user_id":"dddddddd-1111-1111-1111-111111111111","domain":"raw_samples","checksum":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","row_count":1,"range_start":"2020-01-01","range_end":"2020-01-01","format_version":1}',
'dddddddd-1111-1111-1111-111111111111/pending.gz');
select set_config('request.jwt.claim.sub','dddddddd-1111-1111-1111-111111111111',true);
select is(public.account_delete('DELETE')->>'error','USE_ACCOUNT_DELETE_ENDPOINT','legacy RPC cannot orphan pending or verified archives');
select is((select count(*)::int from auth.users where id='dddddddd-1111-1111-1111-111111111111'),1,'blocked legacy deletion preserves account for endpoint cleanup');
select ok(not has_function_privilege('authenticated','nb.account_delete_legacy_oxygen(text)','EXECUTE'),'legacy underlying routine cannot bypass archive guard');
insert into public.oxygen_samples(user_id,ts,spo2,sampled_tz) values('dddddddd-1111-1111-1111-111111111111','2020-01-01',97,'UTC');
select public.prune_retention();
select is((select count(*)::int from public.oxygen_samples where user_id='dddddddd-1111-1111-1111-111111111111'),0,'independent oxygen 400-day retention remains intact');
select * from finish();
rollback;
