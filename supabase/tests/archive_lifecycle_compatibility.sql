begin;
select plan(4);
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
