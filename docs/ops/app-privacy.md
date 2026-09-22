# App Store Connect App Privacy 填写草稿

核验日期：2026-09-22。依据当前 Release 路径代码与 Apple、RevenueCat 官方说明；这是供 ASC 界面填写的草稿，**未在 ASC 保存或发布**。不把不明确的 CLI 枚举伪装成可直接导入的 JSON。上线包行为改变时须同步更新。

## 总体回答

- 是否收集数据：**是**，包括 Supabase、AI 服务、RevenueCat 和反馈服务处理的数据。
- 下表确定收集的类型均选择 **与用户身份关联：是**：记录使用账号 UUID，无法按匿名数据申报。
- 跟踪：当前代码未发现跨公司广告定向、广告归因、数据经纪商或 IDFA 使用，草稿均为 **否**。上线前仍需核实 RevenueCat 控制台外部集成，没有代码并不能证明控制台未配置集成。
- 不选择第三方广告、开发者广告/营销、其他用途；目的按各行填写。

## 可逐项填写的分类

| ASC 数据类型 | 用途 | 实际数据与代码依据 |
|---|---|---|
| Contact Info → Name / 姓名 | App Functionality | Apple 登录姓名、可编辑显示名；`Services/AuditTrails.swift` 的 `saveDisplayName`、`saveProfile`，`profiles.display_name`。 |
| Contact Info → Email Address / 电子邮件地址 | App Functionality | 邮箱 OTP、Apple/Google 身份及账号邮箱；`Services/Supabase.swift` 的 `requestCode`、`verifyCode`、会话邮箱。审核联系人邮箱不属于这项的判断依据。 |
| Health & Fitness → Health / 健康 | App Functionality、Product Personalization、Analytics | 心率、HRV、血氧、睡眠、体重、体成分、能量/恢复分数、营养与健康目标；`raw_samples`、`sleep_nights`、`body_composition`、`weigh_ins`、`daily_results`、`meals`。HealthKit 读取的身高体重等会进入账号数据，不能称仅设备处理。`MorningWidget.markShown` 与 `BodyBatteryDetailView` 还将分数放入分析事件。 |
| Health & Fitness → Fitness / 健身 | App Functionality、Product Personalization、Analytics | 步数、距离、运动时段、训练量、消耗与运动模式；`raw_samples`、`daily_training`、运动会话。`Features/Sport/LiveSession.swift` 的 `SESSION_END` 包含时长、平均心率、热量。 |
| User Content → Photos or Videos / 照片或视频 | App Functionality | 餐食照片保存在私有 `meal-photos`，用户提交的反馈截图保存在 `feedback-images` 并用于 GitHub 工单；`Services/MealPhotoStore.swift`、迁移 `20260921143250_meal_photo_lifecycle.sql`、`functions/feedback/index.ts`。没有视频功能也应选择此合并类别。 |
| User Content → Customer Support / 客户支持 | App Functionality | 用户反馈标题、正文、截图和设备环境；`Services/FeedbackReport.swift`、`functions/_shared/feedback.ts`。未证明满足 Apple 全部自愿披露豁免条件，按收集申报。 |
| User Content → Other User Content / 其他用户内容 | App Functionality、Product Personalization | AI 聊天文字、语音转写后提交的文字、用户记忆和偏好、餐食描述；`conversation_messages.content`、`ai_turns.user_text`、`user_memory`、`meals.text_input`。自由文本按本项，不因用户可能自行提及敏感内容就声明所有敏感类别。 |
| Identifiers → User ID / 用户 ID | App Functionality、Product Personalization、Analytics | Supabase 账号 UUID 关联业务、个性化和分析记录，传给 `Purchases.shared.logIn(userId)`；`Services/AuditTrails.swift`、`Services/Billing/BillingStore.swift`。 |
| Identifiers → Device ID / 设备 ID | App Functionality | 账号绑定手环的 BLE UUID/设备标识及 APNs token；`devices`、`push_tokens`、`Services/NotificationReach.swift`。这是本产品设备功能所需，不是 RevenueCat 自动要求的 IDFA 声明。 |
| Purchases → Purchase History / 购买历史记录 | App Functionality、Analytics | RevenueCat 收据验证、产品、订阅有效期与权益、服务端会员快照及仪表板分析；`Services/Billing/BillingStore.swift`、`functions/_shared/billing.ts`。RevenueCat 官方明确要求这两种用途。 |
| Usage Data → Product Interaction / 产品交互 | Analytics、App Functionality | 页面打开、点击、配对、登录、同意、付费与通知事件；`Services/AuditTrails.swift` 的 `Analytics` 将事件按账号上传 `analytics_events`，业务审计/问题排查也使用操作记录。 |
| Diagnostics → Performance Data / 性能数据 | App Functionality、Analytics | AI/界面耗时、配对和扫描耗时、同步耗时；`ai_turns.latency_ms`、`screen_frames.latency_ms`、`sync_runs`、`SCAN_DONE`/`DEV_OTA_END` 事件的 `MS`。 |
| Diagnostics → Other Diagnostic Data / 其他诊断数据 | App Functionality、Analytics | 同步错误、固件/能力、型号/系统/版本、AI 执行 outcome 与工具调用轨迹；`sync_runs`、`device_capabilities`、`ai_turns`、反馈上下文及失败分析事件。 |
| Other Data → Other Data Types / 其他数据类型 | App Functionality、Product Personalization | 出生日期、生理性别、时区、语言/单位偏好用于个人档案与建议；`profiles`、`Services/AuditTrails.swift`。健康来源字段同时已在 Health 描述中涵盖。 |

