#!/usr/bin/env bash
# Disposable, network-isolated PostgreSQL; never writes linked/shared databases.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
band_dir="$(mktemp -d "${TMPDIR:-/tmp}/nb-band-revisions.XXXXXX")"
band_container="nb-band-revisions-$(date +%s)-$$"
cleanup() {
  docker rm -f "$band_container" >/dev/null 2>&1 || true
  rm -rf "$band_dir"
}
trap cleanup EXIT
python3 "$here/build_harness.py" "$band_dir/harness.sql"
docker run -d --network none --name "$band_container" \
  -e POSTGRES_PASSWORD=isolated-test-only -e POSTGRES_DB=nb postgres:16-alpine >/dev/null
for _ in $(seq 1 30); do
  if docker exec "$band_container" pg_isready -h 127.0.0.1 -U postgres -d nb >/dev/null 2>&1; then break; fi
  sleep 1
done
run_sql() {
  docker cp "$1" "$band_container:/tmp/$(basename "$1")" >/dev/null
  docker exec "$band_container" psql -U postgres -d nb -q -v ON_ERROR_STOP=1 -f "/tmp/$(basename "$1")"
}
run_sql "$band_dir/harness.sql"
run_sql "$here/../band_ingestion.sql"
run_sql "$here/../band_observation_revisions.sql"
python3 "$here/concurrency.py" "$band_container"
