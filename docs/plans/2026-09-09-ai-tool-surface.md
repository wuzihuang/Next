# AI 工具面：现状盘点与「少数几个工具控全 App」的设计 · 2026-09-09

> 起因：用户要求「删除我今天吃的那个猪脚饭」这类话也能说给 AI 听——整个 App 为这个 Agent 而生，
> 所有增删改查和交互都要能用语音驱动；同时工具必须少而抽象，不能给模型扔一百个。
> 依据：`supabase/functions/_shared/{tools,phone-tools,charts,skills,plan,memory,turn-phase,prompt}.ts`、
> `turn/index.ts`、`app/NextBody/Services/PhoneTools.swift`、`App/Router.swift`、各 Feature 目录、
> 全部迁移文件；ADR 0005 / 0011 / 0018 / 0022。本文只做分析与设计，不改代码。

---

## 第一部分 · 现在有哪些工具

### 1.1 模型在一轮 `/turn` 里能看见的工具（共 59 个定义）

| 类 | 数 | 名字 | 在哪执行 | 备注 |
|---|---|---|---|---|
| 服务端只读 | 8 | `day.get` · `data.read` · `data.catalog` · `metric.compare` · `profile.get` · `device.capabilities` · `meals.openSlots` · `meals.search` | Edge Function，用户 JWT，RLS | `data.read` 是 26 个指标的注册表（`metric-query.ts`），`meals.search` 只搜近 30 天 |
| 外部证据 | 3 | `web.search` · `meal.estimate` · `image.inspect`（仅带图时） | Edge Function | 每轮最多 3 次真实搜索 |
| 手机工具 | 11 | `health.prepare` · `device.find` · `device.sync` · `device.alarm.set` · `device.alarm.delete` · `sport.start` · `sport.stop` · `meal.log` · `balance_check.start` · `body_scan.start` · `app.open` | 手机（`PhoneToolRunner`），可续 turn | 5 个需确认：闹钟设/删、运动开/停、记餐；60 s 不点算 CANCELLED |
| 渲染 | 34 | 33 个 `screen.render.<type>` + `plan.render`（Chat 面把 `screen.render.text` 换成教练纯文本） | Edge Function | 带 `source` 的图由服务端填点，35 个数据源（`sources.ts`） |
| 控制 | 3 | `workflow.ready` · `workflow.reread` · `workflow.coach` | Edge Function | 三段 read → act → render 的开关 |

三个面（panel / chat / plan）共用同一套定义；plan 面只开 `plan.render`。每个模型步实际 active 的数量：
读阶段约 26 个（8 + 3 + 11 + 2 个直出 + ready + coach），执行阶段约 15 个，渲染阶段 34 个。
每步都把全部 active 工具的 schema 重发一遍——渲染步的 schema 曾量到 44k 字符、每步 15 s（`charts.ts` 注释）。

随 turn 一起进来、不用调工具的「读证据」：手环状态（电量、连接、充电、上次同步、闹钟表）、长期记忆、
plan 面的 14 天证据。

### 1.2 手机上能用手指做、但模型做不到的事

按「手机已有代码 → 模型能不能调」对了一遍。**✔** 有工具；**✗** 没有；**(有管线)** 表示手机端和云端的
写路径都已存在，只差一个工具把它暴露给模型。

**餐（Fuel）**

| 用户动作 | 手机路径 | 云端路径 | 模型 |
|---|---|---|---|
| 报一顿、记下来 | dock → `meal.estimate` → `meal.log` / 食物帧 CONFIRM | `meal-commit` → `apply_meal_operation(create)` | ✔ |
| 改一顿（文字、kcal、三大营养素、时间、**换餐位**） | `EditMealSheet` → `DataStore.amendMeal` → `MealQueue.enqueueAmend` | `meal-operation`（amend，7 天窗口，不能换天） | ✗ (有管线) |
| **删一顿** | `DataStore.deleteMeal` → `MealQueue.enqueueDelete` | `meal-operation`（delete，软删 `deleted_at`，撤回同意后仍允许） | ✗ (有管线) |
| 标记今天断食（清空当天所有餐） | `FastingAction` → `markTodayFasted` | RPC `mark_day_fasted` | ✗ (有管线) |
| 重试 / 丢弃被拒的餐变更 | `MealQueue.retryRejected / discardRejected` | — | ✗ |
| 语音「确认」上一帧的食物草稿 | 只能点 widget（`HomeView.confirmMeal`） | 草稿只活在本轮 `mealDraft` | ✗（跨轮拿不到草稿） |

**体重与测量（Composition / Measure）**

| 用户动作 | 手机路径 | 云端 | 模型 |
|---|---|---|---|
| 手动记体重（kg/lb） | `WeighInSheet` → `WeighInQueue` | insert `weigh_ins` | ✗ (有管线) |
| 用 Apple Health 的体重 | `WeighInSheet` from-Health | 同上，带 `health_uuid` | ✗ |
| 删体重 | 手机无 UI | RLS 允许 delete | ✗ |
| 做体成分扫描 / 平衡检测 | `Takeover.measure(...)` | 手机队列写 `body_composition` / `balance_checks` | ✔ |
| 心率 / 血氧 / 体温 单次测量 | `Takeover.measure(.heartRate/.bloodOxygen/.temperature)` | 屏上显示，不落库 | ✗ |
| 删一次测量记录 | 手机无 UI，`MeasurementSheet` 只读 | 无 delete 策略 | ✗ |
| 查历史测量列表 | `MeasurementsView` | select | ✗（source 只有 `balance.check.last`） |

