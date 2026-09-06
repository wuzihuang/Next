# 身体电量充放电与展示审计 · 2026-09-06

> 本文保留修复前的审计结果。后续代码、回归门槛与验收状态见 [修复记录](2026-09-06-body-battery-fix.md)。

结论：**当前不能通过“充电、放电和 UI 正确”的验收。** 数据类型已经丰富，核心思路也有合理部分，但存在可重复证明的时间错位、晨值错误、显示值与归因不一致，以及置信度来源错误。更多传感器字段本身不能抵消这些问题。

本轮交付是审计报告与可重复诊断，未修改产品算法、未部署、未重算线上用户数据。诊断使用当前工作树的生产 Swift/SQL；保留工作区已有改动。临时匿名实数回放保留在本机，不提交原始测量、身份字段、SDK 数据库或凭证。

## 1. 实际检查范围与证据边界

- 源头：Veepoo 原始点、RR→RMSSD、睡眠段及分期、辅助血氧/呼吸/温度、上传与本地归档。
- 计算：当前迁移定义的 `reserve_anchor`、`reserve_replay`、`compute_reserve`、夜间 HRV/RHR、恢复倍率、Swift 实时预览。
- 展示：身体电量 DAY/WEEK/MONTH、Profile、首页、MorningWidget、系统 Widget、目标和预测。
- 数值：生产 Swift 编译执行、生产 SQL 函数在独立临时 PostgreSQL 中执行、真实本地记录的单变量对照。
- 实际数据来源：此前从同一手机导出的 `/tmp/next-sep6-local/local-data.sqlite`，选取最新 Home 对应账号，快照时间 **2026-09-06 16:44:02 Asia/Shanghai**。这是已有快照，本轮没有重新连接手环或重新导出手机。
- 线上 Management API 只读查询返回 HTTP 403，未能核对当前部署函数和完整云端样本。不能把本地代码结果称为线上实际执行结果。
- 本地永久 `VitalSample` 没有 MET；SDK 导出有多个设备分区，又缺少同次绑定证据，未混合其 MET。真实回放明确按 MET 缺省处理，不能宣称已完整复算线上绝对分数。
- UI 诊断提取实际 Swift 方法，以必要的最小模型替身运行。它验证数据与展示逻辑，不是实际屏幕截图、布局或真机手势验收。

## 2. 你的数据很多，但参与算法的范围和覆盖率有限

9/6 实际睡眠为 **00:08–02:17、03:45–12:39**，共 663 个记录分钟，首尾跨度 751 分钟，中间空档 88 分钟。分期线含深睡 163、浅睡 407、REM 88、清醒 5 分钟；663 是记录区间分钟数，不能全部称作净睡眠。

| 输入 | 最新档案中的证据 | 身体电量实际如何使用 |
|---|---|---|
| 睡眠分期与起止 | 2 段、44 个分期 run，真实偏移完整保留 | 主要充电输入，但 SQL 读取的压缩分期串丢掉偏移，见 A1 |
| 夜间 HRV | 342 个有效分钟；占记录分钟 51.6%；分钟均值约 74.11 ms | 使用五分钟 HRV 再做 15 分钟桶中位数；缓存夜间摘要为 68 ms，不使用已有精确分钟档案 |
| 夜间 HRV 缺测 | 321 个记录分钟在此前 SDK 对账中为无效占位，其中 274 分钟连续缺失 | 当前夜间基线资格未体现该连续空窗与覆盖率 |
| 血氧 | 660 个夜间点 | 已保存，不进入身体电量 |
| 呼吸率 | 661 个夜间点 | 已保存，不进入身体电量 |
| 心率 | 当天 152 个归档槽中有 140 个；最终醒来后 48 槽中有 36 个 | 活动放电、RHR、佩戴证据、安静判断 |
| 五分钟 HRV | 当天 55/152 槽；最终醒来后 **2/48** 槽 | 自主神经放电、安静判断、夜间汇总 |
| 压力 | 当天 27/152 槽；最终醒来后 **1/48** 槽 | 高于 40 的部分增加放电；缺测直接不计该项 |
| 步数 | 当天 152/152 槽，最终醒来后 48 槽 | 活动放电，与心率/MET 取最大项，防止重复计费 |
| MET | 上传云端及即时计算有路径，本地永久样本未保存 | 活动放电；本地离线完整回放缺这一输入 |
| 皮肤温度 | 已有本地/云端存储路径 | 不进入身体电量 |
| 距离、厂商热量、运动会话 | 有其他功能使用与保存路径 | 不直接进入 reserve；不能假定另有一份会话额外放电 |

