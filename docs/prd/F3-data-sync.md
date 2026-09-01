# F3 · 数据与同步 Data & Sync

## Sec 01 · SEVENTEEN TABLES 一张都不能少
daily_results 是「同源同刻」的物理承载。sync_runs 是 SYNCED 那行字的依据。

| TABLE | 用途 | 关键列 | INDEX·写权限 |
|---|---|---|---|
| profiles | 一个人一行：档案 + 逐字段来源标记 | user_id pk → auth.users · timezone text not null · sex · height_cm · birth_date · goal · field_sources jsonb not null default '{}' | pk 即索引；own-row 全动作 |
| devices | 绑定的手环，一账号一只 | ble_identifier + ble_identifier_kind check in ('uuid','mac') · device_number · firmware_version · battery_percent / battery_level / battery_is_percent · bound_at · unbound_at · last_origin_sync_at | unique(user_id) where unbound_at is null。⚠️ delete 拒——Forget this HOOP 是写 unbound_at |
| device_capabilities | readDeviceFunctions 原样落库，决定所有测量入口死活 | device_id fk · read_at · functions jsonb · watch_data_day_number · body_component / ecg / hrv / stress / auto_measure（全部存 FunctionStatus 原值，不存 bool） | unique(device_id) 只留最新一行。unknown 与 unsupported 屏上都是整行不渲染，但排障时是两件事 |
| raw_samples | 5 分钟原始点，OriginData 逐条 | user_id · ts timestamptz（没有 user_day 冗余列）· heart · step · cal · dis · met · spo2 · temp · stress · sleep_states · src | unique(user_id, ts, src); idx(user_id, ts); insert only + on conflict do nothing |
| **daily_results** | 每人每天一行——四个上屏数字的唯一真相 | training_load · reserve_score · fuel_balance_kcal · daily_direction · the_call · the_call_confidence · algo_version not null · computed_at not null · inputs_hash | pk(user_id, user_day)；客户端只读，写只走 service_role |
| daily_training | 08 板详情：分区、峰值、曲线 | result_id uuid pk fk → daily_results · zone_minutes int[5] · peak_hr · session_count · curve jsonb | pk(result_id)；只读，没有 computed_at |
| reserve_samples | Body Battery 曲线的点 | user_id · ts · value smallint check(value between 0 and 100) · source。⚠️ 表名用中性的 reserve_*，不烧成 body_battery | idx(user_id, ts); insert + select |
| reserve_daily | 当日起点 / 谷底 / 现值 / 消耗去向 | result_id pk fk · wake_value · min_value · current_value · drain_drivers jsonb（13 板归因四行就落这里） | pk(result_id)；只读 |
| sleep_nights | 只进算式，不上屏 (D01) | user_id · user_day = 醒来那天 · total_minutes · deep_minutes · light_minutes · wake_count · raw jsonb | pk(user_id, user_day)。「昨晚怎么样」出现在今天这块屏上，就必须跟今天同一个 key |
| body_composition | 一次测量一行，MEASURED / DERIVED 逐行标注 | measured_at · user_day · measurement_source check in ('device_bia','health_scale','manual') · input_weight_kg · input_weight_id → weigh_ins · body_fat_pct · fat_mass_kg / lean_body_mass_kg · bmr_kcal · derived_fields text[] | idx(user_id, measured_at desc)。⚠️ 手环不产出体重——BodyCompositionTestResult 里没有 weight 字段 |
| weigh_ins | 体重序列，独立于 BIA；换机之后就靠它 | measured_at · weight_kg check(> 20) · source check in ('health','manual') · health_uuid · client_op_id uuid not null | unique(user_id, client_op_id); unique(user_id, health_uuid) where health_uuid is not null |
| meals | 只追加，永不 UPDATE | user_day · slot check in ('BREAKFAST','LUNCH','DINNER','SNACK') · logged_at · deleted_at · text_input · kcal check(null or > 0) · protein/carb/fat_g · confidence · model_version · client_op_id | unique(user_id, client_op_id); idx(user_id, user_day)。改一笔 = 软删一笔 + 记一笔 |
| day_fuel | 日级四态 + 四个餐位状态 | result_id pk fk · intake_state check in ('UNLOGGED','PARTIAL','FASTED','CONFIRMED') · kcal_in · kcal_out · slot_states jsonb | pk(result_id)；只读。两条 CHECK 见 02 节 |
| call_changes | The Call 每一次变化的留痕：从什么变成什么、因为哪条信号 | user_day · call · prev_call · reason · changed_by（如 recompute/meal_backfill）· algo_version · created_at · seen_at | idx(user_id, user_day desc)。10 板「判定不许无声地变」靠它成立 |
| screen_frames | AI 屏渲染过的每一帧（07 板契约的落库） | created_at · trigger · widget_tree jsonb not null · theme jsonb · model_version · latency_ms · tool_calls jsonb | append only；90 天滚动删。出问题能重放屏，不必重放模型 |
| analytics_events | 埋点，客户端批量 flush 写入 | name · props jsonb · client_ts · server_ts · app_version · device_model | 只 insert，连 select 都关掉；180 天滚动删 |
| **sync_runs** | 每次蓝牙同步一行——SYNCED 那行字的依据 | device_id · started_at · finished_at · outcome check in ('success','partial','failed','aborted') · days_requested · days_returned · error_code | idx(user_id, started_at desc)。outcome='partial' 不更新 last_origin_sync_at，但必须写这一行 |