**手环（Device）**

| 用户动作 | 手机路径 | 模型 |
|---|---|---|
| 找手环 / 同步 | `startFindHoop` / `OriginDataSync.refreshNow` | ✔ |
| 设 / 删闹钟 | `writeAlarm` / `deleteAlarm` | ✔ |
| **闹钟开关、改时间、改重复日** | `AlarmsSheet.setOn / saveDraft` | ✗ (有管线) |
| 自动测量 10 个槽的开关与间隔（心率、血压、进餐反应、压力、血氧、体温、Lorentz、HRV、科学睡眠、血液成分） | `AutoMeasurementSheet` → `writeAutoMonitoring` | ✗ (有管线) |
| 心率报警上下限 | `BandSetting.heartRateAlarm` 在 SDK 桥里实现完，**App 里无任何调用** | ✗ |
| 读手环的节奏 5/10/15/30/60 分钟 | `SyncCadenceSheet` → UserDefaults | ✗ |
| 固件检查 / 升级 | `checkFirmwareUpdate / updateFirmware` | ✗（长操作，故意不给） |
| 断开 / 忘记手环 | `disconnect` / `unbindBoundDevice` | ✗（破坏性，故意不给） |

**运动（Sport）**

| 用户动作 | 模型 |
|---|---|
| 开 / 停一场 | ✔，但 `sport.start` 只认 run / walk / ride / strength / other 五个词，`SportModeCatalog` 里的其他模式选不到 |
| 暂停 / 继续 / 丢弃 / 事后改 | 手机自己也没有，`LiveSession` 只有 begin / stop / end |
| 查某天的训练段 | 只有 `segments.today` 这一个 source，没有按日期查 |

**建议（Plan）与记忆（Memory）**

| 用户动作 | 手机路径 | 云端 | 模型 |
|---|---|---|---|
| 读今天的建议（「第二条说什么」） | `PlanStore` 读 `daily_plans` | select | ✗（只有 plan 面自己生成时看得见） |
| REFRESH 重新生成 | `PlanStore.refresh` → `surface=plan` turn | | ✗（`app.open plan` 只是打开页） |
| 勾任务 | `PlanChecks` / `PlanTaskCheckQueue` **无调用方**（ADR 0018 已撤销打勾） | `plan_task_checks` | — |
| 「记住我不吃乳制品」 | 只能等会话结束由 `memory-settle` 重写 | 只有 service role 能写 `user_memory` | ✗（用户无法当场核实） |
| 忘掉某一条 / 清空 | `AIMemoryView` 只有 CLEAR ALL | `forget_user_memory()` | ✗ |

**档案与偏好（Profile）**

| 字段 | 手机路径 | 模型 |
|---|---|---|
| 昵称、性别、生日、身高 | `PersonalInfoSheet` / 尺子 / 生日轮 → `saveProfile(editedFields:)` | ✗，`profile.get` 只读 |
| 训练目标 CUT / RECOMP / BULK | `TrainingGoalSheet`（记 `nb.goal.changedDay`，次日生效） | ✗ |
| 单位 KG/LB | `UnitsSheet` → `units_metric` | ✗ |
| 语言 en / zh | `LanguageSheet` → `AppLanguage.set` + `profiles.locale` | ✗ |
| 通知 7 个开关 + 免打扰 22:30→07:00 | `NotificationsSheet` @AppStorage `nb.notif.*` | ✗ |
| 触感开关 | `HapticsSetting.toggle` | ✗ |
| 同意开关、导出、删号、退出登录、Apple Health 授权 | 各自 sheet | ✗（**应该继续不给**，见 2.6） |

**导航与面板**

| 目标 | 模型 |
|---|---|
| 5 个详情页 + plan + chat + `vitals.<metric>` | ✔ `app.open`（9 个词） |
| `device` / `measurements` / `battery` / `sportMode` / `aiMemory` | ✗，`Destination(envelopeTarget:)` 故意不认（`Router.swift:42-62`） |
| 25 张 sheet（weighIn、goal、units、notifications、language、bandAlarms、findHoop、bandAutoMonitor、syncCadence、export…） | ✗ |
| 详情页 DAY / WEEK / MONTH 窗口、Fuel 翻到过去某天、Composition 跳到某天 | ✗ |
| 首页翻到第二页、返回、回根 | ✗ |
| 关掉面板上的 widget | ✗ |
| 开新聊天、切会话、清聊天记录（本机） | ✗ |
| 撤销上一步 | ✗（谁都没有） |

**小结**：手机端已有 45 种左右的用户动作，模型能调的是 11 个。差的大头不是「没有实现」，
而是「有实现、没暴露」——餐的改删、断食、闹钟改、自动测量设置、档案字段、通知设置、导航，
写路径都在，缺的只是工具。

---

## 第二部分 · 应该有哪些工具，以及怎么收成少数几个

### 2.1 从代码里长出来的五条设计约束

这些不是偏好，是线上摔出来的（各条在源码注释里都有出处）：

1. **参数不许 reject。** Zod enum / 硬长度 / 严格 object 只要一处不合，SDK 抛
   `AI_InvalidToolArgumentsError`，整轮死掉，面板回落电量帧。所以 `tag` / `target` / `source` 都是
   string，在 `execute()` 里校验，错值是「一句话」结果（`phone-tools.ts normalizePhoneArgs`）。
   → 新工具一律宽松 schema + 服务端归一化 + `say` 句子。
