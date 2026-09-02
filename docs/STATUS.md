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
| 01M · 05 | the 7.40s first run, eleven beats and four fallbacks | built, walked on device |
| 02 | Connect · 5 screens | built, walked on device |
| 03 | Onboarding · 6 screens + 3 sheets + the 18+ gate | built, walked on device |
| 04 + 07 | Home · panel, strip, dock | built, walked on device |
| 07 | the render contract · 27 types, 10 renderers, 8 slots | built |
| 05 | Dock · idle / typing / listening | built, walked on device |
| 06 | the plus menu and the measurement takeover | built, walked on device |
| 08 | Training detail · 9 sections | built, walked on device |
| 09 | Fuel detail · 6 cards + the edit/delete entry | built, walked on device |
| 10 + 10S | Composition, and the manual weigh-in | built, walked on device |
| 11 | Profile · the year heat map and 13 sheets | built, walked on device |
| 12 + 12S | Device, and its two sheets | built, walked on device |
| 13 | Body Battery detail | built, walked on device |

### The band · `app/NextBody/Services/Band/`

The SDK ships **arm64 only** — `lipo -info` on `VeepooBleSDK` says
`Non-fat file: architecture: arm64` — so it cannot link into a simulator build at all.
The app is therefore written against a `BandService` protocol with two implementations:

- `MockBand` on the simulator, which answers on the real timings: the scan takes 2.2s,
  contact arrives ~1.2s after the finger lands, and a body scan really does take 30s.
  A stub returning instantly would hide every timing bug the takeover has, which is the
  only part of that flow that is hard to get right.
- `VeepooBand` on a device, behind `#if canImport(VeepooBleSDK)`. Drag the framework into
  the target as *Embed & Sign* and `Band.live` picks it up — nothing else changes.

`HoopQueue` is F3 §06: one serial queue, exactly one native command in flight, P0/P1/P2,
and a higher priority jumps the queue head but never interrupts the command already running.

`OriginDataSync` is F2 §01: it works out the user-day window first and only then decides how
many pages to pull — one in daylight, two in the small hours and at every day close.

Wired through: the pairing sequence runs four real steps, the device page reads identity,
capabilities and the three-value battery, the automatic-measurement sheet lists what this
HOOP actually reports, and the measurement takeover is driven by the band's own contact
signal rather than by a timer pretending to be one.

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

Seed: 26 weeks of five-minute points — 182 user days, the exact width of board 11's heat map
— settled through the same `settle_day()` the cron job calls. It produces a believable spread
rather than a flat one: 114 DEFICIT, 42 LEVEL, 4 SURPLUS, 20 NOT LOGGED, 1 NO BURN.

⚠️ The seeded person is tuned, not sprinkled. Three things about them are load-bearing and a
casual edit will break a screen:

- **They sit still.** A resting tick is HR ≤ RHR+5 *and* met < 1.2 *and* steps = 0. The first
  seed put a few steps on every five-minute block, so nothing was ever resting, the battery
  drained 0.30 a tick from breakfast to midnight and hit the floor daily. The desk band
  (50–58 bpm) straddles RHR+5 on purpose.
- **They train in Z3.** TRAINING_LOAD is 21·(1−e^(−RAW/60)) and saturates fast: 45 minutes at
  Z4 spends 135 raw and lands on 18.5 against a 20.9 cap, so a Z4-every-evening seed read 19
  out of 21 every day and RECENT LOAD said HEAVY forever. Z3 is 54 raw and lands on 12.4 —
  the number board 04 prints.
- **Their intake swings.** A flat intake against a near-flat burn puts all 182 days in one
  bucket. The 0.80–1.35 per-day factor spans −520 to +380 kcal, which is what gives 11 three
  colours and 12 a seven-day mean inside its −200 to −500 recomp window.

The per-day seed is `hashtext(day)`, not `i * 7919 mod 1000` — that walks down by 81 a day, so
consecutive days land on the same side of every threshold and the three most recent days came
out as three hard sessions in a row.

Demo account: `demo@nextbody.app` / `nextbody-demo`.

## The audit, screen by screen

Every screen was opened on the simulator and read against its board. The pass turned up
fourteen places where the app was printing the board's *example* numbers over live data —
the same failure each time, and the reason to do it on a device rather than in the diff:

- **13 · Body Battery** printed the board's four attribution rows (+38 / −14 / −9 / −3) under
  a live headline, so the card read "these four add up to +12 · 60 → 20". The rows are the
  day's own now, they close within 0.5 per 1CUP, and when they do not close the whole card is
  absent rather than fudged.
