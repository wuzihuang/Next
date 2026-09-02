# 13 · 昨夜与 Body Battery — THE NUMBER THAT SETS TODAY

Mirrored from node `1CC9-0` (2174 × 6538). **NOT IN V1**: 睡眠详情页、分期图、睡眠分；BB 周/月趋势；
「几点该睡」「明早会到多少」.

## Screens
**01 昨夜 · ONE WIDGET · ONCE A DAY · WAKE + 6H** — panel: `LAST NIGHT · 07:12` · `72` OF 100 ·
`CHARGED +38 · NORMAL CHARGE` (violet) · *About as much as you usually charge. Today can take a
normal session.* · `TAP TO SEE WHY →`. Behind it a two-colour curve: the night in violet, the
day so far in lime.
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
`drain(t) = k_b + k_a·max(0, met−1) + k_s·max(0, stress−40)` — three additive independent terms.
`charge(t) = k_c · q(t) · M` per sleep tick; `charge_rest` for resting waking ticks. Anchor A:
`BB_wake = min(20 + charge_night, 95)` on the first night; Anchor B: manual BATTERY CHECK re-anchors
once a day. Otherwise never re-anchor — replay must converge.

## Sec 03 · Missing
HRV empty → m=1.00, HRV row not rendered, −1 tier · value-only HRV → LOW, never label MS · not
worn (<4h & no HR) → no score, BB ——, TARGET NOT SET · worn but <4h → count as it came, SHORT
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
cloud · 10 >90 min dim + SYNCED; >6h —— · 11 waking recharge ≤ 25/day, waking cap 95.

## 上线前 (selected)
k_b/k_a/k_s/k_c are all 拍的 · 1.25/0.85 from literature, not KR96 · Body Battery is Garmin's
mark — METRIC_NAMES exists for this · 「CHARGING WHILE YOU WIND DOWN · FULL 06:40」 is the
product's only prediction · confidence words must share 10's tokens · DST days are 23/25 h.
Events: `BB_MORNING_SHOWN{SCORE,DELTA,BAND}` · `BB_MORNING_SUPPRESSED{REASON}` · …
