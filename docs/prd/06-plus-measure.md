# 06 · 加号键与手环测量 — rules, edges, before-ship (mirrored 2026-09-01)
Sections: 01 the plus and its sheet (OPEN 0.34S · ROW PRESS 0.12S · DISMISS 0.22S) · 02 recovery check
(OPEN 0.46S · CONTACT ~1.2S · NUDGE AT 5S · RUN 60S) · 03 reading → result (60S RUN · LIFT-OFF 3S GRACE ·
RESULT 0.5S) · 04 body composition (30S TOTAL · TWO CONTACTS · 14 FIELDS · NO RESUME). Motion: 06M.

## Hard rules
01 Behind the plus there are three groups: for her (photo / library / file), Sport Mode
   (start a session → detail page of catalogued modes), and for the band (recovery check /
   body composition). Nothing else joins the plus.
02 One start*Test at a time. A second entry degrades to MEASURING NOW in the sheet and sends nothing;
   it recovers on TestState 'over' / 'error' without a refresh.
03 The capability table decides a row's state, not its existence: unsupported → 32%, no duration, the
   reason in the row; before the table arrives, everything renders unavailable.
04 Every number on screen was measured. HR / HRV / STRESS appear independently as each settles; a
   missing one stays blank with a Doto reason. No spinner, skeleton, placeholder, fake progress.
05 The sheet's seconds are a promise: 60 S and 30 S run to the end even if the result comes early. The
   only early exit is TestState 'error'.
06 Finger off gets 3 s grace: countdown holds, numbers stay at 32%. Past 3 s → stop*Test() then
   restart, with the line first. Body composition has no grace: lift = restart, said before start.
07 Amber means only "you have to do something" (not worn, finger off, no contact by 5 s). Device-side
   states (disconnected, busy, unsupported) are 32% + a Doto line; never amber, never red.
08 The only exit is the close mark: no timeout exit, no back gesture, no second level. Android back →
   close mark, stop*Test() first.
09 Store, recompute the target, then the result animation: number and target (14.5 → 11.0) change in
   one frame, panel and cards together.

## Edge cases · 06 「测不出来的时候，屏不换」
1 NOT WEARING — dashed amber trace, "The band isn’t on your wrist.", `NOT WEARING · PUT IT BACK ON`;
  countdown pauses, resumes by itself.
2 FINGER OFF — trace flattens in 300 ms and goes amber, "Your finger came off the key.", `PAUSED · 3S TO
  RESUME`; past 3 s stop then start, saying so first. No grace for body composition.
3 DEVICE BUSY — in the sheet, not the screen: "She's already measuring something.", `MEASURING NOW · TRY
  IN A MOMENT` at 32%, not amber.
4 LINK DROPPED — "Lost the band.", `DISCONNECTED · RECONNECTING`; explicit stop, reconnect in place,
  back to "put your finger on". No dialog, no home.
5 NO READING — 60 s with state 'error' or no trustworthy averageHRV: "Couldn't get a clean read.",
  `NO READING · NOTHING KEPT`. Never an invented number.
6 NO BAND — the two band rows are dimmed in the sheet; the screen is never entered. ADD rows unaffected.

## Before ship
! Recovery check is two mutually exclusive tests (ECG for HR/HRV, stress separately): serial with the
  real total, or stress from today's latest reading with its time. ! 72 RECOVERY SCORE is ours, not
  the SDK's: algorithm, bands, "WAS 86 YESTERDAY" basis to be written. ! Waveform only on ECG-capable
  bands. ! progress is 0–100, not seconds; local clock finishes. ! syncPersonalInfo() before body
  composition; older readings marked as computed on the old profile. ! HRV source differs iOS/Android.
! Events: PLUS_OPEN · PLUS_ROW_TAP{KIND} · MEASURE_START{KIND} · MEASURE_CONTACT{MS} ·
  MEASURE_LIFTOFF{T,RESUMED} · MEASURE_DONE{KIND,MS,FIELDS} · MEASURE_FAIL{KIND,STATE} · MEASURE_TO_REPLY
! Acceptance: 60% press a row within 8 s; recovery completion ≥ 70%; LIFTOFF < 15%.
