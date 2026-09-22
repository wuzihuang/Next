# NextBody HOOP

The iOS app and Supabase backend for the HOOP band. One root (Home), five detail pages, and a panel that is the only place the product speaks.

## Language

**手势所有权 (gesture ownership)**:
One touch has exactly one owner for its whole life. Once the page drag is recognized, it owns the touch until the finger lifts; every control underneath is cancelled, not deferred.
_Avoid_: 手势冲突 (that is the symptom, not the rule), 并行手势

**翻页拖动 (page drag)**:
The horizontal drag that turns Home between its two pages. The axis locks on the first points of travel; a vertical touch never becomes a page drag.
_Avoid_: swipe, 横滑 (ambiguous about ownership)

**点按 (tap)**:
A touch that never moved beyond the touch slop and was claimed by no gesture. Only a tap may fire a hot zone.
_Avoid_: click, 点了卡片 (says the action, not the gesture kind)

**热区 (hot zone)**:
A card's whole surface as the one tap target — no second-level button inside a card. The strip's two cards and page two's instrument cards are hot zones.
_Avoid_: 按钮 (a card is not a button; it carries a hot zone)

**探点 (probe)**:
A recognized horizontal drag on a vitals detail chart card that names one recorded sample. Vertical travel on the same card remains page scroll; lift returns the readout to the window's last sample. A gap is named `——`, never a value between ticks.
_Avoid_: 滑动 (that word already names 翻页拖动), scrub, tooltip, 让英雄区跟手

**标线 (marker)**:
The vertical dashed line on a probed chart card. It sits on the probed sample's x, never between samples.
_Avoid_: crosshair, cursor, 准星

**包络 (envelope)**:
A time-sliced occupancy of measured values. Each 15-minute slot paints only the value bands that have ticks; a hole like 70–75 stays empty. A slot the band skipped is absent.
_Avoid_: min–max fill, connecting the slot's lowest tick to its highest across empty values

**夜间 HRV (night HRV)**:
The night's RMSSD over the band's recorded sleep window. It belongs to the night (the SLEEP surface), not to a page-two instrument of its own. The sleep page's NIGHT HRV tile is its home. The HEART page may draw the same-clock RMSSD as a companion envelope, not as a page-two card and not as a second night number.
_Avoid_: 睡眠 HRV as a second number, last-night HRV as its own vitals card, daytime RMSSD as a vitals instrument

**食物反应点 (Food response point)**:
A unitless wrist optical point on page two. The card label is RESPONSE; the number is the latest measured point. The detail page has DAY / WEEK / MONTH rolling windows (last 24 hours / 7 user days / 30 user days), not calendar weeks or months. Day draws a 15-minute occupancy envelope like HEART; week and month are one mark a user day, empty days left vacant. After five valid days the page compares against this person's own daytime median (Near is ±8%). Day's hero is the latest point; week and month heroes are the arithmetic mean of the daily means. The hero is a partitioned dial: Below / Near / Above, the needle on the lit segment. It is not a blood concentration and carries no mmol/L or /100.
_Avoid_: 血糖, 代谢压力, metabolic load, MEAL as the card label (that word belongs to fuel), 自然周 / 自然月, 把周/月顶上的数写成中位

**夜间血氧 (overnight SpO2)**:
Automatic oxygen readings taken during the recorded night only: the night's mean, its minimum, and the curve on that night's clock. Not an apnea grade. On the HEART page the same night points ride as a companion on the heart clock; daylight stays empty.
_Avoid_: 血氧 as a daytime, manual, or health-glance reading on the sleep page; 呼吸暂停 as a on-screen result

**睡眠页 (sleep page)**:
睡眠的二级页，按日 / 周 / 月三档**滚动**窗口呈现（最近 1 夜 / 7 夜 / 30 夜），不翻页。日档印出那一夜的分期、夜间 HRV 与夜间血氧；三档都印睡眠分数，并可拆解到四组。RESPONSE（ADR 0012）与 HEART（ADR 0013）也有同一套三档（1 / 7 / 30 用户日；日档从本地 0 点到现在，不是滚动 24 小时——ADR 0020）。热量页（ADR 0014）用同一组英文词，窗口是 1 / 7 / 28 用户日，月只讲典型的一天。其余五个 vitals 仍由 `VitalsMetric.timeline` 写死。睡眠周/月的英雄数是中位；RESPONSE 周/月是平均；HEART 周/月是日中位的中位。
_Avoid_: sleep report, RESTORATIVE as a badge, 自然周 / 自然月 (窗口是滚动的), 把日/周/月再推广到其余五个 vitals, 把热量的月窗抄成 30 天

