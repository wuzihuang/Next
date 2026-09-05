-- Behavioral integration test; execute only in a disposable migrated database.
begin;
insert into auth.users(id) values('11111111-1111-4111-8111-111111111119'),('22222222-2222-4222-8222-222222222229');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale)
values('11111111-1111-4111-8111-111111111119','test','granted','test','en'),
('22222222-2222-4222-8222-222222222229','test','granted','test','en');
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111119',true);
set local role authenticated;
do $$
declare a jsonb; s jsonb;
begin
  a:=public.ingest_band_domain('test-band','origin','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z',
    '[{"ts":"2026-09-01T12:00Z","heart":70}]');
  if a->>'inserted'<>'1' or a->'affected_days'<>'["2026-09-01"]'::jsonb then raise exception 'first measurement not accepted: %',a; end if;
  a:=public.ingest_band_domain('test-band','origin','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z',
    '[{"ts":"2026-09-01T12:00Z","heart":70}]');
  if a->>'unchanged'<>'1' or a->'affected_days'<>'[]'::jsonb then raise exception 'retry changed facts: %',a; end if;
  a:=public.ingest_band_domain('test-band','hrv','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z',
    '[{"ts":"2026-09-01T12:00Z","hrv":40},{"ts":"2026-09-01T11:00Z","hrv":50}]');
  if a->>'inserted'<>'1' or a->>'completed'<>'1' then raise exception 'late auxiliary samples not repaired: %',a; end if;
  a:=public.ingest_band_domain('test-band','temperature','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z',
    '[{"ts":"2026-09-01T12:00Z","temp":34},{"ts":"2026-09-01T12:05Z","temp":999}]');
  if a->>'completed'<>'1' or a->>'rejected'<>'1' or a->>'status'<>'partial' then raise exception 'rejected input advanced range: %',a; end if;
  a:=public.ingest_band_domain('test-band','rr','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z',
    '[{"ts":"2026-09-01T12:00Z","rr_ms":[800,840,810]}]');
  if a->>'inserted'<>'1' then raise exception 'RR missing: %',a; end if;
  a:=public.ingest_band_domain('test-band','rr','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z',
    '[{"ts":"2026-09-01T12:00Z","rr_ms":[800,840,810]}]');
  if a->>'unchanged'<>'1' then raise exception 'RR duplicated: %',a; end if;
  a:=public.ingest_band_domain('test-band','rr','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z',
    '[{"ts":"2026-09-01T12:00Z","rr_ms":[810,840,800]}]');
  if a->>'rejected'<>'1' then raise exception 'conflicting retry silently accepted: %',a; end if;
  a:=public.ingest_band_domain('test-band','sleep','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z','[]','failed');
  if a->>'status'<>'failed' then raise exception 'sleep failure reported complete'; end if;
  a:=public.ingest_band_domain('test-band','oxygen','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z',
    '[{"ts":"2026-09-01T12:00Z","spo2":97}]');
  if a->>'inserted'<>'1' then raise exception 'oxygen not accepted: %',a; end if;
  a:=public.ingest_band_domain('test-band','oxygen','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z',
    '[{"ts":"2026-09-01T12:00Z","spo2":97}]');
  if a->>'unchanged'<>'1' then raise exception 'oxygen retry changed facts: %',a; end if;
  a:=public.ingest_band_domain('test-band','oxygen','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z',
    '[{"ts":"2026-09-01T12:00Z","spo2":96}]');
  if a->>'rejected'<>'1' then raise exception 'conflicting oxygen silently accepted: %',a; end if;
  a:=public.ingest_band_domain('test-band','oxygen','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z',
    '[{"ts":"2026-09-01T12:05Z","spo2":0},{"ts":"2026-09-01T12:10Z","spo2":101}]');
  if a->>'rejected'<>'2' then raise exception 'out-of-range oxygen accepted: %',a; end if;
end $$;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222229',true);
do $$ begin
 if exists(select 1 from public.band_rr_evidence) or exists(select 1 from public.sync_domain_status)
 then raise exception 'cross-account data leak'; end if;
end $$;
reset role;
insert into public.profiles(user_id,deletion_requested_at)
values('11111111-1111-4111-8111-111111111119',now())
on conflict(user_id) do update set deletion_requested_at=excluded.deletion_requested_at;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111119',true);
set local role authenticated;
do $$ begin
 begin
  perform public.ingest_band_domain('test-band','origin','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z',
    '[{"ts":"2026-09-01T12:00Z","heart":70}]');
  raise exception 'tombstoned account accepted new ingestion';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
rollback;
