# 一天的结算要在秒级完成：夜间证据每夜算一次，回放每天算一次，手机的结算在自己的预算内停下

2026-09-12 用户裁决（#30）。「目前为啥我的设备上的身体电量计算不出来？」查下来数据是满的：手环当天 288 格、格格有心率、22:14 还在上传；公式也是对的，手工给足时间结算今天得 57。数字没出来，是因为**没有一条路能把一天结算完**。

## 为什么算不出来

单日结算的成本涨到了 **40 秒**（在已收尾的一天上量 `recompute_range`：40.6 s；09-05 时每轮 cron 平均 3 秒，09-06 那批 evidence 迁移之后每轮都顶满预算）。两条结算路径都扛不住：

- 手机的 `settle_now` 跑在 `authenticated` 角色下，`statement_timeout` 是 **8 秒**。每一次调用都在回放里被取消、整个事务回滚，一行都没发布过。回前台、切前台、点多少次都一样。
- 每小时的 `nb-settle`（`settle_all(2)`）拿 120 秒的 70% 给全部账号共用。40 秒一天，一轮全网只推得动 2 天。这个账号 `dirty_from` 卡在 09-08：11:07 算了 09-06/07，13:07 算了 09-08/09，09-10 到 09-12 一次都没轮到。当天那行是 09:07 写的，比当天第一批采样到达早了 18 分钟，存的是 `worn=false / reserve_score=null`，之后再没人回来重算。手机读到的就是这行。

40 秒去哪了（对一天开 `track_functions` 剖析，总计 41.6 s）：

| 函数 | 调用次数 | 总耗时 | 该是多少 |
|---|---|---|---|
| `night_evidence_parts_at` | 230 | 27.5 s | 15 个不同的夜 |
| `calculation_instant` | 27,393 | 11.1 s | 逐行求值 |
| `bb_instant` | 1,093,396 | 9.0 s | 在上面 230 次里 |
| `canonical_sleep_nights` | 1,081 | 8.3 s | 每次夜间证据 5 次 |
| `reserve_replay_uncached` | 2 | 12.2 s | 夜跨了两个用户日 |

一夜的证据被 `hr_rest`（7 夜，训练 tick 和训练证据各要一次）、回放（当夜加 14 个基线夜）、充电系数（每个触及的夜再 15 次）反复索要，每次都重新解析那一夜的原生 HRV JSON、重新取规范夜。而一夜的答案在同一个事务里不会变：它读的东西没有一样会在事务中途变。

## 决定

迁移 `20260912150000_a_day_settles_in_seconds.sql`，测试 `supabase/tests/a_day_settles_in_seconds.sql`。

1. **`night_evidence_parts_at` 在事务内记住答案**，键是 用户 / 夜 / as-of / 输入修订号。修订号取自 `nb.calculation_work.input_revision`，每个事实触发器都会推进它，所以同一事务里稍后写入的事实（测试就这么干）不会命中旧答案。引擎本身改名 `night_evidence_parts_at_uncached`，一字未动。
2. **`reserve_replay` 同样记住一天的回放**（键再加上锚点和当时的时钟），只留最新三天。夜起始那一天的回放在结算那天时算一次，第二天汇总晨间充电时直接复用。`settle_day` 原来预热的单日 `nb.replay_key` 缓存成了这个 memo 的特例；包装函数仍认这个键，审计 harness 的断言不受影响。
3. **`reserve_replay_uncached` 与 `training_observations` 把计算时刻算一次**，不再每一行原始采样算一次。
4. **`recompute_range` 拿到账号的锁时清空两个 memo**，`settle_all` 不会把一个账号的 memo 带进下一个。
5. **`settle_now` 给 `recompute_range` 一个 deadline，取调用方语句预算的一半**，和 `settle_all` 取自己 70% 是同一个机制。手机的 8 秒下就是 4 秒：循环至少结算一天，到点停下，把续算点记进 `calculation_work.dirty_from` 并提交；App 回前台看到 `calculation_status` 还是 pending 时本来就会再调，从那里接着算。没有语句预算的调用方（测试、service role）行为不变。

同日第二刀 `20260912160000_training_ticks_once_per_settle.sql`：`training_load_ticks` 在一次 `settle_day` 里只建一次（五个调用方都在 `settle_day` 内，含 `daily_training` 上的两个触发器；`sport_heart_rate_samples` 没有失效触发器，所以这个 memo 只在 `nb.settling_day` 标着当天时生效，结算之外每次都走引擎），`night_evidence_parts_at_uncached` 里把规范夜从五次读改成一个物化 CTE。一天 4.8 → 3.7 s。它同时补上第一刀漏掉的一件事：改名的引擎带着原来的 ACL，新建的包装不带——`night_evidence_parts_at` 包装曾对 anon / authenticated 可执行，两处包装都 revoke 到与引擎一致，`training_load_evidence.sql` 第 39 条和新测试都断言这一点。

