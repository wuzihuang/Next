# 只有已注册的 device address 才能被配对 · 2026-09-06

目标：在服务器上维护一份手环 MAC 名单。不在名单里的手环，app 不让它完成配对，也不让它重连；名单可以撤销。

本文是计划，不是实现。工作树里其他会话的改动一律不动。

## 0. 先把事实边界说清楚

**MAC 只有密码验证之后才拿得到。** `VPPeripheralModel.h` 对 `deviceAddress` 的原话：「设备地址，密码验证成功之后可能会改变，扫描的列表中显示」。扫描阶段它是 CoreBluetooth 的 UUID，`veepooSDKConnectDevice` 走到 `.BleVerifyPasswordSuccess` 之后才变成手环真正的 MAC。app 现在的日志 `sdkAddressIsUUID` 记的就是这件事（`VeepooBand.swift:134`）。

由此「发现不了」只有两个可达层级：

| 层级 | 做法 | 现在能不能确定做到 |
|---|---|---|
| A · 扫描层 | 广播包里如果带 MAC，未注册的手环连 Searching 屏都不出现 | 未验证。要真机看一次 `kCBAdvDataManufacturerData` 才知道 |
| B · 验证层 | 连接并验证密码后读到 MAC，查服务器，不在名单就断开，配对条停在 AUTHORISE 段 | 确定能做，全部 API 都在 |

**决定：第一版做 B，A 作为一个真机 spike 单独立项。** B 已经满足「未注册的手环不能用」，A 只是把拒绝提前到扫描列表。B 的拒绝发生在 02 屏的 authorise 段（35–60%），这一段的名字本来就是「授权」，位置是对的。

**验证密码本身不是安全边界。** 所有 Veepoo 手环出厂密码 0000，`veepooSDKSynchronousPasswordWithType` 谁都能过。安全边界只在服务器名单上，客户端永远拿不到名单本身，只能问「这一个 MAC 在不在」。

**名单一旦上线，空名单会把所有人锁在外面。** 上线顺序必须是：建表 → 把现有手环写进名单 → 才发带门禁的 app。见第 5 节。

**ADR 0003 的前提由此补上。** 该 ADR 写明「跨手机独占归属与转让需先验证硬件身份能力」。验证后的 MAC 就是这个硬件身份，本计划顺手把 `BoundBand` 的绑定键从本机 UUID 改成 MAC。

## 1. 服务端

### 1.1 名单表

新迁移 `supabase/migrations/2026090xxxxxxx_registered_devices.sql`：

```sql
create table public.registered_devices (
  mac            text primary key,                 -- 规范形式 AA:BB:CC:DD:EE:FF，大写
  label          text,                             -- 给人看的名字，如「样机 3 号」
  registered_at  timestamptz not null default now(),
  revoked_at     timestamptz,
  note           text,
  constraint registered_devices_mac_form check (mac ~ '^([0-9A-F]{2}:){5}[0-9A-F]{2}$')
);
alter table public.registered_devices enable row level security;
-- 不建任何 authenticated 策略。客户端不能 select，名单不可枚举。
```

### 1.2 查询入口：一个 security definer 的 RPC

```sql
create or replace function public.device_registered(p_mac text)
returns boolean
language sql security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.registered_devices
    where mac = upper(p_mac) and revoked_at is null
  );
$$;
revoke all on function public.device_registered(text) from public;
grant execute on function public.device_registered(text) to authenticated;
```

只回 true / false。MAC 是 48 位空间，布尔 oracle 撞不出来，不需要额外限流。app 里 `SupabaseClient.rpc` 已经存在（`Supabase.swift:549`），不用部署 edge function。

如果以后要记录每次授权尝试（谁、什么时候、哪只手环被拒），再升级成 edge function `device-authorize`，套用 `metric-read` 的 `currentUserId + enforceRequestBudget` 骨架。第一版不做。

### 1.3 注册方式

第一版不做后台 UI。注册就是一条 SQL，走已链接的 CLI 或 `execute_sql`：

```sql
insert into public.registered_devices (mac, label) values ('C4:2E:8F:1A:73:9D', '样机 1');
-- 撤销
update public.registered_devices set revoked_at = now() where mac = 'C4:2E:8F:1A:73:9D';
```

### 1.4 修正 `devices` 表里的身份标记

同一迁移里补两件事：

