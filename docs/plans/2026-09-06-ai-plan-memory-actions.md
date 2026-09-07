# AI 三步：计划、记忆、手机工具 · 实施记录

依据 [ADR 0018](../adr/0018-ai-plans-remembers-and-acts.md) 和 CONTEXT.md 的「计划页 / 计划任务 / 思考流 / 会话 / 记忆 / 手机工具 / 可续 turn / 三步」词条。2026-09-06 全部写完、部署到 gkgzwcxivnffsecshvfs 并在生产与模拟器上做了真实测试，见末尾。

## 三步与工具

一轮固定顺序 读 → 执行 → 输出（`_shared/turn-phase.ts`）。八个模型步，读最多四步；调了手机工具进入执行阶段，读工具关闭，`workflow.reread` 可回读一次。一步只能调一个手机工具。

| 步 | 工具 | 在哪执行 |
|---|---|---|
| 读 | data.catalog · data.read · metric.compare · day.get · profile.get · meals.openSlots · meals.search · image.inspect · meal.estimate · device.capabilities | 服务端，用户 JWT |
| 读（注入） | memory（记忆概述 + 事实条目）· device（电量、连接、闹钟、上次同步）· plan_context（plan 面预取的三天证据） | 随 turn 进 `<source_data>`，入账本 |
| 执行 | device.find · device.sync · device.alarm.set · device.alarm.delete · sport.start · sport.stop · meal.log · balance_check.start · body_scan.start · app.open | 手机（`PhoneToolRunner`），可续 turn |
| 输出 | screen.render.× 27 · plan.render · Chat 直接文本 | 服务端 |

设闹钟、删闹钟、开运动、停运动、记餐在执行前弹确认（RootView 上的 alert），60 秒不点算 `CANCELLED`。`confirm` 由服务端按工具固定（`_shared/phone-tools.ts`），模型改不了。

## 可续 turn 协议

1. 模型调手机工具 → 服务端在该步结束后把消息历史、workflow、账本、trace、餐草稿存进 `nb.ai_turn_states`（`save_ai_turn_state`，TTL 5 分钟），发 `event: tool.request` `{call_id, name, args, confirm, resume_by}`，再发 `done {suspended: true}`，关流，释放租约。
2. 手机执行，用**同一个 Idempotency-Key 和同一个 body** 再 POST `/turn`，多一个 `tool_result: {call_id, ok, code, data?, message?}`。
3. 服务端重新领租约，`load_ai_turn_state`，校验 `call_id`，把占位的工具结果换成手机的结果，**不再扣次数**，从存档继续。等手机的时间不计入 50 秒。
4. 最多续 3 次；超过返回 `RESUME_BUDGET` 回落帧。手机重发原请求而没带结果时返回 409 `TURN_SUSPENDED` 并附 `tool_request`，客户端据此执行再续。状态过期是 409 `TURN_STATE_LOST`。

客户端循环在 `AIService.turn` → `stream()`；工具执行在 `Services/PhoneTools.swift`。

## 计划

- 上滑计划页：`PlanStore.load` 读 `daily_plans` 今天的行；没有就 `generate`，一次 `surface=plan` 的 turn，计划页脚下跑 `ThinkingStage`。用户下滑离开，turn 在服务端跑完并落表，下次上滑直接显示。「重新生成」才再打模型。
- 服务端 plan 面直接从输出阶段起步（只开 `plan.render` 和一次 `reread`），证据由 `planContext` 预取：过去三个用户日的 `daily_results`+`day_fuel`、`night_score`、`meals`、昨天的 `daily_plans` 和 `plan_task_checks`。`plan.render` 校验 3–5 条任务、id 唯一，upsert `daily_plans`，输出 `type: plan, target: plan` 的帧。
- 任何面都能调 `plan.render`（Chat 里「帮我排一下今天」）。`Destination.planFace` 不是页面：`Router.open(.planFace)` 变成 `planRequest`，Home 观察它上滑计划页。
- 勾选：本地立即打勾，`PlanCheckQueue`（outbox kind `plan-check`）写 `plan_task_checks`，不调模型。第二天生成时模型看到勾和数据。
- `PlanFaceMath` 里的本地规则拼装不再被调用（`PlanSnapshot` 已删），手势与动画常量保留；`NextBodyPlanTests` 仍编译。

## 记忆

