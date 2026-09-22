# NextBody Pro 商店目录与部署

目录最近核验：2026-09-21；历史验收分别注明日期。产品裁决见 [ADR 0030](../adr/0030-ai-is-nextbody-pro.md)。本页不保存密钥。

## 目录

| 资源 | 标识 |
|---|---|
| ASC App / Bundle | `6799623125` / `com.nextbody.hoop` |
| ASC 订阅组 | `22387349`（NextBody Pro） |
| ASC 年订阅（在售，2026-09-20 起） | `6814214555` / `hoop_pro_yearly`，$19.99 / 年，美国 + 中国大陆，首月免费 |
| ASC 月订阅（保留兼容；停售状态待页面复核） | `6812410775` / `hoop_pro_monthly` |
| RevenueCat 项目 | `proje9b647bc`（NEXT） |
| RevenueCat 权益 | `entl9e6ffc6cba` / `next_pro` |
| 当前 Offering | `ofrngaabd10a5d7` / `default` |
| 月付 Package | `pkge68a9532a30` |
| 年付 Package（在售，position 1） | `pkge4e03b9050a`（`$rc_annual`） |
| Test Store App / Product | `appf01d4e38da` / `prod04d7fb5a5a`（`yearly`，P1Y）· `prod7aa8680c30`（`monthly`） |
| iOS App / Product | `app31d0228018` / `prod52968ea7de`（`hoop_pro_yearly`）· `prod39605236af`（`hoop_pro_monthly`） |
| Paywall | `pw84cc6b5106244356`，已发布 revision 11（旧客户端使用）；revision 12 为未发布草稿 |
| SDK 5.89 workflow | `wfc0d7c52d17314f0a`（关联 `default`） |
| RevenueCat webhook | `whintgre7636d4aaa` |

生产授权接受 App Store / Play 的 production 与 sandbox 交易（TestFlight、审核员都在 sandbox 购买，2026-09-19 起）；RevenueCat Test Store 交易只对 `REVENUECAT_TEST_ACCOUNT_ALLOWLIST` 中明确指定的测试 UUID 生效。公开 Test Store key 不能给普通账号授予生产 AI 权限。

2026-09-20 起在售的是年费 `hoop_pro_yearly`（$19.99 / 年，付费页大字 $19.99 / 年，角标 80% OFF 并划线 $99.99（= 年价 ÷ 0.2 取 .99），下一行"折合每月仅 $1.66"。$99.99 不是在售价，审核若质疑划线价，去掉 `listPrice` 那一行即可）。服务端 `_shared/billing-product-ids.ts` 同时认年费与月费四个商品 id，老月订户不受影响。RevenueCat 已于 2026-09-20 通过 REST v2 配好：App Store 商品 `hoop_pro_yearly`、Test Store 商品 `yearly` 都挂到 `next_pro`，并进了 `default` Offering 的 `$rc_annual` 包（月付包保留）；Test Store 商品价格用官方 CLI 设：`npx @revenuecat/cli` 的 `rc products prices set <prod> --price USD=19.99 --price CNY=128`（REST v2 的 product 接口没有价格字段）；客户端按 `BillingCatalog.sellableProductIDs` 的顺序选包，年费优先。

历史月付商品仍关联 `next_pro` 与月付 Package；年付商品关联同一权益与年付 Package。客户端使用 SDK 本地化价格。2026-09-21 API 仍返回月付中美两地 availability，因此不能仅凭此前“停售”记录认定它已停止销售；需在 ASC 页面复核。

## App Store Connect

- 仅美国、中国大陆可售；两地均一个月免费介绍优惠，2026-09-15 起无结束日期。
- 家庭共享关闭；16 天账单宽限期，所有续订、生产与沙盒开启。
- en-US / zh-Hans 本地化及审核截图已上传，订阅 `READY_TO_SUBMIT`，尚未提交审核。原生 Paper 付费页真实 SDK 截图已于 2026-09-19 替换并读回 COMPLETE（ID `0c523868-d1d9-4239-b1ef-5196c2389fcb`，1170×2532，MD5 `62507b8d429467ce7a981af14ca92285` 与本地一致）。
- RevenueCat 控制台确认 ASC / IAP 两套凭据 `Valid credentials`。
- Apple → RevenueCat 生产与沙盒通知地址已保存，ASC API 独立读回均匹配、均 V2。
- Apple 沙盒 TEST 初次请求返回 `4040007`；传播后最终重试 HTTP 200，状态查询 HTTP 200，`sendAttempts.sendAttemptResult=SUCCESS`。已证明 Apple → RevenueCat 测试通知送达；真实购买闭环仍待验证。

