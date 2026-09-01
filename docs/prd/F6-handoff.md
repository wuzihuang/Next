# F6 · 交付规则 Handoff — 交出去之前，先把没定的事标出来

这块板的读者是代码代理，不是设计师。这块板只干四件事：定死四种文字的效力顺序；把屏上画错、代理会照着实现的像素逐条点名；给每个点了通向空气的控件一个处置；再给一层没有手环也能构建和自测的 mock 与种子数据。

## NOT IN V1
- Android 工程目录，以及任何 Platform.OS === 'android' 分支
- 付费墙、订阅、任何计费代码路径（D04：卖表本身就是商业化）
- 睡眠分期与睡眠时长的任何渲染，含 07 板的 hypnogram / split / o2night 三个 widget
- WEEK / MONTH 两段视图，以及 08、09 两页顶上的分段控件本身
- 代理自造的屏：运动中屏、连不上排障页、成分 WEEK 空态
- 中文界面。英文屏先上，中文的字宽要单独走一遍版式

## Sec 01 · PRECEDENCE 板上有四种文字，只有两种是需求
- ① **屏 = 版式的事实源**：屏决定有哪些块、块在哪、块多大、字多大。屏上的数字不是事实源——它是设计师为了让版式看起来像真的而填的样本。凡是屏上的数与 caption 或右列打架，屏输。
- ② **caption = 行为的事实源**：每一屏底下那段中文说的是「按下去会怎样、拿不到数据画什么、为什么不是另一种做法」。行为只从这里读。caption 与屏冲突时 caption 赢，因为屏画不出时间和失败。
- ③ **右列「上线前必须成立」= 尚未决定，一行都不实现**：右列每一条前面都有一个 ！号。它是问题，不是需求。代理遇到 ！号只能做两件事：跳过，或者回来问。不许实现，不许「先按最合理的那种做」，也不许把它排进 backlog 当成迟早要做的事。
- ④ **⚠️ 标记的句子 = 必须照它写的做**：嵌在正文里，标的是「照屏做会踩坑」。它比屏优先，也比同一段的其他句子优先。全文的 ⚠️ 加起来是这份文件里最硬的部分——它们全都来自 SDK 事实或平台事实，不是口味。
- **冲突时序号小的赢**：④ > ② > ① > ③

## Sec 02 · KNOWN WRONG PIXELS 屏上写着，但不许照做
交付前全仓搜这十五个值，一个都不许留（96% · Z5 4 MIN · ~500 · 0.69 · 1,860 · 2,280 这类硬编码值）。

