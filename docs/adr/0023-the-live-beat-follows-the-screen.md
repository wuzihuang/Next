# 实时心率只在有人看的时候跑：离开 App 就停

2026-09-09 用户报告：「只要我一把这个 App 退出去，手环侧面的健康灯就开始亮」。

## 原因

`NextBody-Info.plist` 声明了 `bluetooth-central`，所以按 Home 键回桌面时蓝牙并不断。断的是另一件事：`BandLivePolicy.shouldRun` 原来写成 `phase != .active || foregroundWanted`——**只要 App 不在前台，实时心率流就无条件开着**。`BandLiveLifecycle.setPhase(.background)` 一到，`LiveReadout.run` 就发 `veepooSDKTestHeartStart(true)`，而且后台里 `hold()` 的截止计时器被 `!self.background` 挡掉，测量一直不停，直到固件自己结束再被循环重开。回到前台、翻到不看心率的页面，流才关。用户看到的正是这个：在 App 里灯灭，一离开灯就亮——手环整段时间都在测心率。

这段后台采集没有任何消费者：样本不入库、不进小组件、不进 Live Activity（运动会话走 `LiveSessionStore`，本来就是独占的）。唯一的副作用是 `BandReadiness.ensureReady(reuseRecentLiveReceipt:)` 偶尔能复用一条 3 秒内的样本省一次探测。为此让手环整晚亮着 LED、耗着电，不值。`HomeView.liveReadoutAllowed` 上的注释早就写着：「没人看的读数，到中午手环就没电了」。

## 决定

- `BandLivePolicy.shouldRun` 改为 `foregroundWanted && phase != .background`：实时心率流只跟随屏幕上的需求。`.inactive`（来电、下拉控制中心）保留已开的流，不折腾；`.background` 一律结束。
- 后台拉一天数据的那条线（`BandRefreshCoordinator` / `OriginDataSync`）代码不动，但要承认一个后果：之前正是后台心率回调让进程在 `bluetooth-central` 下一直醒着（`docs/plans/2026-09-04-ble-stress-validation.md`）。没了它，iOS 会照常挂起 App，`HomeView` 每 30 秒的前台刷新循环和随之而来的后台日拉取会停到下次打开为止。不丢数据：手环自己存点，回前台时照旧拉昨天和今天；代价是 App 不在前台时服务端的「今天」会更旧一些。同理，`BandReadiness.ensureReady(reuseRecentLiveReceipt:)` 那条「3 秒内有实时样本就省一次探测」的捷径回前台时基本不再命中，每次都老老实实读身份和电量，按 `SyncCadence` 节流。
- 健康灯本身是设备页上的一个探针（`HealthLightSheet`）。用户选的状态存在手机上（`BandHealthLightPreference`），`BandHealthLightKeeper` 在每次连接后重新写给手环——固件重启、重新配对都不会把用户关掉的灯再点回来。没选过就什么都不发，固件默认值不动。
- 同一张 sheet 上暴露固件自己的「断连提醒」开关（`VPSettingDisconnectRemind`）。这是给另一种情况准备的：如果 App 被划掉、链路真的断了，灯是固件自己点的，那时能关它的只有这个开关和健康灯设置本身。手环答「没有这个开关」时这一行不画。
- `VeepooBand` 注册 `veepooSDKListenHealthLightStatus`，固件自己改灯的时候记一条日志和诊断（`band.health_light_changed`）。这是分辨「App 让它亮的」和「固件自己亮的」的证据，之前没有。

## 怎么在真机上分辨

装上新版后：按 Home 键离开 App，灯应该不再亮。若只有把 App 从后台划掉之后灯才亮，那是固件在报断连——去设备页把「健康灯」设成关闭，再把「断连提醒」关掉，各试一次。

## 2026-09-12 修正

健康灯不再是设备页上的一个正式分组。这块固件答 `healthLightType=0`：SDK 的健康灯根本不可寻址，戴的人看到的侧面灯就是测量 LED，由 ADR 0023 的主决定（心率流跟着屏幕）管着。于是「SIDE LIGHT」分组从发布版设备页撤掉，那一行连同 `HealthLightSheet`（含「断连提醒」开关）一起收进设备页的 DEBUG 卡片，Release 版既不画这一行也不编译这张 sheet。`BandHealthLightPreference` 和 `BandHealthLightKeeper` 不动：调试里选过的状态照旧每次连接重写。
