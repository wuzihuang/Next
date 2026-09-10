-- Run in a disposable migrated database; every synthetic fixture rolls back.
begin;
insert into auth.users(id) values
 ('88888888-8888-4888-8888-888888888801'),('88888888-8888-4888-8888-888888888802'),
 ('88888888-8888-4888-8888-888888888803');
insert into public.profiles(user_id,timezone) values
 ('88888888-8888-4888-8888-888888888801','UTC'),('88888888-8888-4888-8888-888888888802','UTC'),
 ('88888888-8888-4888-8888-888888888803','UTC') on conflict do nothing;
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
 ('88888888-8888-4888-8888-888888888801','test','granted','test','en'),
 ('88888888-8888-4888-8888-888888888802','test','granted','test','en');
create function pg_temp.assert_delta(ok boolean,message text) returns void language plpgsql as $$
 begin if ok is distinct from true then raise exception 'BAND DELTA: %',message; end if; end $$;
create function pg_temp.delta(d text,s jsonb,r timestamptz default '2026-09-02T12:00Z',
 refs jsonb default '[]',device text default 'band-A',mapper text default 'veepoo-rmssd-v2',tz text default 'UTC')
returns jsonb language sql as $$
 select public.ingest_band_delta(device,d,'2026-09-01',tz,'2026-09-01T00:00Z','2026-09-02T00:00Z',
  case when d='origin' and jsonb_typeof(s)='array' then
   coalesce((select jsonb_agg(jsonb_build_object('user_id',auth.uid(),'sampled_tz',tz,'src','band') || value)
    from jsonb_array_elements(s)),'[]'::jsonb) else s end,'complete',mapper,r,refs);
