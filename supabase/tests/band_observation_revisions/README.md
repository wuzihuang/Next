# Device observation revisions

Run `bash supabase/tests/band_observation_revisions/run.sh` from the repository root.
The runner creates and removes a uniquely named, network-isolated PostgreSQL 16
container; it never uses a linked Supabase database. It extracts the actual
migration functions for ingestion, calculation invalidation, archive verification,
and hydration into a minimal schema with Supabase's permissive default public
table grants and the legacy raw own-INSERT policy, then runs:

- The existing band ingestion integration test, including older RPC call shapes.
- `../band_observation_revisions.sql`: ordered non-null corrections, mapper
  upgrades, complete origin snapshots and per-field auxiliary clocks, HRV retraction/restore, immutable RR extensions,
  malformed payloads, exact retry revisions, consent/account ownership, deletion
  tombstones, direct INSERT/UPDATE/DELETE/TRUNCATE and retired fill-RPC denial,
  and format-1 archive compatibility.
- `concurrency.py`: four older uploads wait on a newer transaction and cannot
  overwrite its value or create extra calculation revisions.

The SQL assertions can also run in a fully migrated disposable Supabase database;
all synthetic SQL fixtures roll back. This focused harness does not install the
whole product schema or validate physiological calibration. `p_observed_at` is a
client-recorded device read time, not proof that the physical measurement is true.
The client must persist that time through retries. Unknown legacy source identity
cannot authorize replacement of an existing value.

Origin prefers each sample's `origin_read_at`, falling back to `p_observed_at`,
and accepts only completed five-minute slots. Older complete origin snapshots
cannot refill missing fields in a newer snapshot. Auxiliary fields retain their
own clocks. The first explicit read can establish order for a known legacy
device/mapping; upload receipt time is never treated as a sensor observation time.
