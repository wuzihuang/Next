# AI 走 NextBody PRO；手环与读数仍随手环一次买断

2026-09-15 用户裁决。计划在仓库外的 Pro 订阅方案；本 ADR 记下代码里必须守住的边界。计划原文写「ADR 0025」，但 0025 已经是摄入目标（静息 + 实测活动），所以本裁决落在 0030。

## 决定

1. **手环一次付清。** HOOP $99，黑或白。读生命体征、同步、测量、设备页，都不收订阅。Shopify 只卖手环；不在店里收 App 订阅。
2. **App 里的 AI 是 PRO。** 面板、教练、当日建议、ASR，没有有效权益就拒绝。错误码 `SUBSCRIPTION_REQUIRED`。服务端查 `billing_entitlements`，不信客户端。
3. **额度仍在。** ADR 0007 的日次数与金额上限对 Pro 用户继续生效。没有 Pro 不再赠送每天 10 次。
4. **首月是商店介绍优惠。** 商品 `hoop_pro_monthly`，$6 / month，Introductory Offer / Free trial 一个月。客户端不许空发一个月。必须先在 App Store 绑支付才能领；不绑就没有免费月。我们自己不收银行卡号。
5. **两张文案。** 这个健康账号从未领取过试用 → A（免费送 1 个月）。领过之后取消或过期 → B（只说 $6 / month，不再说免费送一个月）。领取记录是 `intro_claimed_at`，写过就不清。
6. **卡可以关掉。** 身体信息 + 身体成分之后、进 Home 之前出卡；左上角 X 进 Home，不送试用。跳过之后每次点 AI 再出同一张卡。回访且没看过卡的人，第一次进 Home 也出。现有登录 / 配对 / 建档门控不改成强制订阅。
7. **RevenueCat 是商店账本，表是服务端账本。** App User ID = Supabase `auth.users` UUID。登录 `logIn`，登出 `logOut`。Webhook（以及购买后的 `billing-sync`，它向 RevenueCat 再读一次）写表。跑模型之前只查表。
8. **只做 iOS。** Bundle `com.nextbody.hoop`。Google Play 只建同价目录，没有 Android 购买路径。家庭共享关；宽限期开。
9. **付费墙有 RESTORE。** 审核要。

## 不做

- Android 客户端
- 我们自己收银行卡号
- 年付、多档、家庭共享、网页买、Shopify 收订阅
- 客户端空发一个月
- RevenueCat 远程 Paywall 模板

## 文件

- 迁移 `supabase/migrations/20260915120000_pro_membership.sql`
- Edge：`_shared/billing.ts`、`revenuecat-webhook`、`billing-sync`；`turn` / `asr` 在额度前查权益
- 客户端：`Services/Billing/`、`Features/Billing/`、`StoreKit/HoopPro.storekit`
- 商店目录与密钥：`docs/ops/pro-store-catalog.md`