| BOARD · SCREEN | 屏上是什么 | 为什么错 | 改成什么 |
|---|---|---|---|
| 02 · 03 屏 FOUND | 设备卡右边 96% | 电量要连上之后 batteryData 才有；rssi 只在扫描期出现，连上后 SDK 再也读不到 | 改成 rssi 分档的三格信号，或整块只留 NEXTBODY HOOP / READY TO PAIR。二选一，不许保留任何百分比 |
| 02 · EDGE 3 | PERMISSION NEEDED · Android asks for location… | D07：V1 不做 Android。这张卡只为安卓存在 | V1 不渲染。R07 里「蓝牙与定位权限也在这一下里申请」删掉「与定位」 |
| 06 · 结果面板 | 72 RECOVERY SCORE | D02 已改名，且它不是 SDK 字段 | BODY BATTERY 0–100，名字走可换 token（Garmin 商标风险） |
| 08 · 分区时长 | Z5 4 MIN | 原始点五分钟一个，任何分区时长只能是 5 的倍数 | 5 MIN 或 0 MIN。向下取整，整页所有时长同理 |
| 08 · 为什么是 14.5 | 86% 恢复落在满环的 69% | 恢复档位到目标的映射曲线原来没人拍板——F2 已给出九档 BB→TARGET_LOAD 表 | 从 F2 的档位表查，0.69 这个系数不许出现在代码里 |
| 09 · 空态 BREAKFAST | ~500 | 与有数态的 660 用了两套算法 | 一条式子两屏共用：剩余额度 ÷ 剩余未记录餐位，取整到 50。空态 = 1,900 ÷ 4 → ~450 |
| 09 · THIS WEEK | 今天 (SUN) 涂成落窗亮柠檬绿 | 今天还没过完，拿预估值上色等于提前发奖 | 今天那一根半高虚线，落窗判定等当天 CONFIRMED |
| 09 · 空态双高光 | MARK AS FASTED 与 LOG A MEAL 同时柠檬绿 | 违反一屏一个高光 | MARK AS FASTED 降成白 55% 的文字链，柠檬绿只留给 LOG A MEAL |
| 09 · ENERGY BALANCE | −620 NOW 用 OUT 1,860；−380 EST 用 2,280 | 同一条轴上两个点用了两个基数 | OUT 口径见 F2 的口径表，先定死再画。这两个数一个都不许照抄进代码 |
| 09 · 三处未知写法 | EATEN TODAY 用两道 ——，OUT / BALANCE 用一道 – | 同一件事三种写法 | 统一两道 ——。只有 14px 以下的行内值（—/145、— G PRO）退回一道 |
| 09 · FOOD 卡 | 380 / 610 / 250，Doto 粗体精确到个位 | 估算值用了实测的排版，跟 OUT 那一列长得一样 | 卡头认领一次 ESTIMATED，或全部按 10 kcal 取整。二选一 |
| 12 · FIRMWARE | Better sleep staging · about 4 min | D01：睡眠不上屏。更新说明里出现「分期」等于承诺了一个不做的功能 | 换一句不提睡眠分期的更新说明 |
| 12 · 电量卡 | About 3 days of charge left | SDK 只给 percent / level / chargeState，天数是我们推的 | 没有实测耗电曲线之前整句不渲染 |
| 12S · Forget sheet | 12 weeks of nights and every reading | 保留期是编的，而且又提了 nights | 保留期先定数，文案改成不点名睡眠的说法 |
| 07 · widget 全表 | hypnogram / split / o2night 三个 type，以及模板页 12 · sleep 整块 | D01：睡眠只在早上给一句，不展示分期不展示时长 | 三个 type 从 27 里摘掉或封存，sleep 那块模板不实现。⚠️ 摘掉就要同步改 F4 的 CI 门禁 1（27 这个数） |

## Sec 03 · DEAD CONTROLS 六个点了通向空气的东西
| CONTROL | BOARD | VERDICT | WHY |
|---|---|---|---|
| DAY / WEEK / MONTH 分段 | 08 训练详情 | **整个控件删掉** | 两段屏都不存在。08 板自己写过「留一个死控件比没有更糟」。删掉之后顶栏只剩 TODAY，返回仍然回首页——本来就没有历史栈 |
| START A SESSION | 08 训练详情 | 保留、照常可点，落地形态只允许一种：回首页 + 首页顶上出现一条 SESSION RUNNING / 计时 | 置灰是错的——空态里它是唯一的出口，关掉等于留一屏没有动作的解释文字。但运动中屏不存在，所以不许新建整屏 |
| DAY / WEEK / MONTH 分段 | 09 燃料详情 | **整个控件删掉** | 09 板右列已给过这条裁决：WEEK 的诉求由页尾 THIS WEEK 卡承担，MONTH 在只有七天数据时没有内容 |
| Alarms 二级页 | 12 设备 | **不是缺口，已经画完** | 12S 板第 2 张 sheet 就是它，而且它是盖在本页上的底部 sheet，不是二级页 |
| Automatic measurement 二级页 | 12 设备 | **不是缺口，已经画完** | 12S 板第 1 张 sheet。⚠️ sheet 里 isSlotModify=false 那一行整个不渲染，不做只读灰条 |
| Why won't it connect? | 12 设备 · 断联态 | **这一行删掉** | 排障那三条（蓝牙、距离、没电）在 02 板的三张异常卡上已经写全，再做一页是第二份实现。断联态的 CONNECTION 组只剩 Forget this HOOP；重连失败的原因直接印在 RECONNECT 按钮下面那一行 |

