# AI 读数注册表与第一批补数 · 2026-09-05

依据 ADR 0005（一轮分取证与制图两段）、ADR 0006（读数收敛成一张声明式注册表）、ADR 0007（主模型与成本上限）。本文件只写落地顺序与每条注册表条目的具体内容，决策理由不在这里重复。

## 前置：先接 usage，再谈其他

`streamText` 与 `generateObject` 的 `usage` 目前从未被读取，`ai_turns` 与 `screen_frames` 只有 `model_version` 与 `latency_ms`。ADR 0007 里每个成本数字都是估算。所以第一件事与读数无关：把 `usage` 读出来落库，按天按用户聚合成视图。它同时是额度执行、成本 MCP 与「把估算换成实测」三件事的共同前提。

同一批里另一件独立的事：`meal` 与 `asr` 两个 Edge Function 现在完全没有调用 `enforceRequestBudget`，而它们是最贵的两条路径。任何按钱的额度必须先覆盖它们。

## 第一批 · 四个 tick 列加两个日汇总

前四条都在 `raw_samples`，列已经在库里、上传链路已经通，缺的只是 `readSampleHistory` 的 `RawRow` 接口把它们丢了。改一个接口再加条目即可，不需要动 `OriginDataSync`。

| 维度 | table.column | grain | unit | bucket 默认 | agg | 绑定图型 |
|---|---|---|---|---|---|---|
| 皮肤体温 | `raw_samples.temp` | tick | °C | 30 分钟 | mean | curve |
| 逐 tick HRV | `raw_samples.hrv` | tick | ms | 30 分钟 | mean | curve |
| 手环原始耗卡 | `raw_samples.cal` | tick | kcal | 2 小时 | sum | column |
| 距离 | `raw_samples.dis` | tick | m | 2 小时 | sum | column |
| 活动分钟 | `daily_training.active_minutes` | day | min | — | — | column |
| 日距离 | `daily_training.distance_m` | day | m | — | — | column |

bucket 默认值按账本容量定，不按视觉效果定：`raw_samples` 是五分钟一行、一天约 288 点，而账本 `CAP = 60` 计的是去重后的数字个数，超限时 `record()` 会把 `points` 二分砍半。30 分钟分桶得 48 点、2 小时分桶得 12 点，与现有 `heart.today`（30 分钟）和 `steps.today`（2 小时）一致。累加类（耗卡、距离）用 sum 而非 mean，因为 tick 存的是区间增量。

`origin` 要按来源如实标：四个 tick 列是 `measured`；`active_minutes` 与 `distance_m` 是服务端 settle 从 tick 算出来的，标 `derived`。

**手环原始耗卡这一条需要额外的措辞约束。** ADR 0004 已裁决厂商卡路里不与计算基础代谢相加，因为它的基础部分不可分离；展示用的消耗走 `day_fuel.kcal_out`，是服务端从 MET 算的。把 `raw_samples.cal` 暴露给模型，风险是它把厂商值当成"今天消耗"说出来，与屏上和 `day.get` 的数字对不上。条目的 `says` 必须写明这是手环自报的原始值、不是本产品的消耗口径，并且不要给它配一个叫「消耗」的标题。

## 第二批 · 各有额外工作

**进餐 RESPONSE**（`response_samples.optical`）是整张表首次暴露给模型。CONTEXT.md 已锁定它只能叫 RESPONSE，不许出现血糖、mmol/L、mg/dL 或 SPIKE，提示词 S6 也写了同一条；新条目的 `says` 与图型文案都要过这一关。它是无单位的腕部光学点，不是血液浓度。

**睡眠呼吸率**（`sleep_nights.raw.respiration[]`）要解 jsonb。⚠️ 这一项与 `2026-09-05-band-data-fix.md` 那条在飞的工作重叠：那边已经通过 `SDKRespirationArchive` 拿到逐分钟的时间与值、与睡眠区间关联、睡眠页已展示，真机确认 548 条夜间读数。**先等那条落地，再决定 AI 这边是读 `sleep_nights.raw` 还是读它可能新建的表**，不要在它还在改的时候并行加条目。

## 不做

运动模式单次会话。Supabase 没有对应表，`OriginDataSync` 也没有为它建上传路径；`segments.today` 是从心率抬高段反推的，不是手环的 sport-mode 会话。要做是建表、上传、加条目三件事，与本批不是一个量级。

## 顺序

一，接 `usage` 落库与聚合视图；给 `meal` 与 `asr` 补限流。二，删 `tool-routing.ts` 的关键词预路由，确认系统提示词与工具定义逐字节稳定（前缀缓存的前提，约 45% 输入成本）。三，把 `series.get` / `metric.query` / `range.get` / `measurement.latest` 合并成 `data.read`，注册表补 `grain`、evidence 语义与从注册表收集 `select` 列，加 `data.catalog()`。四，`prepareStep` + `activeTools` 分两段，step 上限 6，允许回头补读一次。五，第一批六个条目。六，第二批。

二和三之间可以并行开始，但二必须先合——预路由不删，前缀缓存不成立，三带来的工具 schema 变化就无法评估成本影响。

## 验收

每条新条目要能回答三个问题而不出错：问它本身（「体温怎么样」）、问它的缺测日（返回 null 而不是 0，屏上写 ——）、问一个超出封顶的区间（返回 `truncated: true` 并且模型据此改口而不是照旧宣称完整）。第一批合并后另做一次成本复核：同一句问法在合并前后各跑一次，比对 `usage` 的累计输入 token，确认注册表合并没有把工具 schema 撑大到抵消掉缓存收益。