这些槽是实际缓存条目数，不能把缺字段槽直接判为未佩戴。尤其醒后只有 1 个压力槽，**压力归因为 0 不等于这段时间没有压力**；它也可能是缺测加上整数舍入的结果。

缓存的 HRV 基线为 3 晚、RHR 基线为 4 晚，尚未达到 5 晚的倍率启用门槛，故本夜 **M=1.00**。这能解释“已经有大量当晚数据却没有个性化倍率”：每晚样本数与历史有效晚数是两回事。门槛本身可以合理，但每晚是否足够完整、基线是否稳定以及置信度必须一起说明。

精确分钟均值 74.11 与服务端桶中位数 68 是两种统计量，差异不能直接判为算错；真正的问题是身体电量端仍不使用已保留的分段区间，且缺少覆盖率约束。

## 3. 当前公式，算成具体数值是什么样

每五分钟睡眠恢复：

`充入 = max(0, 95 − 当前值) × (1 − exp(−0.011 × 分期权重 × M))`

分期权重为深睡 1.25、浅睡 0.85、REM 1.00、insomnia 0.15；stage 4 清醒转入放电。SQL 按一分钟分期聚合到五分钟槽，可处理槽内睡醒比例。SQL 的 M 是 HRV/RHR 相对各自 14 晚历史的 z 分数调节后相乘，最终限制在 0.65–1.30；Swift 的下限却是 0.70，存在两端契约差异。

每五分钟清醒放电：

`消耗 = 0.12 + 活动项 + 自主神经项 − 安静休息抵扣`

- 活动项 = HRR 分档、`min(0.75, 0.08×max(MET−1,0))`、`min(0.75, 步数/800×0.50)` 三者最大值。
- 自主神经项 = `(0.10×压力超40比例 + 0.08×HRV相对基线下降比例) × max(0.25, 1−活动项/0.75)`。
- 连续安静至少 20 分钟后，休息抵扣 = `0.05×max(0,(80−当前值)/80)`，并限制累计预算 5 点。
- 没有任何有效佩戴/睡眠证据时保持原值；不是凭空扣一整天空白数据。

直接编译当前 `BodyBatteryEngine.swift` 得到以下合成场景。它们是公式的性质，不是对真人应有分数的标定。除倍率行外，RHR=55、HRmax=190、HRV 基线=50、M=1。

| 场景 | 起点 | 结果 | 变化 |
|---|---:|---:|---:|
| 8 小时恒定 q=1，仅隔离饱和公式 | 20 | 68.91 | +48.91 |
| 相同睡眠，M=0.70 | 20 | 59.19 | +39.19 |
| 相同睡眠，M=1.30 | 20 | 76.00 | +56.00 |
| 16 小时久坐，HR70、HRV50、stress30、MET1 | 80 | 56.96 | −23.04 |
| 16 小时相同活动，HRV25、stress100 | 80 | 30.08 | −49.92 |
| 1 小时运动，HR160、HRV25、stress80、600步/槽、MET6 | 80 | 73.16 | −6.84 |
| 2 小时已验证安静，HR55、HRV55、stress20、零步、MET1 | 50 | 47.53 | −2.47 |
| 2 小时无任何佩戴/睡眠证据 | 50 | 50.00 | 0 |

由公式本身即可证明：**安静休息不可能产生净充电**。每槽最多抵扣 0.05，而基础消耗为 0.12，尚未加活动/压力；所以它最多减慢放电。如果产品想表达“安静可恢复身体电量”，就需要改变模型行为；如果只想表达减慢消耗，就应改文案。不能随意加大系数后宣称已经科学正确。

## 4. 已复现的计算问题

### A1 · 高优先级：分段睡眠被压缩，真实 88 分钟空档消失

[OriginDataSync.swift:576](/Users/zihuangwu/Documents/Next/app/NextBody/Services/Band/OriginDataSync.swift:576) 将分期串写为 `stage:minutes`，丢掉 `offsetMinutes`。虽然 [同文件:591](/Users/zihuangwu/Documents/Next/app/NextBody/Services/Band/OriginDataSync.swift:591) 还把真实偏移保存到了 `raw.line`，但 [reserve_replay:92](/Users/zihuangwu/Documents/Next/supabase/migrations/20260903140000_body_battery_realtime.sql:92) 只读取压缩串并累计时长。