## Sec 04 · SCREEN INVENTORY 哪些能实现，哪些不能自己补
状态写「完全没有」的十一处，代码里只允许两种形态——控件不存在，或者控件存在但按 03 节的裁决处理。

| BOARD | SCREEN | STATE | IN V1 |
|---|---|---|---|
| 01 登录注册 | 欢迎 / 邮箱 / 验证码 三屏 | 已画真屏 | **做** |
| 02 CONNECT | 01 开机 · 02 搜索 · 03 找到 · 04 配对 · 05 连上 | 已画真屏 | 做（03 屏的 96% 按 02 节改） |
| 02 CONNECT | EDGE 1 空态 · 2 蓝牙关 · 4 连接失败 · 5 被占用 | 已画真屏 | **做** |
| 02 CONNECT | EDGE 3 定位权限 | 已画真屏 | 不做（D07，V1 不渲染） |
| 03 ONBOARDING | 六屏 + 三张编辑 sheet。⚠️ F5 C3 要求在 HealthKit 弹窗前插一屏 WHAT HOOP COLLECTS，六屏变七屏 | 已画真屏 + 一屏待补 | 做；同意屏要补 · 代理不许自己画 |
| 04 主页首屏 | 默认 / Day One / 训练环 / 燃料卡 / 下屏尺寸 五屏 | 已画真屏 | **做** |
| 05 DOCK | 打字 / 说话 / 照片 三条轨道 + 五张异常碎片 | 已画真屏 | **做** |
| 06 加号与测量 | 加号单子 6 屏 · BATTERY CHECK 5 屏 · 读数与结果 6 屏 · 体成分 3 屏 | 已画真屏 | **做** |
| 07 AI 屏 | 面板全量模板 · 27 widget · data 全表 · 八个槽位 | 已画真屏 + 契约 | 做（睡眠三个 type 除外） |
| 08 训练详情 | DAY 满态整页 390×1880 · 空态整页 390×1199 | 已画真屏 | **做** |
| 08 训练详情 | WEEK / MONTH 两段 · 运动中屏 · 点开单条来源的二级详情 | 完全没有（运动中只有一张 SPEC ONLY 碎片） | 不做 · 分段控件删掉；运动中按 03 节的落地形态；来源行 V1 不可点 |
| 09 燃料详情 | 有数态 6 卡 / 空态 6 卡 两整页 | 已画真屏 | **做** |
| 09 燃料详情 | NO TARGET（未建档 / 无体重）整屏 | 只有异常碎片 4，没有整屏 | 要补 · 新用户第一次进这一页看到的就是它。⚠️ 补屏之前先拍板，代理不许自己画 |
| 09 燃料详情 | 改一笔 / 删一笔的入口 | 完全没有 | 要补 · FOOD 卡每行可点 + 删除加 5 秒撤销。规格已在右列与 F3，屏没画 |
| 10 成分详情 | DAY 满态 / 空态 两整页；WEEK 空态完全没有 | 已画真屏 | 做；WEEK 空态不做——第一周没有「上周」可比，先用 NO CALL 顶住 |
| 10S 称重录入 | Add a weigh-in 底部 sheet（D06: Apple Health 或手动记一笔） | 完全没有 | 要补 · 待画。10 板那条「NOT IN V1 手动录入体重」已被 D06 作废 |
| 11 我的 | 一整页 + 五张 sheet。⚠️ F5 要求法务组从四行变六行 | 已画真屏 | 做（两行新增要跟版式确认一次） |
| 12 / 12S 设备 | 连接态 1,646px / 断联态 1,757px + 四张 sheet；Why won't it connect? 完全没有 | 已画真屏 | 做；那一行删掉 |
| 13 昨夜 | 早上那一屏 + 通知前置说明屏 + Body Battery 面板 | 已画真屏（本轮新增） | **做** |
| 01M / 02M / 05M / 06M | 四块动效板 | 已画真屏 + 时序 | 做 · 02M 的爆点与 01M 开屏必须是同一份实现 |