**睡眠纠正 (sleep correction)**:
本人给某一夜重新指定的 start / end，写在 `sleep_nights.corrected_start` / `corrected_end`，由触发器发布成 `sleep_start` / `wake_at`，手环原始窗保留在 `raw.recorded_start` / `recorded_end`（ADR 0024）。纠正保留原始分期的钟点，并从新窗重新读取已有心率、HRV 等生理数据。新窗内未测得分期的分钟标为「未分期」，不猜 REM、深睡或浅睡；用户申报时长与实测分期覆盖分别标记。下一次同步保留用户窗，吸收新的真实观测；清除纠正可恢复手环原始窗。
_Avoid_: 把纠正后的窗说成测量, 把未知分期当浅睡或清醒, 用补记生成心率或 HRV

**睡眠补记 (reported sleep)**:
本人补充缺失的一夜，按醒来日期归档，支持最近 30 天。AI 确认与睡眠页按钮共用 `create_sleep_window`；已有夜不能被创建覆盖。`raw.source=user_reported` 区分申报与设备记录；申报时长可以参与时长计算，未测得的分期不进入结构评分或被当作实测充电证据。
_Avoid_: AI 测得, 凭睡眠起止推断真实 REM / 深睡 / HRV

**睡眠分数 (sleep score)**:
0–100，服务端每夜结算一次并落 `night_score`，由四组合成：时长 25%、结构 25%（深睡占比 / REM 占比 / 醒来次数）、恢复 35%（夜间 HRV / 静息心率 / 夜间血氧 / 睡眠呼吸率）、规律 15%（入睡时间偏离个人中位）。阈值写死在打分函数里并带 `score_version`，改版即全量重算历史。缺项在组内重新归一——只要那一夜有记录就必定出分；完全没戴的夜不出分。HRV 与静息心率分别按此前 28 夜中的有效测量夜数，在 14→28 夜之间向个人基线校准；规律组从第 3 个有效入睡时间起发布床时中位并计分（sleep-v1.3，2026-09-09；此前为 14）。时长与结构组永不校准。二级页显示缺项后实际权重、样本覆盖率和最长缺口；分数可计算不等于整夜测量完整。
_Avoid_: 睡眠质量 / sleep quality (SDK 的 `sleepQuality` 是另一个东西：0–4 的五星字段), 把它说成临床结论, 在一级卡上解释它的缺项

**健康账号 (health account)**:
个人健康历史的归属主体；相同的已验证邮箱对应同一个健康账号，登录方式本身不构成另一份健康身份。
_Avoid_: 把 Apple 登录、邮箱登录分别称为不同用户

**手环归属 (band ownership)**:
一只手环与一个健康账号之间的有效归属关系；第一版一个账号同时只拥有一只有效绑定手环，不支持临时共享。
_Avoid_: 蓝牙连接、手机配对

**陪伴天数 (companion days)**:
这个健康账号上，最早一次腕上采样或最早一次手环归属（含已解除的行）起到今天的用户日个数，含当天。设备页石灰卡上的 WITH YOU。不是当前 `devices` 行的 `bound_at`——换 BLE 标识、模拟器种子手环抢绑，都不许把陪伴清零。不是连续佩戴，也不是手环还能存几天历史，也不是电量还能用几天。缺起点画 ——，不编一个数。
_Avoid_: ON DEVICE, 在设备上, 把 saveDays 印成陪伴, 把最新一次绑定当成第一天, streak

**手环转让 (band transfer)**:
手环归属从一个健康账号明确交接给另一个健康账号；转让前的健康历史仍属于原账号。
_Avoid_: 换账号、重新连接

