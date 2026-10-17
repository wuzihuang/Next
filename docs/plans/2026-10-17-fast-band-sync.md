# 手环同步提速：分档同步，后台在预算内跑完

`TECHNICAL PROPOSAL · FAST BAND SYNC · 2026-10-17`

状态：**P0–P5 已写进本地代码，未做真机测量**。P6 不进主线：`VeepooBand` 记录过按天读取在这只固件上会空转超时。P7 仍待单独的架构决定。复用窗口按方案用 30 分钟，首页计时器走轻量档。依据是当前工作树的代码审阅、`docs/STATUS.md` 2026-09-21 的两次真机观测，以及 Veepoo SDK 头文件与文档。没有新做真机测量，没有读闭源 SDK 内部实现。

## 00 · 结论

1. 一次日常刷新真机约 **35 秒**（34.847 / 34.747 s，两次观测，不是分位数）。iOS 给 `BGAppRefreshTask` 的时间大约 **30 秒**。后台刷新通常跑不完，到期被取消，小组件拿不到新数字。这是比「慢」更要紧的问题。
2. 35 秒具体花在哪一段**还没测**。代码里已经有分段埋点，第一步就是拿到这份数据，后面所有收益估计都以它为准。
3. 不换 SDK、不依赖未确认的接口，也有四件事能确定变快：**按用途分档**（后台和计时器走轻量档）、**先今天后昨天**、**蓝牙读取不等网络**、**同一连接内不重复全量命令**。
4. 真正的「几秒同步」要靠按天读取接口，但头文件写明它所属的 `VPPeripheralAddManage`「暂时未实现」。只作为独立真机实验，结果出来之前不进主线。

## 01 · 现状：一次刷新做了什么

入口都汇到 [`OriginDataSync.refreshNow`](../../app/NextBody/Services/Band/OriginDataSync.swift)，由 [`BandRefreshCoordinator`](../../app/NextBody/Services/Band/BandRefreshCoordinator.swift) 合并和节流。

| 请求 | 谁发起 | 节流下限 |
|---|---|---|
| `.automatic` | 冷启动 | 同步频率（默认 5 min） |
| `.foreground` | 首页 30 s 计时器 | 同步频率 |
| `.resume` | 回到前台 | `min(60 s, 频率)` |
| `.background` | `BGAppRefreshTask`，需放了小组件 | `min(300 s, 频率)`，系统最早 30 min 后才拉起 |
| `.fullHistory` | 设备页 SYNC、同意授权后 | 0 |
| `.phoneTool` / `.latest` | AI 工具、调试 | 0 |

不管哪种请求，干的活都一样：

**准备**

- 连接与就绪检查（`BandReadiness.ensureReady`）；`.foreground` / `.resume` 可复用 3 秒内的实时回执。
- `BandHistoryReadCache.beginRefresh` 清空上一次的读取回执。
- **先等网络**：`waitForEvidencePublication()` 等上一轮上传结束，`flushPendingEvidence()` 推完积压，之后才开始读手环。

**蓝牙**（`HoopQueue` 串行，同一时刻只有一条命令）

- `veepooSdkStartReadDeviceAllData`：手环保留的全部天数，单条上限 300 s。
- `veepooSdkStartReadDeviceHrvData`、`...OxygenData`、`temperatureType` 为 2/4 时再加 `...TemperatureData`，每条也是全部天数。
- 以上每次刷新都重跑，因为回执只在同一次刷新内有效。
- 之后的 `readOriginPage` / `readHealthData` / `readSleep` 都只查 SDK 本地库，不走无线。

**逐日处理**：顺序固定是 `[1, 0]`，**先昨天，后今天**。每天：

- 插入 `sync_runs`，结束时再 patch。
- 本地落盘（`HomeSnapshot.saveBandObservations`）。
- 7 个数据域三个一组并发上传，另加睡眠（`publish_sleep_night`）。
- 只有今天：`settle_now` → `load(days: 1)` → `loadSleepScores(days: 30)`。

**历史补查**：`checkHistory` 恒为 `true`。`needsHistorySync` 要求每个域的确认时间落在「今天」，所以每个自然日第一次刷新会把最多 6 个历史日重新处理一遍，再 `settle_now(days)` 加 `load(days)`。

