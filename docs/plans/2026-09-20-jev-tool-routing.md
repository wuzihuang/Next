# Jev 工具路由与图表选择：实施、实测与启用 · 2026-09-20

> 依据 ADR 0031。本文记录改了什么、实测到什么、哪些没验证，以及怎么开、怎么关。
> 下文保留首轮评估历史；当前发布状态见本节。首轮未达标后已补充否定拒绝守卫，并用冻结的新测试集重新评估。

## 本次发布验证（2026-09-20）

**生产 `turn v104`（JWT 校验开启）已部署；回下载的 43 个运行依赖文件与验证候选逐字一致。**

用户授权上线后，仅开放 `fast.single_read` 的 **guided** 路径：JEV 选工具、图表、窗口，Grok 读取并写答案。
模型 `jev-1.13.0`，问题版本 `2026-09-20.3`，目录 `cat-fb49a451`。
生产配置为 `JEV_MODE=on`、`JEV_TASK_ALLOWLIST=fast.single_read`；
`JEV_ALLOW_UNEVALUATED=false`、`JEV_ASSISTED_ENABLED=false`、`JEV_TEMPLATE_FAST=false`。
复杂请求、写入、图片、Coach、plan、续跑继续原流程；ASR 仍为 Qwen。

- 新冻结集 `jev-release-set.json`：108 条；60 条应路由，实际准入 59 条且全部正确；48 条应回退均回退。
  决策 p50 329 ms / p95 442 ms。结果见 `results-2026-09-20-release.json`。
  这是有限样本观察值，不代表已统计证明所有流量达到 99%。assisted 仍未达到发布条件。
- 从生产 v103 下载运行依赖并最小合入 JEV，未夹带工作区中的餐食、模型超时与其他未发布改动。
- 为已知指标提供直接读取参数，省掉指标目录查询；guided 遇到只输出散文时最多提醒一次，
  修复渲染被拒后不再出图的问题；仍保留措辞、数字审计、步骤预算与每步记账。
- 发布候选 `deno check` 通过；路由、渲染、用量、阶段、价格和真实 handleTurn 测试 **108 passed**。
- 按生产实际迁移集重建后，JEV / quota / lease / Pro 四组 pgTAP 共 **81 assertions** 通过。
  `20260920140000_jev_routing_accounting` 已迁移，价格与服务角色权限已核对。

真实生产基础设施使用临时合成用户及固定七天餐食数据做同题对照，计时包含完整 SSE 返回：

| 请求 | 原流程 | JEV guided | 结果 |
|---|---:|---:|---|
| 今日热量 | 24.676 s | 10.822 s | 600 kcal，目标 1495 |
| 今日蛋白质 | 18.429 s | 36.917 s | 40 g，目标 145；首次模型响应慢，并有一次措辞纠正 |
| 七天热量趋势 | 15.229 s | 8.390 s | 750 / 725 / 700 / 675 / 650 / 625 / 600 |
| 无睡眠数据 | — | 10.587 s | text 空状态，没有编造睡眠分数 |
| 两天热量对比 | — | 18.509 s | 原流程完成 |

正式接口发布后再次验证：热量 **10.950 s**、蛋白质 **22.957 s**、七天趋势 **13.936 s**，
三轮数据、图表与完成事件全部正确。JEV 决策分别 285 / 163 / 186 ms；数据库均为一次 JEV 调用，
Grok 分别 2 / 3 / 2 步。蛋白质仍有一次措辞纠正。相同 operation 重放 1.426 s，
没有工具重跑，JEV 用量仍只有一条；匿名访问 401、失效 Pro 权益 402。
`npm run lint` 通过（117 files）。临时测试函数与合成账号已清理，未修改真实用户的会员权益。

这些是小样本，不能据此声称所有请求加速或整体 p95 改善。JEV 已减少部分步骤，主要尾延迟仍来自 Grok。
初次蛋白质测试出现 `WORKFLOW_OUTPUT_REQUIRED`，已在发布前修复，并通过故障重现测试及真实完整请求。
本次仅服务端变更，没有重新构建 iOS；真机操作延迟不包含在上述 API 计时中。

