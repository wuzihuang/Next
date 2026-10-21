#!/usr/bin/env python3
"""Exercise upload and per-account settlement locks in an isolated Postgres container."""
import json
from pathlib import Path
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
IMAGE = "public.ecr.aws/supabase/postgres:17.6.1.166"
CONTAINER = f"nb-band-bundle-{uuid.uuid4().hex[:10]}"
PLATFORM = """
create extension if not exists pg_cron with schema extensions;
create extension if not exists pgtap with schema extensions;
alter role postgres superuser;
alter table auth.users add column if not exists is_anonymous boolean not null default false;
create or replace function auth.jwt() returns jsonb language sql stable as $jwt$
 select coalesce(nullif(current_setting('request.jwt.claim',true),''),
                 nullif(current_setting('request.jwt.claims',true),''))::jsonb
$jwt$;
create table storage.buckets(id text primary key,name text,owner uuid,
 created_at timestamptz default now(),updated_at timestamptz default now(),
 public boolean default false,avif_autodetection boolean default false,
 file_size_limit bigint,max_file_size_kb int,allowed_mime_types text[],owner_id text);
create table storage.objects(id uuid primary key default gen_random_uuid(),
 bucket_id text references storage.buckets(id),name text,owner uuid,
 created_at timestamptz default now(),updated_at timestamptz default now(),
 last_accessed_at timestamptz default now(),metadata jsonb,
 path_tokens text[] generated always as(string_to_array(name,'/')) stored,
 version text,owner_id text,user_metadata jsonb,level int);
alter table storage.objects enable row level security;
grant all on storage.buckets,storage.objects to postgres,service_role;
grant select,insert,update,delete on storage.objects to authenticated;
alter table storage.buckets owner to postgres;
alter table storage.objects owner to postgres;
"""
PSQL = ["docker", "exec", "-i", CONTAINER, "psql", "-X", "-q", "-A", "-t",
        "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"]


def run(*args, sql=None, check=True):
    result = subprocess.run(args, input=sql, text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(f"{' '.join(args)}\n{result.stdout}{result.stderr}")
    return result


def query(sql):
    return run(*PSQL, sql=sql).stdout.strip()


def authenticated(owner, statement):
    return f"""begin;
set local role authenticated;
set local request.jwt.claim.sub='{owner}';
set local statement_timeout='8s';
{statement}
commit;
"""


def hold_work_lock(owner, seconds):
    process = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, bufsize=1)
    process.stdin.write(f"""begin;
select user_id from nb.calculation_work where user_id='{owner}' for update;
\\echo LOCKED
select pg_sleep({seconds});
commit;
""")
    process.stdin.close()
    for line in process.stdout:
        if line.strip() == "LOCKED":
            return process
    raise RuntimeError(f"Could not acquire calculation_work lock: {process.stderr.read()}")


def bundle_sql(owner, domain_array):
    return authenticated(owner, f"select public.ingest_band_bundle('{domain_array}'::jsonb,null,4000);")


