import Foundation
import SwiftUI
#if canImport(RevenueCat)
import RevenueCat
#endif

enum MembershipPresentation: Equatable {
    case welcome
    case ai
    case profile
}

enum BillingPurchaseResult: Equatable {
    case success
    case cancelled
    case unavailable
    case failed(String)
}

#if canImport(RevenueCat)
struct BillingPaywallOffer {
    let identity: UUID
    let package: Package
    /// The figure the card sets big: one billing period, `19.99` for the year.
    let priceAmount: String
    let currencySymbol: String
    /// The store's own string for one billing period — `$19.99` for the year.
    let localizedPrice: String
    let isYearly: Bool
    /// Yearly only: the year divided by twelve (`$1.66`) and the price the 80% comes off (`$99.99`).
    let perMonthPrice: String?
    let listPrice: String?
    let introductoryText: String?
}
#endif

/// iOS store purchases. The table on the server is what `/turn` and `/asr` believe.
@MainActor
final class BillingStore: ObservableObject {
    static let shared = BillingStore()

    @Published private(set) var snapshot = BillingSnapshot.unknown
    @Published var presentation: MembershipPresentation?
    @Published private(set) var busy = false
    @Published var lastMessage: String?
    @Published var showingCustomerCenter = false
    /// Pro just turned on. The paywall is already gone by then (`presentation = nil`),
    /// so the success page is its own root overlay rather than a paywall state.
    @Published var celebrating = false
    #if canImport(RevenueCat)
    @Published private(set) var customerInfo: CustomerInfo?
    /// Store-facing status for subscription UI. AI admission still uses `isPro`.
    var hasStoreSubscription: Bool { isCurrentIdentity && customerInfo?.entitlements.active[BillingCatalog.entitlementID] != nil }
    #else
    var hasStoreSubscription: Bool { false }
    #endif
    var usesStoreFreePreview: Bool { isDebugPreview }
    /// Only App Store subscriptions have Apple's manage sheet; Test Store and web ones don't.
    var cancelsInAppStore: Bool {
        #if canImport(RevenueCat)
        let store = customerInfo?.entitlements.active[BillingCatalog.entitlementID]?.store
        return isCurrentIdentity && (store == .appStore || store == .macAppStore)
        #else
        return false
        #endif
    }

    var isPro: Bool { (isDebugPreview || isCurrentIdentity) && snapshot.isActive && (snapshot.expiresAt.map { $0 > Date() } ?? true) }
    var offer: BillingOffer { snapshot.offer }

    private var identifiedUser: String?
    private var configured = false
    private var identityRevision = UUID()
    private var refreshRevision = UUID()
    private var storeIdentityTask: Task<Void, Never>?
    private var customerInfoTask: Task<Void, Never>?
    private var storeIdentityReady = false
    #if DEBUG
    private var debugWelcomeSeen = false
    #endif
    private var isCurrentIdentity: Bool {
        identifiedUser != nil && identifiedUser == SupabaseClient.currentUserIdSnapshot()
    }
    private var isDebugPreview: Bool {
        #if DEBUG
        return ["offerA", "offerB", "active", "welcome", "success", "manage"].contains(ProcessInfo.processInfo.environment["NB_DEBUG_PRO"] ?? "")
            || ProcessInfo.processInfo.environment["NB_DEBUG_ONB_STEP"] == "membership"
        #else
        return false
        #endif
    }
    private func track(_ event: String, _ props: [String: Any]) {
        Task { await Analytics.shared.track(event, props) }
    }
    private var offerName: String { offer == .intro ? "A" : "B" }
    private var sourceName: String {
        switch presentation { case .welcome: return "WELCOME"; case .profile: return "PROFILE"; default: return "AI" }
    }
    func cardViewed() {
        track("PRO_CARD_VIEW", ["OFFER": offerName, "SOURCE": sourceName])
    }

