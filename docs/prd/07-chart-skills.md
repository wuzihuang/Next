# 07 · 图表 Skills — 云端 AI 什么时候用哪张图

> 由 `supabase/functions/_shared/skills.ts` 生成，不要手改。每一条 Skill 同时是：一个 `screen.render.<type>` 工具的 description、系统提示词 S11 的一行、以及这份文档的一节。

## 路由 · S11 原文

```
S11 CHART CHOICE
屏上的每一种图都是一个 screen.render.<type> 工具。先用读工具拿到数字，再按问题的形状选图：
· 此刻一个数 → metric；一个数对满值/目标 → ring；0–100 带分区 → gauge；BODY BATTERY 此刻 → battery
· 一天之内或几十天里怎么变 → line；一周逐天比较 → days；一天里分时段的量 → bars
· 每天高低两条边 → band；一周×时段的规律 → heat；有正有负的逐次变化 → delta；两条趋势对照 → dual
· 训练：区间分钟 → zones；今天负荷的构成 → workout / table；今天发生了什么 → events
· 昨夜：逐分钟分期 → hypnogram；三段占比 → split；夜间血氧 → o2night
· 燃料：三大营养素对目标 → fuel；吃进对消耗 → balance；今天记了哪几餐 → meal；用户报一顿吃的 → food
· 几项指标一起看 → sparks；做到了几天 → cells；12 周体成分的方向 → recomp
序列类的图只选数据源，点由服务端填；工具返回 NO_DATA 就换一种图或用 text 写 ——，不许自己造点。
没有任何图配得上时才用 text。一轮只渲染一次。
```

## 23 种图，各自的 Skill