## 服务端

项目 `gkgzwcxivnffsecshvfs`：已单独应用会员迁移并部署 `billing-sync`、`revenuecat-webhook`（清理测试配置后均 v7）；生产 `turn` v97、`asr` v38 已部署最小会员门控补丁，下载读回源码 SHA 与部署包一致。没有顺带应用其他任务的迁移。

Edge 配置：

```text
REVENUECAT_PROJECT_ID=proje9b647bc
REVENUECAT_SECRET_API_KEY=<NEXT REST V2 secret>
REVENUECAT_WEBHOOK_SECRET=<random authorization secret>
REVENUECAT_TEST_ACCOUNT_ALLOWLIST=<explicit test health UUIDs only>
```

Webhook URL：`https://gkgzwcxivnffsecshvfs.supabase.co/functions/v1/revenuecat-webhook`。RevenueCat 认证头为 `Bearer <REVENUECAT_WEBHOOK_SECRET>`，覆盖 NEXT 全部 App、事件与环境。该端点关闭 JWT 校验，但强制检查此认证头；`billing-sync` 校验用户 JWT。

REST V2 读取 `next_pro`、`gives_access`、实际到期/宽限期、商品 `store_identifier` 和历史 trial 事件。分页或上游错误拒绝同步，不把错误当作无订阅。可信写入映射至 SQL `entitlement='pro'`；旧 RC `pro` 不授权。空订阅撤销访问但不清除历史 `intro_claimed_at`。

已核验：V2 及测试环境隔离相关 31 项测试通过；现有测试账号同步 200、空恢复无 Pro；未认证调用 401，认证 TEST webhook 200。生产 `turn` / `asr` 已完成部署读回与 HTTP 门控核验，见下方；公开 WebSocket 尚有网关错误。

## 客户端与验证边界

- [SwiftUI/SPM 步骤](revenuecat-swiftui.md)。Release `appl_` key 放在被忽略的 `app/Local.xcconfig`，不使用 Test Store 或 secret key。
- DEBUG 默认 Test Store；`NB_DEBUG_RC_STORE=app_store` 使用 iOS key。真实 Apple 沙盒测试须关闭 Scheme 的本地 StoreKit Configuration。
- `NB_DEBUG_PRO=offerA|offerB|active|welcome` 仅测试门控，不触发真实交易，不证明真实商店购买可用。
- 最新 App 使用原生 Paper 页面和公开 RevenueCat 购买 API；不依赖托管 Paywall workflow。实际月付 Package 缺失时显示可关闭、可重试错误。
- 恢复策略已保存为 **Keep with original App User ID**；跨健康账号真实恢复仍需验证。
- Google Play 目录尚未配置；当前 iOS 路径不依赖 Android。

## 本轮交付核验（2026-09-19）

### 已完成

- 托管 Paywall / workflow 已按此前授权发布并完成真实 SDK 渲染验证。最新用户裁决改为原生 SwiftUI 精确还原 Paper；旧墙继续供旧客户端使用，新客户端不再依赖 workflow 或 Internal SPI。
- 旧托管页面的真实 SDK 空恢复、取消、模拟失败及五入口门控通过；9 项 store-free 门控用例通过。旧墙 5 次带缓存模拟器建档测量 P50=1.457 秒，仅为此前实现的本机基线，不代表新原生页面或生产用户延迟。
- 专用 Test Store QA 于 2026-09-19 05:43 UTC 再次购买成功，客户端关闭付费页，RevenueCat `next_pro` 与服务端有效期账本一致。有效期内 Customer Center 显示 Active、$6、Test Store；冷启 Pro → Center → 关闭 → 冷启 Pro 通过。
- 生产 `turn` / `asr` 仅部署从生产基线提取的会员门控补丁。无权益的面板、聊天、计划、ASR POST 均返回 402 `SUBSCRIPTION_REQUIRED`，预算、额度、操作及模型记录均未增加；过期 QA 同样拒绝。有效订阅 QA 通过会员门槛后，受控无模型请求返回预期 `TURN_STATE_LOST`，只增加预期请求预算，未消耗模型额度。
- Customer Center 配置已保存读回：无额外促销、不升级套餐。Test Store 不展示 Apple 管理操作，不能据此认定 Apple 管理订阅已验证。
- 隔离 PR 的 Swift Billing 9 项、Deno 相关 107 项和 Release 构建曾通过；前期全量 Swift 919、Deno 333、会员 SQL 22 项通过，不应表述为最终全量重跑。最终原生页面的隔离 Release 模拟器构建及差异检查已通过（`/tmp/nextbody-pr39-native-release.log`）。

