# Cal AI 逐屏拆解 × NextBody 改造计划

2026-09-20 · 素材来源：Mobbin（Cal AI iOS，60 个 surface，含 34 屏 onboarding 全流程）
对照物：本仓库 `app/NextBody` 当前 main。

---

## 0. 一句话结论

Cal AI 不是记录工具，是**一台承诺制造机，附赠一个拍照识别**。它的全部设计资源压在两个地方：
(1) 让用户在见到产品之前先投入 34 屏；(2) 让「记一餐」这件事永远不会失败、永远不需要用户填数字。

NextBody 的护城河（真实测量、词表纪律、AI 三步、BIA）Cal AI 永远拿不到。
但 NextBody 当前在这两件事上都明显更差，而这两件事恰好决定留存和付费。

---

## 1. Cal AI 逐屏拆解

### 1.1 冷启动（屏 1–2）

| 屏 | 功能 | UX 机制 |
|---|---|---|
| 1 Splash | 品牌 | 纯白 + 黑苹果字标，无进度条。 |
| 2 价值主张 | 入口 | 一台手机 mockup 播放「对着食物拍」；大标题 `Calorie tracking made easy`；主按钮 `Get Started`；次级 `Already have an account? Sign In`；右上角语言切换 🇺🇸 EN。**第一屏就给语言开关**，为全球投放服务。 |

### 1.2 Onboarding 34 屏：三类屏交替出牌

**A 类·标定题（9 屏）**：性别 / 每周运动次数 / 身高体重 / 生日 / 目标 / 目标体重 / 速度 / 障碍 / 归因。
副标题永远同一句 `This will be used to calibrate your custom plan.`——重复 9 次，把"你填的每一格都会变成一个专属计划"钉进脑子。

**B 类·信念屏（零输入，4 屏）**：
- `Cal AI creates long-term results`：两条曲线，"80% 用户半年后仍保持"
- `Gain twice as much weight with Cal AI vs on your own`：20% vs 2X 双柱
- `Gaining 6 kg is a realistic target. It's not hard at all!`（紧跟在用户刚拨完目标体重之后）
- `You have great potential to crush your goal`：3/7/30 天转变曲线

**位置是关键**：每一屏 B 类都紧跟在一次数字提交之后。输入即奖赏，一次都不让用户怀疑自己。

**C 类·索取屏**：归因（Instagram/TikTok/TV/朋友/Facebook/YouTube，顺手拿投放数据）、`Have you tried other calorie tracking apps?`（👎No / 👍Yes，为后面的对比叙事铺垫）、Apple Health、通知权限（画了个 👆 指着 Allow）、评分（4.8 / 100K ratings / 三张真人头像 / "我两个月瘦 15 磅，本来都要打 Ozempic 了"）、登录（Apple/Google，可 Skip）、邀请码（可跳过）。

**设置项写成问句（2 屏，最值得偷）**：
- `Add calories burned back to your daily goal?` 配小卡片：Today's Goal 500 Cals + Running +100 cals
- `Rollover extra calories to the next day?` 配两张卡：昨天 350/500 剩 150 → 今天 350/650 带 `150` 徽章
一屏同时完成三件事：教会机制、拿到配置、让用户觉得这个产品懂他。比藏进 Settings 强一百倍。

**制造一次等待（3 屏）**：
`Time to generate your custom plan!` → `18%` 进度条 + `Customizing health plan...` + 列出正在算的五项（Calories/Carbs/Protein/Fats/Health Score）→ `Congratulations your custom plan is ready!` + `You should gain: Gain 6 kg by October 13` + 四个可编辑圆环 + `You can edit this anytime` + `Let's get started!`

进度条是假的。但它把 30 屏输入**兑现**成四个数字，用户此刻认为"这是我的计划"。

**然后才是登录和付费墙**：`Save your progress`（Apple/Google/Skip）→ `Unlock CalAI to reach your goals faster` + 一张**已经填满数据的首页截图** + `✓ No Payment Due Now` + `Just $29.99 per year ($2.49/mo)`。
**付费墙在承诺的最高点，不是最低点。**

**全程工艺**：顶部细进度条；底部一颗 Continue 常驻；未答时 Continue 置灰；一屏一问；选项是整行圆角卡，选中变纯黑；标题 32pt 粗体，副标题 15pt 灰。

