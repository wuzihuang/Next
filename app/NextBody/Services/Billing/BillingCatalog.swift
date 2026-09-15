import Foundation

/// App Store / RevenueCat identifiers. The store listing is the price source;
/// `$6` is only the fallback the card prints before a package loads.
enum BillingCatalog {
    static let entitlementID = "pro"
    static let monthlyProductID = "hoop_pro_monthly"
    static let fallbackPrice = "$6"
    static let bundleID = "com.nextbody.hoop"
}
