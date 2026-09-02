# 02 · Connect 手环配对 — screens, rules, edges (mirrored 2026-09-01)

Head: PAIR SPEC · CONNECT THE BAND · 「连上，然后就别再提它」. Five screens do four things: teach the
one hardware action, find it, make connecting visible, then hand off. NOT IN V1: multi-device,
manual code / QR / NFC, firmware update inside pairing, re-bind and history migration.

## Screens (copy verbatim)
01 `PAIRING 01 / 05` · Turn it on · "Hold the button on the right edge for two seconds, until the band
   lights up." · `HOLD 2S` · "Nothing lights up? It may be flat — charge it for ten minutes, then hold
   again." · CTA It’s on
02 `PAIRING 02 / 05` · Searching · "Keep the band close to your phone. This usually takes a few seconds."
   · `SCANNING` · "Keep it within arm's reach."
03 `PAIRING 03 / 05` · Found it · "One band is in range. Tap connect and keep it near your phone." ·
   card NEXTBODY HOOP / `READY TO PAIR` · 96% + 3 bars (⚠️ before-ship: rssi-tiered bars or drop the
   block) · CTA Connect · "Not your band? Search again"
04 `PAIRING 04 / 05` · Pairing · "Keep it close — pulling everything into place." · `PAIRING` 62% ·
   bar 270 wide · "Keep it within arm's reach."
05 `CONNECTED` (Doto 26 / 0.28em) · `LINK LOCKED · DOUBLE TAP` · CTA "Now let me get to know you"

## Hard rules
01 Scan 15 s, connect 20 s — provisional; calibrate on device P90 before launch.
02 Progress bar has four fixed segments: connect 0–35%, auth 35–60%, capabilities 60–85%, version +
   battery 85–100%. Whichever does not return, the bar stops there; never animated full.
03 No error clears state: found devices stay, progress does not reset, user input stays. Failure
   swaps colour and the two lines only.
04 Mid-pairing disconnect → back to 02 with one line, not to 01. Two disconnects in a row → maybe too
   far. No 「确定要放弃吗」; a connected band is never disconnected on exit.
05 Low battery (isLowBattery or < 10%) does not block pairing; one amber line on the success screen.
   isPercent false → `BATTERY LOW`, never an invented percent.
06 Forget this HOOP = disconnect() + clear the stored deviceId. No unbind, no factory reset, no rename.
07 Scanning starts only from 01's It's on (Bluetooth + location permissions asked there). Refused →
   degrade in place to EDGE 2 / 3; returning from 02 does not need the tap again.

## Edge cases · 05 「连不上的时候，不换页」
1 NOTHING FOUND — after 15 s: ripples stop and go white 18%; `NOTHING FOUND`; three checks in order:
  · 手环亮起来了吗 · 是不是超过一臂远 · 是不是还连在别的手机上; outlined "Search again". Still screen 02.
2 BLUETOOTH OFF — illustration to 20%, status line amber `BLUETOOTH IS OFF`, "I can’t look for the band
  without it.", link 去打开蓝牙 →. Back from Settings rescans by itself.
3 PERMISSION — `PERMISSION NEEDED` · "Android asks for location before it will scan for Bluetooth. We
  never read where you are." · 去设置里打开 →. Not shown on iOS.
4 CONNECT FAILED — arms stop, everything amber, `STOPPED` · 62% frozen (never to zero), bar amber, "The
  band stopped answering. Nothing you did wrong.", lime "Try again". Second failure adds Search again → 02.
5 TAKEN — `TAKEN BY ANOTHER PHONE` · "This band is still paired somewhere else." · 1 · 在那部手机上断开连接
  · 2 · 或者长按侧键，把手环重启一次.

## Before ship
! 03's 96% has no source (battery needs a connection, rssi is scan-only). ! readDeviceFunctions() must
  be stored; unknown → plus-menu rows render as unsupported. ! The success burst and the first-run
  opening must be one implementation (MOTION SPEC · 01).
! Events: PAIR_START · PAIR_DEVICE_FOUND{MS,RSSI} · PAIR_STEP_DONE{STEP,MS} · PAIR_SUCCESS{MS,FW,BATTERY}
  · PAIR_FAIL{REASON,STEP} · ONBOARD_ENTER
! Acceptance: pair completion ≥ 92%; 01 → success P50 ≤ 45 s; success → onboarding ≥ 95%.