### 1.3 首页（3 页横向轮播）

| 元素 | 内容 |
|---|---|
| 顶栏 | 🍎 Cal AI 字标 + 右上角 🔥 streak 数 |
| 周条 | W/T/F/S/S/M/T + 日期；未记录日是虚线圈，今天是实心圈，可点切到历史日 |
| 页 1 | `2583` / `Calories left` + 火焰环；下面三张宏量卡 `184g Protein left` 各带小环 |
| 页 2 | `35g Fiber left` / `93g Sugar left` / `1344mg Sodium left` + **Health Score 6/10** 进度条 + 一句人话建议 |
| 页 3 | `0/10,000 Steps today` + `Calories burned` + Water `500 ml` 带 −/+ 和齿轮 |
| 页点 | 三个点，深度全藏在横滑里 |
| Recently uploaded | 餐卡流：照片缩略图 + 名字 + 时间 + 🔥大字卡路里 + 三个宏量 chip |
| 分析中态 | 灰糊缩略图 + `25%` 圆环 + `Analyzing food...` + 骨架条 + `We'll notify you when done!` |
| 提示条 | `You can switch apps or turn off your phone. We'll notify you when the analysis is done.` 带 × |
| 底栏 | Home / Progress / Settings + 一颗纯黑 **+** FAB |

口径全部是 **left**（还剩多少），不是 consumed。

### 1.4 记录闭环

| 屏 | 功能 | UX 机制 |
|---|---|---|
| 加号菜单 | 四格白卡浮起，背景变灰 | `Log exercise` / `Saved foods` / `Food Database` / `Scan food` |
| 相机 | 四个模式 chip：`Scan Food` / `Barcode` / `Food label` / `Library`；四角取景框；闪光灯；大快门；右上 `?` | 模式切换不离开相机 |
| 拍照教程 1/2/3 | ① `Capture the full meal`（整盘入框 / 别切边 / 光线好）② `Show every ingredient`（层叠食物摊开 / 揭盖）③ `Any doubt? Barcodes...`（条码和食品标签最准；scan 适合在餐厅不知道配料时） | 每屏一张示范图 + ✅ 绿标 + 三条要点 + `Next` / `Scan now`。**这三屏是 AI 准确率的最大杠杆，成本几乎为零。** |
| 文字记录 | `Log Food` 顶部四个 tab：All / My foods / My meals / Saved foods；搜索框 `Describe what you ate`；未输入时给 `Suggestions`（花生酱/牛油果/鸡蛋）；输入后 `Select from database` 列表每行带 `+`；底部 `✨ Generate results using AI`；还有 `Manual Add` / `🎙 Voice Log`；右上角条码按钮 | 数据库优先、AI 兜底 |
| 语音记录 | 波形点阵动画 + 实时转写文字（`Chocolate`）+ `Restart ↻` + 黑色 ✓ 确认 | |
| 记完回执 | 底部 toast：✅ `Food logged` + 黑色 `View` 按钮 + `Undo` | **Undo 就在 toast 上** |
| 结果页 | 顶部原图铺满；下半是白卡上滑：时间戳、`Tap to Name`（可改名）、书签收藏、`Measurement` 三段 `Serving/Package/G`、`Number of Servings` 带铅笔的步进框、Calories 大卡、三张宏量卡、页点（第 2 页是微量元素）、`Ingredients + Add`、`How did Cal AI do? 👎👍`、底部 `✨ Fix Issue` + 黑色 `Done` | |
| 食材增量 | 加一条 `Yogurt · 99 cal 100g` 后，Calories 从 `90` 变 `189` 并挂一枚黑色徽章 `+99`，三个宏量各挂 `+4 / +10 / +1` | **全产品最精致的一处**：让编辑有即时因果反馈 |
| Fix result | `✨ Fix result` + 文本框（`Fat is not properly described`）+ 灰底示例 `Example: The sandwich is missing the turkey and lettuce.` + `Update` | 用户不改数字，用户描述哪里不对，模型重算 |
| 溢出菜单 | `Report Food` / `Save Image` / `Delete Food`（红） | |
| Report Food | 弹窗文本域 + `0/500` 计数 + Cancel / Report | 把投诉收成训练数据 |
| Create Meal | `Tap to Name` + 卡路里/宏量卡 + `Meal Items` 空态 + `+ Add items to this meal` + 置灰 `Create Meal` | 组合餐 |
| My Foods 空态 | 罐头插画 + `Add a custom food to your personal list.` + 黑色 `Add food` | |
| 记运动 | `Log Exercise` 四行：`Run`（跑步慢跑冲刺）/ `Weight lifting`（器械自由重量）/ `Describe`（写文字）/ `Manual`（直接输入烧了多少卡） | 每行有副标题解释 |
| 力量训练 | `Set intensity` 竖向三档滑轨：High `Training to failure, breathing heavily` / Medium `Breaking a sweat, many reps` / Low `Not breaking a sweat`；`Duration` 四颗 chip 15/30/60/90 + 自定义数字框 | **用体感描述代替数值**，普通人能答 |

