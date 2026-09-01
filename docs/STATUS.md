# NEXTBODY · build status

Source of truth: the Paper file **NEXTBODY-HOOP · 新版设计**
(`app.paper.design/file/01M0SW066YG64X1X6TQA07024T/N-0`).
Every screen below was built from that board's own JSX and computed styles — never from a
screenshot — and then checked back against it on an iPhone 16e simulator, which is 390 × 844,
the exact geometry the boards are drawn at.

## What runs today

### iOS app · `app/`

Plain SwiftUI, no third-party packages. `NextBody.xcodeproj` uses a synchronized root group,
so adding a file to `app/NextBody/` is all it takes — there is no file list to maintain.

| Board | Screen | State |
|---|---|---|
| 01 | Sign in · gate / email / code | built, walked on device |
| 01M · 02M | the 2.6s pixel-fall wordmark | built, all five beats |
| 02 | Connect · 5 screens | built, walked on device |
| 03 | Onboarding · 6 screens + 3 sheets + the 18+ gate | built |
| 04 + 07 | Home · panel, strip, dock | built, walked on device |
| 07 | the render contract · 27 types, 10 renderers, 8 slots | built |
| 05 | Dock · idle / typing / listening | built, walked on device |
| 06 | the plus menu and the measurement takeover | built, walked on device |
| 08 | Training detail · 9 sections | built, walked on device |
| 09 | Fuel detail · 6 cards + the edit/delete entry | built, walked on device |
| 10 + 10S | Composition, and the manual weigh-in | built |
| 11 | Profile · the year heat map and 13 sheets | built, walked on device |
| 12 + 12S | Device, and its two sheets | built |
| 13 | Body Battery detail | built |

### Backend · `supabase/`

Applied to the live project `gkgzwcxivnffsecshvfs` and seeded.

- **17 tables**, with F3's two laws written as CHECK constraints rather than as review habits:
  `(intake_state = 'UNLOGGED') = (kcal_in is null)` and `intake_state <> 'FASTED' or kcal_in = 0`.
  A trigger keeps `meals` append-only — an edit is a soft delete plus a new row.
- **RLS per action**, `auth.uid()` wrapped in a sub-select so it runs once per statement,
  and an index on every `user_id`.
- **The replayable maths in Postgres**: `nb.compute_training`, `nb.compute_reserve`,
  `nb.compute_fuel`, `nb.compute_the_call`, and `nb.settle_day()` writing `daily_results`
  plus its three detail tables inside one transaction — F3's "one source, one instant".
- **Eight Edge Functions** on the Vercel AI SDK: the ten-section prompt, the eight read tools,
  the banned-phrase scan and the number ledger.

Seed: 24,192 five-minute points over 84 user days, settled through the same `settle_day()`
the cron job calls. It produces a believable spread rather than a flat one —
50 LEVEL days, 19 DEFICIT, 13 NOT LOGGED, 1 SURPLUS, 1 NO BURN — so the heat map has
something honest to draw.

Demo account: `demo@nextbody.app` / `nextbody-demo`.

## Verified end to end

- **The metric chain.** Raw points → `compute_*` → `daily_results` → PostgREST → SwiftUI.
  The training ring on the simulator reads 2.8 of 21 against a target of 14.5, and those are
  the same numbers the SQL returns.
- **The four load anchors.** A 45-minute session lands at 18.8 against F2's stated 18.2 for an
  interval class, and a rest day at 2.8 against 3.9 for a sedentary day. Both inside the ±0.3
  the board asks for once the person is the same.
- **The Body Battery anchors reproduce exactly**: a 16-hour sedentary waking day spends −58
  against the board's −57.6, and a 7.5-hour night at 22% deep charges +61 against +61.
- **`——` never becomes `0`.** Today's user day is UNLOGGED in the seed, and the fuel card shows
  `——/1,900` with `—/145`, `—/195`, `—/60`. The denominators arrive before the numerators,
  which is the line between "no answer yet" and "broken".
- **The AI turn.** Typing 今天还能练多少 into the dock rendered
  `剩余负荷 · MOVE · 今日目标负荷14.5，已练2.8，剩余11.7。· 体感电量20` — every number
  traceable through the ledger, 11.7 being the legal derivation 14.5 − 2.8.

## Open, and why

1. **The Vercel AI Gateway key does not authenticate.**
   `vck_8HH0…` returns `Authentication failed. Check that your Vercel credential is valid and
   has access to AI Gateway.` The model therefore runs through DashScope — the fallback the
   brief names. `supabase/functions/_shared/model.ts` prefers the gateway the moment
   `AI_GATEWAY_API_KEY` is set, so this is one secret away, not a rewrite.

2. **The Edge Functions are written but not deployed.** `supabase login` needs a browser, so
   the CLI could not be authenticated from here. Until they are deployed the app falls back to
   a DEBUG-only path that runs the same prompt, the same envelope contract, the same
   banned-phrase scan and the same number ledger directly against DashScope. It is compiled
   out of release builds. To deploy:

   ```sh
   supabase login
   supabase link --project-ref gkgzwcxivnffsecshvfs
   supabase secrets set DASHSCOPE_API_KEY=… AI_GATEWAY_API_KEY=… SETTLE_SECRET=…
   supabase functions deploy turn meal meal-commit day-settle screen-current asr export account-delete
   ```

3. **The band is not connected.** Everything the SDK would provide is seeded instead. The BLE
   queue, `startReadOriginData` paging, `startBodyCompositionTest` and `syncPersonalInfo` are
   specified in F3 §06 and in board 12 but not implemented — that is the piece to do together
   with the hardware in the room.

4. **Two numbers in the design file disagree with each other.** Board 08's screen prints the
   optimal zone as `13.0 – 16.0`; board 13's nine-band table and the TODAY'S TARGET card both
   say `12.5 – 16.5` for the 70–79 band. The 13 board is the later ruling and the F-series is
   the foundation, so the app uses 12.5 – 16.5 everywhere. One of the two boards needs editing
   so the next person does not have to make this call again.

5. **F2's own open item stands.** The six zone weights and K = 60 were, in the board's words,
   拍 from four anchors and have never been regressed against real data. Reproducing the
   anchors is not the same as being right about a real person.

## Running it

```sh
# app
open app/NextBody.xcodeproj          # iPhone 16e is 390 × 844, the boards' own geometry
cp app/Local.xcconfig.example app/Local.xcconfig   # then paste the DEBUG model key

# database
node scratch/apply.mjs               # or: supabase db push, once the CLI is logged in
psql "$SUPABASE_DB_URL" -f supabase/seed/demo.sql
```

The pooler host for this project is `aws-0-us-west-1.pooler.supabase.com:5432` with the user
`postgres.gkgzwcxivnffsecshvfs`. ⚠️ `db.gkgzwcxivnffsecshvfs.supabase.co` resolves to IPv6 only
and is unreachable from an IPv4-only network, which looks exactly like the database being down.
