#!/usr/bin/env python3
"""Rebuild local migrations in an isolated database; export the effective definitions."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
IMAGE = "public.ecr.aws/supabase/postgres:17.6.1.166"

# The Postgres image initializes auth and platform roles, but storage-api owns its
# tables. These are platform prerequisites only: all app tables/functions/policies
# below come from the unmodified migration chain. No storage HTTP service is run.
PLATFORM = """
create extension if not exists pg_cron with schema extensions;
create extension if not exists pgtap with schema extensions;
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


def command(*args, sql=None):
    result = subprocess.run(args, input=sql, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{' '.join(args)}\n{result.stdout}{result.stderr}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="New export directory (defaults to a temporary directory)")
    parser.add_argument("--test", action="append", default=[], type=Path,
                        help="Run a pgTAP SQL file after rebuilding; may be repeated")
    parser.add_argument("--through", help="Rebuild through this migration filename prefix (for baseline comparisons)")
    args = parser.parse_args()
    output = args.output or Path(tempfile.mkdtemp(prefix="next-schema-"))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    migrations = sorted((ROOT / "migrations").glob("*.sql"))
    if args.through:
        matches = [i for i, path in enumerate(migrations) if path.name.startswith(args.through)]
        if len(matches) != 1:
            parser.error("--through must identify exactly one migration")
        migrations = migrations[:matches[0] + 1]
    # Snapshot first so concurrent edits cannot produce an untraceable mixed build.
    sources = [(path.name, path.read_text()) for path in migrations]
    name = f"nb-schema-{uuid.uuid4().hex[:12]}"
    created = False

    def sql(text, role="postgres"):
        return command("docker", "exec", "-i", name, "psql", "-X", "-U", role,
                       "-d", "postgres", "-Atq", "-v", "ON_ERROR_STOP=1", sql=text)

    try:
        command("docker", "run", "-d", "--pull=never", "--network", "none", "--name", name,
                "-e", "POSTGRES_PASSWORD=isolated-schema-only", "-e", "POSTGRES_DB=postgres",
                IMAGE, "-c", "shared_preload_libraries=pg_cron", "-c", "cron.database_name=postgres",
                "-c", "cron.launch_active_jobs=off")
        created = True
        for _ in range(60):
            # The image's initialization server accepts sockets before platform
            # migrations finish; TCP is available only after the final restart.
            ready = subprocess.run(["docker", "exec", name, "pg_isready", "-h", "127.0.0.1", "-U", "postgres", "-d", "postgres"],
                                   capture_output=True).returncode == 0
            if ready:
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("Isolated Postgres did not become ready")
        sql(PLATFORM, role="supabase_admin")
        for filename, source in sources:
            print(f"Apply {filename}", flush=True)
            sql("begin;\n" + source + "\ncommit;\n")
        schema = command("docker", "exec", name, "pg_dump", "-U", "postgres", "-d", "postgres",
                         "--schema-only", "--schema=public", "--schema=nb", "--no-owner")
        (output / "schema.sql").write_text(schema)
        definitions_query = """
select pg_get_functiondef(p.oid)||';' from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('nb','public') and p.prokind='f'
order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);
"""
        definitions = sql(definitions_query)
        (output / "functions.sql").write_text(definitions)
        # Recompile exactly what was exported, then check that PostgreSQL emits the
        # same definitions. This rejects stale/manual exports and syntax drift.
        sql("begin;\n" + definitions + "\ncommit;\n")
        if sql(definitions_query) != definitions:
            raise RuntimeError("Exported function definitions did not round-trip")
        test_results = []
        for test in args.test:
            result = sql(test.read_text())
            (output / f"{test.stem}.tap").write_text(result)
            print(result, end="", flush=True)
            if re.search(r"(?m)^not ok\b|^# (?:Looks like|No tests run)", result):
                raise RuntimeError(f"pgTAP failure: {test}")
            plans = re.findall(r"(?m)^1\.\.(\d+)\s*$", result)
            assertions = re.findall(r"(?m)^ok \d+\b", result)
            if len(plans) != 1 or len(assertions) != int(plans[0]):
                raise RuntimeError(f"Incomplete pgTAP output: {test}")
            test_results.append({"file": str(test), "assertions": len(assertions)})
        manifest = {
            "postgres_image": IMAGE,
            "migrations": [{"file": name, "sha256": hashlib.sha256(source.encode()).hexdigest()}
                           for name, source in sources],
            "functions_sha256": hashlib.sha256(definitions.encode()).hexdigest(),
            "functions_round_trip": True,
            "tests": test_results,
        }
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"Verified schema export: {output.resolve()}", flush=True)
    finally:
        if created:
            subprocess.run(["docker", "rm", "-f", name], capture_output=True)


if __name__ == "__main__":
    main()