$$;
select set_config('request.jwt.claim.sub','88888888-8888-4888-8888-888888888801',true);
set local role authenticated;
do $$
declare a jsonb; initial_receipt text; ref jsonb; source_clock timestamptz; sample jsonb;
begin
 sample:='[{"ts":"2026-09-01T01:00Z","heart":70,"step":10,"met":1.123}]';
 a:=pg_temp.delta('origin',sample);
 initial_receipt:=a->'receipts'->>'2026-09-01T01:00Z';
 perform pg_temp.assert_delta(a->>'inserted'='1' and length(initial_receipt)=64,'accepted full content receives a receipt keyed by submitted ts');
 perform pg_temp.assert_delta(a->'affected_days'='["2026-09-01"]'::jsonb,'wrapper preserves production midnight mapping');
 ref:=jsonb_build_array(jsonb_build_object('ts','2026-09-01T01:00Z','receipt',initial_receipt));
 a:=pg_temp.delta('origin','[]','2026-09-02T12:20Z',ref);
 perform pg_temp.assert_delta(a->>'unchanged'='1' and a->'needs_samples'='[]'::jsonb,'unchanged compact content is acknowledged');
 perform pg_temp.assert_delta(a->'receipts'='{}'::jsonb,'successful references do not echo tokens or add response bytes');
 select (domain_sources->'origin'->>'read_at')::timestamptz into source_clock
  from public.raw_samples where user_id=auth.uid() and ts='2026-09-01T01:00Z' and src='band';
 perform pg_temp.assert_delta(source_clock='2026-09-02T12:20Z','compact reads advance source clocks');
 a:=pg_temp.delta('origin','[{"ts":"2026-09-01T01:00Z","heart":60,"step":10,"met":1.123}]','2026-09-02T12:10Z');
 perform pg_temp.assert_delta(a->>'unchanged'='1' and a->'receipts'='{}'::jsonb,'stale different full sample never gets a receipt');
 perform pg_temp.assert_delta((select heart=70 from public.raw_samples where user_id=auth.uid() and ts='2026-09-01T01:00Z'),'delayed full samples cannot undo a compact reobservation');
 a:=pg_temp.delta('origin',sample,'2026-09-02T12:10Z');
 perform pg_temp.assert_delta(a->'receipts'->>'2026-09-01T01:00Z'=initial_receipt,'same-content stale input may safely receive current receipt');
 a:=pg_temp.delta('origin',jsonb_set(sample,'{0,ts}','"2026-09-01T01:00:00+00:00"'),'2026-09-02T12:10Z');
 perform pg_temp.assert_delta(a->'receipts'->>'2026-09-01T01:00:00+00:00'=initial_receipt,'new full-sample receipt keys preserve exact incoming timestamp text');
 -- Return keys retain the caller's representation while receipt scope normalizes time.
 ref:=jsonb_build_array(jsonb_build_object('ts','2026-09-01T01:00:00+00:00','receipt',initial_receipt,
  'origin_read_at','2026-09-02T12:40Z'));
 a:=pg_temp.delta('origin','[]','2026-09-02T12:30Z',ref);
 perform pg_temp.assert_delta(a->>'unchanged'='1' and a->'needs_samples'='[]'::jsonb,'equivalent timestamp spelling validates the same receipt');
 perform pg_temp.assert_delta((select (domain_sources->'origin'->>'read_at')::timestamptz='2026-09-02T12:40Z'
  from public.raw_samples where user_id=auth.uid() and ts='2026-09-01T01:00Z'),'per-origin read clock survives compact reconstruction');
 -- Whole-domain comparison must not receipt a sparse update that omits stored fields.
 a:=pg_temp.delta('origin','[{"ts":"2026-09-01T01:00Z","heart":70}]','2026-09-02T12:50Z');
 perform pg_temp.assert_delta(a->'receipts'='{}'::jsonb,'omitted existing origin fields are not silently added to client receipt');
 a:=pg_temp.delta('origin','[{"ts":"2026-09-01T01:00Z","heart":null,"step":10,"met":1.123}]','2026-09-02T12:55Z');
 perform pg_temp.assert_delta(a->'receipts'='{}'::jsonb and (select heart=70 from public.raw_samples
  where user_id=auth.uid() and ts='2026-09-01T01:00Z'),'explicit null preserves existing ingestor semantics and cannot receipt a different stored snapshot');
 -- Failed reference preflight is atomic even when valid new samples precede it.
 perform public.ingest_band_domain('band-A','origin','2026-09-01','UTC',
  '2026-09-01T00:00Z','2026-09-02T00:00Z','[]','failed','veepoo-rmssd-v2','2026-09-02T13:00Z');
 a:=pg_temp.delta('origin','[{"ts":"2026-09-01T01:05Z","heart":72}]','2026-09-02T13:10Z',
  jsonb_build_array(jsonb_build_object('ts','2026-09-01T01:00Z','receipt',repeat('0',64))));
 perform pg_temp.assert_delta(a->>'inserted'='0' and a->>'completed'='0' and a->>'unchanged'='0'
  and a->>'rejected'='0' and a->'receipts'='{}'::jsonb
  and a->'needs_samples'='["2026-09-01T01:00Z"]'::jsonb,'receipt miss requests full samples with zero acknowledged writes');
 perform pg_temp.assert_delta(not exists(select 1 from public.raw_samples where user_id=auth.uid() and ts='2026-09-01T01:05Z'),'receipt miss rolls no partial batch forward');
 perform pg_temp.assert_delta((select status='failed' from public.sync_domain_status where user_id=auth.uid()
  and device_key='band-A' and domain='origin' and user_day='2026-09-01'),'receipt miss cannot promote sync status');
 -- Changed server content invalidates the old token; same-scope full fallback repairs it.
 a:=pg_temp.delta('origin','[{"ts":"2026-09-01T01:00Z","heart":80,"step":10,"met":1.123}]','2026-09-02T13:20Z');
 a:=pg_temp.delta('origin','[]','2026-09-02T13:30Z',ref);
 perform pg_temp.assert_delta(jsonb_array_length(a->'needs_samples')=1,'server correction invalidates old content receipt');
 a:=pg_temp.delta('origin',sample,'2026-09-02T13:30Z');
 perform pg_temp.assert_delta(a->>'completed'='1' and a->'receipts'->>'2026-09-01T01:00Z'=initial_receipt,'full fallback preserves normal correction semantics');
 ref:=jsonb_build_array(jsonb_build_object('ts','2026-09-01T01:00Z','receipt',initial_receipt));
 a:=pg_temp.delta('origin','[]','2026-09-02T13:40Z',ref,'band-B');
 perform pg_temp.assert_delta(jsonb_array_length(a->'needs_samples')=1,'receipt cannot cross device scope');
 a:=pg_temp.delta('origin','[]','2026-09-02T13:40Z',ref,'band-A','veepoo-rmssd-v1');
 perform pg_temp.assert_delta(jsonb_array_length(a->'needs_samples')=1,'receipt cannot cross mapper scope');
 a:=pg_temp.delta('origin','[]','2026-09-02T13:40Z',ref,'band-A','veepoo-rmssd-v2','Etc/UTC');
 perform pg_temp.assert_delta(jsonb_array_length(a->'needs_samples')=1,'receipt cannot cross timezone basis');
 a:=pg_temp.delta('hrv','[]','2026-09-02T13:40Z',ref);
 perform pg_temp.assert_delta(jsonb_array_length(a->'needs_samples')=1,'receipt cannot cross domain scope');
 perform set_config('request.jwt.claim.sub','88888888-8888-4888-8888-888888888802',true);
 a:=pg_temp.delta('origin','[]','2026-09-02T13:40Z',ref);
 perform pg_temp.assert_delta(jsonb_array_length(a->'needs_samples')=1,'receipt cannot cross account scope');
 perform set_config('request.jwt.claim.sub','88888888-8888-4888-8888-888888888801',true);
