# Next · OpenMemory Guide

## Overview

NextBody-Hoop is a SwiftUI iOS app backed by Supabase Edge Functions and Postgres. The app
captures health data from a HOOP band, renders one AI-controlled panel on Home, and keeps
model credentials and tool execution server-side.
As of 2026-10-15, App AI is available without a Pro subscription: the iOS paywall,
RevenueCat client, billing Edge Functions and `/turn`/`/asr` entitlement checks were
removed locally. Authentication, consent and AI quotas remain. Historical billing
migrations/records are preserved; existing App Store renewals require cancellation
outside the codebase. The physical HOOP shop is not part of this removal.
As of 2026-10-17, App AI is hidden, not deleted. iOS: AI-only code lives in
`app/NextBody/AI/` (Chat, Plan, Memory, Services: AIService, AISession, AIImagePayload,
ASRStreamingSession, SpeechCapture, PhoneTools) behind `App/AIFeature.swift` (`enabled = false`); Home
keeps the panel (standby / morning / measure / sport recap) and a plus-only dock; plus menu
drops the photo rows; Log a meal requires KCAL; Profile drops AI MEMORY; Router drops
`.chat` / `.planFace` / `.aiMemory`. The home-screen Shot widget (Log a meal) is gone;
TODAY is the only WidgetKit face and it only displays the day's numbers.
Server: AI-only shared modules live in `supabase/functions/_shared/ai/`; `turn`, `asr`,
`memory-settle`, `screen-current` answer 410 `AI_DISABLED` unless the secret
`AI_ENABLED=1` (`_shared/ai-switch.ts`). AI tables are untouched. AGENTS.md forbids
opening either AI folder without the owner's permission.

## Architecture

- `app/NextBody/`: SwiftUI application, BLE/band services, local repository, and the AI client.
- `app/NextBody/L10n/`: in-app language (`AppLanguage`) and English-as-key catalogs (`L()` → `Tables/zh-Hans.json`, ~1900 keys). Sign-in / pair film line is `Find your next body.` → `找你的下一副身体。` Launch mark is Doto `NEXTBODY` + lime pip + `Build Your NextBody` → `打造你的下一副身体` (English paints `BUILD YOUR NEXTBODY`). Duplicate keys in the table overwrite; the last value wins. Never reuse `CLOSE` (dismiss → 关闭) or `NEAR` (vitals → 近中位) for Find lamps — those use `Find · very near / nearer / farther / very far` → 特别近 / 较近 / 较远 / 特别远; English still paints NEAR / CLOSE / AWAY / FAR.
- `supabase/functions/`: authenticated Edge Functions for turns, ASR, meals, settlement,
  exports, and account deletion.
- `supabase/functions/_shared/`: model provider, prompt, tool catalogue, data sources,
  render contract, numeric ledger, and thought-stream processing.
- `supabase/migrations/`: Postgres schema, RLS policies, and data lifecycle changes.
- `scripts/everos/`: EverOS Cloud agent memory (`everos-cloud` 1.2.0 in `scripts/everos/.venv`). `EVEROS_API_KEY` lives in gitignored `.env.local`. Calls use `app_id=next`, `project_id=wuzihuang/Next`, default `user_id=wuzihuang`.
- `shopify-web/`: Hydrogen + React Router storefront. Home `/` and `/zh` are a 1:1
  Paper `Hoop-WEB` landing (`MQ-0` EN / `30G-0` 中文): 1440 artboard, live
  layout is full-bleed (`.lp-shell` has no max-width; `--lp-max: none`), ink `#070709`,
  lime `#EFF65A`, Inter Tight / Jost / Doto / Noto Sans SC. Brand is NEXTBODY / HOOP,
  never G Band. Landing stills live in `shopify-web/public/landing/`. Shop
  catalog, cart, and checkout are local (`app/lib/catalog.ts`,
  `app/lib/localShop.server.ts`): one SKU, HOOP $99, finish Black or White
  only. Knit nylon and sport straps both ship in the box — no strap picker
  and no $19 strap SKUs. Product stills are transparent `/kit/hoop-*.png`
  (black-studio cutouts). Session cookie holds
  cart, locale, test account, and test orders. Checkout is a closed test
  (card `4242…`, code `TEST10`); no processor, no charge. Legal / science /
  FAQ / about / contact / journal are local pages. The linked shop
  `pnca9j-07.myshopify.com` is still empty of products. Public storefront
  domain is `nextbody.ai`. Landing CSS has a 1100 / 720 mobile reflow. Phone (≤720): one-row nav
  (mid links + current lang hidden; only the other locale + GET HOOP).
  Live `nextbody.ai` is the Liquid theme `NEXTBODY HOOP` (`shopify-theme/`),
  not Hydrogen. Favicon is the iOS App Icon hoop mark (`favicon-32.png`,
  `favicon-192.png`, `apple-touch-icon.png`, `favicon.ico`) rendered from
  `snippets/favicon.liquid` after `content_for_header`. Hydrogen `root.tsx`
  uses the same PNGs. GET HOOP goes to `/collections/all?product=hoop` — a local
  catalog + cart + test checkout in the theme (`snippets/shop-app.liquid`,
  `assets/shop.js`). Buy box matches App tokens (carbon `#0B0B0D`,
  carbon4 `#101014`, lime `#EFF65A`, Doto price, hairline cards). Color is
  Black or White only; both straps are in the box.   The `.kit-*` buy box sets
  `font-family` on `.shop-app` (otherwise the theme falls back to Times) and
  scopes `.shop-pdp .kit-title` so the landing `.shop-page h1` rule cannot win.
  Shop pages are sized for a 16" laptop first screen: `.shop-page` max-width
  1280 and 20/40 padding; kit grid is `calc(100svh - 176px)` / max 640px;
  title 28 / price 36; long `.kit-body` copy is hidden; shop footer collapses
  to a single link row so nav + kit + footer fit a 1440×900 viewport.
  Cart / checkout / order confirmation / account reuse the kit card language
  (block "Cart / checkout / orders" at the end of both `shop.css` files):
  carbon4 + hairline cards with `--r-card`, 9px 0.2em eyebrow labels, Doto
  prices with the total in lime, 38px ink inputs with lime focus, checkout
  legends floated (`float:left; width:100%`) so they leave the fieldset
  border slot, checkout summary lists lines first (`order:-1`), confirmation
  is a stacked receipt card. Theme `.shop-line` price is `<em>`, orders store
  `variant` + `image` so the receipt shows thumbnails, mini-media uses `<img>`.
  Kit PNGs live in `assets/hoop-*.png`, cut out by
  `scripts/punch-hoop-alpha.py` (the studio shots were composited on `#000`,
  so ring interiors stayed opaque until a connected-component pass lifted
  them). Four renders show a green screen UI and must stay out of the gallery:
  `hoop-black-d4/d5`, `hoop-white-d10/d11`. Filenames also lie about color —
  `black-e7/e9` are white units, `white-b4/c6/c8` are black; judge by median
  luminance, not the name. Shopify Admin still has no products; `/products/hoop`
  404s at the platform and is redirected into that shop view. Hydrogen
  `shopify-web` remains the local/Oxygen storefront.
  Phone landing: stacked 3:4 product shots, highlight cards 1-col with 280px media,
  five phones / faces as peek carousels, coach/plan/stress type and
  padding scaled for 390, composition phone stacked under the wrist.
  Tablet (≤1100) keeps two-row nav and horizontal snap rows. Development-store Oxygen URLs
  require staff login. Old Whoop chrome (`HomeLanding`, `public/band/`)
  remains for Shop routes.
- `docs/STATUS.md`: current implementation and verification record.
- Deploy and device install (verified 2026-10-24). DB: `supabase db push --linked --dry-run`,
  then `--yes`; the CLI is linked to `gkgzwcxivnffsecshvfs` and mints its own login role, no
  password needed. Read-only checks: `supabase db query --linked -f file.sql`.
  `supabase functions list` shows deployed versions. iOS device: `xcodebuild -project
  app/NextBody.xcodeproj -scheme NextBody -configuration Debug -destination 'id=<hardware
  UDID from -showdestinations>' -allowProvisioningUpdates build`, then `xcrun devicectl device
  install app --device <CoreDevice id from devicectl list devices> <.app>`. Use Debug: Release
  entitlements carry `aps-environment=production`, which a development-signed install rejects.
  Both configurations talk to production Supabase. A full app build compiles the AI folders, so
  it needs the owner's go-ahead (AGENTS.md). Android: `. ~/.nb-android-env`, then
  `ANDROID_SERIAL=<serial> ./gradlew :app:installDebug` in `android/`. On a physical phone the
  debug build uses the real band and account; only emulators or debug extras load the seed.
  Release has no signing config.
- `CONTEXT.md` plus `docs/adr/`: domain vocabulary and architectural decisions.
- App Store Connect: NextBody `6799623125` (`com.nextbody.hoop`, SKU `nextbody-hoop-ios`,
  team `BP7F7PYU33`, widget `com.nextbody.hoop.LiveActivity`). TestFlight groups:
  internal `Friend` (`d62d8979-1adc-45e2-85c4-964b58a7c896`) and `Internal Testers`
  (`8598b996-8b7b-4d9c-9f6a-82e6b6df538a`); external `Public`
  (`9e585745-be37-48cb-bf27-a16a79b0dd81`) with public link
  `https://testflight.apple.com/join/x4yW7mJQ`. Latest public build is `1.0` (8)
  (`20e016f7-6475-4a12-adca-5f5e2944aa09`, archived+uploaded 2026-10-21 from the
  live working tree, encryption exempt, beta review `APPROVED`; What to Test
  rewritten for the build — seven-factor sleep, home planet deck, scan-gated
  weigh-in — en-US + zh-Hans). Earlier (7) was pushed to public by mistake on
  the same day: it was a month-old upload, NOT a fresh archive. Release flow:
  `asc builds next-build-number` → `asc xcode version edit --build-number N
  --target NextBody --target... ` (bump BOTH NextBody and NextBodyLiveActivity —
  mismatched CFBundleVersion fails embedded-binary validation) → `asc xcode
  archive --project app/NextBody.xcodeproj --scheme NextBody --configuration
  Release -destination generic/platform=iOS -allowProvisioningUpdates` → `asc
  xcode export` with `.asc/artifacts/NextBody-ExportOptions-*.plist` (method
  app-store-connect, destination export) → `asc builds upload --wait` → `asc
  builds add-groups` to `Public` → `asc testflight review submit --build-id ...
  --confirm` (group add alone does not create the beta review submission) →
  `asc builds test-notes update` per localization. pbxproj commits lag: it held
  version 5 while ASC had 6-7 — always use `next-build-number`, never the
  checked-in number. ASC API flaked 403
  REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED intermittently after a fresh agreement
  signing — retrying over ~1 min works.
  Do not confuse with the older phone bundle
  `com.walnutechnology.nextbody.app`.