⚠️ ble_identifier 在 iOS 是 CoreBluetooth UUID 不是 MAC（12 板规则 10），它换手机就变，永远不能当跨端设备标识——主键还是 id。
⚠️ battery 三列一起存：percent / level / is_percent，因为 isPercent=false 的固件只给 0–4 格，压成一列就再也分不清「82%」和「4 格」。

## Sec 02 · FIVE CONSTRAINTS 五段可以直接粘进 migration 的 SQL
1. **未知永不退化成 0 · 写进 CHECK，不是写进代码评审**
```sql
(intake_state = 'UNLOGGED') = (kcal_in is null)
intake_state <> 'FASTED' or kcal_in = 0
meals: kcal is null or kcal > 0
```
这两条把「0 是断言，—— 是沉默」从口号变成 Postgres 拒绝写入：UNLOGGED 想写 0 会被打回，FASTED（用户亲口说的零）想写 null 也会被打回。0 kcal 的一餐不存在，写 0 就是解析器出错了。

2. **改一笔 = 删一笔 + 记一笔，meals 永不 UPDATE**
meals 只 insert 和软删 (deleted_at)，从不 UPDATE。用户改一笔，客户端发两条 op、服务端一个事务处理，两条各带自己的 client_op_id。⚠️ 不做 UPDATE 的理由不是洁癖——AI 估的 kcal 带着 model_version，就地改写会让同一行既是三月的模型又是九月的模型。

3. **来源标记，以及 edit 的不可逆**
```json
{"height_cm":"edit","birth_date":"health","goal":"typed"}
```
HealthKit 同步逐字段判：标 edit 的整字段跳过，不比时间戳、不比新旧、不管 Health 那边多新。

4. **MEASURED 与 DERIVED 逐行说清**
手环 BIA 与体脂秤都是 MEASURED 并重新起锚：source='device_bia' 或 'health_scale'，derived_fields='{}'。只手动记体重、体脂率沿用旧锚点乘出来的：source='manual'，derived_fields 列出那三项。锚点一次都没有过的：整段不渲染，不写行。

5. **算法版本号跟着每一行走**
```
algo_version = "tl-2.1/bb-1.4/fuel-1.0/call-1.2"
```
inputs_hash 存这一天全部输入行的哈希：hash 没变而结果变了 = 算法变了（该有 call_changes）；两者都没变还重算 = 白烧钱，直接跳过。

## Sec 03 · RLS 四个动作分开写，不许图省事
⚠️ Edge Function 拿的是 service_role，而 service_role 绕过 RLS：每一条 SQL 都得自己带 where user_id = $1。

