# 通知触及 · 状态边沿 · 产品方案

2026-09-06 第三稿。经 grilling 拍板，见 [ADR 0019](../adr/0019-notifications-fire-on-edges.md) 与 `CONTEXT.md` 通知词条。本文件是已确认的策略，不是实现记录。通过之前的两稿（钟点四槽、未拍板的边沿稿）作废。

实现前不改客户端、不改前置说明屏、不发新的 `UNNotificationRequest`。昨夜本地排程仍按旧算术跑，直到本方案落地。

技术：**可行**。评估点是同步结束、日/夜结算、记餐、BLE 通断、电量包。本地请求立刻投或短延迟投；手环离开用「断开持续 4 小时」。`push_tokens` 已在生产库。云上刚算完、手机是死的，才需要 APNs Auth Key；没有钥匙时，进程活着就能推。

---

## 1. 开口与预算

通知是手机系统通知：锁屏出、解锁出横幅、NextBody 在前台也出。不是首页面板，不是腕上 Buzz。

每个用户日（04:00 切）最多 **投递 4 条**。同一种一天最多 1 条。手环没电与手环离开同一天只留更急的一条（没电优先）。

**吞掉**：人已经在这条深链的目标页上（燃料↔用餐、训练↔训练、设备↔手环、身体电量详情↔储量低 / 昨夜）。吞掉不占 4 条。在首页、计划页、别的详情，照推。

**免打扰** 22:30–07:00 是闸。闸里成立的边沿先记下；出闸后状态还在才投，人已经看过就丢掉。

**边沿**：上一份快照不成立，这一份成立。同一拍多条成立，只投优先级最高的一条。

优先级：手环没电 → 手环离开 → 昨夜 → 身体电量低 → 训练 → 用餐空档 → 当日收束。

评估发生在：同步 / `daily_results` 更新、一餐 `CONFIRMED`、BLE 通断、电量包、设置开关（只取消，不补发）。

---

## 2. 七条边沿

文案默认英文。数字只引用已结算或腕上最后真值。

### 昨夜 · `morning`

- **边沿**：今天第一次同时有整晚曲线和醒点，昨夜窗内（真实醒来起 6 小时），今早面板还没看过。
- **闸**：03:00 算完先按住；出闸后窗还在、没看过，再推。
- **文案**：与面板同一句（`LAST NIGHT` + 充电词）。
- **深链**：`nextbody://home?panel=body_battery`
- **开关**：Morning report。默认开。
- **不推**：没夜 / 已看过 / 过窗。过了窗打开 App 仍可看详情，不再叫昨夜卡。

### 用餐空档 · `meal`

- **边沿**：近 7 个用户日有过餐；今天未封口；这次同步 `kcal_out` 或活动分钟比上一拍增加；下一顿主餐仍未确认。
- **下一顿**：早餐已确认 → 问午餐；午餐已确认 → 问晚餐；今天还没记过餐但人动了 → 问第一个空着的主餐位。
- **文案**：标题跟那一顿（`LUNCH` / `DINNER` / `BREAKFAST`）；正文 `Have you eaten yet?`
- **深链**：`nextbody://fuel?slot=…`
- **开关**：Meals。默认开。
- **不推**：近 7 日零餐；加餐空着；一天已问过一顿；人在燃料页。

### 训练 · `training`

- **边沿**：有 `target_load`；`training_load` < `target_load`；身体电量第一次落到醒来值的 60%（没有醒来值则用当天最高储量）。
- **文案**：`TRAINING` / `You are still under today's target.`
- **深链**：`nextbody://training`（没有则落首页）。
- **开关**：Training nudge。默认开。副文案不再写 17:00。
- **不推**：已到 / 超过目标；没有目标；正在 Live Session；储量从没掉到那条线。

### 当日收束 · `daily` / 翻周 `weekly`

- **边沿**：夜充电 / 训练负荷 / 一餐确认 / 当前储量，第一次凑齐至少 2 样。第三样不重推。
- **周报**：用户日刚翻周，且上一周至少 4 个有效日 → 同一条换周报文案，不另占一条。
- **文案**：`TODAY` / `THIS WEEK`；只引用已有数，例 `Load 3.9 · 900 in · battery 41.`
- **深链**：`nextbody://home`
- **开关**：Daily wrap（取代 Sunday report）。默认开。
- **不推**：一样都没有；边沿出现时人已经打开过 App。不是计划页，不催勾任务。

### 身体电量低 · `reserve`