- App Store screenshots live on Paper `NEXTBODY-HOOP` page `screenshot` (`S-0`): one
  5-up review board plus five 1290×2796 iPhone 6.7 frames. Screens are cloned from
  `新版设计` (`N-0`), not redrawn. Headlines: SEE LAST NIGHT / KNOW YOUR CHARGE /
  HIT TODAY'S RING / EAT TO THE NUMBER / READ YOUR NIGHT. Ground is lime-1 `#EFF65A`.
  Device chrome uses CSS `zoom: 2.554` so the 390×844 phone fills a 1032-wide bezel.
- Cosmic App Store set lives on Paper `NEXTBODY-HOOP` page `ASC · COSMOS 7` (`p-10-0`):
  seven 1290×2796 frames (APP_IPHONE_67/69), 01 Readiness/Terra → 07 Body Scan. Phones
  show real Home V2 sim captures (iPhone 17 Pro, `NB_DEBUG_HOME_SLOT`, `NB_DEBUG_TAKEOVER=bodyscan`);
  sources and crops in `screenshots/asc-cosmos/raw/`. Paper `update_styles` cannot load
  `paper-asset://` images — swap images with `write_html` replace. Wait ≥2s after
  `simctl terminate` before relaunching, or the screenshot is of the old process.
- Full-app walk-through screenshots (real iPhone 16e sim, English) live on Paper
  `NEXTBODY-HOOP` page `截图` (`T-0`). Shots only — no redraws. Capture uses
  `SIMCTL_CHILD_NB_DEBUG_*` + `/tmp/nextbody-t0-capture.py`. System keyboard
  frames need hardware keyboard off, then `axe tap` on the field. Walk-through
  also pins pairing 100%, fuelDay, chat sending, plus-row press / offline,
  measure fold-back, dock thinking → answer, session fold, camera permission,
  Find HOOP lamps (READY / NEAR / CLOSE / AWAY / FAR / TIMEOUT), live session
  hold / hint / Swim / Yoga plus wrist lines (READING / NO CONTACT / OFFLINE /
  PAUSED / opening / refuse), Training NO TARGET, Home NOT COLLECTING,
  and RESPONSE empty / needs-5-days / SWITCH OFF / ALL ZEROS.
  Later remaining-product strip also pins measure opening, body-scan
  contact / result / fold, weigh-in FROM HEALTH + OUT OF RANGE,
  Body Battery empty day, and Home LAST NIGHT morning widget
  (`NB_DEBUG_MORNING=1`, seed metrics so cloud bootstrap cannot wipe it).
  Empty/disconnect strip pins Device DISCONNECTED, Fuel NOTHING LOGGED /
  FASTED / OUT-unknown, and Profile NO WEIGH-INS YET.
  Product-edges strip pins Composition 0 SCANS, Training SCALE LIMIT /
  AUTO HR IS OFF, Chat long thread + photo attached, Measurements
  NOTHING KEPT YET, Plan NO PLAN YET (`NB_DEBUG_PLAN=empty` without
  generate), Device OTA UPDATING 42 %, Dock TOO SHORT / NOTHING HEARD /
  INTERRUPTED / UPLOAD FAILED, Response SWITCH OFF / ALL ZEROS,
  Profile EXPORT PREPARING…, and Home charging pip 64 %.
  Consent-and-settle strip pins the collect checkbox (amber / unchecked
  Continue vs lime / checked Continue), Device OTA Installed and
  out-of-range fail, Composition first-scan (no previous row), AI Memory
  NOTHING YET, Home 100% charged, and Body Battery confidence card.
  Leftover-product strip pins weigh-in LB (213.8 lb + LB toggle), Device
  NEW ALARM editor (07:30 weekdays), Profile COLLECTING HEALTH DATA OFF,
  Sleep LAST 30 NIGHTS, Sport Mode #33–#47, plus-menu camera row press,
  CAMERA OFF / Open Settings, Chat empty + system keyboard, Health
  weigh-in 173.3 LB, and Body Battery WHY math (four drivers + 64→68).
  WHY/units/Live Activity strip pins the Body Battery WHY 72 card (FROM 46
  AT 04:00), Units LB + FT, Lock Screen Live Activity permission, and the
  allowed Outdoor Run Live Activity (elapsed / 134 BPM / burned).
  Springboard Today strip pins the NextBody icon, the icon-menu size
  picker (App / medium / large), Today medium (BATTERY 68 / LOAD 2.6 /
  SLEEP -- / band 82%), and Today large (three rings plus
  SLEPT/ACTIVE/HR / STRESS/STEPS/DISTANCE / RHR/HRV/SPO2). There is no
  Log a meal widget and no small face — the square was retired.
  Q-0 VOICE / HOLDING / four casting faces are design-only; do not
  clone them.
  Firmware-check strip pins Device VERSION 2.4.1 Up to date, and
  Could not reach the update server (`NB_DEBUG_EDGE=uptodate` /
  `otacheckfail` on MockBand).
  Week-vitals strip pins Stress / Temp / Steps / Distance / Active
  LAST 7 DAYS, measure `noreading` (Couldn't get a clean read /
  NO READING · NOTHING KEPT), and Fuel yesterday (SAT 5 SEP, CLOSED).
  Auto-measurement strip pins firmware switches (HR/SpO2 on, HRV off,
  Stress on), interval empty (DID NOT REPORT), no switches, and
  refuse (THE BAND DID NOT ANSWER). `NB_DEBUG_ROUTE=deviceAutoMonitor`
  plus `NB_DEBUG_DEVICE_SHEET=bandAutoMonitor` after `readAutoMonitoring`.
  Host-shell leftover `SIMCTL_CHILD_NB_DEBUG_SESSION=1` starts a fake
  Outdoor Run on every Home launch — unset it before language / Chinese
  Home shots. `launch()` now also deletes those keys from `os.environ`.
  After a simulator reboot, language sheet pins 简体中文 selected
  (`语言` / yellow dot) and Home paints 准备度 as a 0–100 score with no percent sign.
  Vitals MONTH strip pins Stress / Temp / Steps / Distance / Active
  LAST 30 DAYS (`NB_DEBUG_METRIC_RANGE=MONTH`).
  `NB_DEBUG_SCROLL_TO=bb-why` centres that card. Lock capture is
  `axe button lock` then `home` to wake the lock screen.
  `SheetHost` must present `FindHoopSheet` for `.findHoop` (not `ProfileSheet`'s
  `EmptyView`). Capture batches live in `/tmp/nextbody-t0-capture.py`.

## User Defined Namespaces

- [Leave blank - user populates]

## Components
- **Live sport active-energy repair (2026-10-21)** — `SportMetricAccumulator`
  now subtracts the standard 1-MET resting component (`3.5 × kg / 200` kcal/min)
  from the Keytel gross rate before trapezoidal integration. The four existing
  strength MET estimates are unchanged. The heart-rate model is restricted to
  run/walk/cycle modes (1–4, 7–8, 45), the study's age/weight population
  (18–45 years, 47–120 kg), and a conservative 90–150 BPM operating window.
  These are applicability guardrails, not individually validated accuracy limits
  or a claim that exercise outside them burns nothing. Unsupported intervals
  remain unknown; actual HR is still displayed and retained for training.
  Source: https://pubmed.ncbi.nlm.nih.gov/15966347/ and the paper's discussion
  of the limited linear HR/oxygen-consumption range.
  `LiveSessionStore` uses `SportLiveInfo.receivedAt` for energy, durable evidence,
  and band-start reconstruction. Duplicate/out-of-order reports are ignored;
  pauses and gaps over 15 s still break integration. Joining a pre-existing
  workout does not establish its mode and therefore does not borrow the
  requested mode's estimator. Live/recap copy explains observed-only active
  energy; optional `energyObservedSeconds` persists coverage independently of
  HR-zone coverage, with legacy recaps left intact. Daily server settlement
  and historical recap values are not rewritten by this client repair.
  Focused verification: `python3 app/Tests/diagnostics/sport_energy.py` builds
  real sport/storage sources plus their XCTest suites in a disposable package,
  without reading the restricted AI targets in the main package. Full iOS
  build/device acceptance and deployment remain separate.
- **App/cloud sync stages (2026-10-21)** — `BandSyncProgress.Stage.destination`
  distinguishes App work (yellow `NB.lime1`) from cloud work (blue `NB.blue1`).
  Device button/bar, Home header ring and legacy panel use `workflow.tint`; accessible
  progress names App or cloud. Upload, device registration, capability publication,
  settlement and completion receipts are cloud stages. Backfill can alternate colors
  without resetting progress; only terminal success reaches 100%.
  `SyncProgressStageTests` checks rendered button colors and the current Home ring
  (`home.syncProgress`), not the legacy panel removed from the default Home surface.
  Retained 2026-10-20 device diagnostics showed a 50.46s daily pull: today's BLE/mapping
  2.62s, local persistence 0.012s, upload 10.09s, settlement/reload 11.91s, plus yesterday
  and preparation/receipts. These are historical observations, not a current-device
  benchmark. Diagnostics now separate device metadata, publication wait, settlement,
  reload and receipts; `sync.settlement` is nested within `settlement_and_reload`,
  so do not sum both. Diagnostic recording still follows the existing 48-hour lease.
