# NextBody PRO · App Store Connect / RevenueCat / Play

代码已经按这些标识符接线。控制台还没建商品时，购买会失败；UI、SDK、webhook 与 StoreKit 配置可以先合入。

## Identifiers

| Where | Key | Value |
|---|---|---|
| Bundle ID | iOS | `com.nextbody.hoop` |
| StoreKit / ASC product | Auto-renewable monthly | `hoop_pro_monthly` |
| Price | Monthly | **$6.00 USD** |
| Introductory offer | Free trial | **1 month** (must bind App Store payment to claim) |
| Subscription group (ASC) | Suggested name | NextBody Pro |
| RevenueCat entitlement | | `pro` |
| RevenueCat product | attached to `pro` | `hoop_pro_monthly` |
| RevenueCat App User ID | | Supabase `auth.users` UUID |
| Family sharing | | Off |
| Billing grace period | | On |

Suggested App Store localization (English default):

- Display name: NextBody Pro
- Description: Panel, coach, daily suggestions and voice.

`zh-Hans`: 面板、教练、当日建议和语音。

## RevenueCat

1. Create the iOS app with bundle `com.nextbody.hoop`.
2. Add product `hoop_pro_monthly` (subscription). Attach entitlement `pro`.
3. Public SDK key (`appl_…`) → Xcode `REVENUECAT_API_KEY` in `Local.xcconfig` (see `app/Local.xcconfig.example`) and the Release build.
4. Secret API key (`sk_…`) → Edge secret `REVENUECAT_SECRET_API_KEY` (used by `billing-sync`).
5. Webhook URL: `https://<project-ref>.supabase.co/functions/v1/revenuecat-webhook`
6. Webhook Authorization header: a long random secret, stored as Edge secret `REVENUECAT_WEBHOOK_SECRET`.
7. App Store Connect shared secret / In-App Purchase Key: paste into RevenueCat so sandbox and production receipts verify.
8. Offering: current offering should include the monthly package for `hoop_pro_monthly`.

Events the webhook applies: `INITIAL_PURCHASE`, `RENEWAL`, `UNCANCELLATION`, `PRODUCT_CHANGE`, `CANCELLATION`, `EXPIRATION`, `SUBSCRIPTION_PAUSED`, `TRANSFER`, plus anything else that carries `app_user_id` + `expiration_at_ms`.

## App Store Connect

1. Subscriptions → group **NextBody Pro** → product **hoop_pro_monthly**.
2. Price $6 USD (and equalized tiers).
3. Introductory Offer: Free, 1 month, new subscribers.
4. Family Sharing: off.
5. Billing grace period: on.
6. Turn on In-App Purchase capability for the App ID (already expected for this bundle).
7. Sandbox testers: bind a payment method (StoreKit config `app/NextBody/StoreKit/HoopPro.storekit` is attached to the NextBody scheme for local runs).

## Google Play (catalog only)

No Android app ships. If you have Play Console access, create a matching subscription so the product id exists:

- Product id: `hoop_pro_monthly`
- Status: 1 month, $6
- Free trial: 1 month
- Base plan: paid
- Do not attach a Play billing client in this repo.

If Play Console is not available, skip this and leave the catalog for later. The iOS path does not depend on it.

## Edge secrets

```
REVENUECAT_WEBHOOK_SECRET=
REVENUECAT_SECRET_API_KEY=
```

`revenuecat-webhook` has `verify_jwt = false`. Without the webhook secret the function returns 503.

## Client debug

`NB_DEBUG_PRO=offerA|offerB|active|welcome` pins the card without a store account.
`NB_DEBUG_ONB_STEP=membership` opens the onboarding card.