**电量趋势 (battery trend)**:
手环电量随时间的折线，由每次电量上报、充电接入/拔出、以及连接通断记录而成。电话没听到的长间隔不拉直尺到 NOW，而是按放电曲线估算（先撑住再掉；充电则先快后慢），虚线画出；首次连接叠在同一分钟的旧包+新读数当虚点丢掉。SDK 带电量、充电态 unknown 的脏包不写入、不进图，旧日志加载时清掉。过夜列对齐睡眠页的 sleepStart→wakeAt，不是切日那一刻，也不是充电时段。曲线与 HEART 一样可探点。趋势卡底下一行淡字是学会的斜率外推的时刻（EST · FULL / EST · EMPTY），没学会就不写；不是规格书 10 天，也不是 150 mAh 除以假设电流。学会放电斜率后，同一张卡多一格 LEFT：还能用的整天或小时，来自同一条斜率（`BatteryDrainMath.left`）。没学会、格数固件、正在充、已充满都不写 LEFT。设备页大数字仍是最后一次真读数。还在充但已 100%（或 4/4）写 Charged / 已充满，不写充电中——固件常常不发 `.full`。设备页黄色石灰卡上画近 7 天放电折线（碳线），旁标 LEFT。点折线打开趋势页（`Destination.battery`）。不是另做一张碳黑电量环。首页电量 pip 仍进设备页。不是 Body Battery，格数固件也不把格数画成百分比。
_Avoid_: Body Battery, 把 0–4 格写成 %, 把没听到的时段画成水平直线, 把过夜画在切日那一刻上

**训练负荷 (training load)**:
当天累积的训练负荷，0–21 的产品估算，由服务端从五分钟 tick 结算得出（心率区间负荷与运动负荷取其大者，见 ADR 0004）。它是一个每日标量，不是时长也不是一场运动。二级页有日 / 周 / 月三档（ADR 0015）：周是已结束天的平均，月是典型一天，都不加总。
目标和逐次运动贡献由 `daily_training.evidence` 同版发布：目标以完成夜的睡眠时长和恢复分为主、醒来储量和近期负荷为辅，当前储量有新鲜记录时可进一步下调，恢复后逐步回升；旧读数保留已有电量限制并标记时间，缺失睡眠不虚构目标。运动按实际观测区间入账，力量训练的模式/时长证据也可计入，未结算显示待同步。每次运动的增量与普通活动明细加总到当天环值，不能把每场独立压缩后的分数直接相加。
_Avoid_: 活动 (重载成三样东西), 训练量, 运动强度, 把它说成临床压力测量, strain, 周月加总

**活动分钟 (active minutes)**:
当天 MET ≥ 3 的 tick 折算出的分钟数，服务端结算的每日派生值。它与训练负荷是两个不同的数，不能互相换算或互相印证。
_Avoid_: 活动, 运动时长 (那听起来像一场运动的时长), 锻炼分钟

**运动会话 (sport session)**:
一次有开始与结束的运动，包括手环 sport-mode 实时记录和本人补记的历史窗口。实时观测携带 `session_id`；补记写入 `manual_sport_sessions`，由 `log_sport_session` 验证最近 30 天、已经结束且不重叠的窗口。负荷都由同一训练 ledger 按真实心率 / MET 计算，补记归属替换原日常活动权重，不额外叠加一遍。`daily_training.evidence.sessions` 发布每个用户日的覆盖和负荷贡献；完全无观测也保留申报记录，负荷为未知。后续同步可以补足证据。
_Avoid_: 把匿名高心率段当成用户启动的会话, 凭运动名称生成心率, 把缺失负荷写成零

**睡眠呼吸率 (sleep respiration rate)**:
手环在记录到的睡眠窗口内测到的每分钟呼吸次数，属于那一夜。本产品没有日间呼吸监测。
_Avoid_: 呼吸 (会被读成日间指标), 呼吸监测, 把它当成呼吸暂停结果

**手环原始耗卡 (vendor calories)**:
手环自报的 tick 级卡路里，与本产品的消耗口径不是同一个数——展示用的消耗由服务端从 MET 与体重算出（`day_fuel.kcal_out`），厂商值的基础代谢部分不可分离，因此不与之相加（ADR 0004）。引用原始值时必须说明它是手环自报。

**摄入目标（TARGET）** 只有一个数，`day_fuel.target_in`：全天静息 + 今天到此刻手环实测的活动 + 建档偏移（CUT −500 / RECOMP −380 / BULK +300），不低于男 1500 / 女 1200 的安全线（ADR 0025）。静息取最近一次身体扫描的 `bmr_kcal`，没扫过才按体重估算，`resting_source` 说明是哪种；燃料页 OUT 与 TARGET 用同一个静息值。它随每次同步后的结算上涨，不动就只有静息那份，没戴手环就是没活动。手机与 AI 都不另算一套。
_Avoid_: 消耗, 今天烧了多少, 把它与 kcal_out 混用或互相校验