- **Seven sleep contributors (sleep-v3.0, backend verified live 2026-10-21)** —
  `20261021100000_sleep_seven_contributors.sql` replaces four-group scoring with
  total sleep / efficiency / restfulness / REM / deep / latency / timing,
  nominal weights 40/10/10/15/15/5/5. These are HOOP rules inspired by Oura's public
  definitions, not Oura's proprietary formula (sources and curves in ADR 0008).
  Measured total excludes stages 3/4; REM/deep use 90/60-minute targets; timing uses
  the longest actual segment's local midpoint, not bedtime regularity. Keep v2's
  continuous short-night cap. Efficiency is explicitly recorded-period-only and
  restfulness wake-only; both require complete stage coverage. No real in-bed
  start/latency exists: never substitute SDK firstDeepDuration/fallAsleepScore.
  Latency stays missing; missing factors renormalise. Preserve corrected/reported
  windows and missing-stage evidence, and do not invent naps or zero REM.
  Numeric `inputs.score_*` / `weight_*` plus `contributor_policy=3` carry the contract;
  legacy group columns except duration are null. `SleepContributor` in Metrics
  and the contributor views in SleepRangeBoard render seven tappable rows,
  coverage, cap and version-aware day/week/month breakdowns. Older caches retain
  their four-group explanation. Training target v3 path uses the final sleep score
  (`target-1.1`), not retired columns; legacy target path is unchanged.
  Scoped checks: `python3 app/Tests/diagnostics/sleep_score_explanation.py` compiles
  real model arithmetic and typechecks the four new SwiftUI views against iOS SDK
  and actual design tokens without reading restricted AI folders.
  SQL checks use `inspect-schema.py --test supabase/tests/sleep_contributors.sql`
  plus `sleep_backfill.sql` and `sleep_window_correction.sql`.
  The v2 guardrail suite is historical and runs with
  `--through 20261020160000 --test supabase/tests/sleep_duration_guardrail.sql`.
  Final isolated SQL checks passed 156 assertions across contributors, backfill,
  window correction, training sessions and body-battery target suites. The real
  score loader is also exercised by `sleep_score_lifecycle.py`, including v3
  numeric evidence, null latency, account isolation and offline preservation.
  Cached v3 schedules use `sleep_elapsed_minutes`, not `duration_min`, to recover
  the actual wake clock after excluding awake time from the scored duration.
  Production readback on `gkgzwcxivnffsecshvfs` confirmed the migration was already
  applied and all 98 night scores were v3, with no cap/range/latency violations or
  retired group values; no duplicate deployment was needed. Follow-up UI uses
  spacious white/amber score rows with fixed chevrons, factor explanation sheets,
  and a separate scoring-info sheet. `NB_DEBUG_SLEEP_CONTRIBUTORS=1` seeds only
  simulator UI fixtures; the new interaction test is in SleepScoreEvidenceTests.
  `screenshots/sleep-contributors-preview.png` renders actual components with
  fixture data. Full app build/install and UI-test execution are pending explicit
  compiler-read permission for the protected AI directories; the standalone
  component preview and typechecks did not read those directories.

- **HOOP body scan particles** — `app/NextBody/Features/Measure/HoopFigure.swift`
  draws the screenless side-key device as precomputed Canvas particles; the S1
  ring is 38% of stage width. The finger is the one raster exception: the
  Paper-generated `HoopFinger` imageset (Paper node RMD-0 on artboard RMC-0,
  file NEXT) preprocessed to straight alpha (a = max rgb, rgb un-premultiplied)
  so it composites cleanly over the halo, anchored by the tip pad at the side
  key, masked by a `.destinationIn` axis gradient so the base dissolves before
  the stage edge. A code-drawn tip glow and twinkling
  motes keep the contact reaction procedural.
  `ScanBody.swift` reuses `BodyCloud.shared`'s deterministic Home-body motes,
  cropping only empty margins so the constellation fills the scanning stage.
  `MeasureTakeover` owns the unchanged band stream and state machine, and its
  S1/S2 columns live in `BodyScanLayouts.swift` (`BodyScanPrepareLayout`,
  `BodyScanScanningLayout`, `BodyScanCount`) with shared copy in `BodyScanState`
  — onboarding's `FingersOn`/`ScanningScreen` render the same screens (OnbHeader
  for the takeover header, BASELINE 01/03 in S1 and 02/03 in S2, a skip link in
  the S1 footer until contact), so the first scan is the same UI as a re-scan.
  ⚠️ ScanningScreen's mutable state lives in `OnbScanModel` (ObservableObject,
  @StateObject) — writes from detached tasks must reach the rendered object —
  and its prepare/scanning layouts sit side-by-side in a ZStack keyed by
  `.id("\(status)|\(failed)|\(dropped)")`: a plain `if`/`Group` between the two
  generic layouts pinned the screen to its first frame (evals ran, pixels froze).
  `HomeBodyPage` exposes the
  scan entry only when body composition is not known unsupported; its figure
  reserves 42 pt for the hidden entry only at rest. The result's composition
  link dismisses the takeover before opening that scan's detail, and S3 splits
  its flexible space 1:3 above and below the reading.
- **Sleep score duration guardrail (sleep-v2.0, local 2026-10-20)** —
  `20261020160000_sleep_duration_limits_score.sql` changes the four nominal weights
  to duration / structure / recovery / regularity = 50 / 20 / 20 / 10, then caps the
  weighted score by recorded duration: 4h → 40, 5h → 60, 6h → 75, 7h → 90,
  7.5h → 100, with continuous interpolation. Missing groups still renormalise;
  existing input evidence, stage handling, personal baselines and duration scoring
  stay unchanged. The migration rebuilds all night scores and queues dependent
  daily settlement through `nb.invalidate_calculation`. It does not replace the
  shared settlement functions. `SleepRangeBoard` reads per-night weights and cap
  evidence from `inputs`, explains a binding cap, and retains legacy weights for
  old cached results. Checks: `supabase/tests/sleep_duration_guardrail.sql` through
  `supabase/scripts/inspect-schema.py`; `python3 app/Tests/diagnostics/sleep_score_explanation.py`
  compiles the real score model/explanation without entering the restricted AI
  folders. These changes are not a deployment or a change to sleep detection.
- **MCP for outside AI assistants (ADR 0032)** — `supabase/functions/mcp/`
  (`server.ts` stateless Streamable HTTP JSON-RPC, `tools.ts` read tools +
  `log_meal`/`delete_meal`). Auth = Supabase Auth OAuth 2.1 server
  (DCR + PKCE); tokens are normal Supabase JWTs plus `client_id`. Migration
  `20261018100000_ai_assistants_reach_their_owner.sql`: `mcp_grants`
  (can_write default false), first-party RPCs `record_mcp_grant` /
  `set_mcp_grant_write` / `revoke_mcp_grant`, OAuth-only `touch_mcp_grant`,
  PostgREST pre-request `mcp_request_gate` (8 read tables + few RPCs; write RPCs
  need can_write), storage restrictive policy, budget endpoint `mcp` 60/min.
  `_shared/db.ts` `currentUserId` rejects tokens with `client_id`;
  `assistantCaller` accepts only them. pgTAP `supabase/tests/mcp_request_gate.sql`.
  `mcp-web/` = Cloudflare Pages at `mcp.nextbody.ai` (consent page,
  `.well-known` metadata, `/mcp` proxy). iOS `Features/Profile/AssistantsSheet.swift`
  (Profile › DATA & LEGAL › AI ASSISTANTS; route `.assistants`; Supabase.swift
  `oauthGrants` / `revokeOAuthGrant`). Disconnect = GoTrue DELETE grant first,
  then `revoke_mcp_grant`. GoTrue discovery lives at
  `/auth/v1/.well-known/oauth-authorization-server`; grants list shape
  `[{client:{id,name}, scopes, granted_at}]`.
  Local 2026-10-21 hardening (not deployed): `health.ts` adds daytime vitals and
  scan fields, bringing `list_metrics` to 35 metrics. `read_health_records` pages
  11 fixed health collections; `get_health_profile` uses a narrow invoker RPC,
  not unrestricted access to profiles or its relationships. The migration
  `20261021120000_mcp_health_access_and_meal_receipts.sql` extends only the
  health-read gate and introduces `log_mcp_meal` with private
  `mcp_meal_requests` receipts keyed by owner/client/request UUID. The first
  transaction fixes default time, local day, slot and source; identical retries
  return that receipt even after timezone/day changes. Changed payloads conflict,
  never invite a new ID. Write grants and consent are checked on replay too.
  `request_id` is mandatory at the MCP tool boundary. A saved meal is separate
  from settlement: `dayTotalsUpdated` requires non-busy settlement plus an
  explicit non-pending `calculation_status` row for that day.
  Meal lists and health records return `nextOffset`; absent values remain null.
  Overnight oxygen now queries the actual sleep windows, including the evening
  before the wake day; no sleep window means no claimed overnight readings.
  Profile DATA & LEGAL and `HomeMCPGuide` both open assistant management. The
  copy guide has six localized sections covering OAuth, tool discovery, local
  dates, units, permission, confirmation, retries and error recovery; the server
  initialization instructions and consent page describe the expanded surface.
  Scoped checks: Deno `mcp/index.test.ts` and `metric-read/index.test.ts`,
  `pnpm test && pnpm typecheck` in `mcp-web`, SQL `mcp_meal_retries.sql`,
  `mcp_health_isolation.sql` and `mcp_request_gate.sql` via `inspect-schema.py`,
  and iOS `MCPConnectionTests`. Cloudflare 1010 for Python's default user agent
  is an external blocker; the available Wrangler OAuth scopes lack WAF/rules
  write access. Do not disable whole-site protection or claim token-renewal
  acceptance without an actual authorized OAuth lifecycle test.