2. **一个描述里塞 27 种形状，小模型会发明自己的 key。** 这是渲染从一个 `screen.render` 拆成 34 个的原因。
   → 抽象要抽在「动词 × 实体」这个层面，字段表按实体各自固定，不是把所有字段摊平成一个大对象。
3. **id 不许模型编。** 闹钟 id 来自设备状态或上一次 set 的返回。
   → 每个写操作的目标必须能追溯到本轮某次查询、设备状态或 `match` 解析。
4. **confirm 由服务端按工具固定，模型改不了。**
   → 改成按（实体，操作）固定，并且确认框要念出被改的那条记录。
5. **一步一个手机工具；写完才能说「已记录」。** 账本和禁语机制照旧。

### 2.2 推荐的形状：4 个操作工具 + 3 个证据工具 + 渲染 + 控制

```
find    查记录和状态   { entity, id?, day?, from?, to?, query?, limit? }
read    查指标序列     { metric | metrics[], from?, to?, bucket? }
write   改记录和设置   { entity, op, id? | match?, fields? }
do      执行动作/导航  { action, ...params }

web.search · meal.estimate · image.inspect        （原样保留）
screen.render.<type> ×33 · plan.render            （原样保留，见 2.7）
workflow.ready / reread / coach                    （原样保留）
```

定义总数从 59 降到 44；**非渲染工具从 25 个降到 10 个**。读阶段 active 的工具从 26 个降到约 11 个。
模型要学的不再是 25 个名字，而是一张「实体 × 操作 × 字段」表，放进系统提示替换现在的 S10 和
PHONE TOOLS 两段。

为什么不是一个 `app {verb, entity, ...}` 工具：那正是约束 2 描述的失败形态——动词、实体、字段三个维度
挤进一段描述，每种组合的字段又不同，qwen-flash 会开始猜 key。四个工具的分法让「查 / 序列 / 写 / 做」
各自有一张不重叠的字段表，schema 仍然小到每步重发不心疼。

`find` 与 `read` 为什么分开：`read` 的返回带 evidence 与 stats 进账本、有 366 天 / 2 天的窗口裁剪、
是画图前的取证；`find` 返回的是带 id 的记录列表，是写操作的前置。合在一起会把两套返回形状混进
一个工具。

### 2.3 `find` / `write` 的实体总表（这就是「全集」）

执行地：**手机** = 走 `PhoneToolRunner`，可续 turn，写本机 DataStore + outbox，离线也排队；
**服务端** = Edge Function 直接用用户 JWT 写。确认 = 服务端按（实体，操作）固定，框里念出记录。

| entity | `find` 返回 | `write` 操作与字段 | 确认 | 执行地 | 今天缺什么 |
|---|---|---|---|---|---|
| `meal` | 某天/某范围的餐：id · slot · name · kcal · 三大营养素 · logged_at · editable(7 天内) | `create {name, kcal, protein_g, carb_g, fat_g, slot, day, at}` / `update {同上任意子集}` / `delete` / `restore` | create / update / delete 要；restore 不要 | 手机 → `meal-commit` / `meal-operation` | 只差工具。字段表直接复用 `meal-operation.ts` 的 `Fields` |
| `day` | 某天的四个上屏数 + intake_state（今天的 `day.get`） | `update {fasted: true}`（清空当天餐） | 要，念出会被清掉的餐 | 手机 → `mark_day_fasted` | 只差工具 |
| `weigh_in` | 范围内的体重：id · kg · source · measured_at | `create {weight, unit, at}` / `delete` | create 要（进结算）；delete 要 | 手机 → `WeighInQueue`；delete 直连 | create 只差工具；delete 手机端要补一个删除路径 |
| `measurement` | 范围内的体成分扫描 / 平衡检测：id · kind · 关键字段 | `delete`（待定） | 要 | 服务端 | 两张表今天没有 delete 策略，先只做 find |
| `alarm` | 手环闹钟表（已在设备状态里，`find` 只是同一份的显式读） | `create {time, days, label}` / `update {id, on, time, days, label}` / `delete` | 三个都要 | 手机 → 手环 | update 只差工具（`AlarmsSheet.setOn/saveDraft` 已有） |
| `band_setting` | 10 个自动测量槽：slot · on · interval_min · window · 可改性 | `update {slot, on, interval_min}` | 要（改间隔影响续航） | 手机 → `writeAutoMonitoring` | 只差工具 |
| `hr_alarm` | 心率报警：on · low · high | `update {on, low, high}` | 要 | 手机 → `BandSetting.heartRateAlarm` | SDK 桥已有，App 无 UI，需接一次 |
| `sync_cadence` | 当前分钟数 | `update {minutes ∈ 5/10/15/30/60}` | 不要 | 手机 UserDefaults | 只差工具 |
| `profile` | name · sex · birth · height · goal · units · language · timezone | `update {name / goal / units / language}`；`update {height / birth / sex}` | goal / units / language 不要（可逆）；身高 / 生日 / 性别要（进算法） | 手机 → `saveProfile(editedFields:)`（保住 `field_sources`） | 只差工具。goal 沿用「次日生效」 |
| `notification` | 7 个开关 + 免打扰时段 + 系统授权状态 | `update {kind, on}` / `update {quiet: {from, to}}` | 不要 | 手机 @AppStorage + `applyPrefs` | 只差工具；`applyPrefs` 今天只会取消不会重排，开回去要补 |
| `haptics` | on | `update {on}` | 不要 | 手机 | 只差工具 |
| `plan` | 某天的建议：title · summary · tasks[]（`daily_plans`） | —（重生成走 `do plan.refresh`） | | 服务端 | 只差读工具 |
| `memory` | summary + facts[]（带 at / source） | `create {text}` / `delete {index \| query}` / `delete all` | 单条不要；清空要 | 服务端 | **需要新 RPC** `upsert_user_memory_fact` 在用户 JWT 下写（今天只有 service role 能写） |
| `sport_session` | 范围内的训练段：day · start · minutes · zone · 负荷（`daily_training.segments`） | — | | 服务端 | 只差按日期查的读工具（现在只有 `segments.today`） |
| `chat_session` | 本机会话列表：id · title · updated_at | `create` / `delete {id}` / `delete all` | delete 要 | 手机本地 | 手机端要补单条删除 |
| `device` | 身份 · 电量 · 固件 · 能力表（= 设备状态 + `device.capabilities`） | —（忘记 / 断开 / 固件不给语音） | | | 已有 |
| `screen` | 面板当前帧（type · title · 是否食物草稿） | `delete`（关掉 widget） | 不要 | 手机 | 只差工具 |
| `draft` | 面板上待确认的食物草稿 | —（确认走 `do panel.confirm`） | | 手机 | 草稿要从「只活在本轮」改成手机持有到确认或过期 |

