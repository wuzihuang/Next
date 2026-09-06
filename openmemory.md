# Next · OpenMemory Guide

## Overview

NextBody-Hoop is a SwiftUI iOS app backed by Supabase Edge Functions and Postgres. The app
captures health data from a HOOP band, renders one AI-controlled panel on Home, and keeps
model credentials and tool execution server-side.

## Architecture

- `app/NextBody/`: SwiftUI application, BLE/band services, local repository, and the AI client.
- `app/NextBody/L10n/`: in-app language (`AppLanguage`) and English-as-key catalogs (`L()` → `Tables/zh-Hans.json`, ~1900 keys). Sign-in / pair film line is `Find your next body.` → `找你的下一副身体。` Launch mark is Doto `NEXTBODY` + lime pip + `Build Your NextBody` → `打造你的下一副身体` (English paints `BUILD YOUR NEXTBODY`). Duplicate keys in the table overwrite; the last value wins. Never reuse `CLOSE` (dismiss → 关闭) or `NEAR` (vitals → 近中位) for Find lamps — those use `Find · very near / nearer / farther / very far` → 特别近 / 较近 / 较远 / 特别远; English still paints NEAR / CLOSE / AWAY / FAR.
- `supabase/functions/`: authenticated Edge Functions for turns, ASR, meals, settlement,
  exports, and account deletion.
- `supabase/functions/_shared/`: model provider, prompt, tool catalogue, data sources,
  render contract, numeric ledger, and thought-stream processing.
- `supabase/migrations/`: Postgres schema, RLS policies, and data lifecycle changes.
- `docs/STATUS.md`: current implementation and verification record.
- `CONTEXT.md` plus `docs/adr/`: domain vocabulary and architectural decisions.
- App Store Connect: NextBody `6799623125` (`com.nextbody.hoop`, SKU `nextbody-hoop-ios`,
  team `BP7F7PYU33`, widget `com.nextbody.hoop.LiveActivity`). No TestFlight build, group,
  or tester exists yet. Do not confuse with the older phone bundle
  `com.walnutechnology.nextbody.app`.

## User Defined Namespaces

- [Leave blank - user populates]

## Components

- **AI turn** — `supabase/functions/turn/index.ts` streams SSE in the order
  `state → thought/tool → screen.render → done`; `AIService.swift` consumes it.
- **Voice input** — `SpeechCapture.swift` records 16 kHz mono PCM WAV; `/asr` transcribes it
  and deletes the temporary clip after the response.
- **Thought stream** — `_shared/thoughts.ts` converts reasoning deltas into short display lines;
  `ThinkingStage` renders the latest lines while Thinking remains enabled.
- **Data tools** — `_shared/tools.ts` exposes `data.read` + `data.catalog` over
  `_shared/data-read.ts` and `_shared/metric-query.ts`. Tick grains live in the
  same `definitions` registry (`grain: "tick"`). Catalog rows include the user's
  actual from/to coverage. System tables are not listed. Chart sources still
  fetch their own series. `_shared/sources.ts` remains the chart layer.
- **Number ledger** — `_shared/ledger.ts` rejects frame numbers that did not come from a tool.
- **App language** — `AppLanguage` stores `en` / `zh-Hans` (default English). `L("English source")` looks up the current table. The system prompt language-locks AI frames to the selected locale.

## Patterns

- Edge Functions authenticate with `getClaims` so asymmetric JWT signatures are checked
  locally and JWKS is cached; user data queries still use the caller's JWT and RLS.
- Independent turn preflight reads run concurrently before model execution.
- Daily AI allowance is shared across `/turn`, `/meal`, and `/asr`: 10 uses per day,
  unused balance rolling up to 20, with a spend ceiling. Excess returns SLOW DOWN
  without calling the model. Token usage is recorded per model call.
- A turn is two phases in one `streamText` call (`maxSteps` 6). AI SDK 4.3 has no
  per-step `prepareStep` on `streamText`, so the same `experimental_activeTools`
  array is mutated in `onStepFinish` from `nextTurnPhase`. `gateTurnTool` remains
  an execute fallback. Drawing is hidden until the read budget; one reread is
  allowed after drawing starts.
- Thinking is always enabled; `TURN_THINKING_BUDGET` controls the per-step ceiling.
- AI latency is measured at ASR response, SSE state, first thought, first tool, render, and done.
- Source-backed frames must call `data.read` for the metric before rendering.

# Next Project Guide

## Overview
- NextBody is a SwiftUI iOS app for the HOOP band with a Supabase/Postgres backend.
- The app reads five-minute physiological samples through the HBand/Veepoo BLE SDK.
- `CONTEXT.md` and `docs/adr/` define cross-cutting product language and decisions.

## Architecture
- `app/NextBody/Services/Band/`: BLE boundary, SDK mapping, sync, live measurements, and pure
  algorithms that can also be built through `app/Package.swift`.
- `app/NextBody/Services/Repository.swift`: server persistence and loading into `DataStore`.
- `app/NextBody/Services/DataStore.swift`: main-actor observable state consumed by SwiftUI.
- `app/NextBody/Features/`: root and detail screens.
- `supabase/migrations/`: schema and deterministic server-side settlement/replay.

## User Defined Namespaces
- [Leave blank - user populates]

## Components
- **Launch mark (开机)** — Doto `NEXTBODY` + the 6pt lime pip (take 1+2).
  `LaunchMark` types the word at 28ms a character (same beat as FirstRun),
  the pip lands, then the second line types. Ready cuts. Reduce Motion
  shows the last frame. Harness skips the cover.
- **Dedicated Chat & Cyber Telemetry** — `app/NextBody/Features/Chat/`: Full-screen Cyber Telemetry terminal from the Dock keyboard key. Assistant and user text go through `ChatMarkdown` (headings, lists, emphasis, fenced code) via `ChatMarkdownView`. Entering the page jumps to the latest line (`ChatScrollTarget` + `ScrollViewReader`). Header and dock are lifted `ledOff` plates with a lime inner hairline and a drop shadow so they do not sit on the same carbon as the thread. DEBUG `NB_DEBUG_CHAT_FIXTURE=markdown|long` seeds UI tests without touching the archive.
- **BodyBatteryEngine** — Pure five-minute reserve model. Fuses HR/HRV/stress/steps/MET,
  saturates sleep recovery toward 95, allows bounded verified rest recovery, and holds
  off-wrist ticks.
