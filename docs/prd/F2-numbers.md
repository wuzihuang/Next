# F2 · 口径与公式 The Numbers

## Sec 01 · THE CALENDAR 一天从 04:00 开始，dayOffset 只是分页参数

### 先算窗口，再决定拉几页
W = [本地 04:00, min(now, 次日 04:00))
- now ≥ 04:00 且 整段落在今天 → 只拉 dayOffset 0
- now < 04:00（正在进行的是昨天那本） → 拉 0 与 1 两页
- 日闭合 → 必然跨两页 → 1 取 04:00 后，0 取 04:00 前
- ⚠️ 少拉一页不报错，只是数字偏小。凌晨打开 App 和每天早上第一次日闭合，是唯二会踩的时刻。

### 落库形状
原始点存 UTC 时间戳 + 采样时的 IANA 时区串 `sampled_tz`，不存本地字符串。⚠️ OriginData 只有 time 一个字符串，没有 date、没有时区、没有偏移——一页点的日期只能由你请求的那个 dayOffset 反推。所以每一批点入库必须把 dayOffset 换算出的日历日一起写进去，否则跨页拼接时排不出先后。规则：以「这一批同步发生时手机所在的时区」给整批点打戳，一批不许混两个时区，已落库的行永远不重新打戳。
刀口落在 04:00 而不是设备本地 0:00：09 板餐位轴上已经印着「01:20 +1」，那是凌晨一点的夜宵。按设备日切，这顿饭算进第二天，「昨天吃了多少」永远少一顿。

## Sec 02 · 派生量全表 EVERY NUMBER'S BIRTH CERTIFICATE
全部在 Edge Function 里算完落 daily_metrics，App 只负责取和排版。离线时首页显示最后一次成功落库的值并在卡头挂 AS OF HH:MM，客户端绝不本地补算。