**活动热量 (active energy)**:
首页第二页 ACTIVE ENERGY 卡与它后面的二级页。一级卡与二级日档英雄均为当天已过的 ACTIVE；小时柱、日柱和周/月统计也只使用活动分量。观测到零活动就不画柱，整窗缺观测保留 ——，静息只在明确标记的 OUT 账本与分项出现。活动三项是 SPORT / STEPS / INCIDENTAL，按相对 MET 分钟摊到已结算的活动热量上，三项加总等于活动，再加上静息等于 OUT。累积曲线与热量页 OUT 共用 `FuelWindowMath.burnCurve` 的同一组点（ADR 0016）；主色 lime。缺项是 ——，不是 0。厂商 tick 卡路里不进柱、不进线。
_Avoid_: 把手环 raw cal 画成柱, 另造一份 kcal_out, 把缺项印成 0, 用琥珀或青色当这张卡的主色

**零碎活动 (incidental)**:
用户日里 MET 高于静坐（1.0）又够不上走路（1.5）的五分钟 tick：站着、家务、挪动。不是一场运动，也不是一次走路。没有这类 tick 就是 ——。
_Avoid_: default, NEAT 当成产品词, 把坐着的 BMR 算进来

**二级窗 (detail window)**:
二级页上的 DAY / WEEK / MONTH。三个英文词共用；粒和英雄数按仪器各算——热量窗月是 28 用户日，其余数日子的月是 30，睡眠数夜。不是自然周月。
_Avoid_: 自然周 / 自然月, 把七套 Range 当成七种窗口, 把英雄数的算法合成一套

**训练窗 (training window)**:
训练页上的日 / 周 / 月。滚动用户日：1 / 7 / 30，与 HEART / RESPONSE 同粒，不是热量页的 28。英雄数永远是 0–21 的一天：周是已结束天的平均，月是典型一天，都不加总。空天是空格不是 0。主色是主题黄 lime，一级卡和二级页同一套，Z4–Z5 与最重一天 ember。卡路里标 estimate。
_Avoid_: 自然周 / 自然月, 周月加总, 把空天画成 0, strain, 青色训练环, 一级二级两套色

**身体电量窗 (body-battery window)**:
身体电量页上的日 / 周 / 月。滚动用户日：1 / 7 / 30，与训练同粒。英雄数永远是 0–100 的一天：日是此刻的储量，周 / 月是实际有效晨值的平均，都不加总。空天是空格不是 0。主色 lime；曲线按相邻实测点的升降着色，上升黄、下降白，缺口不连线。整夜充电与本地 0 点以来的恢复分别统计。恢复包括真实睡眠与持续静休；生理负担会加速消耗并减弱睡眠恢复。训练建议在睡眠 / 恢复基础目标上受当前电量限制，疲劳时降低，休息恢复后逐步回升，已完成负荷保持原值。当前值、归因、曲线和观测时间取同版计算结果；数据覆盖置信度独立于身体成分，估计起点另行标明。一级模块在「我的」身份卡与成分之间，整块一热区。此页不展示睡眠分期、时长或分数。
_Avoid_: 自然周 / 自然月, 周月加总, 把空天画成 0, 紫色充电, 睡眠分期/时长/分数, 把周月说成两千

**热量窗 (calorie window)**:
热量页上的日 / 周 / 月。滚动用户日：1 / 7 / 28（四周），不是自然周月，也不是 HEART / RESPONSE 的 30 天。日档是当天的钟加一份不分餐的食物表。周档英雄数是七天加总。月档只讲典型的一天（四周「每天平均」的再平均），不说月加总。表内数字定宽、不换行；五位数上下排，不并排。IN − OUT 的数叫 DIFF / 差额，不是热力图上的空窗。日档消耗线跟当天的步数走，不是一根斜尺；活动页的累积 OUT 用同一条线（ADR 0016）。
_Avoid_: 自然周 / 自然月, 七万级月加总, 热力格, 把月窗做成 30 天, 早餐/午餐/晚餐分组, 五位数并排, 空窗 (那是热力图空格), 柠檬绿 LOG A MEAL pill, 记一餐回 dock