`find` 的通用返回：`{ ok, data: { items: [{id, label, ...}], count, truncated } }`，每条都带一个给确认框
念的 `label`（「12:30 · 午餐 · 猪脚饭 · 680 kcal」）。数字照常进账本。

### 2.4 `do` 的动作总表

`do` 收所有不是「改一条记录」的动词。`action` 是 string，服务端校验，错值返回可用列表。

| action | 参数 | 确认 | 备注 |
|---|---|---|---|
| `device.find` | `{stop?: true}` | 不要 | 现在的 `device.find`（4 s 后自动停） |
| `device.sync` | — | 不要 | 现在的 `device.sync` |
| `health.prepare` | — | 不要 | 现在的 `health.prepare` |
| `sport.start` | `{mode}` | 要 | mode 对整个 `SportModeCatalog` 归一化，不只五个词 |
| `sport.stop` | — | 要 | |
| `measure.start` | `{kind: balance_check \| body_scan \| heart_rate \| blood_oxygen \| temperature \| blood_pressure}` | 不要（流程自己有取消） | 合并 `balance_check.start` / `body_scan.start`，补上另外四种 takeover；不支持的 kind 按能力表返回 UNSUPPORTED |
| `plan.refresh` | — | 不要（扣额度，但用户点 REFRESH 也扣） | 触发 `PlanStore.refresh` |
| `panel.confirm` | — | 要（就是现在点 CONFIRM 那一下） | 确认面板上待确认的食物草稿 |
| `panel.dismiss` | — | 不要 | |
| `app.open` | `{page, window?, day?, sheet?}` | 不要 | 见下表 |
| `app.back` / `app.home` | — | 不要 | |
| `chat.new` | — | 不要 | |
| `undo` | — | 不要 | 撤销本会话最近一次 `write`（餐用 restore，闹钟用反向 set，设置用旧值） |
| `export.start` | — | 要 | 等 `ExportSheet` 真能发出去再开 |

`app.open` 的寻址全集（把 `Router.Destination` / `SheetRoute` / `Takeover` 三个枚举整个交出来）：

- **页**：`home` · `home.vitals`（第二页） · `training` · `fuel` · `bodyBattery` · `composition` · `profile` ·
  `measurements` · `device` · `device.battery` · `device.autoMonitor` · `sportMode` · `chat` · `plan` · `aiMemory` ·
  `vitals.<sleep|heart|stress|temp|steps|distance|active|hrv|response>`
- **参数**：`window: DAY|WEEK|MONTH`（有 `SegmentedPills` 的页）· `day: YYYY-MM-DD`（fuel 翻到过去某天、
  composition 跳到某天、measurement 某条 id）· `session: <chat id>`
- **sheet**：`weighIn` · `profileEdit` · `goal` · `units` · `language` · `notifications` · `appleHealth` ·
  `bandAlarms` · `findHoop` · `bandAutoMonitor` · `syncCadence` · `export` · `about` · `privacy` · `plusMenu`
- **只能打开、不能替用户点的**：`deleteAccount` · `signOut` · `unbind` · `disconnect` · `firmware` · `consent`

`Destination(envelopeTarget:)` 今天故意只认 9 个词，是 F0 rule 06「widget 落地页只有六个」的延伸；
语音导航是另一回事，应该单独给 `app.open` 一张全表，不动 widget 的 `target`。

### 2.5 一句话是怎么落到工具上的

「删除我今天吃的那个猪脚饭」：

```
write { entity: "meal", op: "delete", match: { day: "today", query: "猪脚饭" } }
```

服务端在 `execute()` 里、挂起之前就把 `match` 解析掉（复用 `meals.search` 的查询）：
0 条 → `NOT_FOUND`，让模型如实说；2 条以上 → `AMBIGUOUS` 附候选 `[{id,label}]`，模型可以追问或
直接选；正好 1 条 → 换成 `id` 交给手机，确认框念「删除 12:30 午餐 · 猪脚饭 · 680 kcal？」。
用户点了，手机走 `DataStore.deleteMeal` → outbox → `meal-operation`，返回
`{ok:true, code:"OK", data:{record}, undo:{entity:"meal", op:"restore", id}}`。
一次工具调用、一次确认，S10 的禁语在 ok:true 之后解除。