## Sec 05 · CROSS-BOARD CONFLICTS 板与板互相打架的七处
| SUBJECT | ONE BOARD SAYS | THE OTHER SAYS | THE CALL |
|---|---|---|---|
| 骨架屏 | 08 板 R09：「200ms 内没数据先出骨架」 | 04 板 R09 / 06 板 R04 / 全局法律：禁用 spinner、骨架屏、占位数、假进度 | 全局法律赢。08 板 R09 那半句删掉，没数据就画 —— |
| unsupported 的行 | 06 板 R03：「行照常渲染但降到 32%、去掉时长、行内写原因」 | 12 板碎片 2 / 全局法律：整行不渲染 | 整行不渲染。06 板 R03 改。加号单子少一行，好过让人惦记一件这台机器做不到的事 |
| 一天从几点开始 (D10) | 09 板 R08：App 侧按 04:00 切，凌晨那餐算前一天 | 08 板 R03 / 10 板 R08：设备本地日，dayOffset 按 00:00 切 | 按 F0 D10 与 F2 的裁决：全产品只有一种日历 —— 用户日 = 本地 04:00 → 次日 04:00。dayOffset 降级成 SDK 的分页参数，永不出现在 UI、结算与表键里；服务端按时间戳重切。08 / 09 / 10 三处 R0x 全部改成引用 F2。FOOD 卡上 01:20 那一行照常显示在当天最早的位置，「+1」标记删掉 |
| 手环体成分接不接 (D09) | 10 板右列：「要不要接进这一页，没定」 | D09: SDK 能算，需电极接触、需先 syncPersonalInfo，onboarding 那次 30 秒扫描是真的 | 接。手环 BIA 是一个真实的 MEASURED 源。10 板右列那条待决作废 |
| 体重从哪来 (D06) | 10 板通篇写「秤」，11 板热力图也按秤的读数归日 | D06: Apple Health 自动读，或者用户手动记一笔 | 改成这两个源。V1 里没有秤这个设备，任何屏上不许出现它 |
| OTA 结果几态 | 12 板 R08：「三态：completed / failed / versionUnverified」 | SDK: FirmwareUpdateOutcome 是四态 success / noUpdate / versionUnverified / failed；completed 属于 FirmwareUpdateStage | 按 SDK 写。两套枚举不许混用。noUpdate 不是失败，UI 上说「已经是最新」，而且它不该进失败率 |
| Android (D07) | 02 板右列拿安卓低端机校准超时；06 板 R08 说实体返回键；12 板 R03 说按两端交集取区间 | D07：V1 不做 Android | 阈值只用 iOS 真机校准；实体返回键那句不实现；区间仍按交集取（换机型也不会更宽），但文案与说明里不再出现 Android |

## Sec 06 · SDK MOCK 没有手环，六成的活干不了
这个 App 六成的界面在没有手环的时候根本不进入任何一个有意义的状态——加号单子全是不可用、训练环永远是 0.0、设备页全是 ——。mock 层是让代理能真的跑起来的前提，不是锦上添花。写法上只有一条硬规矩：它必须实现和真实模块字节一致的签名，从同一个注入口进来。做成两套接口、或者在业务代码里加 mock 分支，等于把技术债提前存进去。

