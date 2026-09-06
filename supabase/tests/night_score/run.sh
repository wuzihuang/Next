#!/usr/bin/env bash
# ADR 0008 · exercise the sleep score against a throwaway Postgres.
#
# The scoring function is the one piece of this feature that cannot be read for correctness:
# four groups, renormalisation over absent inputs, and a baseline that migrates from the
# population to the person between the 14th and 28th night. This stands up a container with
# just the tables it touches, runs the real migration into it, and scores synthetic nights.
#
#   supabase/tests/night_score/run.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
name=nb-score-test

# Removal is asynchronous: starting the next container while the old name is still being
# torn down gives you a database with the previous run's schema still in it, and the
# migration then fails to find an anchor it would have found on a clean one.
docker rm -f "$name" >/dev/null 2>&1 || true
for _ in $(seq 1 30); do docker inspect "$name" >/dev/null 2>&1 || break; sleep 1; done
docker run -d --name "$name" -e POSTGRES_PASSWORD=test -e POSTGRES_DB=nb postgres:16-alpine >/dev/null
for _ in $(seq 1 30); do docker exec "$name" pg_isready -U postgres -d nb >/dev/null 2>&1 && break; sleep 1; done

run() { docker cp "$1" "$name:/tmp/$(basename "$1")" >/dev/null
        docker exec "$name" psql -U postgres -d nb -q -v ON_ERROR_STOP=1 -f "/tmp/$(basename "$1")"; }

run "$here/00_harness.sql"
run "$root/supabase/migrations/20260905100000_night_score.sql"
run "$root/supabase/migrations/20260905100002_night_score_rem_and_recovery_scope.sql"
run "$here/01_scoring.sql"
docker exec "$name" psql -U postgres -d nb -c "
select name as case, got->>'score' as total, got->>'duration_score' as duration,
       got->>'architecture_score' as architecture, got->>'recovery_score' as recovery,
       got->>'regularity_score' as regularity, got->>'personal_weight' as personal
from t_out order by name;"
run "$here/02_lifecycle.sql"

docker rm -f "$name" >/dev/null
echo "✅ night_score: scoring table above, lifecycle assertions passed"
