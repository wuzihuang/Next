-- Run only in a disposable database with migrations applied.
begin;
select plan(39);
insert into auth.users(id) values
 ('71000000-0000-4000-8000-000000000001'),
 ('71000000-0000-4000-8000-000000000002'),
 ('71000000-0000-4000-8000-000000000003');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
 ('71000000-0000-4000-8000-000000000001','test','granted','test','en'),
 ('71000000-0000-4000-8000-000000000002','test','granted','test','en');
create function pg_temp.origin_test(p jsonb, device text default 'origin-test-band', mapping text default 'veepoo-rmssd-v1')
returns jsonb language sql as $$
 select public.ingest_band_domain(device,'origin','2026-09-01','UTC',
   '2026-09-01T04:00Z','2026-09-02T04:00Z',p,'complete',mapping);
$$;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","heart":70,"step":0,"cal":0,"dis":0,"met":0}]')->>'inserted','1',
 'legacy zero aggregate remains compatible');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","origin_read_at":"2026-09-01T12:10Z","heart":120,"step":123,"cal":20,"dis":50,"met":3}]')->>'completed','1',
 'new completed observation repairs zero steps, MET, calories and old heart');
select is((select jsonb_build_array(heart,step,cal,dis,met) from public.raw_samples where ts='2026-09-01T12:00Z'),
 '[120,123,20,50,3]'::jsonb,'all origin fields reflect the accepted snapshot');
select is((select changes#>>'{step,before}' from public.band_origin_corrections),'0','correction retains prior value for audit');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","origin_read_at":"2026-09-01T12:10Z","heart":120,"step":123,"met":3}]')->>'unchanged','1',
 'identical snapshot retry is idempotent');
select is((select count(*)::integer from public.band_origin_corrections),1,'retry adds no audit duplicate');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","origin_read_at":"2026-09-01T12:09Z","heart":80,"step":10,"stress":90}]')->>'unchanged','1',
 'older queued snapshot is acknowledged as superseded');
select ok((select heart=120 and step=123 and stress is null from public.raw_samples where ts='2026-09-01T12:00Z'),
 'stale snapshot cannot overwrite or fill a newer snapshot');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","origin_read_at":"2026-09-01T12:10Z","step":124}]')->>'rejected','1',
 'conflicting equal-time snapshot is rejected');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","origin_read_at":"2026-09-01T12:20Z","heart":120,"step":123,"met":3}]')->>'unchanged','1',
 'newer identical observation advances provenance without changing measured values');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","origin_read_at":"2026-09-01T12:15Z","step":300}]')->>'unchanged','1',
 'a delayed update cannot pass a newer identical observation');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","origin_read_at":"2026-09-01T12:30Z","heart":110,"step":90,"met":2}]')->>'completed','1',
 'newer corrections may decrease an aggregate');
select ok((select heart=110 and step=90 and met=2 and cal=20 from public.raw_samples where ts='2026-09-01T12:00Z'),
 'corrected lower values persist and absent values do not erase existing facts');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","origin_read_at":"2026-09-01T12:40Z","step":400}]','other-device')->>'rejected','1',
 'another device cannot rewrite origin observations');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","origin_read_at":"2026-09-01T12:40Z","step":400}]','origin-test-band','other-mapping')->>'rejected','1',
 'another mapping cannot rewrite origin observations');
select is(public.ingest_band_domain('origin-test-band','origin','2026-09-01','America/New_York',
 '2026-09-01T04:00Z','2026-09-02T04:00Z','[{"ts":"2026-09-01T12:00Z","origin_read_at":"2026-09-01T12:40Z","step":400}]')->>'rejected','1',
 'different timezone reconstruction cannot replace known origin provenance');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","step":1000}]')->>'unchanged','1',
 'old clients cannot roll back a versioned observation');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","origin_read_at":"2026-09-01T12:04:59Z","step":400}]')->>'rejected','1',
 'a snapshot from before the slot finished is rejected even when uploaded later');
select is(public.ingest_band_domain('origin-test-band','origin',current_date,'UTC',now()-interval '1 hour',now()+interval '1 hour',
 jsonb_build_array(jsonb_build_object('ts',now()-interval '1 minute','step',0)))->>'rejected','1',
 'still-accumulating origin slot is not inserted');
select is(public.ingest_band_domain('origin-test-band','origin',current_date,'UTC',now()-interval '1 hour',now()+interval '1 hour',
 jsonb_build_array(jsonb_build_object('ts',now()+interval '1 minute','step',0)))->>'rejected','1',
 'future placeholder is not inserted');