---

## 一 · 实际调用链与改动位置

一次面板文本请求，改动前后的差别只有一段：

```
handleTurn
  身份 → 同意 / 删除态 → 体裁校验 → Pro 权益 → 幂等重放 → 速率 → claim_ai_turn（租约）
  → 续跑状态 / 手机结果 → 额度（每个 operation 一次）→ 记忆 / 新鲜度 / 证据预取
  → 建工具：buildTools · phone-tools · buildRenderTools · controls → traceTool 包一层
  ┌─ 新增：ADR 0031 路由分支（turn/index.ts，模型循环之前）
  │    jevConfig() → routeTurn(本轮原文 / 语言 / 用户日)
  │    accept（默认 guided）→ 收窄工具面 + 写死时间范围 + 附一段 <routing> 说明，
  │                           然后照常进下面那个模型循环，由 Grok 取证并写话
  │    accept 且 JEV_TEMPLATE_FAST=true → runFastTurn：服务端读来源 + 模板文案，零模型
  │    其它 → 什么都不做，原样往下走
  └─ while (!envelope && !pending) runStep()   ← 原来的模型循环，guided 也走这里
  → 封禁词扫描 → 数字账本审计 → record_claimed_ai_turn → SSE screen.render / done
```

新文件都在 `supabase/functions/_shared/`：`typesafe.ts`（适配器）、`decision-router.ts`（问题与
拒绝）、`chart-selection.ts`（候选）、`fast-turn.ts`（执行）、`fast-copy.ts`（文案）、
`jev-policy.ts`（阈值策略）。`turn/index.ts` 只加了一个分支、一个 `probeSource`、一个
`explainReading`；`charts.ts` 导出了已有的 `FAMILY_KIND`；`ledger.ts` / `ai-quota.ts` 各加了一个
函数。没有新微服务、没有第二套图表目录、没有关键词业务路由。

## 二 · 第一批接入的任务

| 指标 | 窗口 | 展示 | 绑定（chart:source） |
|---|---|---|---|
| 今日摄入 | TODAY | 目标进度 / 标量 | `ring:kcal.today` |
| 今日蛋白质 | TODAY | 目标进度 / 标量 | `ring:protein.today` |
| 今日已记餐 | TODAY | 构成 / 逐项 | `meal:meals.today` |
| 今日训练负荷 | TODAY | 目标进度 | `ring:load.today` |
| 今日步数 | TODAY | 趋势 / 构成 | `bars:steps.today` |
| 今日心率 | TODAY | 趋势 | `line:heart.today` |
| 身体电量 | TODAY | 此刻 / 曲线 | `battery:battery.now` · `line:bodyBattery.today` |
| 昨夜睡眠结构 | LAST_NIGHT | 构成 / 分期 | `split:sleep.mix` · `hypnogram:sleep.stages` |
| 昨夜睡眠分数 | LAST_NIGHT | 标量 / 子分 | `score:sleep.score.night` |
| 摄入 / 负荷 / 电量 | 7d · 30d | 趋势 / 逐天 | `line:*.7d` · `days:*.7d` · `line:*.30d` |
| 步数 | 7d | 逐天 | `days:steps.7d` |
| 体重 | 30d | 趋势 | `line:weight.30d` |
| 夜间 HRV | 7d | 趋势 | `line:hrv.7d` |

**仍走原流程**：写入与设备动作、删改、确认、估餐与餐食提交、图片与语音、Coach、plan 面、
多意图、开放式解释、医学判断、未支持指标（距离、消耗、血氧、压力、静息心率、体成分、血压、
手环状态、运动时长——它们在指标题里各有自己的选项，选中即回退）、日历周期与具体日期、
指代上一轮的请求、以及一切低置信度。

## 三 · 实测

### 通过