| SYMBOL | INPUT FIELDS | FORMULA | UNIT·ROUND | IF MISSING |
|---|---|---|---|---|
| USER_DAY | phone tz + readOriginData(dayOffset) | 本地 04:00 → 次日 04:00；按窗口切段决定拉几页，见 01 节 | date | tz 缺 → 沿用上次成功的 tz |
| WEIGHT_KG | HealthKit bodyMass / 手动记一笔 (10S) | 该用户日 04:00 之前最近的一条，不取之后的 | kg · 0.1 | 真缺 → 额度与宏量整块不渲染，走 09 异常 4 |
| HR_MAX | profile.birthdate | 208 − 0.7 × age (Tanaka) | bpm · 整数 | 无生日 → 分区与 LOAD 整块不渲染 |
| HR_REST | OriginData.heartValue (睡眠窗口内) | 近 7 用户日睡眠窗口内最低 10% 的中位数；周一 04:00 重算一次，整周冻结。窗口取 sleepTime→wakeTime，无睡眠数据退化为本地 00:00–06:00 | bpm · 整数 | <3 夜 → 用建档那次 60 秒实测当种子并标 ESTIMATED，禁用常数 |
| HRR_i | heartValue, HR_MAX, HR_REST | (h − HR_REST) / (HR_MAX − HR_REST), clamp 0–1 | 比值 · 0.01 | 该点丢弃，不补零 |
| RAW_LOAD | 5 分钟点 HRR_i | Σ w(HRR_i) × 5；w 见 03 节 | load·min · 0.1 | 当日点覆盖 <50% → 打 PARTIAL |
| TRAINING_LOAD | RAW_LOAD | 21 × (1 − e^(−RAW/60))；日内单调不降。渐近线永远够不到 21，最大显示 20.9 | 0–21 · 0.1 | 无点 → ——，不写 0 |
| BB_WAKE | 13 板的充放电积分 (sleepLine, RMSSD, HR_REST) | 醒来那一次的值，冻结全天，只用来推 TARGET_LOAD。系数与式子在 13 板首发，本表不重写 | 0–100 · 整数 | 缺 → ——，训练环 TARGET NOT SET |
| BODY_BATTERY(t) | BB_WAKE + 13 板逐 tick 充放电 | 当日连续曲线，醒来等于 BB_WAKE、清醒时段单调不增。⚠️ 它和 BB_WAKE 是两个符号，别混用 | 0–100 · 整数 | BB_WAKE 为 —— → 全天 —— |
| TARGET_LOAD | BB_WAKE | 按 13 板那张九档对照表取值，档内不插值。BB_WAKE 72 → 14.5，就是 08 屏那个数 | 0–21 · 0.1 | BB_WAKE 缺 → 目标行整条不出现 |
| ZONE_MIN[1..5] | HRR_i | 按 03 节边界计数 × 5。⚠️ 任何分区时长只能是 5 的倍数 | min · 整数 | 缺 HR_MAX → 整块不渲染 |
| BMR | WEIGHT_KG, height, age, sex | 10W + 6.25H − 5A + (男 +5 / 女 −161), Mifflin-St Jeor。⚠️ 不用 BIA 回来的 basalMetabolicRate | kcal · 1.0 | 任一项缺 → 卡片整张不渲染 |
| E_ACTIVE | OriginData.met, WEIGHT_KG | Σ 非运动窗口点 max(0, met−1) × 1.05 × W × (5/60)。⚠️ 绝不用 OriginData.calValue，它内含厂商自己的基础代谢，加到我们的 BMR 上就是双算 | kcal · 1.0 | 无 met → 该点按 met=1 记 0 |
| E_TRAIN | SportRecord.calories / durationSeconds, BMR | 有 calories: max(0, calories − BMR 按秒分摊)；无 calories: 窗口内点按 E_ACTIVE 同式积分 | kcal · 1.0 | 无运动记录 → 0（这是断言，不是沉默） |
| E_TRAIN_PLAN | 用户在 dock 里说的今天要练什么 | 09 屏那条虚线 480 的出处。永远虚线，永远不进实测刻度。本板新增符号——在此之前它没有出处 | kcal · 1.0 | 没说 → 该行不渲染，E_OUT_FULL 里这一项为 0 |
| E_OUT_NOW | BMR, E_ACTIVE, E_TRAIN | BMR × 已过分钟 ÷ 窗口分钟 + E_ACTIVE + E_TRAIN。三项之和必须等于卡头那个数 | kcal · 1.0 | 三项缺一 → 卡整张不渲染 |
| ACTIVE_FCST | 近 14 用户日的 E_ACTIVE 分时曲线 | 当前时刻到 04:00 剩余段的逐日中位数之和；需至少 5 个有数据的日子 | kcal · 1.0 | <5 日 → 该项为 0 且条件式那行不渲染 |
| E_OUT_FULL | E_OUT_NOW, ACTIVE_FCST, E_TRAIN_PLAN | BMR 整窗 + E_ACTIVE + E_TRAIN + ACTIVE_FCST + E_TRAIN_PLAN。09 屏那个 2,280 就是它 | kcal · 1.0 | ACTIVE_FCST 缺 → 条件式那行不渲染 |
| E_IN | AI 食物记录 confirmed 条目 | Σ 已确认餐位 kcal。FASTED 是 0，UNLOGGED 是 null——两者在数据层永不互换 | kcal · 1.0 | UNLOGGED → —— |
| BALANCE | E_IN, E_OUT_NOW | E_IN − E_OUT_NOW，负 = 亏空。两边都是实测 | kcal · 1.0 · 带符号 | E_IN 为 null → —— |
| TARGET_IN | E_OUT_FULL, goal | E_OUT_FULL + Δ（见 04 节），再由宏量回加改写。⚠️ 顺序不能反 | kcal · 见 04 | E_OUT_FULL 缺 → 额度不渲染 |
| P / F / C | WEIGHT_KG, goal, TARGET_IN | P、F 按 04 节系数取整到 5；C 吃余量，顺序写死 P → F → C | g · 5 | WEIGHT_KG 缺 → 三格全 —— |
| NEXT_MEAL | TARGET_IN, E_IN, 空餐位数 | 剩一个空餐位: = TARGET_IN − E_IN，不取整不 clamp。剩多个: ÷ 空餐位数，向下取整到 50，clamp 150–1200。这一条同时管住 09 屏那个 ~500 和 660，两屏共用一条式子 | kcal | 分子 ≤ 0 或无空餐位 → ——，不出负数、不出 0 |
| FAT_KG / LEAN_KG | BodyCompositionSample (MEASURED) 或 体重 × 体脂率 (DERIVED) | 逐样本标 MEASURED / DERIVED。只有体重没有体脂率 → 两个量都不产出 | kg · 0.01 | 无 → 象限不渲染 |
| FAT_EMA / LEAN_EMA | FAT_KG / LEAN_KG | EMA α = 0.25 (N=7)；首样本直接播种；换测量来源必须重新播种 | kg · 0.01 | 7 日窗口内 <5 次测量 → 象限不渲染 |
| CONFIDENCE | n_scans_7d, σ(raw − EMA) | 三档，见 05 节。屏上只有 PENDING / MEDIUM / HIGH 三种写法，不许有第四种 | 三档 | n<5 → PENDING，不写 LOW |
| DIRECTION | E_IN, E_OUT_NOW | 日闭合后 BALANCE 分三档，见 06 节。热力图上那个红点绿点就是它 | 三档 | 记录不足 → 两种灰之一，见 06 节 |