「把中午那顿改成晚餐」→ `write meal update match:{day:today, slot:LUNCH} fields:{slot:DINNER}`。
「心率自动测量改成每 10 分钟」→ `write band_setting update fields:{slot:heartRate, interval_min:10}`。
「别再提醒我吃饭」→ `write notification update fields:{kind:meals, on:false}`。
「记住我膝盖有旧伤」→ `write memory create fields:{text:"膝盖有旧伤"}`，当场写进 facts，不等会话结束。
「打开手环设置」→ `do app.open {page:"device"}`。「看这周的」→ `do app.open {window:"WEEK"}`。
「刚才那个不要了」→ `do undo`。

`match` 只解析实体表里声明过的键（meal：day / slot / query；alarm：time / label；weigh_in：day）。
模型不给 `id` 也不给 `match` 就是 `BAD_ARGS` 一句话。

### 2.6 故意不给语音的

同意的授予与撤回、删号、退出登录、忘记手环、固件升级、Apple Health 授权、断开手环。
理由各不相同（法律、不可逆、系统对话框、长操作），处理方式相同：`app.open` 可以把那张 sheet 打开，
最后一下留给手指。这条要写进提示词，免得模型在 `do` 里试。

### 2.7 渲染工具要不要也收

暂不收，但记一笔。34 个渲染工具占了每步 schema 的大头（44k 字符那次就是它们）。它们拆开的理由是
「自由 `data` 让模型发明 key」，而现在 `data` 已经不在参数里——带 source 的图只剩公共文字槽 + `source`，
无 source 的只有 text / metric / food 三种私有字段。理论上可以收成一个
`render {type, source?, ...公共槽, ...三种私有字段}`，`type → 允许的 source` 表放进 S11。
这会把渲染步 schema 缩到约 1/30，但要用 `turn-matrix.py` 跑一遍 33 种图再定，别凭感觉翻 2026-09-03 的裁决。

### 2.8 工程上怎么落

1. **一个来源文件**：仿 `skills.ts`，新建 `_shared/entities.ts`，声明每个实体的 find 字段、write 操作、
   字段归一化、confirm、执行地、`match` 键、`undo` 方式。由它生成：四个工具的 description、系统提示的
   实体表（替换 S10 + PHONE TOOLS）、`docs/prd/` 里的一页、以及手机端 `PhoneToolRunner` 的实体枚举
   （JSON 下发或 codegen，避免两边手抄不一致——`PHONE_PAGES` 和 `Destination(envelopeTarget:)` 已经
   是两份手抄）。
2. **手机端**：`PhoneToolRunner` 的 dispatch 从「按工具名」改成「`write` 按 entity、`do` 按 action」；
   确认框文案从 `label` 生成；补 weigh_in 删除、chat 单条删除、通知重排、hr_alarm 接线、草稿持有。
3. **服务端**：`write` 在 execute 里解析 `match`、归一化字段、决定 confirm，再按现在的方式挂起；
   memory 需要新 RPC（用户 JWT 下写 facts）；`plan` / `sport_session` / `measurement` 的 find 是纯读。
4. **阶段门禁不变**：`find` 与 `read` 归读工具；`write` 与 `do` 归手机工具，一步一个；写结果进账本。
5. **过渡**：旧的 11 个手机工具名保留一个版本作为别名（`device.alarm.set` ≡ `write alarm create`），
   `turn-matrix.py` 的用例照跑，加上 2.5 那组句子。
6. **分期**：第一期只把「有管线、只差工具」的接上（餐改删、断食、闹钟改、档案、通知、导航全表、
   plan 读、panel 确认/关闭、undo）；第二期做要动手机或建表的（memory 单条、自动测量、hr_alarm、
   体重删、测量删、chat 单条、草稿持有、measure 四种）；第三期看渲染要不要收。

### 2.9 顺手发现的死角

- `PlanChecks.swift` 与 `PlanTaskCheckQueue` 无调用方（ADR 0018 撤销打勾后没删）。
- `Router.dockPrefill`（回填过去某天）有消费者、没有生产者。
- `LogMealSheet` 只在 `NB_DEBUG_FUEL_PLATE=1` 下能打开。
- `PersonalInfoSheet` 的手机号是写死的占位，从不保存；`UnitsSheet` 的身高单位只是本地 `@State`。
- `NotificationReach.applyPrefs()` 只取消、不重排，关了再开不会恢复。
- `ExportSheet` 只数行数，不会真的发出去。

---

## 落地记录 · 2026-09-09 下午

**已上线（turn v75，迁移 `20260909170000_memory_edited_by_voice.sql` 已通过 Management API 应用到生产库）**

