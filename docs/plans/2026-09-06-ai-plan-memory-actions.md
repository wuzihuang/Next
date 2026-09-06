# AI 补全：计划、记忆、动作

依据 [ADR 0018](../adr/0018-ai-plans-remembers-and-acts.md) 和 CONTEXT.md 的「计划页 / 计划任务 / 思考流 / 会话 / 记忆 / 动作」词条。四个阶段，每个阶段独立可发布，顺序按依赖排：先断掉错接线，再记忆，再计划，最后动作。

## 现状里要先拆掉的

- `HomeView.regeneratePlan` 把 turn 结果写进首页 `widget`，计划页只重跑本地规则。
- `HomeView.togglePlanCheck` 每勾一次打一次 `/turn`，烧额度。
- `PlanFaceMath` / `PlanSnapshot` 本地拼计划；`PlanChecks` 只存 UserDefaults。
- 服务端没有 `plan` 类型、没有计划表、没有记忆表、没有 `action` 字段。
- `data.read` 的 DATA_METRICS 和图表工具的 `sources.ts` 是两个目录（顺手合并，见阶段 3）。

## 阶段 0 · 断错接线（半天）

1. `togglePlanCheck` 只写本地勾，不再调 `regeneratePlan`。
2. `regeneratePlan` 暂时禁用按钮，等阶段 2 接上真正的 plan surface。

## 阶段 1 · 记忆

### 表

```sql
create table user_memory (
  user_id uuid primary key references auth.users,
  summary text not null default '',          -- 概述段落
  facts jsonb not null default '[]',         -- [{text, at, source: 'chat'|'panel'}]
  token_estimate int not null default 0,
  updated_at timestamptz not null default now()
);
create table ai_sessions (
  id uuid primary key,
  user_id uuid not null,
  started_at timestamptz not null,
  last_turn_at timestamptz not null,
  closed_at timestamptz,
  summarized_at timestamptz
);
```

RLS：本人可读可删 `user_memory`；写只走 service role 的总结函数。`account_delete` 和撤回同意的路径加一行 delete。

### 会话归属

- 每个 `/turn` 请求带 `session_id`。手机侧一个 `AISession` 单例：Chat 打开、首页发语音 / 拍照时若无活跃会话或距上次 turn 超过 30 分钟就开新会话；退出 Chat 时标记 `closed_at`。
- `ai_turns` 加 `session_id` 列，`claim_ai_turn` 顺手 upsert `ai_sessions.last_turn_at`。

### 总结函数 `memory-settle`

- 触发两处：手机退出 Chat 时 POST 一次；`pg_cron` 每 10 分钟扫 `ai_sessions` 里 `closed_at is null and last_turn_at < now() - 30min` 的行，通过 `pg_net` 打同一个函数（和 `day-settle` 同一套 secret）。
- 输入：旧 `summary + facts`，本会话所有 turn 的 `user_text` 和 frame 的文字槽（不含图表点）。
- 一次 `generateObject`，schema `{summary: string ≤ 600 字, facts: [{text ≤ 80 字, at, source}] ≤ 40 条}`。提示词明确：只记稳定事实（伤病、忌口、偏好、目标、生活规律），不记本轮测量数字；合并时允许删过时条目。
- 幂等：`summarized_at` 非空就跳过。用量走 `recordAiUsage(endpoint: "memory")`，不 `consumeAiQuota`。

### 注入

`turn/index.ts` 在 `availability` 旁加 `memory: {summary, facts}` 进 `<source_data>`（用户消息里，不进 system，前缀缓存不受影响）。提示词 S2 补一句：「memory 是系统记下的事实，可以引用，但不是本轮测量」。

### 客户端

Profile 加一屏「AI 记住的」：显示 summary 和 facts，一个「全部清除」按钮，走 `delete from user_memory`。

## 阶段 2 · 计划

### 表

```sql
create table daily_plans (
  id uuid primary key,
  user_id uuid not null,
  user_day date not null,
  title text not null,
  summary text not null,
  tasks jsonb not null,            -- [{id, title, sub, basis}] 3–5 条
  read_from date not null, read_to date not null,
  turn_id uuid references ai_turns,
  model_version text, created_at timestamptz default now(),
  unique (user_id, user_day)       -- 重新生成是 upsert
);
create table plan_task_checks (
  user_id uuid, user_day date, task_id text,
  checked_at timestamptz not null,
  primary key (user_id, user_day, task_id)
);
```

### 服务端