## Sec 03 · ZONES & LOAD WEIGHTS 一套边界，两处用途
用心率储备 (Karvonen) 而不是 %HRmax，因为 HR_REST 是我们每晚都真实量到的数；用上它，分区才是这个人的分区。权重表和分区边界共用同一组数 (30/40/55/70/85)。屏上写着 Z4 的那 15 分钟，必须正好是负荷里按 3.00 计的那 15 分钟。

| ZONE | HRR RANGE | EXAMPLE (AGE 34, REST 52) | LOAD WEIGHT w | NOTE |
|---|---|---|---|---|
| BELOW | < 30% | < 92 bpm | 0.00 | 不计负荷，不画条 |
| Z1 | 30% – 40% | 92 – 105 bpm | 0.15 | 日常走动 |
| Z2 | 40% – 55% | 106 – 125 bpm | 0.50 | 轻松有氧 |
| Z3 | 55% – 70% | 126 – 144 bpm | 1.20 | 中等强度 |
| Z4 | 70% – 85% | 145 – 164 bpm | 3.00 | 环开始跑得快的地方 |
| Z5 | ≥ 85% | 165 bpm + | 6.00 | ⚠️ 屏上「Z5 4 MIN」不成立，只能是 5 的倍数 |

⚠️ HR_REST 必须整周冻结、周一 04:00 才重算：它每天动一点，Z2 的下沿就每天动一点，08 板的「本周分区时长」就永远无法跨周比较。
六个权重和 K=60 是拿四个场景锚点反解出来的：久坐日 3.9 / 45 分钟 Z2 跑 11.4 / 间歇课 18.2 / 比赛日 20.8，容差 ±0.3，任何一次改参数都要重跑。

## Sec 04 · ENERGY & MACROS 三个数相加必须等于卡头
| GOAL | ENERGY Δ | PROTEIN g/kg | FAT g/kg | CARB |
|---|---|---|---|---|
| CUT | −600 kcal | 2.0 | 0.8 | 余量 ÷ 4 |
| **RECOMP · 09 屏这一档** | **−380 kcal** | **1.9** | **0.8** | 余量 ÷ 4 → 145 / 60 / 195 正好回加 1,900 |
| BULK | +300 kcal | 1.6 | 0.9 | 余量 ÷ 4 |