- 回填 `ble_identifier_kind`：现在 `Repository.swift:387` 和 `:398` 无条件写 `'uuid'`，但验证后写进去的值其实是 MAC。用正则回填一遍 kind。
- 把回填后 kind = 'mac' 且 `unbound_at is null` 的行，作为初始名单 insert 进 `registered_devices`。这一步就是「先把现有手环写进名单」。

## 2. 客户端

### 2.1 MAC 规范化，纯函数，可测

`BandSyncPolicy`（`HomeLaunchPolicy.swift`）新增：

- `canonicalMAC(_ raw: String) -> String?`：接受 `C4:2E:…`、`C4-2E-…`、`c42e8f…`，输出 `C4:2E:8F:1A:73:9D`；不是 12 个十六进制位就回 nil。
- `matchesBoundDevice` 内部比对前先各自 canonical 化，避免 SDK 给的分隔符和我们存的不一致。

### 2.2 授权服务：一处决定，两条连接路径共用

新文件 `Services/Band/BandAuthorization.swift`，`actor`：

```
func allows(mac: String, account: String) async -> Verdict   // .allowed / .denied / .unknown
```

- 在线：调 `device_registered`，结果连同时间写进 UserDefaults 缓存，键含 account 和 mac。
- 离线：缓存里有且 24 小时内的裁决就用缓存；首次配对没有缓存 → `.unknown`，按拒绝处理。首次配对本来就要 `session.ensureSession()`，网络是前提，不算新限制。
- 撤销生效时机：下一次在线检查。不自动解绑，历史留在账号上，符合 ADR 0003「历史保留」。

### 2.3 在验证成功之后、承认连接之前拦下来

两条路径都直接调 `veepooSDKConnectDevice`，两处都要加，不能只改一处：

- `VeepooBand.connect`（`VeepooBand.swift:158`）：`.BleVerifyPasswordSuccess` 之后、`verified = true` 之前，读 `central.peripheralModel?.deviceAddress`。
  - canonical 化失败（SDK 没把它换成 MAC）→ fail closed，`veepooSDKDisconnectDevice()`，抛 `BandError.identityUnavailable`，日志记 `sdkAddressIsUUID = true`。这是真机要重点看的分支，见第 4 节。
  - `BandAuthorization.allows` 不是 `.allowed` → 断开，抛 `BandError.unregistered`。
  - 通过 → `BoundBand.bind(mac:peripheral:)`（新方法，见 2.5），再 `state = .connected`。
- `reconnectForSport`（`VeepooBand.swift:445`）：`outcome = true` 那个分支做同样三步。

`BandError` 新增两个 case：`unregistered`（文案 `THIS HOOP IS NOT REGISTERED`）和 `identityUnavailable`（文案 `HOOP IDENTITY UNREADABLE`）。

### 2.4 02 屏的新 edge

`ConnectFlow.swift` 的 `PairEdge` 新增 `.unregistered`。`runPairing` 的 catch 里：

- `BandError.unregistered` → `pairEdge = .unregistered`，`PAIR_FAIL` 的 `REASON` 记 `UNREGISTERED`。
- 条停在 authorise 段，颜色和现有 STOPPED / TAKEN 一致；两行文案：这只 HOOP 没有登记，联系发放它的人。不给重试按钮，重试没有意义。
- `identityUnavailable` 归入现有 `.stopped`，不单独开 edge。

### 2.5 绑定键改成 MAC

`BoundBand` 现在 `remember(peripheralIdentifier:)` 会在新配对时把 `identifier` 设成 UUID。改成：

- 新增 `bind(mac: String, peripheral: String)`：`identifier = canonical MAC`，`peripheralIdentifier = UUID`，owner 键照旧。
- `remember(peripheralIdentifier:)` 只更新本机 UUID，不再改写 `identifier`。
- 旧绑定（`identifier` 是 UUID）继续能匹配：`matchesBoundDevice` 已经同时比 `discovered` 和 `sdkAddress`，验证成功后那次 `bind` 会把它升级成 MAC。不写迁移代码。

### 2.6 `Repository.registerDevice` 的两个错处

- `ble_identifier_kind` 由值决定：`canonicalMAC` 成功就写 `'mac'`，否则 `'uuid'`。
- `sameHoop` 改成比 canonical MAC，不再比 `device_number`。SDK 头文件明说 `deviceNumber` 是「设备编号，开发者不用」，同型号手环都一样。

