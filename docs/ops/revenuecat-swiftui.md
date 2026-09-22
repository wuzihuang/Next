# NEXT：RevenueCat SwiftUI 接入

本文对应仓库真实实现。完整错误处理、身份队列和服务端同步代码位于链接文件中；示例复用它们，不创建第二个全局购买对象。

## 1. 安装 Swift Package

Xcode → File → Add Package Dependencies，输入：

```text
https://github.com/RevenueCat/purchases-ios-spm.git
```

选择 Exact Version：**5.89.0**；将 **RevenueCat** 和 **RevenueCatUI** 都加入 NextBody target。本项目已锁定实际验证的 5.89.0。App target 启用 In-App Purchase capability，Bundle 保持 `com.nextbody.hoop`。[官方安装步骤](https://www.revenuecat.com/docs/getting-started/installation/ios#install-via-swift-package-manager)。

## 2. 配置 key 与用户身份

复制 `app/Local.xcconfig.example` 到被忽略的 `app/Local.xcconfig`，设置 NEXT iOS 公开 SDK key：

```text
REVENUECAT_API_KEY = appl_<NEXT iOS public SDK key>
```

Info.plist 的 `RevenueCatAPIKey` 从该构建配置读取。不要将 `sk_` secret 放进 App。用户提供的 NEXT `test_` key 已加入 DEBUG 专用 `BillingCatalog.testStoreAPIKey`，默认开发构建使用它；Release 仅接受 `appl_`。

[BillingStore.configure()](../../app/NextBody/Services/Billing/BillingStore.swift) 只初始化一次 SDK；登录完成调用 `await billing.identify(userId: supabaseUUID)`，退出调用 `await billing.logOut()`。App 使用共享 `BillingStore`。购买、恢复和身份变更必须通过它串行执行，不能在其他 View 中直接 `logIn` / `logOut`。

## 3. 商品、权益与 Offering

NEXT 项目创建 `next_pro` entitlement。Test Store 使用 `monthly`，App Store 使用 `hoop_pro_monthly`，两者分别关联同一月付 Package。Offering `default` 设为 current。当前 App 使用原生 Paper 付费页，不再依赖托管付费墙；已发布的 RevenueCat Paywall 保留供旧版本使用。资源 ID、价格和部署状态见 [目录](pro-store-catalog.md)。

付费墙使用动态本地化商品价格、周期和商店优惠资格，不硬编码美元，也不从健康账号的历史领取时间推定 Apple 资格。App 顶栏菜单提供恢复和协议入口，通过 SDK `restorePurchases()` 完成恢复。

## 4. 在 SwiftUI 展示真实接入

以下完整 View 可以放进本项目，用于复用现有会员服务（需要先完成现有登录流程）：

```swift
import SwiftUI

struct SubscriptionExampleView: View {
    @ObservedObject private var billing = BillingStore.shared
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 16) {
            Text(billing.isPro ? "NextBody Pro" : "Free")
            if billing.hasStoreSubscription || billing.isPro {
                Button("Manage subscription") {
                    billing.showingCustomerCenter = true
                }
            } else {
                Button("Explore NextBody Pro") { showPaywall = true }
            }
            Button("Restore purchases") {
                Task {
                    if case .failed(let message) = await billing.restore() {
                        billing.lastMessage = message
                    }
                }
            }
            .disabled(billing.busy)
            if let message = billing.lastMessage {
                Text(message).foregroundStyle(.red)
            }
        }
        .task { await billing.refresh() }
        .fullScreenCover(isPresented: $showPaywall) {
            MembershipCardHost(billing: billing, source: .profile) {
                showPaywall = false
            }
        }
        .sheet(isPresented: $billing.showingCustomerCenter) {
            CustomerCenterHost(billing: billing) {
                billing.showingCustomerCenter = false
            }
        }
    }
}
```

真实 App 已在 `RootView` 与 onboarding 配置这些展示容器；示例不要再叠加到它们同一个 View 上。

[MembershipCardHost 完整实现](../../app/NextBody/Features/Billing/MembershipCard.swift) 使用原生 SwiftUI 还原 [Paper 原稿](https://app.paper.design/file/01M1M2B4XWK5W388XSKACJ1K9N/A-0)。Inter Tight / Doto / Jost 字体、字距和固定行高在页面内设置。背景改为用户提供的 Originkit Grain Mass：[本地 WebGL 渲染](../../app/NextBody/Resources/GrainMass.html) 由 [GrainMassBackground](../../app/NextBody/Features/Billing/GrainMassBackground.swift) 承载，位于所有原生内容后方，不参与点击，不加载远端资源。沿用手机粒子数量和指定配色、辉光参数，粒子团放大后上移、右移作为半屏背景，入场从半成形状态快速展开；退到后台暂停，关闭时释放资源，减少动态效果时显示静态形态。关闭不授予权益；恢复和协议在右上角菜单。真实系统状态栏、商店本地化价格及符合资格时的试用说明是必要的动态内容。

`loadPaywallOffer()` 等待健康账号登录 RevenueCat，读取当前月付 Package，再核对身份版本。加载失败只显示重试，不提供虚构价格或替代商品。页面把这个 Package 和身份版本交给 `purchase(package:expectedIdentity:)`；恢复也绑定同一身份。交易任务由 `BillingStore` 持有，即使页面关闭仍可完成服务端同步。保持 SDK 默认 RevenueCat 完成交易模式，不自行 finish StoreKit 事务。

基础调用如下（具体加载、重试和展示状态见完整宿主）：

```swift
let offer = try await billing.loadPaywallOffer()
// Display offer.priceAmount / currencySymbol and optional introductoryText.
let result = await billing.purchase(
    package: offer.package, expectedIdentity: offer.identity
)
switch result {
case .success: showPaywall = false
case .cancelled: break
case .unavailable: billing.lastMessage = "Subscription unavailable. Please retry."
case .failed(let message): billing.lastMessage = message
}
```

## 5. CustomerInfo 与 `next_pro`

SDK 的基本读取形式是：

```swift
import RevenueCat

func fetchStoreSubscription() async throws -> (CustomerInfo, Bool) {
    let info = try await Purchases.shared.customerInfo()
    return (info, info.entitlements.active["next_pro"] != nil)
}
```

仓库 `BillingStore.refresh()` 负责错误处理、身份验证和刷新；`customerInfoStream` 持续更新商店状态，身份切换时取消旧订阅并清空旧值。App 回到前台再次刷新。

`hasStoreSubscription` 用于商店管理入口；`isPro` 使用服务端账本及到期时间。客户端 CustomerInfo 不是调用 AI 的授权凭证。购买后请求 `billing-sync`，后端用 NEXT REST V2 key 重新读取真实权益，再写账本；同步失败不在客户端解锁。

## 6. 错误和恢复

- 用户取消返回 `.cancelled`，不当作购买失败或成功。
- 网络、配置或商品不可用给出可重试错误；缺失月付 Package 不显示可购买的替代商品。
- 交易进行中禁用重复操作；关闭页面不取消服务持有的购买任务。
- 恢复必须由用户点击触发。空恢复不授予 Pro；收据属于其他健康账号时提示回到原账号。
- `intro_claimed_at` 由可信事件/历史同步记录，取消和过期不会清除。
- 服务端 webhook 验证随机认证头；`billing-sync` 只同步 JWT 对应用户，忽略客户端伪造身份/权益。

## 7. Customer Center

[CustomerCenterHost 完整实现](../../app/NextBody/Features/Billing/RevenueCatCustomerCenter.swift) 使用 `CustomerCenterView()`，在 Profile 的现有订阅入口展示。恢复也经过身份队列与服务端同步，关闭后刷新。远端配置不要无意启用促销 offer。Customer Center 是否可用取决于 RevenueCat 项目套餐和配置，不能只由编译成功推断。[官方说明](https://www.revenuecat.com/docs/tools/customer-center)。

## 8. 验证

1. DEBUG 默认 Test Store：使用专用受控 QA 和独立模拟器；将该 UUID 精确加入服务端测试 allowlist。集成测试传入 `NB_RC_EXPECT_IDENTITY`，核对实际健康账号与 SDK 身份后，检查原生付费页、真实月付价格、取消、失败、成功、恢复和 Customer Center。环境注入的登录 token 不会覆盖已有 Keychain，不能据此假定当前账号。
2. 购买后确认 `next_pro`、服务端账本、有效到期时间一致；空恢复或到期确认不授权。
3. Apple 沙盒：`NB_DEBUG_RC_STORE=app_store`，关闭 Scheme 的本地 StoreKit Configuration，使用 sandbox tester。Test Store 通过不能替代 Apple 购买/通知验证。
4. Release 构建确认使用 `appl_` key；服务端无 Pro 返回 402 且不消耗 AI 额度，有 Pro 仍遵守原额度门槛。
5. 测试完成后删除本轮创建的 QA 数据并移除临时 allowlist。Test Store 订阅有短有效期；交易后先验证 Customer Center，再验证冷启，避免将跨休眠过期误判为激活失败。

实际通过项和未完成外部验证以 [运维状态](pro-store-catalog.md) 为准。

### SDK 版本

当前锁定实际验证的 RevenueCat 5.89.0。原生页面只使用公开的 Offering、Package、优惠资格及购买 API，已移除托管 Paywall 的 Internal SPI 适配器。RevenueCatUI 继续用于 Customer Center。升级时复核交易身份队列、恢复归属和服务端同步。
