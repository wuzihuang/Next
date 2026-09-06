# 13 · 昨夜与 Body Battery — THE NUMBER THAT SETS TODAY

Mirrored from node `1CC9-0` (2174 × 6538), then Paper `13A` / `13B` 方案一（ADR 0017）。
**NOT IN V1**: 睡眠详情页、分期图、睡眠分；「几点该睡」「明早会到多少」。
周 / 月已落地：醒来高点的平均，不是加总。主色 lime，不是紫。

## Screens
**01 昨夜 · ONE WIDGET · ONCE A DAY · WAKE + 6H** — panel: `LAST NIGHT · 07:12` · `72` OF 100 ·
`CHARGED +38 · NORMAL CHARGE` (lime) · *About as much as you usually charge. Today can take a
normal session.* · `TAP TO SEE WHY →`. Behind it a two-colour curve: the night in lime, the
day so far in white.
**02 详情上半** — HERO + WHY 72 (4 ROWS · MUST CLOSE · ±0.5) + the next card peeking.
**03 详情下半** — INPUTS (3 INPUTS · 3 TIERS · NO SLEEP NUMBERS) · TARGET · CONFIDENCE · FOOTER.
**04 第一天** — NO CURVE · NO TARGET · NO SKELETON.
**05 解剖** — 5-MIN TICK · PURE FUNCTION · REPLAYABLE.

## Sec 01 · Inputs (each points at a real SDK field)
sleep stages per tick (`sleepLine` first, `sleepStates` fallback) → charge q(t), 深 1.25 / 浅 0.85
/ 床上醒 0.15 · sleep duration only as a ≥4h gate · night HRV (RMSSD from `rrIntervals`, ±25% vs
14-night baseline; missing → m=1.00, confidence −1) · night RHR (5th percentile, +15%/−20%) · MET
(k_a = 0.22 over 1.0) · steps (fallback for MET) · stress (k_s = 0.25, dead-zone 40; missing →
drop the term, no re-weighting, no downgrade) · sport sessions (annotation only, no extra drain)
· wear (heartValue empty ≥ 3 ticks).

## Sec 02 · The math
Five-minute pure replay, from the previous day's close. Veepoo's authoritative sleep stages come
from `VPAccurateSleepModel.sleepLine`: deep 0 / light 1 / REM 2 / insomnia 3 / awake 4. The
original-data dictionary's absent `sleep_states` is never treated as awake.

Sleep recovery is saturating rather than a linear deposit:
`gain(t) = (95 − BB(t)) · (1 − exp(−0.011 · q(t) · M))`, where q is deep 1.25 / light 0.85 /
REM 1.00 / insomnia 0.15 / awake 0. M is the clamped HRV × RHR multiplier.

Awake drain is additive and independently attributable:
`drain(t) = 0.12 + movement(HRR, MET, steps) + autonomic(stress, RMSSD) − restorative_rest`.
HRR, MET and steps observe the same movement, so their maximum wins rather than charging one
workout three times. Stress above 40 and RMSSD below the personal baseline form the autonomic
term, attenuated during exercise. Twenty quiet minutes can restore a small amount, capped at
5 points/day and below 80. No wear evidence holds the previous value; it never spends battery.
The first valid night starts from an explicitly assumed 20. Replay converges because recovery
shrinks as BB approaches 95.

Sleep is recovery input, not a scoring gate. With no previous close and no placeable sleep
window, the first worn daytime tick starts from an explicitly assumed neutral 50; `BB_WAKE` and
the training target stay unset until a real `sleep_start`→`wake_at` window exists.

## Sec 03 · Missing
HRV empty → m=1.00, HRV row not rendered, −1 tier · value-only HRV → LOW, never label MS · not
worn (<4h & no HR) → no score, BB ——, TARGET NOT SET · an off-wrist tick after a score exists
holds that score rather than draining it · worn but <4h → count as it came, SHORT
NIGHT, −1 tier · stress missing → drop term, no downgrade · met all 0 → `1.0 + steps/45`, −1 tier
· HRV baseline <5 nights → LOW, BASELINE n/14 · last tick >90 min → dim + SYNCED HH:MM · >6h → ——.

## Sec 04 · Body Battery → target (档内不插值)
| BB | Target | Optimal | Ring % |
|---|---|---|---|
| 0–19 | 4.0 | 0.0–6.0 | 19% |
| 20–29 | 6.0 | 3.0–8.5 | 29% |
| 30–39 | 8.0 | 5.0–10.5 | 38% |
| 40–49 | 10.0 | 7.0–12.5 | 48% |
| 50–59 | 11.5 | 8.5–14.0 | 55% |
| 60–69 | 13.0 | 10.5–15.5 | 62% |
| 70–79 | 14.5 | 12.5–16.5 | 69% |
| 80–89 | 16.0 | 14.0–18.0 | 76% |
| 90–100 | 18.0 | 15.5–20.0 | 86% |

## Edge cases · 数不出来的时候，宁可什么都不说
1 NO NIGHT DATA — `NO NIGHT ON THE BAND` · —— OF 100 · *Nothing charged last night. No target
until tomorrow morning.* · TRAINING RING · TARGET NOT SET (the morning widget is not rendered).
2 HRV MISSING — `MULTIPLIER 1.00 · NO HRV YET` · 64 · CHARGED +44 · *Reading it plain — no HRV
to weigh it with.* · CONFIDENCE · ONE TIER DOWN.
3 FIRST MORNING — `FIRST READING · LOW CONFIDENCE` · 58 OF 100 · *First night on the band — this
one has a guess under it.* · 20 ASSUMED + 38 CHARGED.
4 STALE — `SYNCED 07:12 · 2H AGO` · 72 (dim) · *72 as of 07:12.* · CURVE STOPS AT THE LAST REAL TICK.
5 SHORT NIGHT — `SHORT NIGHT · COUNTED AS IT CAME` · 41 · CHARGED +19 · *Barely charged. Today is
a light one.* · 3H 20M ON THE WRIST · NO EXTRAPOLATION.
6 MID-DAY RECHECK — `TARGET 14.5 → 11.0` (lime) · 54 · RE-READ 14:20 · *Re-read: 54. I moved
today's target down.* · ONE RE-ANCHOR PER DAY.

## Hard rules
01 5-min tick grid · 02 BB is float, rounded only at render · 03 today's target is frozen at wake;
two changes a day at most · 04 the four attribution rows must close (±0.5) · 05 sleep duration
fields never on screen · 06 `sleepQuality` banned · 07 HRV = own RMSSD · 08 unworn = HR empty ≥3
ticks · 09 the morning widget once a day, `bb_morning_shown_at` on the 04:00 day, written to the
 cloud · 10 >90 min dim + SYNCED; >6h —— · 11 waking recharge ≤ 5/day and only after a verified
 quiet run; sleep recovery cap 95.

## 上线前 (selected)
0.011/0.12 and the movement/autonomic weights are initial calibration values, not clinical
constants · stage weights are product heuristics, not KR96 validation · Body Battery is Garmin's
mark — METRIC_NAMES exists for this · 「CHARGING WHILE YOU WIND DOWN · FULL 06:40」 is the
product's only prediction · confidence words must share 10's tokens · DST days are 23/25 h.
Events: `BB_MORNING_SHOWN{SCORE,DELTA,BAND}` · `BB_MORNING_SUPPRESSED{REASON}` · …