取整规则跟着定死：P、F 取整到 5，C = (TARGET_IN 原始 − 4P − 9F) ÷ 4 取整到 5，然后把展示的 TARGET_IN 改写成 4P + 9F + 4C。⚠️ 顺序不能反——先把 TARGET_IN 取整到 50 再算宏量，回加就永远差十几 kcal。
碳水地板 100 g，顶住时先从脂肪里扣（不低于 0.6 g/kg），还不够就缩小赤字并把额度行标琥珀，绝不出现负数碳水。
RECOMP 取 −380 是被 09 屏逼出来的：E_OUT_FULL = 2,280 (1,480 + 320 + 480)，TARGET_IN = 1,900，145 / 195 / 60 三个宏量回加正好 1,900，差额正好 −380，落在 09 屏那条 −200~−500 的绿带里。

## Sec 05 · EMA, THRESHOLDS & CONFIDENCE 三档，不许有第四种写法
FAT Δ7D 阈值 ±0.15 KG，LEAN Δ7D 阈值 ±0.10 KG。九种组合：

| FAT Δ7D | LEAN Δ7D | QUADRANT | 读作 |
|---|---|---|---|
| < −0.15 | > +0.10 | RECOMP | 脂肪降、瘦体重升 |
| 带内 ±0.15 | > +0.10 | RECOMP | 脂肪没动、瘦体重升 |
| > +0.15 | > +0.10 | BULK | 两个都升 |
| < −0.15 | 带内 ±0.10 | CUT | 脂肪降、瘦体重守住 |
| 带内 ±0.15 | 带内 ±0.10 | MEASURED, NO CHANGE | 空心格，不是 DRIFT，也不是失败 |
| > +0.15 | 带内 ±0.10 | BULK | 只有脂肪在涨 |
| < −0.15 | < −0.10 | CUT | 两个都降。这不是 RECOMP |
| 带内 ±0.15 | < −0.10 | CUT | 瘦体重在掉 |
| > +0.15 | < −0.10 | DRIFT | 脂肪升、瘦体重降 |

### 把握度三档 · σ 是降档条件，不是新档
- n = 7 且 σ(raw − EMA) ≤ 0.35 kg → HIGH
- n ≥ 5 且 σ ≤ 0.70 → MEDIUM
- n ≥ 5 但 σ > 0.70 → 退回 PENDING
- n < 5 → PENDING

σ 大说明这几次称重互相打架，凑够天数不等于凑够证据。

### 一条 SDK 事实必须写进流程
手环 BIA 的 fatMass / leanBodyMass 是拿我们通过 syncPersonalInfo 推下去的体重算出来的。所以每次 startBodyCompositionTest 之前必须先用当前 WEIGHT_KG 同步一次；没同步就测的样本直接丢弃，不入 EMA。也因此 FAT 与 LEAN 不是两个独立测量——它们由同一次测量的体重与体脂率乘出来，Δfat + Δlean 恒等于 Δweight。