end $$;

do $$ declare a jsonb; token text; ref jsonb; sample jsonb; invalid_hrv jsonb;
 values_rr real[]; indices integer[]; begin
 a:=pg_temp.delta('hrv','[{"ts":"2026-09-01T02:00Z","hrv":42.123}]');
 perform pg_temp.assert_delta(a->'receipts'='{}'::jsonb,'scalar HRV does not receive an expensive receipt');
 a:=pg_temp.delta('hrv','[{"ts":"2026-09-01T02:00Z","hrv":42.123}]','2026-09-02T12:20Z');
 perform pg_temp.assert_delta(a->>'unchanged'='1','full scalar HRV retains stored precision idempotency');
 invalid_hrv:='[{"ts":"2026-09-01T02:00Z","hrv":null,"hrv_valid":false,"hrv_invalid_reason":"insufficient_adjacent_rr"}]';
 a:=pg_temp.delta('hrv',invalid_hrv,'2026-09-02T12:30Z');
 perform pg_temp.assert_delta(a->>'completed'='1','explicit HRV invalidity retains normal ingestion');
 a:=pg_temp.delta('hrv',invalid_hrv,'2026-09-02T12:50Z');
 a:=pg_temp.delta('hrv','[{"ts":"2026-09-01T02:00Z","hrv":43}]','2026-09-02T12:40Z');
 perform pg_temp.assert_delta(a->'receipts'='{}'::jsonb and (select hrv is null
  from public.raw_samples where user_id=auth.uid() and ts='2026-09-01T02:00Z'),'reobserved invalid HRV prevents delayed resurrection');
 a:=pg_temp.delta('temperature','[{"ts":"2026-09-01T02:00Z","temp":34.123}]');
 perform pg_temp.assert_delta(a->'receipts'='{}'::jsonb,'scalar temperature does not receive an expensive receipt');
 a:=pg_temp.delta('temperature','[{"ts":"2026-09-01T02:00Z","temp":34.123}]','2026-09-02T12:20Z');
 perform pg_temp.assert_delta(a->>'unchanged'='1','scalar temperature keeps independent source clocks');
 values_rr:=array[800::real,900.123::real] || array_fill(800::real,array[18]);
 indices:=array(select n*2 from generate_series(0,19) n);
 sample:=jsonb_build_array(jsonb_build_object('ts','2026-09-01T02:00Z','rr_ms',values_rr,'rr_indices',indices));
 a:=pg_temp.delta('rr',sample);
 token:=a->'receipts'->>'2026-09-01T02:00Z';
 perform pg_temp.assert_delta(length(token)=64,'long RR arrays receive useful compact receipts');
 ref:=jsonb_build_array(jsonb_build_object('ts','2026-09-01T02:00Z','receipt',token));
 a:=pg_temp.delta('rr','[]','2026-09-02T12:20Z',ref);
 perform pg_temp.assert_delta(a->>'unchanged'='1' and a->'receipts'='{}'::jsonb,'RR compact payload preserves real precision and avoids token echo');
 perform pg_temp.assert_delta((select rr_indices=indices from public.band_rr_evidence where user_id=auth.uid()
  and device_key='band-A' and ts='2026-09-01T02:00Z' and mapping_version='veepoo-rmssd-v2'),'RR gaps are not silently joined');
 a:=pg_temp.delta('rr',jsonb_build_array(jsonb_build_object('ts','2026-09-01T02:00Z',
  'rr_ms',values_rr[1:1] || array[850::real] || values_rr[2:20],
  'rr_indices',array[0,1] || indices[2:20])),'2026-09-02T12:30Z');
 a:=pg_temp.delta('rr','[]','2026-09-02T12:40Z',ref);
 perform pg_temp.assert_delta(jsonb_array_length(a->'needs_samples')=1,'RR extension invalidates shorter receipt');
 a:=pg_temp.delta('rr',sample,'2026-09-02T12:50Z');
 perform pg_temp.assert_delta(a->>'unchanged'='1' and a->'receipts'='{}'::jsonb,'accepted RR subset does not get a receipt for larger server array');
 a:=pg_temp.delta('rr',jsonb_build_array(jsonb_build_object('ts','2026-09-01T02:05Z','rr_ms',array_fill(800::real,array[40]))));
 token:=a->'receipts'->>'2026-09-01T02:05Z';
 perform pg_temp.assert_delta(length(token)=64,'long legacy RR arrays receive compact receipt');
 a:=pg_temp.delta('rr','[]','2026-09-02T12:20Z',jsonb_build_array(jsonb_build_object('ts','2026-09-01T02:05Z','receipt',token)));
 perform pg_temp.assert_delta(a->>'unchanged'='1' and a->'needs_samples'='[]'::jsonb,'legacy nullable RR indices round trip without fabricated indices');
 -- Domains without provenance still accept full samples, but never compact them.
 a:=pg_temp.delta('oxygen','[{"ts":"2026-09-01T02:00Z","spo2":98}]');
 perform pg_temp.assert_delta(a->>'inserted'='1' and a->'receipts'='{}'::jsonb,'oxygen full upload remains compatible');
 a:=pg_temp.delta('response','[{"ts":"2026-09-01T02:00Z","optical":1234.5}]');
 perform pg_temp.assert_delta(a->>'inserted'='1' and a->'receipts'='{}'::jsonb,'response full upload remains compatible');
 a:=pg_temp.delta('oxygen','[]','2026-09-02T12:20Z',ref);
 perform pg_temp.assert_delta(jsonb_array_length(a->'needs_samples')=1,'unproven oxygen reference requires full fallback');
 a:=pg_temp.delta('sleep','[]');
 perform pg_temp.assert_delta(a->>'status'='complete' and a->'receipts'='{}'::jsonb,'empty sleep domain status retains original behavior');