- 原生 Paper 页面已按 390×844 对照：主要文字位置偏差约 0–0.3pt，CTA 边界约 0.5pt，保留真实系统状态栏及恢复/协议菜单。截图几何、DEBUG 预览不可购买、关闭进入 Home、真实 SDK 商品加载与关闭、五个真实 AI 入口及自动计划不弹窗均通过。真实商品就绪计时（Enter 点按至 START PRO 可用）5 次为 1.390 / 1.389 / 1.399 / 1.381 / 1.390 秒，P50=1.390 秒；进程冷启但保留磁盘和会话缓存，含 XCTest 开销，不代表生产延迟。此次不重复购买交易；购买/恢复服务沿用此前已验证的身份队列。ASC 审核截图已更新并独立读回 COMPLETE。

### 尚未完成 / 验证边界

- 公开 ASR WebSocket：有效 HTTP/1.1 Upgrade 与实际 WebSocket 客户端均收到空 Cloudflare 502，未建立音频会话。不能声称公开 WebSocket 402 已通过；本地测试和部署源码确认会员门控位于额度操作前。
- 用户暂时无法连接 USB，明确暂缓真实 Apple 购买验证。此前真机可安装启动，但 XCTest 在执行前因 IDE 连接拒绝（code 74）失败。Apple 沙盒 TEST 通知成功不等于真实购买通过。
- 跨健康账号真实恢复、Apple 购买 / 续费 / 取消及管理操作仍需设备验证。恢复归属策略已配置并读回；Test Store 到期拒绝已验证。
- 购买 QA 已清理：RevenueCat 与 Auth 读回 404，相关账本、预算和额度记录为 0；临时 allowlist 已设空并核对远程摘要。无权益 QA 也已在 UI 验证后清理，RevenueCat / Auth 均不存在，相关记录为 0；本地 QA 会话凭证已删除。

### 证据

临时本地验收产物：原生页面 `/tmp/nextbody-native-paper-verification.xcresult`、严格商品就绪计时 `/tmp/nextbody-native-ready-final.xcresult` 与截图 `/tmp/nextbody-native-approved-screens/native-paywall-final.png`；五入口 `/tmp/nextbody-rc-real-five-gates.xcresult`；有效期内 Center / 冷启 `/tmp/nextbody-rc-center-badge-final.xcresult`；生产部署读回 `/tmp/nextbody-production-membership-readback.json`；拒绝与额度 `/tmp/nextbody-production-gates-result.json`（因 WebSocket 未通过，整体标记 false）；有效订阅 `/tmp/nextbody-production-positive-gate-result.json`；到期拒绝 `/tmp/nextbody-expired-gate-result.json`。这些路径是本轮本机证据，不是仓库长期依赖。

## 2026-09-20 年费闭环验证

iPhone 17 Pro Max 模拟器，demo 账号（`f6507719…`，已加入 `REVENUECAT_TEST_ACCOUNT_ALLOWLIST`，与用户账号 `9c59c2e5…` 并列）：ME 卡片读到 `US$19.99 / 年` → 付费页 80% OFF / 划线 US$99.99 / US$19.99 / 年 / 折合每月 US$1.66 → Test Store 弹窗显示 `yearly` · US$19.99 · 1 year → Test valid purchase → 成功页 PRO IS ON（颗粒云背景）→ 服务端 `billing_entitlements` 写入 `product_id=yearly, store=test_store, will_renew=true` → ME 显示已开通 → 管理页显示下次续订 / 每年 US$19.99 / Pro 会员。demo 账号在 RevenueCat 里现在持有一个 Test Store 年费订阅（Test Store 年费一小时续订一次）；再测前先把它的 `billing_entitlements` 行改过期。


## 2026-09-21 上线复核

**尚不能声称 Apple 订阅全流程跑通，也不能直接提交当前 App。**
本次实时查询 NEXT（`proje9b647bc`）的 REST v2；当前通用 RevenueCat MCP
连接属于另一项目 O1，不能用于 NEXT。未变更该连接、密钥或商品价格。

### 实时确认

- `next_pro` 下四个商品齐全；`default` 是 current，月/年两包的 App Store
  与 Test Store 映射均正确，所有列表 `next_page=null`。
- iOS bundle 为 `com.nextbody.hoop`，ASC key 和 subscription key 都显示
  configured；这是配置存在检查，不是本次重新完成凭据验证。