| 检查 | 结果 |
|---|---|
| `deno test --no-check supabase/functions` | **411 passed / 0 failed**（新增 51 条） |
| `npm run lint` | 115 files, 干净 |
| `deno check`（新文件 + turn/index.ts） | 干净 |
| pgTAP：`jev_usage.sql`（新）+ `ai_quota.sql` + `ai_turn_leases.sql` + `pro_membership.sql` | 全量迁移重建后 **22 assertions 全过** |
| 真实 API 形状核对（2026-09-20） | 4 题一批 1.03 s / 1304 in / 354 out；401 / 400 / 422 错误体已核 |

关键测试：`turn/jev-route.test.ts` 走**真实 handleTurn**，断言 fast 路径上
`streamText` / `generateObject` 一次都没被调用、trace 就是 `workflow.ready → screen.render`、
供应商失败后模型仍拿到完整原文、off 与 shadow 零调用、图片 / chat / plan 不进路由、
用量落库失败则不再开始付费回退。`fast-turn.test.ts` 用真实渲染器与真实账本，
确认模板数字过审计、而编造的 1999 被同一套审计打回。

### 离线评估（真实 Jev API，非 mock）

`supabase/scripts/eval/jev-eval-set.json`：**156 条**手工标注样本（中 / 英 / 混写、错别字、否定、
双重否定、提示注入、指代、日历周期、未支持指标与窗口），dev 39 / test 117。
运行器 `supabase/scripts/eval/jev-eval.ts` 驱动**真实 router 代码**，不重实现判定。

最终一次独立测试集（`results-2026-09-20-test.json`，模型 `jev-1.13.0`，问题版本 2026-09-20.2，
候选目录 `cat-fb49a451`）：

| 指标 | 值 |
|---|---|
| 样本 | 117 |
| 已准入 | 47 |
| **已准入请求正确率** | **0.979**（46 / 47） |
| 覆盖率（该路由的里实际路由了多少） | 0.821 |
| **复杂请求错误准入率** | **0.009**（1 / 117） |
| 决策延迟 | p50 360 ms · p95 770 ms |
| 输入 token | 251,375（约 USD 0.011） |
| 中文 / 英文正确率 | 0.957 / 1.000 |

唯一一条错误准入是 `x010`「我没有不想看今天的热量」——双重否定，被判为看今日热量。
这条标签本身可争议（多数人问这句确实是想看），但按标注它算错，不改标签。
dev 上另有一条 `f010`「今天蛋白质吃够了吗」被判为 READ_WITH_EXPLANATION 而非 SINGLE_READ：
「够吗」确实在要判断，模型的答案比我的标签更合理，同样不改标签。

主要回退原因（test）：`request_scope` 置信度 16、指代守卫 10、`metric` 置信度 7、
`time_range` 置信度 7、写操作 6、窗口不可解析 6、闲聊 5、多意图 4。

**评估过程中做过的两次调整**（都先在 dev 上验证）：把时间题的判据写死「最近 N 天 = 从今天往回数，
不是日历周期」（jev-1.13 把日期当文本读，这是官方短板页给的对策），覆盖率 0.70 → 0.83；
给相邻的未支持指标各开一个选项，修掉「how far did I walk today」被答成步数。
**测试集因此被跑过两次**（修前 0.958 / 错误准入 0.017，修后 0.979 / 0.009）；严格地说它已不再
完全独立，下一轮调整前应补充新样本。

### 延迟（2026-09-20 重新设计为 guided 之后）

| | 数字 | 怎么来的 |
|---|---|---|
| Jev 判定本身 | p50 0.30–0.42 s | 实测，真实 API，12 次连续请求 |
| template 变体整条（数据库打桩） | p50 371 ms | 实测，`JEV_TEMPLATE_FAST=true` |
| **首轮 guided 预计整条** | **约 6–8 s** | 推算：Jev 0.35 s + 线上 1–2 个模型步的实测分布 |
| 今天同类请求 | p50 25.8 s / p90 55.1 s | 线上实测，61 轮，60 天 |

线上按真实模型步数拆开（60 天，去掉 plan 面）：

