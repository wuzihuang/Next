# 手环同步与本地数据完整性诊断 · 2026-09-05

> 本文件是修复前证据。后续修复与真机复验见 [睡眠与实测数据完整性修复](2026-09-05-band-data-fix.md)。

结论：当前无法通过“手环数据完整进入应用本地数据库并完整展示”的验收。真实数据已到 SDK 的 SQLite，但应用存在字段遗漏、睡眠过滤、历史详情被摘要覆盖、首页与详情时间范围不一致。此次完成诊断与复现，未修改业务逻辑来掩盖失败。

## 实际执行

- iPhone 17 Pro Max，真实绑定手环和现有账号；未使用模拟或种子数据。
- 导出 SDK `Documents/wypDataBase.sqlite` 与应用 `Library/Application Support/HOOP/local-data.sqlite`。两个数据库 `PRAGMA integrity_check` 均为 `ok`。
- 按最新 Home 快照账号隔离，只对与当前设备偏好匹配的 SDK 分区对账。手机数据映射时区为 Asia/Shanghai，用户日以 04:00 分界；这与运行终端的时区不同。
- 连续三轮调用 SYNC 按钮使用的 `OriginDataSync.refreshNow(minimumInterval: 0, fullHistory: true)`，每轮均观察到 `lastSync` 前进、本地快照保存成功。当前账号 outbox 最终为零。其他账号的队列未合并、未上传到当前账号。

| 轮次 | 手机时间开始 | 结束 | 最后成功同步时间 | 快照保存 | 睡眠 |
|---|---|---|---|---|---|
| 1 | 14:11:56 | 14:12:23 | 14:12:18 | 成功 | 空 |
| 2 | 14:12:23 | 14:12:50 | 14:12:46 | 成功 | 空 |
| 3 | 14:12:50 | 14:13:16 | 14:13:11 | 成功 | 空 |

- 重启，在 Home 的网络 bootstrap/同步任务开始前捕获已 hydrate 的状态：今日 122 个采样点、1 个体温点、2 个 HRV 点恢复，睡眠仍空。该点早于 Home 网络加载，但不宣称系统完全断网或所有 App 级任务均停用。
- 读取自动监测配置：体温、精准睡眠、HRV、血氧、压力开关均开启。设备采用开关式配置，没有可验证的采样间隔，不把返回的 interval=0 解释成“每零分钟”。
- 通过真实页面路由保存八个指标页面的实际窗口截图，逐页查看。未注入 UI 数值。截图只证明拍摄时刻的可见区域，不代表每个可滚动区域或手势均完成验收。

## 已证实的问题

### 1. 下午醒来的睡眠被适配器丢弃

SDK 精准睡眠表有 09-05 03:59 → 13:09 的完整记录，`sleepDuration=550`（厂商原始时长字段，不重新解释成净睡眠时长）。`VeepooBand.readSleep` 内 `endsThisMorning` 强制 `hour < 12`，因此三轮同步都不返回这条夜间记录。另一个 sleepLine 路径也有相同中午门槛。

证据链：SDK 有记录 → 实际筛选函数拒绝 → 应用今日快照无 sleep → 真实睡眠页面显示“还没有夜里的记录”。

睡眠窗口缺失还阻断夜间氧气筛选。09-05 SDK 氧气表有 828 个符合当前映射 50–100 范围的读数，但睡眠页无夜间血氧。不能据此把 SDK 全日氧气读数都称作夜间读数；必须先恢复正确睡眠窗口。

### 2. 呼吸率没有接入应用数据链路

SDK 原始点含 `resRates`，氧气表也含 `RespirationRate`。在 09-03 和 09-04 各有 1,440 个非零原始 resRates 值；三轮后的 09-05 用户日范围有 610 个非零值。非零只代表设备有上报，未额外验证其生理准确性。

`VeepooBand.point` 未映射 resRates，`OriginPoint`/`VitalSample` 没有对应呼吸率字段，当前八张卡片也没有呼吸率。RESPONSE 是进餐反应，不是 respiration。重复同步不会补齐不存在的映射、存储和展示路径。

### 3. 历史摘要刷新会删除详细数据

`Repository.loadHistorySummaries` 在结果变新或时间戳不足时新建 `DailyMetrics`，随后替换旧日对象；新对象不带旧的 sleep/vitalsCurve。它又保存 HomeSnapshot，于是内存缺失会进入持久化缓存。读取旧日缓存并不等价于首页已经 hydrate 该缓存。

真实导出：基线 09-02 的 UI 缓存有 48 点（22 个体温点），后续刷新/重启后的快照为 0 点；SDK 仍有该用户日的 31 个体温点。三轮强制同步未修复这一历史缓存缺口。09-04 的独立 day 文档有睡眠，但 Home 的历史详情没有睡眠。09-03、09-05 在检查到的应用缓存中均无对应睡眠。

最小回放直接编译现有 `Repository.loadHistorySummaries`，预置睡眠和体温，再加载历史摘要；两项保留断言都失败。这个回放锁定的是摘要覆盖行为，不声称完全重演手机上所有并发时序。

### 4. 体温首页和详情页使用不同范围