- **Shopify Paper landing** — `shopify-web/app/components/landing/` +
  `app/lib/landing.ts` + `app/styles/landing.css`. `/` English, `/zh` Chinese
  (default English). `PageLayout` hides old Header/Footer on those routes.
  Twelve sections from Paper `MQ-0` / `30G-0`: 72px nav, 820 hero, THE OBJECT
  gallery (buckle / weave / dashed sensor), highlights `#F5F5F7` 6 cards
  (last card is AI DISPLAY: spoken query + lime night-dot grid, not Home /
  lock screen),
  five-phone app, three-core radar, composition wrist + baseline phone
  (`LandingCompositionPhone`), stress, 9 generated faces (`LandingFaces` from
  Paper JSX), AI coach well, next body / chase, two finishes `$99`, twelve
  signals, YOUR MOVE close. Claims: no ECG, not medical, 18+, `$99` once, no
  subscription, 5 days a charge, black or white. Get HOOP CTA `/products/hoop`.
  Shop chrome (header/footer/cart) uses landing tokens on every non-landing
  route. Deploy is Hydrogen → Oxygen after `shopify hydrogen link`.
- **Local shop loop** — `shopify-web/app/lib/shopMath.ts` + `shopCopy.ts` +
  `policies.ts` + `sitePages.ts` + `app/components/shop/*` + `app/styles/shop.css`.
  Add to cart, aside/page cart, test checkout, order confirmation, account
  with session orders. EN/ZH from session (`/` sets en, `/zh` sets zh).
  `npm run test:shop` covers totals, TEST10, and test-card helpers.
- **App screens as web components** — `shopify-web/app/components/AppScreens.tsx` +
  `app/styles/app-screens.css`. Home, Vitals, Body Battery, Sleep, Training, Fuel,
  Plan, and Chat drawn in NextBody's own carbon/lime/Doto language, scaled with `em`
  so they sit in a marketing grid. The panel is the only place the product speaks.
- **Packaging insert (说明书)** — Paper `NEXTBODY-HOOP` page `说明书` (`R-0`), eight
  1400×1800 pages (cover → parts → charge → first use → lamps → reads → care →
  FAQ). Hardware is G70 (`~/Downloads/G70资料` 白底图): curved metal *frame* with
  two raised bars, honeycomb face (strap material shows through), lamp-hole
  column, pill side key with pulse mark + pinhole, strap through the frame
  (silicone hex pin-tuck or nylon ring). Back: two electrode bars, optical
  window, two charge pins. Charge drawing is a magnetic *clip* on those pins
  (no official dock photo in G70资料). Never draw a finger ring or a round
  watch. Bilingual copy. App law: no ECG, overnight oxygen only, not medical,
  18+, name is NextBody never G Band.
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
- **ME card composition week grid (2026-10-20)** — Profile's `COMPOSITION · 26 W` card
  paints one cell per user week, not one per day, and never from eating: each week's
  latest `body_composition` scan is compared against the nearest earlier scanned week,
  classified by the training goal into `aligned` (lime) / `held` (outline, in-band or
  first anchor) / `drift` (amber) / `noScan` (dark) via `CompositionWindowMath.weekCells`
  + `classify` (F2 §05 bands restated as `weekFatBand`/`weekLeanBand`; `CompositionAim`
  mirrors `Goal` because `Goal` is app-module only). Replaces `DirectionHeatMap` /
  `DirectionLegend` / `DirectionCell` and `MetricNames.deficit/level/surplus`;
  `DailyDirection`/`DailyDirectionPolicy`/`daily_direction` stay as the server contract.
  Legend chips: ALIGNED / HELD / DRIFT / NO SCAN. Tests: `CompositionWindowMathTests`
  `testWeekCells*` + `testClassifyFollowsTheAim`.