    func configure() {
        guard !configured else { return }
        configured = true
        guard !isDebugPreview else {
            applyDebugOverride()
            #if DEBUG
            // Once, not in `applyDebugOverride`: `refresh()` re-applies that on every pass
            // and would reopen a page the walk just closed.
            switch ProcessInfo.processInfo.environment["NB_DEBUG_PRO"] {
            case "success": celebrating = true
            case "manage": showingCustomerCenter = true
            default: break
            }
            #endif
            return
        }
        #if canImport(RevenueCat)
        var key = (Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #if DEBUG
        // Test Store is the default development path. Opt into Apple's sandbox
        // explicitly using the configured iOS key; Release always uses that key.
        if ProcessInfo.processInfo.environment["NB_DEBUG_RC_STORE"] != "app_store" {
            key = BillingCatalog.testStoreAPIKey
        }
        let allowTestStore = true
        #else
        let allowTestStore = false
        #endif
        if BillingCatalog.isConfiguredSDKKey(key, allowTestStore: allowTestStore), !Purchases.isConfigured {
            Purchases.logLevel = .warn
            Purchases.configure(withAPIKey: key)
        }
        #endif
        applyDebugOverride()
    }

    func identify(userId: String) async {
        configure()
        customerInfoTask?.cancel()
        identityRevision = UUID()
        let revision = identityRevision
        identifiedUser = userId
        #if canImport(RevenueCat)
        customerInfo = nil
        #endif
        showingCustomerCenter = false
        celebrating = false
        snapshot = .unknown
        snapshot.introClaimed = UserDefaults.standard.bool(forKey: "nb.membership.intro.claimed.\(userId)")
        presentation = nil
        lastMessage = nil
        busy = false
        storeIdentityReady = false
        let previous = storeIdentityTask
        let operation = Task { @MainActor in
            await previous?.value
            guard self.identityRevision == revision, !self.isDebugPreview else { return }
            #if canImport(RevenueCat)
            if Purchases.isConfigured {
                do {
                    _ = try await Purchases.shared.logIn(userId)
                    guard self.identityRevision == revision else { return }
                    self.storeIdentityReady = Purchases.shared.appUserID == userId
                } catch { self.storeIdentityReady = false }
            }
            #endif
        }
        storeIdentityTask = operation
        await operation.value
        guard identityRevision == revision else { return }
        #if canImport(RevenueCat)
        if storeIdentityReady, Purchases.isConfigured {
            customerInfoTask = Task { @MainActor [weak self] in
                for await info in Purchases.shared.customerInfoStream {
                    guard !Task.isCancelled, let self,
                          self.identityRevision == revision, self.isCurrentIdentity else { return }
                    self.customerInfo = info
                }
            }
        }
        #endif
        await refresh()
    }

    func logOut() async {
        customerInfoTask?.cancel()
        customerInfoTask = nil
        identityRevision = UUID()
        identifiedUser = nil
        #if canImport(RevenueCat)
        customerInfo = nil
        #endif
        showingCustomerCenter = false
        celebrating = false
        snapshot = .unknown
        presentation = nil
        lastMessage = nil
        busy = false
        storeIdentityReady = false
        let previous = storeIdentityTask
        let operation = Task { @MainActor in
            await previous?.value
            guard !self.isDebugPreview else { return }
            #if canImport(RevenueCat)
            if Purchases.isConfigured, !Purchases.shared.isAnonymous {
                _ = try? await Purchases.shared.logOut()
            }
            #endif
        }
        storeIdentityTask = operation
        await operation.value
    }

    func refresh() async {
        applyDebugOverride()
        guard !isDebugPreview, isCurrentIdentity, let userId = identifiedUser else { return }
        let revision = identityRevision
        let refresh = UUID()
        refreshRevision = refresh
        let price = snapshot.localizedPrice
        let pricedProductID = snapshot.isActive ? snapshot.productId : nil
        let row = try? await SupabaseClient.shared.select(
            "billing_entitlements", query: [URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "owner", value: "eq.\(userId)"),
                URLQueryItem(name: "entitlement", value: "eq.pro")]).first
        guard identityRevision == revision, refreshRevision == refresh, isCurrentIdentity else { return }
        let claimed = snapshot.introClaimed
        snapshot = row.map { BillingSnapshot.fromServer(row: $0, price: price) } ?? .unknown
        snapshot.localizedPrice = price
        if snapshot.isActive, let productID = snapshot.productId, productID != pricedProductID {
            snapshot.localizedPrice = "—"
        }
        snapshot.introClaimed = claimed || snapshot.introClaimed
        rememberIntroClaim()
        #if canImport(RevenueCat)
        if storeIdentityReady, Purchases.isConfigured,
           let info = try? await Purchases.shared.customerInfo(),
           identityRevision == revision, refreshRevision == refresh, isCurrentIdentity {
            customerInfo = info
        }
        if storeIdentityReady, Purchases.isConfigured, snapshot.isActive, let productID = snapshot.productId {
            // Existing plans may no longer be in the offering. Their price must
            // come from their own product, never the currently promoted plan.
            let products = await Purchases.shared.products([productID])
            guard identityRevision == revision, refreshRevision == refresh, isCurrentIdentity else { return }
            if let product = products.first(where: { $0.productIdentifier == productID }) {
                snapshot.localizedPrice = product.localizedPriceString
            }
        } else if storeIdentityReady, Purchases.isConfigured,
           let info = try? await Purchases.shared.offerings(),
           identityRevision == revision, refreshRevision == refresh, isCurrentIdentity,
           let package = Self.proPackage(in: info) {
            snapshot.localizedPrice = package.localizedPriceString
        }
        #endif
    }