**后台任务**：[`BackgroundRefresh`](../../app/NextBody/Services/BackgroundRefresh.swift) 跑完上面整条，然后 `flushPendingEvidence`，最后写小组件 glance 和 `HomeSnapshot`。到期回调会取消整个 Task，**写 glance 在最后一步**，所以超时就等于小组件没更新。

**其他事实**

- Info.plist 已有 `bluetooth-central`、`fetch`、`BGTaskSchedulerPermittedIdentifiers`。
- 没有 CoreBluetooth 状态恢复（无 `RestoreIdentifier`）。
- 没有 APNs `.p8`，服务端无法静默唤醒手机（ADR 0026）。
- 身体电量早上的充电用夜间 HRV（`nb.night_evidence_parts`）；白天消耗看心率、压力和活动。

## 02 · 可能的慢点（待 P0 证实）

| 段 | 推测 | 依据 |
|---|---|---|
| 3–4 条全量蓝牙命令 | 可能是大头 | 代码注释称七天要几分钟、单日几秒；每次刷新都重跑 |
| 准备阶段串行等网络 | 网络差时放大 | 读手环前先等上传和补推 |
| 先昨天后今天 | 后台超时时今天最吃亏 | 今天排在第二位，还要等昨天的上传 |
| 网络往返 | 每天约 6–8 次 RPC，今天再加 3 次 | 见上 |
| `loadSleepScores(30)` | 每次刷新读 30 天，可能不必要 | 日常刷新只改动今天、昨天 |
| 每日首次整周补查 | 早上第一次明显更重 | `needsHistorySync` 按自然日失效 |

## 03 · 目标与验收

| 指标 | 现状 | 目标 |
|---|---|---|
| 后台刷新完成率（手环在身边） | 未测，估计很低 | ≥ 90% 在到期前写出 glance |
| 后台轻量档耗时 P95 | — | ≤ 20 s |
| 回到前台到首页出新数字 | ≈ 35 s 量级 | P50 ≤ 12 s，P95 ≤ 20 s |
| 完整档（设备页 SYNC） | 未测 | 不变慢；完整性不降 |
| 数据完整性 | 7 域分别确认 | 不变：每个域最迟在下一次日常/完整档补齐，确认不倒退 |

## 04 · 方案

### P0 · 先测量（必做，阻塞后续的收益判断）

已有埋点：`sync.segment`（`ble_and_mapping` / `local_persistence` / `upload` / `settlement_and_reload`）、`sync.refresh_finished.durationSeconds`、`sdk.read_all_progress`，以及 `NightDiagnostics` 的 `background.started/finished`。

要补的：

- 在 `VeepooBand.sdk(...)` 外层，给 `readAllData`、`readHRV`、`readOxygen`、`readTemperature` 各记一次 `sdk.command_duration`（名称、秒数、`totalDay`）。
- 在 `refreshWork.prepare` 里分别记就绪、等上传、补推三段。
- 后台到期时记 `background.expired`，并带上当时所处阶段（`BandSyncActivity.stage`）。

测量矩阵：同一台 iPhone、同一只 HOOP，手环在身边。每类至少 10 次：冷启动、回到前台、设备页 SYNC、当天首次（触发整周补查）、后台任务（用调试器 `_simulateLaunchForTaskWithIdentifier` 触发）。

**决策门**：如果 `readAllData` 单条就超过 20 秒，P1–P4 只能救回后台的一部分，后台能否跑完要看 P6；否则 P1–P4 足以让后台在预算内完成。

### P1 · 按用途分档同步（核心）

在 `BandRefreshRequest` 上新增 `tier`，由请求决定，不由页面决定：