- **08 · Training** lit all four WHY signals and printed a fixed 06:40 walk, a 12:10 cycle
  commute and 8,432 steps on every day forever. The build rows are segments cut out of the
  tick stream now, allocated as shares of the day's raw work so the column adds up to the ring.
- **09 / 10 · Fuel** said "3 MEALS · LAST 16:10" on a day with two, and measured macros against
  its own 145 / 195 / 60 while the server's split for this person is 145 / 215 / 60.
- **12 · Composition** sat in its empty state — NO CALL · FAT —— · 0 OF 5 SIGNALS READY — on an
  account with six months of scans, because `compute_the_call`'s working was thrown away at
  settle time and the page read today's row out of the wrong collection.
- **11 · Profile** showed "ZEPH · you@nextbody.app" over a real account.
- **10S · the weigh-in sheet** always opened claiming Apple Health had a new reading of 78.6 kg
  — on a build with no HealthKit entitlement at all.
- **01 · the email screen** compensated for the keyboard twice and drew its title over the
  status bar clock, with the back chevron and STEP 01 / 02 gone off the top edge.

A second pass went after the things a screenshot cannot show.

**Every table, counted rather than assumed.** Five of the twenty had never had a row
written to them, each for its own reason and none of them "not built yet": sync_runs was
written without the NOT NULL user_id and every insert was swallowed by a `try?`;
analytics_events was rejected because the insert helper always asked for the row back and
RETURNING needs a select policy on a table that is deliberately write-only; recompute_log
stayed empty because the logging version of recompute_range *overloads* the old signature
rather than replacing it, so every caller kept resolving to the old one; device_capabilities
was read and written by nobody; and ai_turns had no client insert policy, so the on-device
turn — the one path whose turns most need a record — left no trace. All twenty hold data now.

**Controls that did nothing.** The DAY / WEEK / MONTH segment sat on three pages and changed
only its own pill. The boards rule on it three times (ZUO, VAF, 1EIH) and all three say
delete, so 08 and 09 lost it; 12 keeps DAY and WEEK because 18FW says both have real screens,
and its week view is now built to 19YC / 19YF / 19YI / 19YL. START A SESSION was an empty
closure and is now visibly disabled with its reason, per 10PV.

**Writes that only moved the screen.** The training-goal sheet assigned `data.profile.goal`
and stopped; the row said RECOMP while the server went on computing from the old value.
DELETE EVERYTHING called `session.reset()` — it signed the user out and deleted nothing,
under a sentence reading "There is no undo".

Two of the first pass's findings were real bugs rather than mock data: a one-day refresh after a band sync
*assigned* `store.history`, dropping the other 181 days the week bars and the heat map are made
of; and `the_call` is stored as `NO_CHANGE` while the token on screen is `MEASURED, NO CHANGE`,
so mapping by rawValue silently dropped that one verdict.

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

## The Edge Functions, run for real

They were served locally with Deno against the live Supabase and the live model, and calling
them found four bugs a typechecker could not:

1. `ai@4.3.16` pulls a `zod-to-json-schema` that imports `zod/v3`, a subpath `zod@3.23.8`
   does not export. Pinned to `zod@3.25.76`.
2. `generateObject` reaches for a `json_schema` response format that DashScope's
   OpenAI-compatible endpoint does not accept. It needs `mode: "json"`.
3. `screen.render` was written as text for the server to parse back. Board 07 · S1 says the
   only way she speaks is by *calling* screen.render, so it is now a real tool with a real
   schema — there is no free prose to parse, and nothing to mis-parse.
4. That tool's `type` and `target` were free strings, so the model invented `type: "day"` and
   `target: "dailyDirection"` and the whole frame was rejected. With the 27 types and the 5
   targets in the tool schema it picks a real one.

What a turn does now, against the seeded account:

```
event: state         {"value":"THINKING"}
event: tool          {"name":"day.get"}
event: tool          {"name":"profile.get"}
event: tool          {"name":"screen.render"}
event: screen.render {"envelope":{"type":"gauge","title":"TODAY CAPACITY","tag":"RECOVER",
                      "sentence":"电量 19，今日负荷 19.1，方向 LEVEL",
                      "footer":"剩余可练量：无对应读数","target":"training", ...}}
event: done          {}
```

Every number traces to a tool return, and where it had none it wrote 无对应读数 rather than
inventing one — S4's absence law, holding under a real model.

Asking it a medical question renders the fixed stop frame and calls no tool at all, which is
S7 working: `NOT A DOCTOR · 这类问题请找医生。这块屏只报告测量到的数字。`

## What the audit could not reach