    func allowAI(surface: String = "panel") -> Bool {
        if isPro { return true }
        track("PRO_DENIAL", ["SURFACE": surface.uppercased(), "INTRO_CLAIMED": snapshot.introClaimed])
        if presentation == nil { presentation = .ai }
        return false
    }

    func considerWelcome() {
        if isPro { markWelcomeSeen(); return }
        guard isCurrentIdentity || isDebugPreview, presentation == nil, !hasSeenWelcome else { return }
        presentation = .welcome
    }

    func presentFromProfile() {
        if isPro || hasStoreSubscription { showingCustomerCenter = true; return }
        lastMessage = nil
        presentation = .profile
    }

    func handleServerDenial(introClaimed: Bool?, presentCard: Bool, surface: String = "panel") {
        if let introClaimed { snapshot.introClaimed = snapshot.introClaimed || introClaimed }
        rememberIntroClaim()
        track("PRO_DENIAL", ["SURFACE": surface.uppercased(), "INTRO_CLAIMED": snapshot.introClaimed])
        snapshot.isActive = false
        guard presentCard, presentation == nil else { return }
        presentation = .ai
    }

    func dismiss() {
        track("PRO_CARD_DISMISS", ["OFFER": offerName, "SOURCE": sourceName])
        if presentation == .welcome { markWelcomeSeen() }
        presentation = nil
    }

    func markWelcomeSeen() {
        #if DEBUG
        if isDebugPreview { debugWelcomeSeen = true; return }
        #endif
        guard let userId = identifiedUser ?? SupabaseClient.currentUserIdSnapshot() else { return }
        UserDefaults.standard.set(true, forKey: Self.seenKey(userId))
    }

    /// A paywall may remain visible across account changes. Bind each transaction
    /// to the identity that was verified before presenting the SDK view.
    func preparePaywall() async -> UUID? {
        configure()
        let revision = identityRevision
        await storeIdentityTask?.value
        guard revision == identityRevision, isCurrentIdentity, storeIdentityReady, !isDebugPreview else {
            lastMessage = L("App Store purchases are not configured on this build.")
            return nil
        }
        #if canImport(RevenueCat)
        guard Purchases.isConfigured, Purchases.shared.appUserID == identifiedUser else { return nil }
        return revision
        #else
        return nil
        #endif
    }

    func purchase() async -> BillingPurchaseResult {
        track("PRO_START_TAP", ["OFFER": offerName, "SOURCE": sourceName])
        let capturedOffer = offerName
        let revision = identityRevision
        let previous = storeIdentityTask
        let operation = Task { @MainActor in
            await previous?.value
            guard self.identityRevision == revision else { return BillingPurchaseResult.cancelled }
            return await self.performPurchase()
        }
        storeIdentityTask = Task { _ = await operation.value }
        let result = await operation.value
        let outcome: String
        switch result { case .success: outcome = "SUCCESS"; case .cancelled: outcome = "CANCEL"; case .unavailable: outcome = "UNAVAILABLE"; case .failed: outcome = "FAIL" }
        track("PRO_PURCHASE", ["OUTCOME": outcome, "OFFER": capturedOffer])
        return result
    }

