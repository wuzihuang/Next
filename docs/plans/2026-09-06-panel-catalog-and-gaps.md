# 面板总表与缺口 · 2026-09-06

> **已落地（2026-09-06）**：34 种类型 / 34 个渲染工具全部写进代码，Deno 193 个测试通过，
> iOS Debug build 通过。落地过程中，真库验证推翻了本文最初的三处判断，见 §7「落地时改掉的
> 判断」——那一节是这份文件里最该先读的部分。

面板一次只显示一张图，画哪一张是模型当轮的选择。这份文件是那张选择表的全集：
现在代码里真实存在的 28 种类型 / 27 个渲染工具，以及审计出来该补的 6 种类型和 14 个数据源。

配套的视觉稿在 Paper 文件 `01M1M2B4XWK5W388XSKACJ1K9N` 的「显示屏 2.0」页：
`缺口补充 · 数据在库里，图还没有` 和 `总表 · 34 张图 × 33 个工具`。

## 0 · 先纠正两件事

- `PANEL_TYPES` 是 **28** 个，不是 27。第 28 个是 `plan`，它的渲染工具叫 `plan.render`
  （`_shared/plan.ts`），只在 `surface === "plan"` 时注册，不在 `screen.render.*` 里。
  `TARGETS` 同样是 6 个（多一个 `plan`）。
  所以：**28 种类型 = 26 个 `screen.render.*` + `plan.render` + 有类型没工具的 `wave`**。
- `reserve_daily.drain_drivers` 不是耗电拆分，只有 `close_value` / `assumed_anchor` /
  `anchor_origin` 三个锚点记账字段。任何「电量消耗瀑布图」的想法作废。

## 1 · 一轮 turn 的形状（ADR 0018）

`读 → 动手 → 画`，`MAX_TURN_STEPS = 8`，读阶段 `READ_STEP_BUDGET = 4`，最多续 3 次。

| 阶段 | active 的工具 |
| --- | --- |
| read | 10 个读工具 + 10 个手机工具 + `workflow.ready` |
| act | 10 个手机工具 + `workflow.ready` +（还够步数时）`workflow.reread` |
| render | 该表面的渲染工具 +（还够步数时）`workflow.reread` |

- 渲染与控制互斥，一步之内不能既画图又换阶段 → `STEP_ALREADY_COMMITTED`。
- 手机工具一步只允许一个 → `ONE_PHONE_TOOL_PER_STEP`。手机跑完把结果送回来，本轮继续，步数接着算。
- 整轮只渲染一次。TTL 20 分钟，过期回落 `batteryFallback()`。
- 这里**没有 MCP server**。`contract.ts` 写着 “No MCP server, no JSON-RPC hop”：
  所有工具是 Vercel AI SDK 的 `tool()` + Zod，定义在 `turn` 这个 Edge Function 里，
  工具体用当轮 JWT 建 Supabase client，RLS 生效。

## 2 · 公共文本槽（每个 `screen.render.*` 都一样）

`title ≤18` · `sentence ≤48`（必填）· `footer ≤42` · `action ≤32` · `hero ≤16` ·
`tag`（MOVE / FUEL / RECOVER / ALERT）· `target`（6 个 TARGETS 之一）· `claims[] ≤32`。

`tag` / `target` / `source` 是 **string 不是 Zod enum**，这是故意的：线上出现过模型漏写
`target` → enum 在 generateText 里抛 `AI_InvalidToolArgumentsError` → 整轮 `MODEL_UNAVAILABLE`。
合法值写在 description 里，在 `execute()` 里校验，错值是模型能处理的工具结果。

下表「独有参数」只写这张图在公共槽之外还要什么。

## 3 · 现有 28 种类型

