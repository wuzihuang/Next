# F7 · 数据管线 The Pipeline — FROM SENSOR TO SENTENCE

Mirrored from node `1FAL-0` (2174 × 9393). 「从传感器到她开口，中间隔着五次降维」. The band gives
288 points a day; she has ~2.5k of context. **NOT IN V1** — no vectors / embeddings: 「哪天最累」
is ORDER BY, not semantic similarity.

## Sec 01 · The gap (token counts hand-estimated, ±15%)

| What | Size | vs 2.5k | How |
|---|---|---|---|
| a day of 5-min points, 24 keys → 10 | 288 pts · 15,552 tok | 622% | never leaves the server; only feeds Body Battery |
| 90-day daily rollup | ≈4,230 tok | 1.7× | give 90 days as 13 weekly buckets (114 tok) |
| day.get full | ≈233 tok · 37 ledger numbers | 9.3% | ten sub-blocks, one call |
| 7-day columnar + last-week compare | ≈177 tok · 35 | 7.1% | columnar saves 47% vs rows |
| 13 weekly buckets | ≈114 tok · 33 | 4.6% | three months in 114 tokens |
| a typical turn (system + 8 schemas) | ≈3,013 / 5,500 | 55% | context is 305 tok = 12%. Token was never the bottleneck |

Contrast rows: 90 days of raw points into the prompt = 1.4M tok; ledger at N=288 passes ≈100% of
invented numbers; 10k users × 1 yr = 1.05B rows per-point vs 3.65M rows per-day.

## Sec 01′ · 五次降维
1 SDK bridge exit 24 → 10 keys (rebuild the object, do not spread) · 2 5-min → 15-min buckets,
288 → 96 (900 s is the gcd of every IANA offset; store `met_excess_dsec`, not avg) · 3 bucket →
user-day rollup 96 → 1 (283× — the largest step, invisible to the user) · 4 rollup → columnar
90 days → 12 weekly buckets (the bottleneck moves from tokens to the ledger) · 5 tool return →
screen ≤60 → 9–12 per frame (this one is enforcement, not compression).

## Sec 02 · 三条 SDK 事实
① the 5-min event stream cannot be dated (`OriginData.time` is HH:mm only) ② missing is already
0 before ingest (`toInt(value, fallback = 0)`) — 「0 是断言，—— 是沉默」 head-on ③ sync is
all-or-nothing, and iOS HRV only reads the local library.

## Sec 03 · SDK data plane — four dispositions
STORE_RAW: 5-min whitelist scalars (heart/step/cal/dis/met …), BIA 14, sport sessions, battery,
firmware, capabilities, settings. DERIVED: HRV/RR → 15-min RMSSD median (not per-minute rows).
HIDDEN: sleep (only `q_dsec`, the charge integral — not the four columns), skin temperature,
stress (⚠️ not in F5's whitelist — see 上线前). DROP: daytime/spot SpO2, BP, ppgs/ecgs, half-hour
summaries, day summaries, progress events. Overnight automatic SpO2 is not origin: it is stored
in `oxygen_samples` from the SDK oxygen history, clipped to the recorded night. Vendor optical
meal-response history is stored in `response_samples` and rendered only as the unitless
RESPONSE index — never as glucose / mmol/L / 血糖.

## Sec 04–06 · local → upload → cloud
Local: `PRIMARY KEY (device_id, ts_utc)`, ≈117 KB/day, never a CHECK that can void a whole row.
Upload: not PostgREST direct; unit = one user-day columnar block; `record_id = UUIDv5(...)`;
replay, never patch; BLE reads foreground only. Cloud: six layers — raw (120 d) → 15-min buckets →
day rollup → trend windows → BB series; bucket = 900 s not 3600; raw has no date column;
pg_cron stores the next local 04:15 as UTC and scans `settle_due` every 15 min.

## Sec 07 · 聚合金字塔
L0 raw (never leaves) · L1 cell 2h ×12 (day.get `s`, charts only) · L2 day card · L3 bucket run
(range.get bucket=d) · L4 period (bucket=w) · L5 rank hits (range.get rank — this *is* the
RAG replacement) · ctx pre-injected block (108 tok, the zero-call answer to 「我现在怎么样」).
Route table: PICK EXACTLY ONE ROW. Rank synonyms: a closed enum (tired | …).

## Sec 08 · 账本容量才是真正的预算 — 这块板最重要的一节
Monte Carlo: under F4's free derivation (any pair's difference / percentage), an invented number
passes the audit **36.5% at N=30, 60.7% at N=40, ≈100% at N=288**. Ruling: **freeze the
derivation whitelist server-side** — every on-screen `v` is a ledger original with a `from`
pointer, tolerance 0.05, zero derivation. 「她想说的差值，服务端必须提前替她算好」. Hard cap
**N ≤ 60**, trimmed in a fixed order (series first) with `trimmed:true`.

## Sec 09 · shapes, gaps, forecasts
Bucket width is a function of span, not a parameter. A week with two unworn days: buckets stay,
dates stay continuous, value `null`, plus a `cov` string ('oonnoot'). Array values go to charts
only; text may only quote `agg / dlt / rank`. `not_synced` and `out_of_retention` look identical
at the SDK (both empty) — the fourth state.

## Hard rules
01 pull 5-min points with readOriginData(dayOffset), never the event stream · 02 missing-value
reconstruction at ingest only (0 → null for hr/met/stress/temp) · 03 out-of-range → NULL the
column, never drop the row · 04 the whitelist rebuilds the object (`pickOrigin`, ORIGIN_ALLOW ×10)
· 05 HIDDEN has four leak surfaces: screen, DB, export, **tool returns** · 06 local key
(device_id, ts_utc) · 07 overwrite only by rev · 08 bucket 900 s, store integrals · 09 **raw 表不
许有任何日期列** · 10 recompute is a watermark · 11 **N ≤ 60**, server-counted, `trimmed:true` ·
12 fixed curve point counts, no LTTB / percentiles.

## 上线前 (selected)
【阻塞级】stress is not in F5's whitelist but BB's discharge term k_s is hard-coded — needs a
ruling · F4's 「两个账上数字相减 / 百分比」 must be rewritten · units to calibrate on device
(`disValue` m vs km …) · F2's two BB sentences cannot both be true · two backends have drifted
into two schemas · the vendor FMDB already holds SpO2/glucose/ECG/BP history on the phone.