    #if canImport(RevenueCat)
    /// Fetch the current offering only after RevenueCat is bound to the health account.
    func loadPaywallOffer() async throws -> BillingPaywallOffer {
        guard let revision = await preparePaywall() else { throw CancellationError() }
        let offerings = try await Purchases.shared.offerings()
        guard let package = Self.proPackage(in: offerings),
              let period = package.storeProduct.subscriptionPeriod, period.value == 1,
              period.unit == .year || period.unit == .month else {
            throw NSError(domain: "Billing", code: 1, userInfo: [NSLocalizedDescriptionKey:
                L("App Store purchases are not configured on this build.")])
        }
        let product = package.storeProduct
        let yearly = period.unit == .year
        var intro: String?
        if let discount = product.introductoryDiscount,
           discount.paymentMode == .freeTrial,
           discount.subscriptionPeriod.unit == .month,
           discount.subscriptionPeriod.value * discount.numberOfPeriods == 1,
           await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: product) == .eligible {
            intro = L(yearly ? "1 month free, then %@ / year" : "1 month free, then %@ / month",
                      product.localizedPriceString)
        }
        guard revision == identityRevision, isCurrentIdentity, storeIdentityReady,
              Purchases.shared.appUserID == identifiedUser else { throw CancellationError() }
        let currencyFormatter = product.priceFormatter
        let formatter = product.priceFormatter?.copy() as? NumberFormatter
        let currency = formatter?.currencySymbol ?? ""
        formatter?.numberStyle = .decimal
        formatter?.minimumFractionDigits = 0
        formatter?.maximumFractionDigits = 2
        let amount = formatter?.string(from: NSDecimalNumber(decimal: product.price))
        var perMonth: String?
        var list: String?
        if yearly {
            // The year divided by twelve, rounded down like every store does: 19.99 → 1.66.
            var twelfth = product.price / 12
            var monthly = Decimal()
            NSDecimalRound(&monthly, &twelfth, 2, .down)
            perMonth = currencyFormatter?.string(from: NSDecimalNumber(decimal: monthly))
            // What "80% OFF" is off: the year ÷ 0.2, taken to the nearest .99 (19.99 → 99.99).
            var whole = Decimal()
            var full = product.price * 100 / Decimal(100 - BillingCatalog.yearlySavingsPercent)
            NSDecimalRound(&whole, &full, 0, .up)
            list = currencyFormatter?.string(from: NSDecimalNumber(decimal: whole - Decimal(string: "0.01")!))
        }
        return BillingPaywallOffer(identity: revision, package: package,
            priceAmount: amount ?? product.localizedPriceString,
            currencySymbol: amount == nil ? "" : currency,
            localizedPrice: product.localizedPriceString, isYearly: yearly,
            perMonthPrice: perMonth, listPrice: list, introductoryText: intro)
    }

    /// Own the entire SDK operation independently of the Paywall view lifetime.
    func purchase(package: Package, expectedIdentity: UUID) async -> BillingPurchaseResult {
        guard expectedIdentity == identityRevision else { return .cancelled }
        track("PRO_START_TAP", ["OFFER": offerName, "SOURCE": sourceName])
        let capturedOffer = offerName
        let previous = storeIdentityTask
        let operation = Task { @MainActor in
            await previous?.value
            guard self.identityRevision == expectedIdentity else { return BillingPurchaseResult.cancelled }
            return await self.performPurchase(package: package)
        }
        storeIdentityTask = Task { _ = await operation.value }
        let result = await operation.value
        let outcome: String
        switch result { case .success: outcome = "SUCCESS"; case .cancelled: outcome = "CANCEL"; case .unavailable: outcome = "UNAVAILABLE"; case .failed: outcome = "FAIL" }
        track("PRO_PURCHASE", ["OUTCOME": outcome, "OFFER": capturedOffer])
        return result
    }
    #endif

    private func performPurchase() async -> BillingPurchaseResult {
        #if canImport(RevenueCat)
        return await performPurchase(package: nil)
        #else
        return .unavailable
        #endif
    }

    #if canImport(RevenueCat)
    private func performPurchase(package selectedPackage: Package?) async -> BillingPurchaseResult {
        guard !busy, !isDebugPreview, isCurrentIdentity, storeIdentityReady else { return .unavailable }
        let revision = identityRevision
        // Restoring from the manage page while already Pro is not an occasion.
        let wasPro = isPro
        busy = true
        lastMessage = nil
        defer { if identityRevision == revision { busy = false } }
        #if canImport(RevenueCat)
        guard Purchases.isConfigured else { return .unavailable }
        do {
            let package: Package
            if let selectedPackage {
                package = selectedPackage
            } else {
                let offerings = try await Purchases.shared.offerings()
                guard let pro = Self.proPackage(in: offerings) else { return .unavailable }
                package = pro
            }
            guard identityRevision == revision, isCurrentIdentity else { return .cancelled }
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            guard identityRevision == revision, isCurrentIdentity else { return .cancelled }
            await syncAfterPurchase()
            guard identityRevision == revision, isCurrentIdentity else { return .cancelled }
            if isPro {
                markWelcomeSeen()
                celebrating = !wasPro
                presentation = nil
                return .success
            }
            return .failed(L("Purchase did not activate yet. Try Restore."))
        } catch {
            guard identityRevision == revision, isCurrentIdentity else { return .cancelled }
            if Self.isCancel(error) { return .cancelled }
            return .failed(error.localizedDescription)
        }
        #else
        return .unavailable
        #endif
    }

    #endif

    func restore(expectedIdentity: UUID? = nil) async -> BillingPurchaseResult {
        if let expectedIdentity, expectedIdentity != identityRevision { return .cancelled }
        track("PRO_RESTORE_TAP", ["OFFER": offerName, "SOURCE": sourceName])
        let revision = identityRevision
        let previous = storeIdentityTask
        let operation = Task { @MainActor in
            await previous?.value
            guard self.identityRevision == revision else { return BillingPurchaseResult.cancelled }
            return await self.performRestore()
        }
        storeIdentityTask = Task { _ = await operation.value }
        return await operation.value
    }

    private func performRestore() async -> BillingPurchaseResult {
        guard !busy, !isDebugPreview, isCurrentIdentity, storeIdentityReady else { return .unavailable }
        let revision = identityRevision
        // Restoring from the manage page while already Pro is not an occasion.
        let wasPro = isPro
        busy = true
        lastMessage = nil
        defer { if identityRevision == revision { busy = false } }
        #if canImport(RevenueCat)
        guard Purchases.isConfigured else { return .unavailable }
        do {
            _ = try await Purchases.shared.restorePurchases()
            guard identityRevision == revision, isCurrentIdentity else { return .cancelled }
            await syncAfterPurchase()
            guard identityRevision == revision, isCurrentIdentity else { return .cancelled }
            if isPro {
                markWelcomeSeen()
                celebrating = !wasPro
                presentation = nil
                return .success
            }
            return .failed(L("No Pro purchase to restore for this health account."))
        } catch {
            guard identityRevision == revision, isCurrentIdentity else { return .cancelled }
            if Self.isCancel(error) { return .cancelled }
            let code = (error as NSError).code
            if code == RevenueCat.ErrorCode.receiptAlreadyInUseError.rawValue
                || code == RevenueCat.ErrorCode.receiptInUseByOtherSubscriberError.rawValue {
                return .failed(L("No Pro purchase to restore for this health account."))
            }
            return .failed(error.localizedDescription)
        }
        #else
        return .unavailable
        #endif
    }

    /// After the store's own sheet closes: ask the server to re-read RevenueCat.
    func syncFromStore() async {
        guard !isDebugPreview, isCurrentIdentity else { return }
        await syncAfterPurchase()
    }

    private func syncAfterPurchase() async {
        if let userId = identifiedUser ?? SupabaseClient.currentUserIdSnapshot() {
            _ = try? await SupabaseClient.shared.callFunction(
                "billing-sync", payload: [:], expectedOwner: userId)
        }
        await refresh()
    }

    private func rememberIntroClaim() {
        guard snapshot.introClaimed, isCurrentIdentity, !isDebugPreview, let userId = identifiedUser else { return }
        UserDefaults.standard.set(true, forKey: "nb.membership.intro.claimed.\(userId)")
    }

    private var hasSeenWelcome: Bool {
        #if DEBUG
        if isDebugPreview { return debugWelcomeSeen }
        #endif
        guard let userId = identifiedUser ?? SupabaseClient.currentUserIdSnapshot() else { return false }
        return UserDefaults.standard.bool(forKey: Self.seenKey(userId))
    }

    private static func seenKey(_ userId: String) -> String {
        "nb.membership.card.seen.\(userId)"
    }

    private func applyDebugOverride() {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["NB_DEBUG_PRO"] {
        case "active", "success", "manage":
            snapshot = BillingSnapshot(
                isActive: true, introClaimed: true, periodType: "trial",
                expiresAt: Date().addingTimeInterval(20 * 24 * 3600),
                localizedPrice: BillingCatalog.fallbackPrice, willRenew: true,
                productId: BillingCatalog.yearlyProductID)
        case "offerB":
            snapshot = BillingSnapshot(
                isActive: false, introClaimed: true, periodType: "normal",
                expiresAt: Date().addingTimeInterval(-3600),
                localizedPrice: BillingCatalog.fallbackPrice, willRenew: false)
        case "offerA", "welcome":
            snapshot = BillingSnapshot.unknown
        default:
            break
        }
        #endif
    }

    #if canImport(RevenueCat)
    private static func proPackage(in offerings: Offerings?) -> Package? {
        guard let packages = offerings?.current?.availablePackages else { return nil }
        // The dashboard's current offering controls which packages exist; the catalog
        // order says which one the paywall sells when it carries more than one.
        for id in BillingCatalog.sellableProductIDs {
            if let package = packages.first(where: { $0.storeProduct.productIdentifier == id }) { return package }
        }
        return nil
    }

    private static func isCancel(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.code == RevenueCat.ErrorCode.purchaseCancelledError.rawValue
    }
    #endif
}