```ts
// 注入口：唯一一个。App 侧只认这个接口，不认真实模块。
// packages/hoop-sdk/index.ts
export function provideHBand(impl: HBandModule): void

// 真机:      provideHBand(NativeHBand)
// 开发与测试: provideHBand(createMockHBand(scenario))
//
// ⚠️ 源码里不许出现被注释掉的 SDK 调用，
//    也不许 if (__DEV__) 返回假数据。
//    mock 只能从这一个口进来，否则真机到货那天找不回来。

createMockHBand({
  capabilities: Partial<DeviceFunctions>,   // 开关 1
  measure:      MeasureScript,              // 开关 2
  link:         LinkScript,                 // 开关 3
  busy:         BusyPolicy,                 // 开关 4
  battery:      { isPercent: boolean },     // 开关 5
  ota:          OtaScript,                  // 开关 6
  clamp:        Record<SettingKey, Clamp>,  // 开关 7
  clock:        () => Date   // 设备本地日由它决定，不是手机时区
})
```
- **开关 1 · 能力表**：readDeviceFunctions() 可逐字段设成 supported / unsupported / unknown。必备三档预设：FULL、NO-BIA (bodyComponent unsupported)、UNKNOWN（整表读不回来）。UNKNOWN 下所有测量入口按不可用渲染。
- **开关 2 · 测量状态机**：按脚本推 TestState: idle → start → testing → over。可插入 notWear、手指离开后回 testing（3 秒宽限）、deviceBusy、error。progress 是 0–100 不是秒——mock 必须把 progress 和本地时钟解耦，才能验出「以本地时钟收尾」这条。
- **开关 3 · 断连**：在任意毫秒切断，可选是否补发 disconnected 事件（真机上常常不补）。断连后 readOriginData 必须继续返回最后一次同步的数据，不返回空——这是 08 板碎片 1「陈旧不是空」的唯一验证路径。
- **开关 4 · DEVICE_BUSY**：同类型二次 start 直接抛 DEVICE_BUSY；测量中写设置也抛。可配「排队后多久放行」，用来验 12 板碎片 4 的开关弹回与排队文案。
- **开关 5 · isPercent = false 的固件**：batteryData 只给 level 0–4，percent 缺席。这一档下电量环должен匹配四格、「About 3 days」整句不渲染。⚠️ mock 必须真的不返回 percent，而不是返回 0——返回 0 验不出这条。
- **开关 6 · OTA 四条路**：outcome = success / noUpdate / versionUnverified / failed，四条都要能单独触发，stage 逐段可停。blockedReason 五种（notConnected / notVerified / lowBattery / busy / unsupported）各自能触发一次，用来验「置灰理由来自字段而不是前端判断」。
- **开关 7 · 写设置被固件夹变**：writeDeviceSetting 返回的值可以跟传入的不一样。预设：sedentary 传 60 回 45、heartRateAlarm 传 45 回 50。UI 必须拿回读值重渲染并说明被改了——这是这一页最难查的那种 bug，没有这个开关就永远查不出来。

## Sec 07 · SEED SETS 八组固定数据，对着异常碎片长
八组的挑法不是「覆盖率」，是「每一组正好对着一张已经画出来的异常碎片」。这八组要跟 mock 层一起进仓库，`yarn seed <SET>` 一句话切过去。

