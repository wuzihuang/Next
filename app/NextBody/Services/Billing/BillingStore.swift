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

/// iOS store purchases. The table on the server is what `/turn` and `/asr` believe.
@MainActor
final class BillingStore: ObservableObject {
    static let shared = BillingStore()

    @Published private(set) var snapshot = BillingSnapshot.unknown
    @Published var presentation: MembershipPresentation?
    @Published private(set) var busy = false
    @Published var lastMessage: String?

    var isPro: Bool { snapshot.isActive }
    var offer: BillingOffer { snapshot.offer }

    private var identifiedUser: String?
    private var configured = false

    func configure() {
        guard !configured else { return }
        configured = true
        #if canImport(RevenueCat)
        let key = (Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !key.isEmpty, !Purchases.isConfigured {
            Purchases.logLevel = .warn
            Purchases.configure(withAPIKey: key)
        }
        #endif
        applyDebugOverride()
    }

    func identify(userId: String) async {
        configure()
        identifiedUser = userId
        #if canImport(RevenueCat)
        if Purchases.isConfigured {
            _ = try? await Purchases.shared.logIn(userId)
        }
        #endif
        await refresh()
    }

    func logOut() async {
        #if canImport(RevenueCat)
        if Purchases.isConfigured {
            _ = try? await Purchases.shared.logOut()
        }
        #endif
        identifiedUser = nil
        snapshot = .unknown
        presentation = nil
        applyDebugOverride()
    }

    func refresh() async {
        applyDebugOverride()
        #if DEBUG
        if ProcessInfo.processInfo.environment["NB_DEBUG_PRO"] != nil { return }
        #endif
        var price = snapshot.localizedPrice
        #if canImport(RevenueCat)
        if Purchases.isConfigured, let info = try? await Purchases.shared.offerings() {
            if let package = Self.monthlyPackage(in: info) {
                price = package.localizedPriceString
            }
        }
        #endif
        if let row = try? await SupabaseClient.shared.select(
            "billing_entitlements",
            query: [URLQueryItem(name: "select", value: "*")]
        ).first {
            snapshot = BillingSnapshot.fromServer(row: row, price: price)
        } else {
            snapshot.localizedPrice = price
        }
    }

    func allowAI() -> Bool {
        if isPro { return true }
        if presentation == nil { presentation = .ai }
        return false
    }

    func considerWelcome() {
        guard !isPro, presentation == nil, !hasSeenWelcome else { return }
        presentation = .welcome
    }

    func presentFromProfile() {
        if isPro { return }
        presentation = .profile
    }

    func handleServerDenial(introClaimed: Bool?, presentCard: Bool) {
        if let introClaimed { snapshot.introClaimed = introClaimed }
        snapshot.isActive = false
        guard presentCard, presentation == nil else { return }
        presentation = .ai
    }

    func dismiss() {
        if presentation == .welcome { markWelcomeSeen() }
        presentation = nil
    }

    func markWelcomeSeen() {
        guard let userId = identifiedUser ?? SupabaseClient.currentUserIdSnapshot() else { return }
        UserDefaults.standard.set(true, forKey: Self.seenKey(userId))
    }

    func purchase() async -> BillingPurchaseResult {
        busy = true
        lastMessage = nil
        defer { busy = false }
        #if canImport(RevenueCat)
        guard Purchases.isConfigured else { return .unavailable }
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let package = Self.monthlyPackage(in: offerings) else {
                return .unavailable
            }
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            await syncAfterPurchase()
            if isPro {
                markWelcomeSeen()
                presentation = nil
                return .success
            }
            return .failed(L("Purchase did not activate yet. Try Restore."))
        } catch {
            if Self.isCancel(error) { return .cancelled }
            return .failed(error.localizedDescription)
        }
        #else
        return .unavailable
        #endif
    }

    func restore() async -> BillingPurchaseResult {
        busy = true
        lastMessage = nil
        defer { busy = false }
        #if canImport(RevenueCat)
        guard Purchases.isConfigured else { return .unavailable }
        do {
            _ = try await Purchases.shared.restorePurchases()
            await syncAfterPurchase()
            if isPro {
                markWelcomeSeen()
                presentation = nil
                return .success
            }
            return .failed(L("No Pro purchase to restore for this health account."))
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .unavailable
        #endif
    }

    private func syncAfterPurchase() async {
        if let userId = identifiedUser ?? SupabaseClient.currentUserIdSnapshot() {
            _ = try? await SupabaseClient.shared.callFunction(
                "billing-sync", payload: [:], expectedOwner: userId)
        }
        await refresh()
    }

    private var hasSeenWelcome: Bool {
        guard let userId = identifiedUser ?? SupabaseClient.currentUserIdSnapshot() else { return false }
        return UserDefaults.standard.bool(forKey: Self.seenKey(userId))
    }

    private static func seenKey(_ userId: String) -> String {
        "nb.membership.card.seen.\(userId)"
    }

    private func applyDebugOverride() {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["NB_DEBUG_PRO"] {
        case "active":
            snapshot = BillingSnapshot(
                isActive: true, introClaimed: true, periodType: "trial",
                expiresAt: Date().addingTimeInterval(20 * 24 * 3600),
                localizedPrice: BillingCatalog.fallbackPrice, willRenew: true)
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
    private static func monthlyPackage(in offerings: Offerings?) -> Package? {
        guard let offerings else { return nil }
        let packages = (offerings.current?.availablePackages ?? [])
            + offerings.all.values.flatMap(\.availablePackages)
        return packages.first { $0.storeProduct.productIdentifier == BillingCatalog.monthlyProductID }
            ?? offerings.current?.monthly
            ?? packages.first
    }

    private static func isCancel(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == "RevenueCat.ErrorCode" && ns.code == 1
    }
    #endif
}