- RevenueCat webhook URL 指向正确生产函数，App、环境、事件过滤器均为空（接收全部）。
- 年费 `hoop_pro_yearly`：美国 $19.99/年，中美地区一个月免费试用，
  2026-09-20 起；年/月订阅均为 `READY_TO_SUBMIT`，不是已批准。
- 年费审核截图已交付 COMPLETE，1320×2868。订阅检查无阻塞，
  两项待送审和两项可选推广图片警告；推广图片不能替代 App Store 商店截图。
- 下载线上 `billing-sync`、`revenuecat-webhook` 及其五个共享模块，
  全部与工作区逐字节一致，包含年费商品和 Test Store allowlist 隔离。

### 本次补齐

- ASC 1.0 中文介绍（含自动续订说明）、关键词、副标题、健康与健身分类、
  `2026 NextBody` 版权与手动发布设置已保存。年龄问卷按现有条款设为 18+，
  标注健康/健身主题；未宣称具有年龄验证或家长控制。
- 客户端修复：有效订阅按它自己的商品取价格，避免老月订户显示年费；
  付费页的恢复入口不再依赖在售 Offering 加载成功，保留身份校验。
- 33 项 Deno Billing/Webhook、9 项 Swift Billing 测试与完整 Release 模拟器
  构建通过。测试不覆盖真实 SDK 交易/上述 UI 路径；额外 turn/asr 用例因本地
  `npm:ws@8.18.3` 依赖解析缺失未跑通。产物 `RevenueCatAPIKey` 是 `appl_`，
  且与 NEXT iOS 的公开 SDK key 一致。
- 本地修改尚未上传新的 App Store build；真实 Apple 购买/恢复仍待验证。

### 上线仍缺

1. **最终 build 与真实 Apple 沙盒验收**：版本 1.0 当前关联 build 3
   （9 月 6 日）；最新上传 build 6（9 月 19 日）也早于年费改动和本次修复。
   需要包含最终变更的 Release，实际验收购买、续费、取消、到期、同/跨账号恢复，
   并核对 RevenueCat → webhook → 服务端权益。Test Store 或 TEST 通知不能替代。
2. **审核资料与截图**：真实审核联系人、可用审核账号/登录路径、选定的最终
   商店截图。现有多套截图仍为候选，不擅自替用户决定最终画面。
3. **App 隐私与支持网页**：`nextbody.ai/policies/privacy-policy` 返回 200，
   但内容是 Shopify 电商政策，尚不覆盖 App 的健康/AI/订阅处理；
   `/pages/contact` 返回 404。不能把它们填进去只为消除校验错误。
   需发布覆盖 App 的政策与有效支持页，并完成 App Privacy 声明。
4. **内容权利和销售地区**：内容权利声明未填写。中美销售地区初始化失败，ASC 返回
   `territoryAvailabilities.territory` 引用 BEL 缺少 included resource，
   随后读取确认 availability 仍不存在；不能记为成功。
5. **商业账户与首批订阅送审**：付费协议、税务、银行状态需要登录后的 ASC
   Business 页面确认。CLI web session 未登录，公共 API 无法证明这些已完成。
   首个订阅需随新的 App 版本送审；本轮没有提交审核或发布。
6. **划线价依据**：页面 80% OFF / $99.99 来自年价反推，未核验真实历史/标准
   在售价依据；上线前需提供依据或移除该营销声明。

ASC 复查由初始 34 个必填问题降到 6 个：支持 URL、审核资料、内容权利、
销售地区、截图与隐私 URL。年龄问卷已不再报缺失。临时证据保存在
`/tmp/next-subscription-audit-20260921`；本页为长期状态记录。


## 2026-09-22 审核联系人与截图