### 1.5 Progress 页

`My Weight 72 kg / Goal 78 kg` + 进度条 + `Next weigh-in: 7d` ｜ `Day Streak` 火焰卡 + 一周七点
四档 chip `90 Days / 6 Months / 1 Year / All time`
`Goal Progress` 折线 + 右上 `🏳 0% of goal` + 底部绿字鼓励句（`Getting started is the hardest part. You're ready for this!`）
周 chip `This week / Last week / 2 wks ago / 3 wks ago`
`Total Calories 1,298 cals` 按宏量堆叠柱
`Your BMI 22.8` + `Healthy` 徽章 + 四色带
有完整深色模式。

### 1.6 Daily Breakdown

`Calories 1,298/2,715` + 环；Protein 78/193g、Carbs 67/315g、Fats 73/75g；`Edit Daily Goals` 描边按钮
`Water 500/1,892 ml` + 蓝环
`Health score  Good  7/10` 绿环 + Fiber 3g🔴 / Net Carbs 64g🟢 / Sugar 17g🔴 / Sodium 1124mg🔴

### 1.7 Settings

用户卡（首字母头像 + 名字 + 年龄）
`Invite friends` + 一张情侣照片 banner + `Earn $10 for each friend referred`
`Personal details` / `Edit nutrition goals` / `Goals & current weight` / `Weight history` / `Language`
`Preferences`：Appearance（Light/Dark/Automatic 下拉）、`Live activity`（锁屏显示当日卡路里）、`Add burned calories`、`Rollover calories`（最多 200）、`Auto adjust macros`（改一个值其余按比例自动调）
`Widgets` 画廊：三种尺寸预览 + 右上 `How to add?`
`Terms and Conditions`

- **Personal Details**：`Goal Weight 78 kg` + 黑色 `Change Goal`；当前体重/身高/生日/性别/每日步数目标，每行带铅笔
- **Weight History**：纯列表 `73 kg — September 2, 2025`
- **Edit nutrition goals**：四个彩环对应四个输入框 + `View micronutrients ⌄` 展开纤维/糖/钠 + 底部 `✨ Auto Generate Goals`（手动改完能一键回到自动）

### 1.8 Widget / 锁屏

锁屏：`Today` + 四个小环（Calories left / Protein / Carbs / Fats）
主屏中号：环 + 三个宏量 + 右侧两颗快捷 `Scan Food` / `Barcode`
主屏小号：环 + 黑色 `+ Log your food` 药丸
主屏小号（提醒款）：🔥1 + `Remember to log!` + 一盘食物插画

---

## 2. NextBody 逐面对照