| TABLE 组 | SELECT | INSERT | UPDATE / DELETE |
|---|---|---|---|
| profiles / weigh_ins / meals | auth.uid() = user_id | 允许，with check 强制 user_id = auth.uid() | profiles 允许；weigh_ins 允许 delete；meals 只允许 update deleted_at 这一列（列级 policy），其余全拒 |
| devices | auth.uid() = user_id | 允许 | update 允许（改绑、写 unbound_at、更新电量与固件）。delete 拒——12 板那句「历史还在」靠它成立 |
| daily_results / daily_training / day_fuel / reserve_daily / call_changes | auth.uid() = user_id | **拒绝——客户端不许写结果** | 全拒。只有 service_role 写 |
| raw_samples / reserve_samples / sleep_nights / body_composition | auth.uid() = user_id | 允许——客户端是唯一采集方，一律 on conflict do nothing | 全拒。采集到的东西不可改 |
| screen_frames / analytics_events | screen_frames 只读自己的；analytics_events 连 select 都关掉 | 允许 | 全拒，append-only。保留期由 pg_cron 以 service_role 执行，不走 RLS |

## Sec 04 · WHERE IT RUNS 能重放的进 Postgres，不能重放的进 Edge Function
| 计算 | 跑在哪 | 为什么 |
|---|---|---|
| Training Load 0–21、分区时长、当日曲线 | Postgres `compute_training(uid, user_day)` | 只依赖 raw_samples 的行。同一批输入必须永远同一个结果 |
| Body Battery 0–100（睡眠作为输入） | Postgres `compute_reserve(uid, user_day)` | 睡眠只进算式不上屏 (D01)，是干净的纯函数 |
| Fuel 的额度、差值、四态、Daily Direction 三档 | Postgres `compute_fuel(uid, user_day)` | 加减法不值得一次网络往返。⚠️ 三档边界见 F2 06 节，在它给出之前这个函数返回 null，热力图不上色 |
| The Call 的 7 天 EMA、四象限、三档把握度 | Postgres `compute_the_call(uid, user_day)` | 要回溯重算三十天。只有 SQL 能一条 select recompute_range(uid, from, to) 跑完 |
| 「chicken and rice」→ kcal / 宏量 / 把握度 | **Edge Function + Vercel AI SDK** | 不确定、不可重放、要花钱。落库的是结果 (meals.kcal + model_version + confidence)，不是提示词 |
| 把结果渲染成 screen.render 的 widget 树 | **Edge Function**（契约归 07 板与 F4） | 每一帧原样存进 screen_frames——出问题能重放屏，不必重放模型 |
| 首页四个数字的当日增量 | 客户端 · 打 `provisional` 标记 | 只为了没网也能看。⚠️ 它和 SQL 那份是同一套公式的两个实现，Training Load 差值超过 0.3 就是 bug |
| 详情页的任何数字 | **一律不算** | 读 daily_training / day_fuel / reserve_daily，三张按 result_id 挂在同一行结果上 |

## Sec 05 · 「同源同刻」在实现上到底是什么
- **写入 · 这就是「同源」**：一次 recompute 起一个事务：算四个数 → 插/更 daily_results 一行拿到 result_id → 用同一个 result_id 覆盖 daily_training / reserve_daily / day_fuel 三张明细 → 提交。四张表要么一起变，要么一起不变。
- **computed_at · 这就是「同刻」**：只有 daily_results 有 computed_at，三张明细表一个时间戳都没有。想知道详情页那些数什么时候算的，只能回头看那一行。
- **禁止**：禁止任何详情页发起第二次计算请求。禁止 Edge Function 在渲染 widget 时顺手改一个数（哪怕只是四舍五入）。屏是结果的显示器，不是计算器。
- **读取**：首页读 daily_results 一行。详情页读 daily_results + 对应明细，按 result_id join。任何一个详情页发现 join 不到明细行，屏上原地降级成 ——，不自己补算、不发第二个请求。
- **过期**：客户端只看 computed_at，不判断算法版本新旧。算法 bump 之后由服务端把受影响的日期排进重算队列，算完 computed_at 自然变新。