| type | 形状 | 用在 | 不用在 | 数据源 | 文案 | 落点 |
|---|---|---|---|---|---|---|
| `metric` | ANY SCALAR | 用户问的是此刻的一个数（心率现在多少、体重多少、今天吃了多少）。 | 这个数有满值或目标时用 ring；问的是「怎么变」时用 line。 | 模型自己填字 | value 只写数字与单位，来自本轮读到的值；label 写指标名；ref 写参照（+4 VS RHR 52）。 | profile |
| `text` | BIG WORD · NO DATA | 没有任何一张图配得上这个问题：一句判断、一个方向、或者数据是空的（写 ——）。 | 手里有一串数据就别用 text，把它画出来。 | 模型自己填字 | sentence 是唯一的主角，≤ 48 字；footer 放依据，action 放下一步（可省）。 | profile |
| `line` | TIME SERIES | 问的是一天之内或一段日子里某个指标怎么变：心率、压力、BODY BATTERY 曲线、体重走势、负荷/电量/摄入的 7–30 天趋势。 | 只有一个数时用 metric；一周里逐天比较用 days；两条线对照用 dual。 | `heart.today`<br>`stress.today`<br>`bodyBattery.today`<br>`trainingLoad.7d`<br>`trainingLoad.30d`<br>`bodyBattery.7d`<br>`bodyBattery.30d`<br>`intakeKcal.7d`<br>`intakeKcal.30d`<br>`weight.30d`<br>`weight.90d`<br>`hrv.7d` | title 写「指标 · 窗口」；sentence 说形状（一个高峰、平了、往下走），footer 放 min/max/mean。 | training |
| `band` | HI / LO PAIR | 问的是每天的高低两条边——一周心率最高与最低的走势。 | 只关心一条线用 line；不是高低成对的数据不要用。 | `heart.range.7d` | hero 写今天的低–高；sentence 说两条边有没有拉开或收窄。 | training |
| `bars` | INTRADAY BINS | 一天里分时段的量：今天的步数按两小时、今天每一餐的 kcal。 | 逐天比较用 days；连续变化用 line。 | `steps.today`<br>`mealsBySlot.today`<br>`trainingLoad.7d`<br>`intakeKcal.7d` | hero 写总量与单位；sentence 指出最高的那一段；footer 写峰值时段。 | training |
| `days` | WEEK VS TARGET | 一周里每天多少：步数、训练负荷、电量、摄入逐天比较。 | 一天之内用 bars；有正有负用 delta。 | `steps.7d`<br>`trainingLoad.7d`<br>`bodyBattery.7d`<br>`intakeKcal.7d` | hero 写 7 天均值；sentence 点名最高和最低的那天；footer 写今天对均值。 | training |
| `hypnogram` | SLEEP STAGES | 问的是昨晚睡得怎么样、几点睡几点醒、深睡够不够：按分钟画成清醒 / 浅睡 / 深睡三条泳道。 | 只想知道各段总时长用 split；只想要一个数用 metric。 | `sleep.stages` | title 写 SLEEP · 起止时刻；hero 是总时长；sentence 说深睡块的形状；footer 写醒了几次。 | bodyBattery |
| `split` | SLEEP MIX | 昨晚深睡 / 浅睡 / 清醒各占多少：一条堆叠轨加三行图例。 | 想看逐分钟的形状用 hypnogram。 | `sleep.mix` | hero 是总时长（7H38 这种）；sentence 说深睡占比；footer 写三段分钟数。 | bodyBattery |
| `o2night` | SPO2 + APNEA | 问的是夜间血氧：一整夜的曲线、均值、最低点、掉到 90 以下几次。 | 手环没写 SpO2 时这张图没有数据，改用 split 或 text。 | `o2.night` | hero 写均值百分比；sentence 说有没有掉点；footer 写 guide 90 与最低值。 | bodyBattery |
| `sparks` | MULTI-METRIC ROWS | 用户想一眼看几项指标（心率、压力、步数）各自的近况。 | 只问一项时用 line 或 metric。 | `vitals.7d` | 没有 hero；sentence 说三项里哪一项在动；footer 写窗口。 | training |
| `ring` | GOAL PROGRESS | 一个数对它的满值或目标：TRAINING LOAD 对 21、蛋白质对目标、热量对目标。 | 没有目标的数用 metric；BODY BATTERY 用 battery。 | `load.today`<br>`protein.today`<br>`kcal.today` | sentence 写「X 的 Y」或还差多少；footer 写目标从哪来。 | training |
| `gauge` | ZONED 0–100 | 一个 0–100 且有分区含义的读数：此刻的压力（REST / MID / HIGH）。 | 没有分区的数用 metric 或 ring。 | `stress.now` | hero 写数值与分区名；sentence 说它在往哪边走；footer 写读数时刻。 | bodyBattery |
| `battery` | BODY BATTERY | 问的是 BODY BATTERY 此刻多少、或者没有更好的判断时的回落帧。 | 问一天怎么充放用 line + bodyBattery.today。 | `battery.now` | title 固定 BODY BATTERY；sentence 写「现在 N」；footer 写醒来时的值。 | bodyBattery |
| `cells` | COUNT OF N | 做到了几天：一周里称了几天体重、记了几天餐。 | 关心数值本身时用 line 或 days。 | `weighins.7d`<br>`mealsLogged.7d` | hero 写「N OF 7」；sentence 说缺的是哪几天。 | composition |
| `zones` | LIVE WORKOUT | 今天在五个心率区间各待了多少分钟。 | 问负荷总量用 ring + load.today；问构成用 workout。 | `zones.today` | hero 写占比最大的区间与分钟；footer 写五个分钟数与峰值心率。 | training |
| `table` | KV ROWS | 几对「名称 → 值」并排看：今天负荷的构成、一次体成分的几个字段。 | 有时间顺序用 events；带趋势用 sparks。 | `segments.today` | rows ≤ 5，value 里的数字必须来自本轮读到的值；hero 写总数。 | training |
| `workout` | SESSION CARD | 今天的一次或几次训练：抬高心率的时段、各自的贡献。 | 没有抬高心率的时段就没有 workout，改用 ring + load.today 或 text。 | `segments.today` | hero 写今天的 TRAINING LOAD；sentence 点名最重的一段；footer 写分钟与平均心率。 | training |
| `events` | DAY LOG | 用户问今天发生了什么、记录了什么：餐、训练时段、称重、体成分按时间排列。 | 只问一类事情时用那一类的图。 | `events.today` | hero 写事件数；sentence 说最重要的一件；footer 写最早和最晚的时刻。 | profile |
| `heat` | WEEK × HOUR | 一周里的规律：哪一天的哪个时段心率或步数最高。 | 只问今天用 bars 或 line。 | `heart.heat.7d`<br>`steps.heat.7d` | hero 写最亮的格子（星期 + 时段）；sentence 说这个规律；footer 写 UNLIT → DIM → MID → BRIGHT。 | training |
| `food` | ONE ITEM | 用户报了一顿吃的（S10）：渲染草稿帧，action 固定「确认记录」，由屏幕那一侧提交。 | 用户问的是今天吃了多少（不是在报餐）时用 meal 或 balance。 | 模型自己填字 | name 写菜名，portion 写份量；不写没有依据的 kcal；sentence 说这一餐大致是什么。 | fuel |
| `meal` | ITEM LIST | 今天记了哪几餐、各多少 kcal。 | 问剩多少额度用 ring + kcal.today；问三大营养素用 fuel。 | `meals.today` | hero 写总 kcal；sentence 说还有哪一餐没记（没记 ≠ 0）；footer 写蛋白质合计。 | fuel |
| `fuel` | MACRO BUDGET | 三大营养素今天吃进对目标：蛋白质、碳水、脂肪各差多少。 | 只问热量用 balance 或 ring + kcal.today。 | `macros.today` | hero 是缺口最大的那个（服务端算好）；sentence 说怎么补；footer 写三对 eaten/target。 | fuel |
| `balance` | IN VS OUT | 今天吃进对消耗：净差是多少、还能吃多少。 | 没记餐的一天没有 balance（没记 ≠ 0），改用 meal 或 text。 | `balance.today` | hero 写 in − out（带符号）；sentence 说方向；footer 写 in / out / 目标。 | fuel |
| `recomp` | DAY GRID · 12 W | 12 周里体成分的方向：多少次测量脂肪往下走。 | 问具体数值用 dual；问最近几次变化用 delta。 | `composition.recomp` | hero 写 N DOWN · M UP；sentence 说趋势；footer 写 12 周脂肪量变化。 | composition |
| `delta` | DAILY Δ · SIGNED | 有正有负的逐次变化：两次体成分之间脂肪量的增减、一周每天吃进减消耗。 | 全是正数的量用 days 或 bars。 | `composition.delta`<br>`deltaKcal.7d` | hero 写净变化（带符号）；sentence 写几次向上几次向下；footer 写窗口。 | composition |
| `dual` | FAT vs LEAN | 两条趋势对照：12 周脂肪量 vs 瘦体重。 | 只有一条线用 line；问方向用 recomp。 | `composition.dual` | hero 写最新体脂率；sentence 说两条线有没有交叉或拉开；footer 写各自的变化量。 | composition |

