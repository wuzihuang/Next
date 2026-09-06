#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
name=nb-wear-test

docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --name "$name" -e POSTGRES_PASSWORD=test -e POSTGRES_DB=nb postgres:16-alpine >/dev/null
for _ in $(seq 1 30); do docker exec "$name" pg_isready -U postgres -d nb >/dev/null 2>&1 && break; sleep 1; done

run() { docker cp "$1" "$name:/tmp/$(basename "$1")" >/dev/null
        docker exec "$name" psql -U postgres -d nb -q -v ON_ERROR_STOP=1 -f "/tmp/$(basename "$1")"; }

run "$here/00_harness.sql"
run "$root/supabase/migrations/20260905120000_wear_run.sql"
run "$here/01_scoring.sql"

docker rm -f "$name" >/dev/null
echo "✅ wear_run: worn-day threshold, miss colours, and restart-from-1 passed"
