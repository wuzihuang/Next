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