- **Board 07's contract is audited now**, by a DEBUG-only catalogue behind a long press on
  the wordmark: all 24 types the model may pick, rendered side by side with 07's own data
  shapes, so the ten renderers, the accent map and the four hero styles read against the
  board in three screenfuls. It found two things a screenshot of one widget never would —
  the three sleep types were on offer to the model despite 1EEU and F0 rule 03, and the
  envelope's `data.hero` was being dropped for the six types whose hero cannot be derived
  from the shape.
- **WEEK's empty state on 12**, which 1EL9 and 1ACQ say deliberately not to build: the first
  week has no previous week, and NO CALL holds that ground.
- **Anything the band has to answer.** The mock answers on the real timings, but a HOOP on a
  wrist is the only way to know the parsing is right.

## The third pass · two defects the boards' own numbers exposed

Both were found by reading the running simulator against the boards rather than the diff, and
both are fixed and re-verified on the simulator against the live seeded account.

**S7 was reachable around the side.** The dock decides between the turn path and the meal path
with `looksLikeFood`, which matches the marker 吃 — and 吃药 contains 吃. So
「我最近头晕是什么症状要吃药吗」 never reached the medical stop: it was classified as food,
`logMeal` wrote the row *before* the model was called, and it came back rendered as
`LOGGED · 1 KCAL · LOW`, name 头晕咨询, with the fuel card ticking 1,007 → 1,008. Two holes met
here. The stop lived only inside `AIDebugTurn`, which is `#if DEBUG`, so a release build had no
client-side stop at all; and `meal` / `meal-commit` had no server-side stop either, so the
sentence would have been estimated for calories on a deployed backend too. S7's wording is that
the stop happens *before any tool call*, which has to mean before the classifier, because the
classifier is what decides which tool runs. There is now one `MedicalStop` compiled into every
build, checked at the top of `handleSend`; one `MEDICAL` in `_shared/contract.ts` that both
`turn` and `meal` read; and the turn path and the dock can no longer drift apart. Re-tested: the
fixed frame renders and intake stays at 1,007.

**NEXT_MEAL never divided by the open slots.** F2 gives it three branches — one open slot is
`TARGET_IN − E_IN` with no rounding and no clamp, more than one divides by the open-slot count
then floors to 50 and clamps 150–1200, and a non-positive numerator is ——. The code did the
flooring and clamping unconditionally and never divided at all, so the whole day's remainder was
printed as though it were one meal. On the seeded account it showed `1,050 LEFT` against
`907 /1,980`, which is floor50(1073) — a number that reads like a budget, the one thing F2 says
this is not. `merge` now takes the open-slot count, counting a slot settled when it is logged or
SKIPPED per 04's three outcomes. With three of four slots logged the card now reads `973 LEFT`
against `1,007 /1,980`: exactly `TARGET_IN − E_IN`, the one-open-slot branch, un-rounded.

⚠️ `Local.xcconfig` had `NB_FUNCTIONS_BASE` pointing at `127.0.0.1:8000` with nothing serving it,
so every AI turn hung on a dead socket rather than falling through to the DEBUG path. Commented
out; the turn renders again. Uncomment it only while a local Deno server is actually up.

## Third-pass audit coverage

Walked on the iPhone 16e simulator against the live seeded account, reading the accessibility
tree for exact geometry rather than eyeballing a screenshot:

| Board | Checked | Result |
|---|---|---|
| 04 | strip geometry, both cards, dock, panel | 358×136 strip, 174×136 cards, gap 10, AI screen 358×470 — all 1:1 |
| 06 | plus menu, body-scan takeover | two groups, 60 S / 30 S, two-contact protocol run end to end |
| 07 | the DEBUG catalogue | `24 TYPES · 10 RENDERERS` — 27 less the three sleep types, F0 rule 03 holding |
| 08 | ring, WHY, build, zones, week | build rows sum to the ring exactly; 5.0 + 11.0 = 16.0 = target |
| 09 | eaten, macros, what went in | 375 + 532 + 100 = 1,007; 145−94=51, 215−85=130, 60−22=38 |
| 10S | the weigh-in sheet | no longer claims a Health reading it cannot have |
| 11 | heat map, account, preferences | 7 × 26 = 182 cells, the board's own width; DELETE ACCOUNT in-app |
| 12 | device, battery, firmware | three-value battery, CONNECTED, 2.4.1 → 2.5.0 |
| 13 | hero, WHY, inputs, target | +18 −27 −2 −2 = −13, and 65 → 52 closes exactly |

The numbers agree *across* screens, which is the part a single-screen check cannot show: the
morning battery 83% picks BAND 80–89, which sets target 16.0 and range 14.0–18.0, and those same
three numbers appear on 13's target card, 08's WHY panel and 04's training card.

