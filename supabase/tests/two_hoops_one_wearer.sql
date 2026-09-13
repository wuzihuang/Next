-- Two HOOPs, one wearer: the declaration is the only source-selection rule.
-- Run in a disposable migrated database; every synthetic fixture rolls back.
begin;
insert into auth.users(id) values ('99999999-9999-4999-9999-999999999901');
insert into public.profiles(user_id,timezone) values ('99999999-9999-4999-9999-999999999901','UTC') on conflict do nothing;
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
 ('99999999-9999-4999-9999-999999999901','test','granted','test','en');
select set_config('request.jwt.claim.sub','99999999-9999-4999-9999-999999999901',true);
select plan(1);
set local role authenticated;

create function pg_temp.assert_wear(ok boolean,message text) returns void language plpgsql as $$
 begin if ok is distinct from true then raise exception 'TWO HOOPS: %',message; end if; end $$;
create function pg_temp.origin(device text,s jsonb,r timestamptz default '2026-09-02T12:00Z')
returns jsonb language sql as $$
 select public.ingest_band_domain(device,'origin','2026-09-01','UTC','2026-09-01T00:00Z','2026-09-02T00:00Z',
  coalesce((select jsonb_agg(jsonb_build_object('user_id',auth.uid(),'sampled_tz','UTC','src','band') || value)
   from jsonb_array_elements(s)),'[]'::jsonb),'complete','veepoo-rmssd-v2',r);
$$;