- **Number ledger** — `_shared/ledger.ts` rejects frame numbers that did not come from a tool.
- **App language** — `AppLanguage` stores `en` / `zh-Hans` (default English). `L("English source")` looks up the current table. The system prompt language-locks AI frames to the selected locale.
- **Detail-page chrome** — `Chrome.swift` (2026-10-22, learned from Oura's detail
  pages, refs in `~/Downloads/OURA`): a pinned header = 52pt bar (40pt glass back
  disc on the left, 44pt hit; title centred, brand 16) + a centred 36pt context
  row (Oura's date-pager slot) that shows eyebrow / headline / `trailing` only
  when one exists. A tinted linear gradient (glow 0.22 → 0.08 → 0 over 460pt)
  is anchored at the screen top behind the scroll; the header ground is an
  opaque strip of the same gradient, `ScreenMetrics.safeArea.top + headerHeight`
  tall and top-aligned (a centred or unclipped 460pt slice covers the pills and
  hero — that bug happened), with a hairline fading in over 24pt of scroll.
  Init signatures are unchanged because AI-folder code calls DetailScroll.
  `ScrollOffsetWatcher` / `DetailOffsetKey` (iOS 18
  scroll geometry, iOS 17 preference fallback) are shared: 12 · ME keeps its
  own `‹ ME · YOU` bar and bleeds the identity's lime bloom into the status
  bar the same way instead of a solid carbon slab.
  Back is one custom move everywhere: `detailEdgeBack` (window-level pan, ≤32pt
  edge) slides the page right over `router.returnBackdrop` (a window
  `snapshotView` taken at push), then pops with animations disabled. iOS 26's
  system pop is kept out — it plays a card pop where the page underneath
  scales back up ("放大一下"): `interactivePopGestureRecognizer` is disabled in
  `EdgeBackGate`, and every ‹ key calls the host's `slideOff` through the
  `detailBackSlide` environment value. The env read must live on a child view
  (DetailBackButton / ProfileBackKey) — the value is injected inside the
  page's own body, so a `@Environment` on the page itself always sees nil.

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
- Voice meal logs are two hops, not one: `/asr` then `/turn`. On release the
  client races the realtime socket against the WAV/`qwen3-asr-flash` upload —
  first usable transcript wins; it no longer waits 8 s then uploads. The
  stream is cut only after `ASR_STALL_MS` (20 s) of silence, not a 5 s / 70 s
  wall clock, and flash has no 22 s HTTP cap. A Chat fallback reading
  「这次回复没有完成，请稍后重试。」 is `/turn` after `meal.estimate` with no
  render — same path for typed Chat. After a finished estimate the server
  publishes `foodDraftEnvelope` immediately and still renders that plate if
  the next model/stream dies. Chat is detached like advice. There is no
  120 s / 60 s turn or model wall clock; SSE heartbeat 8 s and lease renew
  every 30 s keep a thinking model alive. Meal web search stays a 4 s bonus.
  Client SSE/upload idle gap is 120 s. Chat keeps a food `fallback_frame`.
- Simulator seed is compile-time `Band.allowsSeed` (`#if targetEnvironment(simulator)`).
  Mock never replaces cloud home rows (`Repository.bootstrapHome` returns after
  `openSession`), never flushes meals / weigh-ins / profiles / sport HR
  (`saveProfile`, `addWeighIn`, `MealQueue`, `SportEvidenceQueue`,
  `flushPendingEvidence`). `NB_DEBUG_EDGE=restonly` is DEBUG+simulator only.
  `seedToday()` and vitals boards share `VitalsClock.now` so `NB_DEBUG_NOW`
  includes the 18:00 session ticks (overnight `Date()` has no activity MET).
- Activity hour bars (`ActiveEnergyMath.hourly` + `LivedHourBars`) are activity
  only: `kcal==0` draws nothing; rest-only days stay blank. Fuel AI plates
  commit `items[]` without confirmation (`foodDraftEnvelope` already logged,
  action `OPEN FUEL`). Edit-meal plate `rise` is 0; the sheet pads internally
  so the keyboard cannot pin the handle to the top. Sport recap
  (`SportRecapMath`) is local; simulator `applySeedSessionLoad` bumps load;
  mock HR never hits `ingest_sport_heart_rate`.

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
- **BodyBatteryEngine** — Deterministic reference for readiness-1.0, not a phone-side publisher.
  Sleep still approaches 95. Quiet rest approaches the morning score, capped at 90.
  Light daily movement (HRR < 0.30, MET < 2, no session) costs 0. Awake fatigue is 0.02
  per five minutes for the first 10 hours after a night of at least 6.5h, and 0 during
  sustained quiet rest. Server settlement is `nb.compute_reserve` at `readiness-1.0`;
  training composition is `target-1.3` (see Training target composition). Tables stay `reserve_*`.
- **Training target composition (target-1.3, 2026-10-24, production)** — migration
  `20261024100000_training_does_not_lower_its_own_target.sql`. `nb.training_target` reads
  fatigue = readiness + movement cost (replay `d_active`) since the final wake bucket; falls
  follow the latest row, rises the 15-minute average. Pure `nb.compose_training_target(base,
  morning, fatigue)`: weight 0 while fatigue ≥ 60 and within 8 of morning, ramps to 1 over 5
  points past either; target = base − w·max(0, base − C(fatigue)). Base short-night guard is
  8 at ≤4h rising linearly to 16 at 7.5h (was a 6h step). Evidence adds `fatigue_reserve`,
  `movement_cost`, `limit_weight`. Fixed: a followed zone-3 run cut 14.6 → 12.8 and showed
  "over target"; readiness 60 → 59 moved 14.2 → 11.4; 5h59 → 6h00 jumped 11.0 → 13.2.
  HR strain kept during exercise still counts (~0.4 / 10 min zone 3). iOS
  `TrainingTargetEvidence.hasReserveLimit` accepts any `target-1.1`+ (was an exact
  whitelist, so new versions hid BASE TARGET / REMAINING); Android `TrainingSettlement.kt`
  got the same fix (`TrainingSettlementTest`). Tests:
  `supabase/tests/training_target_composition.sql`; Swift via
  `python3 app/Tests/diagnostics/training_settlement.py` (disposable package; the main
  package compiles AI targets). Pre-existing HEAD failures, unrelated: `body_battery_adaptive` #18,
  `reserve_and_load_calibration` #1/#4/#5 (readiness-1.0 recalibration), `operation_receipts`.
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
- **Fuel TARGET (ADR 0025 / fuel-2.0)** — one server number, `day_fuel.target_in`.
  `TARGET = full-day resting + activity so far + goal offset` (CUT −500 /
  RECOMP −380 / BULK +300), never under 1500 male / 1200 female, then P/F/C
  rewrite. Resting is the latest `device_bia` `bmr_kcal` (`BODY_SCAN`), else
  Mifflin. OUT is the *prorated* resting + the same activity, so the cyan burn
  sits below the white budget until the day closes. 2026-09-14 owner row:
  scan 2229 + active 436 + BULK +300 = **2965**; OUT ~2597→2609. Winter lean /
  cut intent is TDEE − 500 (eat ~2100 on a 2600 day), not a Strength/BULK
  surplus. Goal sheet copy is the trap: BULK paints as Strength / 力量
  (“Lean mass first”), CUT as Endurance / 耐力.
- **Body Battery live preview** — `DataStore` rebases from the server score and applies
  unsynced live sensor minutes; the next settlement always replaces the preview anchor.
- **MealResponseIndex** — Pure SyncCore index: timestamped optical points and recorded sleep
  windows in, signed percent versus own daytime median out. Near is ±8%. Vendor zeros never
  become points. Ingest stores `response_samples.optical`. The RESPONSE board
  remains at `vitals.response`; page two's slot is Body Battery.
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
- Page two's retired RESPONSE slot is Body Battery (`Destination.bodyBattery`): lime
  reserve score, compact `BatteryCurve`, tap opens the same 13 page as Profile and
  the morning widget. RESPONSE is no longer a page-two card; `vitals.response` still
  opens the meal-response board. That board is never a blood test: no mmol/L /
  glucose / 血糖 / SPIKE on screens, export, or AI frames. It reuses the sleep-style
  DAY/WEEK/MONTH pills (ADR 0012): day is a 15-minute occupancy envelope, week is
  seven daily bars, month is a 30-cell heat. Week/month hero is the mean of daily
  means; the own daytime median stays the comparison.
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
  do not print on the 174 × 136 card. `FuelCardMath.eaten` is the header
  rule: confirmed plates win over a stale `day_fuel.kcal_in` of 0 / UNLOGGED
  (meal insert only dirties the day; settle can lag). Empty plates keep the
  server header so a failed meal fetch does not blank a settled number.
  `Repository.load` calls `DataStore.refreshIntakeFromMeals` after merge.
- Fuel detail (Paper **09H**, ADR 0014) is one `CALORIES` page with `SegmentedPills`
  DAY / WEEK / MONTH. Arithmetic lives in `FuelWindowMath` (SyncCore); boards in
  `FuelBoards.swift`. DAY is the 09E-C clock (IN orange step, OUT cyan burn from
  five-minute steps, NOW, budget) plus one ungrouped food table. WEEK stacks
  IN / OUT / DIFF as 7-day totals. MONTH speaks **a typical day**. `DIFF` is the
  numeric difference (zh 差额); heat-map `GAP` stays 空窗. `LOG A MEAL` is an ember
  state on the food card that opens `FuelPlateLayer` (page clips to `NB.R.panel`
  and scales to 0.88 over black, 34% dim plus a card hairline, plus-menu rise,
  Profile `SheetFrame` /
  `FieldBox` chrome). Tapping a FOOD row opens `EditMealSheet`: name, kcal, protein /
  carb / fat, slot chips, and `Eaten at` (`TimeFieldBox`). Save writes those macros
  plus `logged_at` through `amendMeal` / `meal-operation`; the clock is pinned to the
  same user day (`UserDay.pinningClock`, 04:00 → 03:59+1). Debug hooks
  `NB_DEBUG_FUEL_RANGE`, `NB_DEBUG_FUEL_PLATE=1`.
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
- Agent memory: MCP `everos` (EverOS Cloud via `uvx everos-mcp`) sits alongside NAS `mem0`/`openviking`; scope `EVEROS_USER_ID=wuzihuang`, `EVEROS_PROJECT_ID=Next`. Config lives in user-level `~/.cursor/mcp.json` and `~/.config/devin/mcp_config.json` — the API key never enters the repo.

## User Defined Namespaces
- [Leave blank - user populates]

## Components
- **Idle planet field** — Daily Home idle draws `IdlePlateArt` (Paper V-1
  `星球显示屏`, 358×470 recipes + atmosphere) through `StandbyArt`. Pose is
  `IdlePlateMotion` (8s seamless revolution — moons / pips ride closed
  ellipses via `around()` + `pose.satellite`; far half occults behind the
  disc. Visible-arc shepherds use `alongArc()` / `svgArcPoint()` so plate 21
  never ducks behind the giant.   Soft filled discs (08/09) keep a night-ramped `sphere` — `hazeOrb` is
  only a highlight wash, not the body. Plates 02 / 20 use two `softBall()`
  layers (center fill + offset highlight) that dissolve to clear so the
  Paper screenshot reads as a glow moon + right crescent, not a flashlight
  or a hard 3D cut-out. `featherRim` dissolves a hard disc into `#070709` (09/15)
  (`pad` must stay ≤ 1.0). Plate 02 must not get an extra ink fill or
  a second `haloRing` over the disc. `mist()` fades by ~48% radius for
  horizon / low blooms (16/25). Plate 16 keeps the cyan horizon mist and
  also rides a high-sky moon on `orbitGuide` so the board reads as a
  turning world (Paper JSX had no pip). Plate 28 foreground rings stay
  at Paper 90/50/28. `paperOvals` are radial bowls, not hard black discs; 23
  lips stay typed `PaperLip` but stay off the V-1 paint so pits do not read
  as water drops; ovals are solid Paper ellipse fills. `filmGrain` hashes
  the Paper plate overlay after `look()`. No glow-breathe fake.
  Reduce Motion holds the Paper rest seat). Day
  pick is `IdlePlateLock` + `IdlePlateStore`. FirstRun still uses `OrbitField`
  and must stay frozen. Release is one plate per user-day. DEBUG walks
  `IdlePlateLock.advanceVisit` (01…28) once per app foreground so every
  look can be judged; `IdlePlateStore` keeps the visit cursor off the
  daily snapshot. Pin with `NB_DEBUG_PLATE=1…28`; restore the playbook
  with `NB_DEBUG_PLATE_DAILY=1`. Saturn plates spin `pose.ringDeg` one
  closed turn per loop (Paper rest at t=0); `ansaGlow` rides the ring.
  Plate 02 is a moon in the field (r≈92, dust ring, shepherd) — not a
  320px balloon. Shepherds without a Paper dashed path get `orbitGuide`
  (the closed ellipse `ride` traces) so a moon reads as orbit, not a
  blink. Plate 19/28 keep authored ring seats so SVG arcs and
  edge-on rings do not tumble. Geometry source of
  truth is the Paper artboard (e.g. plate 01 ball 164 at 97/106, rings −14°,
  moon 7×7 at 286/214; 03 ice 156 at 101/50 −3°; 05 umber 136 at 111/110 −22°
  + moon 88/108; 06 dashed orbits around 150 at 105/120; 07 blue-gray 144 at
  107/106 −24°; 08 is a 90px warm ball at 95/145 plus a wide diagonal band
  (no rings); 09 is a 150px cool ball at 104/115 plus a fading diagonal;
  10 is a dashed blue diagonal; the (14, 94) star rides `around()` so it
  travels the trail instead of sitting still; 11 is an
  860px right-limb with diagonal lines and no rings; 12 silhouette 170 at
  94/103; 13 is a bright diagonal plus dashed 210×110 ellipse at −32° (no
  moon); 14 is a 56px dim ball at 151/167, dashed r=62 circle, fade line;
  16 is a bottom cyan bloom + far circles + left dashed crescent; 17 is a
  violet bloom + 128×96 ellipse at 18° + pip (294, 210); 18 is two magenta
  blooms + rings at (200, 210) + pip (106, 264); 19 is a 150px ivory ball
  at 105/125 with a thin −13° ring and three color ticks; 20 blue 184 at
  206/103 + far arcs; 21 left giant 404 at −262/38 + pip 223/218; 22 ivory
  136 at 111/118 −2°; 24 is a cyan cubic trail whose head rides
  `pose.comet` along `plate24Point`;
  25 low amber bloom 240×130 at 59/248 + inner 100×40 at 129/278 + arc
  `M 244 410 A 64 15 −4`; 26 violet 160 at 170/150 left-lit; 27 dashed
  arcs `1.2 8` / `1.6 7` + pip 150/138), not the old LED OrbitField.
  Plate 02/23 craters are Paper mares/pits with radial bowls (no hard
  discs). Plate 23 keeps the 600px close-up; its sky pip rides a tight
  top-strip ellipse (rest 300/42 around 179/38) so it never leaves the
  board. 23 paints Paper SVG elliptical pits plus typed `PaperLip`
  elliptical-arc strokes (cream `0xFFFAF0`, not circular bowl rims)
  and the Paper bottom fade 30%→85%. `discWash` is the 142° night
  overlay on 02/08/23. Plate 02 also
  paints a 440px `haloRing` (stops 70/77/86/100) and a Paper night
  ramp — do not flatten it to a mid-gray balloon. Sphere specular is
  `specA` (plate 15 keeps it near 0); `limbA` 0 drops the default 1px
  white rim (02/08/09/11/16/21). `bloom()` fades by 70% radius so a
  large ellipse stays haze (16/17), not a hard disc. `paperBlurLine`
  is the Paper-blurred stroke (08: 94/58/30 at 6/10/16%; 13: 42/14
  at 16/28% plus a 2.4px 90% core) — do not stroke those widths as
  hard `paperLine` (that reads as a gray road). DEBUG `NB_DUMP_PLATES=1`
  plus `NB_DUMP_PLATE` / `NB_DUMP_CLOCK` (via `SIMCTL_CHILD_*`) holds
  one 358×470 still on the real window for `simctl io screenshot`.
  Crop the iPhone 17 Pro Max 1320×2868 capture at x=123 y=729 w=1074
  h=1410.
- **Notification reach** — ASC App ID `com.nextbody.hoop` (`MBK78HK26T`)
  has `PUSH_NOTIFICATIONS`. Debug entitlements use `aps-environment`
  development; Release uses `production`. `NotificationPrimer` (F5 C4)
  is still the only path to the system dialog. After Turn on, the app
  registers for remote notifications and stores the hex token in
  `push_tokens`. Product law is ADR 0019: fire on data edges, not
  clocks; lock screen + in-app banners; 4 delivered / 用户日; one kind
  once; band battery beats band away. Math is `NotificationReachMath`
  (`decide` / `swallows` / `awayFireAt`, SyncCore). iOS adapter is
  `NotificationReach`: snapshot from `DataStore` + BLE + meals, local
  `UNNotificationRequest`, harvest delivered, `willPresent` banners
  unless the target page is open (`daily` never swallows on Home).
  Disconnect clock starts in `recordBandLink(false)` (`nb.notif.disconnectAt`).
  Settings: Morning / Training / Meals / Daily wrap / Energy / Band /
  Quiet (all default on). Primer: “HOOP taps you when something
  changes.” Deep links include `nextbody://training` and bare
  `nextbody://home`. `NB_DEBUG_NOTIFY=1` still fires a 3s test. Cloud
  APNs Auth Key (p8) cannot be minted by the ASC API. Plan:
  `docs/plans/2026-09-06-notification-reach-plan.md`.
- **Background pull (ADR 0026)** — `Services/BackgroundRefresh.swift` owns one
  `BGAppRefreshTask` (`BackgroundRefreshPolicy.taskIdentifier` =
  `com.nextbody.hoop.refresh`; Info.plist has `fetch` + `BGTaskSchedulerPermittedIdentifiers`;
  registered in `AppDelegate.didFinishLaunching`). Scheduled on every
  `didEnterBackground` and after every run, only when
  `WidgetCenter.getCurrentConfigurations` shows ≥1 of our widgets, a session is on
  the phone and a band is bound; `earliestBeginDate` is the last `store.lastSync` +
  30 min (never in the past).   A run: `Repository.openSession` →
  `OriginDataSync.refreshNow(.background)` (floor `min(300, cadence)`, no live-receipt
  reuse) → `flushPendingEvidence` (settle today + reload even when the band was out of
  reach) → `WidgetGlancePublisher.publish` + `HomeSnapshot.save` → reschedule.
  As of 2026-10-17 the pull is tiered (`docs/plans/2026-10-17-fast-band-sync.md`):
  `.background` and the Home 30 s `.foreground` timer are light (today only, yesterday
  before 04:00 or when unconfirmed, no week audit, sleep scores for 2 days). `.resume`,
  `.automatic` and `.phoneTool` are daily (today then yesterday, repair missing days only).
  `.fullHistory`, consent and the first pull (`lastSync == nil` on a daily request) stay
  full. Today is settled and, in the background task, written to the glance before yesterday.
  HRV, oxygen and temperature dumps are reused for 30 minutes on the same link unless the
  tier is full or that night is unconfirmed; a skipped domain keeps its old acknowledgement.
  The origin dump still runs every refresh. BLE reading no longer waits for the previous
  upload; the upload is awaited before this refresh publishes. Expiration records
  `background.expired` with the current stage and cancels the Task; `BackgroundTaskCompletion`
  locks `setTaskCompleted` to once. The glance is also written when today finishes, so a
  later cancel can still leave today's number on the widget. Returning to the app uses
  `BandRefreshRequest.resume` (floor `min(60, cadence)`, reuses the live receipt) so the
  device-page cadence no longer throttles a foreground entry. Body Battery
  "empty" = server `observed_at` (last observed tick + 5 min) older than
  `BodyBatteryReadoutPolicy.goneAfter` (6 h) or no `reserve_daily` row yet; the phone
  never computes the reserve. Pure rules in `Services/Band/BackgroundRefreshPolicy.swift`
  (in the `NextBodySyncCore` package; tests `BackgroundRefreshPolicyTests`).
  Silent push is not an option until the APNs `.p8` exists.
- **System widget (Paper THREE TIERS)** — TODAY on `NextBodyLiveActivity`
  ships two families on one carbon, no tile columns (the square small face
  was retired): medium = three rings then a rail (`NEXTBODY` white, no
  lime square, plus the home-header band cell) — READINESS lime, LOAD
  white, SLEEP in `Island.luna` (violet-1); large = that rail on top,
  rings with air between them, then a 3×3 of SLEPT / ACTIVE / HR,
  STRESS / STEPS / DISTANCE, and RHR / HRV / SPO2 (no TEMP). The RHR
  cell is last night's resting pulse (`nightInputs.rhr` →
  `Glance.nightRhr`), a night number that does not withdraw at ninety
  minutes — it replaced the meal-RESPONSE cell, which needed optical
  points most days never produce. One margin governs the whole
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
  the wordmark; the large 3×3 takes `.padding(.bottom, 14)` so RHR /
  HRV / SPO2 do not sit on the floor. Medium rings take `topInset: 16`
  and pin under it — a centred stack put the circles ~8pt from the
  squircle. Large rings stay centred (no topInset).
  Band cell is `WidgetBandPip` (same 12×7 as
  `BandBatteryPip`); it does not withdraw at 90 minutes. TODAY is the only
  WidgetKit kind; the Log a meal shutter (`NextBodyShot`) is removed.
  App Group `group.com.nextbody.hoop` carries the glance
  (`widget.glance.v1.json`); `UserDefaults.standard` is never a fallback
  for numbers. The widget process does not talk BLE. `signedIn` follows
  Keychain `userId`. No-night SLEEP stays ——.
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
- **Profile 12-B line** — `ProfileView.swift` is the live 我的 page, Paper NEXT
  `01M5431DYXFG97J2RRGJR6YTTD` page `首页` artboard `12-B · ME — 线条风格`
  (`MH2-0`). Carbon ground, full-width hairlines, no plates. Compact `‹ ME`
  bar with a lime YOU pip. Identity is a 72pt lime ring, NOW, and the name
  (opens `.profileEdit`). HEIGHT / AGE come from the profile; WEIGHT is the
  latest `compositionScans.inputWeightKg` only — a missing scan is `——`, never
  `today.weightKg` — with `SCAN ·` date under it, and that number is lime.
  COMPOSITION is the 26×7 Daily Direction map (months above, legend
  DEFICIT / LEVEL / SURPLUS / GAP) and opens today's composition; `BODY ›`
  calls `Router.showHome(page: 2)`. Fat / lean / the 12-week gauges and the
  Body Battery curve are gone from ME. MEASUREMENTS stays three lines plus
  `ALL_MEASUREMENTS`. Rows: PROFILE, TRAINING GOAL (the goal enum's own name,
  CUT / RECOMP / BULK), DEVICE, NOTIFICATIONS (real auth; denied is
  `OFF IN SETTINGS` in amber), APPLE HEALTH (`ACCESS OFF` amber until linked),
  the MCP card says “Connect your AI” and opens the three-step page:
  one address, copy, add it, sign in, turn on meal logging. UNITS · HAPTICS (units sheet, haptics
  toggle lives on that sheet), LANGUAGE · WIDGETS (language sheet links to
  widgets), COLLECTING HEALTH DATA, PRIVACY · TERMS (date from
  `LegalText.revised`; the sheet links to the other document), REPORT,
  DELETE ACCOUNT in `#F87171`. SIGN OUT is text. The build line reads
  `CFBundleShortVersionString` and `CFBundleVersion`. AI MEMORY stays behind
  `AIFeature.enabled`. UI/brand type on device is Fusion Pixel; Paper still
  paints Inter Tight / Jost / Doto.