select is(pg_temp.origin_test(jsonb_build_array(jsonb_build_object('ts','2026-09-01T12:00Z','origin_read_at',now()+interval '1 minute','step',200)))->>'rejected','1',
 'future snapshot clock is rejected');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","origin_read_at":"2026-09-01T12:40Z","user_id":"71000000-0000-4000-8000-000000000002","step":200}]')->>'rejected','1',
 'payload cannot claim another account');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T14:00Z","origin_read_at":"2026-09-01T14:30Z","step":50},{"ts":"2026-09-01T14:00Z","origin_read_at":"2026-09-01T14:20Z","step":200}]')-'affected_days'-'status',
 '{"inserted":1,"completed":0,"unchanged":1,"rejected":0}'::jsonb,
 'one outbox batch can acknowledge snapshots in reverse observation order');
select is((select step from public.raw_samples where ts='2026-09-01T14:00Z'),50,
 'per-sample read clocks preserve the latest snapshot within a batch');
select ok(not has_table_privilege('authenticated','public.band_origin_corrections','INSERT'),
 'the client cannot manufacture correction audit entries directly');
select ok(not has_table_privilege('anon','public.band_origin_corrections','SELECT'),
 'anonymous callers cannot read the correction audit');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T15:00Z","origin_read_at":"2026-09-01T15:10Z","met":1.123}]')->>'inserted','1',
 'SDK numeric precision is accepted at the storage boundary');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T15:00Z","origin_read_at":"2026-09-01T15:10Z","met":1.123}]')->>'unchanged','1',
 'identical MET replay compares at stored numeric precision');
select is(public.ingest_band_domain('origin-test-band','origin','2026-09-01','UTC',
 '2026-09-01T04:00Z','2026-09-02T04:00Z','[{"ts":"2026-09-01T16:00Z","step":0}]',
 'complete','veepoo-rmssd-v1','2026-09-01T16:10Z')->>'inserted','1',
 'the optional batch observation clock remains a compatible origin input');
select is(public.ingest_band_domain('origin-test-band','origin','2026-09-01','UTC',
 '2026-09-01T04:00Z','2026-09-02T04:00Z','[{"ts":"2026-09-01T16:00Z","step":5}]',
 'complete','veepoo-rmssd-v1','2026-09-01T16:20Z')->>'completed','1',
 'a newer compatible batch clock can complete origin values');
select is(public.ingest_band_domain('origin-test-band','rr','2026-09-01','UTC',
 '2026-09-01T04:00Z','2026-09-02T04:00Z','[{"ts":"2026-09-01T16:00Z","rr_ms":[800,900],"rr_indices":[0,1]}]',
 'complete','veepoo-rmssd-v2','2026-09-01T16:10Z')->>'inserted','1',
 'the independent indexed RR decoder remains available');
select is(public.ingest_band_domain('origin-test-band','rr','2026-09-01','UTC',
 '2026-09-01T04:00Z','2026-09-02T04:00Z','[{"ts":"2026-09-01T16:00Z","rr_ms":[800,900,850],"rr_indices":[0,1,2]}]',
 'complete','veepoo-rmssd-v2','2026-09-01T16:20Z')->>'completed','1',
 'the independent RR extension rule is preserved');
select is(public.ingest_band_domain('origin-test-band','hrv','2026-09-01','UTC',
 '2026-09-01T04:00Z','2026-09-02T04:00Z','[{"ts":"2026-09-01T16:00Z","hrv":40}]',
 'complete','veepoo-rmssd-v2','2026-09-01T16:10Z')->>'completed','1',
 'HRV still fills its own domain on an origin row');
select is(public.ingest_band_domain('origin-test-band','hrv','2026-09-01','UTC',
 '2026-09-01T04:00Z','2026-09-02T04:00Z','[{"ts":"2026-09-01T16:00Z","hrv":45}]',
 'complete','veepoo-rmssd-v2','2026-09-01T16:20Z')->>'completed','1',
 'the independent HRV revision rule is preserved');
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000002',true);
select is((select count(*)::integer from public.band_origin_corrections),0,'RLS hides another account correction audit');
select is(pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","origin_read_at":"2026-09-01T12:40Z","step":200}]')->>'inserted','1',
 'same device key and timestamp in another account do not mutate the first account');
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
select is((select step from public.raw_samples where ts='2026-09-01T12:00Z'),90,'first account is unchanged by another account upload');
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000003',true);
select throws_ok($$select pg_temp.origin_test('[{"ts":"2026-09-01T12:00Z","step":1}]')$$,
 '42501','CONSENT_REQUIRED','consent remains mandatory');
reset role;
insert into public.raw_samples(user_id,ts,src,sampled_tz,heart,step) values
 ('71000000-0000-4000-8000-000000000001','2026-09-01T13:00Z','band','UTC',70,0);
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select is(pg_temp.origin_test('[{"ts":"2026-09-01T13:00Z","origin_read_at":"2026-09-01T13:10Z","step":200}]')->>'rejected','1',
 'legacy observations without device provenance are not silently reassigned');
select * from finish();
rollback;