- **边沿**：`bodyBatteryForDisplay` 第一次 ≤ 25，观测未过期，且低于当天醒来值（或当天最高）。
- **文案**：`BODY BATTERY` / `Reserve is low.`
- **深链**：`nextbody://home?panel=body_battery`
- **开关**：Energy。默认开。
- **一天一次**。回到 40 以上再掉，当天也不再推。醒来就是 22 不推。

### 手环没电 · `band_battery`

- **边沿**：最后真读数第一次 ≤ 15%（格数固件 = 最低一格），且不在充电 / 已充满。
- **重置**：充电或回到 > 30%。
- **文案**：`HOOP` / `Charge HOOP.`
- **深链**：`nextbody://device`
- **开关**：Band（与离开共用）。默认开。

### 手环离开 · `band_away`

- **边沿**：已绑定；BLE 断开，并且这一次断开持续满 4 小时。
- **做法**：断开开始计时；满 4 小时仍断开 → 推；重连取消。
- **做不到**：进程从没起来过。下次起来重新计时，不补发。
- **文案**：`HOOP` / `HOOP has been away for 4 hours.`
- **深链**：`nextbody://device`
- **同一天**与没电只出一条，没电优先。

---

## 3. 设置与前置说明

副文案写阈值，不写钟点。

| 行 | 默认 | 管什么 |
|---|---|---|
| Morning report · WHEN LAST NIGHT LANDS | 开 | 昨夜 |
| Training nudge · UNDER TARGET · RESERVE DROPS | 开 | 训练 |
| Meals · NEXT SLOT EMPTY · YOU MOVED | 开 | 用餐空档 |
| Daily wrap · WHEN THE DAY FILLS IN | 开 | 当日收束；翻周换文案 |
| Energy · RESERVE CROSSES 25 | 开 | 身体电量低 |
| Band · AWAY 4 H / CHARGE 15 | 开 | 手环没电、手环离开 |
| Quiet hours · 22:30 → 07:00 | 开 | 闸 |

系统 ACCESS OFF：整表灰，只留 Open Settings。冷启动不弹系统框。Turn on 仍是唯一通向系统框的路。Not now 次日早晨再出前置屏。系统框拒绝过，不再出系统框。

前置说明改口：

- 废：`Every morning HOOP tells you how last night went. That's the only thing it will ever notify you about.`
- 新：`HOOP taps you when something changes — last night lands, a meal is still open, training is under, or the band goes dark.`

---

## 4. 明确不做

- 固定钟点排程。
- 一天超过 4 条；同线抖动连推。
- 催计划任务勾选（计划页 _Avoid_ 推送督促）。
- 早餐闹钟、加餐、蛋白、喝水、起立（腕上 Buzz）。
- 训练表扬、超额警告。
- 成分判定翻转、聊天、营销、固件。
- 把断连说成没戴。
- 没夜、没目标、从不记餐的空推。

---

## 5. 技术（落地时按这个拆）

**第一刀 · 本地**  
每次同步 / 记餐 / BLE 打快照，纯函数看哪条边沿新成立。单测：跨线、未跨线、闸持有、出闸仍在 / 已不在、目标页吞掉、预算 4。手环离开：断开时排 4 小时后的请求，重连取消。前台 `willPresent` 不再一律空：不在目标页就出横幅。

**第二刀 · 云端（可选）**  
结算在云上完成、手机当时是死的，APNs 补那一条。没有 Auth Key 就不上。

深链补 `nextbody://training`。埋点：`NOTIF_EDGE{KIND,REASON}` · `NOTIF_HOLD{KIND,QUIET}` · `NOTIF_DELIVERED{KIND}` · `NOTIF_OPEN{KIND}` · `NOTIF_SKIP{KIND,REASON}` · `NOTIF_BUDGET{N}`。

---

## 6. 验收

- 夜第一次算完、人不在目标页、不在闸里：立刻昨夜。03:00 算完：出闸后才出，且只在窗还在、没看过时。
- 记了早餐，后来同步消耗增加、午餐仍空：一条午饭。再动一次不再问。
- 近 7 日零餐：不问饭。
- 负荷低于目标，储量第一次掉到醒来值 60%：一条训练。整天储量都高：不催。
- 负荷已到目标之后储量才掉：不催。
- 当天第二次「两样齐」：不重发收束。
- 储量从 40 跨到 25：一条低储量。醒来就是 22：不发。
- 手环读数第一次 ≤ 15%：一条充电。断开满 4 小时：一条离开。同一天只留更急的。
- 一天已投 4 条：第五个边沿丢掉。
- 前台在燃料页、用餐边沿成立：无横幅，预算不扣。前台在首页：出横幅，扣预算。
- 文案键英文；中文只进 `zh-Hans.json`。