| type | family → kind | Swift 渲染器 | 工具 | 独有参数 | source | 什么时候选它 | target | 色 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| metric | number → rows | RowsRenderer | `screen.render.metric` | value · unit · label · ref | 无（数字由模型填，必须来自本轮工具返回） | 此刻的一个数：心率现在多少、体重多少、今天吃了多少 | profile | ember |
| text | number → rows | RowsRenderer | `screen.render.text` | headline ≤12 · eyebrow · sub | 无 | 没有一张图配得上：一句判断、一个方向，或数据为空（写 ——）。屏上无 sentence 槽 | profile | white |
| line | curve | CurveRenderer | `screen.render.line` | source | heart.today · stress.today · bodyBattery.today · trainingLoad.7d/30d · bodyBattery.7d/30d · intakeKcal.7d/30d · weight.30d/90d · hrv.7d | 一天内或一段日子里某指标怎么变 | training | ember |
| band | pair | PairRenderer | `screen.render.band` | source | heart.range.7d | 每天的高低两条边 | training | blue |
| bars | column | ColumnRenderer | `screen.render.bars` | source | steps.today · mealsBySlot.today · trainingLoad.7d · intakeKcal.7d | 一天里分时段的量 | training | ember |
| days | column | ColumnRenderer | `screen.render.days` | source | steps.7d · trainingLoad.7d · bodyBattery.7d · intakeKcal.7d | 一周里每天多少 | training | lime |
| hypnogram | strip | LaneRenderer | `screen.render.hypnogram` | source | sleep.stages | 昨晚几点睡几点醒、深睡够不够 | bodyBattery | violet |
| split | stack | StackRenderer（分钟制） | `screen.render.split` | source | sleep.mix | 深睡/浅睡/清醒各占多少 | bodyBattery | cyan |
| o2night | curve | CurveRenderer | `screen.render.o2night` | source | o2.night | 夜间血氧曲线、均值、最低点。不是呼吸暂停分级 | bodyBattery | blue |
| sparks | rows | RowsRenderer + Sparkline | `screen.render.sparks` | source | vitals.7d | 几项指标各自近况，每行一条迷你走势 | training | white |
| ring | arc | ArcRenderer | `screen.render.ring` | source | load.today · protein.today · kcal.today | 一个数对它的满值或目标 | training | ember |
| gauge | gauge | GaugeRenderer | `screen.render.gauge` | source | stress.now | 0–100 且有分区含义的读数 | bodyBattery | ember |
| battery | arc | ArcRenderer | `screen.render.battery` | source | battery.now | BODY BATTERY 此刻多少；也是兜底帧 | bodyBattery | lime |
| cells | grid | GridRenderer | `screen.render.cells` | source | weighins.7d · mealsLogged.7d | 做到了几天 | composition | lime |
| zones | strip | ZoneColumnsRenderer | `screen.render.zones` | source | zones.today | 今天五个心率区间各多少分钟 | training | ember |
| table | rows | RowsRenderer | `screen.render.table` | source | segments.today | 几对「名称 → 值」并排看 | training | ember |
| workout | rows | RowsRenderer | `screen.render.workout` | source | segments.today | 今天的一次或几次训练 | training | ember |
| events | rows | RowsRenderer | `screen.render.events` | source | events.today | 今天发生了什么、记录了什么 | profile | ember |
| heat | grid | GridRenderer | `screen.render.heat` | source | heart.heat.7d · steps.heat.7d | 一周里的规律：哪天哪个时段最高 | training | ember |
| food | rows | RowsRenderer | `screen.render.food` | name · portion · kcal · protein_g · carb_g · fat_g · pct_of_budget | 无（turn 包了一层：没先跑 `meal.estimate` 返回 `ESTIMATE_REQUIRED`） | 用户报了一顿吃的（S10），渲染草稿帧，action 固定「确认记录」 | fuel | cyan |
| meal | rows | RowsRenderer | `screen.render.meal` | source | meals.today | 今天记了哪几餐。没记的槽是 OPEN，不是 0 kcal | fuel | cyan |
| fuel | stack | StackRenderer | `screen.render.fuel` | source | macros.today | 三大营养素对目标 | fuel | cyan |
| balance | stack | StackRenderer | `screen.render.balance` | source | balance.today | 今天吃进对消耗。腕表报的卡路里不是产品口径的消耗 | fuel | cyan |
| recomp | grid | GridRenderer | `screen.render.recomp` | source | composition.recomp | 12 周体成分的方向 | composition | lime |
| delta | column | ColumnRenderer（zeroAxis） | `screen.render.delta` | source | composition.delta · deltaKcal.7d | 有正有负的逐次变化。唯一带零轴的柱图 | composition | violet |
| dual | pair | DualRenderer | `screen.render.dual` | source | composition.dual | 两条趋势对照 | composition | violet |
| wave | trace | TraceRenderer | `screen.render.wave` | source | rr.tachogram.last | 逐拍间期本身，按拍号画成迹线。**审计前它是唯一有类型没工具的一张**——`CHART_SKILLS` 里没有它，服务端不生成工具；现在接上 `band_rr_evidence.rr_ms` 补齐了 | bodyBattery | alert |
| plan | 自有面 | plan 面自己的帧 | `plan.render` | title ≤18 · summary ≤120 · tasks[1–8]{id ≤24, title ≤14, sub ≤40, basis ≤40} | `planContext()` 预取 daily_plans · plan_task_checks · 3 天 daily_results / night_score / meals | `surface=plan` 时唯一可用的渲染工具，不走 read 阶段 | plan | lime |