## Sec 06 · DAILY DIRECTION 三档颜色加两种灰，一格都不许含糊
- **DEFICIT · 柠檬绿实心**：BALANCE ≤ −150 kcal。要求当天已闭合（过了次日 04:00），FUEL 是 CONFIRMED / FASTED / 或 PARTIAL 且已确认餐位 ≥ 2，且当天手环点覆盖 ≥ 50%。绿点是热力图上唯一的柠檬绿。
- **LEVEL · 描边空心**：−150 < BALANCE < +150。±150 是记录误差的地板：AI 估摄入的相对误差约 10–15%，MET 估消耗同量级，两者一叠，150 kcal 以内的符号没有意义。只描边不填色——它说的是「分不出来」，不是「刚刚好」。
- **SURPLUS · 红**：BALANCE ≥ +150 kcal。红只给这里，其余任何地方的红都留给真正的 ALERT。这是全产品第二处允许出现红的地方，第一处是 11 板的删除账号。
- **灰 A · NOTHING LOGGED**：UNLOGGED，或 PARTIAL 只有 1 个餐位。我们不知道他吃了什么。对应 11 板图例里「NO WEIGH-IN」那一档的位置。
- **灰 B · NO BURN**：记了吃的，但当天手环点覆盖 < 50%。方程只有一半，半个断言不上色。⚠️ 最容易犯的错是「用 BMR 当 OUT 凑一个点」——那等于假设用户躺了一天，红点会假性偏多。两种灰必须不同色。
- **两者矛盾时**：连续绿点却判 DRIFT 或 BULK，不是 bug。只有当这种矛盾连续 14 天成立，才在 10 板顶部出一行琥珀，英文原文写死为 YOUR LOGS AND YOUR SCANS DISAGREE. LOGGED INTAKE MAY RUN LOW. 只报告分歧，不给建议、不做分级、不出诊断。
- ⚠️ 两者的投票资格不同且必须保持不同：PARTIAL ≥ 2 餐位的那天可以给热力图一个点，但按 10 板规则它不给四信号投票。

## Sec 07 · CONFLICT RULINGS 同名不同义的地方，今天全部处理掉
| WHERE | SAME NAME, TWO MEANINGS | RULING |
|---|---|---|
| 08 规则 03 与解锁时间轴 | 「一天的边界是设备本地日，不是手机时区，dayOffset=0 由手环判定」 | 两处全部改为用户日 04:00→04:00，引用本板规则 01。dayOffset 只出现在取数代码里。 |
| 09 规则 08 的 ⚠️ 半句 | 「IN 走 App 的 04:00 日、OUT 走设备的 0:00 日……两本日历不允许同时存在」 | 前半句（04:00 切、01:20 +1）保留，⚠️ 那一整段删掉改引用本板规则 01。两本日历的问题已经不存在。 |
| 09 卡头 ENERGY BALANCE | −620 NOW 用 1,860（已过时段）、−380 EST 用 2,280（全天）。同一条轴上两个基数 | 两行都留，换语义而不换像素：NOW = E_IN − E_OUT_NOW，两边都是实测 (1,240 − 1,860 = −620)；第二行标签从 EST 改成条件式 IF YOU HIT BUDGET，定义为 TARGET_IN − E_OUT_FULL (1,900 − 2,280 = −380)。 |
| 09 屏那条虚线 TRAINING 480 | 它进了 2,280，但全产品没有一个符号定义它 | 定为 E_TRAIN_PLAN，来源是用户在 dock 里说的今天要练什么。⚠️ 本板新增符号——在此之前这个数字没有出处，而这块板的立场就是没有出处的数字不许上屏。 |
| 08 屏 TARGET 14.5 | 整页立论是「今天该练到多少」，但这个数从哪来从没写过 | 定为 TARGET_LOAD，按 13 板九档表取值。BB_WAKE = 72 时正好 14.5，与面板上的 BODY BATTERY 72 闭合，08 屏那句「LANDS AT 69% OF THE FULL RING」一个字都不用改。 |
| F0 的 Body Battery 定义 | F0 词汇表写「它是一条连续曲线，不是每天早上算一次的快照」，但训练目标又必须一天只定一次 | 拆成两个符号：BODY_BATTERY(t) 是连续曲线，BB_WAKE 是醒来那一次的值、冻结全天、只用来推 TARGET_LOAD。一天的训练目标必须在一天开始时就成立，但电量本身照常掉——一件事，两个名字。 |
| 10 板 CONFIDENCE 的三档 | 10 规则写「5–6 天 MEDIUM、7 天 HIGH」，纯按天数 | 保留三种写法与天数下限，加上 σ 作为降档条件（见 05 节）。 |
| 10 板的两个 5/7 | CONFIDENCE 数的是称重天数，四信号数的是记录天数，两个分母长得一样 | 拆成 n_scans_7d 与 n_logged_7d 两个计数器两个名字。屏上禁止无主语的分数，必须写 5/7 SCANS 与 6/7 LOGGED。 |
| 蛋白的 1.8 与 1.9 | 10 屏印着「7 OF 7 DAYS AT OR ABOVE 1.8 G/KG」，09 的目标是 1.9 g/kg | 两个数都对，但必须写清是两件事：1.9 是每日目标，1.8 是四信号里给「蛋白达标」记票的门槛，低 0.1 是因为达标判定不该要求每天精确命中目标。 |
| 10 的 7 天日变化 vs 11 的 12 周净变化 | 10 屏 FAT −0.42 / LEAN +0.18 · 7D；11 屏 FAT MASS −2.1 / LEAN +1.4 / BODY FAT 14.2。都是 KG、都带正负号、排版一样 | 10 屏已经写了 7D 不用改，字段 fat_ema_delta_7d / lean_ema_delta_7d。11 按它自己 caption 的要求在卡头印区间 (RECOMP · 12 W)，字段 fat_mass_delta_12w 等。⚠️ BODY FAT 14.2 是绝对值不是变化量，夹在两个变化量中间必须单独标注。 |
| 03 交底页 vs 全局 BMR | BIA 回来的 basalMetabolicRate vs Mifflin 算的 BMR | 每日额度只用 Mifflin。BIA 的 BMR 降级成成分详情里一行 MEASURED 参考值，不进任何算式。理由：电极接触好坏能让它单次差数十 kcal，握姿变了额度就变，这种 bug 用户自己查不出来。 |
| E_ACTIVE 的来源 | OriginData.calValue vs MET 积分 | 一律 MET 积分。calValue 内含厂商自己的基础代谢，与我们的 BMR 双算——这是最容易悄悄多算几百 kcal 的地方。 |
| 04 首屏环 vs 08 详情环 | 两处各自从原始点重算，于是会出现 12.4 与 12.6 | 同取 daily_metrics.training_load 一个字段。前端不许持有第二份算法。 |

