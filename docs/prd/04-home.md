# 04 · 主页首屏 下屏双卡

Mirrored from the Paper board while the server was answering. Structure, copy and measurements
are the board's own; the commentary is the board's caption text, not a summary of it.

> HOME SPEC · BOTTOM STRIP · TWO CARDS
> 首屏底下只有两个数：今天该练到哪，今天该吃多少

## 01 · 默认 Default — `2 CARDS · 174PX EACH · 136PX TALL`

Phone is 390 × 844. Top to bottom:

| Element | Size | Notes |
|---|---|---|
| Status bar | 390 × 62 | time `9:41` |
| Header | 358 × 30 | wordmark `NEXTBODY` 129 × 24 + 6 × 6 dot; right block 88 × 26 = band battery 50 × 14 + avatar 26 × 26 |
| AI Screen | 358 × 470 | |
| Bottom strip | 358 × 136 | two cards 174 × 136, gap 10 |
| Dock | 358 × 56 | keyboard 54 × 54 · voice 222 × 56 · camera 54 × 54 |
| Home indicator | 358 × 19 | bar 134 × 5 |

Default AI Screen copy: `STANDBY` · `22:41` · `BODY BATTERY 72%` ·
`CHARGING WHILE YOU WIND DOWN · FULL 06:40` · `TAP OR TALK — I'M UP` ·
readout `HR 72 · STRESS 31 · 12 MIN AGO`.

> 训练在左、燃料在右，顺序写死，不随数据或时间调换——它跟一天的因果顺序一致：先有消耗，才谈补给。

## 02 · 第一天 Day One — `NO TARGET · UNLOGGED · SAME SLOT`

Screen copy: `FIRST RUN` · `DAY 01` · `I DON'T COACH.` / `I READ YOU.` ·
`THE FIRST TARGET LANDS BY MORNING` · `TAP OR TALK — I'M UP`.

> 空态不许藏卡。藏起来的后果是第二天卡片凭空出现，人会以为是新功能上线，而不是「我的数据来了」。

## 03 · 训练环 The Ring — `ABSOLUTE 0–21 · NOT A PERCENTAGE`

Anatomy ring 200 × 200, centre `12.4` over `OF 21`. Legend rows:

| Row | Value |
|---|---|
| TRAINING NOW | 12.4 |
| OPTIMAL ZONE | 13.0 – 16.0 |
| TARGET | 14.5 |
| FULL RING | 21.0 MAX |

Card ring is 80 × 80: 内环 stroke 7.5 / r27, 外圈区间弧 stroke 4 / r35.5, 目标点 r3.

> 环走绝对量程 0–21，满环 = 到顶，不是「完成度百分比」。

## 04 · 燃料卡 Fuel — `EATEN · TO GO / OVER · FILL · 3 MACRO BARS`

Paper **09C**. The card asks two numbers: how much went in, and the signed gap.

| Part | Rule |
|---|---|
| EATEN | 只累计有结论的餐位。PARTIAL 也照常给数——不给数等于罚他记了一半。UNLOGGED 是 ——，FASTED 是 0。 |
| OF TARGET | 额度缩成右上角 `OF 2,900`。没有额度时这一栏不印。 |
| TO GO / OVER | 差额是 `eaten − target`。没到写 TO GO，带负号；刚好是 0 TO GO；多出来换 OVER，带正号。没记不是没到：没有已知摄入就不能说还差或超了，右栏是 ——。没有额度时右栏也是 ——。 |
| FILL | 一条琥珀条，量程 0 → 当天额度，按 EATEN / TARGET 走。满了就停，超额不变红、不溢出。 |
| 3 BARS | PRO / CARB / FAT 各一条，4px 高，各自到顶各自停。颜色固定：紫、绿、橙。标签跟条同色。 |
| NO BADGE | 不画状态徽章、不写鼓励语、不印 LEFT、不印下一餐建议。NEXT_MEAL 只留在数据层给模型用。 |

> 两栏是一对。没到：350 + 2,550 = 2,900。超了：3,140 = 2,900 + 240。

Tap target is the whole card → fuel detail. 卡内不放任何二级按钮.

## 05 · 这条带 The Strip — `WAS 3 CARDS · 216PX → NOW 2 · 136PX`

`CARD` 174 × 136 · radius `--r-card` · padding 12 — `GAP` 10 — `ORDER` TRAINING 在左 · CALORIES 在右 · 写死.
腾出的 80px 全部划给大屏：AI Screen 从 390 涨到 470。这条带不许再要回去。

## Edge cases — `0 是一个断言，—— 是沉默`

| # | State | Balance |
|---|---|---|
| 1 | UNLOGGED | — UNKNOWN · 默认态，永远不会因为「过了午夜」自动变成 0 |
| 2 | PARTIAL | — UNKNOWN · 卡片照常给数，但下游按未知处理 |
| 3 | FASTED | — REAL · 用户亲口说的零 |
| 4 | CONFIRMED | — REAL · 四个餐位都有结论 |
| 5 | NO TARGET | RING — UNCALIBRATED · 灰环画满 21.0，中心 0.0，TARGET NOT SET |

## Hard rules

1. 环走绝对量程 0–21，任何状态下量程不变。
2. 目标点与区间只能由当天的 Recovery 推出（86% → 目标 14.5、区间 13.0–16.0）。
3. 未知永不退化成 0。跨午夜不自动封口。
4. 只有 FASTED / CONFIRMED 投票。
5. 断食日进账本、不进趋势。
6. 两张卡都不下结论：不画状态徽章、不写鼓励语、超额不变红。热量卡上的琥珀条只表达 EATEN / TARGET，满了就停。
7. 布局写死：两卡各 174 × 136、间距 10、整条 358 × 136、radius `--r-card`。
8. 整张卡是唯一热区，落到对应详情页。
9. 这两张卡不做骨架屏、不做加载态。首屏没有转圈的东西。

## 上线前必须成立

- 进食窗口（16:8）在设置里还没有落位。
- 断联与数据陈旧在这两张卡上没画过。大屏读数行的规矩是「最后一次采样超过 60 分钟整行撤掉」，下屏未定。
  ⚠️ Conflicts with board 13's 90min/6hr model — unresolved, see STATUS.
- 进首屏不能并发刷新（厂商 SDK 命令串行，二次 start 直接 DEVICE_BUSY）。
- 21:30 那句「午饭之后还有吗」的触发条件要写死。
- 埋点：`STRIP_TAP{CARD}` · `RING_NO_TARGET_DAYS` · `STRIP_STALE{MIN}` · `FUEL_*`