- 服务端：`_shared/entities.ts`（实体表、归一化、match 解析、导航全表、提示词段）、`_shared/normalize.ts`（从 phone-tools 拆出的值归一化）、`tools.ts` 只剩 `find` + `read`、`phone-tools.ts` 只剩 `write` / `do` / `health.prepare`、`prompt.ts` 换成 ENTITIES / ACTIONS 段、`freshness.ts` 的 `device.settings`、`turn/index.ts` 的 match 解析与服务端 memory 写入。Deno 278 个测试通过。
- 手机端：`PhoneToolRunner` 按 entity / action 分发，确认框文案从 `label` / fields 生成，undo 栈；`Router.windowRequest`；HomeView 借出 `panelHandler`（确认草稿、关面板、刷新建议、面板状态）；五个详情页 `onReceive(router.$windowRequest)`；`SupabaseClient.deleteWhere`。Debug 构建通过。
- 生产实测（turn-resume.py）：「删除我今天吃的猪脚饭」→ `write meal delete match` → NOT_FOUND → `find meal` → 如实文字帧；「设一个七点的工作日闹钟」→ `write alarm create` confirm:true 挂起 → 续跑成功帧；「记住我膝盖有旧伤，不要安排深蹲」→ 服务端 `edit_user_memory` 当场落库（已查库核实）。
- 模拟器实测（iPhone 17 Pro · iOS 26.1）：「别再提醒我吃饭了」→ `nb.notif.meals=false` 已写入、面板「已关闭」；「设一个七点的工作日闹钟」→ 确认框「在手环上设这个闹钟? 07:00 · MO TU WE TH FR」→ 点确认 → 「已设」；「打开手环页」→ 直接落到设备页（此前 `Destination(envelopeTarget:)` 故意挡住的页）。

**没做完 / 需要注意**

- `chat_session` 单条删除返回 UNSUPPORTED（ChatStore 没有单条删除）；`measurement` 只有 find；`hr_alarm` 走 `writeSetting` 但从未在真手环上试过。
- `band_setting` 的 find 依赖手机上次读过自动测量槽（`remember(slots:)` 只在 `write` 之后调用，`AutoMeasurementSheet` 还没接 `remember`）。
- 渲染工具没收（2.7 节），`data.read` / `day.get` 等旧名已从 turn 移除，旧手机构建的 `meal.log` 等名字不再被服务端认识：手机版本要跟 turn v75 一起发。
- 共享树里 `sources.ts` 有别的会话 27 行未部署改动，这次部署用的是线上版本，没有带上。

## 模拟器实测第二轮 · 2026-09-09 · 找到并修掉的问题

iPhone 17 Pro（iOS 26.1），每句用 `NB_DEBUG_TURN` 走真实 dock 路径，看屏、看 `NB turn ·` 日志、查云端行。跑了 20 句。

| 问题 | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 冷启动「我有哪些闹钟」答「没有闹钟」 | 假阴性 | 手机只在打开闹钟表后才缓存闹钟；设备状态里没有 `alarms` 键时 `find alarm` 返回空表 | 服务端：没有 `alarms` 键 = 未读，返回 `data:null` 并要求写 ——；手机：`deviceState` 发现没缓存且手环在线就后台读一次（`primeAlarmsIfNeeded`），设备页读到闹钟/自动测量槽也交给 runner 缓存 |
| 2 「把震动关了」说成「手环震动」 | 措辞错 | 实体描述只写 haptics on/off | 描述改成「手机触感反馈，不是手环」 |
| 3 「打开闹钟设置」弹出一张黑 sheet | UI 空白 | `RootView.SheetHost` 没有 bandAlarms 等设备 sheet 的视图；这些 sheet 由 `DeviceView` 自己的 `@State` 呈现 | 新增 `Router.deviceSheetRequest`，DeviceView `onReceive` 后自己弹；导航先推设备页再 700 ms 发请求 |
| 4 改餐确认框英文「Change this meal?」、`15:14Z · LUNCH` | 没本地化、UTC 时间 | 新增的 L() 键没进 zh-Hans.json；服务端 label 用 UTC 小时和英文餐位 | 补 40 余条中文；`resolveMatch` 收 tz/locale，用户时区 HH:MM + 中文餐位；update 的确认框附「→ 餐位 午餐」 |
| 5 **改餐报「已挪到晚餐」但云端没变** | 假成功 | 两层：a) 线上 `meal-operation` v4 不认 `logged_at`（工作树里别的会话已修未部署，App 自己的编辑 sheet 对线上也是坏的）；b) runner 用 `DataStore.amendMeal` 吞掉错误、也不等 outbox 回执就报 ok | 部署 `meal-operation` v5（带 `logged_at`）；runner 改为直接 `MealQueue.enqueueAmend/Delete`，然后 `settleMealOutbox`：flush、刷新状态、有新 rejection 就返回 WRITE_FAILED 附服务端原因 |
| 6 测试驱动脚本自己的 bug | 日志窗口带上一句的行，3 秒就把 turn 杀了 | 脚本问题，不是 App | 改为按 `NB turn` 行数计数 |

**修后复测（turn v76 · meal-operation v5 · 新构建）**：「我有哪些闹钟」→「闹钟 · 待读取」如实；「打开闹钟设置」→ 设备页 + 闹钟表（两条 07:30 / 08:45）；「把今天晚餐那顿猪脚饭改回午餐」→ 确认框「11:19 · 晚餐 · 猪脚饭 · 850 kcal → 餐位 午餐」→ 云端出现 `voice-amendment-v1` 午餐行、旧行软删；「删除我今天吃的猪脚饭」→ 确认框念出记录 → 云端当天 live 行 = 0。

