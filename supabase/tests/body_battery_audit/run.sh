#!/usr/bin/env bash
# Synthetic diagnostic only. A reproduced defect exits 1, not a successful test.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
audit_dir="$(mktemp -d "${TMPDIR:-/tmp}/nb-body-battery-audit.XXXXXX")"
audit_container="nb-body-battery-audit-$(date +%s)-$$"
audit_created=false
cleanup() {
  if "$audit_created"; then docker rm -f "$audit_container" >/dev/null 2>&1 || true; fi
  rm -rf "$audit_dir"
}
trap cleanup EXIT

python3 "$here/build_harness.py" "$audit_dir/harness.sql"
docker run -d --network none --name "$audit_container" \
  -e POSTGRES_PASSWORD=isolated-audit-only -e POSTGRES_DB=nb \
  postgres:16-alpine >/dev/null
audit_created=true
ready=false
for _ in $(seq 1 30); do
  if docker exec "$audit_container" pg_isready -h 127.0.0.1 -U postgres -d nb >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if ! "$ready"; then echo "AUDIT_ERROR: isolated Postgres did not become ready" >&2; exit 2; fi
run_sql() {
  docker cp "$1" "$audit_container:/tmp/$(basename "$1")" >/dev/null
  docker exec "$audit_container" psql -U postgres -d nb -q -v ON_ERROR_STOP=1 \
    -f "/tmp/$(basename "$1")"
}
run_sql "$audit_dir/harness.sql"
run_sql "$here/fixtures.sql"
run_sql "$here/findings.sql"
run_sql "$here/regressions.sql"
run_sql "$here/cross_day_clock.sql"
run_sql "$here/../../migrations/20260906132450_sleep_hrv_observation_revisions.sql"
docker cp "$here/../../migrations/20260906145500_body_battery_evidence_performance.sql" \
  "$audit_container:/tmp/body_battery_evidence_performance.sql" >/dev/null
run_sql "$here/evidence_performance.sql"
# The equivalence test rolls back its fixtures and migration together.
run_sql "$here/../../migrations/20260906145500_body_battery_evidence_performance.sql"
run_sql "$here/sleep_hrv_revisions.sql"
failures="$(docker exec "$audit_container" psql -U postgres -d nb -Atq \
  -c "select count(*) from audit_findings where status <> 'CHECK_PASSED'")"
if [[ "$failures" != "0" ]]; then
  echo "AUDIT FINDINGS: $failures failed contracts. This is not a passing validation."
  exit 1
fi
echo "All audited contracts passed. This diagnostic does not validate clinical calibration."