| 模型步数 | 轮数 | p50 | p90 |
|---|---|---|---|
| 1 | 17 | 7.8 s | 31.2 s |
| 2 | 114 | 5.9 s | 19.7 s |
| 3 | 94 | 16.3 s | 55.1 s |
| 4 | 71 | 27.0 s | 55.0 s |
| 5 | 34 | 33.0 s | 51.4 s |
| 6 | 19 | 47.0 s | 65.9 s |

guided 把「挑工具、挑图、定范围」那几步拿掉，剩下取证加渲染，落在 1–2 步这一档，所以预计
**6–8 s，比现在的 25.8 s 快 3–4 倍**。这是推算不是实测：本机没有 Grok 网关的 key，跑不了真实
的 guided 端到端。要实测，给一个 `GROK_API_KEY` 和 `GROK_BASE_URL` 就能立刻跑同一支脚本。

顺带量到的一件事：收窄工具面**并不**省 schema——`screen.render` 一个工具就带着 3.3k 字符的
「TYPE → SOURCES」目录，读阶段整套也才 6.7k。所以省的是步数，不是载荷。既然图已经选定，
guided 把这段目录换成了一句话（3292 → 约 150 字符），这才是载荷上的实际收益。

### 首轮实施时未验证 / 未运行（历史，发布验证见上）

- **线上未部署、未执行生产迁移**（按任务要求）。生产 `nb.ai_price_book` 尚无 `jev-1.13.0` 行，
  所以在迁移上线前即使把 `JEV_MODE` 打开，代码也会因 `UNPRICED_PROVIDER` 拒绝调用。
- `swift test --package-path app`、`xcodebuild`：**未运行**。本次不含 iOS 改动，且工作区里有其他
  会话未提交的 app 改动，跑了也不是本次的结论。
- `npm --prefix shopify-web run test:shop`：**未运行**，与本次无关。
- 端到端真机 / 模拟器走查：**未做**。
- **guided 的真实端到端延迟：未实测**（本机没有 Grok 网关凭证）。上表的 6–8 s 是用线上
  1–2 步turn 的实测分布推算的，同一任务集上的对照实验没有做。
- 线上 shadow：**未实现**（见 ADR 0031 第 6 条）。

## 四 · 启用与回滚

**后续版本上线顺序**（本次已获用户授权执行）：

1. 先部署迁移 `20260920140000_jev_routing_accounting.sql`。它只加列、加索引、加价格行，并把
   `record_ai_usage_trusted` 换成带 attempt 与 cost_state 的版本（旧 9 参数形式被 drop，新版
   全部新参数有默认值，现有调用方不受影响）。**必须先于函数部署**，否则 Jev 调用会按 `'*'` 计价。
2. 部署 `turn`（默认 `JEV_MODE` 未设 = off，行为与今天完全一致）。
3. 开发机验证：`TYPESAFE_API_KEY=… JEV_MODE=on JEV_TASK_ALLOWLIST=fast.single_read
   JEV_ALLOW_UNEVALUATED=true`，问「今天吃了多少热量」，看日志里的 `JEV_ROUTE`。
4. 想开生产，先补足评估：在 `jev-policy.ts` 把对应任务的 `evaluated` 改为 true 并写明依据，
   再设 `JEV_TASK_ALLOWLIST`。首轮 97.9% 未达目标；本次 fast 已通过上文新冻结集，assisted 仍关闭。

**回滚**：`supabase secrets set JEV_MODE=off`（或删除 `TYPESAFE_API_KEY`）。下一次函数实例读取
环境变量即生效，无需改代码；已在运行的实例按其启动时的配置继续，不承诺瞬时全局熔断。
数据库改动向后兼容，不需要回滚：价格行、两列与 `cost_state` 对旧代码无影响。

**观测**：每轮打一行 `JEV_ROUTE`，含 route、outcome、reason（含是哪一道题的哪个字段不够）、
binding、版本四元组、每次调用的耗时 / 失败 / 未知成本 / 输入 token / 供应商 request id。
不含用户 id、原文、健康数据、密钥与供应商错误正文。