9/6 的真实最后醒来是 12:39，压缩分期线却在 **11:11** 就结束。第二段睡眠前移 88 分钟，部分清醒时段变为充电，真实睡眠末段又被当成清醒或缺测。

在隔离 PostgreSQL 中，对同一份实际本地 samples/sleep 保持 anchor=72、M=1、HRmax=187、MET 缺省等全部条件相同，**只替换 run_offset 为原始偏移**。两次回放最后可计分槽均为15:35，与缓存模型曲线末点一致；有后续样本行不代表其含有有效佩戴证据。

| 回放 | 晨值（整数） | 当前值（未舍入） | 累计充电 | 基础清醒净项 | 活动项 | 压力项 | 最后睡眠槽 |
|---|---:|---:|---:|---:|---:|---:|---|
| 现行压缩串 | 86 | 78.4100 | +13.9741 | −6.5040 | −1.0025 | −0.0576 | 11:05 |
| 保留真实偏移 | 87 | 81.9480 | +15.4499 | −4.4640 | −1.0163 | −0.0217 | 12:35 |

当前值差 **+3.5380**。这是时间偏移的受控敏感性结果。缓存实际分数是 77，旧离线回放约 78，说明本地回放输入与线上并不完全相同；**81.95 不是可以发布给用户的“修正后正确分数”**。

### A2 · 高优先级：晨值取首段连续睡眠，半夜醒一下就提前定格

[compute_reserve:339](/Users/zihuangwu/Documents/Next/supabase/migrations/20260903140000_body_battery_realtime.sql:339) 取首个连续 asleep 段末值，未按真实 `wake_at` 取数。

原 SQL 实测：04:00–08:00 连续深睡得到 wake/current=56；仅加入 04:30–04:35 清醒，再继续睡至 08:00，current 仍为 56，但 **wake 变成 26**。训练目标随之从 11.5 变为 6.0。实际晚间恢复接近，却产生悬殊的晨值和目标。

另一算例：21:00–03:00 已醒，当日 04:00 后没有 asleep 槽；fallback 直接拿当前值作为晨值。同一晚睡眠不变，07:00 晨值为 76，17:00 就成了 60。目标冻结的 UI 设计无法补救上游晨值随重算变化。

### A3 · 高优先级：04:00 归因与“昨夜充电”不是同一个时间窗口

[reserve_anchor](/Users/zihuangwu/Documents/Next/supabase/migrations/20260903150000_recompute_body_battery_v2.sql:4) 接前一天 close；[reserve_replay](/Users/zihuangwu/Documents/Next/supabase/migrations/20260903140000_body_battery_realtime.sql:83) 在一个 04:00→04:00 用户日中处理两晚睡眠的交集；`drivers.last_night` 却直接采用这个用户日所有充电累计。

因此它会遗漏“昨晚入睡→04:00”的充电，并可能在晚上加入“今晚入睡→次日04:00”。这是标签/窗口契约错误，**不是已证明同一分钟重复充电**。9/6 缓存算术 `72 +14 −7 −2 +0 =77` 能闭合，但 +14 并不代表完整昨夜从 00:08 开始的充电。

应同时保存跨日连续储量、真实整夜充电量和用户日归因，不能要求同一个 `last_night` 数字兼任三者。

### A4 · 中高优先级：冷启动锚点与缺分期回退不可靠

- 首晚 22:00–06:00 的 8 小时深睡，顺序重放前一天时，因为该睡眠记录按次日醒日存，前日 anchor 选了 50；算出的晨值为 83，并最终显示 `assumed_anchor=false`。明确以首次睡眠假设 20 起算，公式应得到约 74.965，即 75。已有一个中间派生 close 不代表初始假设消失。[reserve_anchor:4](/Users/zihuangwu/Documents/Next/supabase/migrations/20260903150000_recompute_body_battery_v2.sql:4)
- 缺 `sleep_line` 时，fallback 将整个首睡至末醒跨度当作睡眠，未保留真实区间。[fallback_minute:133](/Users/zihuangwu/Documents/Next/supabase/migrations/20260903140000_body_battery_realtime.sql:133) 中同样 240 分钟深睡总量，窗口 4 小时得 56，窗口 6 小时得 67，多充 11 点。
- 非空但完全非法的 sleep_line 会阻止 fallback。该项是输入防御风险，未证明当前用户上传过非法字符串。

