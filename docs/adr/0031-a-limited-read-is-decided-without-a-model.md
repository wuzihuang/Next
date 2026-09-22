# 有限的只读请求，工具与图表由判别器选，活还是 Grok 干

2026-09-20 用户裁决。本 ADR 使用未占用的 0031，并修订 ADR 0018「工具选择由主模型独占」这一条：
工具、指标与图表的选择，在**有限候选**范围内可以交给判别模型 Jev；其余一切不变。

## 决定

1. **2026-09-20 用户裁决（本条覆盖初稿）：Jev 只负责选——选用哪个工具、画哪张图、什么时间
   范围；真正干活的仍然是 Grok。** 它照旧读数据库、必要时联网搜索、自己写答案，只是不必再
   花步骤去想「该用哪个工具、哪张图」。`/turn` 内因此有三条执行方式，同属一个工作流、一个
   operation、一个租约：
   - **guided（默认）**：Jev 判定 → 模型拿到收窄后的工具面（read / find / web.search + 选定
     的那一张图 + 空数据时的 text 帧）、已解析好的时间范围和一段服务端写的 `<routing>` 说明
     → 模型自己取证、自己写话 → 原渲染器。不再提供 `workflow.ready`：范围已经定了，给它就等
     于允许它改掉这个决定。
   - **template**（`JEV_TEMPLATE_FAST=true`，默认关）：服务端自己读来源、用固定模板写字，
     零模型调用。最快，但话是死的，不能联网、不能临场加读一个指标。
   - **legacy**：原有完整流程，保留自主取证、补读、Coach 交接、估餐与手机动作。
   三者是本项目的执行方式，不是 Jev API 的参数。不把每一轮串成「Jev → 大模型 → Jev」。
2. Jev 只在服务端给出的**封闭候选**里做选择：请求范围、指标、时间类别、展示需求，必要时再选一次
   图表绑定。它不写日期、不写指标 id、不写来源 id、不写工具名、不写 SQL、不写任何数字。
   每道题都有 UNKNOWN / NO_MATCH / NOT_SUPPORTED 出口，拒绝是正常答案，回退到 legacy。
3. **日期由代码解析**。Jev 只认语义标签，服务端用 TurnContext 与用户日规则算出真实区间。
   「上周」「本月」「9 月 15 号」不在可解析集合里——日历周期不是滚动窗口，宁可回退。
   任何来源的自带跨度都不许顶替用户问的窗口：体重只有 30d / 90d，所以「最近七天体重」没有绑定。
4. 身份、同意、账号删除、输入大小、速率、额度、幂等重放、执行租约、用户隔离、健康数据新鲜度、
   阶段控制、确认与回执，一概不因此改变。fast 省掉大模型不改变产品的次数规则：同一个用户操作
   仍只准入一次，不新增第二次客户端请求。
5. 每一次真实供应商调用单独计量。Jev 有自己的价格（USD 0.042 / Mtok 输入，输出免费；按固定
   记账汇率换成 31 fen/Mtok，向上取整），**不落到 `'*'` 兜底价**。收到可信用量即使答案不可用也
   落账；中途中断、用量缺失的调用记为 `unknown` 上界并计入当日 spend；用量无法落库时，不再开始
   新的付费回退。
6. 配置缺省为 `off`。2026-09-20 经用户授权，生产启用 `fast.single_read` 的 guided 路径；
   新冻结集 108 条中已准入 59 条全部正确，复杂请求无错误准入（有限样本）。assisted 与 template 保持关闭。`on` 只开放**既在 allowlist、又已完成独立测试集评估**的任务；
   `JEV_ALLOW_UNEVALUATED` 仅供开发机。`shadow` 本版不做线上调用——线上影子会用用户自己的
   spend 额度为用户看不到的决策付费，而当前账务分不开实验成本，影子评估走离线 runner。
7. 图片、语音、复杂分析、餐食写入、设备操作、手机续跑、每日建议与长期记忆，本版全部保持原逻辑。
   Jev 不接收图片或音频。

## 实现

- `supabase/functions/_shared/typesafe.ts`：HTTP 适配、响应校验、超时与取消的区分、用量映射。
- `_shared/decision-router.ts`：准入、问题构造、阈值、拒绝判断、计划校验。
- `_shared/chart-selection.ts`：从 `CHART_SKILLS` 与 `SOURCES` 生成的准入清单，装载时自校验。
- `_shared/fast-turn.ts`：template 变体——把已验证计划接到真实工具、真实阶段、真实渲染器上。
- `_shared/fast-copy.ts`：template 变体的本地化文案（只陈述，不解释、不判断、不建议）。
- `_shared/turn-phase.ts`：`outputReady` ——范围已定的一轮不再走 `workflow.ready` 这道门。
- `_shared/jev-policy.ts`：按 task + 模型版本 + 问题版本 + 候选目录版本管理的阈值策略。
- `turn/index.ts`：模型循环之前的一个分支；不接受就原样落到循环里。
- `supabase/migrations/20260920140000_jev_routing_accounting.sql`：价格、attempt 幂等、cost_state。

评估、实测数字、启用与回滚：[2026-09-20 Jev 工具路由](../plans/2026-09-20-jev-tool-routing.md)。

依据：[Jev API](https://docs.typesafe.ai/api)、[模型与价格](https://docs.typesafe.ai/models)、
[confidence](https://docs.typesafe.ai/confidence)、[jev-1.13 的短板](https://docs.typesafe.ai/model-jaggedness/jev-1.13)。