end $$;

-- Input bounds, duplicates and invalid reference clocks fail before status writes.
do $$ declare sample jsonb; refs jsonb; call_sql text; begin
 foreach call_sql in array array[
  'select pg_temp.delta(''origin'',''[]'',refs => ''[{"ts":"bad","receipt":"bad"}]'')',
  'select pg_temp.delta(''origin'',''[]'',refs => ''[{"ts":"2026-09-01T01:00Z","receipt":"bad"}]'')',
  'select pg_temp.delta(''origin'',''[]'',refs => ''null'')',
  'select pg_temp.delta(''origin'',''{}'')',
  'select pg_temp.delta(''origin'',''[{"ts":"2026-09-01T01:00Z","heart":70},{"ts":"2026-09-01T01:00:00+00:00","heart":70}]'')',
  'select pg_temp.delta(''origin'',''[]'',now()+interval ''1 day'')'
 ] loop
  begin execute call_sql; raise exception 'invalid delta input accepted: %',call_sql;
  exception when invalid_parameter_value then null; end;
 end loop;
 refs:=jsonb_build_array(jsonb_build_object('ts','2026-09-01T01:00Z','receipt',repeat('a',64)));
 begin
  perform pg_temp.delta('origin','[{"ts":"2026-09-01T01:00Z","heart":70}]',refs=>refs);
  raise exception 'full/reference collision accepted';
 exception when invalid_parameter_value then null; end;
 begin
  perform pg_temp.delta('origin','[]',refs=>refs||refs);
  raise exception 'duplicate reference accepted';
 exception when invalid_parameter_value then null; end;
 begin
  perform pg_temp.delta('origin','[]',refs=>jsonb_build_array(jsonb_build_object(
   'ts','2026-09-01T01:00Z','receipt',repeat('a',64),'origin_read_at','infinity')));
  raise exception 'nonfinite reference observation accepted';
 exception when invalid_parameter_value then null; end;
 select jsonb_agg(jsonb_build_object('ts','2026-09-01T01:00Z','heart',70)) into sample from generate_series(1,5001);
 begin perform pg_temp.delta('origin',sample); raise exception 'oversized count accepted';
 exception when invalid_parameter_value then null; end;
 begin perform pg_temp.delta('origin',jsonb_build_array(jsonb_build_object('ts','2026-09-01T01:00Z','extra',repeat('x',4000000))));
  raise exception 'oversized bytes accepted';
 exception when invalid_parameter_value then null; end;
 -- Per-sample invalid inputs retain original partial acks; no receipts are minted.
 sample:=pg_temp.delta('temperature','[{"ts":"2026-09-01T03:05Z","temp":"bad"},{"ts":"2026-09-01T03:00Z","temp":34}]');
 perform pg_temp.assert_delta(sample->>'rejected'='1' and sample->>'inserted'='1' and sample->'receipts'='{}'::jsonb,
  'partially rejected full batch retains normal ingestion without unsafe receipts');
