# Fine-grained history archival

Deploy `archive-data` after applying the sample archive migration. It processes at
most 500 rows older than 400 days per request, verifies gzip readback, and removes
only unchanged hot rows. The public owner-authenticated body is
`{"domain":"raw_samples"}` (or `band_rr_evidence`). `more:true` requests another
bounded batch. No cold expiry exists. Failed archival keeps the hot records.

For scheduled operation, call the same endpoint from a trusted scheduler using the
service role bearer credential and body `{"user_id":"<account UUID>","domain":"raw_samples"}`.
The owner must remain active in profiles; preparation/finalization lock the profile
against deletion. Process both domains, repeat while `more`, with an overall job
budget and retry/backoff; spread accounts across runs rather than looping forever.
Store the scheduler credential in its secret manager. Never embed it in an app,
SQL migration, or logs. Scheduling/credential provisioning is a deployment step;
this change does not configure a production scheduler.

Monitor failures, oldest unarchived sample age, pending manifest age, and Storage
size. Alert when oldest hot evidence exceeds 401 days and archive runs are failing
or absent. Until scheduling is configured or requests are made, raw pruning stays
paused deliberately; the existing 90-day frame / 180-day analytics sweeps continue.
A pending manifest can indicate an interrupted upload. Before cleanup inspect its
state again; never delete a verified object, including after a lost finalization
response. Account deletion removes all objects under the account prefix, pending
and verified, before cascading manifests.

History readers return explicit archive-unavailable errors on corruption, failed
reads, or the bounded read budget (100 archive batches, 100,000 hot rows). Request
narrower intervals for large histories. Exports fail explicitly rather than return
a partial history. Larger asynchronous exports are future work.

## Recovery for historical calculation

Send `{"action":"recover","from":"<ISO start>","to":"<ISO end>"}` with the
same owner or trusted scheduler authorization. Each request first resumes at most
seven calculation days. If archived inputs are needed, the calculation RPC supplies
authoritative baseline-plus-batch bounds; restore at most ten verified objects,
then resume the bounded calculation. Repeat while `calculation.pending` or `more`
is true. Once all dependent days finish, the same action releases at most ten
hydrated batches per request, using their existing verified objects. It does not
create duplicate archives. `action:release` can also resume only that final cleanup.

Hydration and release preserve logical input revisions and hot corrections. New
archival preparation is paused while hydrated inputs remain, preventing a
concurrent archive job from removing a recovery batch. Account tombstones block
both operations. Older legacy inputs erased before the coverage floor return an
explicit calculation-unavailable error; they cannot be reconstructed.