- **G70 capability sweep** — DEBUG `NB_DEBUG_PROBE=capsweep` (or Device → Capability sweep)
  dumps `VPPeripheralModel` types, reads female mode 2, listens 6s GSensor + 3s ADC, then
  `readFuncAssessment`. Results persist to `Documents/capsweep.txt`. 2026-09-06 wrist:
  firmware `00.80.01`, female byte 12 = 0 and calendar empty, GSensor xyz = 0 packets,
  GSensor ADC = 6 packets / 1434 bytes, FuncAssessment timeout. Not a product feature.
- **Body Battery server replay** — `nb.reserve_replay` expands `sleep_nights.sleep_line` using
  Veepoo stage ids and writes the authoritative daily curve through normal settlement. Sleep
  improves recovery but is not an output gate: a worn daytime cold start uses an assumed 50
  while leaving `BB_WAKE` and the training target unset.
- **Body Battery v2 correction** — migration `20260903150000` accepts previous-day anchors only
  when a v2 curve proves the score was calculated. A `daily_results` trigger removes stale
  reserve details/curves whenever reserve computation is unknown; deployment also clears and
  recomputes today with an audited migration reason.
- **FindDistanceMath / BandAlarmMath** — SyncCore. RSSI → NEAR/CLOSE/AWAY/FAR
  (vendor cuts, distance words). New-alarm week bitmask (LSB Monday),
  `2 / ?` until capacity is known, demo ceiling 20, one-shot date, scene 0.
  Sheets: `FindHoopSheet` (START then STOP), `AlarmsSheet` (SWITCH, no top
  hairline, Add has no rocker). Band API on `BandService`.
- **UserDay calendar** — `UserDay.last` / `hours` / `weekRolls` in SyncCore.
  Last-N 用户日, the 04:00 clock, and 7-day cuts. `rollingBack` is the instance
  form of `last`. Battery wall hours stay off this seam.
- **RollingPills** — DAY / WEEK / MONTH words, default 1 / 7 / 30 user days,
  default `TODAY` / `LAST 7 DAYS` / `LAST 30 DAYS`. Fuel writes
  `userDays(month: 28)`. Parse falls back to `.day`.
- **DetailWindow** — surface-specific overrides on the pills: period words,
  `Repository.hydrate` load, debug keys, HEART slot minutes. Hero math stays
  per instrument (ADR 0012). Tick merge for vitals is `VitalsWindowAssembly`.
  `bodyBattery` is a surface of its own (not device `.battery`): 1 / 7 / 30
  user days, `dailyResults` lookback 29, debug `NB_DEBUG_BODY_BATTERY_RANGE`.
- **BodyBatteryWindowMath** — Week/month heroes are the mean of published
  morning peaks (`bbWake`), never a sum. Empty days stay out. `weekRolls`
  cut 30 days as 9 + 7 + 7 + 7. Lime is the page colour (ADR 0017). The ME
  plate sits between identity and COMPOSITION; back from profile is `back()`.
- **Plan face (Paper 04D)** — `Features/Plan/`: `PlanFaceMath` assembles today's catalog
  from the settled night, training load, and meal state. `PlanLip` stacks the chasing
  chevron, the two page dots, then `PLAN` under them. That lane is root chrome:
  it stays put through a horizontal home page turn (only the dots crossfade via
  `pageFade`). Hiding it on `homeDrag == .horizontal` flashed the chevron and
  dots. The chasing chevron is the lip's resting motion: opening then closing
  Plan must not retire it. `hintPlaying` only stops for Reduce Motion.
  Home geometry: `homeIndicatorExtra = max(0, safe.bottom − 19)` drops the lip
  by extra+8 and the dock by extra−4, so PLAN sits over the Home Indicator
  instead of a void, the voice key keeps ~20pt above the chevron, and the
  panel / strip ride down into the room. A home-button phone (extra = 0)
  keeps the old SE packing.
  `PlanPage` is the vertical
  third face. No `/turn` on open. Empty night prints `NO NIGHT YET`. Arithmetic is
  PlanCore-tested. The catalog is five checkable tasks (bed / load /
  strength / meals / afternoon quiet). The face is Paper `04E · 14 BRIEF`:
  a short lime plate with title plus one sentence, then five carbon slabs
  each with a title, a subtitle, and a check. Tapping a task completes it
  one way: lime box with a carbon checkmark, two Core Haptics needles
  150ms apart (no sound, no success-notification tail), then the slab
  leaves. Checks live in `plan.checks.2.` so a test sweep can start clean.
  Done rows stay off the list. REGENERATE sits in a bottom inset, not
  under the last task. No hero score, no WHAT THE AI READ. A complete or
  the footer REGENERATE is an explicit `/turn`. Close rides the catalog's
  own pan. Casting boards on `Hoop Sport` page `4-0` stay as reference.
- **Home FuelCard (Paper 09C)** — `BottomStrip.FuelCard` + `FuelCardMath`. Two numbers
  only: EATEN and the signed delta (`eaten − target`). TO GO is negative, OVER is
  positive, equal is `0 TO GO`. An ember fill is EATEN / TARGET and stops at full.
  Unlogged cannot name a delta. NEXT_MEAL stays off the card. Macros stay three
  independent bars. Arithmetic is SyncCore-tested.
- **Body Battery live preview** — `DataStore` rebases from the server score and applies
  unsynced live sensor minutes; the next settlement always replaces the preview anchor.
- **MealResponseIndex** — Pure SyncCore index: timestamped optical points and recorded sleep
  windows in, signed percent versus own daytime median out. Near is ±8%. Vendor zeros never
  become points. Page two prints RESPONSE; ingest stores `response_samples.optical`.
- **OriginDataSync** — Joins original-data ticks with separate HRV, overnight oxygen, and
  wrist optical meal-response histories. Optical points upload as domain `response` into
  `response_samples` (never a glucose column). Screens print only the unitless RESPONSE index.
