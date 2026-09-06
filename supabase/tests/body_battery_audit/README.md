# 身体电量 SQL 回归

```sh
bash supabase/tests/body_battery_audit/run.sh
```

需要 Docker、Python 3 和本机 `postgres:16-alpine`。脚本只启动唯一命名的临时容器，关闭网络、不开端口，不读取项目凭据；退出后清理自己的容器与临时文件。全部输入为合成数据。

`build_harness.py` 建立最小数据表、固定测试时钟，加载实际 `bb-2.1` 函数及生产 replay 缓存包装。`fixtures.sql` 保留最初审计反例，`regressions.sql`、`cross_day_clock.sql` 检查新增时间、覆盖和跨日合同。最后应用分钟 HRV 修订和性能迁移，运行 `evidence_performance.sql`、`sleep_hrv_revisions.sql`。

通过时退出 0，失败时退出 1；报错不是验收通过。覆盖范围包括：

- 短暂夜醒不冻结晨值，03:00 早醒不随白天样本改变。
- 首次跨日睡眠从假设 20 开始；未舍入 close 连续承接，假设来源继续传递。
- `raw.line` 保留真实 offset；旧分期串按实际 intervals 映射；同一夜的错日副本不重复充电。
- 缺位置的 240/360 分钟汇总不伪造睡眠，实际白天样本仍可放电。
- HRV 按五分钟槽优先精确分钟；其余槽可用粗数据；原生槽内部缺点不补齐。显式空原生数组表示无测量。
- 实际睡眠区间外的 HR/HRV 不进入夜间统计。基线资格要求至少 60 个有效分钟、50% 覆盖、最长缺口不超过 90 分钟且实际已醒；包含边界反例。
- 稳定基线使用 0.5 的尺度下限，稀疏夜保持可见但不计为合格基线夜。
- 全夜充电与 04:00 用户日账目分开；重放子日时固定到子日结束，整夜归因采用与承接值一致的账目。
- 无证据不扣电，安静休息只抵扣消耗，归因在 0 下限仍闭合，固定 clock 之后不产生曲线槽。
- HRV 无效分钟有持久撤销高水位，旧睡眠 outbox 不能复活；只有严格更新的有效观测能恢复，其他睡眠窗口隔离。
- 658 分钟睡眠、342 个原生 HRV 点与粗数据补充的两夜，性能迁移前后全部 14 个证据字段相等；粗数据槽中的撤销恰好移除一个覆盖分钟。

`drivers` 保留 `anchor`、`assumed_anchor`、`last_night`、`awake`、`movement`、`stress`。新字段 `day_charge` 与旧 `last_night` 都属于用户日归因；`night_charge` 属于实际整夜，可为空。`close_value` 保留 12 位小数承接；`anchor_origin`、`wake_at`、`observed_at`、`confidence`、`coverage`、`algo_version` 供 UI 解释。`confidence` 是输入充分性，不是生理准确度或假设锚点的不确定性估计。

本轻量回归不代替完整 Supabase 迁移安装、RLS、历史 profile、归档及并发测试。本轮另在独立 Supabase PostgreSQL 17 容器中，从平台基础 schema 顺序安装完整迁移链，并执行已有计算修订、归档恢复、摄入与训练集成测试。所有原始诊断结论仍保留在 `docs/plans/2026-09-06-body-battery-audit.md`，避免把修复后的结果当成最初审计状态。

这些检查验证确定性的实现合同，不证明恢复/消耗系数经过生理或临床标定，也不构成任何用户的完整线上分数复算。
