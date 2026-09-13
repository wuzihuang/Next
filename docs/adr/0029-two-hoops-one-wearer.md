# 两只 HOOP，一个佩戴者：声明是唯一的来源规则

2026-09-13 用户裁决。产品方案在 `docs/plans/2026-09-12-dual-device-continuity.md`；本 ADR 记录 V1 落地时定下的、代码里看不出来的几条边界。

## 决定

1. **一套只给一个人戴。** 两只 HOOP 是同一个账号的槽位 A / B，不是两个佩戴者。没有「借给别人」的分支，没有「谁在戴」的猜测，只有「我戴的是哪只」。
2. **切换是手动的。** 手机上点 `I'm wearing B`（可以往前补时间）。声明进 `wear_events`，从生效时刻起，那只手环的采样是正史；另一只在同一时刻的采样进 `band_standby_samples` 存着，不丢、不覆盖。声明时间往前推，`nb.reproject_wear` 把两边换过来；睡眠夜同理（`band_standby_sleep`）。
3. **手机一次只连一只。** Veepoo SDK 是单例，没有双连接。`DeviceSlots.transport` 是当前在链路上的槽位，`BoundBand.identifier` 从它读——三十多个按 `BoundBand.identifier` 作用域的调用点（就绪、刷新范围、证据发布）一行不改就跟着换。切换 = 记录声明 → 等在飞的拉取结束 → 断开 → 换 transport → 重连全量读。待机那只的 `SYNC B` 是同一个动作走一个来回。
4. **服务端不猜。** `nb.wearer_device_key(user, at)` 只看声明；没有声明时槽位 A（或唯一绑定的那只）从绑定时刻起算佩戴。`ingest_band_domain` 原函数改名 `ingest_band_domain_single`，同名包装按佩戴者分流；只有一只手环、或 sleep/rr 域时原样直通，所以 `20260907020000` 用 `pg_get_functiondef` 打的补丁仍然在。
5. **第二只只能从设备页加。** Onboarding 只绑第一只，连接成功页留一行 `KEEP WEARING. CHARGE THE OTHER.`。启用第二只时借用手腕那只的链路：连接 → 校验 → 读能力表 → 注册槽位 B → 把链路还给手腕那只。它在启用之前记录的东西不进时间线。
6. **支持单只解除（2026-09-13 用户修订）。** 设备页选择 A / B，只关闭选中的绑定；另一只保持原槽位并成为当前使用的手环。删除最后一只才回到连接引导。`release_device` 成功后手机才移除本地绑定，失败可重试；历史留在账号上，空槽位可再次添加手环。此裁决替代原方案的「整套一起解除」。

7. **佩戴者按手机的键判。** 真机第一次走就撞上：手机给每条证据打的键是 CoreBluetooth 的 peripheral UUID（`BoundBand.identifier`），`devices.ble_identifier` 存的是固件报的 MAC，按 MAC 比对永远对不上，戴着的那只自己的采样反而被扣进 standby。`20260913120000` 给 `devices` 加 `client_key`，手机注册/加载时 `claim_device_key` 认领，`nb.wearer_device_key` 回 `coalesce(client_key, ble_identifier)`；认领时把此前扣住的采样重投。

8. **切换只有一次确认，起点由证据定。** 只有两只，点另一只的卡片本身就是选择，面板只确认一句 `Switch to HOOP B?`；不再有单选，也不再有「此刻 / 更早」。`record_wear_event` 不带时间时落在此刻并标 `source='auto'`；手机切过去读完那只之后调 `settle_wear_start`，`nb.wear_start_from_evidence` 从声明往回走那只手环自己「有脉搏」的连续段（断档 45 分钟为界，最多 24 小时，不跨越更早的声明），把起点移到段首——前提是同段时间里被换下的那只是静的（两只都有脉搏就不猜，留在此刻）。手动指定的时间 `source='manual'`，永不被移动，入口只在设备页 `Counted from …` 那行小字后面。见 `20260913140000`。

