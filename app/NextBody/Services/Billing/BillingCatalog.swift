import Foundation

/// App Store / RevenueCat identifiers. The store listing is the price source;
/// `$19.99` is only the fallback the card prints before a package loads.
///
/// Sold since 2026-09-20: the yearly plan. The monthly ids stay so an existing
/// monthly subscriber is still recognised and their renewal still counts.
enum BillingCatalog {
    static let entitlementID = "next_pro"
    static let yearlyProductID = "hoop_pro_yearly"
    static let testYearlyProductID = "yearly"
    static let monthlyProductID = "hoop_pro_monthly"
    static let testMonthlyProductID = "monthly"
    /// Offering packages the paywall will sell, best first.
    static let sellableProductIDs = [yearlyProductID, testYearlyProductID, monthlyProductID, testMonthlyProductID]
    static let yearlyProductIDs: Set<String> = [yearlyProductID, testYearlyProductID]
    static let fallbackPrice = "$19.99"
    static let fallbackMonthlyEquivalent = "$1.66"
    static let fallbackListPrice = "$99.99"
    /// The card's "80% OFF": the year is sold at a fifth of its list price.
    static let yearlySavingsPercent = 80
    static let bundleID = "com.nextbody.hoop"

    #if DEBUG
    static let testStoreAPIKey = "test_vWlZrJXAfSZQkCVbGYxXvTcKSnf"
    #endif

    static func isConfiguredSDKKey(_ key: String, allowTestStore: Bool = false) -> Bool {
        let prefix = key.hasPrefix("appl_") ? "appl_" : (allowTestStore && key.hasPrefix("test_") ? "test_" : "")
        return !prefix.isEmpty && key.count > prefix.count && !key.contains(where: { $0.isWhitespace })
    }
}
