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
- `CONTEXT.md` plus `docs/adr/`: domain vocabulary and architectural decisions.
- App Store Connect: NextBody `6799623125` (`com.nextbody.hoop`, SKU `nextbody-hoop-ios`,
  team `BP7F7PYU33`, widget `com.nextbody.hoop.LiveActivity`). TestFlight groups:
  internal `Friend` (`d62d8979-1adc-45e2-85c4-964b58a7c896`) and `Internal Testers`
  (`8598b996-8b7b-4d9c-9f6a-82e6b6df538a`); external `Public`
  (`9e585745-be37-48cb-bf27-a16a79b0dd81`) with public link
  `https://testflight.apple.com/join/x4yW7mJQ`. Latest processed build is `1.0` (4)
  (`1f1f674d-f2c2-49bd-a12d-4472b395759a`, uploaded 2026-09-06, encryption exempt).
  First external Beta App Review was submitted 2026-09-13 and is now
  `APPROVED` / `BETA_APPROVED`; the public link can be used to join and install.
  Do not confuse with the older phone bundle
  `com.walnutechnology.nextbody.app`.
- App Store screenshots live on Paper `NEXTBODY-HOOP` page `screenshot` (`S-0`): one
  5-up review board plus five 1290×2796 iPhone 6.7 frames. Screens are cloned from
  `新版设计` (`N-0`), not redrawn. Headlines: SEE LAST NIGHT / KNOW YOUR CHARGE /
  HIT TODAY'S RING / EAT TO THE NUMBER / READ YOUR NIGHT. Ground is lime-1 `#EFF65A`.
  Device chrome uses CSS `zoom: 2.554` so the 390×844 phone fills a 1032-wide bezel.
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
  picker (App / small / medium / large), Today small (BODY BATTERY 68),
  Today medium (BATTERY 68 / LOAD 2.6 / EATEN -- / band 82%), and Today
  large (three rings plus SLEEP/ACTIVE/HR / STRESS/STEPS/DISTANCE /
  RESPONSE/HRV/SPO2). Shot strip pins `ShotWidget` LOG A MEAL on the
  home screen (yellow viewfinder) and the same Shot beside a filled
  Today medium (BATTERY 72 / LOAD 12.4 / EATEN 1,240). Inject Shot via
  IconState `widgetIdentifier=NextBodyShot` then `simctl shutdown` /
  `boot` — the in-app widget gallery stayed blank. Q-0 VOICE / HOLDING
  / four casting faces are design-only; do not clone them.
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
  (`语言` / yellow dot) and Home paints 身体电量 72% in zh-Hans.
  Vitals MONTH strip pins Stress / Temp / Steps / Distance / Active
  LAST 30 DAYS (`NB_DEBUG_METRIC_RANGE=MONTH`).
  `NB_DEBUG_SCROLL_TO=bb-why` centres that card. Lock capture is
  `axe button lock` then `home` to wake the lock screen.
  `SheetHost` must present `FindHoopSheet` for `.findHoop` (not `ProfileSheet`'s
  `EmptyView`). Capture batches live in `/tmp/nextbody-t0-capture.py`.

## User Defined Namespaces

- [Leave blank - user populates]

