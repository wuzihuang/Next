# 身体电量在 App 不在前台时也要跟上：回来必拉，放了小组件就每半小时拉一次

2026-09-12 用户裁决。「身体电量的计算好多时候都是空的。我需要它在每次进入 App 时都算一下；如果后台有小组件，应该每 30 分钟算一次。」

## 为什么是空的

身体电量从来不在手机上算。手环的 tick 由手机前台同步上传，服务端 `nb.compute_reserve` 按 tick 重放出储量，并把 `observed_at` 定在**最后一个真有采样的格子**（ADR 0022 记下的事实：「手环数据只有手机前台同步才上传」）。手机这边 `BodyBatteryReadoutPolicy` 对这个时刻只认三态：90 分钟内亮着、6 小时内变暗并写 SYNCED HH:MM、6 小时以外整数字撤成 `——`（CONTEXT「身体电量窗」）。

于是「空」有两条来路，都不是算法坏了：

1. **回到前台时不一定拉手环。** ADR 0021 让回前台一律调 `settle_now`，但结算只能重放服务器**已有**的 tick；把新 tick 带上来的那次拉取 `OriginDataSync.refreshNow(.foreground)` 仍以设备页的同步频率为地板。默认 5 分钟无妨，选了 EVERY 30 MIN / EVERY HOUR 的人打开 App 就常常被 `throttled`，服务端没有新 tick 可算，数字停在上次同步的时刻，过了 6 小时就是 `——`。
2. **后台什么都不发生。** App 退到后台后没有任何拉取；小组件只画 App 上一次写进 App Group 的 glance。人睁眼看主屏时，最后一个 tick 往往已是昨晚——小组件是 `——`，打开 App 第一屏也是 `——`，要等 BLE 连上、读完、上传、结算、读回这一整串跑完才有数。

## 决定

- **回到前台必拉一次。** 新增 `BandRefreshRequest.resume`，由 `didBecomeActive` 的 `requestForegroundRefresh("foreground")` 发起，地板 `min(60 s, cadence)`：只把「切走又切回」折进刚跑完的那一次，不再让设备页的 EVERY HOUR 拦它。首页自己那个 30 秒的计时器仍走 `.foreground`，照旧受频率约束——那是「多久问一次手环」的设置该管的事。`.resume` 与 `.foreground` 一样复用 3 秒内的实时回执，不重走连接。结算那一半不变：`HomeLaunchPolicy.shouldSettleOnForeground`，冷启动永远要一次，其后以服务端的 5 分钟刻度为地板。
- **放了小组件，就在后台每半小时拉一次。** `BackgroundRefresh` 注册一个 `BGAppRefreshTask`（`com.nextbody.hoop.refresh`，Info.plist 加 `fetch` 后台模式与 `BGTaskSchedulerPermittedIdentifiers`）。每次进后台和每次跑完都问一次 WidgetKit 主屏上有几个我们的小组件：`BackgroundRefreshPolicy.shouldSchedule(widgetCount:signedIn:bound:)` 三条都成立才排下一次，否则撤掉已排的。`earliestBeginDate` 取距上次成功同步 30 分钟、且不早于现在。一次运行：恢复 Keychain 会话 → `refreshNow(.background)`（地板 `min(300 s, cadence)`，不复用回执）→ `flushPendingEvidence`（无论手环有没有连上都请服务端结算今天并读回，cron 算出的数也能到主屏）→ 重写 glance、存 HomeSnapshot → 再排一次。到期回调取消 Task 并自行 `setTaskCompleted`，两条路径共用一把锁保证只完成一次。
- **不改显示规则。** 6 小时撤成 `——` 仍是对的：曲线停在最后一个真 tick，不外推。这两条改的是 tick 到达服务器的频率，不是什么时候允许印数字。
- **手机仍然不算数。** 后台跑的只是「读手环、上传、请结算、读回」。F2 rule 02 不变。

## 边界，先说清楚

- iOS 只保证**不早于** `earliestBeginDate`，不保证准点。常用的 App 通常一天能拿到多次，但「每 30 分钟一次」是我们请求的节律，不是系统的承诺。用户从多任务里划掉 App、或在设置里关掉「后台 App 刷新」，就一次都不会跑。
- 一次后台运行大约 30 秒预算。手环不在身边时 BLE 连接会吃掉大半，这时拉取记 `disconnected`，但结算与读回仍然执行。
- 静默推送本可以由服务端 cron 每半小时叫醒手机，但 APNs `.p8` 未配（ADR 0022 同一条），此期不做。小组件扩展自己去请求服务端也不做：它没有会话，把 Keychain 共享给扩展是另一个决定。

## 考虑过的替代

- 只把回前台的 `settle_now` 调得更勤（服务端没有新 tick，算多少次都是同一个数）。
- 把 6 小时的撤回放宽到隔夜（那是把一个没在测的手腕画成在测，CONTEXT 明确 Avoid）。
- `BGProcessingTask`（只在充电或空闲时跑，一天一两次，与「每半小时」相去更远）。
- 小组件 `getTimeline` 里直接调 Supabase（需要 Keychain 共享组与一份扩展内的会话刷新逻辑，安全面扩大，留作后议）。
