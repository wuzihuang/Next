# 活动页的 OUT 曲线就是热量页那条消耗线

2026-09-05 用户确认：ACTIVE ENERGY 按 Paper `HY1-0` 落地。一级卡是账本（lime、用户日小时柱、RESTING + ACTIVE = OUT）。二级页日档是英雄 OUT + 五张图。周/月仍走五个仪表共用的滚动窗。

活动页上那条累积 OUT 折线，和热量页日档的青色消耗线是同一条算术：`FuelWindowMath.burnCurve`。坐着平、走着陡，实线端点对齐已结算的 `kcal_out`（`eOutNow`），虚线接到 `eOutFull`，不另造一份消耗。两页只是颜色不同——热量页青、活动页石灰——点和时钟都是日历日 00–24（`clockFraction`）。小时柱才是用户日 04–04。

活动三项（SPORT / STEPS / INCIDENTAL）是相对 MET 分钟摊到已结算活动热量上，不是从厂商 `raw_samples.cal` 加出来的。`ActivityEnergyPolicy.hourlyBins` 继续返回空，避免有人把厂商柱画回去。缺的一项写 ——，不写 0。

算术在 `ActiveEnergyMath`：`outCurve` 直接转调 `burnCurve`；`split` 先收口 `RESTING + ACTIVE = OUT`，再拆活动三项。