## 4 · 要新增的 6 种类型

每一条都要动 `contract.ts`（`PANEL_TYPES`）、`skills.ts`（`CHART_SKILLS`）、
`sources.ts`（`SOURCE_IDS` + `fetchAs` + `shape`）。

> 已全部落地。Swift 端最后写了四个新渲染器（`MeterRenderer` / `ScatterRenderer` /
> `MatrixRenderer` / `VerdictRenderer`）加 `CurveRenderer` 的阈值线与竖标记；`ScatterRenderer`
> 直接复用 App 里已有的 `PoincarePlot`。下面每一节的 family / source 以 §7 的更正为准。

### 4.1 `score` — 睡眠总分 + 四个子分

- source `sleep.score.night` ← `night_score`：`score` + `duration` / `architecture` /
  `recovery` / `regularity` 四个子分。
- family `stack`，复用 StackRenderer；hero 是总分，四条子分轨各带标签。
- 何时选：问「昨晚睡得几分」「为什么分低」。要同时说清总分和哪一项拖后腿——
  `gauge` 只有一个数，`split` 只有占比，都答不了。早上第一屏的默认帧。
- target `bodyBattery`，accent violet。
- 现状：`night_score` 只被 `plan.render` 的 `planContext()` 读到，前台没有任何图能画它。

### 4.2 `poincare` — 平衡测试散点

- source `balance.check.last` ← `band_rr_evidence.rr_ms`（一次测量的有序 RR 毫秒数组）画点，
  `balance_checks` 给 `lead` / `rest_share` / `sdnn_ms` / `heart_rate` / `beat_count`，
  算法字段 `poincare-1`。
- **要写新渲染器**（散点是 28 种类型里完全没有的形状，`line` / `band` 都画不了）。
- 何时选：刚做完 `balance_check.start`，或用户问上次平衡测试的结果。
- target `bodyBattery`，accent cyan。
- 现状：`balance_checks` 和 `band_rr_evidence` 都没有读工具、没有 source，测完只能在 App 里看。

### 4.3 `matrix` — 同步状态矩阵

- source `sync.status.7d` ← `sync_domain_status`（每域每天 complete / not_collected /
  unsupported / partial / failed 五态）+ `sync_runs` 给页脚（上次同步时间、成功率）。
- family `grid`，GridRenderer 要加离散色阶（现在是连续色阶）。
- 何时选：任何一次读回 `NO_DATA`，或用户问「为什么没有数据 / 数据是不是漏了」。
  `heat` 的连续色阶表达不了 unsupported 和 not_collected 的区别。
- target `profile`，accent lime。
- 现状：用户看到 NO_DATA 时没有任何解释。

### 4.4 `call` — 体成分判定 + 置信度

- source `composition.call` ← `daily_results.the_call` + `the_call_confidence` +
  支撑它的称重次数。
- family `number → rows`，复用 RowsRenderer。五个判定
  （RECOMP / CUT / BULK / DRIFT / NO_CHANGE）× 三档置信度（PENDING / MEDIUM / HIGH）。
- 何时选：用户问「我到底在增肌还是在减脂」。置信度不敢露，用户就不会信这个结论。
- target `composition`，accent lime。
- 现状：全库最重要的结论字段，一张图没有。`recomp` 画的是趋势格子，不是判定本身。

### 4.5 `curve` — 单次训练心率序列

- source `session.curve.last` ← `daily_training.curve`（jsonb）+ `peak_hr` / `zone_minutes`。
- family `curve`，复用 CurveRenderer。
- 何时选：刚练完（`sport.stop` 之后的默认帧），或用户问「刚才那次练得怎么样」。
  `line` 是 7 天一天一点，`zones` 是五区总分钟，都答不了单次的强度分布。
- target `training`，accent ember。

### 4.6 `response` — 餐后反应曲线

- source `response.meal.last` ← `response_samples.optical`（无量纲指数）+ `meals` 给开饭时刻。
- family `curve`，CurveRenderer **要加两个标记槽**（开饭那一刻、回到基线的时刻）。
- 何时选：用户问「刚才那顿反应怎么样」。
- **口径红线**：表注释写死了——不是血糖、不是化验单位。任何文案不许出现这两个词。
- target `fuel`，accent cyan。

