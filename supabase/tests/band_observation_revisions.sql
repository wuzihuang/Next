-- Runs in a disposable migrated database; rolls back every synthetic observation.
begin;
insert into auth.users(id) values('66666666-6666-4666-8666-666666666601'),('66666666-6666-4666-8666-666666666602');
insert into public.profiles(user_id,timezone) values
 ('66666666-6666-4666-8666-666666666601','UTC'),('66666666-6666-4666-8666-666666666602','UTC') on conflict do nothing;
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
 ('66666666-6666-4666-8666-666666666601','test','granted','test','en');
create function pg_temp.band_ingest(d text,s jsonb,r timestamptz default null,v text default null,device text default 'band-A')
returns jsonb language sql as $$
 select public.ingest_band_domain(device,d,'2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z',s,'complete',coalesce(v,case when d='origin' then 'veepoo-rmssd-v1' else 'veepoo-rmssd-v2' end),r);
$$;
create function pg_temp.assert_band(ok boolean,message text) returns void language plpgsql as $$
 begin if ok is distinct from true then raise exception 'BAND REVISION: %',message; end if; end $$;
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666601',true);
set local role authenticated;
do $$ declare a jsonb; row_data public.raw_samples; begin
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","heart":70,"step":0,"met":0}]','2026-09-02T12:00Z','veepoo-rmssd-v1');
 perform pg_temp.assert_band(a->>'inserted'='1','first source read accepted');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","heart":80,"step":120,"met":3.2}]','2026-09-02T12:10Z');
 perform pg_temp.assert_band(a->>'completed'='1' and a->'affected_days'='["2026-09-01"]'::jsonb,'new device read corrects previously nonnull zero and invalidates its day');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","heart":70,"step":0,"met":0}]','2026-09-02T12:05Z','veepoo-rmssd-v1');
 perform pg_temp.assert_band(a->>'unchanged'='1' and a->'affected_days'='[]'::jsonb,'older outbox retry cannot revert');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","heart":70,"step":0,"met":0}]','2026-09-02T12:20Z','unknown-mapper');
 perform pg_temp.assert_band(a->>'rejected'='1','newer origin snapshot cannot silently switch mapper');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","step":130}]','2026-09-02T12:10Z');
 perform pg_temp.assert_band(a->>'rejected'='1','same observation clock with contradictory facts is rejected');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","heart":90}]','2026-09-02T12:30Z');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","step":150}]','2026-09-02T12:20Z');
 select * into row_data from public.raw_samples where ts='2026-09-01T12:00Z';
 perform pg_temp.assert_band(row_data.heart=90 and row_data.step=120 and row_data.met=3.2,'full origin snapshots reject older reads across every field');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","heart":90}]','2026-09-02T12:50Z');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","heart":85}]','2026-09-02T12:40Z');
 perform pg_temp.assert_band(a->>'unchanged'='1','newer equal reading still advances watermark');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","heart":60,"cal":50}]','2026-09-02T13:00Z','veepoo-rmssd-v2','band-B');
 perform pg_temp.assert_band(a->>'rejected'='1','another device cannot overwrite or fill owned sample');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","heart":60,"cal":50}]');
 perform pg_temp.assert_band(a->>'unchanged'='1','unversioned origin snapshots cannot fill a newer snapshot');
 a:=pg_temp.band_ingest('temperature','[{"ts":"2026-09-01T12:00Z","temp":34}]');
 perform pg_temp.assert_band(a->>'completed'='1','independent legacy streams can fill an absent field');
 select * into row_data from public.raw_samples where ts='2026-09-01T12:00Z';
 perform pg_temp.assert_band(row_data.heart=90 and row_data.cal is null and row_data.temp=34,'independent fill preserves complete origin snapshot');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:05Z","met":1.123}]','2026-09-02T12:00Z');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:05Z","met":1.123}]','2026-09-02T12:00Z');
 perform pg_temp.assert_band(a->>'unchanged'='1','stored decimal precision remains idempotent');
 a:=pg_temp.band_ingest('hrv','[{"ts":"2026-09-01T12:00Z","hrv":200}]','2026-09-02T12:00Z','veepoo-rmssd-v1');
 a:=pg_temp.band_ingest('hrv','[{"ts":"2026-09-01T12:00Z","hrv":null,"hrv_valid":false,"hrv_invalid_reason":"insufficient_adjacent_rr"}]','2026-09-02T12:10Z');
 perform pg_temp.assert_band(a->>'completed'='1','explicit reread retracts invalid v1 RMSSD');
 select * into row_data from public.raw_samples where ts='2026-09-01T12:00Z';
 perform pg_temp.assert_band(row_data.hrv is null and row_data.domain_sources->'hrv'->>'hrv_valid'='false','invalid HRV provenance is exposed without fabricated value');
 a:=pg_temp.band_ingest('hrv','[{"ts":"2026-09-01T12:00Z","hrv":200}]','2026-09-02T12:00Z','veepoo-rmssd-v1');
 perform pg_temp.assert_band(a->>'unchanged'='1','stale retry cannot resurrect retracted HRV');
 a:=pg_temp.band_ingest('hrv','[{"ts":"2026-09-01T12:00Z","hrv":null}]','2026-09-02T12:20Z');
 perform pg_temp.assert_band(a->>'rejected'='1','ordinary missing HRV is not a retraction');
 a:=pg_temp.band_ingest('hrv','[{"ts":"2026-09-01T12:00Z","hrv":45}]','2026-09-02T12:30Z');
 perform pg_temp.assert_band(a->>'completed'='1','newer v2 evidence can restore valid HRV');
 a:=pg_temp.band_ingest('rr','[{"ts":"2026-09-01T12:00Z","rr_ms":[800,900],"rr_indices":[0,2]}]','2026-09-02T12:00Z');
 perform pg_temp.assert_band(a->>'inserted'='1','RR gaps retained');
 a:=pg_temp.band_ingest('rr','[{"ts":"2026-09-01T12:00Z","rr_ms":[800,850,900,920],"rr_indices":[0,1,2,3]}]','2026-09-02T12:10Z');
 perform pg_temp.assert_band(a->>'completed'='1','compatible superset appends RR evidence');
 a:=pg_temp.band_ingest('rr','[{"ts":"2026-09-01T12:00Z","rr_ms":[800,900],"rr_indices":[0,2]}]','2026-09-02T12:00Z');
 perform pg_temp.assert_band(a->>'unchanged'='1','subset retry remains idempotent');
 a:=pg_temp.band_ingest('rr','[{"ts":"2026-09-01T12:00Z","rr_ms":[810,850,900,920,930],"rr_indices":[0,1,2,3,4]}]','2026-09-02T12:20Z');
 perform pg_temp.assert_band(a->>'rejected'='1','conflicting RR never silently replaces original facts');
 a:=pg_temp.band_ingest('rr','[{"ts":"2026-09-01T12:05Z","rr_ms":[800,900],"rr_indices":[0,0]},{"ts":"2026-09-01T12:10Z","rr_ms":[800,null]},{"ts":"2026-09-01T12:15Z","rr_ms":[800,900],"rr_indices":[0]}]','2026-09-02T12:20Z');
 perform pg_temp.assert_band(a->>'rejected'='3','malformed RR arrays/indices are rejected per sample');
 a:=pg_temp.band_ingest('rr','[{"ts":"2026-09-01T12:05Z","rr_ms":[800,900]}]','2026-09-02T12:20Z','veepoo-rmssd-v1');
 perform pg_temp.assert_band(a->>'inserted'='1','legacy contiguous RR accepted');
 a:=pg_temp.band_ingest('rr','[{"ts":"2026-09-01T12:10Z","rr_ms":[800,900]}]',null,'veepoo-rmssd-v1');
 a:=pg_temp.band_ingest('rr','[{"ts":"2026-09-01T12:10Z","rr_ms":[800,900,950]}]','2026-09-02T12:20Z','veepoo-rmssd-v1');
 perform pg_temp.assert_band(a->>'completed'='1','first explicit device clock can extend legacy RR without using upload receipt order');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-03T12:00Z","heart":70}]','2026-09-02T12:00Z');
 perform pg_temp.assert_band(a->>'rejected'='1','sample outside batch or after device read rejected');
 begin
   perform pg_temp.band_ingest('origin','[]',now()+interval '1 day');
   raise exception 'future read clock accepted';
 exception when invalid_parameter_value then null; end;