第三刀 `20260912170000_replay_walks_its_ticks_once.sql`，三件事。回放的递归 CTE `replay` join 的 `numbered` 不是 materialized，只被引用一次，规划器把它内联进了递归项——288 步递归每一步都把 tick_grid → observed → fused → feature 整条链重跑一遍，一天 83,000 次 `raw_samples` 索引查找；一个 `materialized` 让它算一次，回放本身 1264 → 165 ms。夜间证据引擎里同一夜的 HRV JSON 被 `merge_sleep_hrv` 合并两次（原生点一次、撤销一次），每个原生点的时间戳解析 5 次、数值 3 次；`night` CTE 带上合并结果，原生点经 `offset 0` 挡住上拉的 lateral 子查询各解析一次。包装函数的 key 对已收尾的夜不再带 as-of：引擎里所有与 as-of 比较的项（原生点与原始采样的 `ts < as_of`、资格判定的 `wake_at <= as_of`）在 `wake_at` 过后就已定死，因为覆盖的分钟止于 `wake_at`；候选行（前后各一天）的 `wake_at` 都不晚于 as-of 时，答案与任何更晚的 as-of 相同，一次追三天的结算每个基线夜只算一次。仍在进行的夜保留精确 as-of。一天 3.6 → 1.9 s（今天 2.4 → 1.3 s，另一账号 2.5 → 1.3 s）。

memo 放在事务级 setting 里，就是 `nb.replay_key` 早就在用的模式：随事务消亡，不占目录行，STABLE 的 SQL 函数里读得到（验证过：带 `SET` 子句的 STABLE plpgsql 函数里 `set_config(…, true)` 写的值在函数退出后仍在，rollback 后消失）。

## 验证

- 生产库上同一事务、同一时刻、同一批事实：先用旧代码结算 4 天再用新代码结算，`daily_results` / `reserve_daily` / `daily_training` / `day_fuel` / `night_score` / `reserve_samples` 的每一个字段逐一相等；耗时 33–35 s → 3.5–4.5 s（另一账号 18 s → 2.7 s）。事务回滚，没落盘。
- 本地 Docker 全量迁移重建 + 11 套 pgTAP 195 条全绿，函数定义往返校验通过。新测试量到：两天结算夜间证据引擎跑 46 次（原来一天 230 次），回放 3 次（昨天、昨夜起始那天、今天各一次），`settle_now` 在 6 秒预算下结算 2 天后停下并记录续算点。
- 09-12 当天的积压先用 service 连接分片结算掉了（止血），账号今天读 57，`wear_run` 从 0 回到 14。

## 边界

- 结果**按构造不变**：memo 返回的就是引擎返回的。`calculation_version` 不动，不触发全量重放。
- 6 小时撤成 `——` 的显示规则（CONTEXT「身体电量窗」）不动；ADR 0026 修的是「tick 没上来」，这条修的是「tick 上来了没人算」，两条互不替代。
- 同一夜在不同 as-of 下仍会各算一次（键含 as-of）。已收尾的夜其实与 as-of 无关，把键归一化能把跨天的重复也省掉，但要在包装里先读 `wake_at`；本期不做，一天 3–5 秒够用。
- 一天 1.3–2 秒，不是毫秒。剩下的大头是夜间证据里对每一夜原生 HRV JSON 的解析（`bb_instant` / `bb_number` 是带异常块的 plpgsql，每次调用有子事务开销）和 `training_load_ticks` 的一次构建；再往下走要把解析结果落成表。等它成为问题再说。手机 8 秒预算的一半是 4 秒，2 秒一天意味着每次回前台结算两到三天，手环补传昨夜把账号标脏到前天也一次追完。

## 考虑过的替代

- 只把 `settle_now` 挪到 service role 的边缘函数（120 秒）：把 40 秒一天的成本原样留着，cron 那条路照旧追不上。
- 临时表做 memo：STABLE 函数里不能写，改 VOLATILE 会让外层查询的快照看不见同一语句内的插入，且每个事务都往目录写行。
- 每个 memo 条目一个 GUC 名：名字随会话泄漏；单个 jsonb 对象只占一个名字。
- 把 `calculation_version` 抬一版做全量重放：没有必要，结果没变。
