# 08 · 训练详情 Strain — rules, edges, before-ship (mirrored 2026-09-01)

Head: TRAINING SPEC · STRAIN DETAIL · RING 0–21 · 「今天练到哪，是今早的恢复说了算」. The page answers two
numbers — today's target and where you are now — and every other block is evidence for them.
No number on the page comes from the band directly; all are computed from the 5-minute points.
NOT IN V1: GPS track/pace · manual session entry · custom target · plans/periodisation · leaderboards.

## Hard rules
01 Training values are computed, never device-given. Only input: readOriginData(dayOffset) 5-min points
   (heartValue / met / stepValue) + readSportRecords. Algorithm version lands with every day row; a
   change affects later days only, no backfill.
02 Resolution is 5 minutes: zone minutes, active minutes, gap lengths are multiples of 5, floored.
   「Z5 4 MIN」 cannot exist.
03 Day boundary is the device's local day (dayOffset=0 from the band); TODAY follows it. One settle per
   day across time zones. (F-series later rules the 04:00 user-day cut — F3/F7.)
04 Session types come only from startSport(mode) or SportRecord.mode. Any other high-HR segment is
   ELEVATED HR with duration and mean HR only — never a guessed name.
05 Sources must sum exactly to the ring; no 「其他」 filler. On mismatch the whole block is —— and reported.
06 Target derives from this morning's recovery; user cannot change it. No recovery → TARGET and OPTIMAL
   ZONE both ——, ring draws only what happened, no target tick, and no 「差 2.1」 sentence.
07 The curve connects only sampled time. Missing point or HR 0 (notWear) breaks the line and is
   never interpolated. Do not shade the hole, label it, or add a DATA MISSING note — an empty
   stretch is just empty.
08 Every failure degrades in place: the block becomes —— plus one reason line. No modal, no full-page
   error, no bounce home. DEVICE_BUSY / TIMEOUT / network share this rule.
09 DAY / WEEK / MONTH are filters of one page (ADR 0015 / Paper 08C A). Same three
   words as HEART. Month is 30 user days. Week/month heroes are finished-day
   averages on the 0–21 scale, never sums — drawn as a number plus a daily line,
   not the 0–21 ring. Empty days stay empty.
10 Commands are serial: at most one read in flight (points → sport records → HRV); reuse a running sync.
11 Home card and this page read the same day result from the same sync; the detail never recomputes.

## Edge cases · 05 「环不动，有五种完全不同的原因」
1 STALE — ring desaturated, hero dim, `AS OF 09:12` under it, `LAST SYNC 2H AGO` (amber), sentence
  "The band has been out of range since 09:12. This is where you were, not where you are." Judged by the
  last successful readOriginData, not by connection state.
2 NO HEART RATE — STEPS bar filled, HR MIN dashed 0, `AUTO HR IS OFF` (amber), "Steps alone can't move
  the ring. Turn continuous heart rate back on and today rebuilds itself." Must name the cause and link
  straight to the switch.
3 NOT WORN — the curve breaks across the unsampled stretch. No amber callout, no
  `DATA MISSING` line: the hole in the line is the whole statement.
4 IN SESSION — SESSION RUNNING 14:32 pill; `SCREEN MISSING · SPEC ONLY`; the button is held until the
  running screen exists (Android opt-ack ≈12 s, iOS returns immediately — no shared optimistic animation).
5 OVER THE RING — ring capped at 21 and amber, `RAW 23.6` once in the sub-line, `RING FULL · 6.5 OVER
  TARGET`, "Way past 14.5. Tomorrow's target will already know about this." Not an achievement, not a
  warning. Whether to notify is undecided.

## Before ship
! Recovery → target mapping curve undecided (86% → 69% of ring is a placeholder); needs the table and the
  recovery formula (HRV / RHR / sleep weights; missing input → down-weight or no score).
! Foundation is auto HR monitoring on (funType=0). Default, pairing-time enable, interval — unconfirmed.
! Source second-level detail and the in-session screen are still missing. WEEK / MONTH
  landed as filters of this page (ADR 0015). Build the in-session screen or disable the
  running-session edge.
! iOS HRV reads the local store written by startReadOriginData; empty before sync is normal. Copy must
  say 「还没同步」, not 「暂无数据」.
! History depth limited by watchDataDayNumber; THIS WEEK missing days are empty slots, not 0, not in the
  7-day mean.
! Over-ring voice and three-day-over target lowering undecided; cap without speaking. HR-zone upper
  formula depends on age; no age → block not rendered.
! Events: STRAIN_OPEN{ENTRY} · STRAIN_RANGE_SWITCH{RANGE} · STRAIN_SOURCE_TAP{TYPE} ·
  SESSION_START{MODE,PLATFORM,MS} · SESSION_END{MODE,SEC,DELTA} · STRAIN_STALE_SHOWN{MIN_SINCE_SYNC} ·
  STRAIN_DEGRADED{REASON}
! Acceptance: ≥80% of 7-day wearers see a non-empty ring daily; first paint ≤800 ms; RECENT LOAD always
  has a value (local history only).