## Sec 06 · THE QUEUE 五块板各写一遍的那件事，在这里只写一次
| 项 | 规格 |
|---|---|
| 形态 | 进程内单例 HoopQueue，串行。同一时刻在飞的原生命令恒等于 1 |
| 优先级 | P0 用户按下的 (start*Test、writeDeviceSetting、startFirmwareUpdate) / P1 进页刷新 (readDeviceVersion、readDeviceFunctions、listDeviceSettings、按日读取) / P2 后台同步 (startReadOriginData)。高优先级插队首，但不打断在飞的那一条 |
| 电量不进队列 | readBattery 只在 ready 那一次调用，之后一律吃 batteryData 事件。12 板规则 07 写死了「绑事件，不轮询」 |
| 去重与复用 | 队列深度上限 32。同 key（命令名 + 参数）后到的替换先到的，除非先到的已在执行。⚠️ startReadOriginData 是例外：它返回 Promise\<void\>，完成信号是 readOriginComplete 事件不是 Promise resolve。所以「进页复用正在跑的同步」复用的是 sync_runs 里那条 finished_at 为空的 run，不是复用 Promise |
| 超时 | 读类 15s。写类 12s ⚠️ 这个数来自 Android 侧的写指令 ack，iOS 没有对应的 ack，V1 的 12s 只是我们自己定的上限。startReadOriginData 不设固定超时，改用进度看门狗：readOriginProgress 连续 90s 无推进即判死 |
| **测量互斥 vs 写设置** | 两者处理相反，这一条最容易被拉平。start* 拿不到 measurementSlot 立即返回 DEVICE_BUSY，不排队——用户在等一个 60S 的东西，让他排队等于骗他。writeDeviceSetting 命中忙态入队并在屏上说明在排队（12 板规则 09 / EDGE 4），开关先弹回原位加一句 A measurement is running |
| stop 通道 | stop* 不进队列，走插队通道直发。放进队列会被前面排着的读命令拖到超时之后，那时测量还开着、电极还在耗电、下一次 start 必然 DEVICE_BUSY |
| 退出与断连清理 | 离开测量屏 / 切后台 / 断连前：先 stop*，等 over 或 1.5s 硬超时，再做下一步。`finally { await stop() }` 是硬要求。deviceDisconnected 到达时清空 P1/P2、释放 measurementSlot、在飞的命令 reject 成 DEVICE_NOT_CONNECTED |
| 可观测 | 每条命令进出队都记 BLE_CMD，本地批量缓冲、每 30 条或每 60 秒 flush 一次 |

## Sec 07 · CONNECTION LIFECYCLE & iOS BACKGROUND
12 板屏上那行 SYNCED 只有一个口径：最后一次 readOriginComplete{success:true} 的时刻，落在 devices.last_origin_sync_at。不是连接态、不是 readBattery 成功、不是 App 启动时间。

### 状态机
```
disconnected → scanning → connecting → connected
 → verifying(verifyPassword) → capabilities(readDeviceFunctions) → ready
```
verifyPassword 通过条件是 status ∈ {CHECK_SUCCESS, SUCCESS}，NOT_SET 也放行（出厂未设密码），其余退回 connected。只有 ready 才允许 P1/P2 入队；P0 在非 ready 时直接拒，屏上原地降级，不排队等连接。

### 能力表的位置在 ready 之前，不是之后
它决定后面所有测量入口的死活；晚一步，用户就会看到一个存在几秒然后消失的按钮。读到就 upsert 进 device_capabilities，存 FunctionStatus 原值。⚠️ 读失败时用库里的上一行，不要退回「全部支持」。

### 重连
指数退避 2 / 4 / 8 / 16 / 30s，上限 30s。连续 20 次失败后停止自动重连（省电），前台回来立刻重试一次。不弹窗、不 toast——首页设备状态那一行换字就是全部反馈。

### iOS 后台蓝牙
UIBackgroundModes: bluetooth-central + CBCentralManager 的 state restoration identifier。restoration 必须开，否则 App 被系统杀掉之后再也不会自己连上。⚠️ 这不是一个 JS 侧能打开的开关。后台被唤醒时只做一件事：一次 startReadOriginData()。

### HealthKit 后台 + 后台不做的事
enableBackgroundDelivery 频率 hourly + HKObserverQuery 触发 HKAnchoredObjectQuery。⚠️ anchor 持久化到沙盒，不要放 keychain——keychain 跨卸载存活，重装之后拿着上次的 anchor，历史增量永远补不回来且没有任何报错。后台只写库：不发通知、不刷新、不调 Edge Function、不触发重算。