- **Pro exploration (Paper only, 2026-09-13)** — not in code. STATUS 08 still
  holds: no purchase entry. Legal copy still says NEXTBODY is free forever.
  Chosen direction is C taken as **signage**: full-bleed lime `#EFF65A` ×
  black type, monthly only `$6` (Jost `$` + Doto `6`).   Live ME is the line page in NEXT (`MH2-0`); Hoop Sport `B-0` is the older
  plate replica. The paid flow lives on Hoop Sport page `订阅` (`A-0`).
  **The planet is background only, and only on the dark screens.** ME
  carries no sky: both ME boards are flat carbon `#0B0B0D` with no
  bloom, stars, or ring, because a gradient sky above a stack of plates
  read as two unrelated pages. Pro on ME is a **plate**, not a
  full-bleed bar — 358 wide, radius 26, lime `#EFF65A`, built like the
  identity plate (head row + `#00000029` hairline + 44px bottom rail)
  and sitting first inside `Page stack`. Free head is `MEMBERSHIP` /
  `START PRO` / `$6` / `A MONTH`; Pro head is `MEMBERSHIP` /
  `PRO IS ON` / `13 OCT` / `RENEWS`; both rails list TALK · COACH ·
  MEALS · ADVICE · DISPLAY. ME Pro's identity plate stays dark carbon
  so two lime plates never stack. Planet geometry still derives from
  NEXTBODY-HOOP `V-1` Plate 01; `x-paper-clone` cannot cross files, so
  A-0 redraws the SVG. B-0 A–E / S1–S5 are the rejected first pass.
  Free = band + vitals + logging; Pro = the AI.
  **The pitch is three blocks, not five features.** The five AI names
  (TALK / COACH / MEALS / ADVICE / DISPLAY) are a feature list, not a
  value proposition; the paywall copy collapses them into DISPLAY ·
  CONTROL (run the app by voice, band read live), MEALS (say the plate,
  macros split, gap named), COACH · SUGGEST (what to do today, where
  you're going next, ask anything). Every line is a scene, not a
  capability noun. A-0 carries four paywall directions to pick from:
  `11C · Paywall · START PRO` (Horizon — the only planet screen: a `Sky`
  layer with a 460px disc bleeding off the bottom at 42% opacity, wide
  −13° rings, faint stars, bottom scrim, three 22px lines over it),
  `Paywall B · Chapters` (no planet, 01/02/03 Doto numerals, headline +
  scene paragraph, scrolls past one screen), `Paywall C · Proof cards`
  (three carbon plates, each showing the actual result — spoken prompt
  bubble + sleep bars, macro bars + lime gap note, today's suggestion +
  12-week rail), `Paywall D · Lime signage` (inverted: full lime, black
  40px headlines split by black hairlines, dark `Start Pro` slab).
  `11C · Need Pro · Sheet` has no planet at all — the lime sheet carries
  the frozen ask plus the same three blocks as a hairline-topped list.
- **Composition 10E** — `CompositionDetailView.swift` + `CompositionWindowMath.swift`.
  Body fat % is the protagonist. Same DAY / WEEK / MONTH chrome as Battery 12F.
  DAY is this-scan vs last-scan (no chart). WEEK breaks the line on empty days
  and lists every scan. MONTH is a 30-user-day line plus week averages. The page
  reads `DataStore.compositionScans` from every `body_composition` row (device
  BIA, scale, manual). Only persisted fields are drawn.
- `Router`: one-level detail navigation; leaving the root snapshots `homePage`, and every dismiss restores it so page-two vitals return to page two. Destinations include `sportMode`.
- `HomeView` still boots the day (sync, consent gate, live-session takeover). The visible root is `HomeV2Shell`: three horizontal pages, body on the left, planet in the centre, instruments on the right. `Router.homePage` is 0 planet, 1 instruments, 2 body, so a detail push still returns to the page that was open. The page drag is a `simultaneousGesture` so `HotZoneTap` receives the touch; a high-priority drag held the finger until lift and the card never opened. Planet readiness opens Body Battery, sleep opens the sleep board, load opens Training, a logged food card opens Fuel (an unlogged day still opens the MCP copy guide from its own line, and the target row opens Fuel). Body head / heart / gut / legs follow PRD 10, even when the glow is dark. The deck scales to 2.6× around the tapped part and fades out, and `HomeZoneDetail` grows out of the same point in 0.45 s on curve (0.32, 0.72, 0, 1). Back, a swipe right, or a pull down reverses the move. The body page reports the part's centre in its own `body-page` coordinate space, and `HomeDeck` adds `safe.top + HomeHeader.height` to convert it to screen coordinates. Body metrics open Composition. Timeline rows open the matching board (meal → that day's Fuel, sleep/wake → sleep, workout/activity → Training, stress → stress); saved body scans and balance checks open their exact measurement sheet, while weigh-ins are read-only rows. Instrument cells open their vitals boards. The today-timeline sheet pins a lime down-chevron and `Swipe down for home` (下滑回到首页) under the status bar. A tap, a downward flick, or about 80pt of pull on that edge, the title, or the list while it is at rest sends the sheet home. Opening from the planet still takes a third of the screen or an upward fling. The timeline workout pill is still the only control for `sportMode`. Food has four faces from real meals and targets; unlogged days never show eaten as 0. Muscle, visceral fat, water, bone and metabolic age stay —— until those fields are actually stored. The old dock, strip, plan drawer and photo-meal path are not on this root.
- **Home timeline events** — `Services/Band/HomeTimeline.swift` is the pure event-window
  policy compiled by `NextBodySyncCore`; `Features/Home/HomeV2Model.swift` adapts existing
  records, and `HomeTimelineBoard.swift` draws them. Includes confirmed meals, completed
  sport recaps and distinct automatic activity, recorded sleep onset/wake, manual or
  Health weigh-ins, saved body scans/balance checks, and at most one recorded stress
  peak >=60 per day. Sync packets and live-heart “Now” are not life events. Band BIA
  input weight is not a weigh-in; body-scan values explicitly say body fat / lean mass.
  Events use their own timestamps, not the availability of a daily settlement. First
  record per ID wins; current daily metrics precede stale history. Today is local
  midnight to now, and past seven days includes today plus six calendar days.
  Future/reversed intervals are withheld. A recorded workout replaces an automatic
  segment only when it covers that segment within one five-minute sampling tick at
  either edge; substantial activity outside the workout stays visible.
  Sleep start and wake keep their actual dates; the wake row also prints the onset
  clock/date, and manually logged or edited windows retain provenance. No onset is
  inferred from a duration. Past-seven-day mode loads historical records and ticks
  on demand, uses `recentMeals` for prior days, groups by date, and does not inflate
  the planet's today-only count. Published measurements, weigh-ins, recent meals and
  units participate in the deck cache stamp. Timeline scroll rows use plain buttons
  rather than `HotZoneTap`'s zero-distance drag; an open sheet leaves subview gestures
  enabled with `GestureMask.subviews`. Header/list pull-to-dismiss is unchanged.
  Regression seams are `HomeTimelineTests` (portable) and `HomeTimelineEntryTests`
  (real simulator list scrolling, historical dates, measurement sheets and dismissal).
