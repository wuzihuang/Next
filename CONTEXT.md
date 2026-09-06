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
睡眠的二级页，按日 / 周 / 月三档**滚动**窗口呈现（最近 1 夜 / 7 夜 / 30 夜），不翻页。日档印出那一夜的分期、夜间 HRV 与夜间血氧；三档都印睡眠分数，并可拆解到四组。RESPONSE（ADR 0012）与 HEART（ADR 0013）也有同一套三档（24 小时 / 7 / 30 用户日）。热量页（ADR 0014）用同一组英文词，窗口是 1 / 7 / 28 用户日，月只讲典型的一天。其余五个 vitals 仍由 `VitalsMetric.timeline` 写死。睡眠周/月的英雄数是中位；RESPONSE 周/月是平均；HEART 周/月是日中位的中位。
_Avoid_: sleep report, RESTORATIVE as a badge, 自然周 / 自然月 (窗口是滚动的), 把日/周/月再推广到其余五个 vitals, 把热量的月窗抄成 30 天

**睡眠分数 (sleep score)**:
0–100，服务端每夜结算一次并落 `night_score`，由四组合成：时长 25%、结构 25%（深睡占比 / REM 占比 / 醒来次数）、恢复 35%（夜间 HRV / 静息心率 / 夜间血氧 / 睡眠呼吸率）、规律 15%（入睡时间偏离个人中位）。阈值写死在打分函数里并带 `score_version`，改版即全量重算历史。缺项在组内重新归一——只要那一夜有记录就必定出分；完全没戴的夜不出分。恢复组与规律组从第 14 夜起向个人基线校准，时长与结构组永不校准。
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
手环电量随时间的折线，由每次电量上报、充电接入/拔出、以及连接通断记录而成。电话没听到的长间隔不拉直尺到 NOW，而是按放电曲线估算（先撑住再掉；充电则先快后慢），虚线画出；首次连接叠在同一分钟的旧包+新读数当虚点丢掉。SDK 带电量、充电态 unknown 的脏包不写入、不进图，旧日志加载时清掉。过夜列对齐睡眠页的 sleepStart→wakeAt，不是 04:00，也不是充电时段。曲线与 HEART 一样可探点。趋势卡底下一行淡字是学会的斜率外推的时刻（EST · FULL / EST · EMPTY），没学会就不写；不是规格书 10 天，也不是 150 mAh 除以假设电流。学会放电斜率后，同一张卡多一格 LEFT：还能用的整天或小时，来自同一条斜率（`BatteryDrainMath.left`）。没学会、格数固件、正在充、已充满都不写 LEFT。设备页大数字仍是最后一次真读数。还在充但已 100%（或 4/4）写 Charged / 已充满，不写充电中——固件常常不发 `.full`。设备页顶部是电量环（POWER / LEFT / TREND）；TREND 打开趋势图（`Destination.battery`）。首页电量 pip 仍进设备页。不是 Body Battery，格数固件也不把格数画成百分比。
_Avoid_: Body Battery, 把 0–4 格写成 %, 把没听到的时段画成水平直线, 把过夜画在 04:00 切日上

**训练负荷 (training load)**:
当天累积的训练压力，0–21 的产品估算，由服务端从五分钟 tick 结算得出（心率区间负荷与运动负荷取其大者，见 ADR 0004）。它是一个每日标量，不是时长也不是一场运动。二级页有日 / 周 / 月三档（ADR 0015）：周是已结束天的平均，月是典型一天，都不加总。
_Avoid_: 活动 (重载成三样东西), 训练量, 运动强度, 把它说成临床压力测量, strain, 周月加总

**活动分钟 (active minutes)**:
当天 MET ≥ 3 的 tick 折算出的分钟数，服务端结算的每日派生值。它与训练负荷是两个不同的数，不能互相换算或互相印证。
_Avoid_: 活动, 运动时长 (那听起来像一场运动的时长), 锻炼分钟

**运动会话 (sport session)**:
手环 sport-mode 下的一次运动，有开始与结束。⚠️ 服务端目前没有这张表；`segments.today` 是从心率抬高段反推的段落，不是一次运动会话。
_Avoid_: 活动, 训练, 把 segments 当成会话

**睡眠呼吸率 (sleep respiration rate)**:
手环在记录到的睡眠窗口内测到的每分钟呼吸次数，属于那一夜。本产品没有日间呼吸监测。
_Avoid_: 呼吸 (会被读成日间指标), 呼吸监测, 把它当成呼吸暂停结果