## Sec 08 · VERSION & BACKFILL 改算法不动历史，改输入才重算
- **每行带版本**：daily_metrics 每条日结果落 calc_version (semver) 与 inputs_hash（输入字段的稳定哈希）。inputs_hash 变了才允许重算，calc_version 变了不重算。
- **minor 与 major 的边界**：minor = 口径调整但用户看不出数量级变化（例：ACTIVE_FCST 的中位数窗口 14 天改 21 天）。major = 同一天的同一份输入会算出肉眼可见的差别（例：K 从 60 改 50）。major 升版必须同时更新 03 节那四个锚点数。
- **不回填**：改算法只对之后的用户日生效。历史行永远保留当时那个版本算出的数，哪怕新算法更好。
- **用户改一笔不算回填**：F0 右列点名 09 缺「改一笔／删一笔」的入口，那个入口一旦补上，就有第三条重算路径：用户改了某天的餐，inputs_hash 变，该用户日按它原本那个 calc_version 重算并覆盖。这不是回填，不写 recompute_log，但要发 CALC_RECOMPUTE_EDIT。⚠️ 可改动范围限最近 7 个用户日，再往前只读。
- **图上怎么标**：折线跨过版本边界时画一条 1px 竖虚线，不配文字、不配图标。点进那一天的详情才在底部多一行 CALC v1.2 → v1.3。
- **唯一的例外**：同一 version 内算错了（真 bug），才允许批量回填。回填必须写 recompute_log：版本、原因一句话、影响行数、执行时刻。没有 recompute_log 的批量 UPDATE 视为事故。
- AI 也吃这一套：食物估算的模型与提示词版本落 ai_estimate_version，与 calc_version 分开。换模型不重估历史餐；只有用户主动改了描述才重估那一顿，且旧值保留在 revision 里。