用户指定 [Paper ASC 页面](https://app.paper.design/file/01M0SW066YG64X1X6TQA07024T/p-Y-0)
并确认沿用 18+。当前 Paper `NEXTBODY-HOOP / ASC` 的 B-01 至 B-06 画布与
`screenshots/final-deepfield/01…06` 导出图逐张视觉对应；直接使用已有 1290×2796
PNG，未改设计，也未上传 contact sheet。

- 审核联系人按用户本轮提供内容保存并独立读回；邮箱拼写未擅自更正。
  私人联系方式只保存在 ASC，不在本文重复。
- 18+ (`ageRatingOverrideV2=EIGHTEEN_PLUS`) 已读回确认。
- 六张截图已上传到 1.0 的 `zh-Hans` localization，按文件 01–06 排序；
  `IPHONE_69` 由 CLI 映射为 Apple API `APP_IPHONE_67`。
  Screenshot set `6415f1c0-1a88-4a8d-b7f5-ad9f98afd49f`，六张均 COMPLETE，
  独立读取的 MD5 均与本地文件一致。英文设计按用户选定原稿保留。
- ASC 仍有六个必填字段问题：支持 URL、审核登录名、审核登录密码、内容权利、
  销售地区、隐私政策 URL。联系人缺失和商店截图缺失已解决。
  审核账号尚未填写；Release 的普通登录是 Apple/Google/邮箱验证码，
  不应把 DEBUG demo 登录或随意填写的固定验证码当作审核可用账号。
- 销售地区公共 API 的 relationship 拒绝是 CLI 上游已记录的问题；建议的
  web-session 备用路径仍缺 ASC 登录会话。本轮没有提交审核、发布或上传新 build。

上传回执、逐图读取与最终 validate JSON 位于
`/tmp/next-subscription-audit-20260922`。


## 2026-09-22 上线准备续查（当前状态）

用户随后取消 18+ 定位。本轮已将 ASC override 改为 `SIXTEEN_PLUS`，
App 注册门槛与中英条款同步为 16 岁，未成年人需监护人许可；不宣称已实现
监护人身份验证。上文 18+ 是此前状态，以本节为准。

- `nextbody.ai` live theme 已新增 9 个原生 Liquid 文件。以下三个中英双语
  页面独立 HTTP 验证为 200、含正文且无 Liquid 错误，不依赖客户端 JS：
  [隐私政策](https://nextbody.ai/collections/all?view=app-privacy)、
  [条款](https://nextbody.ai/collections/all?view=app-terms)、
  [支持](https://nextbody.ai/collections/all?view=app-support)。
  隐私和支持 URL 已保存至 ASC，中文介绍补充隐私与条款链接。
- 政策已覆盖 TypeSafe/Jev、RevenueCat 的账户关联、GitHub 工单/截图及
  Shopify 网站处理；数据保留期仅表述为配置目标，未声称线上清理已证实。
  两个公开邮箱的收件能力尚未验证。页面生成、ESLint、TypeScript、Swift
  语法及 Shopify Toolkit 验证通过；原生浏览器视觉验证受工具状态返回限制。
- 使用 NEXT 项目的授权实时验证 Apple 两套凭据，ASC key 的三项与 IAP key
  的两项检查均 valid。商品、权益、Offering、Package、Webhook 映射正确。
  旧托管 Paywall 已不存在，当前 Offering 无 hosted paywall；原生购买界面
  不依赖它。恢复归属策略/Customer Center 未重新验证。
- Apple 年价为美国 $19.99、中国 ¥148；Test Store 中国为 ¥128，仅测试价格
  不一致，本轮未改生产价格。月订阅 API 仍返回 USA/CHN，不能以历史文档
  推断它已经停售。年/月订阅均 `READY_TO_SUBMIT`，尚未获批。
- [App Privacy 草稿](app-privacy.md)列出实际收集数据与用途，尚未发布。
  DashScope 原始音频保留需核实；自家服务清空音频不等同于第三方不保留。
- 尝试新增 en-US 商店介绍时，Apple 以 NextBody 名称已被占用拒绝，未产生
  英文本地化；未擅自更改 App 品牌名。现有 zh-Hans 信息与六张截图完整保留。
- 最新公共 API 校验为 4 个阻塞字段：审核登录名、审核登录密码、内容权利、
  销售地区。App Privacy 发布状态、商业协议/税务/银行、首次订阅随版本
  送审及真实 Apple 沙盒交易仍需完成。没有提交审核或公开发布 App。

主 App 与 Live Activity 扩展已新增 required-reason 隐私清单：UserDefaults
`CA92.1` / `1C8F.1`，主 App 另有 SystemBootTime `35F9.1`。未用空数据
收集列表代替 ASC 声明。两份 plist 验证通过，最终 Release build 7 归档成功；已读取归档，确认主 App
和扩展各自包含正确清单。SDK 的 Google/RevenueCat 等清单也已打包。

本轮临时证据：`/tmp/next-launch-20260922`。


Build 7 已导出为 App Store IPA 并上传，Apple 处理为 `VALID`，已成功关联
1.0 待审核版本，替换旧 Build 3。Build ID 为
`0c9b60a8-70d8-46b6-80d8-0a9895648e8b`。归档和 IPA 位于
`/tmp/next-launch-20260922`。最终校验仍为 4 个阻塞字段、4 项订阅警告。
`asc account status` 可读取 App，商业协议状态仍为 public API unavailable，
不能推断协议已生效。