end $$;

reset role;
do $$ begin
 perform pg_temp.assert_delta(not has_function_privilege('anon',
  'public.ingest_band_delta(text,text,date,text,timestamptz,timestamptz,jsonb,text,text,timestamptz,jsonb)','EXECUTE'),'anonymous RPC execution denied');
 perform pg_temp.assert_delta(not has_function_privilege('authenticated',
  'nb.band_delta_stored_sample(uuid,text,text,text,text,timestamptz)','EXECUTE'),'cross-account canonical helper is private');
 perform pg_temp.assert_delta(not has_function_privilege('authenticated',
  'nb.band_delta_receipt(uuid,text,text,text,text,timestamptz,jsonb)','EXECUTE'),'receipt helper is private');
 perform set_config('request.jwt.claim.sub','88888888-8888-4888-8888-888888888803',true);
 begin perform pg_temp.delta('origin','[]'); raise exception 'missing consent accepted';
 exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claim.sub','',true);
 begin perform pg_temp.delta('origin','[]'); raise exception 'missing auth accepted';
 exception when invalid_authorization_specification then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','88888888-8888-4888-8888-888888888801',true);
do $$ declare a jsonb; token text; begin
 a:=pg_temp.delta('origin','[{"ts":"2026-09-01T04:00Z","heart":70,"step":10,"cal":3,"dis":5,"met":1}]');
 token:=a->'receipts'->>'2026-09-01T04:00Z';
 perform pg_temp.assert_delta(length(token)=64,'archive fixture receives confirmed content receipt');
 -- Model an archived/released hot row without relying on a second receipt table.
 delete from public.raw_samples where user_id=auth.uid() and ts='2026-09-01T04:00Z' and src='band';
 a:=pg_temp.delta('origin','[{"ts":"2026-09-01T04:05Z","heart":71}]','2026-09-02T12:20Z',
  jsonb_build_array(jsonb_build_object('ts','2026-09-01T04:00Z','receipt',token)));
 perform pg_temp.assert_delta(a->'needs_samples'='["2026-09-01T04:00Z"]'::jsonb and a->>'inserted'='0',
  'receipt whose hot row disappeared requests an atomic full fallback');
 perform pg_temp.assert_delta(not exists(select 1 from public.raw_samples where user_id=auth.uid()
  and ts in ('2026-09-01T04:00Z','2026-09-01T04:05Z')),'missing references never synthesize or partially ingest observations');
end $$;
update public.profiles set deletion_requested_at=now() where user_id=auth.uid();
set local role authenticated;
do $$ begin
 begin perform pg_temp.delta('origin','[]'); raise exception 'deleting account accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
