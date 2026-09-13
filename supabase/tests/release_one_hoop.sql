-- Disposable migrated database only; all fixtures roll back.
begin;
insert into auth.users(id) values ('99999999-9999-4999-9999-999999999902'), ('99999999-9999-4999-9999-999999999903');
insert into public.profiles(user_id,timezone) values ('99999999-9999-4999-9999-999999999902','UTC') on conflict do nothing;
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
 ('99999999-9999-4999-9999-999999999902','test','granted','test','en');
select set_config('request.jwt.claim.sub','99999999-9999-4999-9999-999999999902',true);
select plan(1);
set local role authenticated;
create function pg_temp.assert_release(ok boolean,message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'RELEASE ONE: %',message; end if; end $$;
do $$
declare a uuid; b uuid; replacement uuid; t jsonb; r jsonb; event_count integer;
begin
 insert into public.devices(user_id,ble_identifier,ble_identifier_kind,bound_at)
 values(auth.uid(),'release-A','uuid',now()-interval '2 days') returning id into a;
 insert into public.devices(user_id,ble_identifier,ble_identifier_kind,bound_at)
 values(auth.uid(),'release-B','uuid',now()-interval '2 days') returning id into b;
 perform public.record_wear_event(b,now()-interval '1 day','release-test-wear-B');
 -- Removing the wearer leaves A bound and marks the transition at release time.
 t := public.release_device(b);
 perform pg_temp.assert_release(jsonb_array_length(t->'devices')=1 and t->'devices'->0->>'id'=a::text,'only B is released');
 perform pg_temp.assert_release(t->'wearing'->>'device_key'='release-A','A becomes wearer');
 perform pg_temp.assert_release(t->'events'->0->>'source'='release','handoff has release provenance');
 perform pg_temp.assert_release((t->'events'->0->>'effective_at')::timestamptz=now(),'handoff is not backdated');
 perform pg_temp.assert_release(exists(select 1 from public.devices where id=b and unbound_at=now()),'old binding is retained');
 event_count:=jsonb_array_length(t->'events');
 t:=public.release_device(b);
 perform pg_temp.assert_release(jsonb_array_length(t->'events')=event_count,'retry does not add events');
 -- Historical B was worn; A upload must remain standby even without a currently bound B.
 r:=public.ingest_band_domain('release-A','origin',(now()-interval '12 hours')::date,'UTC',
  date_trunc('day',now()-interval '12 hours'),date_trunc('day',now()-interval '12 hours')+interval '1 day',
  jsonb_build_array(jsonb_build_object('ts',now()-interval '12 hours','user_id',auth.uid(),'sampled_tz','UTC','src','band','heart',75,'step',10)));
 perform pg_temp.assert_release(r->>'standby'='1','released B still owns its historical segment');
 perform pg_temp.assert_release(exists(select 1 from public.band_standby_samples where user_id=auth.uid() and device_key='release-A'),'history stays stored');
 insert into public.devices(user_id,ble_identifier,ble_identifier_kind)
 values(auth.uid(),'release-B-replacement','uuid') returning id into replacement;
 perform pg_temp.assert_release((public.wear_timeline()->'wearing'->>'device_key')='release-A','new B does not steal current wearing');
 -- Removing standby leaves the wearer selected.
 t:=public.release_device(replacement);
 perform pg_temp.assert_release(t->'wearing'->>'device_key'='release-A','standby removal keeps A worn');
 -- Foreign / unknown IDs must not mutate or expose another account.
 perform set_config('request.jwt.claim.sub','99999999-9999-4999-9999-999999999903',true);
 begin
  perform public.release_device(a);
  raise exception 'foreign release succeeded';
 exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claim.sub','',true);
 begin
  perform public.release_device(a);
  raise exception 'anonymous release succeeded';
 exception when invalid_authorization_specification then null; end;
 perform set_config('request.jwt.claim.sub','99999999-9999-4999-9999-999999999902',true);
 t:=public.release_device(a);
 perform pg_temp.assert_release(jsonb_array_length(t->'devices')=0 and t->'wearing'->>'device_key' is null,'last device can be released');
 -- The opposite slot survives: rebinding A must preserve B as wearer.
 insert into public.devices(user_id,ble_identifier,ble_identifier_kind)
 values(auth.uid(),'release-A-new','uuid') returning id into a;
 insert into public.devices(user_id,ble_identifier,ble_identifier_kind)
 values(auth.uid(),'release-B-new','uuid') returning id into b;
 t:=public.release_device(a);
 perform pg_temp.assert_release(t->'wearing'->>'device_key'='release-B-new','B survives A removal');
 insert into public.devices(user_id,ble_identifier,ble_identifier_kind)
 values(auth.uid(),'release-A-next','uuid');
 perform pg_temp.assert_release((public.wear_timeline()->'wearing'->>'device_key')='release-B-new','replacement A does not steal B wearing');
 perform pg_temp.assert_release(not has_function_privilege('anon','public.release_device(uuid)','execute'),'anonymous role has no execute privilege');
end $$;
select pass('single-device release: wearer, standby, history, retry, ownership, final removal and replacement');
select * from finish();
rollback;
