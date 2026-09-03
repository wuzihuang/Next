# Next · OpenMemory Guide

## Overview

NextBody-Hoop is a SwiftUI iOS app backed by Supabase Edge Functions and Postgres. The app
captures health data from a HOOP band, renders one AI-controlled panel on Home, and keeps
model credentials and tool execution server-side.

## Architecture

- `app/NextBody/`: SwiftUI application, BLE/band services, local repository, and the AI client.
- `supabase/functions/`: authenticated Edge Functions for turns, ASR, meals, settlement,
  exports, and account deletion.
- `supabase/functions/_shared/`: model provider, prompt, tool catalogue, data sources,
  render contract, numeric ledger, and thought-stream processing.
- `supabase/migrations/`: Postgres schema, RLS policies, and data lifecycle changes.
- `docs/STATUS.md`: current implementation and verification record.
- `CONTEXT.md` plus `docs/adr/`: domain vocabulary and architectural decisions.

## User Defined Namespaces

- [Leave blank - user populates]

## Components

- **AI turn** — `supabase/functions/turn/index.ts` streams SSE in the order
  `state → thought/tool → screen.render → done`; `AIService.swift` consumes it.
- **Voice input** — `SpeechCapture.swift` records 16 kHz mono PCM WAV; `/asr` transcribes it
  and deletes the temporary clip after the response.
- **Thought stream** — `_shared/thoughts.ts` converts reasoning deltas into short display lines;
  `ThinkingStage` renders the latest lines while Thinking remains enabled.
- **Data tools** — `_shared/tools.ts`, `_shared/sources.ts`, and `_shared/charts.ts` read
  user-scoped data under RLS and build render envelopes.
- **Number ledger** — `_shared/ledger.ts` rejects frame numbers that did not come from a tool.

## Patterns

- Edge Functions authenticate with `getClaims` so asymmetric JWT signatures are checked
  locally and JWKS is cached; user data queries still use the caller's JWT and RLS.
- Independent turn preflight reads run concurrently before model execution.
- Thinking is always enabled; `TURN_THINKING_BUDGET` controls the per-step ceiling.
- AI latency is measured at ASR response, SSE state, first thought, first tool, render, and done.
- Source-backed frames must read the same source before rendering.
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
- **Dedicated Chat & Cyber Telemetry** — `app/NextBody/Features/Chat/`: Full-screen Cyber Telemetry terminal from the Dock keyboard key. Keeps DIAGNOSTIC TERMINAL chrome, lime telemetry cards, CMD chips, HISTORY bottom sheet. Spacing/fonts slightly enlarged for readability; tap message area dismisses keyboard; no seeded demo sessions.
- **BodyBatteryEngine** — Pure five-minute reserve model. Fuses HR/HRV/stress/steps/MET,
  saturates sleep recovery toward 95, allows bounded verified rest recovery, and holds
  off-wrist ticks.
- **Body Battery server replay** — `nb.reserve_replay` expands `sleep_nights.sleep_line` using
  Veepoo stage ids and writes the authoritative daily curve through normal settlement. Sleep
  improves recovery but is not an output gate: a worn daytime cold start uses an assumed 50
  while leaving `BB_WAKE` and the training target unset.
- **Body Battery v2 correction** — migration `20260903150000` accepts previous-day anchors only
  when a v2 curve proves the score was calculated. A `daily_results` trigger removes stale
  reserve details/curves whenever reserve computation is unknown; deployment also clears and
  recomputes today with an audited migration reason.
- **Body Battery live preview** — `DataStore` rebases from the server score and applies
  unsynced live sensor minutes; the next settlement always replaces the preview anchor.
- **OriginDataSync** — Joins original-data ticks with separate HRV history, uploads raw samples
  and accurate sleep records, settles the affected day, then reloads the server result.