### A5 · 高优先级：夜间基线未反映实际睡眠段与数据充分性

[night_hrv_parts:25](/Users/zihuangwu/Documents/Next/supabase/migrations/20260903120000_night_hrv_sleep_window.sql:25) 和 [night_rhr:8](/Users/zihuangwu/Documents/Next/supabase/migrations/20260905090300_indexed_night_baselines.sql:8) 只按首睡至末醒跨度过滤，未排除分段清醒空档，也未优先消费已有分钟 HRV。

一晚一个有效 HRV 桶/心率点就可能计作一晚，14 晚共 14 个点也可满足 14/14 晚基线。基线标准差 <0.5 时直接回到中性倍率，还会导致不连续：合成 14 晚都为 60，当晚 HRV20/RHR90，M 仍为 1；历史仅增加很小的波动后，M 可降到 0.65。应以足够覆盖的夜晚建立基线，并采用明确的稳定尺度下限，而不是将几乎恒定基线直接视为“不作任何调整”。

### A6 · 中优先级：两端公式与端点归因并不完全一致

[BodyBatteryEngine.swift:104](/Users/zihuangwu/Documents/Next/app/NextBody/Services/Band/BodyBatteryEngine.swift:104) 将值 clamp 到 0，但仍累计全部原始消耗。起点 0.1 的高负荷五分钟最终值为 0，drivers 却记下 0.911 的消耗，归因残差为 **0.811**。SQL 会按剩余储量缩放有效消耗，这一端点处理正确。

此外，SQL M 下限 0.65、Swift 0.70；连续安静 20 分钟用五分钟槽和一分钟槽回放也相差约 0.015 点。倍率差异对目前不传睡眠 stage 的实时预览不是已发生的充电偏差，但证明“同一引擎/两端完全一致”的注释不成立。应在共享契约上做差分测试。

## 5. 放电数据链路的其他风险

- **凌晨历史页错位已用生产 Swift 复现。** 9/6 02:00 同步上一用户日 9/4 04:00→9/5 04:00，本应读取自然日页 `[2,1]`，实际 `[1,0]`。可能漏历史原始点并错配睡眠日期。[OriginDataSync.swift:108](/Users/zihuangwu/Documents/Next/app/NextBody/Services/Band/OriginDataSync.swift:108)、[自然日解释:203](/Users/zihuangwu/Documents/Next/app/NextBody/Services/Band/OriginDataSync.swift:203)。未统计真实触发次数。
- **重复同步不能修订已有非空值。** 最新 ingestion 主要只补 NULL；已有 step=0/MET=0 或其他非空旧值，后续修订会确认 unchanged。同一时间 RR 内容增长还可能被拒收。[ingestion:125](/Users/zihuangwu/Documents/Next/supabase/migrations/20260905090000_response_samples.sql:125)、[RR冲突:69](/Users/zihuangwu/Documents/Next/supabase/migrations/20260905090000_response_samples.sql:69)。这证明修订契约有问题，不证明当前用户所有零值都错误。
- **本地没有 MET 与完整原始 RR。** 上传成功后的 outbox 会清空，本地永久档案只保留部分派生指标。[VitalSample.swift:7](/Users/zihuangwu/Documents/Next/app/NextBody/Services/Band/VitalSample.swift:7)、[Repository.swift:904](/Users/zihuangwu/Documents/Next/app/NextBody/Services/Repository.swift:904)。这阻止完整离线复算与源头追溯。
- **RR 无效值过滤会跨空洞拼接相邻对。** 当前 mapper 对 `[80,255,100]` 先过滤再乘 10，生成 `[800,1000]` 并得到 RMSSD200ms。[HealthSampleMapping.swift:138](/Users/zihuangwu/Documents/Next/app/NextBody/Services/Band/HealthSampleMapping.swift:138)。RR×10 单位符合 SDK 文档；需要检查真实坏值是否仅为尾部填充，才能判断实际污染量。

## 6. UI 已复现的问题