- `user_memory` 一人一行：`summary` + `facts[{text, at, source}]`，封顶约 1500 token。每个 turn 注入 `<source_data>.memory`。
- 会话：`AISession` 给每个 turn 一个 `session_id`（30 分钟无 turn 换新）；退出 Chat 调 `close_ai_session` 并触发总结；App 回到前台和每个 turn 开始时 `settleIfDue`。服务端 `memory-settle` 用用户 JWT 找到「已关闭或闲置 30 分钟且未总结」的会话，读 `ai_session_transcript`，一次 `generateObject` 合并重写，经 `write_user_memory_trusted` 落表并盖 `summarized_at`。
- 总结记 `endpoint=memory` 的模型成本，不扣用户次数。撤回同意的触发器删记忆；删号级联；Profile → AI MEMORY 可看可整段清除（`forget_user_memory`）。

## 文件

服务端：`_shared/turn-phase.ts`（三阶段）· `_shared/phone-tools.ts`（新）· `_shared/memory.ts`（新）· `_shared/plan.ts`（新）· `_shared/prompt.ts` / `coach.ts`（S10、PHONE TOOLS、PLAN）· `_shared/contract.ts`（`plan` 类型与 target）· `_shared/freshness.ts`（device）· `_shared/ledger.ts`（序列化）· `turn/index.ts`（可续、记忆、plan 面）· `memory-settle/index.ts`（新）· 迁移 `20260906180000_ai_three_step.sql`。测试：`turn/index.test.ts` +6、`turn-phase.test.ts` +3、`memory-settle/index.test.ts` 4；全仓 167 个 Deno 用例通过。

客户端：`Services/AIService.swift`（可续循环、`logMealDraft`）· `Services/PhoneTools.swift`（新）· `Services/AISession.swift`（新）· `Features/Plan/PlanStore.swift`（新）· `Features/Plan/PlanPage.swift`（重写）· `Features/Home/HomeView.swift` · `Features/Profile/AIMemoryView.swift`（新）· `App/Router.swift` / `RootView.swift` · `Features/Chat/ChatDetailView.swift` · `App/NextBodyApp.swift` · `L10n/Tables/zh-Hans.json` +41。Debug 构建通过。

## 部署与真实测试（2026-09-06 已完成）

- 迁移 `20260906180000_ai_three_step.sql` 经 Management API 应用到 `gkgzwcxivnffsecshvfs`（CLI 的直连走 IPv6 失败），并写入 `schema_migrations`。`turn` 与 `memory-settle` 已 `functions deploy --use-api`。
- 命令行（`supabase/scripts/dev/turn-resume.py`，会话由 admin magic-link 铸造）：
  - 设备状态注入：「电量多少、有哪些闹钟」→ 不调工具，直接引用 63% 与 06:30 闹钟，15 s。
  - 手机工具：「设 7 点闹钟」→ 5.7 s 挂起 `tool.request{confirm:true}` → 续跑 10 s → 「Weekday alarm set for 07:00」。用户取消（`CANCELLED`）→ 「闹钟未写入手环」。
  - plan 面：9 s 一次调用出 5 条任务并落 `daily_plans`；Chat 里「记住我左膝旧伤、不吃乳制品，今天做什么」→ 模型自选 `plan.render`。
  - 记忆：`memory-settle` 关会话后写入 `user_memory`（概述 + 2 条事实，59 token）；新一轮「今晚跑五公里可以吗」直接引用「左膝旧伤」。
  - 成本：`nb.ai_model_calls` 出现 `endpoint=memory`，单次 0.23 分。
- 模拟器（iPhone 16e，`SIMCTL_CHILD_NB_DEBUG_REFRESH_TOKEN` 种入真实账号会话）：上滑计划页读到服务端行 → 勾选落 `plan_task_checks` → 「重新生成」跑思考流后落页 → Profile → AI 记忆页显示两条事实 → Chat 里「Set a band alarm for 7am on weekdays」弹出确认 → MockBand 写入 → 模型汇报手环上全部三个闹钟。

真实测试改掉的问题：plan.render 的 zod 长度上限改为截断（硬上限会让 SDK 整轮抛错）；计划任务的标题和做法不审计、只审总结与依据；账本白名单加 `M-DD` 与 `M/D` 日期；计划行改为审计通过后再写库；手机写工具返回 ok:true 后解除「已记录 / logged」类禁语；E_CLAIM 命中开始记日志；RootView 上的旧式 `.alert(item:)` 会让 UIKit 在启动时断言崩溃，改成新 API 挂在最外层。

## 未做

- 真机（iPhone 17 Pro Max）未走：模拟器的 MockBand 替代了真实 BLE 写入，`device.find` / 真闹钟 / 开运动的真实 SDK 路径要在真机上再看一遍。
- 14:56 那次模拟器重生成回落的根因没抓到（当时 E_CLAIM 不记日志），现在会记。
