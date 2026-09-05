# 读数收敛成一张声明式注册表，加数据只加条目

2026-09-05 用户确认：工具不要做太多，以后尽量工具本身不变，只加新表或新字段；数据库里有的健康数据都应该能读出来，不限于 UI 展示过的。

这个形状仓库里已经有一半。`metric-query.ts` 的 `definitions` 就是注册表：每条声明 `table` / `column` / `unit`，可选 `nested` 与 `timestamp`，加一个指标等于往 `METRICS` 加个字符串、往 `definitions` 加一行，查询分页、用户日对齐、缺测算 null、统计量与整套 evidence（证据哈希、覆盖率、`partial`/`stale`/`absent`、`measured` 对 `derived`、算法版本）全部自动继承。散乱在另一边：`sources.ts` 的 39 个 chart source 各自写 `fetch`，而 `queryMetrics()` 只服务 `metric.query` 与 `range.get`，`sources.ts` 完全不调它——两套数据层平行查库。

`series.get`、`metric.query`、`range.get`、`measurement.latest` 合并为一个 `data.read`，背后共用这张注册表。39 个 source 里 20 个能表达成「表.列 + 时间窗 + 聚合」并入注册表；19 个做了通用注册表表达不了的整形（30 分钟与 2 小时分桶、7×12 热力归一化、strip 泳道、pair 双轨、stack 多段、rows 加 spark、体成分差分与 12 周方向格、`o2.night` 的睡眠窗口定界、`events.today` 的四表合并排序），留在绘图层。`metric.compare` 不并入，它算的是 Pearson r，是分析不是读数；`day.get` 也不并入，它给的 `direction` 与 `the_call` 是服务端算好的产品判断，不该让模型自己组装。

注册表补三样东西才能兑现「只加条目」这句话。一是粒度：条目带 `grain` 为 `day`、`measurement` 或 `tick`，tick 类支持 `bucket` 参数，服务器按返回点数封顶——否则 `raw_samples` 那些五分钟一行的列（体温、逐 tick HRV、原始耗卡、距离）根本表达不了。二是 evidence 语义：`origin`、`measuredAtColumn`、是否检查 `stale` 提到条目里，现在这些是按表名硬编码的 if（`derived` 判的是 `daily_results` 或 `body_composition`，`measuredAt` 对 `sleep_nights` 特判取 `wake_at`），加一张新表就要回来改那几行。三是 `daily_results` 的 `select` 硬编码列串要改成从注册表收集需要的列，否则往 `day_fuel` 加个字段仍要改代码。

注册表是白名单，不是「库里所有表」。健康测量与派生数据默认全进，包括 UI 从未展示的 `raw_samples.met`、`daily_training.curve`、`reserve_daily.drain_drivers`、`body_composition.bmr_kcal`；`ai_turns`、`screen_frames`、限流计数表与 `profiles` 不进。界线画在「测量与派生的健康数据」与「系统自己的账」之间，不是画在「UI 有没有」。让模型读 `screen_frames` 会让账本审计失去意义——它能看到自己上一轮写过的数字再"读"回来当证据。指标名保持 zod enum 内联（短名进缓存前缀，命中后只花 12.5% 输入价），单位、粒度与可用区间由 `data.catalog()` 提供。

时间窗由模型提，服务器按用户日（04:00 切日）对齐并封顶，超限截断并回 `truncated: true`。这不是不信任模型判断问哪一段，是不让它决定能从库里拖走多少行。同理拒绝「每轮把所有维度都读一遍」：账本 60 个去重数字与 50 秒预算装不下，而且屏上数字更容易因为碰巧对得上而通过审计。

关键词预路由（`tool-routing.ts` 的 `sourceScopeFor`）删除。它的正则只认中英词，法语、换说法与跟进句都失效，与「让模型自己选数据」这个目标相反；更实际的代价是它把 `sourceScope` 传给 `chartChoicePrompt`，命中时 S11 那一节被裁短，系统提示词逐字节改变，隐式前缀缓存（最小前缀 1024 token，我们的系统提示词约 3k）在命中与未命中的轮之间互不复用。它省下的一圈 `series.get`，换掉的是约 45% 的输入成本。

补读数按代价分两批。第一批都在 `raw_samples`，改 `readSampleHistory` 的 `RawRow` 接口再加条目即可：皮肤体温 `temp`、距离 `dis`、逐 tick HRV `hrv`、手环原始耗卡 `cal`；同批加两个日汇总条目 `daily_training.active_minutes` 与 `daily_training.distance_m`。第二批各有额外工作：睡眠呼吸率要解 `sleep_nights.raw.respiration[]` 的 jsonb，进餐 RESPONSE 是 `response_samples` 首次暴露给模型。运动模式单次会话不做——Supabase 没有对应表，`segments.today` 是从心率抬高段反推的，不是手环的 sport-mode 会话，要做是建表、上传、加条目三件事。

## 尚待确定的边界

`metric.query` 把 `bloodOxygen` 标为 `unsupported`，但夜间血氧其实能通过 `o2.night` 这张图从 `oxygen_samples` 读到，这处不一致在补 metric 条目时对齐。`raw_samples` 的 tick 级数据进账本后如何避免被 `record()` 的二分截断砍残，与 ADR 0005 里"绘图自取数"的处理相同，但 `data.read` 直接返回给模型的 tick 序列仍会被截断，`bucket` 的默认值需要按账本容量而不是按视觉效果来定。