以上路径的 `Services`、`Features` 均相对 `app/NextBody/`；`functions`、`migrations` 均相对 `supabase/`。

## 音频：发布前需要单独关闭的不确定项

`functions/asr/index.ts` 将 WAV/PCM 交给 DashScope 实时/文件转写；文件模式在 `finally` 清空本函数持有的 bytes，没有发现把原始音频写入本项目数据库或 Storage 的路径。清空一个缓冲区不等于第三方没有保留，也不等于所有副本被证明即时删除。

Apple 的收集定义包括第三方在完成实时请求之后仍可访问的数据。因此：

- 若确认当前 DashScope 合同/产品设置不在实时请求之外保留原始音频，可不勾 Audio Data；转写成文字后的账号聊天仍须申报 Other User Content。
- 若第三方保留原始音频，应选择 **Audio Data → App Functionality → Linked Yes → Tracking No**；若第三方另有用途，继续按真实用途补充。
- 目前尚无第三方当前保留设置证据，不能把本行当成已经核验的“不收集”。

## 当前无依据勾选的类别

没有发现用户手机号/地址/通讯录、支付卡/银行账户、信用/收入、GPS 或粗略定位上传、浏览历史、广告数据、跨应用广告标识、独立搜索历史、手部/头部动作或环境扫描收集。时区本身不当作定位，Apple 处理银行卡不代表本 App 收集 Payment Info。生理健康信号归 Health；没有发现身份识别用途的生物特征模板。没有发现 Release 集成独立崩溃上传 SDK；普通失败事件放 Other Diagnostic Data，不凭日志名称宣称收集 Crash Data。Apple 自身分享给开发者的诊断不应直接等同 App 自行收集。

## 最后核实项

1. DashScope 原始语音的留存/日志设置，按上文确定 Audio Data。
2. RevenueCat 控制台启用的分析/归因/营销集成及客户属性：若另行发送邮箱、广告 ID 或营销数据，调整用途和跟踪回答。
3. 自有 required-reason 清单已补到 `app/NextBody/PrivacyInfo.xcprivacy` 和 `app/NextBodyLiveActivity/PrivacyInfo.xcprivacy`：两者均声明 UserDefaults `CA92.1`（本应用状态）和 `1C8F.1`（WidgetBridge 的 App Group 共享状态）；主应用另声明 SystemBootTime `35F9.1`（同步超时、触觉/长按等应用内计时）。仅声明已证实 API 用途，未用空 CollectedData 数组表示不收集数据。仍需在重新归档后核实两个 bundle 均携带清单，检查 SDK 自带清单和聚合报告；本草稿不替代这些检查。
4. 反馈图片代码使用公开 bucket URL，GitHub issue 包含账号 UUID；实际仓库可见性及已有图片访问控制需核实，政策应准确披露。不要把这些截图称作只有用户本人可访问，或声称数据库删号自动删除 GitHub 工单。

## 官方依据

- [Apple App privacy details](https://developer.apple.com/app-store/app-privacy-details/)：披露范围涵盖第三方；实时处理后不保留与仅本机处理适用不同事实前提；关联账号的数据不能按匿名申报；普通自由文本有单独类别。
- [RevenueCat Apple App Privacy](https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy)：购买历史必须申报 App Functionality 和 Analytics；本项目自定义账号 ID 可关联身份；RevenueCat 本身不等于广告跟踪。

文档仅记录类别与代码证据，没有保存用户健康值、账号令牌或服务密钥。