- **Active Energy (Paper HY1-0)** — `ActiveEnergyMath` + `ActiveEnergyBoard`. Page-two
  card hero is ACTIVE; day-board hero is OUT. SPORT / STEPS / INCIDENTAL split settled
  active energy. Accumulated OUT is `FuelWindowMath.burnCurve` (same points as the
  calories page, lime instead of cyan). Vendor tick calories stay out. Missing parts
  print ——.
- **Header flame / wear run (ADR 0010)** — `WearRun` scores a worn day from wrist
  evidence in at least half of elapsed 5-minute slots (HR / stress / HRV / steps > 0;
  temperature and vendor calories do not count). `DataStore.wearFlame` previews today
  from local ticks and, when `daily_results.worn` is still nil, yesterday from that
  day's curve. `HomeHeader` must take `flame:` — the default used to leave the mark
  gray forever. Consecutive count is a server-settled daily_results value; migration
  `20260905120000_wear_run.sql` is what persists `worn` / `wear_run` / `wear_miss`.
  Lime + number is a live run, amber is the first closed miss, gray is cold. Not a
  spark (that word is the panel trend), not Daily Direction coverage. Scenario
  lives live in `WearRunScenarioTests`: 08–23 wear lights at 12:00 and holds the
  previous run overnight; 09–20 (11 h) can light an open evening then drop after
  ~02:00 and close amber; 10-minute HR all day is barely worn, 15-minute HR over
  16 h is not. Random stress is 200 × 30 days × 5 clocks. SQL extras in
  `supabase/tests/wear_run/01_scoring.sql`.

## Patterns
- Deep conversational AI interactions navigate to the dedicated full-screen Cyber Telemetry terminal (`/chat`), while the Home display maintains focus on immediate ambient widget metrics.
- Multi-modal chat inputs support staging image attachments (`PhotosPicker`) alongside query text sent to server-side AI turns.
- Plus · Photograph your meal (`拍照记录食物`) is presented by `CameraGate` (UIKit camera on the key window) and auto-sends through `photoMeal`. The keyboard-field camera key still attaches and waits for a caption. Photo library stays pick-then-caption. Long-pressing the dock orb skips the plus sheet and opens that same camera (`sendFood: true`); a tap still opens the sheet. The hold is `PressHold` (UIKit) so it arms under the page drag (ADR-0001).
- Stored historical health values are server-authoritative and reproducible from raw inputs.
- A live UI preview may estimate only the unsynced interval and must rebase on server reload.
- Optional SDK values remain optional; missing and off-wrist are not numeric zero.
- Veepoo accurate sleep stages: 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake.
- Sleep page prints a server-settled night score (ADR 0008) plus staging, night HRV, and
  overnight SpO2. The hero dial colours the score on 40 / 60 / 80 bands and does not
  name the night. Overnight SpO2 lives in `oxygen_samples`. Day-board HRV, SpO2 and
  respiration are `VitalsTrace` occupancy envelopes on the night clock (same
  15-min measured-value capsules as HEART). A slot paints only the value bands
  that have ticks; a hole like 70–75 stays empty. Bedtime vs habit is a Tukey
  box (Q1–Q3 + whiskers + tonight mark), not a scatter of fourteen dots.
- **VitalsDial** — Shared hero on every vitals second-level page (`VitalsDetailChrome`).
  Named zones on a fixed ruler; the occupied zone lights and a white needle marks the
  reading. Arithmetic lives in `VitalsDialMath`. Replaces the old min–now–peak fill rail.
- Page two RESPONSE is the meal-response index, never a blood test: card label RESPONSE,
  tint compare-amber, no mmol/L / glucose / 血糖 / SPIKE on screens, export, or AI frames.
  The detail page reuses the sleep-style DAY/WEEK/MONTH pills (ADR 0012): day is a
  15-minute occupancy envelope, week is seven daily bars, month is a 30-cell heat. Week/month
  hero is the mean of daily means; the own daytime median stays the comparison.
- **ResponseRangeBoard** — `app/NextBody/Features/Vitals/ResponseRangeBoard.swift`.
  Window math lives in `MealResponseIndex.horizonWindow`; chrome is `ResponseDayBars`
  and `ResponseDayHeat`. Debug hook `NB_DEBUG_RESPONSE_RANGE=WEEK|MONTH`.
- **HeartBoard** — `app/NextBody/Features/Vitals/HeartBoard.swift`. HEART second level
  after the zone dial (ADR 0013 / Paper 04K Lead): lead envelope plus HRV and overnight
  SpO2 on the same clock. `DetailWindow` + `HeartWindowMath` are the three rolling windows
  (24h / 7 user days / 30 user days). Week/month hero is the median of daily medians.
  `Repository.loadHeartWindow` pulls only `raw_samples` + `oxygen_samples`. Debug hook
  `NB_DEBUG_HEART_RANGE=WEEK|MONTH`.
- Pure SDK-boundary calculations belong in `NextBodySyncCore` with deterministic XCTest coverage.
- Home calories card (Paper **09C**): `FuelCardMath.readout` is EATEN plus
  `eaten − target`. TO GO / OVER / silent; fill caps at 1. LEFT and NEXT_MEAL
  do not print on the 174 × 136 card.
- Fuel detail (Paper **09H**, ADR 0014) is one `CALORIES` page with `SegmentedPills`
  DAY / WEEK / MONTH. Arithmetic lives in `FuelWindowMath` (SyncCore); boards in
  `FuelBoards.swift`. DAY is the 09E-C clock (IN orange step, OUT cyan burn from
  five-minute steps, NOW, budget) plus one ungrouped food table. WEEK stacks
  IN / OUT / DIFF as 7-day totals. MONTH speaks **a typical day**. `DIFF` is the
  numeric difference (zh 差额); heat-map `GAP` stays 空窗. `LOG A MEAL` is an ember
  state on the food card that opens `FuelPlateLayer` (page clips to `NB.R.panel`
  and scales to 0.88 over black, 34% dim plus a card hairline, plus-menu rise,
  Profile `SheetFrame` /
  `FieldBox` chrome). Debug hooks `NB_DEBUG_FUEL_RANGE`, `NB_DEBUG_FUEL_PLATE=1`.
  **09G** was the prior single-day reading; **09F** is rejected.
