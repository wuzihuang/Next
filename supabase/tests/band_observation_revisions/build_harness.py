#!/usr/bin/env python3
"""Build only the production ingestion/revision/archive seams in isolated Postgres."""
from pathlib import Path
import re
import sys
root = Path(__file__).resolve().parents[2] / 'migrations'
def function(file, name):
    sql = (root / file).read_text()
    found = re.search(r'create (?:or replace )?function ' + re.escape(name) + r'\([\s\S]+?\$\$;', sql, re.I)
    assert found, name
    return found[0] + '\n'

sql = '''
create role anon;
create role authenticated;
create role service_role;
-- Model Supabase's real public defaults, rather than granting SELECT by hand.
alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
create schema auth;
create schema nb;
create schema storage;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
create table public.profiles(user_id uuid primary key references auth.users(id) on delete cascade,
 timezone text default 'UTC',deletion_requested_at timestamptz);
create table public.consents(user_id uuid references auth.users(id),consent_version text,choice text,
 text_sha256 text,locale text,decided_at timestamptz default now());
create table public.raw_samples(user_id uuid references auth.users(id),ts timestamptz,sampled_tz text not null,
 src text default 'band',heart smallint,step integer,cal integer,dis integer,met numeric(4,2),
 temp numeric(4,2),hrv numeric(6,2),stress smallint,sleep_states smallint,primary key(user_id,ts,src));
alter table public.raw_samples enable row level security;
create policy own_read on public.raw_samples for select to authenticated using(user_id=auth.uid());
create policy own_insert on public.raw_samples for insert to authenticated with check(user_id=auth.uid());
create table public.oxygen_samples(user_id uuid,ts timestamptz,spo2 smallint,sampled_tz text,src text,primary key(user_id,ts,src));
create table public.response_samples(user_id uuid,ts timestamptz,optical double precision,sampled_tz text,src text,primary key(user_id,ts,src));
create table public.daily_results(user_id uuid);
create table public.sleep_nights(user_id uuid);
create table public.meals(user_id uuid);
create table public.weigh_ins(user_id uuid);
create table public.body_composition(user_id uuid);
create table public.screen_frames(created_at timestamptz);
create table public.analytics_events(server_ts timestamptz);
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(bucket_id text,name text);
'''
sql += function('20260901120200_compute.sql', 'nb.user_day_of')
rev = (root / '20260904085910_reproducible_calculation_revisions.sql').read_text()
sql += rev[rev.index('create table nb.calculation_work'):rev.index('create function nb.on_calculation_profile')]
sql += rev[rev.index('create table nb.calculation_maintenance'):]
sql += (root / '20260904090007_band_domain_ingestion.sql').read_text()
sql += (root / '20260904085941_verified_sample_archives.sql').read_text()
sql += (root / '20260904091122_archive_history_hydration.sql').read_text()
for migration, name in [
    ('20260903100000_raw_samples_hrv.sql', 'public.fill_hrv'),
    ('20260903110000_fill_distance.sql', 'public.fill_dis'),
    ('20260903171349_fill_temperature.sql', 'public.fill_temp'),
]:
    sql += function(migration, name)
    sql += f'grant execute on function {name}(jsonb) to authenticated;\n'
sql += (root / '20260906130703_band_observation_revisions.sql').read_text()
Path(sys.argv[1]).write_text(sql)
