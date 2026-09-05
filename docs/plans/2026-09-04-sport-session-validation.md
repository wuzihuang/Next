# Sport-session physical-device validation

## Scope and device

Reinstalled and exercised the real app on the user's wired iPhone 17 Pro Max (iOS 26.5), using its existing account, consent and bound band. NaClO, the other visible phone, was not used. No simulated band, synthetic account, permission bypass or test clock was enabled. Raw health logs and screenshots remain local under `/tmp/nextbody-sport-validation`.

## Changes

- App-owned Bluetooth lifecycle retains the connection and live stream on ordinary background transitions. Sport has exclusive admission; pages do not own the connection.
- Startup and stopping wait for admitted native commands rather than the entire history/cloud pull. Unique session lifetimes fence account/binding changes and late callbacks; cancellation drains opening and listener teardown before releasing ownership.
- Sport readers share the SDK's single native callback. Generation and last-reader guards prevent one-shot reads or old cleanup from stealing a newer stream.
- Firmware busy receives one bounded retry after the sensor settles. Only a fresh confirmed running state permits joining an existing workout. Definitive busy does not destructively close the band's session. Normal stop sends one native stop command.
- Active sport owns reconnect after radio loss, with bounded backoff, cancellation and password-verified readiness.
- Historical persistence reuses formatters per batch and uses atomic FULL-durability batch transactions. Eleven storage tests cover reopen durability, idempotency and rollback; all 42 focused BLE/sport/storage tests passed.
- Native STOP recognition is no longer reconfigured on every unchanged SwiftUI refresh. A STOP-only stationary qualified-release fallback handles a completed hold whose recognition was lost across scene activation. Native timestamps, movement and cancellation guards preserve the 0.9-second threshold and at-most-once commit. Recording controls do not opt in.
- Modal accessibility children are grouped for reliable interaction. UI tests drive the real native overlay and wait until the visible opening state finishes before attempting STOP.

## Physical evidence

| Scenario | Verified result | Artifact under the local log directory |
| --- | --- | --- |
| Sport start/stop across relaunch, picker navigation and foreground/background | 10/10 completed; 10 native start ACKs and 10 stop ACKs; every session received new heart-rate callbacks; no in-session reconnect | `resume-ten-cycles.xcresult`, `resume-ten-receipts.json` |
| Background sport for two minutes | 120.617 seconds, 58 new heart-rate receipts, largest adjacent receipt gap 3.238 seconds, zero reconnects; final stop ACK | `resume-edge-cases.xcresult`, `resume-edge-receipts.json` |
| Relaunch while band workout remains running | Fresh running-state verification, joined existing workout, received new heart-rate data and stopped with native ACK | `resume-edge-cases.xcresult` |
| Immediate stop and same-mode restart | 3/3 passed after correcting the test's opening-state readiness check | `resume-edge-retry.xcresult` |
| Normal connection navigation | 5 relaunches, 10 background returns, 20 device/profile round trips and final connection check all passed | `resume-navigation.xcresult`, `navigation-evidence.json` |
| Normal background connection ownership | Zero reconnects and zero stream stops in all 10 background windows; one new logged ordinary live sample in the last 15-second window | `navigation-app.log` |
| Radio recovery before final STOP fix | Real radio off/on verified; new sport receipt 6.374 seconds after the on marker. First STOP crossed activation and failed; teardown STOP received ACK | `radio-recovery.xcresult`, `radio-app.log` |

The normal navigation run had six connection starts: initial launch plus five intentional process relaunches. The roughly five-second UI connection-check duration includes navigation and XCTest waits and is not BLE handshake latency. The sport background counts come from native receipt logs, not cached display values. Both ordinary connect logs and session-owned reconnect-attempt logs were checked; none occurred in the ten ordinary sport sessions.

## Final regression status

The final signed device build succeeded (`final-test-cleanup-build.log`) and was installed on the selected phone. Against the final app source:

- All three rapid same-mode start/stop cycles passed, with three native start and stop acknowledgements. The first two intentionally stopped before waiting for a heart sample; the third received new heart-rate data.
- Short tap and swipe did not stop the workout. The subsequent valid hold stopped it with one native ACK (`final-hold-regression.xcresult`).
- The first final radio attempt recovered data and acknowledged the first intended STOP, but the test subsequently failed querying background Settings in redundant cleanup. This failed bundle is retained and is not reported as a fully passed suite. Cleanup now uses the existing restoreBluetooth-gated teardown only.
- The isolated radio rerun passed end-to-end (`final-radio-cleanup.xcresult`): switch states OFF/ON confirmed, password-verified reconnection, three new post-recovery heart receipts, first intended hold stopped the band with one ACK, and return to interactive home. Recovery to the first new receipt took 25.088 seconds after the ON marker. Earlier attempts measured 6.374 seconds and 22.775 seconds (the latter required retry); no instant recovery is claimed.
- The app was relaunched normally with only diagnostic log forwarding enabled. Password verification, a fresh battery reply and at least five new ordinary live samples were observed; readiness was 2.181 seconds (`final-verified-baseline.log`). Bluetooth is left ON and no workout remains running.

The release fallback is reviewed and opt-in; final physical tests exercised valid holds and short-tap/swipe rejection, but did not emit a qualified-release diagnostic. Therefore the rare fallback branch itself is not claimed as directly exercised on hardware. The adjacent evidence JSON contains the exact counts and artifact locations. The requested bounded stress matrix is complete.

## Diagnosis and limits

Initial failures included both genuine product defects and automation issues. Tests that never reached sport, pressed while opening was still active, or failed to operate the Settings switch are not counted as successful stress cases. The genuine activation-edge STOP failure had a stationary 1.292-second native touch while new BLE receipts continued; this justified the narrowly scoped qualified-release fallback.

An earlier Time Profiler capture identified main-thread historical persistence work, including repeated date formatter initialization and per-row SQLite transactions. Batch changes reduced isolated Mac 1,000-row transaction timing from 0.1871 to 0.0080 seconds and formatter work from 0.1313 to 0.0402 seconds. These are not phone latency measurements. A later 10-second capture during the automation cleanup wait showed continued main-thread rendering (3.021 seconds sampled, including 2.042 seconds in OrbGlyph); it does not prove a deadlock or establish the cause of the preceding accessibility delay. An initial render/wait stall had insufficient waiting-thread evidence to establish its root; no claim is made that every possible hang is eliminated.

Background transport is verified for the measured two-minute sport interval, not indefinitely. Killing the app is tested as reconnect/rejoin on relaunch, not continued app execution after force quit. Phone power-off and long-duration soak are not claimed. In the final radio test, the initial fresh sport receipt took 28.484 seconds after start ACK; connection readiness and first sensor sample are different milestones. The 42 focused passing tests do not establish whole-app 80% coverage. No commit or unrelated-file rollback was performed.