### 2.7 就绪门

`BandReadiness.allowed(account:binding:)` 多一条：`binding` 是 MAC 时，`BandAuthorization` 的缓存裁决不能是 `.denied`。这样撤销后 Home 不会靠 `reconnectIfBound` 偷偷连回去。Device 页 `IdentityRow` 旁边加一行状态：REGISTERED / NOT REGISTERED。

### 2.8 模拟器

`MockBand` 的种子 MAC `C4-2E-8F-1A-73-9D` 要么写进 `supabase/seed/demo.sql` 的 `registered_devices`，要么 `BandAuthorization` 在 `#if DEBUG` 下对 `BoundBand.seedIdentifier` 直接放行。选后者，seed 不碰真实名单。

## 3. 扫描层 spike（第二阶段，先不排）

问题只有一个：G70 / R30 的广播 `kCBAdvDataManufacturerData` 里有没有那 6 个字节等于验证后的 MAC。

做法：`VeepooBand` 用 SDK 扫描，拿不到原始广播。spike 时另起一个 `CBCentralManager` 只扫不连，把 manufacturer data 十六进制打进 `NightDiagnostics`，和验证后的 `deviceAddress` 对一眼。

如果有：可以在 `startScan` 的回调里对每个候选先问一次 `device_registered`，未注册的不发 `.discovered` 事件，Searching 屏就看不到它。不需要换成 `veepooSDKSelfScanConnectDevice`，那条路头文件写明不能和 `veepooSDKConnectDevice` 混用，换了就是整条连接路径重写。

如果没有：到此为止，B 就是终态。

## 4. 测试与验收

单元（`NextBodySyncCoreTests`）：

- `canonicalMAC` 三种输入形态、一种非法输入。
- `matchesBoundDevice`：绑定是 MAC、扫描给 UUID、`sdkAddress` 给同一 MAC 不同分隔符 → true。
- `registerDevice` 的 kind 推导和 `sameHoop` 用 MAC。

SQL（本地临时 PostgreSQL，套现有迁移测试方式）：

- 未知 MAC → false；注册 → true；撤销 → false。
- `authenticated` 直接 `select registered_devices` 被 RLS 挡住。

真机，按顺序：

1. 手环未注册 → 配对条停在 authorise 段，显示 NOT REGISTERED，`PAIR_FAIL REASON=UNREGISTERED`。
2. 注册 → 重新配对成功，`devices.ble_identifier_kind = 'mac'`，`BoundBand.identifier` 是 MAC。
3. 杀 app 重开，飞行模式 → 靠缓存重连成功。
4. 撤销 → 下次在线启动拒绝重连，Device 页显示 NOT REGISTERED，历史仍在。
5. 特别看：验证成功后 `deviceAddress` 是不是真的变成了 MAC。头文件用的是「可能会改变」，如果某个固件不变，`identityUnavailable` 分支就会把它挡住，这时要决定是放宽还是拒绝，而不是现在猜。

## 5. 顺序

1. 迁移：建表、RPC、回填 kind、把现有手环 insert 进名单。`supabase db push` 前先 dry-run，只推这一条。
2. 用 SQL 确认名单里已经有你手上每一只手环的 MAC。
3. 客户端 2.1 → 2.6，跑单元测试。
4. 2.7、2.8。
5. 真机走第 4 节的五步。
6. 之后再决定要不要做第 3 节的 spike。

## 6. 涉及文件

- `supabase/migrations/…_registered_devices.sql`（新）
- `app/NextBody/Services/Band/BandAuthorization.swift`（新）
- `app/NextBody/Services/Band/HomeLaunchPolicy.swift`：`canonicalMAC`、`matchesBoundDevice`
- `app/NextBody/Services/Band/VeepooBand.swift`：`connect`、`reconnectForSport`、`BoundBand`
- `app/NextBody/Services/Band/BandService.swift`：`BandError`
- `app/NextBody/Services/Band/BandReadiness.swift`：`allowed`
- `app/NextBody/Services/Repository.swift`：`registerDevice`
- `app/NextBody/Features/Connect/ConnectFlow.swift`：`PairEdge.unregistered`
- `app/NextBody/Features/Device/DeviceView.swift`：状态行
- `app/NextBodySyncCoreTests/`：新增测试
