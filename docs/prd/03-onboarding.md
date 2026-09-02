# 03 · Onboarding 建档与基线 — screens, sheets, rules, edges (mirrored 2026-09-01)

Head: ONBOARD SPEC · ABOUT YOU & BASELINE · 「最后一屏不说恭喜，说 21.4%」. Six screens in two runs.
NOT IN V1: experience/activity questionnaire, diet preferences, target weight & deadline, task list /
tour, second-scan comparison.

## Screens (copy verbatim)
ABOUT YOU 01 / 03 · First, about you · "We can pull height, weight and birthday straight from Apple
  Health." · Health mark · four chips HEIGHT WEIGHT BIRTHDAY SEX · CTA Sync from Apple Health ·
  "Enter manually instead"
ABOUT YOU 02 / 03 · Does this look right? · "Pulled from Apple Health. Tap any value to correct it before
  we calibrate." · rows Sex / Born / Height / Weight with `HEALTH` (lime pill) or `EDIT` (outlined) ·
  CTA Looks right · "Nothing synced? Just type it in"
ABOUT YOU 03 / 03 · What brings you here? · "Pick one focus. It sets your daily MOVE and FUEL targets —
  change it anytime." · Lose fat / Burn more than you take in · Build muscle / Fuel the work, protect
  the gains · Lose fat + build muscle / Recomposition — slower, but both · CTA Continue · "You can
  switch goals later in Profile"
BASELINE 01 / 03 · Now, your baseline · "Rest your hand on the table and touch the side key with your
  index finger. Hold still." · `INDEX FINGER ON THE SIDE KEY` · CTA Start body scan · "Takes about 30
  seconds"
BASELINE 02 / 03 · Scanning · "A tiny current maps your body — you won’t feel a thing. Keep your fingers
  on the frame." · `BODY COMPOSITION` · 00:24 · "Lift your fingers and the scan restarts."
BASELINE 03 / 03 · Your baseline · "First scan complete — this is day zero." · 21.4 % BODY FAT | 21.3 BMI
  · twelve tiles FAT MASS · LEAN MASS · MUSCLE · MUSCLE RATE · SKELETAL · BONE · BODY WATER · WATER ·
  PROTEIN · PROTEIN MASS · SUBCUT FAT · BMR · CTA Enter NEXTBODY · "Scan again anytime from the Device page"

## The three sheets (TAP TO EDIT · 03)
01 ≤ 62% of the screen; the table underneath keeps its title and one row. 02 Initial value = current
value; Save without a change writes the identical value and source. 03 A real change makes the source
EDIT forever; HealthKit never overwrites it. 04 Save is the only commit; drag-down = cancel, no prompt.
05 Units are account-level; set once here. 06 One-handed: drag area on the right half, Save at the
thumb. 07 Sex has no sheet — inline toggle.

## Hard rules
01 Two counters: ABOUT YOU 01–03 and BASELINE 01–03, never 01–06. Back works within a run; once the
   scan starts, back disappears.
02 Source tag (health / edit / typed) is stored with each field; EDIT fields skip HealthKit sync.
03 HealthKit: read only, four types: sex, dateOfBirth, height, bodyMass.
04 Units are an account setting. 05 Scan is a fixed 30 s countdown, no percent; a lifted finger pauses,
   the second lift in one attempt restarts from 30 with a line. 06 Baseline makes no judgement: no
   colour, no range, no good/high/low. 07 The whole BASELINE run is skippable. 08 Onboarding runs once
   per account.

## Edge cases · 05 「填不下去，和测不下去」
1 NOTHING SYNCED — 02 appears as normal with empty values, tags `ADD` (amber), CTA "Save and continue"
  disabled until all four are filled. No error, no 「同步失败」 — refusal and emptiness are the same on iOS.
2 FINGERS LIFTED — wave fades to amber, `HOLDING · 00:18` (countdown holds, never resets), "Put your
  fingers back — we'll pick it up." Second lift in the attempt restarts from 30 with a line.
3 BAND DROPPED — `BAND DISCONNECTED` · "The band went quiet mid-scan. / Nothing you filled in is lost."
  · 重新连接 → (Connect · 02, then back to BASELINE 01).
4 LOW BATTERY — `BATTERY 8%` · "Charge the band before the first scan — it needs about 15%." · 先跳过，
  稍后再测 →. Gated before the scan starts.
5 OUT OF RANGE — height 90–230 cm, weight 25–250 kg: amber border on the row + "That's outside what we
  can measure. Check it?" Never cleared, never blocks Looks right. The only hard stop is under-18.

## Before ship
! HealthKit read permission is undetectable; branch only on fields returned. ! Under-18 has no exit
  (built: AgeGate at Looks right). ! Sex is binary because BIA is. ! readDeviceFunctions() before the
  BASELINE run; no capability → skip the run. ! "Takes about 30 seconds" to be measured.
! Events: ONBOARD_ENTER · HEALTH_PROMPT{GRANTED_FIELDS} · PROFILE_EDIT{FIELD,FROM} · GOAL_SET{GOAL} ·
  SCAN_START · SCAN_DONE{MS,RESTARTS} · SCAN_SKIP{REASON} · ONBOARD_DONE
! Acceptance: success screen → home P50 ≤ 90 s; 02 zero-edit ≥ 60%; scan first-try ≥ 85%.