**这一轮通过、没改的**：我今天吃了什么 / 今天建议第一条 / 你记得我什么 / 读手环改半小时 / 改增肌目标（云端 profile 同步）/ 看这周的训练（周窗口）/ 记住不吃香菜、忘掉不吃香菜（服务端记忆）/ 撤销（冷启动后如实说无可撤）/ 近一周夜间 HRV（metric 帧）/ 记一碗猪脚饭（估算 → 确认 → 云端 create）/ 把训练目标改回减脂。

**对真实账号的副作用**：测试期间训练目标 BULK→CUT 已改回原值；记忆里多了「膝盖有旧伤不排深蹲」「工作日闹钟 7:00」两条测试事实（可语音「忘掉」）；今天的猪脚饭记录已全部软删；触感、读取节奏、吃饭提醒只改在模拟器本机。

**仍未验证**：hr_alarm、band_setting 写入需要真手环；weigh_in 删除；measure.start 的四种单次测量；chat 面的 write。

## 模拟器实测第三轮 · 2026-09-09 · 剩余项目

新增 DEBUG 钩子 `NB_DEBUG_TURN2` / `NB_DEBUG_TURN2_AFTER`：同一次 App 会话里发第二句，用来测「结束运动」「撤销」「确认草稿」这类依赖前一句的工具。

**通过的**：记体重 72.5 公斤（云端 `weigh_ins` 新行）→ 删掉今天那条体重（云端行数归零）；心率超过 160 提醒（改 claims 宽松后渲染成功）；心率自动测量改每 10 分钟；开始一场瑜伽（LIVE · YOGA 实时页）→ 70 秒后「结束运动」（确认框 → 已结束，163 条实时心率样本上云）；把震动打开 → 45 秒后「撤销刚才那个」（`nb.haptics.enabled` 回到 false）；今天标断食（`fasted_days` 新行）；打开训练页 → 返回首页；Chat 面 `write notification`（服务端脚本）。

**找到并修掉的**（turn v78，手机新构建）

| 问题 | 根因 | 修法 |
|---|---|---|
| 7 心率报警写成功后整轮报「请求未完成」 | 模型在 `screen.render.text` 的 `claims` 里写 `"to": null`，schema 不可空 → `AI_InvalidToolArgumentsError` 杀掉整轮 | `claims` 改为 `z.any()`，`normalizeClaims()` 在 execute 里过滤（charts.ts） |
| 8 手环设置 / 心率报警的确认框原样打印字段（`interval_min 10 · slot heartRate`、`on 1`） | 没走翻译 | `fieldWord` / `valueWord` / `slotName`，补 zh 键 |
| 9 「测一下血氧」打开的是「电量检查」（心率/HRV 测量页） | `MeasureTakeover` 只实现心率、平衡检测、体成分三种，其余 `MeasureKind` 落进心率路径 | 服务端 `measure.start` 只接受这三种，血氧/体温/血压返回一句「没有按需测量，用 read 读自动采样」；手机端同样 UNSUPPORTED |
| 10 「确认，记下来」返回 NO_DRAFT | `AIService.turn()` 一开始就 `mealDraft = nil`，且 Home 的 handler 用当前 `widget`（第二轮已是 THINKING） | 草稿随帧存活 20 分钟；`pendingMealDraftFrameID` / `pendingMealDraftLabel`；确认框显示「香蕉 · 105 KCAL」 |
| 11 语音确认草稿报「已记入」但云端被拒 | `confirmMeal` 只入本地 outbox 就返回 | `panel.confirm` 之后也走 `settleMealOutbox`，拒了就 WRITE_FAILED / FASTED_DAY |
| 12 断食标记被拒时只说「取消」 | `markTodayFasted` 在 outbox 有待同步餐时抛裸 `CancellationError` | 先 flush，`pendingCount > 0` 返回 PENDING_MEALS 并说明 |
| 13 CANCELLED 的 message 是枚举的 localizedDescription（「错误0」） | 直接透传 | 执行类失败不带 message |
| 14 体重删除后模型说「可用撤销」但没有撤销项 | 没 pushUndo | 删除前记下那条，undo 时重建 |

**仍留着的瑕疵**：Chat 面 locale=en-US 时 Coach 用中文答（Coach 提示词层面，不属于本次）；撤销触感时模型仍说「手环震动」（措辞）；`MealPublication` 的 rejection 文案是通用句，看不出是断食日拒的；`measure.start` 只剩三种。

**对真实账号的副作用（本轮）**：今天被标成断食日（服务端无取消接口，明天自动过去）；体重 72.5 已删；运动记录里多了一场 1 分钟的瑜伽（模拟器 mock 手环的实时心率样本上云 163 条）。

## 真机实测 · 2026-09-09 · iPhone 17 Pro Max + 真 HOOP

`xcodebuild -destination 'platform=iOS,id=00008150-0011293C2E21401C' -allowProvisioningUpdates` → `devicectl device install app` → `devicectl device process launch -e '{"NB_DEBUG_TURN2":"…","NB_DEBUG_TURN2_AFTER":"35","NB_DEBUG_AUTOCONFIRM":"1"}'`，日志走 `idevicesyslog -o`（`NB turn ·` / `NB phone ·` 两类公开行）。手机登录的是账号 9c59c2e5…，不是模拟器用的 e1c2…。

**通过的**：设 07:30 工作日闹钟（手环回读确认）→ 冷启动「我有哪些闹钟」直接列出 07:30 + 08:20 → 「把七点半的闹钟关掉」→ 「删掉七点半那个闹钟」（手环恢复到只剩原来的 08:20）；心率超过 160 报警写入手环；找手环震动；同步手环（0 新点、电量 52% 充电中）；心率自动测量读取。