| # | NextBody surface | 现状 | Cal AI 对应 | 差距判决 |
|---|---|---|---|---|
| 1 | LaunchMark / 登录 / 配对 | 点阵开机动画，工艺极好 | Splash | **我方更强**，不动 |
| 2 | Onboarding 8 步 | consent→healthSync→confirm→goal→fingersOn→scanning→baseline→membership | 34 屏 | **最大缺口**：零信念投入，付费墙紧贴体测后 |
| 3 | Home 根页 1 | 点阵待机盘 BODY BATTERY 72% + HR/STRESS + `TAP OR TALK` | 一个数 `2583 Calories left` | 我方信息更硬；但"今天该干什么"没有单一答案 |
| 4 | strip 两张卡 | TRAINING 12.4 / CALORIES 1,240 of 1,900 · TO GO −660 + PRO/CARB/FAT 条 | 三张宏量卡 | **持平**，我方甚至更密 |
| 5 | Home 页 2 | vitals 仪器卡阵 | 页 2/3 微量 + 步数水 | **我方远强** |
| 6 | PLAN 建议面 | 上滑打开，当日建议 | Health Score 旁一句话 | 我方内容更强，但**藏得太深**，一级面一句解释都没有 |
| 7 | AI 面板 / dock | 语音 / 键盘 / 相机三键 | 无（Cal AI 没有对话） | **我方独有**，但全部 PRO 门后 |
| 8 | 加号菜单 | 拍餐 / 相册 / 运动 / 平衡检查 / 身体扫描 | 四格 | 结构持平；**缺常吃、缺条码、缺拍照教程** |
| 9 | FUEL 页 | DAY/WEEK/MONTH + EATEN TODAY + 660 LEFT — ABOUT ONE FULL DINNER + MACROS VS TARGET + 一句人话 + WHAT WENT IN 表 | Daily Breakdown | **我方更强**（那句 "PROTEIN IS THE ONE THAT MATTERS TONIGHT" 是 Cal AI 没有的） |
| 10 | 记一餐 plate | `LogMealSheet`：食物名 + **kcal 必填**，宏量留 `——` | 拍照，零输入 | **最大缺口**，见 W1 |
| 11 | 改一餐 plate | `EditMealSheet`：kcal/蛋白/碳水/脂肪**四个数字全必填**才能保存 | 份数步进器 / `Fix result` 写一句话 | **重大缺口**：这是数据录入表，不是纠错 |
| 12 | 训练页 | 日/周/月 0–21 负荷 | 无 | 我方独有 |
| 13 | 身体电量页 | 日/周/月 + 归因 | 无 | 我方独有 |
| 14 | vitals 七面 + 睡眠 | 包络、探点、分期线、分数 | 无 | 我方碾压 |
| 15 | 体成分 + 称重 | Profile 内，热力图 + FAT/LEAN/BODY FAT | Progress 页（体重 + BMI + 目标进度） | **结构缺口**：我方数据更好却没有"我在变吗"的独立答案面 |
| 16 | 测量清单 | 主动测量记录 | 无 | 我方独有 |
| 17 | 设备页 / 电量趋势 / 闹钟 | 完整 | 无 | 我方独有 |
| 18 | Chat + 历史 | 完整 | 无 | 我方独有 |
| 19 | ME / 设置 | ACCOUNT / PREFERENCES / DATA & LEGAL | Settings | **缺**：邀请好友、Widget 画廊 + 怎么加、目标可视化编辑 |
| 20 | 付费墙 / 管理 | `$6/mo`，RevenueCat，位置在体测后 | 位置在计划兑现后 + 已填满首页截图 + No Payment Due Now | 位置错 |
| 21 | 运动 / 实时 / 灵动岛 | 已有 ActivityKit | Live activity（只是卡路里） | **我方独有且更强** |
| 22 | Widget | TodayWidget / ShotWidget 已存在 | 画廊 + `How to add?` + 提醒款 | **隐形大漏斗**：CONTEXT 写死「只在主屏上放了小组件才排下一次后台拉取」，而 App 里没有任何一处教用户加 widget |
| 23 | 通知 | notification edge 体系（昨夜窗 / 低储量 / 用餐空档…） | 时钟式提醒 | **我方设计更高级**，保持 |
| 24 | 评分请求 | **完全没有** | onboarding 内 4.8 星 + 证言 | 缺 |
| 25 | 邀请 / 转介 | **完全没有** | $10 referral | 缺（卖硬件，价值更高） |
| 26 | Undo | **全 App 没有一处** | 记餐 toast 自带 | 缺 |

---

## 3. 代码审计：已经有的，和真正缺的

> 本节全部基于 2026-09-20 的 main 实读，不是推测。

### 3.1 我方已经有、而且做法比 Cal AI 更彻底的

