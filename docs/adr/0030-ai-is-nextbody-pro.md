# AI 走 NextBody Pro；手环与读数一次买断

历史决策，已于 2026-10-15 停用：App AI 不再要求 Pro 订阅。本文件保留作为当时的决策记录，不代表当前实现。订阅取消仍需用户在 App Store 操作。

2026-09-15 用户裁决。本 ADR 使用未占用的 0030。

## 决定

1. HOOP $99 一次买断；生命体征、同步、测量和设备功能不收订阅。Shopify 只卖手环。
2. App 的面板、教练、当日建议和 ASR 需要 Pro。服务端在模型、预算和额度操作前检查 `billing_entitlements`，无权益返回 `402 SUBSCRIPTION_REQUIRED`，查询故障返回 `503 BILLING_UNAVAILABLE`。Pro 仍受 ADR 0007 的额度限制。
3. 2026-09-20 起主推 iOS 年付商品 `hoop_pro_yearly`，美国 $19.99/年；月付 `hoop_pro_monthly` 保留兼容已有订阅。当前价格、可售地区和优惠以商店为准，目录见运维文档。美国和中国大陆配置一个月介绍性免费试用。实际首月资格由 App Store 判定；健康账号不能强制关闭或授予商店优惠。`intro_claimed_at` 一旦写入便不可清除。
4. **2026-09-19 最新裁决：原生 SwiftUI 按 Paper 页面还原，RevenueCat 负责商品、购买、恢复和 `next_pro` 权益。** 此项替代此前托管 RevenueCat Paywall 的 UI 决定。原稿为 Paper 文件 `01M1M2B4XWK5W388XSKACJ1K9N`、页面 `A-0`、画板 `1180-1`（390×844）；使用原稿背景、字体、字距和行高。实际价格及优惠资格来自商店。旧 A/B 仅保留为 DEBUG 门控测试夹具，不决定真实交易文案。恢复与协议通过右上角菜单提供；符合资格时另显示真实免费试用说明。
5. 付费墙可关闭：建档后、Home 前展示；返回按钮进入 Home，不授予试用。跳过后访问 AI 再展示。原登录、配对、建档门控不变。
6. RevenueCat App User ID 使用 Supabase 用户 UUID。登录、购买、恢复与退出在同一身份队列执行；切换健康账号后不能应用旧账号结果。
7. 客户端读取 `CustomerInfo.entitlements.active["next_pro"]` 展示商店订阅状态。AI 授权由服务端账本决定，购买成功仍须同步服务端。RevenueCat REST V2 可信读取与认证 webhook 写入本地 `entitlement='pro'`；旧 RevenueCat `pro` 不再授予访问。
8. 付费墙提供恢复购买。已有订阅在 Profile 进入 RevenueCat Customer Center，处理订阅支持与恢复。恢复归属应保留在原健康账号，不能仅凭客户端回调转移权限。
9. DEBUG 默认使用 NEXT Test Store 的 `yearly`（`monthly` 保留兼容）；显式切换后可用 Apple 沙盒。Release 只接受 iOS 公开 `appl_` key。Secret key 仅用于服务端。
10. 当前只实现 iOS。关闭家庭共享，开启账单宽限期；主推年付，不做多档、网页 AI 订阅或客户端发放试用。

## 实现与运维

- `app/NextBody/Services/Billing/`：身份、SDK、客户信息与服务端同步。
- `app/NextBody/Features/Billing/`：Paywall、Customer Center、Profile 状态。
- `supabase/migrations/20260915120000_pro_membership.sql`：账本、RLS、不可清除的领取历史。
- `supabase/functions/_shared/billing-revenuecat-v2.ts`：REST V2 权益映射。
- 当时的商店目录与 SwiftUI 接入文档已随订阅代码一起移除。

依据：[Apple 介绍优惠](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions)、[RevenueCat Paywalls](https://www.revenuecat.com/docs/tools/paywalls)。