do $$
declare a jsonb; a_id uuid; b_id uuid; steps integer; owner text; held integer; t jsonb;
begin
 -- Slot A is the first bound band; a second bound band takes slot B; a third has no slot.
 insert into public.devices(user_id,ble_identifier,ble_identifier_kind,bound_at)
  values (auth.uid(),'band-A','uuid','2026-08-20T00:00Z') returning id into a_id;
 insert into public.devices(user_id,ble_identifier,ble_identifier_kind,bound_at)
  values (auth.uid(),'band-B','uuid','2026-09-01T06:00Z') returning id into b_id;
 perform pg_temp.assert_wear((select slot from public.devices where id=a_id)='A','first bound band takes slot A');
 perform pg_temp.assert_wear((select slot from public.devices where id=b_id)='B','second bound band takes slot B');
 begin
  insert into public.devices(user_id,ble_identifier,ble_identifier_kind) values (auth.uid(),'band-C','uuid');
  perform pg_temp.assert_wear(false,'a third bound band must be refused');
 exception when unique_violation then null; end;

 -- No declaration yet: A is worn since it was bound, so A's ticks are canonical and B's are held.
 perform pg_temp.assert_wear((public.wear_timeline()->'wearing'->>'device_key')='band-A','slot A is the wearer before any declaration');
 a:=pg_temp.origin('band-A','[{"ts":"2026-09-01T08:00Z","heart":70,"step":100},{"ts":"2026-09-01T09:00Z","heart":72,"step":110}]');
 perform pg_temp.assert_wear(a->>'inserted'='2' and a->>'rejected'='0','wearer samples are accepted as before');
 a:=pg_temp.origin('band-B','[{"ts":"2026-09-01T08:00Z","heart":80,"step":900},{"ts":"2026-09-01T09:00Z","heart":82,"step":910}]');
 perform pg_temp.assert_wear(a->>'inserted'='2' and a->>'rejected'='0' and a->>'standby'='2','standby samples are acknowledged, not rejected');
 select step into steps from public.raw_samples where user_id=auth.uid() and ts='2026-09-01T08:00Z';
 perform pg_temp.assert_wear(steps=100,'the held band never overwrites the wearer');
 select count(*) into held from public.band_standby_samples where user_id=auth.uid() and device_key='band-B';
 perform pg_temp.assert_wear(held=2,'held samples are kept per device');
 a:=pg_temp.origin('band-B','[{"ts":"2026-09-01T08:00Z","heart":80,"step":900}]');
 perform pg_temp.assert_wear(a->>'unchanged'='1' and a->>'inserted'='0','a repeated held sample is unchanged, so the phone''s receipt holds');

 -- Declare B worn from 08:30. The 09:00 tick moves to B; the 08:00 tick stays with A.
 t:=public.record_wear_event(b_id,'2026-09-01T08:30Z','op-1');
 perform pg_temp.assert_wear((t->>'moved')::integer=1,'one tick changed hands: '||coalesce(t->>'moved','null'));
 perform pg_temp.assert_wear(t->'wearing'->>'device_key'='band-B','the timeline now says B is worn');
 select step, coalesce(domain_sources->'origin'->>'device_key',ingestion_device_key) into steps, owner
  from public.raw_samples where user_id=auth.uid() and ts='2026-09-01T09:00Z';
 perform pg_temp.assert_wear(steps=910 and owner='band-B','09:00 is B''s after the declaration');
 select step, coalesce(domain_sources->'origin'->>'device_key',ingestion_device_key) into steps, owner
  from public.raw_samples where user_id=auth.uid() and ts='2026-09-01T08:00Z';
 perform pg_temp.assert_wear(steps=100 and owner='band-A','08:00 stays A''s');
 perform pg_temp.assert_wear(exists(select 1 from public.band_standby_samples where user_id=auth.uid() and device_key='band-A' and ts='2026-09-01T09:00Z' and (values->>'step')::integer=110),'A''s displaced 09:00 tick is held, not lost');
 perform pg_temp.assert_wear(not exists(select 1 from public.band_standby_samples where user_id=auth.uid() and device_key='band-B' and ts='2026-09-01T09:00Z'),'the promoted sample leaves the standby table');

 -- Idempotent: the same operation id returns the same timeline without a second event.
 t:=public.record_wear_event(b_id,'2026-09-01T08:30Z','op-1');
 perform pg_temp.assert_wear(jsonb_array_length(t->'events')=1,'a retried declaration does not duplicate');

 -- New samples after the switch: B's are canonical, A's are held.
 a:=pg_temp.origin('band-A','[{"ts":"2026-09-01T10:00Z","heart":71,"step":120}]');
 a:=pg_temp.origin('band-B','[{"ts":"2026-09-01T10:00Z","heart":81,"step":920}]');
 select step into steps from public.raw_samples where user_id=auth.uid() and ts='2026-09-01T10:00Z';
 perform pg_temp.assert_wear(steps=920,'after the switch B wins live ticks');

 -- Back-dating the same switch to 07:30 moves 08:00 to B as well.
 t:=public.record_wear_event(b_id,'2026-09-01T07:30Z','op-2');
 select step into steps from public.raw_samples where user_id=auth.uid() and ts='2026-09-01T08:00Z';
 perform pg_temp.assert_wear(steps=900,'back-dating promotes the held 08:00 sample');

 -- A declaration cannot predate the band''s binding.
 t:=public.record_wear_event(b_id,'2026-08-01T00:00Z','op-3');
 perform pg_temp.assert_wear((t->'events'->0->>'effective_at')::timestamptz>='2026-09-01T06:00Z','effective_at is clamped to bound_at');

 -- Sleep: the night belongs to the band worn at wake time. B has been worn since 06:00
 -- (op-3 clamped to its binding), so a 05:40 wake is still A's.
 t:=public.publish_sleep_night(jsonb_build_object('user_day','2026-09-01','total_minutes',400,'deep_minutes',90,'light_minutes',300,
   'wake_count',1,'device_key','band-A','sleep_start','2026-08-31T23:00Z','wake_at','2026-09-01T05:40Z'));
 perform pg_temp.assert_wear(t->0->>'total_minutes'='400' and t->0->>'held' is null,'A''s night is filed while A is worn at wake');
 t:=public.publish_sleep_night(jsonb_build_object('user_day','2026-09-01','total_minutes',380,'deep_minutes',80,'light_minutes',300,
   'wake_count',2,'device_key','band-B','sleep_start','2026-08-31T23:00Z','wake_at','2026-09-01T05:40Z'));
 perform pg_temp.assert_wear(t->0->>'held'='true' and t->0->>'total_minutes'='380','B''s night for the same day is held with a confirmable shape');
 perform pg_temp.assert_wear((select total_minutes from public.sleep_nights where user_id=auth.uid() and user_day='2026-09-01')=400,'the filed night is untouched');

 -- The phone's own key for a band (a CoreBluetooth UUID) is what the wearer rule matches.
 t:=public.claim_device_key(a_id,'phone-A');
 perform pg_temp.assert_wear((public.wear_timeline()->'wearing'->>'device_key')='band-B','claiming A''s key does not change who is worn');
 a:=pg_temp.origin('phone-A','[{"ts":"2026-09-01T05:00Z","heart":66,"step":10}]');
 perform pg_temp.assert_wear(a->>'inserted'='1' and a->>'standby'='0','A''s ticks under the phone key are canonical while A is worn');
 t:=public.record_wear_event(a_id,'2026-09-01T11:00Z','op-4');
 perform pg_temp.assert_wear((public.wear_timeline()->'wearing'->>'device_key')='phone-A','the timeline answers with the claimed key');
 a:=pg_temp.origin('phone-A','[{"ts":"2026-09-01T11:30Z","heart":67,"step":12}]');
 perform pg_temp.assert_wear(a->>'inserted'='1' and a->>'standby'='0','after declaring A under its phone key the ticks are canonical');
 a:=pg_temp.origin('band-B','[{"ts":"2026-09-01T11:30Z","heart":90,"step":900}]');
 perform pg_temp.assert_wear(a->>'standby'='1','B is held once A is declared again');

 -- A switch with no time is the app's own declaration: filed at now, then moved back to
 -- where the newly worn band's own run of wrist evidence begins.
 perform set_config('role','postgres',true);
 insert into public.band_standby_samples(user_id,device_key,domain,ts,sampled_tz,values)
  select auth.uid(),'band-B','origin',g,'UTC',jsonb_build_object('heart',72,'step',30)
   from generate_series(date_trunc('minute', now()) - interval '3 hours',
                        date_trunc('minute', now()) - interval '5 minutes', interval '5 minutes') g
  on conflict do nothing;
 perform set_config('role','authenticated',true);
 t:=public.record_wear_event(b_id,null,'op-5');
 perform pg_temp.assert_wear(t->'events'->0->>'source'='auto','a switch with no time is the app''s own declaration');
 perform pg_temp.assert_wear((t->>'counted_from')::timestamptz > now() - interval '2 minutes','it files at now until the band has been read');
 t:=public.settle_wear_start('op-5');
 perform pg_temp.assert_wear((t->>'counted_from')::timestamptz < now() - interval '2 hours 50 minutes','the start moves back to where B''s run begins: '||coalesce(t->>'counted_from','null'));
 perform pg_temp.assert_wear((public.wear_timeline()->'wearing'->>'device_key')='band-B','B is still the one worn after the settle');
 perform pg_temp.assert_wear((select heart from public.raw_samples where user_id=auth.uid() and ts=date_trunc('minute',now()) - interval '2 hours')=72,'B''s stretch is canonical once the start moved');

 -- Settling twice changes nothing, and a time the wearer pinned is never moved.
 t:=public.settle_wear_start('op-5');
 perform pg_temp.assert_wear((t->>'moved')::integer=0,'a second settle has nothing left to move');
 t:=public.record_wear_event(a_id, date_trunc('minute',now()) - interval '30 minutes','op-6');
 perform pg_temp.assert_wear(t->'events'->0->>'source'='manual','a time the wearer pins is manual');
 t:=public.settle_wear_start('op-6');
 perform pg_temp.assert_wear((t->>'counted_from')::timestamptz=date_trunc('minute',now()) - interval '30 minutes','a pinned time stands');

 -- Releasing the set closes both bindings; single-band ingest paths still work afterwards.
 t:=public.release_device_set();
 perform pg_temp.assert_wear((t->>'released')::integer=2,'release closes both bindings');
 perform pg_temp.assert_wear((public.wear_timeline()->'wearing'->>'device_key') is null,'nobody is worn after release');
end $$;
reset role;
select pass('two HOOPs, one wearer: every boundary in the block above held');
select * from finish();
rollback;
