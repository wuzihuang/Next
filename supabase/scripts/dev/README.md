# dev · driving `turn` without the dock

Three harnesses, all reading `NB_DEV_DIR` (default: this directory) for two files that are
never committed: `apikeys.json` (the project's API keys, `GET /v1/projects/<ref>/api-keys?reveal=true`
with the Management token from `supabase/.env`) and `session.json` (a session for the test
account — mint one with the admin magic-link path: `POST /auth/v1/admin/generate_link
{type:"magiclink", email}` with the service role, then `POST /auth/v1/verify {type:"magiclink",
token_hash}` with the anon key; the scripts refresh it themselves afterwards).

- `turn-test.py <base> <question>…` — POST /turn as the user, print tools → envelope. Base is
  `https://<ref>.supabase.co/functions/v1` or a local `serve-local.ts` host.
- `source-test.ts [dayKey]` — every chart data source against the hosted DB, straight from
  `_shared/sources.ts`: `deno run -A --config supabase/functions/deno.json supabase/scripts/dev/source-test.ts`.
- `panel.sh <tag>…` — pin one panel state per launch with `NB_DEBUG_PANEL` and grab it. A tag is
  any of the 27 widget types or the word `thinking`. This is the only way to photograph a widget
  whose data the account does not have today, or a state that is on screen for two seconds.
- `device-turn.sh "<question>" <tag>` — install the Debug build on the iPhone, launch it with
  `NB_DEBUG_TURN`, grab the screen twice (needs the ScreenGrab.app from the simulator notes),
  and print the app's `NB turn ·` log line.

⚠️ Port 8000 on this machine is held by an unrelated Python process; serve the functions on 8787.

## Inspecting the current database definitions locally

```sh
python3 supabase/scripts/inspect-schema.py \
  --test supabase/tests/calculation_validity.sql \
  --test supabase/tests/calculation_revisions.sql \
  --test supabase/tests/settle_time_budget.sql \
  --test supabase/tests/settle_reaches_newest_sample.sql \
  --test supabase/tests/calculation_archive_recovery.sql
```

Requires Docker, Python 3 and the locally available
`public.ecr.aws/supabase/postgres:17.6.1.166` image. This tool uses no project
credentials or linked database: it starts its own disposable container with no
network or published ports and disables cron execution. The image supplies auth
and platform roles; a small storage table fixture supplies storage-api's database
prerequisites. Every application migration is then installed in order, unchanged.
This validates PostgreSQL functions, permissions and synthetic SQL behavior, not
storage HTTP, scheduled jobs or hosted deployment configuration.

The printed output directory contains `schema.sql`, searchable `functions.sql`,
pgTAP results, and `manifest.json` with the exact migration hashes. Exported
functions are recompiled and re-exported to check that the definitions round-trip.
Files are generated review artifacts; do not edit or commit another current-schema
copy beside the migrations. `--output` selects a new directory; `--through` accepts
one migration filename prefix to reproduce a baseline. The container is removed
even when a migration or test fails, and failed/incomplete pgTAP output exits nonzero.

Settlement validity is owned by `nb.calculation_result_is_current`: publication
version, historical profile revision, dirty frontier and clock are checked once
for both `calculation_status.pending` and `recompute_range` reuse. The published
version comes from `nb.calculation_version`. An open day may reuse a result for
less than five minutes; a closed day must reach its end. Input revisions are
account-wide, so an older day's lower revision alone does not invalidate it: the
dirty frontier determines which carry-forward dependencies changed.