**睡眠分期 (sleep staging)**:
一夜之中每个时段各处于哪一个睡眠阶段——深睡、浅睡、REM、清醒。它是一条带时间位置的序列，不是一组总数；说"分期"而不指明落点，就会和分期总量混淆。⚠️ 一夜有没有 REM，由**那条记录自己的** `VPAccurateSleepModel.accurateType` 决定：1（精准睡眠）会给出 stage 2，0（普通睡眠）只给深睡与浅睡。设备级的 `VPPeripheralModel.sleepType` 不是判据——同一只手环连续几夜可以一夜有一夜没有。缺 REM 的夜是"没在测"，不是"没有 REM 睡眠"，所以那一段整个不画。
_Avoid_: 分期 (单说这两个字指代不明), 睡眠质量, 把深浅睡的分钟数称作分期, 把 REM 缺失说成这台设备不支持

**清醒证据 (awake evidence)**:
App 进入前台的时刻，存在本机、只留 48 小时，1 分钟内的反复切换算同一次。它是手环拿不到的一条输入：一夜被切在落进这一夜的第一个前台标记上（入睡后不满 45 分钟、或距手环自报 wake 不足 5 分钟的标记不算），所以人已经在看屏幕的那些分钟不再被记成睡眠（ADR 0021）。它只会拿掉手环多记的分钟，永不新增睡眠，也永不改入睡时刻。
_Avoid_: 屏幕使用时间, 活动检测, 把它当成一次主动测量, 用它改 sleep_start

**后台拉取 (background pull)**:
App 不在前台时，系统按 `BGAppRefreshTask` 把进程拉起来做的一次同步：读手环今天的 tick、上传、请服务端结算今天、读回、重写小组件的 glance。只在主屏上放了小组件、本机已登录且绑了手环时才排下一次；没有小组件就没有读者，不点亮无线电。`earliestBeginDate` 是距上一次成功同步 30 分钟的地板，不是时刻表——真正什么时候跑由 iOS 决定，用户从多任务划掉 App 后到下次打开前不会跑。它不算任何数：身体电量仍只在服务端结算（ADR 0026）。回到前台的那一次拉取叫 `.resume`，不受设备页同步频率约束（地板 1 分钟）。
_Avoid_: 后台计算 (手机不算数), 每 30 分钟一定刷 (系统只保证不早于), 静默推送 (APNs 未配), 小组件自己去拉 (它没有会话)

**分期线 (stage line)**:
睡眠分期的存储形态：手环自报的连续阶段段落，存成 `阶段:分钟` 的紧凑串（`sleep_nights.sleep_line`），如 `"1:84,0:60,1:110,4:4"`。hypnogram 与首页那条 `SleepStrip` 都只画它，绝不由 App 重新切分。这个字段是后加的，更早的夜读作 NULL。
_Avoid_: 睡眠曲线 (SDK 的叫法，和图表里的曲线撞名), 把它和分期总量都叫"分期"

**分期总量 (stage totals)**:
整夜各阶段的分钟数汇总（`deep_minutes`、`light_minutes` 等），不带时间位置。分期线缺失的夜只剩它，此时只能画占比、画不出 hypnogram。
_Avoid_: 分期, 深浅睡结构 (听起来像有时间轴)

**皮温 (skin temperature)**:
手环测到的腕部皮肤温度，°C，日常落在 32–35 之间，夜里在被子下高于白天。它不是核心体温，读数在 33 上下是正常态而不是低体温；这张卡从不判断发烧。
_Avoid_: 体温, 发烧, 低于 36 就说低

**夜间皮温范围 (personal night range)**:
本人最近 28 天里最后 14 个有效夜的夜间皮温均值，取中位数 ± 2·MAD（半宽不小于 0.2 °C）得到的区间。至少 5 个有效夜才成立，当夜不进自己的范围。TEMP 卡的结论只有一种：昨夜均值落在这个范围之内、略出（一个范围宽度内）还是远出，白天的 tick 不参与判定。
_Avoid_: 基线 (那是一个点，白天的 tick 对着夜里的一个点比永远偏高), 正常范围 (听着像临床), DEVIATION / 异常 (听着像诊断)

**有效夜 (valid night)**:
睡眠窗口不短于 3 小时、且窗口内至少 60% 的五分钟槽有皮温 tick 的一夜。不满足的夜不进范围样本，也不出当夜结论。
_Avoid_: 有数据的夜 (半夜摘表的夜有数据但不算)

**佩戴日 (worn day)**:
一个用户日里，有腕上证据的五分钟槽不少于当天已过槽位的一半。未结束的今天从本地 0 点计到现在；已结束的日子按 288 槽。腕上证据是心率或明确的传感器佩戴，不是连过一次蓝牙。它不是有效夜：夜里摘去充电、白天没戴满，这一天不成立。
_Avoid_: 火花, streak, 连续打卡, 把有效夜当成这一天的佩戴