end $$;
-- Exercise actual ACL denial, including INSERT (previously allowed by own-row
-- RLS) and TRUNCATE (which bypasses RLS), rather than mistaking an UPDATE that
-- silently affects zero rows for evidence of a successful row mutation.
do $$ declare table_name text; privilege_name text; statement text; begin
 foreach table_name in array array['raw_samples','band_rr_evidence'] loop
  foreach privilege_name in array array['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
   perform pg_temp.assert_band(not has_table_privilege('authenticated','public.'||table_name,privilege_name),
     table_name||' client '||privilege_name||' grant revoked');
  end loop;
  perform pg_temp.assert_band(has_table_privilege('authenticated','public.'||table_name,'SELECT'),table_name||' authenticated reads preserved');
  perform pg_temp.assert_band(not has_table_privilege('anon','public.'||table_name,'SELECT'),table_name||' anonymous reads denied');
 end loop;
 foreach statement in array array[
  'insert into public.raw_samples(user_id,ts,sampled_tz,heart) values(auth.uid(),''2026-09-01T14:00Z'',''UTC'',70)',
  'update public.raw_samples set heart=1 where user_id=auth.uid()',
  'delete from public.raw_samples where user_id=auth.uid()',
  'truncate public.raw_samples',
  'insert into public.band_rr_evidence(user_id,device_key,ts,mapping_version,rr_ms,sampled_tz) values(auth.uid(),''forged'',''2026-09-01T14:00Z'',''v1'',array[800]::real[],''UTC'')',
  'update public.band_rr_evidence set rr_ms=array[1000]::real[] where user_id=auth.uid()',
  'delete from public.band_rr_evidence where user_id=auth.uid()',
  'truncate public.band_rr_evidence',
  'select public.fill_hrv(''[]''::jsonb)',
  'select public.fill_dis(''[]''::jsonb)',
  'select public.fill_temp(''[]''::jsonb)'
 ] loop
  begin
   execute statement;
   raise exception 'unguarded client write executed: %',statement;
  exception when insufficient_privilege then null; end;
 end loop;
 perform pg_temp.assert_band(has_function_privilege('service_role','public.finalize_sample_archive(uuid,uuid,text,jsonb)','EXECUTE'),
   'service archive finalization remains available');
 perform pg_temp.assert_band(has_function_privilege('service_role','public.hydrate_sample_archive(uuid,uuid,text,jsonb)','EXECUTE'),
   'service archive hydration remains available');
end $$;
reset role;
do $$ declare before_revision bigint; a jsonb; begin
 perform pg_temp.assert_band((select dirty_from='2026-09-01'::date from nb.calculation_work where user_id=auth.uid()),'updated fact uses production dirty revision trigger');
 select input_revision into before_revision from nb.calculation_work where user_id=auth.uid();
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","heart":90}]','2026-09-02T12:50Z');
 perform pg_temp.assert_band(a->>'unchanged'='1','exact retry after auxiliary updates is unchanged');
 perform pg_temp.assert_band((select input_revision=before_revision from nb.calculation_work where user_id=auth.uid()),'exact retry does not advance calculation revision');
end $$;
-- Unknown legacy facts retain unknown provenance when another field fills a gap.
insert into public.raw_samples(user_id,ts,sampled_tz,heart) values(auth.uid(),'2026-09-01T13:00Z','UTC',70);
do $$ declare a jsonb; begin
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T13:00Z","step":10}]','2026-09-02T12:00Z');
 a:=pg_temp.band_ingest('origin','[{"ts":"2026-09-01T13:00Z","heart":90}]','2026-09-02T13:00Z');
 perform pg_temp.assert_band((select heart=70 from public.raw_samples where user_id=auth.uid() and ts='2026-09-01T13:00Z'),'null-fill cannot claim and overwrite unknown legacy source');
end $$;
-- An immutable format-1 archive omits the new nullable columns. It can still
-- finalize, hydrate and release exactly; a later hot extension survives all three.
insert into public.band_rr_evidence(user_id,device_key,ts,mapping_version,rr_ms,sampled_tz)
 values(auth.uid(),'band-A','2020-01-01T12:00Z','legacy',array[800,900]::real[],'UTC');
create temporary table band_archive_payload as select jsonb_agg(to_jsonb(r)-array['rr_indices','observed_at']) rows
 from public.band_rr_evidence r where user_id=auth.uid() and ts='2020-01-01T12:00Z';
create temporary table band_archive_id as select public.prepare_sample_archive(auth.uid(),
 jsonb_build_object('user_id',auth.uid(),'domain','band_rr_evidence','checksum',repeat('a',64),'row_count',1,
 'range_start','2020-01-01T12:00Z','range_end','2020-01-01T12:00Z','format_version',1),auth.uid()::text||'/old-rr.gz') id;
do $$ declare n integer; begin
 n:=public.finalize_sample_archive(auth.uid(),(select id from band_archive_id),repeat('a',64),(select rows from band_archive_payload));
 perform pg_temp.assert_band(n=1,'old archive can finalize after nullable columns added');
 n:=public.hydrate_sample_archive(auth.uid(),(select id from band_archive_id),repeat('a',64),(select rows from band_archive_payload));
 perform pg_temp.assert_band(n=1,'old archive hydrates without synthetic indices');
 update public.band_rr_evidence set rr_ms=array[800,900,950]::real[],rr_indices=array[0,1,2],observed_at=now()
  where user_id=auth.uid() and ts='2020-01-01T12:00Z';
 update nb.calculation_work set dirty_from=null where user_id=auth.uid();
 n:=public.release_sample_hydration(auth.uid(),(select id from band_archive_id),repeat('a',64),(select rows from band_archive_payload));
 perform pg_temp.assert_band(n=0,'archive release preserves extended hot RR');
 perform pg_temp.assert_band((select cardinality(rr_ms)=3 from public.band_rr_evidence where user_id=auth.uid() and ts='2020-01-01T12:00Z'),'old hydration never shrinks newer evidence');
 perform pg_temp.assert_band(not has_function_privilege('anon','public.ingest_band_domain(text,text,date,text,timestamptz,timestamptz,jsonb,text,text,timestamptz)','EXECUTE'),'anonymous cannot ingest');
end $$;
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666602',true);
set local role authenticated;
do $$ begin
 perform pg_temp.assert_band(not exists(select 1 from public.raw_samples) and not exists(select 1 from public.band_rr_evidence),'cross-account rows remain private');
 begin
  perform pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","heart":70}]','2026-09-02T12:00Z');
  raise exception 'missing consent accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666601',true);
update public.profiles set deletion_requested_at=now() where user_id=auth.uid();
set local role authenticated;
do $$ begin
 begin
  perform pg_temp.band_ingest('origin','[{"ts":"2026-09-01T12:00Z","heart":70}]','2026-09-02T12:00Z');
  raise exception 'tombstoned account accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