- **Rhythm history** — `Features/Home/HomeRhythmHistory.swift` is a separate overlay
  from the today-only `HomeTimelineBoard`. Its 30D default is a Monday-aligned,
  rolling 30-day calendar of 24-hour bars; 7D expands those same bars into a
  single row. Recorded sleep intervals may cross midnight; meal, activity and
  stress markers keep their actual timestamps, and tapping a day opens its
  event list. Missing days remain empty rather than receiving generated data.
  `HomeV2Shell` hydrates 29 preceding days on entry, and the model/event
  policy accepts an explicit lookback so today's list remains today-only.
  1Y is visible but unavailable until a bounded annual summary read exists;
  loading a year of raw ticks through the detail loader would be excessive.
- `HomeBodyParticles` (`Features/Home/HomeBodyParticles.swift`): the body-page figure is a live point cloud, not the `HomeBody` PNG. `BodyCloud.shared` samples the PNG once (150 columns, about 4,400 points, seeded so it is the same every launch) and one `Canvas` draws it in about 30 batched paths: (1 + 4 spot) tones × 6 opacity levels. The scan sweep remains additive; point colours use normal blending so orange hues stay saturated. The first time the body page becomes active the points gather from scatter (nothing is drawn before that). Every later visit plays an outward ripple and restarts the scan sweep. It also breathes at the torso, twinkles, sheds rising dust and shows occasional flares. Head, heart, gut and legs spots (intensity + tint, `Zone.allCases` order) colour up to 80% of eligible points inside narrow zone rects, so the hands stay untinted. Shared status colours run green → lime → yellow → amber orange → orange-red, avoiding signal-red for these non-diagnostic scores. The gut blends the protein / carbohydrate / fat palette by their recorded calorie shares (4 / 4 / 9 kcal per gram); missing macros do not become zeros. Legs are an activity-volume heat ramp rather than a low-step warning: dim gray at zero, progressively green up to 8k, yellow at 10k, orange at 20k and orange-red at 30k+. Animation pauses when the page is off screen or Reduce Motion is on. A blurred static halo `Canvas` sits underneath. `BodyLens` either fits the whole figure or enlarges it around a focus point. `Zone.anchor` is each part's centre in artwork units, and `Zone.closeUp` frames `HomeZoneDetail` as a head-and-shoulders, chest, torso or legs close-up. Close-ups use `BodyCloud.dense` (260 columns) and draw only the points on screen. On the body page, `BodyStage` splits the space under the status line into figure, handle, and rows: the row is 17 % of the room, clamped to 84…112 pt. Pulling up trades figure height for two more rows, so three rows fill the space exactly with no gap. Each caption has a leader line from its body part (a dot and ring) to a rail under the caption. The gut's caption and leader hide entirely until food is logged.
- `AIPanel`: renders STANDBY when no widget exists, THINKING during a request, and a completed personalized widget frame.
- `StreamHaptics`: typing ticks + a line tap while THINKING; when the turn lands,
  `settled()` is one Core Haptics needle (intensity 0.9, sharpness 1.0). No continuous
  body — that 55 ms mid-band knock read as dirty. Same cue on Home and Chat.
- `PanelWidgetView`: renders the server-declared widget envelope on the fixed 358 × 470 panel canvas.
- `Chrome`: shared page geometry and reusable navigation/close controls. `DetailScroll` draws a 40pt glass back disc (44pt hit) with the title centred in the bar (Oura pattern, 2026-10-22); Chat's header keeps its own `‹` cluster. `detailEdgeBack` is a window left-edge pan (`EdgeBackGate`) that offsets the page 1:1 with the finger (40% / 300 pt/s commit, same numbers as 04B). It is not an overlay on the ‹ mark. `NB_DEBUG_ROUTE` stops retrying after the first successful land so a pop stays popped. Regression: `NextBodyUITests/DetailBackTapTests` (tap matrix + swipe commit/cancel).
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
- **Sport wrist face (`SportWristMath`)** — HOOP's sport report is `heartRate = 0`
  until the optical lock lands (~20 s). That zero is "not yet", not a loose
  strap. Live session keeps `.reaching` / `READING HEART RATE` / 正在读取心率
  for 30 s of first lock, then `NO CONTACT · TIGHTEN THE BAND`. After a real
  beat, a dropout uses the 15 s live window before tighten. Heart-test
  `.lostContact` is still an immediate tighten. Same class of bug as
  `VPTestHeartStateStart` on the finger test.
- `VitalsTimelinePolicy` + `VitalsDetailView`: sleep uses its recorded night and now also
  draws night HRV, overnight SpO2 and sleep respiration as 15-min occupancy
  envelopes on that same clock (`VitalsTrace`; a column only paints the value
  bands that have ticks, and capsule width follows the slot so a short last
  quarter-hour still sits against the rail). The nav word is the instrument itself (`HEART` / 心率), never
  a `VITALS ·` / `体征 ·` prefix. Page two's retired RESPONSE slot is Body Battery.
  `vitals.response` still deep-links to the meal-response board (`MealResponseIndex`):
  unitless signed percent versus own daytime median, compare-amber, no mmol/L.
  `vitals.hrv` still deep-links to sleep. Heart now has the same DAY/WEEK/MONTH
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
- Band sync outcome is wrist facts only (`BandSyncPolicy.dayStatus`).
  `settle_now` writes derived scores afterwards and cannot mark a complete
  reading `partial`. Doing that showed "Some readings could not sync" after
  a successful upload and forced the next pull to re-read the week. `settle_now`
  lock contention returns `-1`; only transport failures retry once in
  `Repository.settleNow`. HTTP statement timeouts are not retried. Cron and
  foreground settle still finish the scores.