9. **App 只跟手腕上那只说话。** 待机那张卡没有自己的 SYNC 键——它记录的东西在你戴上它的时候一起读回来。firmware 只存 7 天，所以在最早的未同步那天要被覆盖前 24 小时，待机卡改印琥珀色的 `Wear it before 今天 13:54 or its oldest days are gone.`，而不是偷偷把链路切过去。
10. **没电有自己的说法。** 没电不是蓝牙问题：待机卡 `FLAT` + `It is out of charge and recording nothing.`；戴着的那只连不上且上次读到的电量见底时，条上印 `WEARING · FLAT`，同步失败的那句话也改成先去充电而不是先查蓝牙。切到一只上次读到没电的手环仍然允许（声明说的是手腕，不是链路），但面板会用琥珀色说清楚。
11. **状态不互相打架。** 顶栏那颗胶囊说的是链路，所以它一旦变 `CONNECTED`，石灰条就不能还写 `CONNECTING`——改成 `WEARING · SYNCING`，右边带 `3 / 9 DAYS`，卡上再画一条点阵进度条（`READING DAY 4 OF 9`）。速率由 SDK 决定，能诚实交代的是读到哪儿了。
12. **描边键必须自带命中形状。** `.buttonStyle(.plain)` 包一个只有描边的 `Text` 时，只有字形本身可点，中间是空的——`NOT NOW` 点不动就是这个原因。每个描边键都要 `.contentShape(Capsule())`。

13. **换手的基础体验按四个指标做。** ①点到石灰移动：本地写，不等网络也不等电台——声明先落盘，`replayPending` 丢进后台任务。②点到链路在新手环上、今天可读：第一趟只要 `.handover`（跳过历史回补），`WEAR_SWITCH_CONNECTED.MS` 量的就是这一段。③手环里剩下的天数：`.fullHistory` 在后台补，卡上进度条继续画，`WEAR_SWITCH_CAUGHT_UP.MS` 量它。④连点：整条换手串行一条任务，起手有 400 ms 合并窗，且总是追最新的那条声明——B→A→B→A 连点收敛成 0 次链路移动，落在 A（模拟器实测）。
14. **正在读的那次不再拖住换手。** 旧实现先 `waitForCurrentPull()` 再切指针，于是一次正在走一周历史的拉取能把换手卡几分钟。现在先把 `BoundBand` 指向新槽位——在读的那次发现 scope 不再属于自己，会在下一个日界自己停——再等 `awaitNativeIdle`。SDK 没有 stop，所以仍然等，但等的是一天的读取而不是整周。测量不可中断，所以没有拉取在跑时仍按旧顺序先等再切。

15. **一次切换只跑一趟同步。** 曾经为了让换手显得快，第一趟只读链路和今天，历史放到后台第二趟——结果用户看到的是"同步完一次又连一次、又同步一次"：第二趟会重走 `prepare`（所以又连接一次），还把今天和昨天再读一遍。现在只有一趟 `.fullHistory`；换手这件事在链路接通的那一刻就算结束（`phase` 提前落回 `.idle`），剩下的交给进度条，不再由 `phase` 一直占着说 CONNECTING。为这个拆分加的 `.handover` 请求类型随之删掉。

## 没做的（V1 之外）

- 自动判断佩戴（RSSI、离腕检测）。方案里排了优先级，但 V1 只用声明；做不好就把所有场景列清楚——见方案 §04.5 的 F/W/D/X 清单。
- Preferred HOOP、把一只交给别人。

## 文件

- 迁移 `supabase/migrations/20260913100000_two_hoops_one_wearer.sql`；测试 `supabase/tests/two_hoops_one_wearer.sql`。
- `Services/Band/DeviceSlots.swift`（槽位、时间线、`UserDefaults`）、`DeviceSetStore.swift`（加载、声明、链路移动、启用、解除）、`VeepooBand.swift` 的 `BoundBand` 改为读槽位。
- `Features/Device/DeviceSetSheets.swift`（启用 / 我戴的是哪只 / 解除两只），`DeviceView.swift` 的佩戴条、待机卡、空槽位卡。
- `Package.swift` 把 `DeviceSlots.swift` 编进 `NextBodySyncCore`；`WearTimelineTests`。