## 口径 · 硬规则
01. 屏上的每一个数字必须能在 02 节找到它的符号、输入、公式和版本号。找不到就不许上线。
02. 全部派生量在 Edge Function 里算完落 daily_metrics，客户端不许有第二处算法。离线时显示最后一次落库值并挂 AS OF HH:MM，绝不本地补算。
03. 一本日历：用户日 04:00 → 次日 04:00。先算窗口再决定拉几页，白天一页、凌晨与日闭合两页。BMR 按窗口实际分钟数分摊。
04. 原始点必存 UTC 时间戳 + sampled_tz + 该批 dayOffset 换算出的日历日。同一批不许混两个时区，已落库的行永远不重新打戳。
05. 未知永不退化成 0：数据层写 null，屏上写 ——。FASTED 的 0 是断言，UNLOGGED 的 null 是沉默，两者在任何一层都不许互换。
06. 分区边界与负荷权重共用同一组数 (30/40/55/70/85)。HR_REST 周一 04:00 重算一次，整周冻结。
07. 宏量顺序写死 P → F → C，P、F 取整到 5，再把展示的 TARGET_IN 改写成 4P + 9F + 4C。碳水地板 100 g，绝不出现负数碳水。
08. 象限九种组合完备，两条都在带内 = MEASURED, NO CHANGE，不是 DRIFT。把握度只有 PENDING / MEDIUM / HIGH 三种写法。
09. 每日方向与四象限不共用颜色，也不共用投票资格。PARTIAL ≥ 2 餐位的天给热力图一个点，但不给四信号投票。
10. 每条日结果落 calc_version 与 inputs_hash。inputs_hash 变了才重算，calc_version 变了不重算，改算法不回填历史。
11. 批量回填必须写 recompute_log（版本、原因、影响行数、执行时刻）。没有 recompute_log 的批量 UPDATE 视为事故。

## 上线前必须成立
- 六个分区权重与 K=60 是拿四个锚点反解的，没有真人数据回归过。上线前拿 20 个人 14 天的数据跑一遍，四个锚点必须复现：久坐日 3.9 / 45 分钟 Z2 跑 11.4 / 间歇课 18.2 / 比赛日 20.8，容差 ±0.3。
- Tanaka 公式 208 − 0.7×age 对普通人群够用，但对训练有素的人会低估 HR_MAX，于是分区偏高、负荷偏大。V1 接受这个误差，但不许在任何文案里把分区说成「你的最大心率」。
- ACTIVE_FCST 需要 5 个有数据的日子。新用户前五天那条 IF YOU HIT BUDGET 整行不出现——09 屏的空态没画这一种。
- 每日方向的 ±150 是拍的。它直接决定热力图上绿点的密度——定窄了满屏花，定宽了满屏空。上线后按真实分布回看一次，目标是让典型用户一周里有 2–4 个非灰格。
- 10 板与 13 板的把握度词必须共用一个 token 集。本板定的是 PENDING / MEDIUM / HIGH，13 板现在写的是 HIGH / MEDIUM / LOW，差一个词——上线前统一，以本板为准。
- 埋点清单：`CALC_VERSION_BUMP{FROM,TO,SCOPE}` · `CALC_RECOMPUTE_EDIT{DATE}` · `CALC_MISMATCH{SYMBOL,APP,SERVER}` · `DAY_CLOSED{DATE,IN,OUT,DIRECTION}` · `METRIC_NULL{SYMBOL,REASON}` · `ANCHOR_REGRESSION{CASE,VALUE}`
- 验收线三条：CALC_MISMATCH 恒为 0（同一时刻 App 与服务端任一符号差 ≥ 1 就打点）；随机抽 100 个用户日，02 节里每一个非 null 的符号都能追到 inputs_hash；夏令时切换那两天不出现整批 DAY_CLOSED 缺失。第一条掉下来只有一种可能——有人在客户端偷偷算了第二遍。