| SET | WHAT IT IS | RULE IT PROVES |
|---|---|---|
| D1-FRESH | 刚建完档，零同步、零记录、无目标。能力表 FULL | 04 板 Day One 卡、08 板空态整页、09 板空态整页、10 板 NO CALL。验「0.0 是断言，—— 是沉默」：全屏不许出现一个孤零零的 0 |
| D7-FULL | 连续七天满数据。今天 12.4 / 目标 14.5 / 已记三餐 1,240 / 七天有测量 | 08 满态、09 有数态、10 出 RECOMP + HIGH。验「来源之和严格等于环上的数」与「两张卡的加数必须对得上」 |
| D7-PARTIAL | 同上，但今天只记了两餐、没封口 | 09 板碎片 1：卡上照常给 990，能量差仍然是 ——。验「PARTIAL 不投票也不算反对票」，10 板的把握度只降档不翻面 |
| D7-FASTED | 第 3、5 天 confirmed 摄入低于 BMR×0.5 | 04 板 R05：断食日进账本不进趋势，周条独立色。验「饿一天 → 系统夸你 RECOMP」这个闭环没有被我们自己奖励出来 |
| NO-TARGET | 有手环数据，但档案里没有体重 | 09 板碎片 4：连分母都没有，宏量三条整段不渲染。08 板 R06：TARGET 与 OPTIMAL ZONE 一起显示 ——，环不画目标刻线，不许出现「差 2.1」这种句子 |
| STALE-2H | 最后一次成功 readOriginData 在 09:12，之后断连 | 08 板碎片 1、12 板断联态整页。验判定用的是最后同步时刻而不是连接状态——连着但没同步也算陈旧 |
| CAP-MINIMAL | 能力表里 bodyComponent 与 ecgFunction 都是 unsupported | 全局法律：整行不渲染。加号单子只剩两行，12 板设置组少一行，03 板 BASELINE 段整段跳过直接进主页 |
| BACKFILL | 回看三天前那一天，当天补记一餐 | 09 板碎片 5：EST 空心点、OPEN 餐位、建议值全部消失，CTA 换成 ADD TO THAT DAY。10 板 R09：判定变化要有可见回执并写清是哪条信号变了 |

## Sec 09 · DEFINITION OF DONE 每块板交付时对着勾
- **01 屏与版式**：每一张真屏都实现了，尺寸与 Paper 一致（390 宽，整页高度按板上标的那个数）。屏清单里标「完全没有」的，代码里对应位置是 03 节给的形态，不是自造屏。
- **02 caption 里的行为**：每一段 caption 里说的行为都能演出来：按下去去哪、拿不到数据画什么、失败之后版式动没动。演不出来的，说明这一屏还没做完，不是 caption 写得不清楚。
- **03 ⚠️ 逐条销账**：这块板里所有带 ⚠️ 的句子，一条一条在代码里指得到位置。指不到的写在交付说明里，别默默跳过。
- **04 右列一条没做**：右列的 ！号条目在代码里找不到任何实现痕迹——包括「先搭个架子等以后填」。有疑问的列成问题清单交回来。
- **05 错误像素已改**：02 节里属于这块板的那几行，全仓 grep 不到那些值。改成什么，交付说明里写一句。
- **06 八组种子数据跑得动**：凡是这块板会被触发的，逐组截图，与板上对应的异常碎片比对，版式零位移、只有颜色和那两行字变了。
- **07 降级路径不弹窗**：每一条失败路径都在当前屏原地降级。Alert / Toast / ErrorBoundary 兜底页 / navigation.reset() 四个 API 在这块板的代码范围内一次都没出现（lint 规则拦住最好）。
- **08 一屏一个高光**：每一屏渲染后，--lime-1 作为填充色出现的次数 ≤ 1。写成快照测试，别靠眼睛看。
- **09 组件是复用的**：08 节点名的七个组件，用到哪几个就 import 哪几个，仓库里没有第二份实现。
- **10 埋点先于上线**：埋点事件名照写，一个不少、属性名一个不改——埋点没上就发版，这块板的验收线就永远读不出来。