Animations were read against the MOTION boards rather than watched: the wordmark's five beats sit
at 0.00 / 0.35 / 1.10 / 1.80 / 2.15 / 2.60 with `total = 2.60`, and the first run's eleven beats
at 0.00 → 7.40 including KEY at 5.20 doing 390×844 → 358×470, radius 44 → 30, spring(0.82/0.34)
over 0.62s. The measurement takeover was run live and keeps the real timings.

Not re-walked this pass, and still resting on the earlier passes: 02 Connect and 03 Onboarding
(both need an unpaired or first-run account to reach), 05's typing and listening dock states, and
10's composition detail.

## Board conflicts left standing, not silently resolved

**The readout row's staleness rule.** 04's TPH names it as 「最后一次采样超过 60 分钟整行撤掉」;
13 specifies three states — fresh under 90 minutes, stale from 90 minutes to 6 hours with the
numbers dimmed and `SYNCED HH:MM` shown, gone past 6 hours with the numbers becoming ——. The app
implements 13, and on the seeded account the row reads `HR 54 · STRESS 71 · 2 HR AGO`, which 04
would have removed outright. 13 is the specific model and 04 raises it inside 上线前必须成立 as
an open question about the bottom strip, so 13 stands — but one of the two boards needs editing.

## Open, and why

0. **Board 13's Body Battery model has no fixed point, and it is implemented as written.**
   Charge and drain are two independent sums, so a day whose sums do not cancel walks the level
   until a clamp catches it — the board's own printed day is +12 (+38 −14 −9 −3), which reaches
   100 in eight days. There is no restoring term anywhere in 1COD or 1COH. The demo bounds the
   chain to fourteen nights off the cold-start 20 rather than pretending to a stability the
   formula does not have. Related: F2 §02 says BODY_BATTERY(t) is 清醒时段单调不增, which 13's
   `charge_rest` contradicts outright — a resting waking tick nets +0.10. 13 wins, because F2
   itself says 系数与式子在 13 板首发. Both need a ruling before launch.

1. **The `vck_…` key is a Vercel access token, not an AI Gateway API key.** It is valid —
   `GET api.vercel.com/v2/user` returns the account and team — but the gateway refuses it,
   and its own error says why: *"Create an API key and set in AI_GATEWAY_API_KEY."* There is
   no API to mint one; it is made at **vercel.com → your team → AI Gateway → API Keys**.
   Until then the model runs through DashScope, the fallback the brief names.
   `model()` now ignores a `vck_` key rather than sending a request that will be refused, and
   switches to the gateway the moment a real key is set.

2. **Deployment needs one `supabase login` — for four of the eight endpoints, not all of
   them.** `turn`, `asr`, `meal` and `meal.commit` exist to reach the model and need Deno, so
   they need the CLI. The other four were database work, and they are deployed and running:

   | | |
   |---|---|
   | the settle job | `pg_cron`, hourly, per-user calendar, two days back |
   | retention | `pg_cron` nightly · 400 / 90 / 180 days per 1DLA |
   | `account.delete` | `public.account_delete(confirm)` RPC |
   | `export` | `public.export_all()` RPC |

   The CLI's login is a browser flow, so it could not be done from here. The four model-facing
   functions are finished and proven — run these four lines with `!` in front and they are live:

   ```sh
   supabase login
   supabase link --project-ref gkgzwcxivnffsecshvfs
   supabase secrets set DASHSCOPE_API_KEY=… SETTLE_SECRET=…
   supabase functions deploy turn meal meal-commit day-settle screen-current asr export account-delete
   ```

   Until then the app uses a DEBUG-only path with the same prompt, envelope contract,
   banned-phrase scan and number ledger. It is compiled out of release builds, which I checked.

3. **The band layer is written; only the hardware test is left.** Both implementations exist
   and the whole product runs on the mock. Linking the framework and putting a HOOP on a
   wrist is the remaining step, and that is the part you said we would do together.

4. **Two numbers in the design file disagree with each other.** Board 08's screen prints the
   optimal zone as `13.0 – 16.0`; board 13's nine-band table and the TODAY'S TARGET card both
   say `12.5 – 16.5` for the 70–79 band. The 13 board is the later ruling and the F-series is
   the foundation, so the app uses 12.5 – 16.5 everywhere. One of the two boards needs editing
   so the next person does not have to make this call again.

5. **F2's own open item stands.** The six zone weights and K = 60 were, in the board's words,
   拍 from four anchors and have never been regressed against real data. Reproducing the
   anchors is not the same as being right about a real person. The board itself files this
   under 上线前必须成立, and it needs 20 people × 14 days.

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