| 档 | 请求 | 读哪几天 | 专用全量命令（HRV / 血氧 / 体温） | 历史补查 | 结算与读回 |
|---|---|---|---|---|---|
| **轻量** | `.background`、`.foreground`（计时器） | 只读今天；昨天只在「未确认」或本地 04:00 前才读 | 只在需要时跑（见下） | 不做 | `settle_now(0)`；`load(1)`；睡眠分只读 2 天 |
| **日常** | `.resume`、`.automatic`、`.phoneTool` | 今天 + 昨天，**先今天** | 需要时跑 | 只修「失败 / 缺失」的日子，不做每日整周审计 | 同现状，睡眠分读 2 天 |
| **完整** | `.fullHistory`、同意后、首次绑定 | 今天 + 昨天 + 保留天数 | 每次都跑 | 现状的每日审计 | 现状 |

「需要时跑」的判定（新的纯函数，放进 `BandSyncPolicy`）：

- 今天的夜间 `hrv` / `oxygen` 域尚未确认 complete，必须跑。早上起床后的第一次同步一定会跑，所以身体电量的晨间充电不受影响。
- 本连接内上一次成功的专用命令不到 30 分钟，可跳过。白天 HRV 约 10 分钟一个点，晚半小时上传不影响白天的消耗计算。
- 跳过的域本次**不上传、不改它的确认状态**。不能用空数组把它标成 `notCollected`，否则会盖掉真实的修复范围。

每日整周审计从「每天第一次任何刷新」移到「每天第一次完整档或日常档」。轻量档永远不触发它。

### P2 · 先今天，后昨天

`BandRefreshCoordinator.perform` 的 `[1, 0]` 改为 `[0, 1]`。现在的顺序有个隐含原因：只有今天那一份带 `settle: true`，调用 `settleNow(days: 1)`，把昨天一起重算。昨天先上传，这次结算才拿得到昨天的数据。改顺序后要这样调整：

- 逐日 `sync` 一律 `settle: false`。
- 今天上传完，先 `settle_now(0)` 并读回今天（后台在这里写 glance）。
- 昨天上传完，再 `settle_now(1)`。昨天没有新数据时，跳过这次结算。

后台任务改为分步写出：**今天上传、结算完成后立刻写 glance**，再继续昨天。到期时至少今天已经到了小组件上。

### P3 · 蓝牙读取不等网络

现状的串行有理由：2026-09-21 的故障里，上传与结算抢同一把账户锁导致超时。所以不能简单并行上传，只并行「读手环」：

- `prepare` 里的 `waitForEvidencePublication()` 和 `flushPendingEvidence()` 改为后台 Task 启动，不阻塞 BLE 命令。
- 第一次 `publication.publish(...)` 之前，再 `await` 这个 Task 完成。
- 结果：服务端的写入顺序与锁的使用和现在完全一样，只是空闲等待的时间被蓝牙读取填上了。
- 回归测试沿用 2026-09-21 那条「前台发布期间刷新不得并发上传」的用例，必须仍然通过。

### P4 · 同一连接内不重复全量命令

`BandHistoryReadCache` 的回执在 `beginRefresh` 时清空。改为：

- `.all` 回执仍然每次刷新都重读，因为它是今天 5 分钟数据的唯一来源。
- `.hrv` / `.oxygen` / `.temperature` 的回执，跨刷新保留到「同一 scope、同一连接代、30 分钟内」。scope 或连接一变就失效，沿用现有的 `generation` 机制。
- 与 P1 的「需要时跑」共用一个判定，不做两套。

### P5 · 网络瘦身

- 日常与轻量档：`loadSleepScores(days: 30)` 改为 2 天。30 天只在完整档、睡眠纠正和冷启动加载里读。
- `sync_runs` 的 insert + patch 改成结束时一次 insert（字段齐全），每天少一次往返。表的用途「解释一次失败的同步」不受影响。
- 不改上传协议本身：`ingest_band_delta` 已经在服务端处理未变化的样本。

### P6 · 按天读取实验（独立，不进主线）

在调试构建里加一个开关，用 `veepooSDK_readBasicDataWithDayNumber:0 maxPackage:` 只读今天，和 `readAllData` 对比：

- 能不能在 HOOP 固件上返回（头文件称该组接口「暂时未实现」）；
- 字段是否和 `veepooSDKGetOriginalData` 一致（心率、步数、压力、睡眠状态、MET）；
- `maxPackage` 续读是否真能只传新增；
- 耗时差多少。