## Components

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
  horizon / low blooms (16/25); Paper 16 JSX has no traveler pip. Plate 28 foreground rings stay
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
  with `NB_DEBUG_PLATE_DAILY=1`. Geometry source of
  truth is the Paper artboard (e.g. plate 01 ball 164 at 97/106, rings −14°,
  moon 7×7 at 286/214; 03 ice 156 at 101/50 −3°; 05 umber 136 at 111/110 −22°
  + moon 88/108; 06 dashed orbits around 150 at 105/120; 07 blue-gray 144 at
  107/106 −24°; 08 is a 90px warm ball at 95/145 plus a wide diagonal band
  (no rings); 09 is a 150px cool ball at 104/115 plus a fading diagonal;
  10 is a dashed blue line from top-left with a star at (14, 94); 11 is an
  860px right-limb with diagonal lines and no rings; 12 silhouette 170 at
  94/103; 13 is a bright diagonal plus dashed 210×110 ellipse at −32° (no
  moon); 14 is a 56px dim ball at 151/167, dashed r=62 circle, fade line;
  16 is a bottom cyan bloom + far circles + left dashed crescent; 17 is a
  violet bloom + 128×96 ellipse at 18° + pip (294, 210); 18 is two magenta
  blooms + rings at (200, 210) + pip (106, 264); 19 is a 150px ivory ball
  at 105/125 with a thin −13° ring and three color ticks; 20 blue 184 at
  206/103 + far arcs; 21 left giant 404 at −262/38 + pip 223/218; 22 ivory
  136 at 111/118 −2°; 24 is a cyan cubic trail + static head (366, 92);
  25 low amber bloom 240×130 at 59/248 + inner 100×40 at 129/278 + arc
  `M 244 410 A 64 15 −4`; 26 violet 160 at 170/150 left-lit; 27 dashed
  arcs `1.2 8` / `1.6 7` + pip 150/138), not the old LED OrbitField.
  Plate 02/23 craters are Paper mares/pits with radial bowls (no hard
  discs); 23 paints Paper SVG elliptical pits plus typed `PaperLip`
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
  30 min (never in the past). A run: `Repository.openSession` →
  `OriginDataSync.refreshNow(.background)` (floor `min(300, cadence)`, no live-receipt
  reuse) → `flushPendingEvidence` (settle today + reload even when the band was out of
  reach) → `WidgetGlancePublisher.publish` + `HomeSnapshot.save` → reschedule.
  Expiration cancels the Task; `BackgroundTaskCompletion` locks `setTaskCompleted` to
  once. Returning to the app uses `BandRefreshRequest.resume` (floor `min(60, cadence)`,
  reuses the live receipt) so the device-page cadence no longer throttles a foreground
  entry; the HomeView 30 s timer keeps `.foreground` (floor = cadence). Body Battery
  "empty" = server `observed_at` (last observed tick + 5 min) older than
  `BodyBatteryReadoutPolicy.goneAfter` (6 h) or no `reserve_daily` row yet; the phone
  never computes the reserve. Pure rules in `Services/Band/BackgroundRefreshPolicy.swift`
  (in the `NextBodySyncCore` package; tests `BackgroundRefreshPolicyTests`).
  Silent push is not an option until the APNs `.p8` exists.
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
- **Profile 11C Instrument** — `ProfileView.swift` is the live 我的 page. Four
  `panelWash` plates: identity (NOW + brand name + lime avatar + HEIGHT/WEIGHT/AGE
  rail), Body Battery (curve + MORNING/NIGHT/NOW), composition (YEAR header →
  today, 26×7 Daily Direction cells → that day, DEFICIT/SURPLUS/LEVEL/GAP
  legend, 12-week gauges on the same card), measurements (recent three +
  `ALL_MEASUREMENTS` only). Settings rows stay `carbon4` (ACCOUNT /
  PREFERENCES including HAPTICS + APPLE HEALTH last-read / DATA & LEGAL).
  Page gap is 16. Nav trailing is a lime YOU pip. Current 1:1 Paper replica
  of that code is Hoop Sport `01M1M2B4XWK5W388XSKACJ1K9N` page `我的` (`B-0`),
  artboard `11C · 我的 · ME` (390, fit-content). NEXTBODY-HOOP `11 · 我的
  Profile` / old `57U-0` is the earlier spec (no Body Battery plate, old
  month-dot map, EXPORT MY DATA). 11D/E/F stay Paper-only. UI/brand type on
  device is Fusion Pixel; Paper still paints Inter Tight / Jost / Doto.
- **Pro exploration (Paper only, 2026-09-13)** — not in code. STATUS 08 still
  holds: no purchase entry. Legal copy still says NEXTBODY is free forever.
  Chosen direction is C taken as **signage**: full-bleed lime `#EFF65A` ×
  black type, monthly only `$6` (Jost `$` + Doto `6`). Live 1:1 ME stays
  on `B-0`. The paid flow lives on Hoop Sport page `订阅` (`A-0`).
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
- `HomeView`: owns the current optional `PanelWidget`, dock state, and panel callbacks; the pager index lives on `Router.homePage` so NavigationStack push/pop cannot wipe it.
- `AIPanel`: renders STANDBY when no widget exists, THINKING during a request, and a completed personalized widget frame.
- `StreamHaptics`: typing ticks + a line tap while THINKING; when the turn lands,
  `settled()` is one Core Haptics needle (intensity 0.9, sharpness 1.0). No continuous
  body — that 55 ms mid-band knock read as dirty. Same cue on Home and Chat.
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

## Verification
- Swift package logic: `cd app && swift test`.
- iOS UI behavior: run the `NextBody` Xcode scheme/UI test target on an available simulator or device.
- Edge Function lint: `pnpm run lint`.
- Edge Function tests: `deno test --node-modules-dir=auto --allow-all supabase/functions`.