首页 `VitalsPage.tempCard` 只读取今天 04:00 后的 ticks。详情 `VitalsDetailView` 合并历史并读取最近 24 小时，显示相对基线偏差。因此深夜 00:20 的体温归前一个用户日，可能在本地存在、在详情可见，但首页是空。

基线滚动 24 小时 44/44 个体温点精确匹配时间和数值；三轮后窗口移动，43/43 匹配，新增今日体温读数后首页恢复 33.1°C。实际详情截图显示 +0.2°C、皮肤 33.1°C、43 次采样。这部分不能归咎于数据库写入失败。

### 5. 缺少睡眠窗口时，夜间 HRV 图回退到整个用户日

真实睡眠截图上，睡眠摘要和分期为空，但“夜间 HRV”图仍绘出中午附近的点。`VitalsDetailView` 在无睡眠起止时间时使用 user-day fallback，并将同一范围给该图。不能把这些白天点作为夜间 HRV 展示；应将无窗口状态明确处理。

## 八个页面的观察

| 页面 | 本次可见状态 | 解释 |
|---|---|---|
| HEART | 有心率和曲线 | 最新值随实时数据变化；静息基线仍空 |
| SLEEP | 摘要/分期空，夜间血氧空 | SDK 有睡眠，适配器过滤；夜间 HRV 图还存在范围错误 |
| RESPONSE | NEEDS 5 DAYS | 产品自身基线门槛，不能与呼吸率混淆；不凭空补零 |
| STRESS | 有数值和曲线 | 实际截图可见 |
| TEMP | +0.2°C，皮肤33.1°C，43次采样 | 最近24小时点已在缓存中 |
| STEPS | 42步及曲线 | 实际截图可见 |
| DISTANCE | 0.04km（36m）及曲线 | 显示四舍五入，不是两份不同距离 |
| ACTIVE | 总872kcal，活动33、静息839 | 页面明确暂无可信的分时热量；有总数不代表所有图都有数据 |

## “本地保存”的边界

SDK SQLite 确实保存了本次检查到的睡眠、体温、氧气、HRV、呼吸率等原始数据。应用自己的 SQLite 目前主要是带过期/裁剪策略的 `documents` 缓存和上传后删除的 `outbox`，并非全部原始测量的永久归档。outbox 清空只说明待传队列清空，不能证明全部数据已长期本地保留。

这次没有 BLE 空口抓包，所以不能声称逐字节核验“手环可能发出的所有包”。结论覆盖 SDK 已落库记录、应用缓存与八个页面可见区域。旧日期没有对应账号缓存或历史归属证据时，在 JSON 中列为 uncertain，不计为当前账号确定丢失。

## 可重复检查

```sh
python3 app/Tests/diagnostics/band_data_audit.py /path/to/export --timezone Asia/Shanghai --output /path/to/report.json
python3 app/Tests/diagnostics/sleep_filter_repro.py
python3 app/Tests/diagnostics/repository_history_detail.py
```

本次三条命令均产生预期红灯。数据库审计分别报告 `home_display` 和 `any_local_cache`，避免“磁盘某处存在”掩盖首页缺失；无法确认设备分区返回 2，不假报成功。

`swift test --package-path app --filter LocalDataTests.testEvidenceBatchIsDurableOrderedAndRetryIsIdempotent` 通过，仅证明底层 SQLite 288 条队列载荷的幂等、重开保留及账号隔离，不能证明端到端完整性。

新增真机 XCTest：`BandConnectionStressTests.testRealBandRepeatedSyncDataAudit`。测试 runner 两次在开始前因 IDE 连接中断、退出码 74 失败，因此没有把自动点击/滚动报告为通过。实际三轮同步和八张截图由临时 DEBUG 入口完成；入口和日志代码已从应用源码移除。

原始导出保留于本机 `/tmp/next-sync-audit-*`，含私人数据，不应提交。脱敏 JSON、轮次记录、重启记录、八张截图位于本机 Codex artifact 目录的 `band-data-audit` 子目录。

修复顺序建议：先修睡眠筛选与窗口，再阻止摘要覆盖原始详情；随后统一体温取数范围，并补齐呼吸率的字段、账号隔离持久化、查询及 UI。以上缺陷仍存在，当前不能标记数据完整性验收通过。

本机证据入口：[三轮同步](/Users/zihuangwu/.codex/visualizations/2026/09/05/01a07026-6e41-7320-a17b-55317ba6e48e/band-data-audit/rounds.json)、[本地对账](/Users/zihuangwu/.codex/visualizations/2026/09/05/01a07026-6e41-7320-a17b-55317ba6e48e/band-data-audit/after-three-syncs.json)、[重启恢复](/Users/zihuangwu/.codex/visualizations/2026/09/05/01a07026-6e41-7320-a17b-55317ba6e48e/band-data-audit/restore.json)、[睡眠截图](/Users/zihuangwu/.codex/visualizations/2026/09/05/01a07026-6e41-7320-a17b-55317ba6e48e/band-data-audit/screens/sleep.png)、[体温截图](/Users/zihuangwu/.codex/visualizations/2026/09/05/01a07026-6e41-7320-a17b-55317ba6e48e/band-data-audit/screens/temp.png)。