四项都成立，才另起方案，把轻量档的 `readAllData` 换成按天读取。任何一项不成立就放弃，并把结论写进 STATUS。按天读 HRV、血氧的接口头文件已标注「无效 / 不可用」，不做实验。

### P7 · 可选：夜间完整审计放进 `BGProcessingTask`

ADR 0026 拒绝 `BGProcessingTask` 的理由是它做不到「每半小时」，那个理由对轻量档成立。但每日整周审计正好适合它：充电或空闲时跑，时间预算长。做法是注册第二个任务标识，`requiresExternalPower = true`，只跑完整档的历史部分。这样早上第一次打开 App 不再背整周补查。是否采用待评审；采用的话要补一条 ADR。

## 05 · 不做

- 不放宽身体电量 6 小时撤回规则（CONTEXT 明确 Avoid）。
- 不让小组件扩展直接调 Supabase（ADR 0026 已留作后议）。
- 不在没有 APNs 的情况下承诺服务端唤醒。
- 不缩短 300 s 的命令上限来「美化」耗时；超时是上限，不是目标（`2026-09-04-ble-under-3s-research.md` 同一原则）。
- 不靠跳过上传来提速；跳过的只是「本次不读」的域，确认状态原样保留。

## 06 · 风险

| 风险 | 缓解 |
|---|---|
| 轻量档跳过 HRV，夜间 HRV 晚到，晨间充电偏低 | 夜间域未确认时强制跑；验收用例覆盖「起床后第一次后台刷新」 |
| 改顺序后今天的结算缺少昨天的数据 | 今天先只结算当天，昨天上传后再补一次 `settle_now(1)`（P2） |
| 并行读手环重新引入锁争用 | 只并行 BLE，上传前仍等待；保留 09-21 回归用例（P3） |
| 回执跨刷新复用，读到旧连接的数据 | 复用以 scope 加连接代为键，断开即失效（P4） |
| 跳过的域被误标 `notCollected` | 跳过的域不进 `publications`；单测断言 `BandDomainSyncState` 不变 |
| 整周审计移出轻量档后，历史漏洞修得更晚 | 日常档仍修失败与缺失的日子；完整审计每天至少一次（前台或 P7） |

## 07 · 测试

**单元**（`NextBodySyncCoreTests`）

- `BandRefreshRequest.tier` 映射表。
- 「需要时跑」的判定：夜间未确认、30 分钟内、scope 变化三种情况。
- `BandRefreshCoordinator` 先今天后昨天，结算只跑一次。
- 轻量档不调用 `history`。
- 跳过的域不改确认状态。

**真机**：P0 矩阵在 P1–P5 前后各跑一遍，对照第 03 节的指标。后台用 `_simulateLaunchForTaskWithIdentifier`，并人为在第 25 秒触发到期，检查 glance 是否已写出今天。

**回归**：现有 `BandSyncPolicyTests`、`BandSyncProgressTests`、`BandDomainSyncTests`、`SyncProgressStageTests`，以及 09-21 的锁争用用例。

## 08 · 顺序与估算

| 步 | 内容 | 依赖 | 估算 |
|---|---|---|---|
| 1 | P0 埋点 + 一轮真机测量 | — | 0.5 天 + 测量 |
| 2 | P2 先今天、glance 提前写 | 1 | 0.5 天 |
| 3 | P1 分档 + P4 回执复用 | 1 | 1.5 天 |
| 4 | P3 蓝牙不等网络 | 1 | 0.5 天 |
| 5 | P5 网络瘦身 | — | 0.5 天 |
| 6 | 第二轮真机测量，更新 STATUS | 2–5 | 0.5 天 |
| 7 | P6 按天读取实验 | 1 | 1 天，可并行 |
| 8 | P7 夜间审计（如批准） | 3 | 1 天 + ADR |

## 09 · 待决定

1. 轻量档的 HRV / 血氧复用窗口用 30 分钟是否可以接受（影响白天 HRV 曲线的新鲜度）。
2. 首页 30 秒计时器是否归入轻量档。归入的话，前台的数据最多晚一个窗口拿到 HRV。
3. 是否采用 P7，把每日整周审计挪到夜间充电时。