**找到并修掉的**（turn v80，手机构建）

| 问题 | 根因 | 修法 |
|---|---|---|
| 15 **真机上确认框从不出现**，每次准点 60 秒超时 | SwiftUI `.alert(_:isPresented:presenting:)` 在 iPhone（iOS 26.3）上没有呈现，模拟器（26.1）却能；日志证明 prompt 已发布、前台、无 takeover/sheet | 改成 App 自己画的 `PhoneToolConfirmOverlay`（RootView `.overlay`），日志 `overlay shown` 证实显示；加 `NB_DEBUG_AUTOCONFIRM=1` 让测试机自动确认 |
| 16 冷启动后闹钟 `match` 全部 NOT_FOUND | 服务端只按随 turn 上传的设备状态解析，而缓存每次重启都空 | 服务端拿不到闹钟表时把 match 原样交给手机；手机 `readAlarms()` 后按 time/label 自选；`OriginDataSync.refreshNow` 之后 `primeAlarms()`，首问就有列表 |
| 17 改心率自动测量间隔时模型连试三次耗尽续跑额度，落到「请求未完成」 | 固件 `intervalModifiable=false` 是合法的 UNSUPPORTED，但 BAD_ARGS 文案列了 0–180 一长串「可选间隔」误导模型 | 先判可改性、给「结果已定，不必重试」的文案；服务端 `refusedThisTurn`：同一实体/动作本轮已 UNSUPPORTED 就不再挂起 |
| 18 `auto_monitor` 的 `allowed_intervals` 是 181 个数 | 固件步长 0 = 每分钟 | 超过 12 个只给区间 |

**这只手环的事实**：固件不允许 App 开关或改间隔任何自动测量槽（`slotModifiable=false`、`intervalModifiable=false`），设备页的开关本来也是灰的；模型在这种情况下会自己编「到手环设置里打开」——手环没有屏幕，这是提示词层面要补的一句。

**没在真机上试的**：体重、餐、断食等云端写入（和模拟器路径相同，没重复）；`sport.start` 真运动；测量接管（平衡检测/体成分要人戴着做）。

## 收尾 · 2026-09-09 · 剩余瑕疵全部处理（turn v81 · meal-operation v6 · meal-commit v9）

| 瑕疵 | 修法 | 复测 |
|---|---|---|
| Chat 面 en-US 用中文答 | `coach.ts` 两种语言各加一句语言锁定（不管记忆/历史/工具结果是什么语言） | 服务端脚本：「stop reminding me about meals」→ 英文回答 |
| 撤销触感被说成「手环震动」/ 读反 | haptics 记录带 `what: phone haptic feedback, not the band`；undo 返回 `now / reverted / undone`；提示词补「手环没有屏幕和设置，UNSUPPORTED 哪里都改不了；haptics 是手机」 | 模拟器：「把震动打开」→「撤销」→ 值回 false，帧说明是手机触感 |
| 本地拒绝文案看不出原因 | `meal-operation` 22* 错误带 `reason`（DAY_ALREADY_FASTED / MEAL_EDIT_WINDOW_CLOSED…）；`MealPublication` 把它写进 rejection；runner `rejectionCode()` 映射成 FASTED_DAY / EDIT_WINDOW_CLOSED / NOT_FOUND | 模拟器：断食日「确认，记下来」→ `FASTED_DAY … [DAY_ALREADY_FASTED]` → 帧「今天被标成了断食日，没能同步」 |
| 模型编「到手环设置里打开」 | 提示词那一句 | — |
| 体重删除确认框里的英文 source | `resolveMatch` label 用中文来源词 | — |
| chat_session 单条删除 UNSUPPORTED | `ChatStore.deleteSession(id)` + runner 接线 | 编译通过，未单独跑 |

**明确不做的**：`measurement` 删除（体成分/平衡检测是结算输入，两张表没有 delete 策略，删了要连带重算，超出本次范围）；`hr_alarm` 的 find 只能给本会话写过的值（SDK 没有读接口）。

真机那版还差最后一次安装（含撤销返回形状和聊天删除），手机当时已断开。

## 优化 · 2026-09-09 晚 · 渲染工具收拢（turn v82）

2.7 节的问号有了答案。量过每个模型步重发的工具 schema：读阶段 ≈ 7.0k 字符，渲染阶段 33 个 `screen.render.<type>` ≈ **32.2k**（每步都重发）。现在只保留三个直出工具（text / food / metric，它们各有私有字段，且允许在读/执行阶段直出），其余 30 种带 `source` 的图收成一个 `screen.render {type, source, …公共槽}`，`type → sources` 表和 35 个数据源的说明只在这一个工具的描述里写一遍；S11 的选图规则不变。渲染阶段降到 **7.6k**（−76%）。`buildChartTools` 仍在（被 `buildRenderTools` 内部复用、被测试和文档生成器使用），阶段门禁不变（`isRenderTool` 按前缀）。

真实模型复测 8 句：周负荷 → `screen.render{type:days}`、昨夜 → `score`、30 天体重 → `line`、电量/心率 → metric、无数据 → text；未见 `type`/`source` 选错，单轮 12–30 秒。模拟器：「这周训练负荷怎么样」→ days 帧解码正常。

之前想过的「一个 `app {verb, entity}` 工具」仍然不做，理由不变（动词 × 实体 × 字段挤进一个描述）。