## Sec 08 · OFFLINE & CONFLICTS
| 场景 | 行为 | 为什么 |
|---|---|---|
| 离线进首页 | 四个数字照常显示，读本地缓存的 daily_results 快照；设备状态行换成 OFFLINE + 最后同步时刻 | 昨天算出来的数字今天还是真的。把它换成 —— 是撒另一种谎 |
| 离线进四个详情页 | 历史部分照常渲染；需要重算的部分显示上一次的结果，不显示 —— | 旧的不等于没有，—— 只留给真的没有 |
| 离线进 AI 屏 | 原地降级成上一帧 screen_frames + 一行 OFFLINE · LAST UPDATED 08:12。输入框照常能打字，发送进 outbox | AI 屏是全产品唯一需要网络的东西。假装能答比说不能答糟得多 |
| 离线写（记饭 / 记体重 / 改设置） | 进本地 outbox：client_op_id(uuid) + op_type + payload + created_at + user_day。上线后按 created_at 顺序重放，服务端按 client_op_id 幂等 | 幂等键在客户端生成，不在服务端 |
| 两台手机都改了体重 | LWW by measured_at；同一秒按 source 优先级 health > manual。输的那笔留在 weigh_ins 里不删，只是不进序列 | 两台手机改的是同一个物理事实。⚠️ 手环不在这个优先级里，它根本不称重 |
| 两台手机各记一顿饭 | 都留下。meals 只追加；餐位状态由服务端按该餐位下末软删的条目重算 | 两顿饭都是真吃了的。这里用 LWW 会凭空吃掉一顿 |
| outbox 反复失败 | 同一条退避 1/2/4/8/16s 重试 5 次后标 stuck，在 Profile 页出一行琥珀 1 ENTRY NOT SAVED — TAP TO RETRY | 不弹窗、不拦路；但也不能无声丢 |

## Sec 09 · RECOMPUTE, RECEIPTS & HISTORY DEPTH
- **触发与范围**：五个入口排重算：补记 / 软删一顿饭、新增一条体重、一次 BIA 或体脂秤读数、一次成功的历史同步、算法 bump。范围恒为 recompute(uid, from_date, today)——那天以及之后的每一天。The Call 是 7 天 EMA，只重算那一天是错的。
- **样本口径与上限**：进 The Call 的只有 intake_state ∈ ('FASTED','CONFIRMED') 的日子。一次重算最多回溯 30 天；超过 30 天的补记照样入库，但不重算。
- **留痕与回执**：The Call 与上次不同就写一条 call_changes。The Call 变了而没有对应的 call_changes 行 = bug，这条能写成一句 SQL 断言进 CI 当门禁锁。屏上回执是琥珀一行：RECALCULATED · 3 DAYS CHANGED SINCE MON，看过写 seen_at 就消失。⚠️ 重算过程中不显示进度、不转圈、不灰掉。
- **历史深度 · 三个按日命令的参数不是一回事**：readOriginData / readDaySummaryData / readHRVData / readBodyCompositionData / readSportRecords 吃 dayOffset (0=今天)；readSleepData 和 readSportStepData 吃的是 yyyy-MM-dd 日期字符串。传错类型 SDK 不报错，它会当成「今天」默认返回。每次拉 dayOffset 0..N，N = min(watch_data_day_number − 1, 距上次成功同步天数 + 1) 且 N ≥ 1。⚠️ 代码里出现字面量 7 即为 bug——固件一改就全线静默错位。
- **换机 / 重装后体重序列从哪来**：云端 weigh_ins 表。V1 的答案就是这一行：数据本来就在服务端，不依赖 HealthKit 的历史授权，也不依赖手环。⚠️ 代价是「删账号 = 删体重历史」，注销流程里必须明说。
- 保留期：daily_results / weigh_ins / body_composition / meals / call_changes 永不删；raw_samples 400 天、screen_frames 90 天、analytics_events 180 天滚动删。

