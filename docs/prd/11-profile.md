# 11 · 我的 Profile — rules, edges, before-ship (mirrored 2026-09-01)

## Hard rules
01 One second-level page only: Device. Every other row opens a sheet in place, height by content, ≤ 78%.
02 Every row shows its current value on the right; rows without a value (privacy, terms) show a version
   or update date. Never blank.
03 Heat map: one cell a day, one column a week, the composition quadrant palette. Two greys — NO WEIGH-IN
   and MEASURED, NO CHANGE — must differ, not by legend alone.
04 The three numbers under the map are 12-week range totals; the range is written on the card head. Not
   the 7-day EMA; the two never quote each other.
05 Sheet submit semantics by content: single-choice closes on pick (no Save); forms have explicit Save;
   switches apply immediately.
06 Changing the training goal affects tomorrow's target and macros; today is not recomputed. Said both at
   the sheet's foot and in the ME row's sub-line.
07 Units and language are app-side display preferences, never sent to the band.
08 Sign out clears this phone's cache only: no disconnect(), no band data cleared, no unbind. Delete
   account is disconnect() + local device id cleared.
09 Delete asks twice; the second time counts what is lost. Atomic; failure leaves no half state and gives a
   reference number for support.
10 No toast, no banner, no full-page error. Every anomaly shows in the row's value: word, colour, at most
   one sub-line.

## Edge cases · 05 「设置行的值就是它的状态灯」
1 HEALTH REVOKED — APPLE HEALTH row: sub-line `LAST READ AUG 21 · NOTHING NEW`, value `ACCESS OFF` (amber).
  Heat map stays at its last day. No modal.
2 GOAL SWITCHED — TRAINING GOAL row: sub-line `FROM TOMORROW · TODAY IS UNCHANGED`, value RECOMP (lime).
3 REPORT SENDING — REPORT A PROBLEM sheet (ADR 0027, replaces EXPORT MY DATA): the pill reads
  `SENDING …`; failure keeps the form and adds one red line (offline / not configured / rate limited);
  success swaps the form for `FILED · #n` and a Done pill. Nothing leaves the phone but the report.
4 SIGN OUT — pill SIGN OUT + "The HOOP stays paired and keeps recording. / Your data comes back when you
  sign in." Not the same as delete.
5 DELETE FAILED — red-bordered card `DELETION FAILED` · "Nothing was removed. Your account is exactly as it
  was. Try again, or write to us." · `REF 4C81-DE`. The page's only permitted red.

## Before ship
! Heat map source after reinstall (weight series in the cloud). ! 12-week vs 7-day EMA definitions
  cross-referenced. ! Chinese widths must be walked separately.
! Delete timing (immediate vs 30-day cooling) — "There is no undo" must be true.
! Notification switches must reflect system permission state.
! Events: ME_OPEN{STATE} · ME_HEATMAP_TAP{DATE} · ME_ROW_TAP{ROW} · ME_SHEET_SAVE{ROW} ·
  ME_SHEET_DISMISS{ROW,CHANGED} · ME_GOAL_SET{GOAL} · FEEDBACK_FILED{NUMBER,IMAGES} · ME_SIGNOUT · ME_DELETE_CONFIRM{STEP}
! Acceptance: row-open to sheet-close ≤ 5 s for ≥ 85%; CHANGED=false > 60% means the row value is unclear.