| 机制 | 证据 |
|---|---|
| **食材分解** | `_shared/meal-estimate.ts` `MealItemSchema`（name/portion/kcal/p·c·f，≤12 项）；system prompt 明写「One visible food is one item. Do not collapse a mixed plate into one name.」；`commitEstimatedMeals` 把每一样食物写成**独立一条 meal**。Cal AI 是一餐一条 + 子行，我方粒度更细。 |
| **自动/乐观写入** | `estimateMeal` 返回 `requires_confirmation: false`；`turn/index.ts:483` 直接 `commitEstimatedMeals`；`foodDraftEnvelope` 注释：「A finished estimate is already on the record. The plate is a receipt, not a confirm.」面板卡的 `data.rows` 就是逐项列表。 |
| **Undo** | `Services/PhoneTools.swift` `pushUndo` / `undoStack` / `restore` op，create·update·delete 三条路径都压栈，返回体还带 `undo` 描述给模型。 |
| **自然语言改餐** | `writeMeal("update")` 支持部分字段更新（只给 name 就只改 name）。 |
| **0 不是估算失败的借口** | `meals.kcal check (kcal > 0)` + 注释「A 0 kcal meal does not exist: writing 0 means the parser failed」+ `writable = items.filter(kcal >= 1)`。Cal AI 会把 `greek` 记成 0，我方结构上拒绝。 |
| **语音 / 运动 / 步数 / 消耗** | 全局 ASR、手环实测、`log_sport_session` 补记。 |

**结论：Cal AI 的记录闭环里，最硬的三块（食材分解、自动写入、撤销）我方已经有了。**

### 3.2 真正的缺口（带代码位置）

| # | 缺口 | 证据 | 影响 |
|---|---|---|---|
| **G1** | **`portion` 被丢弃** | `MealItemSchema.portion` 模型已经估了（"1 bowl" / "200g"），但 `commitEstimatedMeals` 的 payload 里没有它，`meals` 表也没有这列 | 份量调整只能重打字。Cal AI 的份数步进器我方已经有一半，只是扔了 |
| **G2** | **照片不落库** | `AIImagePayload` 的 dataURL 进 turn 即消失；migrations 里 0 个 photo/image 列 | 餐卡无缩略图、无法回看复检、无法「这张图再看一次」 |
| **G3** | **手打路径与 AI 路径两套摩擦** | `Fuel/FuelSheet.swift:91` `canSave` 要求 `kcal > 0`；AI 路径零输入 | 同一个 App，拍照零输入，打字要自己算卡路里 |
| **G4** | **`EditMealSheet` 四个数字全必填** | `Fuel/FuelDetailView.swift:655` `canSave` 要 kcal+三宏都有值 | **UI 比自家工具还笨**：`writeMeal("update")` 本来支持部分更新 |
| **G5** | **Undo 没有 UI** | `pushUndo` 只在 `PhoneTools`；`DataStore.addManualMeal / amendMeal / deleteMeal` 不压栈 | 只有对 AI 说话能撤销，手动操作不能 |
| **G6** | **无微量**（纤维 / 糖 / 钠） | schema 与 `meals` 表都没有 | 钠和糖是真会改变行为的两项 |
| **G7** | **无常吃 / 收藏** | 无 saved 概念 | 记录成本不随时间下降 |
| **G8** | **估算未后台化** | turn 仍是同步 SSE | 30 s inter-byte 超时；切走即断 |
| **G9** | **没有「一餐」这个聚合对象** | 一次估算 → N 条独立 meal，彼此无关联 | 整餐调份量、整餐一张照片、整餐存成常吃 —— 三件事都没有落点 |

### 3.3 G9 是唯一需要产品决策的一条

Cal AI：一餐一条 + items 子行。我方：一样食物一条。

我方形态在「日档食物表不分餐」（CONTEXT 明确 `Avoid: 早餐/午餐/晚餐分组`）下是自洽的，删改粒度也更细。**不建议改形态**。

建议加一个轻量分组键：同一次估算的 N 条共享 `meal_group_id`，照片和 portion 挂在组上。表层照旧不分餐，但「这一次拍的这盘饭」可以被整体回看、整体调份量、整体存成常吃。

---

## 4. 落地（2026-09-20 已实现）