| 优先级 | 问题与反例 | 入口 |
|---|---|---|
| 高 | BATTERY CHECK 直接将当前值改回晨值：45→70，但曲线、归因仍为45；没有真实重评、目标更新或次数限制 | [详情:376](/Users/zihuangwu/Documents/Next/app/NextBody/Features/BodyBattery/BodyBatteryDetailView.swift:376) |
| 高 | 实时预览仅替换 hero：高负荷后显示44，归因和曲线仍解释45 | [DataStore:154](/Users/zihuangwu/Documents/Next/app/NextBody/Services/DataStore.swift:154)、[WHY:179](/Users/zihuangwu/Documents/Next/app/NextBody/Features/BodyBattery/BodyBatteryDetailView.swift:179) |
| 高 | 身体电量置信度读自身体成分 `the_call_confidence`；相同手环/睡眠数据可随成分字段变 HIGH/PENDING | [Repository:1036](/Users/zihuangwu/Documents/Next/app/NextBody/Services/Repository.swift:1036)、[详情:351](/Users/zihuangwu/Documents/Next/app/NextBody/Features/BodyBattery/BodyBatteryDetailView.swift:351) |
| 高 | 7小时前身体电量仍显示为 NOW，没有落实90分钟变暗/6小时隐藏 | [详情:138](/Users/zihuangwu/Documents/Next/app/NextBody/Features/BodyBattery/BodyBatteryDetailView.swift:138)、[Profile:268](/Users/zihuangwu/Documents/Next/app/NextBody/Features/Profile/ProfileView.swift:268)、[AIPanel:224](/Users/zihuangwu/Documents/Next/app/NextBody/Features/Home/AIPanel.swift:224) |
| 高 | DST切日错：纽约2026-03-08切到05:00，11-01切到03:00，未保持本地04:00 | [UserDay:27](/Users/zihuangwu/Documents/Next/app/NextBody/Services/Band/UserDay.swift:27) |
| 中 | FULL线性预测到100，而真实恢复渐近95；真实模型生成的整数曲线预测08:05满，同模型该时仅77.51 | [ChargeForecast:79](/Users/zihuangwu/Documents/Next/app/NextBody/Models/BodyBattery.swift:79) |
| 中 | +35、个人常态+70，同一夜Profile说NORMAL CHARGE，Morning说BARELY CHARGED | [固定阈值:47](/Users/zihuangwu/Documents/Next/app/NextBody/Models/BodyBattery.swift:47)、[个人比例:67](/Users/zihuangwu/Documents/Next/app/NextBody/Features/Home/MorningWidget.swift:67) |
| 中 | 以全日最大值切黄白：23:00新峰会把中午明显下降也涂成充电黄；峰时不能代表真实醒来时刻 | [曲线:681](/Users/zihuangwu/Documents/Next/app/NextBody/Features/BodyBattery/BodyBatteryDetailView.swift:681) |
| 中 | 缺曲线时凭空回退07:12；目标SET AT也可能取全日峰时 | [详情:26](/Users/zihuangwu/Documents/Next/app/NextBody/Features/BodyBattery/BodyBatteryDetailView.swift:26)、[Profile:219](/Users/zihuangwu/Documents/Next/app/NextBody/Features/Profile/ProfileView.swift:219) |
| 中 | 月视图没有晨值被写成NOT WORN；白天有佩戴但无睡眠时，可同时计入WORN和EMPTY | [统计:47](/Users/zihuangwu/Documents/Next/app/NextBody/Services/Band/BodyBatteryWindowMath.swift:47)、[文案:502](/Users/zihuangwu/Documents/Next/app/NextBody/Features/BodyBattery/BodyBatteryDetailView.swift:502) |
| 低 | 04/10/NOW/22是固定等距标签，NOW不跟随实际时间；30天实际分成2+7+7+7+7五组，却写四周 | [时间轴:159](/Users/zihuangwu/Documents/Next/app/NextBody/Features/BodyBattery/BodyBatteryDetailView.swift:159)、[月文案:535](/Users/zihuangwu/Documents/Next/app/NextBody/Features/BodyBattery/BodyBatteryDetailView.swift:535) |

Widget 自己确有90分钟过期隐藏；问题是 Publisher 使用各指标共用的 `numbersAt`，其他指标更新可能将旧身体电量标成新时间，不能笼统说它完全没有过期机制。[WidgetGlancePublisher:13](/Users/zihuangwu/Documents/Next/app/NextBody/Services/WidgetGlancePublisher.swift:13)

## 7. 已经合理或验证通过的部分

