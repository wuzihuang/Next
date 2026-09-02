# 10S · 称重录入 Add a weigh-in — rules and edges (mirrored 2026-09-01)

## Hard rules
01 Weight has three sources — HEALTH / MANUAL / BAND — one weigh_ins table, `source` tells them apart.
   No 「秤」 anywhere: V1 has no scale.
02 Stored in kg (numeric(5,2)); LB is display only; switching units converts in place.
03 Range 20–300 kg, fixed: outside it SAVE is disabled and the line shows the range, never "error".
   No 「与上次相差过大」 judgement.
04 Health readings are never adopted silently: confirmed once on screen 03, asked at most once per
   record (health_uuid), swipe = decline. Unique (user_id, health_uuid).
05 Several per user-day are all kept; the latest measured_at counts. Nothing deleted (export shows them).
06 Day assignment per F2: measured_at UTC + sampled_tz; day_key computed; no user_day column.
07 Two entries only: the composition page's top row and NO TARGET's CTA. Not in ME, settings, dock, or
   notifications.
08 Own numeric keypad: one decimal, five characters max. No date picker — back-logging is 09's route.
09 Save is optimistic: sheet closes, number changes, offline queue syncs. No rollback, no dialog.
10 One lime on the sheet: SAVE (or USE THIS). "Enter a different number" is a 55% white text link.
   Height by content, ≤ 78%.
11 Never 「你拒绝了 Health 权限」 or any paraphrase (F5 C2).

## Edge cases · 05 「一个数字输入框能出的五种事」
1 NOTHING IN HEALTH — straight to the keypad, no explanation: "Add a weigh-in · 78.6 KG · SAVE".
2 ALREADY ONE TODAY — no block, no confirm: `ALREADY ONE TODAY` (amber) and "78.6 REPLACES 78.4" above SAVE.
3 OUT OF RANGE — `OUT OF RANGE`, number amber, SAVE disabled, the line "20–300 KG" only.
4 OFFLINE — `SAVED · NOT SYNCED`, "IT'LL GO UP LATER"; sheet closes, page updates, queue retries.
5 FROM HEALTH · LB — bodyMass is a unit quantity: render in HOOP's preference, store kg. "173.3 LB ·
  APPLE HEALTH · TODAY 07:12".

## Before ship
! Board 10 must lose 「秤」 everywhere. ! Staleness threshold (3 days) 拍的; settle with F2. ! When Health
  is read (cold start / composition page / observer) undecided. ! BAND as a source depends on what the
  SDK really returns. ! NO TARGET screen (built). ! "Stays in HOOP. It never goes back to Health." is the
  same promise as the plist strings.
! Acceptance: row → saved P50 ≤ 8 s, ≤ 5 taps; one Health record → one row, one ask (integration test,
  twenty syncs, row count unchanged); five fragments pixel-compared, layout unmoved.