**手环原始耗卡 (vendor calories)**:
手环自报的 tick 级卡路里，与本产品的消耗口径不是同一个数——展示用的消耗由服务端从 MET 与体重算出（`day_fuel.kcal_out`），厂商值的基础代谢部分不可分离，因此不与之相加（ADR 0004）。引用原始值时必须说明它是手环自报。
_Avoid_: 消耗, 今天烧了多少, 把它与 kcal_out 混用或互相校验

**活动热量 (active energy)**:
首页第二页 ACTIVE ENERGY 卡与它后面的二级页。一级卡英雄是当天已过的 ACTIVE；二级日档英雄是 OUT（静息 + 活动）。活动三项是 SPORT / STEPS / INCIDENTAL，按相对 MET 分钟摊到已结算的活动热量上，三项加总等于活动，再加上静息等于 OUT。累积曲线与热量页 OUT 共用 `FuelWindowMath.burnCurve` 的同一组点（ADR 0016）；主色 lime。缺项是 ——，不是 0。厂商 tick 卡路里不进柱、不进线。
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
身体电量页上的日 / 周 / 月。滚动用户日：1 / 7 / 30，与训练同粒。英雄数永远是 0–100 的一天：日是此刻的储量，周是醒来高点的平均，月是典型一天的早晨高点，都不加总。空天是空格不是 0。主色 lime；夜里充电用黄，白天放电用白。一级模块在「我的」身份卡与成分之间，整块一热区。睡眠不上屏。
_Avoid_: 自然周 / 自然月, 周月加总, 把空天画成 0, 紫色充电, 睡眠分期/时长/分数, 把周月说成两千

**热量窗 (calorie window)**:
热量页上的日 / 周 / 月。滚动用户日：1 / 7 / 28（四周），不是自然周月，也不是 HEART / RESPONSE 的 30 天。日档是当天的钟加一份不分餐的食物表。周档英雄数是七天加总。月档只讲典型的一天（四周「每天平均」的再平均），不说月加总。表内数字定宽、不换行；五位数上下排，不并排。IN − OUT 的数叫 DIFF / 差额，不是热力图上的空窗。日档消耗线跟当天的步数走，不是一根斜尺；活动页的累积 OUT 用同一条线（ADR 0016）。
_Avoid_: 自然周 / 自然月, 七万级月加总, 热力格, 把月窗做成 30 天, 早餐/午餐/晚餐分组, 五位数并排, 空窗 (那是热力图空格), 柠檬绿 LOG A MEAL pill, 记一餐回 dock

**睡眠分期 (sleep staging)**:
一夜之中每个时段各处于哪一个睡眠阶段——深睡、浅睡、REM、清醒。它是一条带时间位置的序列，不是一组总数；说"分期"而不指明落点，就会和分期总量混淆。⚠️ 一夜有没有 REM，由**那条记录自己的** `VPAccurateSleepModel.accurateType` 决定：1（精准睡眠）会给出 stage 2，0（普通睡眠）只给深睡与浅睡。设备级的 `VPPeripheralModel.sleepType` 不是判据——同一只手环连续几夜可以一夜有一夜没有。缺 REM 的夜是"没在测"，不是"没有 REM 睡眠"，所以那一段整个不画。
_Avoid_: 分期 (单说这两个字指代不明), 睡眠质量, 把深浅睡的分钟数称作分期, 把 REM 缺失说成这台设备不支持

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
一个用户日里，有腕上证据的五分钟槽不少于当天已过槽位的一半。未结束的今天从 04:00 计到现在；已结束的日子按 288 槽。腕上证据是心率或明确的传感器佩戴，不是连过一次蓝牙。它不是有效夜：夜里摘去充电、白天没戴满，这一天不成立。
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

**计划页 (plan face)**:
首页根上的第三张脸。竖向上滑打开、下滑关闭；不是第六个详情页，也不进 NavigationStack。顶上的下滑线箭和 `AGENT · 生成` 落在灵动岛下面，不和开孔抢位。一页只留标题、副标题、一段说明、四个带对勾的指标、以及 AI 读了什么。对勾表示今天做完了；点对勾或底下一行「重新生成」才打 `/turn`。没有夜就不写假分数。
_Avoid_: 第六个详情, 横向第三页, 带对勾标题的目录卡, 「为什么是这四件事」, 日历周, 推送督促, 把 61 写进空夜, 上滑就打 /turn

**计划把手 (plan lip)**:
底栏一条竖线：上头两条 1.6pt 圆头石灰折线追逐向上，中间仍是原来那两枚 4pt 分页点，下头单独一行 `PLAN`。不在 PLAN 两边再画点。系统 Home Indicator 仍由 iOS 画，不画假的。
_Avoid_: 把 Home Indicator 画进 App, 实心三角, 第三条分页点, 把分页点夹在 PLAN 左右