def main():
    created = False
    owners = [str(uuid.uuid4()), str(uuid.uuid4())]
    try:
        run("docker", "run", "-d", "--pull=never", "--network", "none", "--name", CONTAINER,
            "-e", "POSTGRES_PASSWORD=isolated-schema-only", "-e", "POSTGRES_DB=postgres",
            IMAGE, "-c", "shared_preload_libraries=pg_cron", "-c", "cron.database_name=postgres",
            "-c", "cron.launch_active_jobs=off")
        created = True
        for _ in range(60):
            if run("docker", "exec", CONTAINER, "pg_isready", "-h", "127.0.0.1", "-U",
                   "postgres", "-d", "postgres", check=False).returncode == 0:
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("Disposable Postgres did not become ready")

        run("docker", "exec", "-i", CONTAINER, "psql", "-X", "-U", "supabase_admin",
            "-d", "postgres", "-v", "ON_ERROR_STOP=1", sql=PLATFORM)
        for migration in sorted((ROOT / "migrations").glob("*.sql")):
            run(*PSQL, sql="begin;\n" + migration.read_text() + "\ncommit;\n")

        owner, second = owners
        today = query("select current_date::text")
        setup = f"""
insert into auth.users(id) values('{owner}'),('{second}');
insert into public.profiles(user_id,timezone,birth_date) values
 ('{owner}','UTC','1990-01-01'),('{second}','UTC','1990-01-01');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values
 ('{owner}','concurrency-test','granted','test','en'),
 ('{second}','concurrency-test','granted','test','en');
insert into nb.calculation_work(user_id,dirty_from)
 values('{owner}','{today}'::date-2),('{second}','{today}'::date-2)
 on conflict(user_id) do update set dirty_from=excluded.dirty_from;
"""
        query(setup)
        now = query("""select to_char(date_trunc('minute',now() at time zone 'UTC'),
          'YYYY-MM-DD"T"HH24:MI:SS"Z"')""")
        sample_time = now
        domain_entries = []
        for domain in ("hrv", "temperature", "rr"):
            sample = {"ts": sample_time}
            sample.update({"hrv": 42} if domain == "hrv" else
                          {"temp": 36.5} if domain == "temperature" else {"rr_ms": [800, 810]})
            domain_entries.append({
                "p_device_key": "bundle-concurrency-band",
                "p_domain": domain,
                "p_day": today,
                "p_timezone": "UTC",
                "p_start": f"{today}T00:00:00Z",
                "p_end": f"{today}T23:59:59Z",
                "p_samples": [sample],
                "p_status": "complete",
                "p_mapping_version": "veepoo-rmssd-v2",
                "p_observed_at": now,
                "p_receipts": [],
            })
        encoded_domains = json.dumps(domain_entries, separators=(",", ":"))

        lock = hold_work_lock(owner, 4)
        started = time.monotonic()
        settle = query(authenticated(owner, "select public.settle_now(0);"))
        elapsed = time.monotonic() - started
        lock.wait(timeout=10)
        if lock.returncode:
            raise RuntimeError(lock.stderr.read())
        if settle.splitlines()[-1] != "-1" or elapsed >= 3:
            raise AssertionError(f"settle_now lock fast-fail was {settle!r} after {elapsed:.2f}s")
        print(f"PASS C1: settle_now returned -1 in {elapsed:.2f}s")

        lock = hold_work_lock(owner, 4)
        started = time.monotonic()
        first_bundle = query(bundle_sql(owner, encoded_domains))
        elapsed = time.monotonic() - started
        lock.wait(timeout=10)
        if lock.returncode:
            raise RuntimeError(lock.stderr.read())
        response = json.loads(first_bundle.splitlines()[-1])
        if elapsed >= 4 or not all(entry.get("deferred") for entry in response["results"]):
            raise AssertionError(f"bundle did not defer promptly under lock: {response}, {elapsed:.2f}s")
        resent = json.loads(query(bundle_sql(owner, encoded_domains)).splitlines()[-1])
        if not all("ok" in entry for entry in resent["results"]):
            raise AssertionError(f"bundle retry did not ingest after lock release: {resent}")
        print(f"PASS C2: bundle deferred in {elapsed:.2f}s and succeeded after lock release")

        for user in owners:
            query(f"""insert into public.raw_samples(user_id,ts,sampled_tz,heart,met)
              values('{user}',now()-interval '1 hour','UTC',70,1.2)
              on conflict(user_id,ts,src) do update set heart=excluded.heart;""")
        call_started = time.monotonic()
        run(*PSQL, sql="call nb.settle_accounts(2);")
        call_elapsed = time.monotonic() - call_started
        commits = int(query("select count(distinct xmin::text) from public.recompute_log where reason='cron';"))
        if commits < 2:
            raise AssertionError(f"settle_accounts logged {commits} distinct account transactions")
        print(f"PASS C3: settle_accounts completed in {call_elapsed:.2f}s with {commits} committed cron transactions")
    finally:
        if created:
            run("docker", "rm", "-f", CONTAINER, check=False)


if __name__ == "__main__":
    main()
