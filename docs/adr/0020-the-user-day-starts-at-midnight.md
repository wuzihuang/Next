# 用户日从本地 0 点开始；每张卡的「日」都是同一个日

2026-09-07 用户裁决（issue #19）。用户日从 **本地 04:00 → 04:00** 改成 **本地 00:00 → 00:00**。同时，二级页和首页卡上所有「日」窗口一律是这个用户日，不再有第二种日：HEART / HRV / STRESS / TEMP / RESPONSE 原来画的是滚动 24 小时，现在和 STEPS / DISTANCE / ACTIVE / 热量 / 训练 / 身体电量一样，从本地 0 点画到现在。睡眠不动——它属于一夜，键仍是醒来那一天。

改这个是因为屏幕自己不自洽。卡上写 TODAY，人读的是零点；账本切在四点，凌晨零点到四点这段时间里每一个累积数字仍然是昨天的。更糟的是同一屏两张卡对「今天」给两个答案：STEPS 从 04:00 起算，HEART 却往回滚 24 小时，于是今天早上的心率卡里带着昨天傍晚的点。用户说的「每个卡片的时间分布不太一样」就是这件事。

四点这条缝原本是为了让凌晨两点四十结束的一夜仍然收在它该收的那天。它不需要为此存在：一夜是 `sleep_nights` 里存下来的一行，键是醒来的日历日，不是从用户日窗口里切出来的。缝挪到零点之后，「醒来那天」和「wake_at 的日历日」永远相等，`nb.sleep_night_is_canonical` 的日期判定再也不会因为四点前醒来而落空。

代价说清楚：一夜横跨零点，所以夜里的恢复被记在两个用户日上。身体电量本来就不靠这条缝算整夜——`nb.compute_reserve` 从 `sleep_start` 到 `wake_at` 逐日相加，`night_charge` 与日内归因分开——所以这条不受影响；受影响的是「日内起点」，它现在是零点或当日醒来时刻中较晚的一个。

## 落地

- `nb.user_day_bounds` / `nb.user_day_of` 改成零点。`public.ingest_band_domain` 里那份手写的 `- interval '4 hours'` 一并改成调用 `nb.user_day_of`，否则零点到四点写进来的 tick 会去弄脏昨天。
- App 侧 `UserDay.boundaryHour = 0`；`VitalsTimelineKind.rolling24Hours` 整个删掉，`MealResponseIndex.Horizon` 的日档变成 `.userDays(1)`。文案 `TODAY · 04→NOW` 和 `LAST 24H` 统一成 `TODAY`。
- `VitalsTimelinePolicy.rolling24Hours` 留着，但它只剩一个用途：最新一行没带值时，往回接多久的读数仍算「现在」。那是 tick 的新鲜度，不是卡的窗口。
- 所有已结算的 `daily_results` 都是按旧缝积分出来的，迁移把每个账号从它最早一天标脏，`nb.recompute_range` 按序重放。
- 零点到四点之间记下的餐和体重是**存下来的事实**，各自带 `user_day`，重放不搬它们；只有此后新记的才落在钟面上的那天。