## 5 · 只加 source、不加类型的 14 条

`data.read` 现在就读得到这些指标，但 `sources.ts` 里没有对应条目，模型永远画不出来。
加一行 `shape()` 就完事，不动 contract。

| 指标 | 接到哪张图 | 说明 |
| --- | --- | --- |
| bloodPressure | `band` | 收缩/舒张天生是一对 |
| ecg | `wave` | **wave 终于有数据源了**，接上就激活 |
| skinTemp | `line` | tick 粒度 |
| dayDistance · distance | `days` | |
| activeMinutes | `days` | |
| burnKcal（单独） | `days` | |
| wearRun | `cells` | 连续佩戴天数 |
| nightRHR × hrvBaseline | `dual` | 静息心率对 HRV 基线 |
| leanMassKg · bodyFatPct（单独） | `line` | |
| fasted_days | `cells` | 一周断食几天 |
| user_memory.facts | `table` | AI 记住了你什么 |
| sync_runs | `matrix` 的页脚 | 上次同步 / 成功率 |

注意 `vendorCalories` 是故意不接的：腕表报的卡路里不是产品口径的消耗。

## 6 · 不画图的 22 个工具

**READ · 10 个**（只在读阶段 active）：`day.get` · `metric.compare` · `data.read` ·
`data.catalog` · `profile.get` · `device.capabilities` · `meals.openSlots` ·
`meals.search` · `meal.estimate`（一轮一次，预算门控）· `image.inspect`（只在带图时注册）。

读到的每个数进 `NumberLedger`；之后说出口、写进 `agg` / `hero` / 轴标签的数字都必须在账本里，
否则 `INVALID_EVIDENCE`。

**PHONE · 10 个**（手机上执行，会挂起这一轮）：`device.find` · `device.sync` ·
`device.alarm.set` · `device.alarm.delete` · `sport.start` · `sport.stop` · `meal.log` ·
`balance_check.start` · `body_scan.start` · `app.open`（training / fuel / bodyBattery /
composition / profile / plan / device / sleep / heart）。写操作由用户在手机上确认。

**CONTROL · 2 个**：`workflow.ready`（宣布读够了，顺手定 `range`）·
`workflow.reread`（一轮只有一次回头机会）。

**公共失败口径**：`NO_DATA` / `QUERY_FAILED` / `INVALID_EVIDENCE` / `ESTIMATE_REQUIRED`。
`QUERY_FAILED` 不许说成「没有测量」。


## 7 · 落地时改掉的判断

纸上审计对了大半，但真跑起来有三处是错的。留在这里，因为每一处都会把一个错数字送上屏。

1. **`daily_training.curve` 不是心率序列。** 它是 `[[epoch, 累积 TRAINING LOAD], …]`，
   五分钟一点，满值 21。`curve` 这张图因此改口径为「今天负荷是怎么攒起来的」，
   source 叫 `load.curve.today`，并带一条 21 的阈值线。
   落地时还踩到一个真 bug：`dayRows()` 的嵌套 select 故意不取 `curve` 这个 jsonb 列，
   所以从那里读永远是 undefined——真库上一直返回 NULL。改成单独查 `daily_training`。

2. **`ecg` 是 unsupported，`wave` 的数据源不是它。** `metric-query.ts` 里 `ecg` 明写
   `unsupported: true`：这只手环不产 ECG。给 `wave` 接 ecg 等于凭空造一个没有行的 source。
   真正能画的是 `band_rr_evidence.rr_ms`——逐拍间期本身，画成 tachogram。
   source 叫 `rr.tachogram.last`，真库上读到 48 拍。
   连带一处：`wave` 的 hero 原来写成「平均心率 BPM」，而它的样本是毫秒，直接改成 MS AVG。

3. **一次测量是一串行，不是一行。** 手环每个 HRV 样本写一行 `band_rr_evidence`，
   每行只有 2–10 个间期。只取最新一行会被 12 拍下限挡掉，`poincare` 和 `wave` 在真库上
   全是 NULL。改成把最新那一行往前 10 分钟内的所有行按时间拼起来，并套用 App 自己的
   生理区间过滤（300–2000 ms，`AutonomicBalance` 的同一条规则）。

另外两处是真库验证抓出来的：