- Training detail (Paper **08C** A DIAL, ADR 0015) is one `TRAINING` page with
  `SegmentedPills` DAY / WEEK / MONTH. Arithmetic lives in `TrainingWindowMath`
  (SyncCore); charts in `TrainingCharts.swift`. Windows are 1 / 7 / 30 user days
  (HEART grain, not Fuel's 28). Week/month heroes are finished-day averages on
  the 0–21 scale, never sums. Empty days stay empty. Lime hero
  (`NB.lime1`) is the same on the home training card and the detail
  page; ember stays on Z4–Z5.
  Card order is hero → main chart → ingredients → zones → steps/burn → CTA.
  Debug hook `NB_DEBUG_TRAINING_RANGE=DAY|WEEK|MONTH`.
# Next · OpenMemory Guide

## Overview
- NextBody-Hoop is a portrait iOS SwiftUI application backed by Supabase Edge Functions and Postgres.
- The product has one root (`HomeView`), detail destinations managed by `Router`, full-screen takeovers, and sheets.
- The home AI panel has two states: the idle/STANDBY readout (`widget == nil`) and one personalized `PanelWidget` frame at a time.

## Architecture
- `app/NextBody/App/`: application entry point, root composition, and navigation.
- `app/NextBody/Features/`: SwiftUI feature surfaces. Shared visual primitives live under `Features/Shared`.
- `app/NextBody/Services/`: local state, BLE synchronization, AI requests, and Supabase access.
- `supabase/functions/`: Edge Functions and the AI screen-rendering contract.
- `supabase/migrations/`: database schema changes.
- `docs/prd/` and `docs/adr/`: product laws and architecture decisions.

## User Defined Namespaces
- [Leave blank - user populates]

## Components
- **System widget (Paper THREE TIERS)** — TODAY on `NextBodyLiveActivity`
  ships three families on one carbon, no tile columns: small = body battery
  only; medium = three rings then a rail (`NEXTBODY` white, no lime square,
  plus the home-header band cell); large = that rail on top, rings with
  air between them, then a 3×3 of SLEEP / ACTIVE / HR, STRESS / STEPS /
  DISTANCE, and RESPONSE / HRV / SPO2 (no TEMP). One margin governs the whole
  face — the wordmark, the band cell and the two outer rings all start there,
  and the leftover width becomes the air between the circles. That geometry is
  now shares of the face, not constants: `TodayWidgetFace.margin(for:)` is
  `width * 0.062` clamped to 14…28, `Spacer(minLength:)` is `width * 0.05`
  floored at 14, each circle is capped at `width * share` (medium 0.24, large
  0.225), and the large 3×3 is `height * 0.44`. `edge` (14) survives only as
  the margin floor. Fixed `edge: 14` + `maxDiameter: 96` made the large face
  read crowded — the rings nearly touched both sides. Centring three
  fixed-diameter circles instead left a dead band down both sides while the
  rail hugged the edge. System content margins are off
  (`.contentMarginsDisabled()`), so the large face passes
  `identityRail(topInset: 10)`; at zero inset `NEXTBODY` and the band cell
  read as fused with the squircle's corner. The same rule on the bottom
  edge: medium `identityRail(bottomInset: 6)` keeps a little air under
  the wordmark; the large 3×3 takes `.padding(.bottom, 14)` so RESPONSE /
  HRV / SPO2 do not sit on the floor. Medium rings take `topInset: 16`
  and pin under it — a centred stack put the circles ~8pt from the
  squircle. Large rings stay centred (no topInset).
  Band cell is `WidgetBandPip` (same 12×7 as
  `BandBatteryPip`); it does not withdraw at 90 minutes. A second kind,
  Shot (`NextBodyShot`, small only) is Paper 02 LIME: lime viewfinder,
  lime lens, `LOG A MEAL`. Tap opens `nextbody://log?via=photo` and Home
  fires `openCamera(sendFood: true)`. Gallery name is "Log a meal". App Group
  `group.com.nextbody.hoop` carries the glance (`widget.glance.v1.json`);
  `UserDefaults.standard` is never a fallback for numbers. Shot pending is
  app-process `UserDefaults.standard` only. The widget process does not
  talk BLE. `signedIn` follows Keychain `userId`. Unlogged EATEN stays ——.
- **App Icon** — Shipping mark is the StandbyArt planet: carbon ground, lime-1 charge
  band (gap at top-left), violet-2 tilted orbit, lime stand. Paper `NEXTBODY-HOOP`
  page `APP ICON` holds four icon castings: `20 FACES`, `100 FACES`, `BOLD`
  (floods — rejected as sloppy), and `CASTING · TITLES` under BOLD (12 lockups
  set as mastheads: N+pip, NEXT, BODY, HOOP, MARK, LINE, FOUR, NOW, PIXEL,
  CHARGE, FLAME, NB). Titles use Inter Tight display + Doto machine line.
  User picks by number before any 1024 export.
- **Default avatar** — Home/Profile still render `Avatar` as initials (`Chrome.swift`).
  Paper `NEXTBODY-HOOP` page `APP ICON` holds `DEFAULT · 50 HEADS` (below the
  20-face sheet). First pass was rejected as timid UI glyphs. Current pass is
  signage: cropped posters, lime as paint, 10×5 on smoke-key. Names 01 GRIN
  through 50 DOUBLE. Not a second app icon, not a photo, not initials. User
  picks by number before any bundle asset or Swift change.
- `GateRoute` / `LaunchGate` / `SessionStore.resolveLaunch`: F1 §02 cold start. After a session exists, `devices.unbound_at is null` plus a finished About You (sex / height / birth_date) decide Connect vs Onboarding vs Home. Pairing writes the devices row immediately; Forget writes `unbound_at` and returns to Connect.
- `HomeLaunchPolicy` / `HomeSnapshot` / `Repository.bootstrapHome`: same-day disk snapshot paints Home on the first frame; a still-valid access token skips the grant round trip; today's `daily_results` plus two-day samples load in parallel and replace the snapshot. 182-day history, composition, and BLE origin pull continue in the background.
- `DirectionHeatMap` / `DailyDirectionPolicy`: Profile COMPOSITION is 26×7 Daily Direction
  cells (lime deficit / outline level / red surplus). Colour comes from two logged meal
  slots plus band coverage and live BALANCE — weigh-ins never light a square, and the
  open user day is allowed to colour before 04:00 so the map is not empty until tomorrow.
- **Profile 11C Instrument** — `ProfileView.swift` lands Paper `57U-0`. Three
  `panelWash` plates: identity (NOW + brand name + lime avatar + HEIGHT/WEIGHT/AGE
  rail), composition (YEAR header → today, cells → that day, one-line
  DEFICIT/SURPLUS/LEVEL/GAP legend, 12-week gauges on the same card), measurements
  (recent three + `ALL_MEASUREMENTS` only). Settings rows stay `carbon4`. Page gap
  is 16. Nav trailing is a lime YOU pip. 11D/E/F stay Paper-only.
- **Composition 10E** — `CompositionDetailView.swift` + `CompositionWindowMath.swift`.
  Body fat % is the protagonist. Same DAY / WEEK / MONTH chrome as Battery 12F.
  DAY is this-scan vs last-scan (no chart). WEEK breaks the line on empty days
  and lists every scan. MONTH is a 30-user-day line plus week averages. The page
  reads `DataStore.compositionScans` from every `body_composition` row (device
  BIA, scale, manual). Only persisted fields are drawn.
- `Router`: one-level detail navigation; leaving the root snapshots `homePage`, and every dismiss restores it so page-two vitals return to page two. Destinations include `sportMode`.
- `HomeView`: owns the current optional `PanelWidget`, dock state, and panel callbacks; the pager index lives on `Router.homePage` so NavigationStack push/pop cannot wipe it.
- `AIPanel`: renders STANDBY when no widget exists, THINKING during a request, and a completed personalized widget frame.
- `PanelWidgetView`: renders the server-declared widget envelope on the fixed 358 × 470 panel canvas.
- `Chrome`: shared page geometry and reusable navigation/close controls. `DetailScroll` draws `‹ TITLE` as one control — the board chevron sits on the large title's baseline and docks with it. An invisible 56pt 热区 covers the mark (and the word at rest); Chat's header uses the same cluster. `detailEdgeBack` is a window left-edge pan (`EdgeBackGate`) that offsets the page 1:1 with the finger (40% / 300 pt/s commit, same numbers as 04B). It is not an overlay on the ‹ mark. `NB_DEBUG_ROUTE` stops retrying after the first successful land so a pop stays popped. Regression: `NextBodyUITests/DetailBackTapTests` (tap matrix + swipe commit/cancel).
- `AIService`: sends user turns and decodes rendered widget frames.
- `ASRStreamingSession` + `SpeechCapture`: open the authenticated socket before recording,
  tail complete 16 kHz mono Int16 frames from the live WAV, and retain the WAV as fallback.
- `AIImagePayload` + Chat image turns: compress to ≤ 640 px / 96 KiB soft target, pass the
  request-scoped data URL to `/turn`, then clear the preview and Base64 after recognition.
- `_shared/tool-routing.ts`: conservatively scopes explicit single-domain turns; unclear and
  multi-domain questions keep the full source and renderer catalogue.
- `PlusMenuSheet`: three groups — ADD (`Photograph your meal` / `拍照记录食物` opens the camera and auto-sends; Photo library still attaches), SPORT MODE (`Start a session` → `SportModeView`), MEASURE. Copy follows `AppLanguage`.
- Dock orb: tap opens `PlusMenuSheet`; a 0.45 s hold on the same key calls `openCamera(sendFood: true)` and skips the sheet. VoiceOver exposes `Photograph your meal` as a custom action. Home's first-run skip `TapGesture` is masked with `including: firstRun.playing ? .all : .none` — a parent tap after idle cancels the orb's UIKit `PressHold`, so the sheet never opened. Regression: `NextBodyUITests/DockOrbPlusMenuTests`.
- `DeviceView`: Paper **12X 04 ACTION TILES**. Lime identity slab is HOOP + carbon
  SYNC + 2×2 WORN / WITH YOU / SYNCED / LAST POINT — no 96%, charge bar,
  Not charging, or TREND. Two carbon bricks under it: Find HOOP (PING is the
  only lime word) and Alarms (CLOCK + count after the first read). FIRMWARE
  card unchanged (VERSION + MODEL / HARDWARE / BLUETOOTH / LAST PLUG / LAST
  LINK / SPORT). CONNECTION still has Disconnect / Why won't it connect? /
  Forget; `.findBand` is that help sheet, not find-the-wrist.
  **FIND** is `FindHoopSheet` (`.findHoop`, ≤78%): Paper **12Y 02 LED** faces
  KLF-0 / LFQ-0. Opens READY · LIVE with a giant Doto dBm and START; START
  then ENTER · RINGING and STOP. Top padding is 32pt to clear the bottom
  sheet grab indicator with comfortable breathing room. Four lamps are a stepped lime falloff
  (current = lime-1, one step farther = lime 40%, the rest hairline), not a
  single isolated cell. Cuts: NEAR `> −60`, CLOSE `−70…−60` inclusive
  (−70 is CLOSE), AWAY `−85…< −70` (−85 is AWAY), FAR `< −85`. Never
  V.GOOD / GOOD / MID / POOR. STOP / dismiss is instant (0.12s hold or tap);
  `stopFindHoop` does not wait on `HoopQueue` or the 6s SDK gate, and a
  user-stop Timeout is not painted as LAST. Firmware Timeout is KXX-0
  (ember TIMEOUT + Timed out + frozen RSSI + ember DONE). RSSI reads go
  through `HoopQueue` and freeze on Timeout / dismiss. Ring via
  `veepooSDK_searchDeviceFuntionWithState`.
  **ALARMS** is `AlarmsSheet` (`.bandAlarms`, ≤78%): Paper **12Y 04 SWITCH** (KUV-0).
  Full-width list directly on carbon-4 without cardSkin; top padding 28pt clears
  the grab handle. Huge Doto 28pt clock + week phrase + bespoke 68x40 mechanical
  rocker (`HoopSwitchStyle`, lime on / white-opacity off) only when `repeatState ≠ 0`.
  No hairline above the first clock. Adding is **one capsule key** (`alarms.add`,
  52pt, `Add an alarm` / 新建闹钟): filled lime-1 centred in the face when the HOOP
  has no alarms (`NO ALARMS YET` + one sentence, `NB_DEBUG_EDGE=noalarms` walks it),
  lime-stroke outline pinned to the floor of the sheet under a list. Capacity is
  **never** on the face as `2 / ?` — that was engineering talk and is deleted. A refused
  add learns that count as the cap and flips FULL (one centred ember 20 / 20). Busy writes
  say DEVICE BUSY, not ALARM WRITE FAILED. The rows live in a real `List`
  (`.plain`, clear row background, hairline separator inset 24) so a left swipe gives
  Apple's own red 删除 — the swipe action needs an explicit `.tint(NB.alert2)` or the
  app's lime accent paints destructive the same colour as ON. Editor: eyebrow title
  (`NEW ALARM` / `EDIT ALARM`) with **Cancel top-right**, one lime `SAVE` plate, and a
  plain red `Delete alarm` under it for an existing alarm. There is **no `DONE`** — it
  meant discard while sitting next to SAVE, which read as a second way to agree.
  Week pills are lime stroke, not lime fill — SAVE is the one lime plate. Edit stays on
  the same sheet. New-alarm API mode 0/1/2; scene locked to 0; write failure rolls the
  table back. Demo ceiling 20.
  Band methods: `startFindHoop` / `stopFindHoop` / `readConnectedRSSI` /
  `readAlarms` / `writeAlarm` / `deleteAlarm`. DEBUG `NB_DEBUG_DEVICE_SHEET`
  = `findHoop` | `bandAlarms`. UITest `FindHoopAlarmsTests`. Battery trend
  remains `Destination.battery` from the home pip. SYNC is `pullBandNow`.
  WORN reads `wearFlame`; WITH YOU is `DeviceCompanionMath`. LAST PLUG /
  LAST LINK come from `BatteryLog`. TREND is an entry on the lime slab:
  implemented as Paper **12Z3 12 BRIDGE** (lead corridor). Top line has
  `TREND · 7D DRAIN CURVE` on the left and `3 DAYS LEFT >` on the right (with
  a chevron indicating clickability). The qualifier is one muted caption
  (`7D DRAIN CURVE` / `7日放电曲线`, Jost/Fusion Pixel 600 11pt at carbon-4
  62%) — not a hero 7. Directly beneath it is a 40pt carbon
  lead sparkline (`LimeTrendLead`) tracing 7-day drain points across the lime width,
  ending on a live terminal dot. The corridor does not draw its own floor —
  the lime grid's full-width hairline under TREND is the only rule. The corridor
  is deliberately tall (12pt gap above the line, 18pt below) so the whole strip
  reads as one comfortable tap target, not a thin band. Tapping anywhere in the
  TREND corridor opens `Destination.battery` to view the full curve.
  The LEFT unit is singular at 1 (`DAY LEFT` / `HR LEFT`).
  No separate carbon charge ring on Device.
  100% or 4/4 still on the charger is Charged (`BatteryDrainMath.settle`).
  Automatic measurement still exposes Scientific sleep; Training can still
  open that sheet via `.deviceAutoMonitor`.
- `BatteryLog` / `BatteryDrainMath` / `BatteryTrendView`: local append-only log
  (30 days). A quiet stretch is a dashed drain curve, not a ruler to NOW. A
  first-connect cliff (stale last packet + fresh read in the same two minutes)
  is collapsed; estimated points that land on a heard packet are scrubbed.
  A valued `charge == .unknown` packet is a vendor ghost: `BatteryLog.record`
  refuses it, `collapse` strips it, hydrate rewrites the stored log without it.
  A small EST · FULL / EST · EMPTY clock under the facts is `BatteryDrainMath.eta`
  from a learned slope only — never the five-day pack, never 150 mAh.
  Chinese is `预计 %@ 充满` / `预计 %@ 没电` (never `约`, which reads as 预约).
  The stamp is today / tomorrow / weekday + clock, not a bare time.
  LEFT is the same unplugged slope as hours (< 18) or whole days; silent
  wherever `eta` is silent.
  Reconnect does not stamp `lastBattery` at NOW. Overnight columns and week
  ticks use each night's `sleepStart` → `wakeAt` (same clock as sleep), not
  04:00 and not charge spans. The line takes `VitalsChartProbe` (`battery.probe`).
  Simulator seed is a month of overnight charges plus three closer days ending
  on the live percent. Paper **12F**: no lime hero, DAY / WEEK / MONTH, rolling
  last 24h / 7d / 30d. Doto rail 100/50/0; spec HIGH / LOW / LAST PLUG.
  Default landing is DAY. `NB_DEBUG_BATTERY_RANGE` opens a window in DEBUG.
- `BandBatteryPip`: 12×7 header cell. Charging / full draw a pixel bolt and pulse the
  fill; `BandPresence` stores `chargeState` from battery events so the pip updates
  without opening Device.
- `SportModeView` / `SportModeCatalog`: catalogued modes (raw 0…47); start/stop via `BandService.startSportMode` / `stopSportMode`. Firmware refusals stay greyed for the page life.
- `VitalsTimelinePolicy` + `VitalsDetailView`: sleep uses its recorded night and now also
  draws night HRV, overnight SpO2 and sleep respiration as 15-min occupancy
  envelopes on that same clock (`VitalsTrace`; a column only paints the value
  bands that have ticks, and capsule width follows the slot so a short last
  quarter-hour still sits against the rail). The nav word is the instrument itself (`HEART` / 心率), never
  a `VITALS ·` / `体征 ·` prefix. Page two's retired HRV slot is RESPONSE (`MealResponseIndex`):
  unitless signed percent versus own daytime median, compare-amber, rolling-24h scatter,
  no mmol/L. `vitals.hrv` still deep-links to sleep. Heart now has the same DAY/WEEK/MONTH
  pills as sleep and RESPONSE (ADR 0013): day stays last-24h, week/month are user days,
  companions share the clock. `LiveVitals` NOW for HEART and STRESS is
  `currentHeart` / `currentStress`: the newest tick's own field, else the last
  positive reading inside 24h. A step/MET row must not dash the HEART card.
  Stress and temperature stay rolling 24 hours; steps,
  distance, and active calories use the current 04:00 user day only through now.
  ACTIVE ENERGY (Paper `HY1-0`, ADR 0016) is a lime ledger: home card 174-wide with lived
  hourly bars and `RESTING + ACTIVE = OUT`; the day board is hero OUT + five cards.
  The accumulated OUT polyline is `FuelWindowMath.burnCurve` (same points as Fuel, lime
  not cyan). Split is RESTING / SPORT / STEPS / INCIDENTAL on settled energy — never
  vendor `raw_samples.cal`. Arithmetic lives in `ActiveEnergyMath.swift` (SyncCore) and
  `ActiveEnergyBoard.swift`.
- `VitalsChartProbe` / `VitalsProbeMath`: 探点 on vitals detail chart cards. Arithmetic
  (snap, gap, vacant hour, idle, VoiceOver step, axis lock, `timeSlots`, `envelopes`,
  `occupancyRuns`) lives
  in `VitalsProbeMath` and is covered by `NextBodySleepTests/VitalsProbeMathTests`. The
  shell axis-locks at 10pt: horizontal travel owns the chart, vertical travel stays page
  scroll. The 标线 snaps onto a recorded sample (or names `——` in a gap). Plot field is
  160pt. `fingerFraction` takes both a `leadingInset` (hypnogram gutter) and a
  `trailingInset` (the scale rail), so a touch still maps to the right clock on a chart
  with a rail. Hypnogram clocks come from the night window. Home mini-charts, Fuel,
  Training, Body Battery, and the AI panel are not this shell.
  UI: `NextBodyUITests/VitalsProbeTests`.
- `VitalsDial.Model` is the metric's **zone ruler**, not just the hero's bar: it carries the
  interior `cuts` alongside the zones, so it can colour *any* value and not only the one
  reading the hero prints. `tint(for:)` gives a value's zone colour; `stops(low:high:)` gives
  hard-edged gradient stops for a mark that spans a range; `legendStops` gives the key.
  ⚠️ Charts take this same object rather than a palette of their own — that is what stops a
  capsule coming out red while the dial above it still lights STEADY. Pure segment maths is
  `VitalsDialMath.zoneRuns(low:high:cuts:)`, covered by `NextBodySleepTests/VitalsDialMathTests`.
  Heart zones are Tanaka (60/70/80 % of `hrMax`) → blue1 · lime2 · ember1 · alert2; stress
  25/50/75 → optimal2 · lime1 · ember1 · alert2; skin temp is the personal night range.
- `VitalsScaleRail` + `VitalsChartLegend` (`VitalsDetailChrome.swift`): the shared chart
  skeleton behind 04's envelope-band redesign. ⚠️ Nothing is printed inside the plot —
  the ruler is the rail on the trailing edge, and the peak/band/extreme captions that
  used to sit over the data are a footer legend. `VitalsMetric.chartHasScaleRail` says
  which instruments carry the rail, and `VitalsAxis` is padded by `VitalsScaleRail.gutter`
  so axis clocks stay aligned under the plot rather than under the rail.
- `VitalsTrace` / `VitalsHistogram` / `VitalsClimb` (`VitalsDetailCharts.swift`): the three
  chart bodies on that skeleton. Trace is an occupancy envelope (`VitalsProbeMath.envelopes`
  + `occupancyRuns` over 15-minute slots) drawn as capsules, not a polyline and not a
  min–max fill: a hole such as 70–75 with no sample stays empty. Capsule width follows
  the slot (`VitalsProbeMath.slotBar`) so a night of ~28 quarter-hours fills the window;
  a 7pt cap left a dead strip against the rail. Trace and Histogram both take an optional `zones: VitalsDial.Model`: given one,
  every mark is coloured by the zone it occupies and a mark that crossed a cut carries both
  colours with the edge *on* the cut. ⚠️ A capsule is coloured over its clamped ends, so a
  190 BPM spike on a 40–160 field does not paint its whole visible height in the top zone.
  Heart, stress and temp pass `r.dial`; steps/active pass nil, having no per-hour threshold. Histogram columns are capsule-headed with the radius capped at 6pt — a user day
  a few hours old gives each hour a ~39pt column, where `width / 2` would read as a pill.
  ⚠️ The hour still running is skipped below 40% of a column's width: on a time-proportional
  axis it has no room of its own, and a 2.5pt sliver against the rail reads as an artefact.
  The probe still reports that hour, so no tick is lost.
- `SleepScoreBars` (`SleepRangeBoard.swift`) stands on the same skeleton: a fixed 0–100 rail
  (the one rail in vitals that never rescales), capsule heads capped at 6pt, and the score's
  four colour bands named in a footer legend (`SleepScoreBars.legend`) rather than keyed in
  the field. A night with no record stays a dotted full-height slot.
- `OriginDataSync` + `Repository`: measured band ticks merge into the in-memory curve before
  upload/settlement, while repository reloads query two user days and preserve fresher local
  points. A missing `daily_results` row never gates raw-sample loading. Overnight automatic
  oxygen is a separate SDK history domain (`veepoo-spo2-v1` → `oxygen_samples`), clipped
  to the recorded night — never restored onto `raw_samples.spo2`.

## Patterns
- Female health stays off the product surface. G70 answers the female read with
  `state=None` and `function.female=0`; it is a calendar write (SDK business lock),
  not a sensor, and F1 already spent both second-level pages. Sweep it in DEBUG only.
- Gate branching is `LaunchGate.stage(hasBoundBand:profileComplete:)` — never the last `nb.gate.stage` alone. A finished profile is not asked again after re-pair; a kill mid-About You restores `nb.onboarding.draft.<userId>`.
- Daily Direction on the heat map uses live E_OUT_NOW; `nb.compute_fuel` no longer writes a null direction for an open day. Two snacks in one slot still stay GREY_NOTHING.
- Use design tokens from `NB`; do not introduce hard-coded colors outside `DesignSystem/Tokens.swift`.
- Interactive controls expose at least a 44 × 44 pt hit target even when the visible glyph is smaller. Second-level back is the board's `‹` beside the large title, not a 44pt disc; the left-edge pan lives on the window so it cannot sit on top of that mark (`NextBodyUITests/DetailBackTapTests`).
- Vitals second-level titles are the instrument name (`HEART` / 心率), never `VITALS ·` / `体征 ·`. `DetailScroll` pins the back chevron on the large title's baseline on every detail page.
- User-visible and accessibility defaults are English; explicit Simplified Chinese is selected through app language state (`AppLanguage` + `L()` English-as-key tables in `app/NextBody/L10n/`).
- Adding a language: add an `AppLocale` case and a `L10n/Tables/<code>.json` mapping English source strings to that language. Missing keys fall back to English. The first table is `zh-Hans.json` (~1900 keys). Do not repeat a key — JSON keeps the last value, which is how `NO NIGHT YET` once leaked English over `还没有夜里`.
- The sign-in / pair film line is `Find your next body.` / `找你的下一副身体。`.
  The launch mark is Doto `NEXTBODY` + lime pip, then `BUILD YOUR NEXTBODY` /
  `打造你的下一副身体`. Not PingFang. The only motion is a typewriter
  (28ms per character, same beat as FirstRun): word, pip, second line.
  Ready cuts even mid-type. Sign-in / pair film stays the pixel-fall.
- On-screen metric names follow the language (`BODY BATTERY` → `身体电量`). Units and brands (KCAL, HRV, HOOP, NEXTBODY) may stay Latin. Permission `InfoPlist.strings` follow the phone language, not `AppLanguage`.
- Chinese charge-idle copy is **未充电**, never 未插电. Device page uses `L("Not charging")` → 未充电. Old `Unplugged` / `UNPLUGGED` keys stay mapped to 未充电 so a stale lookup cannot bring 未插电 back.
- Chinese UI/brand type uses Fusion Pixel 12px proportional zh_hans, cascaded behind Doto/Jost/Inter Tight so numbers stay pixel-dot and CJK stays pixel.
- AI turns carry `AppLanguage.serverLocale`. The system prompt, meal vision prompt, and chart slot descriptions are written in the selected language and lock the frame to that language regardless of user input.
- The idle panel is represented by `widget == nil`; THINKING and completed personalized frames are represented by non-nil widgets.
- `StandbyArt` (the planet) lives only on `idlePlate`. `AIPanel` switches idle / occupied / ceremony as one exclusive tree with animations disabled on the swap, so the orbit cannot cross-fade under a reading. Photo answers paint an opaque unlit LED field under the words (`unlitField`); they used to sit on `Color.clear`. The standby charge cluster (`BODY BATTERY` + the 64pt %) sits below the planet's limb (bottom pad 10, vitals 6 above, hint 8 above) so the lime band on the near side does not cross the hero. Do not restore equal 16pt vertical padding.
- Every asynchronous panel request carries a request ID; dismissing or starting another request invalidates late results so they cannot replace STANDBY.
- The panel’s chart layer is drawn behind `HalftoneScreen`, while text remains crisp above it.
- Home horizontal paging owns recognized drags; panel and card taps must not fire at the end of a page swipe. A 探点 on a vitals detail chart card is the same rule on a different axis: horizontal travel owns the chart, vertical travel stays page scroll.
- First-run skip is a root `TapGesture` only while `firstRun.playing`. After idle it is `.none`: SwiftUI's parent tap cancels a child `UIViewRepresentable` (`PressHold`) even when the handler is a no-op. Keyboard still worked because it is a `Button`.
- Push-to-talk ASR streams during recording and commits on release; any stream failure falls
  back to the completed WAV upload instead of losing the utterance.
- AI image bytes are never persisted to Postgres or Storage. `image.inspect` produces an
  ephemeral factual extract for the Thinking turn and the UI distinguishes sending from
  server-confirmed analysis.
- A plus-menu food photo is a camera capture that auto-sends through `photoMeal` with a
  locale prompt; it is not staged in the dock the way a keyboard-field or library photo is.
- A confidently routed turn prefetches its ranked source candidates, harvests the winning
  source into the number ledger, and removes the redundant model read round while Thinking
  remains enabled. Ambiguous turns are not pruned; explicit comparisons among heart rate,
  stress, and steps use the existing `vitals.7d` multi-metric source.
- SDK cannot list supported sports; product shows a fixed catalog and marks refused modes after a failed start.
- Home launch paints the last same-day snapshot immediately, then replaces it with the
  server's current row (target <1 s). A previous user day's snapshot is not today's score.
  Child tables are selected by `result_id in.(…)` so Home is not blocked on every day's
  training curve. Band origin sync still updates the wrist's unsynced minutes afterwards.
- Raw measurements may update the UI immediately, but derived daily metrics remain
  server-authoritative. Merge raw ticks by timestamp and preserve non-nil auxiliary fields.
- Never draw future hours on a current-day chart. A ruler's endpoint, sample filter, and
  hourly-bin geometry must all use the same concrete time range.
- Battery Check: 60 s PPG on the phone clock (never a fake 0.5 fraction), median of
  recent plausible beats (≥3 samples), then real stress (+ HRV try). Lift past 3 s
  grace restarts the heart stream; close cancels stress/HRV/fold-back. The sweep is a
  pulse monitor from BPM — not ECG (F5). Missing HRV/stress stay ——.
- Meals are logged by speaking through the dock. The calories page has no
  `LOG A MEAL` button and never grows an input field. Composition has no
  EDIT THIS DAY. Closed fuel days page back on DAY only (7 user days). Week
  and month are rolling 7 / 28 user days; month is a typical day, never a
  monthly total. Training uses the same three words on 1 / 7 / 30 user days
  (ADR 0015); week/month heroes stay on the 0–21 day scale and never sum.
- Composition 10E (`CompositionDetailView` + `CompositionWindowMath`): body fat %
  is the only plotted series. DAY / WEEK / MONTH share Battery 12F chrome
  (358 / 16 / 14 / hairline / 148pt chart / 28pt Doto rail). DAY never charts —
  this scan vs last scan, five persisted fields. WEEK disconnects empty days
  and lists every scan. MONTH is time-linear over 30 user days plus week
  averages. Numbers come from `body_composition` (all sources) into
  `DataStore.compositionScans`; SDK-only BIA fields that never persist are not
  drawn. Simulator seed maps the same records so the page is walkable offline.

## Verification
- Swift package logic: `cd app && swift test`.
- iOS UI behavior: run the `NextBody` Xcode scheme/UI test target on an available simulator or device.
- Edge Function lint: `pnpm run lint`.
- Edge Function tests: `deno test --node-modules-dir=auto --allow-all supabase/functions`.