## Sec 08 · TOKENS & SHARED COMPONENTS 不点名，代理会画三个不一样的环
| NAME | APPEARS ON | MUST BE ONE | TRAP |
|---|---|---|---|
| `theme.ts` | 全产品 | 从 Paper 的 token 表整表导出，一个不漏也一个不加：--carbon 系 7、--lime 系 6、--ember 系 5、--text 系 4、三个字体、--fs-* / --w-* / --ls-* / --lh-* / --sp-1..17 / --r-* | 组件里不许出现字面色值与字面 px。--lime-1 只给高光，--ember-1 只给「需要你这边动手」与待决，--state-alert-2 只给真 ALERT |
| `<LoadRing>` | 首页训练卡 174×136 · 训练详情整页 · 训练空态 | 一份实现，量程写死 0–21 | 三处直径不一样，但量程、起始角、缺口、目标点画在环外这四件事必须一样。屏上目标从来不画进环里——画进去人会以为自己到了 |
| `<WeekBar7>` | 成分 THAT WEEK · 燃料 THIS WEEK · 训练 THIS WEEK · 我的一年热力图（同一套格子逻辑） | 一份实现，七格 + 今天半高虚线 + 缺失画空槽 | 缺的日子必须画空槽，不画 0，也不进 7 日均值。今天永远上不了落窗色。热力图的灰有两档——NO WEIGH-IN 与 MEASURED, NO CHANGE——不能同色 |
| `<MacroBar>×3` | 燃料有数态 · 空态 · AI 面板 fuel widget | 一份实现，三条永远独立 | 任何状态下都不合并成一条总进度条。空态的分子空着、分母先到（—/145），这是「还没答案」和「坏掉」的分界线 |
| `<DotCapsule>` | 全产品的 Doto 状态胶囊：READY TO PAIR · MEASURING NOW · DEVICE BUSY · NOT CLOSED · NO TARGET YET | 一份实现，颜色由状态枚举决定 | 颜色不许由调用处传。传得进来就一定会有人传错，然后琥珀出现在一个不需要用户动手的地方 |
| `<SettingRow>` | 我的十四行（F5 后十六行）· 设备七组 · 12S 四张 sheet 里的行 | 一份实现：label + 副文案 + 右侧值 + 可选 chevron | 右侧值不许留空——没有值可显示的行放版本号或更新日期。图标与右侧值用固定宽度的槽 (flexShrink: 0)，不靠 gap 对齐，否则跨行对不齐 |
| `<Sheet>` | 全产品所有二级内容。除了「设备」，没有第二个页面 | 一份实现，高度按内容自适应、最高不超过屏高 78% | 提交语义按内容定死：单选类点完关不给 Save；表单类必须显式 Save；开关类即时生效。同一类出现两种做法就是 bug |
| `<Panel358×470>` | 首页显示屏面板，AI 的唯一出口 | 一份渲染器：八个槽位 (title / tag / hero / sub / chart / sentence / facts / action) + 27 个 widget type | 槽位撞在一起时后面的赢，渲染器不重排——所以 layout 覆盖要在构建期校验。⚠️ agent 不该写 theme：让模型自由挑颜色，这块屏很快会变成调色板 |

## 硬规则
01. 效力顺序写死，冲突时序号小的赢：④ ⚠️ 标记的句子 > ② caption > ① 屏 > ③ 右列。这四句要进代理的系统提示，不能指望它每次自己读出来。
02. 右列每一条前面都有一个 ！号。遇到 ！号只有两个合法动作：跳过，或回来问。不许实现、不许搭架子、不许「先按最合理的那种做」。全文七十多条，一条都不例外。
03. 02 节列的十五处错误像素，交付前全仓 grep 一遍：96% · Z5 4 MIN · ~500 · 0.69 · 1,860 · 2,280 这类硬编码值，源码里一个都不许留。
04. 屏清单里状态为「完全没有」的那些处，代码里只允许两种形态：控件不存在，或控件存在但按 03 节的裁决处理。出现第三种形态即为交付不合格。
05. SDK 一律走 mock 层的同一套签名，从 provideHBand() 一个口注入。源码里不许出现被注释掉的 SDK 调用，不许 if (__DEV__) 返回假数据，不许业务代码里有 mock 分支。
06. 八组种子数据是构建产物的一部分：`yarn seed <SET>` 必须能把 App 切到那一组，不连手环、不改一行业务代码。改不动的那一组说明业务层把数据源写死了，回去改业务层。
07. theme.ts 从 Paper 的 token 表整表导出，一个不漏也一个不加。组件里不许出现字面色值；间距、圆角、字号一律走 --sp-* / --r-* / --fs-*。次要文字用 --text-3-prod，不用 --text-3 (F5 C10)。
08. 08 节点名的七个跨板组件，仓库里各只允许一份实现。第二次需要它的时候是 import，不是新建一个文件。
09. 一屏一个高光要能被机器检查：任意一屏渲染后，--lime-1 作为填充色出现的次数 ≤ 1。写成快照测试，别靠眼睛。
10. 所有失败在当前屏原地降级。Alert、Toast、ErrorBoundary 兜底页、navigation.reset() 四个 API 在 lint 规则里禁掉，要用得逐处豁免并写明理由。
11. V1 只做 iOS：不建 android/ 目录，不写 Platform.OS === 'android' 分支。SDK 契约里的两端差异照读（它决定接口形状），但只实现 iOS 那一支。

