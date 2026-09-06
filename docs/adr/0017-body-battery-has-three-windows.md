# 身体电量也有日 / 周 / 月，英雄永远是一天的 0–100

2026-09-06 用户确认：身体电量按 Paper `13A` / `13B` 方案一（CURVE）落地。一级模块落在「我的」身份卡与 COMPOSITION 之间，整块一热区。二级页同一页 `BODY BATTERY`，顶上是 `SegmentedPills`（DAY / WEEK / MONTH）。主色从板上的紫改成产品标准黄（`--lime-1` / `NB.lime1`）。这重开了 `docs/prd/13-body-battery.md` 里「BB 周/月趋势不在 V1」那一句，也重开了 F1「Body Battery 只有面板一个入口、返回只回首页」。

三个英文词和训练 / HEART / RESPONSE 一样。窗口跟训练同粒：用户日（04:00 切日），日是 1 个用户日，周是滚动 7 个用户日，月是滚动 30 个用户日。不是自然周月。

三档说的不是同一句话，但英雄数永远停在 0–100 的一天。DAY 是今天的充放曲线（夜里黄、白天白、lime 点是 NOW），底下 WHY（四行必须加到 now−anchor）和 TODAY'S TARGET（由晨峰定一次，白天不滑）。WEEK 的英雄是**醒来高点的平均**，空天不是 0。MONTH 的英雄是**典型一天的早晨高点**，不是 30 天加总——加总会出现两千，那不是身体电量。空天是空格（热力虚线），不是零。今天的格子和柱是 lime。

从「我的」进，返回回「我的」；从面板进，返回回首页。只记一层 from，和成分页同一条。它仍是从根出发的五个去处之一，不是第三个二级页。

睡眠分期 / 时长 / 分数不上屏。充电词只有 `LIGHT CHARGE` / `BELOW USUAL` / `NORMAL CHARGE` / `FULL CHARGE`。

算术在 `BodyBatteryWindowMath`：周/月平均跳过没有醒来高点的空槽；`weekRolls` 从末尾每 7 天往回切。首页只预载约一天，进这页要自己 `load(days: 29)`。DEBUG `NB_DEBUG_BODY_BATTERY_RANGE=DAY|WEEK|MONTH`。