**焰 (flame)**:
首页名字右边的一枚标记，旁边至多一个阿拉伯数字、不写「天」。石灰带数字 = 连续佩戴还在；琥珀无数字 = 刚断一天；灰无数字 = 已冷或从未连上。只活在这一处，热力图仍是成分方向。产品不在这里印字。
_Avoid_: 火花 (那是面板上的多指标趋势线), badge, 活动圆环, 一排灯, 把琥珀当成续命

**连续佩戴 (wear run)**:
从今天往回连着成立的佩戴日个数；今天一旦自己也是佩戴日，立刻计入。一个已结束、且不是佩戴日的用户日把它断开，数字立刻没有。下一次佩戴日从 1 再计。
_Avoid_: streak, 火花, freeze, 打卡

**昼夜差 (day–night gap)**:
当天白天皮温均值减去当晚夜间均值。只做描述、暴露给 AI 引用，不进任何评分或负荷公式（ADR 0009）。
_Avoid_: 训练压力 (词表里没有这个词；训练负荷是 0–21 的服务端标量), 把它当运动强度

**主动测量 (active measurement)**:
用户从加号菜单发起、需要手指按住侧键、有开始有结束的一次手环测量。第一版只有两种：平衡检查（40 秒脉律，得出 rest / drive / even 的自主神经倾向）与身体扫描（30 秒 BIA，14 个字段）。被动 tick（心率、压力、皮温等）不是主动测量；体重录入是记录，不是测量。
_Avoid_: 压力测量 (固件拒绝主动压力腿，产品里没有它), 测一下 (不区分主动与被动), 把体重录入算进来

**测量记录 (measurement record)**:
一次成功完成的主动测量留下的一行：时间、类型、摘要值。身体扫描的记录是 `body_composition` 里 `device_bia` 那一行；平衡检查的记录只存摘要（结论词、心率、节拍数、离散度），不存逐拍序列。失败、未读到、中途摘表的尝试不产生记录。
_Avoid_: 心电记录 / ECG (产品不呈现也不解读波形), 测量历史 (听起来像被动曲线的时间窗), 把面板上那个 widget 当成记录

**建议页 (advice face)**:
首页根上的第三张脸。竖向上滑打开、下滑关闭；不是第六个详情页，也不进 NavigationStack。打开只是读当日建议，不发起生成：当日建议还没生成好时先显示前一份并标旧，没有前一份才显示思考流。REFRESH 是同一天内唯一的重生成入口。没有可行动的证据可以没有建议；刷新失败时明确标出旧内容。接口仍用 `surface=plan` / `type=plan`，存储仍用 `daily_plans`。
_Avoid_: 第六个详情, 横向第三页, 全天排程, 打开即生成 / 每次打开重新生成 (ADR 0022 撤销), 每日缓存 (当日建议是那天的成品，不是命中或未命中), 固定五格, 勾选完成, 推送督促, 手机本地拼的建议