- Band publication sends sleep and up to eight compacted domain offers through
  `public.ingest_band_bundle` when available, retaining each observation in the
  local outbox before network work. Per-domain failures stay isolated; deferred
  offers remain replayable, and stale receipts resend only their full samples.
  The invoker RPC delegates to the existing authenticated sleep/delta functions.
  `nb.settle_accounts` commits account work independently; `settle_now` returns
  `-1` for a brief calculation-row lock wait so clients do not retry a busy settle.
- NextBody `xcodebuild` warning cleanup: MockBand progress loops must
  `await progress(done)` rather than `MainActor.run { progress(done) }`
  (captured `var` in a Sendable closure). DEBUG panel pin helpers that touch
  `WidgetCatalogue` statics need `@MainActor` on the nested function.
  `PhoneTools.fieldWord` maps meal `slot` → `L("slot")` and `band_setting`
  `slot` → `L("measure")` via the entity argument — never two `case "slot"`
  arms. `ISOTimestamp.loose` is `[DateFormatter]` (Sendable) and must not
  carry `nonisolated(unsafe)`; `strict`/`plain` keep it because
  `ISO8601DateFormatter` is still not Sendable. Verified clean with README's
  simulator `xcodebuild` (zero `warning:` lines).
- Female health stays off the product surface. G70 answers the female read with
  `state=None` and `function.female=0`; it is a calendar write (SDK business lock),
  not a sensor, and F1 already spent both second-level pages. Sweep it in DEBUG only.
- Gate branching is `LaunchGate.stage(hasBoundBand:profileComplete:)` — never the last `nb.gate.stage` alone. A finished profile is not asked again after re-pair; a kill mid-About You restores `nb.onboarding.draft.<userId>`.
- Daily Direction on the heat map uses live E_OUT_NOW; `nb.compute_fuel` no longer writes a null direction for an open day. Two snacks in one slot still stay GREY_NOTHING.
- Use design tokens from `NB`; do not introduce hard-coded colors outside `DesignSystem/Tokens.swift`.
- Interactive controls expose at least a 44 × 44 pt hit target even when the visible glyph is smaller. Second-level back is a 40pt glass disc in a 44pt hit area (Oura pattern); the left-edge pan lives on the window so it cannot sit on top of that disc (`NextBodyUITests/DetailBackTapTests`).
- Detail-page layout follows Oura: score hero (number + zone word at its baseline) → `SectionLabel` 主要指标 (`VitalsStatPair` = two filled tiles) → 详情 → cards. `LineSkin`/`CardBlock` are filled cards (white 6 %, radius 20) that bleed `NB.Layout.cardBleed` (12pt) into the gutter so content keeps `contentWidth`; `SegmentedPills(lined:)` is Oura's underline tabs. HOOP fonts and colours stay.
- Vitals second-level titles are the instrument name (`HEART` / 心率), never `VITALS ·` / `体征 ·`. `DetailScroll` pins the back disc and the centred title on every detail page.
- User-visible and accessibility defaults are English; explicit Simplified Chinese is selected through app language state (`AppLanguage` + `L()` English-as-key tables in `app/NextBody/L10n/`).
- Adding a language: add an `AppLocale` case and a `L10n/Tables/<code>.json` mapping English source strings to that language. Missing keys fall back to English. The first table is `zh-Hans.json` (~1900 keys). Do not repeat a key — JSON keeps the last value, which is how `NO NIGHT YET` once leaked English over `还没有夜里`.
- The sign-in / pair film line is `Find your next body.` / `找你的下一副身体。`.
  The launch mark is Doto `NEXTBODY` + lime pip, then `BUILD YOUR NEXTBODY` /
  `打造你的下一副身体`. Not PingFang. The only motion is a typewriter
  (28ms per character, same beat as FirstRun): word, pip, second line.
  Ready cuts even mid-type. Sign-in / pair film stays the pixel-fall.
- On-screen metric names follow the language (`READINESS` → `准备度`). The score is 0–100 with no percent sign; `%` stays on band battery, SpO2, and body fat. Units and brands (KCAL, HRV, HOOP, NEXTBODY) may stay Latin. Permission `InfoPlist.strings` follow the phone language, not `AppLanguage`. Low-readiness notification fires the first time the day reaches ≤ 35 and at least 15 below morning readiness. Tier words: READY / STEADY / MODERATE / RECOVER, all lime.
- Chinese charge-idle copy is **未充电**, never 未插电. Device page uses `L("Not charging")` → 未充电. Old `Unplugged` / `UNPLUGGED` keys stay mapped to 未充电 so a stale lookup cannot bring 未插电 back.
- Chinese UI/brand type uses Fusion Pixel 12px proportional zh_hans, cascaded behind Doto/Jost/Inter Tight so numbers stay pixel-dot and CJK stays pixel.
- AI turns carry `AppLanguage.serverLocale`. The system prompt, meal vision prompt, and chart slot descriptions are written in the selected language and lock the frame to that language regardless of user input.
- The idle panel is represented by `widget == nil`; THINKING and completed personalized frames are represented by non-nil widgets.
- `StandbyArt` (the planet) lives only on `idlePlate`. Daily idle paints `IdlePlateArt` — Paper V-1 `星球显示屏` 1:1 recipes plus atmosphere/grain/limb, driven by `IdlePlateMotion` (8s closed orbit: moons/pips ride `around()`, far half occults). FirstRun ceremony still paints `OrbitField` and must not be swapped onto a day plate. `IdlePlateLock` picks the day-pool / event plate; `IdlePlateStore` persists the snapshot and the BLE-down stamp. Release stays one plate per user-day. DEBUG default walks `advanceVisit` (01…28) once per foreground — header shows the plate index — so every paint can be reviewed; `NB_DEBUG_PLATE=1…28` pins, `NB_DEBUG_PLATE_DAILY=1` restores the playbook. Day-pool plates do not draw the lime charge band (that band belongs to FirstRun `OrbitField`). The planet does not breathe in size. `AIPanel` switches idle / occupied / ceremony as one exclusive tree with animations disabled on the swap, so the orbit cannot cross-fade under a reading. Photo answers paint an opaque unlit LED field under the words (`unlitField`); they used to sit on `Color.clear`. The standby charge cluster (`BODY BATTERY` + the 64pt %) sits below the planet's limb (bottom pad 10, vitals 6 above, hint 8 above). Do not restore equal 16pt vertical padding.
- Every asynchronous panel request carries a request ID; dismissing or starting another request invalidates late results so they cannot replace STANDBY.
- The panel’s chart layer is drawn behind `HalftoneScreen`, while text remains crisp above it.
- Home horizontal paging owns recognized drags; panel and card taps must not fire at the end of a page swipe. A 探点 on a vitals detail chart card is the same rule on a different axis: horizontal travel owns the chart, vertical travel stays page scroll.
- First-run skip is a root `TapGesture` only while `firstRun.playing`. After idle it is `.none`: SwiftUI's parent tap cancels a child `UIViewRepresentable` (`PressHold`) even when the handler is a no-op. Keyboard still worked because it is a `Button`.
- Push-to-talk ASR streams during recording and, on release, races the socket
  against the WAV upload; the first usable transcript wins. A live stream is
  not cut by a wall clock — only after it goes idle.
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
- Home body map: `BodyStatus.dim` (-1) is the neutral off-ramp. A measured
  zero can keep the label/leader visible without implying a warning; truly
  absent data (`nil`) stays unlit. Legs use a separate step-volume tint: gray
  to green below 8k, yellow at 10k, orange at 20k, orange-red at 30k+, and no
  low-step red/orange warning. Their status copy stays neutral. Gut's tint is
  the weighted blend of recorded protein/carbohydrate/fat calories, while its
  calorie-allowance status still controls glow intensity.
- Hairline dividers between stack children go in `.overlay`, never inline:
  a bare `Rectangle().frame(width: 1)` inside an HStack is height-flexible and
  makes its whole ancestor chain flexible, so a parent VStack splits leftover
  space into the card. The Home planet `.logged` food card's dead band between
  header and macro strip was exactly this (`loggedHeader`); fixed by overlaying
  the divider on the leading column. Same class of bug: a `GeometryReader`
  inside an uncapped stack.

## Verification
- Home body colour ramp and macro tint: `cd app && swift test --filter NextBodyHomeTests`.
  The math is pure in `Features/Home/BodyTintMath.swift` (SwiftPM target
  `NextBodyHomeCore`; `HomeV2Model.legsTint/gutTint` only bridge `Color`). Tests check
  low/missing steps stay neutral, 8k green, 10k yellow, 20k orange, 30k+ orange-red,
  and protein/carb/fat at 4/4/9 kcal per g with gut colours `optimal2`/`lime1`/`run1`
  (the same macro colours as the timeline and planet). UI test bundles cannot
  `@testable import NextBody`, so model logic tests belong in a SwiftPM core target.
- Back-swipe snapshot geometry: `python3 app/Tests/diagnostics/backdrop_geometry.py`
  (requires a booted iOS simulator; `--device <UDID>` selects one). It compiles the
  actual `BackdropSnapshot` container against UIKit and checks first layout,
  safe-area size proposals, cancellation/reuse and the committed cover at three
  phone sizes. Keep the snapshot at fixed window size with no flexible autoresizing:
  a screen-sized child inside an initially zero-sized flexible container doubled
  to 780×1688 on a 390×844 screen, then shrank when lifted into the window.
- Swift package logic: `cd app && swift test`.
- iOS UI behavior: run the `NextBody` Xcode scheme/UI test target on an available simulator or device.
- Edge Function lint: `pnpm run lint`.
- Edge Function tests: `deno test --node-modules-dir=auto --allow-all supabase/functions`.
