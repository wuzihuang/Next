# Real-device BLE stress validation · 2026-09-04

Device: physical iPhone 16 Pro Max; existing signed-in account and paired HOOP. Real Veepoo transport, no mock data or consent bypass.

## Completed: repeated app termination and launch

10 consecutive terminate-and-launch cycles passed. Each cycle required `connect step 4` (password verified) and a fresh `readBattery ← ok`, not a cached battery indicator. Commands terminated the app; these were not unexpected crashes.

| Cycle | Launch → battery (s) | Connect → verified (s) | Result |
| --- | ---: | ---: | --- |
| 1 | 6.02 | 3.298 | PASS |
| 2 | 17.07 | 13.991 | PASS |
| 3 | 11.06 | 8.423 | PASS |
| 4 | 3.03 | 1.805 | PASS |
| 5 | 4.03 | 1.797 | PASS |
| 6 | 4.03 | 2.197 | PASS |
| 7 | 5.05 | 2.704 | PASS |
| 8 | 5.05 | 2.484 | PASS |
| 9 | 4.04 | 1.561 | PASS |
| 10 | 5.05 | 2.672 | PASS |

Launch-to-battery measurement includes devicectl overhead and one-second polling. Mean 6.44 s, maximum 17.07 s. Handshake mean 4.09 s, maximum 13.991 s. No connection deadline expired in these ten cycles. This is bounded evidence, not a claim of long-term reliability.

## UI scenarios prepared; execution blocked

`app/NextBodyUITests/BandConnectionStressTests.swift` defines 5 additional app relaunches, 10 background/foreground transitions (2 or 15 seconds), and 20 Home → Device → Home → Profile → Home iterations. It checks the device page live CONNECTED state and retains screenshots. Simulator runs skip this hardware-dependent test.

The test target built and signed successfully. The first UI run failed before any test scenario started: `Timed out while enabling automation mode.` The phone did not require a passcode at the lock-state check. UI automation initialization is separate from BLE connection. A second attempt failed with the same automation-mode initialization timeout before any UI scenario executed. Device-side automation confirmation is required to proceed. No page-switch or background test is counted as passed.

## Local artifacts

- `/tmp/nextbody-ble-stress/cold-results.json`: per-cycle results.
- `/tmp/nextbody-ble-stress/cold-1.log` through `cold-10.log`: raw device launch logs; may contain private SDK data, not committed.
- `/tmp/nextbody-ble-stress/ui-stress.xcresult`: first UI runner initialization failure.
- `/tmp/nextbody-ble-stress/ui-stress-retry.xcresult`: retry result.

UI checks must be correlated with Bluetooth logs to distinguish transient disconnects from cached UI state. Fifteen seconds in background does not prove OS suspension.

## Foreground/background implementation and follow-up validation

The approved follow-up moves live collection from HomeView's scene-bound task to an app-owned `BandLiveLifecycle`. An active heart-rate stream is retained on background entry. New inserted stress tests wait for foreground; manual measurement, workout, consent withdrawal, account changes, and binding changes retain their ownership gates. Bluetooth-central background mode was already declared. This supports Bluetooth-driven delivery while the process is alive; the vendor SDK has no working state-restoration configuration, so force quit/system termination is not covered.

A short coalesced readiness lane validates the password-verified link and a fresh battery response independently of cloud hydration and historical uploads. Foreground return may reuse an actual matching-owner heart-rate receipt no older than three seconds. Native reads pause the sensor only around BLE work, not cloud waits. Manual measurement closes admission and waits for already admitted native operations before starting; network requests hold no native lease. SDK automatic connection is disabled at initialization so it cannot race app-owned reconnect.

Validation on the physical device:

- Final Debug build succeeded and was installed on the existing iPhone, preserving its account/binding.
- 16 focused tests passed: readiness coalescing and retry, binding isolation, fresh-receipt gates, native-operation drain, lifecycle ownership, and reconnect selection. The two new core implementation files have 100% line coverage in this focused run; this is not whole-app coverage.
- An intermediate smoke run had scan misses, a connect timeout and failed verification. It did not establish a usable link and is not a pass.
- Final installed build at device time 22:32:48 started readiness; verification completed at 22:32:52, fresh battery at 22:32:55 (6.581 seconds from readiness start). Native historical reads also returned successfully.
- That link disconnected at 22:33:15, before background entry at 22:33:23. No accepted live HR samples were recorded in that interval. Therefore background continuous transfer and sub-three-second readiness remain UNVERIFIED; this successful battery read is not evidence of background streaming.
- Launching Settings and reactivating NextBody produced actual inactive/background/active lifecycle events. UI page-switch XCTest remains blocked by device automation initialization; it is not counted as passed.

Raw diagnostics are local only: `/tmp/nextbody-background-validation/initial.log`, `reuse-smoke.log`, and `final-installed.log`; build/test logs are `/tmp/nextbody-ble-background-build.log` and `/tmp/nextbody-background-core-tests.log`. Raw SDK and history logs may contain health data and are not committed. Continue with a worn, powered nearby band and exclude another connected companion app before asserting a background-data pass. Physical conditions have not yet been confirmed by the user; the remaining disconnect cause is not established.

### Additional observed recovery blocker

On foreground return at 22:34:13, readiness began but did not scan until 22:34:44. The previous stress measurement, started at 22:33:13 and canceled after disconnect, waited for its 90-second SDK bridge timeout. Its cancellation handler sent stop but did not resume the suspended continuation. Reconnect subsequently verified and read battery at 22:34:49 (36.549 seconds including the old measurement wait). This is a concrete application cancellation defect, independently of the original disconnect cause. A targeted cancellation bridge is being implemented and must be rebuilt/retested before this defect is called fixed.

### Established-link foreground/background stress results

After recovery, the same physical-device process received real HR notifications in background starting 22:35:44. A supported devicectl launch of Settings put NextBody into background; reactivating NextBody retained its process. Ten cycles then used 3 seconds foreground and 15 seconds background. All ten observed both lifecycle transitions, reused a recent actual HR receipt, had no connection-start or disconnect event, and received background HR callbacks. Total callback receipts within cycle windows: 144. These are callback counts, not distinct physiological measurements. No debugger was attached; console capture was active. These checks do not establish behavior after force quit or prove system suspension.

The ten-cycle run used the background implementation before the additional stress-cancellation bridge was installed. The final bridge build passed 20 focused tests. Core line coverage: BandLivePolicy 100%, BandReadinessFlight/receipt/drain 100%, BandMeasurementReply 96.83%. Final installed-revision cancellation validation follows separately.

### Final installation and remaining device-side gate

The final cancellation-bridge build succeeded and installed at host time 10:40. Its launch was denied by iOS because the phone had locked (`FBSOpenApplicationErrorDomain` code 7; lockState `passcodeRequired: true`). No final-revision cancellation scenario executed. The prior ten background cycles remain valid for the preceding installed build; they must not be presented as final-revision cancellation validation. Unlocking the iPhone is required to finish the targeted real-device cancellation/return-to-foreground check. Unit tests prove bridge behavior, not that this physical SDK cancellation scenario has run.