## Edge Cases · 06 数据层的六种坏，屏上一个弹窗都没有
1. **SYNC NEVER FINISHED** — `SYNC STALLED · OUTCOME PARTIAL` / `SYNCED 4 HRS AGO`。progress 连续 90 秒没推进就判死，sync_runs 记 partial。last_origin_sync_at 一动不动。不弹窗，下次进前台自动重试一次。
2. **TWO PHONES, TWO WEIGHTS** — `WEIGHT` / `78.4 KG · 2 MIN AGO`。按 measured_at 取晚的，同秒按 health > manual。输的那笔留在库里不删、不进序列。屏上完全不提「冲突」两个字。
3. **BACKFILL CHANGED THE CALL** — `RECALCULATED` / `3 DAYS CHANGED SINCE MON`。补记周一顿饭，周一到今天每天重算。配三条 call_changes，看过写 seen_at 就消失。⚠️ 变的是 The Call 不是 Daily Direction——热力图那三格可能一格都不动，两者用的是两套判据。
4. **DEVICE WINDOW EXPIRED** — `OUT OF DEVICE RANGE` / `-- · NOT RECORDED`。十天没戴，手环只留 watch_data_day_number 天，中间那几天永久没有。不插值、不用前后平均填。写 0 会让 The Call 判成 CUT——凭空造出一次减脂，比空着坏得多。热力图那几格留空。
5. **CAPABILITY TABLE NEVER READ** — `CAPABILITIES UNKNOWN` / `CONNECT TO MEASURE`。unknown 不是 unsupported，但屏上处理相同：整行不渲染。不许只让其中一个入口消失——能力表没读到时它们的把握度完全一样。读到过一次就用库里那行，宁可用旧的，也绝不退回「全部支持」。加号面板两行测量入口都消失。
6. **OFFLINE, LAST FRAME** — `OFFLINE` / `LAST UPDATED 08:12`。断网时原地留住上一帧 widget 树，加一行时刻。不整页 error、不跳回首页——降级只换颜色和那两行字。输入框照常能打字，发送进 outbox。

## 数据与同步 · 硬规则
01. 所有 daily_* 以 (user_id, user_day) 为主键，raw_samples 只存 ts 不存 user_day。服务端禁用 Postgres 的 current_date——数据库跑在 UTC，它给出的今天会比用户早或晚一天，而且只在半夜出错。
02. 四个上屏数字只存在 daily_results 一行里。daily_training / day_fuel / reserve_daily 一律用 result_id 外键挂上去，同事务写入，同事务回滚。
03. 只有 daily_results 有 computed_at 和 algo_version。明细表一个时间戳、一个版本号都不许加；客户端只看 computed_at，不判断版本新旧。
04. 详情页禁止发起任何计算请求。按 result_id join 不到明细行就渲染 ——，不许自己补算，也不许重试。
05. day_fuel 上两条 CHECK 必须存在。meals 与 weigh_ins 的 client_op_id 必须 not null——可空的幂等键在唯一索引里等于没有幂等键。
06. profiles.field_sources 里标 edit 的字段，HealthKit 同步逐字段跳过，不比时间戳、不比新旧。meals 永不 UPDATE，改一笔 = 软删一笔 + 记一笔，两条 op 一个事务。
07. 同一时刻在飞的原生命令恒等于 1。start* 拿不到 measurementSlot 立即返回 DEVICE_BUSY 不排队；writeDeviceSetting 命中忙态入队并在屏上说明；stop* 走插队通道不进队列；readBattery 只在 ready 那一次调用。
08. 离开测量屏 / 切后台 / 断连前必须先 stop*，等 over 或 1.5s 硬超时再往下走。写法固定为 `finally { await stop() }`。
09. SYNCED = 最后一次 readOriginComplete{success:true} 的时刻。outcome='partial' 不更新它，但必须写一行 sync_runs。后台唤醒只发 startReadOriginData()——readOriginData(dayOffset) 不触发设备同步，不许拿它当同步命令。
10. 每一次 The Call 变化必须有一条 call_changes。CI 里跑一句断言：The Call 与上一版不同且无 call_changes 的行数必须恒为 0。进 The Call 样本的只有 intake_state ∈ ('FASTED','CONFIRMED') 的日子。
11. watch_data_day_number 只能从 device_capabilities 读，代码里出现字面量 7 即为 bug。能力位一律存 FunctionStatus 原值，存成 bool 即为 bug。

