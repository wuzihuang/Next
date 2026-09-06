# 09 · 燃料详情 Fuel — rules, edges, before-ship (mirrored 2026-09-01)

> **2026-09-05 · Paper 09H / ADR 0014.** This page has DAY / WEEK / MONTH again.
> Day is the clock plus one ungrouped food table. Week is a 7-day total.
> Month is four weeks spoken as a typical day (28 user days), never a monthly
> sum and never a heat grid. The six-card layout, OPEN meal chairs, and the
> "DAY/WEEK/MONTH deleted" line below are historical. Training is unchanged.
> `LOG A MEAL` is an ember state on the food card; tapping it opens a plate
> (Profile `SheetFrame` chrome, page pressed down).

## Hard rules
01 Unknown has one spelling: ——. Only inline values under 14 px (—/145, — G PRO) fall back to one dash.
02 Budget bar range is fixed 0 → today's target. Over target: bar stops at 100%, `660 LEFT` becomes
   `+240 OVER`; no red, no overflow, no bar colour change. Alarm colour is for ALERT.
03 Three macros always independent, never merged into one bar. The card's closing sentence names one
   macro only, and only when the most-behind macro is ≥ 25% of its target short; otherwise not rendered.
04 One amber OPEN slot on the whole page — the next meal by clock. Other unlogged slots are grey OPEN.
05 Suggested value, one formula on both screens: remaining budget ÷ remaining unlogged slots, rounded to
   50. Empty-state breakfast = 1,900 ÷ 4 ≈ ~450; skipped slots leave the denominator.
06 Planned burn (TRAINING · PLANNED) is always a dashed cell, never in BALANCE's measured scale, only in
   the EST hollow dot. When training happens, dashed → solid and the head total moves. Strength burn on
   wrist HR is still an estimate.
07 WHERE THE BURN GOES three items sum to the head's EST; ENERGY BALANCE's OUT derives from the same
   three items' happened part. Mismatch is a bug.
08 Day cut at 04:00; 0:00–03:59 belongs to the previous day, shown as 01:20 +1. Two calendars must not
   coexist with the device's 0:00 day (F7 settles: raw table has no date column; user-day at query time).
09 Week bars colour only closed days; today is a half-height dashed bar until CONFIRMED. Fasted days
   (confirmed intake < BMR×0.5) go in the ledger, not the trend; own colour.
10 `LOG A MEAL` is an ember state on the food card. Tapping it (or a row you can still
   edit) opens a plate over the pressed-down page — Profile `SheetFrame` / `FieldBox`,
   not a field grown into the page itself. Dock voice logging still works.

## Edge cases · 05 「缺哪一块就画哪一块的 ——，别整卡消失」
1 PARTIAL — EATEN TODAY `2 MEALS · NOT CLOSED` (amber) · 990 /1,900 KCAL shown · BALANCE ——.
  "Shown, but not counted."
2 OUT UNKNOWN — ENERGY BALANCE `4H OF DATA ONLY` (amber) · IN 1,240 · OUT —— · BALANCE —— ·
  "TODAY'S BURN NEEDS A FULL DAY OF WEAR. THE MEALS STILL COUNT." Judged by hours of activity data
  synced today, not by wear state. Never fill OUT with BMR.
3 OVER TARGET — `4 MEALS · LAST 20:40` · 2,140 /1,900 · bar full · `+240 OVER — STILL A FINE DAY`
  (ember-pale) · 113%. Capped, not punished.
4 NO TARGET — `NO TARGET YET` · —— /—— KCAL · "Your weight sets the number." ADD IT. (Full screen: 补屏 B.)
5 PAST DAY — `‹ SAT 30 AUG` · ENERGY BALANCE `CLOSED` · −410 `MEASURED · NO ESTIMATE` · CTA
  `ADD TO THAT DAY`. EST dots, OPEN slots, suggestions all gone; back-logging stays open.

## Before ship
! OUT's basis fixed first: OUT = past hours' BMR + measured activity; EST dot labelled INCL. PLANNED 480.
! Edit / delete: every FOOD row tappable (dock prefilled 「把 12:40 那顿改成…」), delete with 5 s undo.
! Sync chain: serial pulls; failure never clears data; card head carries LAST SYNCED HH:MM; disconnected
  OUT freezes at last sync, never drops to 0.
! MARK AS FASTED at the foot of the logged FOOD card (or per-slot 「没吃」).
! DAY/WEEK/MONTH restored (09H / ADR 0014): rolling 1 / 7 / 28 user days; month is a typical day. ! FOOD card claims ESTIMATED once, or rounds to 10 kcal.
! Empty-state ENERGY BALANCE treatment undecided. ! NO TARGET screen (built: NoTargetFuel).
! Wear hours: SDK has no continuous wear state; OUT trust derives from synced activity coverage.
! Events: FUEL_DETAIL_OPEN{STATE} · FUEL_SEG_TAP{SEG} · MEAL_SLOT_TAP{SLOT,STATE} · FUEL_LOG_START{ENTRY}
  · FUEL_LOG_DONE{MS,KCAL,SRC} · FUEL_MARK_FASTED{SLOTS} · FUEL_EDIT{SLOT} · FUEL_DELETE{SLOT} ·
  FUEL_DAY_CONFIRMED{IN,OUT}
! Acceptance: CONFIRMED rate ≥ 55% among detail visitors; OPEN-slot entries ≥ LOG A MEAL entries.