- **餐后曲线的窗口要按采样步长来。** 这条带子约 30 分钟一个点，原来 30 分钟基线窗 + 6 点
  下限一次都没填满过。改成前 90 分钟取基线、后 3 小时取反应，至少各 1 点、总共 4 点。
- **峰值只能在开饭之后找。** 原来在整段序列里找最大值，于是 09-04 那顿打印出
  `peakAfterMin: -86`——不是差一点，是在描述另一件事。已加回归测试钉死。

### 真库跑出来的状态（账号 e1c203bd / 9c59c2e5，2026-09-06）

| source | 结果 |
| --- | --- |
| `sleep.score.night` | ✅ 总分 91 / 87，子分 2–3 个（没算出来的子分不画，不补 0） |
| `sync.status.7d` | ✅ 7 域 × 7 天，complete 36 / partial 4 / missing 9 |
| `load.curve.today` | ✅ 89–199 点，mark=21，peakHr 105–127 |
| `rr.tachogram.last` | ✅ 48 拍，hz 1.3 |
| `response.meal.last` | ✅ 09-05 有 15 点、峰值 +20；09-06 只有 1 个餐后点，返回 NULL |
| `balance.check.last` | ⬜ `balance_checks` 全库 0 行——还没有人做过平衡测试 |
| `composition.call` | ⬜ 该账号 14 天内 `the_call` 全为 null（置信度 PENDING） |

后两个的 NULL 是数据没有，不是代码不通：两者的读取路径都有单元测试覆盖真实行。

### UI

`NB_DEBUG_PANEL=<type>` 直接吃 `PanelType`，七张新面板不用改 hook 就能钉在屏上，
七张都在模拟器上逐个拍过。落地时抓到三个 UI bug：

1. **两层布局必须一致。** 面板会把图层画两遍（LED 层在点阵屏后、文字层在前）。
   `MeterRenderer` / `VerdictRenderer` / `MatrixRenderer` 原来在文字层里干脆不建柱子，
   两层就错开——子分的名字被压到柱子底下。三个渲染器现在都保留完整几何，只切换上色。
2. **反白 chip 在点阵屏上印不出来。** `call` 原来把选中的判定画成「亮块 + 深色字」：
   块是屏后的 LED，字是屏前的文字，中间隔着一层点阵掩膜，字直接被吃掉。
   改成选中项用 accent 文字加一条 accent 下划线，两者都能穿过屏。
3. **`.large` hero 是给短数字的。** 给 `call` 用了 `.large`，六个字母的 RECOMP 在 60pt
   下直接压穿图表区。回到普通 hero 槽。

4. **散点旁边缺读数。** `poincare` 原来只画云，右半边整片空着——设计稿上 SDNN / LEAD /
   REST SHARE 是贴着云的。`scatter` 这个 kind 现在带 `stats`，服务端从 `balance_checks`
   直接给出这三个值。顺带踩到一个坑：文字层里把点清空会让 `PoincarePlot` 打出
   「NOT ENOUGH BEATS」空状态，正好盖在 LED 层刚画好的云上——文字层要整块不画，不是画个空的。
5. **`NO_CHANGE` 换行顶掉了置信度那一行。** 五个判定要在 322pt 里一行放下，
   第五个按板子的写法缩成 `NO CHG`，每项 `lineLimit(1)`。

另外 `wave` 的目录样本还停在 ECG 的老口径（标题 ECG、footer 写 bpm），
而它现在拿的是毫秒级 RR 序列——样本和 hero（原来算成「平均心率 BPM」）都已改成毫秒。
`WidgetCatalogue` 的表头也从「12 个渲染器」改成 16 个（新增 Meter / Scatter / Matrix / Verdict）。


## 8 · 调试钩子

`NB_DEBUG_PANEL` 原来只在启动后 4 秒赋值一次，随后第一次同步落定会把面板打回 STANDBY——
截图晚一点拍到的就是电量兜底帧，不是被测的那张。钩子现在会持续钉住一分钟（DEBUG only）。
没有这一步，「UI 逐张验过」这句话是不成立的。

`balance_checks` 全库 0 行不是链路坏了：`BalanceCheckQueue` 的写入、
表上的 insert policy 与 grant 都查过，是没有人完成过这个测量流程。
`the_call` 全为 null 也一样——`nb.compute_the_call` 在没有 7 天前那次体成分读数时直接
`return`（返回零行），这个账号的读数不满足，不是判定函数坏了。