## Patterns
- Deep conversational AI interactions navigate to the dedicated full-screen Cyber Telemetry terminal (`/chat`), while the Home display maintains focus on immediate ambient widget metrics.
- Multi-modal chat inputs support staging image attachments (`PhotosPicker`) alongside query text sent to server-side AI turns.
- Stored historical health values are server-authoritative and reproducible from raw inputs.
- A live UI preview may estimate only the unsynced interval and must rebase on server reload.
- Optional SDK values remain optional; missing and off-wrist are not numeric zero.
- Veepoo accurate sleep stages: 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake.
- Pure SDK-boundary calculations belong in `NextBodySyncCore` with deterministic XCTest coverage.
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
- `Router`: one-level detail navigation; `backToRoot()` clears the path and preserves `homePage` (page two stays on page two). Destinations include `sportMode`.
- `HomeView`: owns the current optional `PanelWidget`, dock state, home paging, and panel callbacks.
- `AIPanel`: renders STANDBY when no widget exists, THINKING during a request, and a completed personalized widget frame.
- `PanelWidgetView`: renders the server-declared widget envelope on the fixed 358 × 470 panel canvas.
- `Chrome`: shared page geometry and reusable navigation/close controls.
- `AIService`: sends user turns and decodes rendered widget frames.
- `ASRStreamingSession` + `SpeechCapture`: open the authenticated socket before recording,
  tail complete 16 kHz mono Int16 frames from the live WAV, and retain the WAV as fallback.
- `AIImagePayload` + Chat image turns: compress to ≤ 640 px / 96 KiB soft target, pass the
  request-scoped data URL to `/turn`, then clear the preview and Base64 after recognition.
- `_shared/tool-routing.ts`: conservatively scopes explicit single-domain turns; unclear and
  multi-domain questions keep the full source and renderer catalogue.
- `PlusMenuSheet`: three groups — ADD, SPORT MODE (`Start a session` → `SportModeView`), MEASURE.
- `SportModeView` / `SportModeCatalog`: catalogued modes (raw 0…47); start/stop via `BandService.startSportMode` / `stopSportMode`. Firmware refusals stay greyed for the page life.
- `VitalsTimelinePolicy` + `VitalsDetailView`: sleep uses its recorded night; heart, HRV,
  stress, and skin temperature use a rolling 24-hour window; steps, distance, and active
  calories use the current 04:00 user day only through now.
- `OriginDataSync` + `Repository`: measured band ticks merge into the in-memory curve before
  upload/settlement, while repository reloads query two user days and preserve fresher local
  points. A missing `daily_results` row never gates raw-sample loading.

## Patterns
- Use design tokens from `NB`; do not introduce hard-coded colors outside `DesignSystem/Tokens.swift`.
- Interactive controls expose at least a 44 × 44 pt hit target even when the visible glyph is smaller.
- User-visible and accessibility defaults are English; explicit Simplified Chinese is selected through app language state.
- The idle panel is represented by `widget == nil`; THINKING and completed personalized frames are represented by non-nil widgets.
- Every asynchronous panel request carries a request ID; dismissing or starting another request invalidates late results so they cannot replace STANDBY.
- The panel’s chart layer is drawn behind `HalftoneScreen`, while text remains crisp above it.
- Home horizontal paging owns recognized drags; panel and card taps must not fire at the end of a page swipe.
- Push-to-talk ASR streams during recording and commits on release; any stream failure falls
  back to the completed WAV upload instead of losing the utterance.
- AI image bytes are never persisted to Postgres or Storage. `image.inspect` produces an
  ephemeral factual extract for the Thinking turn and the UI distinguishes sending from
  server-confirmed analysis.
- A confidently routed turn prefetches its ranked source candidates, harvests the winning
  source into the number ledger, and removes the redundant model read round while Thinking
  remains enabled. Ambiguous turns are not pruned; explicit comparisons among heart rate,
  stress, and steps use the existing `vitals.7d` multi-metric source.
- SDK cannot list supported sports; product shows a fixed catalog and marks refused modes after a failed start.
- Raw measurements may update the UI immediately, but derived daily metrics remain
  server-authoritative. Merge raw ticks by timestamp and preserve non-nil auxiliary fields.
- Never draw future hours on a current-day chart. A ruler's endpoint, sample filter, and
  hourly-bin geometry must all use the same concrete time range.
- Battery Check nudge: `try? await Task.sleep` must `guard !Task.isCancelled` (same as
  onboarding). Do not disarm the 5 s nudge on `.waitingForContact` — only when the band
  reports contact or later. Heart-rate streams use a generation slot so a late LiveReadout
  `onTermination` stop cannot clear Battery Check's SDK result block.

## Verification
- Swift package logic: `cd app && swift test`.
- iOS UI behavior: run the `NextBody` Xcode scheme/UI test target on an available simulator or device.
- Edge Function lint: `pnpm run lint`.
- Edge Function tests: `deno test --node-modules-dir=auto --allow-all supabase/functions`.