**当日建议 (day's set)**:
一个用户日的那一份建议。当天第一次打开 App 并同步后自动生成一次；同一天只有 REFRESH 才重生成，最近一次替换前一次。每个用户日最多一次自动生成，两台手机共用同一份；自动生成失败在同一用户日最多再试两次。它在服务端跑完并存下，与手机是否还连着无关。存储是 `daily_plans` 里那一天的行。
_Avoid_: 晨间建议 (触发不绑早晨，下午才第一次打开也算), 缓存, 每次打开都新的一份, 服务端定时生成 (没有手机同步就没有昨晚的数据)

**建议 (suggestion)**:
围绕一个有时间和来源的核心指标，用一句或几句说明现在适合做什么、为什么。一组通常一到五条，按相关性排序，不为凑数补同步、吃三顿饭等常识待办。数字来自本轮引用的证据，行动参考经核实的专业资料。与上一组换有价值的切入点，但不为新鲜捏造异常或反转意见。无勾选、无完成评价；旧 `plan_task_checks` 仅保留历史兼容。
_Avoid_: 计划任务, 槽位, 固定时长任务, 未记录等于没吃, 疲劳等于缺蛋白, 压力指数等于诊断

**思考流 (thinking stream)**:
一次 `/turn` 进行中，屏幕或计划页脚下逐行打出的模型自述，来自 `thought` 事件；没有 thought 时退回到「正在读 X」的工具名。它是等待态的唯一画面，不是 spinner。用户中途离开时，当日建议的 turn 在服务端跑完并存下结果（ADR 0022）；其他面的 turn 随连接一起中止。回来后接不上先前的自述，只显示已用时间和「几分钟后再来看也可以」。
_Avoid_: 转圈, 骨架屏, 假进度, 离开就取消, 回放旧 thought

**会话 (session)**:
一段连续的 AI 对话，跨 Chat 和首页语音 / 拍照。退出 Chat 或三十分钟没有新 turn 即结束；结束时系统总结一次，写进记忆。
_Avoid_: 每个 turn 都总结, 只算 Chat 的会话

**记忆 (memory)**:
系统替这个人记下的两层文字：一段「这个人是谁」的概述，加带日期和来源的事实条目。每次会话结束由模型把旧记忆和新会话合并重写，可以删过时的条目，封顶约 1500 token。每个 turn 和每次计划生成都读它。用户在 Profile 可见、可整段删除；撤回同意或删号时清空。
_Avoid_: 无限追加的日志, 对用户不可见的记忆, 把上一轮的数字当记忆, 用记忆代替本轮读数

**手机工具 (phone tool)**:
模型在一轮里调用、由手机执行、结果回到同一轮的工具：找设备、同步、设闹钟、开运动、记餐、平衡检查、身体扫描、打开某一页。模型碰不到蓝牙，所以服务端发出 `tool.request`、存档、关流，手机执行后带同一个 Idempotency-Key 续 turn。每个工具返回 ok / code / data，模型据此说成没成。设闹钟、开运动、记餐在执行前弹确认，不点算取消。
_Avoid_: 终态意图, 模型直接读手环, 语音一句话就开跑, 只读工具, 服务端排队等连上再执行

**可续 turn (resumable turn)**:
一次 `/turn` 因等手机工具而暂停后，用同一个 Idempotency-Key 再次 POST 附上工具结果，从存档的消息与阶段状态继续。一轮最多续三次，等手机的时间不计入模型预算。
_Avoid_: 服务端轮询等结果, WebSocket, 第二个 turn id

**三步 (read · act · render)**:
每一轮的固定顺序：先读（含记忆与设备状态），再执行手机工具，最后一个输出。执行完允许回读一次。输出是显示屏的一张图、一组建议或 Chat 的一段文字，三者只出一个。
_Avoid_: 读和执行混在一起, 一轮两个输出, 按入口锁输出工具

**开机 (launch mark)**:
1 的柠檬点 + 2 的 Doto。`LaunchMark` 按 FirstRun 的 28ms 一格把 `NEXTBODY` 打出来，点落下，再打第二行 `BUILD YOUR NEXTBODY` / `打造你的下一副身体`。ready 立刻切走。登录 / 配对片仍是 `WordmarkAnimation`。
_Avoid_: 开机播 02M, 苹方字标, 像素雨

**通知 (notification)**:
手机系统通知。锁屏出、解锁后出横幅，NextBody 在前台也出。它不是首页面板上的那句话，也不是手环上的走动 / 喝水 Buzz。
_Avoid_: 只锁屏, 把面板当通知, 把手环 Buzz 当通知

**通知边沿 (notification edge)**:
上一份快照不成立、这一份成立的事实：一根阈值被跨过，或一组事实第一次凑齐。不是墙上钟点。
_Avoid_: 闹钟, 07:00 / 12:30 / 17:00 / 20:30 排程

**身体电量低 (low reserve)**:
身体电量当前值第一次落到 25 及以下，且低于当天醒来值。不是手环电量。当天回到 40 以上再掉，不再算第二次。
_Avoid_: 电量低（会和手环电量混）, 没电, 异常

**手环没电 (low band charge)**:
手环最后一次真读数第一次落到 15% 及以下（格数固件为最低一格），且不在充电。不是身体电量。充电或回到 30% 以上才重置。
_Avoid_: 电量低（会和身体电量混）, Body Battery, 把格数写成百分比

**手环离开 (band away)**:
已绑定手环的 BLE 从连上变成没连上，并且这一次断开持续满 4 小时。不是没戴，也不是佩戴日断了。
_Avoid_: 手表没连上, 没戴, 把断连写成连续佩戴断开

**昨夜窗 (last-night window)**:
真实醒来起六小时。昨夜通知和昨夜卡只在这扇窗里出现一次。过了窗，详情还在，锁屏不再叫。
_Avoid_: 07:00 闹钟, 把日历早上当醒来

**当日收束 (day wrap)**:
当天第一次同时具备至少两样已落地事实（昨夜充电、训练负荷、一餐确认、当前储量）时说的那一句。不是计划页上的总结。用户日翻周且上一周至少 4 个有效日时，同一句换成周报。
_Avoid_: 日报, 晚报, 把计划总结当通知

**用餐空档 (open meal)**:
下一顿主餐仍未确认。通知边沿还要求这次同步里人动了，且近七个用户日有过餐。
_Avoid_: 12:30 午饭闹钟, 进食窗口

**NextBody PRO**:
健康账号上的 App AI 会员（ADR 0030）。App Store 商品 `hoop_pro_monthly`，$6 / month；首月优惠资格由 App Store 判定。原生 SwiftUI 付费页按 Paper 原稿还原，RevenueCat 负责购买、恢复及 `next_pro` 权益，Test Store 商品为 `monthly`；服务端可信同步到本地 `pro` 账本。没有有效权益时，面板 / 教练 / 当日建议 / ASR 全部拒绝（`SUBSCRIPTION_REQUIRED`）。手环、生命体征、测量不收订阅。跳过付费墙不送试用；已有订阅可在 Profile 进入 Customer Center。
_Avoid_: 永远免费, 客户端空发一个月, 自己收银行卡号, 把 Shopify 手环卖成订阅

**盘 (plate)**:
一次估算写下的那一组 meal 行。它们共享 `meals.meal_group_id`，共享一张照片（`photo_path`，私有桶 `meal-photos`，路径第一段是本人 id），每一行各带自己的 `portion`。它是「这一次拍的这顿」的落点——整体回看、整体调份量、整体存成常吃都按它走。它不是餐次分组：日档食物表仍然按时间列行，不分早午晚。
_Avoid_: 一餐 (那听起来像餐次), 早餐/午餐/晚餐分组, 把组当成一行

**份量 (portion)**:
模型给每样食物的量，一句人话：「1 碗」「200 g」「2 slices」。改份量走乘数（×0.5 / ×1 / ×1.5 / ×2），热量、三大营养素、已知的纤维／糖／钠和这句话一起缩放；话里没有数字（「半份」）就在缩放时丢掉这句话，不留一句和新数字对不上的量。它不是称重结果。
_Avoid_: 克重 (不一定是克), 份数 (那是乘数), 把没法缩放的词留在旁边

食物记录保留营养数据的小数，展示 1 位；修改份量按 1 位小数计算，未知仍是未知。日级预算与能量摘要沿用整数展示。小数是记录／展示精度，不是照片估算的测量准确度。

**微量三项 (micronutrients)**:
纤维、糖、钠。模型只在真知道的食物上给，缺就是 null、画 ——。一天的合计是全有全无：只要有一行不知道，这一天就不出合计，并写明有几行不知道——把知道的加起来印成「今天」，和给读不出的盘写 0 kcal 是同一种谎。不做 x/10 营养总分。
_Avoid_: 把缺项当 0 相加, Health Score, 营养评分

**常吃 (regular)**:
存下来的一盘，`meal_favorites` 里的一行（label + items + 照片）。再记一次就是把 items 原样重放成新的 meal 行：不调模型、不重新估算、不等待。它是历史的副本不是引用——删掉那顿饭不清空它，改它也不动历史。
_Avoid_: 收藏夹, 模板 (听起来会随原餐变), 把它做成一条引用

**回执 (receipt)**:
刚写进记录的那一条在屏幕上停留的八秒：写了什么、TARGET 还剩多少、一个 UNDO。同时只有一条，新的顶掉旧的，自己消失，没有关闭按钮。撤销走的是写它的同一条出站队列（改是软删加新行，所以撤销一次修改是再改一次），不是把界面上的字擦掉。
_Avoid_: toast, 通知, 一次排好几条, 只在界面上撤销

**读取中的盘 (reading plate)**:
已经发出、还没有行的那一盘：食物表里那一行有照片、有那句话，数字列写 READING。它从不写数字，也不写 0——猜一个 kcal 配个转圈是这一格唯一不许出现的东西。带图的一轮和从 LOG A MEAL 发出的一轮（`intent: "meal"`）都不随连接中断，人走开了服务端也把这一盘写完。
_Avoid_: 骨架屏数字, 进度百分比当成把握, 0 kcal 占位