## 上线前必须成立
- 右列那七十多条谁拍板、什么时候拍，现在没有排期。建议一张表，一条一行，状态只有三种：未决 / 已决 / 已进板。
- mock 层的行为口径是我们编的，不是量的。TestState 各态的真实停留时长、DEVICE_BUSY 的真实触发窗口、写设置被夹过的真实边界，都得等真机回来校准一次。校准之前，mock 上跑绿的测试只证明代码自洽，不证明它在 KR96 上能跑。
- theme.ts 导出之后，Paper 与代码谁是 token 的主人？建议 Paper 是主、代码是生成产物，改 token 走一次导出脚本而不是手改——但这需要有人真的去写那个脚本。
- Body Battery 是 Garmin 注册商标（D02 / F5）。指标名 token 叫什么、放 i18n 还是 theme 层、备选 RESERVE / CHARGE / CAPACITY 选哪一个，三件事都没定。改名当天必须一处改全产品变。
- D08 的北美合规清单在是 F5 板，但它自己右列还挂着八条待决（DPA 算不算 share、商标检索、三份文档、审计日志）。导出与删号这两条链路，等 F5 右列清空再实现——F5 08 节的表清单本身还依赖 F3 生成。
- 埋点名各板不统一：PAIR_STEP_DONE{STEP,MS} 与 STRAIN_OPEN{ENTRY} 的属性命名风格不一样，也没有一组公共字段（用户、设备、算法版本、平台）。上线前要有一份事件字典，否则九条漏斗接不起来，验收线就都是空的。⚠️ STRAIN_ 这个前缀本身要跟 D02 改名一起扫。
- 完成定义第 6 条要求真机截图与 Paper 屏比对零位移，可现在没人有 KR96。这一条什么时候能执行，取决于样机什么时候到——它是整个交付计划里唯一一个我们控制不了的日期，也是唯一一个不能靠 mock 绕过去的关口。
- 埋点：`HANDOFF_STUB_HIT{BOARD,SCREEN}` · `MOCK_MODE_ACTIVE{BUILD,SET}` · `SCREEN_RENDER_REJECT{REASON}` · `PAIR_FAIL{REASON,STEP}` · `STRAIN_DEGRADED{REASON}` · `FUEL_STATE{UNLOGGED,PARTIAL,FASTED,CONFIRMED}` · `FASTED_SOURCE{ASK,MEAL_SKIP,DAY_MARK,WINDOW}` · `DEV_SETTING_WRITE{KEY,OK,CLAMPED}` · `COMP_CALL_CHANGED{FROM,TO,REASON}`
- 验收线三条：一，全仓 grep 不到 02 节列出的十五个错误值，一个都没有；二，八组种子数据在 mock 层上跑得动，每组截图与对应板的异常碎片比对，版式零位移；三，屏清单里标「完全没有」的十一处，代码里是显式的「不存在」或 03 节给的形态，grep 不到任何自造屏。
