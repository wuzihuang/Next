# 10 · 成分详情 Composition — rules, edges, before-ship (mirrored 2026-09-01)

## Hard rules
01 The call's only input is the 7-day EMA change of FAT MASS and LEAN MASS vs ±0.15 / ±0.10 kg. Single-day
   readings never enter the call, only the evidence area.
02 Fewer than 5 measured days → NO CALL + PENDING + empty outlined swatch. 5–6 MEDIUM, 7 HIGH. No fourth
   wording; MEDIUM is never 「基本确定」.
03 MEASURED / DERIVED per field: WEIGHT and BODY FAT % from the scale, FAT MASS and LEAN MASS derived. A
   real composition measurement re-anchors that day as MEASURED; history is not rewritten.
04 The four signals' thresholds are printed on screen; changing a threshold changes the printed line.
05 Only fuel-closed days (FASTED / CONFIRMED) feed the two behaviour signals. UNLOGGED / PARTIAL neither
   vote nor oppose; they only lower confidence.
06 Quadrant named by the two trend signals only; behaviour signals affect confidence. Disagreement →
   HOLDING with n/4 written as is. Never pick the two favourable signals.
07 ENERGY / MACROS / FOOD / TRAINING cards are read-only mirrors of the same day result; tap → that
   day on the detail page.
08 Scale readings day-assigned by their own timestamp; device data by device day; alignment per 09 rule 08.
09 Any call change (word, tier, back to NO CALL) needs a visible receipt naming the signal. EDIT THIS DAY
   and backfill likewise; THAT WEEK cells recolouring counts.
10 No health advice, no body-fat grading, no health score. Direction and confidence only.

## Edge cases · 05 「判定可以变，但不许无声地变」
1 SOURCE GONE — SCALE `LAST READ AUG 21` (amber) · 74.4 `KG · FROZEN` · "APPLE HEALTH ACCESS WAS TURNED
  OFF. NOTHING NEW SINCE." Frozen, not extrapolated. 3 days without a reading → confidence down one tier;
  day 7 → NO CALL.
2 MEASURED ARRIVES — FAT MASS `MEASURED` (lime) · 11.2 `KG · DEXA` · "ESTIMATE WAS 10.5 · THE SERIES
  RE-ANCHORS FROM HERE". History untouched.
3 WEIGHT SPIKE — WEIGHT `OUTLIER · KEPT` (amber) · 75.8 `KG · +1.4 IN A DAY` · "THE 7-DAY AVERAGE BARELY
  MOVED. THE CALL DID NOT FLIP." Shown, stored, marked on its day cell; never deleted.
4 SIGNALS SPLIT — CUT `2/4 SIGNALS AGREE` (amber) · "FAT IS DOWN, LEAN IS TOO. PROTEIN AND BALANCE
  DISAGREE." Trends name, behaviours only lower confidence; 2/4 is written 2/4.
5 BACKFILL — THAT WEEK `3 DAYS RECALCULATED` (amber) · cells recoloured · "YOU LOGGED AUG 21–23 LATE.
  THOSE THREE DAYS CHANGED." A visible receipt is mandatory.

## Before ship
! 5/7 threshold is 拍的. ! Band body composition (electrodes, syncPersonalInfo) undecided; unsupported →
  row not rendered. ! Quadrant names/colours decided only for RECOMP; colour is a value judgement.
! Weight series must be cloud-backed or 「换机即重来」 admitted. ! watchDataDayNumber depth → app-side store.
! WEEK empty state not drawn. ! EXPORT THIS WEEK undecided (compliance).
! Events: COMP_OPEN{VIEW,STATE} · COMP_DATE_STEP{DIR} · COMP_SEG_TAP{SEG} · COMP_DAY_TAP{DATE} ·
  COMP_EDIT_DAY{DATE} · COMP_WEIGHIN_ADD{SRC} · COMP_CALL_CHANGED{FROM,TO,REASON} · COMP_EXPORT{RANGE}
! Acceptance: ≥60% of scale users get a non-NO CALL by day 10; daily flip rate <5%; COMP_CALL_CHANGED
  with empty REASON must be 0.