## 数据源目录 · series.get 与 screen.render.* 共用

序列由服务端按数据源从库里读、分桶、成形；模型只选源，不抄点。空的源返回 null，工具答 NO_DATA，模型换图或用 text 写 ——。

| source | 形状 | 内容 |
|---|---|---|
| `heart.today` | curve | 今天的心率曲线，30 分钟一点（bpm） |
| `stress.today` | curve | 今天的压力曲线，30 分钟一点（0–100） |
| `bodyBattery.today` | curve | 今天的 BODY BATTERY 曲线：夜里充、白天放（0–100） |
| `steps.today` | column | 今天的步数，两小时一柱 |
| `steps.7d` | column | 最近 7 天每天的步数 |
| `trainingLoad.7d` | curve | 最近 7 天每天的 TRAINING LOAD |
| `trainingLoad.30d` | curve | 最近 30 天每天的 TRAINING LOAD |
| `bodyBattery.7d` | curve | 最近 7 天每天的 BODY BATTERY（%） |
| `bodyBattery.30d` | curve | 最近 30 天每天的 BODY BATTERY（%） |
| `intakeKcal.7d` | curve | 最近 7 天每天的 EATEN（kcal） |
| `intakeKcal.30d` | curve | 最近 30 天每天的 EATEN（kcal） |
| `deltaKcal.7d` | column | 最近 7 天每天吃进减消耗（kcal，有正有负） |
| `weight.30d` | curve | 最近 30 天的体重（kg） |
| `weight.90d` | curve | 最近 90 天的体重（kg） |
| `heart.range.7d` | pair | 最近 7 天每天心率的最高与最低两条线 |
| `heart.heat.7d` | grid | 最近 7 天 × 每两小时的心率热力图 |
| `steps.heat.7d` | grid | 最近 7 天 × 每两小时的步数热力图 |
| `zones.today` | strip | 今天五个心率区间各多少分钟 |
| `segments.today` | rows | 今天训练负荷的构成：每一段抬高的心率贡献了多少 |
| `load.today` | arc | 今天的 TRAINING LOAD，满值 21 |
| `battery.now` | arc | 此刻的 BODY BATTERY，0–100 |
| `protein.today` | arc | 今天吃进的蛋白质对目标（g） |
| `kcal.today` | arc | 今天吃进的热量对目标（kcal） |
| `stress.now` | gauge | 最近一次压力读数，分区 REST / MID / HIGH |
| `meals.today` | rows | 今天记了哪几餐，各多少 kcal |
| `mealsBySlot.today` | column | 今天每一餐的 kcal 柱（没记的餐不画） |
| `macros.today` | stack | 今天三大营养素吃进对目标（g），hero 是缺口最大的那个 |
| `balance.today` | stack | 今天吃进 vs 消耗（kcal）；没记录的一天返回空，不当 0 |
| `weighins.7d` | grid | 最近 7 天哪几天称了体重 |
| `mealsLogged.7d` | grid | 最近 7 天哪几天记了餐 |
| `vitals.7d` | rows | 心率、压力、步数三行，每行带最近 7 天的小折线 |
| `composition.dual` | pair | 12 周脂肪量 vs 瘦体重两条线（kg） |
| `composition.delta` | column | 两次体成分之间脂肪量的变化，一柱一次，有正有负（kg） |
| `composition.recomp` | grid | 12 周 × 7 天的格子：每次测量脂肪往下（亮）还是往上（暗） |
| `sleep.mix` | stack | 上一夜的深睡 / 浅睡 / 清醒各多少分钟 |
| `sleep.stages` | strip | 上一夜的睡眠分期，按分钟画成清醒 / 浅睡 / 深睡三条泳道 |
| `o2.night` | curve | 上一夜的血氧曲线（需要手环写入 SpO2，目前多半为空） |
| `hrv.7d` | curve | 最近 7 天每天的 HRV（ms） |
| `events.today` | rows | 今天按时间发生了什么：餐、抬高心率的时段、称重、体成分 |

## 不提供的四种

- `wave` · ECG 走纸：库里没有心电采样，07 的规则是「能力表里没有的数据永远不给 widget」，所以不暴露给模型。
- `hypnogram` `split` `o2night` · 睡眠三件：F0 规则 03，睡眠不上屏，夜晚只以它产出的 BODY BATTERY 出现。