- HRR/MET/步数描述同一份活动，取最大值避免三次叠加消耗，这是合理的工程去重方向；数值系数仍需标定。
- 睡眠恢复随当前电量升高而减少，不会用固定线性存款一路无限增长。
- 原 SQL 在混合活动一路扣到0时归因闭合误差小于1e−12；输出整数drivers时还分配舍入残差。不能把 UI 的 `Int(value)` 单独误报成当前服务端路径必然出错。
- 无证据不凭空放电；完全无证据且没有有效结果时返回未知，不造一个确定分数。
- 周/月英雄值是有效晨值的平均，不是相加；无晨值不补零。30个70得到70。
- 1/7/30用户日窗口、29天预加载、月窗口从末尾按七天切组符合当前ADR。
- 目标分档表符合PRD；按已经发布的整数晨值分档。19.49→19→4.0、19.50→20→6.0属于既定舍入口径。正常preview路径不直接滑动目标；A2是上游晨值本身的问题。

## 8. 如何更合理地使用这些数据

需要先修复时间和证据契约，再考虑增加模型输入：

1. **保留实际时间。** 使用 `raw.line.offset_minutes` 和 `raw.intervals`；夜间统计统一按实际睡眠段；跨用户日储量连续，整夜充电单独归因；晨值绑定真实 `wake_at`。
2. **保存可回放的输入与来源。** 本地保留 MET，记录每个槽的来源、缺失、覆盖和算法版本；修订非空测量应有明确替换/版本规则，避免旧零值永远占位。
3. **置信度属于身体电量本身。** 至少包含每夜有效覆盖、最长缺口、白天心率/HRV/压力覆盖、合格历史晚数、假设锚点、最后真实观测时间；缺失不是零压力、零疲劳或未佩戴。
4. **把界面显示绑定为同一份计算结果。** 当前值、曲线、归因、时间戳、模型版本共同更新；重评按钮不得改写实测派生状态；取消不可能的100分FULL预测；统一个人常态等级和空状态。
5. **再做标定。** 以一段足够覆盖且包含不同睡眠/工作/运动场景的纵向记录，检验短夜、长夜、午睡、静息、运动、脱腕、跨日的方向与稳定性，并结合用户主观状态和独立参考做验证。基线数据充分与得到有效模型是两个验收阶段。

血氧、呼吸率、皮温可以优先成为**数据质量或个人异常偏离的上下文**，只有验证其在该设备上的可靠性和增量价值后才调节恢复；不能把每个数都强行折算成电量。距离、热量、运动会话与HR/MET/步数重叠，也不应再次相加。压力与HRV可能反映重叠的自主神经信号，当前简单相加是否重复加权属于待验证模型问题，不能仅凭代码认定已经独立计量。

外部官方方法说明支持“用心率/HRV/活动/睡眠估计负荷与恢复”这一方向，但没有证明本项目的 0.011、0.12、分期权重或目标分档正确。这里的判断是对证据范围的归纳，不是复现 Garmin/Firstbeat 的专有算法。[Garmin 方法说明](https://www.garmin.com/en-US/garmin-technology/health-science/body-battery/)、[Firstbeat 资源与恢复说明](https://www.firstbeat.com/en/body-resources/)

## 9. 本轮执行结果与复现

```sh
swift test --package-path app --filter 'HealthSampleMappingTests|BodyBatteryWindowMathTests'
python3 app/tests/diagnostics/body_battery_math_audit.py
python3 app/tests/diagnostics/body_battery_ui_repro.py
bash supabase/tests/body_battery_audit/run.sh
```

- 既有相关 Swift 测试：50个全部通过，说明它们未覆盖本报告中的关键反例，不能当成模型正确的充分证据。
- 新数学审计：编译实际 Swift 引擎，输出合成场景与两项违规；预期退出1，表示现行行为尚未满足报告中的契约。
- 新 UI 审计：提取实际 Swift 方法与表达式，`REPRODUCED` 标识错误已复现，`OK` 标识单项不变量正常。脚本退出0表示诊断顺利执行，不表示 UI 正确。
- SQL 审计：12项中8项 `BUG_REPRODUCED`、4项 `CHECK_PASSED`，预期退出1；仅在唯一命名的临时容器中运行当前生产函数定义和合成用例，不接触线上。不能把缺陷复现包装成验证通过。
- 真实数据对照：使用独立临时库，旧版/保留offset两个回放之间只改变分期偏移，原始数据未提交。

本轮未声称完成生理准确度标定、线上部署比对、当前手机刷新后的分数复算、完整端到端迁移安装测试或真实UI视觉验收。当前应优先修复上述确定性错误，之后再以相同输入重跑审计和完整数据对账。