## 上线前必须成立
- 最大的一条：本地 Nextbody-Hoop-Supabase 仓不是 Supabase Edge Function，是一套 FastAPI + Alembic + Redis 的服务端，已经有自己的 build server，表叫 food_entries / device_bindings / derived_input_snapshots / derived_workflow_runs——最后两张跟本板的 daily_results + inputs_hash 是同一个想法的两种实现。上线前必须裁一次谁往哪：要么把这份清单落成那套 Alembic migration，要么这份清单作数、那套仓退役。
- F0 法律 01 要求「一个概念只准有一个名字」，法律 02 要求「改一个指标名的成本必须是改一行」。这两条在存储层正面打架：叫 body_battery 满足前者、违反后者；叫 reserve 反过来。本板选了后者——商标风险是真的，migration 是最贵的那种改名。请拍板并回填进 F0：显示名走 METRIC_NAMES，存储层用中性名，法律 01 的「字面一致」只约束界面文案与板上文字。
- 30 天重算上限、400/180/90 天三条保留期、90 秒同步看门狗、退避 2/4/8/16/30s、outbox 重试 5 次、写类 12s 超时——六个数字全是拍的，其中 12s 那个连出处都是 Android 的。上线前至少用真机跑一周，把它们换成实测值。
- iOS state restoration 不是一个 JS 侧能打开的开关：CBCentralManager 由厂商 SDK 创建，restoration identifier 只能在原生初始化时传进去。上线前必须确认 SDK 是否已支持，不支持就得改 config plugin 或原生层——这是一条可能要动 SDK 的排期项，不是一行 Info.plist。验法：杀 App → 等两小时 → 查 sync_runs 有没有新行。模拟器验不出来，它没有 BLE。
- service_role 绕过 RLS。上线前拿另一个用户的 uid，对 daily_results / meals / weigh_ins / body_composition / screen_frames 各做一次越权拉取，五次全空才算过。这是硬门，不是抽查。
- HealthKit 体重的 background delivery 实际频率由系统说了算，hourly 只是上限。若实测投递延迟经常超过 4 小时，D06「Apple Health 自动读」在体验上就不成立，得改成每次进前台主动跑一次 anchored query。
- 埋点清单：`SYNC_STARTED{TRIGGER,DAYS_REQUESTED}` · `SYNC_FINISHED{OUTCOME,DAYS_RETURNED,MS}` · `SYNC_WATCHDOG_KILLED{LAST_PROGRESS_PCT,STALLED_MS}` · `BLE_CMD{NAME,PRIORITY,QUEUE_MS,EXEC_MS,RESULT}` · `BLE_BUSY_REJECTED{NAME,SLOT_HOLDER}` · `BLE_WRITE_QUEUED{KEY,QUEUE_MS}` · `CAPABILITIES_READ{SOURCE,WATCH_DATA_DAY_NUMBER}` · `RECOMPUTE_RUN{TRIGGER,FROM_DATE,DAYS,MS}` · `CALL_CHANGED{DATE,FROM,TO,CHANGED_BY}` · `OUTBOX_STUCK{OP_TYPE,ATTEMPTS}` · `WEIGHT_CONFLICT_RESOLVED{WINNER_SOURCE,DELTA_KG}` · `PROVISIONAL_VALUE_SHOWN{METRIC,AGE_MIN}` · `HEALTHKIT_DELIVERY{TYPE,LATENCY_MIN}` · `BACKGROUND_WAKE{REASON,DID_SYNC}`
- 验收线，连续七天真机、至少 6 台设备：① 首页四个数字与详情页逐日比对，168 次比对零不一致；② provisional 值存活超过 24 小时的次数 = 0；③ CI 那句 call_changes 断言恒为 0 行；④ 杀 App 后两小时内 sync_runs 出现新行的比例 ≥ 80%；⑤ 五张表越权拉取全空；⑥ BLE_BUSY_REJECTED 占比 < 1%；⑦ 每天 04:00 前一小时的 raw_samples 覆盖率与其他小时持平（差 > 5% 说明多出来那一页没拉）。①掉了是写 recompute 事务的人，不是前端渲染；⑥掉了是队列没做成单例。
