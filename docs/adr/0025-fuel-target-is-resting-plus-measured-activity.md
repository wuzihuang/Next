# 热量目标是「静息 + 今日已测活动 + 建档偏移」，静息取身体扫描的数

2026-09-10 用户拍板（#29）。燃料卡上的 2705 是过去两周六个实测日全天消耗的中位数加 BULK +300，跟今天动没动无关；它建立在 Mifflin 的 1965 上，而同一台手环一小时前在扫描页印的是 2229。用户看不懂，产品定为：

`TARGET = 全天静息 + 今天截至此刻手环实测的活动消耗 + 建档偏移`，不低于安全线。偏移沿用三档：CUT −500 / RECOMP −380 / BULK +300。安全线是绝对值，按建档性别：男 1500 / 女 1200。它取代 20260906120500 定的「不低于基础代谢」那道底——静息起步的公式如果还压着基础代谢，减脂用户要走够 500 大卡的活动之后目标才会开始生效，等于目标不生效。

静息是**全天值**，不按时刻分摊。零点起就有一个能规划的底数，白天只随活动往上长；什么都没动就只有静息那一份。没戴手环就是没活动：不搬运、不按往常节奏补、不读两周。过去的日子在自己的日末结算，等于静息 + 全天活动 + 偏移，也就是 #26 原话的「当日 E_OUT_FULL + Δ」。`nb.burn_baseline` / `nb.measured_burn` 仍然定义着（测试还在读两周中位数），但热量路径不再调用它们。

静息优先取最近一次手环身体扫描（`body_composition.measurement_source = 'device_bia'`）的 `bmr_kcal`，`measured_at` 不晚于该日的计算时刻；今早扫的数从今天零点起算，明天扫的数不倒灌到今天。没扫过的人才用 Mifflin–St Jeor。这修改了 ADR 0004 里「扫描值保留为设备估算、不静默替代基线」那句：现在它**是**基线，但不静默——`day_fuel.resting_source`（`BODY_SCAN` / `MIFFLIN`）和 `resting_measured_at` 与数字一起发布，热量详情页印成「RESTING 2,229 · BODY SCAN 09-10 · ACTIVE +188 · GOAL +300」。整套口径一起换：`nb.fuel_components` 与 `nb.compute_fuel` 从同一个 `nb.resting_kcal` 取静息，燃料页 OUT、差额、活动页 RESTING 与 TARGET 用的是同一个数。

扫描的代谢值是手环自己的公式，不是测量。SDK 只给 14 个算好的字段，不给阻抗（`VPBodyCompositionValueModel.h`）；同一具身体六天五次扫描，瘦体重五次一样，代谢却在 2159–2240 之间跳，且比 Mifflin 系统性高 200–270。它也不是从自己的瘦体重按 Cunningham 算的（那样只有 1787）。产品仍选它，理由是那是用户建档时亲眼看到的数；取最近一次而不取中位数，理由相同。能改的是什么时候扫（晨起、空腹、同一条件，另开）和取哪一次，不是公式；要自己拟合阻抗到静息代谢，得先拿到原始阻抗并对照参考测量做标定，那是标定项目。

三处 TARGET 仍只有一个来源。手机上的活动值本来就来自 `day_fuel.active_kcal`，每次手环同步后 `settle_now` 重算，所以手机不需要第二套公式，只印服务端发布的分量（`bmr_full_kcal`、`active_kcal`、`goal_offset_kcal`、`resting_source`）；AI 的 `find day` 读同一列，并带回 restingKcal / activeKcal / goalOffsetKcal / restingSource 供解释。「实时」的粒度是一次同步：目标随下一次结算上涨，不在两次同步之间自己爬。

宏量拆分不变。目标仍由取整后的蛋白、脂肪、碳水拼回来，落在公式值的一个 20 kcal 台阶之内；被安全线顶住的日子，2.0 g/kg 蛋白和 0.5 g/kg 脂肪装不进 1500 时会高出安全线，那部分显示在 FAT_G 里，不藏在目标里（20260908160000）。BULK 下这个数是「至少吃到」，不是上限；「今天最多能吃多少」这个问法只对 CUT 成立。

`calculation_version` fuel-1.2 → fuel-2.0、energy-1.1 → energy-1.2，全量标脏按序重放。测试在 `supabase/tests/fuel_target_resting_plus_activity.sql`；`fuel_goal_offsets` / `measured_burn_target` / `daily_activity_load` 里与旧口径相反的断言同步改了。