- `/turn` 接受 `surface: "plan"`。校验、租约、额度和 panel 一样。
- **不走读阶段**：`createTurnWorkflow([], ["screen.render.plan"])` 直接进 render。请求时服务端预取并塞进 `<source_data>`：
  - 过去 3 个用户日的 `daily_results`（负荷、电量、方向）、`sleep_nights` 分数、`day_fuel`、餐
  - 前一天 `daily_plans.tasks` 和 `plan_task_checks`
  - `user_memory`
  - 手机上传的 freshness（含当天早晨那一夜是否已同步）
- 新工具 `screen.render.plan`：`{title ≤ 18, summary ≤ 80, tasks: [{title ≤ 14, sub ≤ 40, basis ≤ 40}] 3–5}`。`basis` 里的数字照常过账本审计。
- `PANEL_TYPES` 加 `"plan"`；`Envelope.data` 放 `tasks`。持久化：`record_claimed_ai_turn` 之后 upsert `daily_plans`。
- 提示词新增 `planPrompt(locale)`：语气允许建议（和 panel 的 S6 不同），先说昨天勾了什么、数据是否印证，再给今天 3–5 条；没有夜就不写夜的任务。
- `GET /v1/plan/current`：返回今天的 `daily_plans` 加勾选，手机上滑时先打这个。

### 客户端

- `PlanPage` 改为渲染 `daily_plans` 行：标题、总结、任务列表（对勾 + 标题 + 副标题 + 依据）、「AI 读了 MM-dd 到 MM-dd」、底部「重新生成」。
- 上滑流程：`openPlan` → 打 `plan/current` → 有则显示；无则进思考流阶段（复用 `AIService.thoughts` / `reading`，在计划页脚下逐行打出）→ `ai.turn(surface: "plan")` → 落页。用户下滑离开不取消 Task，结果回来后写缓存，下次上滑直接显示。
- 勾选：本地立即打勾，写 `plan_task_checks`（走现有 outbox 模式，离线可补）。不调模型。
- 删除 `PlanFaceMath.face` / `PlanSnapshot` 的规则拼装，保留手势和动画常量。

## 阶段 3 · 动作与设备读

### 设备状态上传

`AIService.prepareFreshness` 加 `device: {battery_percent, connected, last_sync_at, alarms: [{id, time, days, enabled}]}`。服务端把它放进 `<source_data>`，并在账本 `seedConstants` 之后 `harvest(device, "device.state")`，这样「电量 63%」能过审计。`device.capabilities` 工具改为也返回这份实时状态。

### 契约

`Envelope` 加可选 `action`：

```ts
action: {
  kind: "find_device" | "sync" | "open_page" | "start_sport" | "log_meal"
      | "balance_check" | "body_scan" | "set_alarm",
  confirm: boolean,             // 服务端按 kind 固定，模型不能改
  args?: { page?: Target, sport?: string, alarm?: {time, days} }
}
```

模型通过一个 `screen.render.action` 工具输出（title / sentence / action），或在任意 render 工具上带 `action` 参数。服务端在 execute 里按 kind 强制 `confirm`：`start_sport / set_alarm / log_meal` 为 true，其余 false。

### 客户端执行

`HomeView` 收到带 `action` 的 frame：
- `confirm=false`：立即执行。`find_device` → `VeepooBand.findDevice()`（SDK `FindDevice` 震动）；`sync` → `prepareFreshSync` + 读数据；`open_page` → `router`。
- `confirm=true`：frame 的 `action` 槽显示确认文案，点了才执行。`start_sport` → `LiveSessionStore.start`；`set_alarm` → SDK `veepooSDKSettingDeviceAlarmWithAlarmModel`；`log_meal` 沿用现有 `confirmMeal`。

### 提示词

S10 改写：「你没有写工具，但可以在 envelope 里提出一个动作。动作由手机执行，开运动、设闹钟、记餐需要用户确认；在确认前不说已开始、已设置、已记录。」

### 顺手合并读目录

图表工具的 `source` 改为引用 `metric-query.ts` 的 DATA_METRICS 加窗口后缀，`sources.ts` 只留取数实现。这样 `data.read` 读的和 `screen.render.*` 画的是同一个 id，UNTRACEABLE_NUMBER 少一个来源。

## 验证

- 服务端：`turn/index.test.ts` 加 plan surface 的用例（无读阶段、预取注入、upsert）；`memory-settle` 的幂等与不计额度；action 的 `confirm` 不可被模型覆盖。
- 客户端：模拟器走 `NB_DEBUG_PLAN=1` 上滑 → 思考流 → 落页 → 勾选 → 杀 App 再上滑直接显示；Profile 清除记忆。
- 成本：plan 一次调用、memory 一次调用，都进 `ai_model_calls`，看板按 endpoint 分列。