| 缺口 | 做法 | 落点 |
|---|---|---|
| **G1 portion 被丢弃** | `meals.portion` 新列；`commitEstimatedMeals` 停止丢弃；system prompt 要求每一项都给一句人话的量；编辑面四颗乘数 ×0.5/×1/×1.5/×2 同时缩放四个数和这句话，缩放不了的话就丢掉不留假量 | migration、`meal-estimate.ts`、`PortionMath.swift`(+5 测试)、`FuelDetailView` |
| **G2 照片不落库** | 私有桶 `meal-photos`（路径第一段是本人 id，RLS 直传直读）；turn 存图回写 `photo_path`；`MealPhotoStore` 本地缓存，手机把刚发的图按服务端给的路径记住，不再下载一次；缩略图进食物表、编辑面、回执、常吃 | migration、`turn/index.ts`、`MealPhotoStore.swift`、`FuelBoards` |
| **G3 两套摩擦** | LOG A MEAL 改成相机优先；KCAL 变可选覆盖（填了就按填的记，留空就走估算）；文字路径与拍照走同一条链 | `FuelSheet.swift` |
| **G4 四个数字全必填** | `amendMeal` 全字段可选，留空即保持；编辑面按部分更新保存，盘的组/照片/微量随替换行带过去 | `DataStore.swift`、`FuelDetailView` |
| **G5 Undo 没有 UI** | `DataStore.mealReceipt` + 八秒回执条（写了什么 / 还剩多少 / UNDO），首页 dock 上方与热量页各一处；撤销走同一条出站队列，改的撤销是再改一次 | `DataStore.swift`、`MealReceiptBar.swift` |
| **G6 无微量** | 纤维/糖/钠进 schema、表与估算；一天的合计全有全无，缺就写「几行不知道」；不做 x/10 总分 | migration、`meal-estimate.ts`、`MealMicroTotals.swift`(+4 测试) |
| **G7 无常吃** | `meal_favorites` 表 + `MealFavorites`；编辑面「存成常吃」（有组就存整盘）；LOG A MEAL 顶部一排 chip，点一下原样重放，不调模型 | migration、`MealFavorites.swift`、`MealQueue.createKnown` |
| **G8 估算未后台化** | 带图的一轮本来就不随连接中断；`intent: "meal"` 让 LOG A MEAL 发出的文字轮同样不中断。人走开服务端照样把这盘写完 | `turn/index.ts`、`AIService.turn` |
| **G9 没有「一盘」** | `meal_group_id`：一次估算的 N 行共享一组，照片和份量挂在组上；日档食物表仍然不分餐 | migration、`meal-estimate.ts` |
| A3 占位 | 已发出、还没有行的那一盘在食物表里占一行：照片 + 那句话 + `READING`。从不写数字，更不写 0 | `AIService.ReadingPlate`、`FuelBoards` |
| E1 下次体扫 | 体成分页新卡：距第一次扫描的体脂/瘦体重变化 + `NEXT SCAN` 倒计时（7 天，过期写 DUE，不计连续、不计失败） | `BodyScanCadence.swift`(+4 测试)、`CompositionDetailView` |
| F1 Widget 漏斗 | ME › WIDGETS › 怎么加：两张画出来的面 + 三步，并第一次说明「后台同步是为小组件跑的，没有小组件就不跑」 | `WidgetsSheet.swift`、`ProfileView` |
| C6 步数目标 | `Profile.stepGoal` 可编辑（1,000–60,000），保存即推给手环，三处硬编码的 8000 一并接上 | `DataStore.swift`、`ProfileSheets.swift` |

新增词表：盘 / 份量 / 微量三项 / 常吃 / 回执 / 读取中的盘（`CONTEXT.md`）。

验证：948 个 Swift 包测试、452 个 Edge 测试、7 条新 pgTAP（含「别人的照片路径被拒」与「新列和营养数一样不可改」）、iOS 构建通过。迁移在一次性容器里从头逐条应用干净。

### 没做的，和为什么

- **手动改 TARGET / 一键恢复自动**：Cal AI 需要它是因为它的数字是人手填的。这里的 TARGET 是静息 + 实测活动 + 建档偏移（ADR 0025），热量页已经把这行算式印出来了。加一个自由偏移等于给同一个数第二个来源——要做的话先改 ADR，不是先改界面。
- **rollover（没吃完的额度滚到明天）**：不抄。它服务的心理功能用「本周至此 DIFF」如实给了。
- **「分析完通知你」**：APNs 未配置（词表已写明）。人走开时服务端照样写完，回来就在表里——没有假装能推送。
- **邀请好友 $10**：需要真实的转介与发放机制，凭空印一个金额就是编。
- **锁屏实时开关**：iOS 自己就有每个 App 的 Live Activity 开关，不在产品里再立一个。
