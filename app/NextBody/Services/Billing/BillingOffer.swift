import Foundation

/// Health-account history for analytics and DEBUG card fixtures.
/// The native paywall uses actual store offer eligibility from RevenueCat.
enum BillingOffer: String, Equatable {
    case intro
    case pay
}

struct BillingSnapshot: Equatable {
    var isActive: Bool
    var introClaimed: Bool
    var periodType: String?
    var expiresAt: Date?
    var localizedPrice: String
    var willRenew: Bool
    var productId: String? = nil

    var offer: BillingOffer { introClaimed ? .pay : .intro }

    /// Billed once a year. A missing product (fixtures, no row yet) is read as the plan on sale.
    var isYearly: Bool { productId.map { BillingCatalog.yearlyProductIDs.contains($0) } ?? true }

    var isTrial: Bool {
        let period = periodType?.lowercased() ?? ""
        return isActive && (period == "trial" || period == "intro" || period == "introductory")
    }

    static let unknown = BillingSnapshot(
        isActive: false,
        introClaimed: false,
        periodType: nil,
        expiresAt: nil,
        localizedPrice: BillingCatalog.fallbackPrice,
        willRenew: false
    )

    static func fromServer(row: [String: Any], price: String) -> BillingSnapshot {
        let expires = Self.date(row["expires_at"])
        let product = row["product_id"] as? String
        let hasProduct = !(product?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasNoExpiry = row["expires_at"] == nil || row["expires_at"] is NSNull
        let active = (expires.map { $0 > Date() } ?? false) || (hasNoExpiry && hasProduct)
        return BillingSnapshot(
            isActive: active,
            introClaimed: row["intro_claimed_at"] != nil && !(row["intro_claimed_at"] is NSNull),
            periodType: row["period_type"] as? String,
            expiresAt: expires,
            localizedPrice: price,
            willRenew: row["will_renew"] as? Bool ?? false,
            productId: hasProduct ? product : nil
        )
    }

    static func date(_ value: Any?) -> Date? {
        if value is NSNull || value == nil { return nil }
        if let text = value as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: text) { return date }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: text)
        }
        return nil
    }
}

enum BillingCopy {
    static func title(for offer: BillingOffer) -> String {
        switch offer {
        case .intro: return "One month of Pro, free"
        case .pay: return "NextBody Pro"
        }
    }

    static func conditionKey(for offer: BillingOffer) -> String {
        switch offer {
        case .intro:
            return "Bind App Store payment to claim it. After one month, %@ / year."
        case .pay:
            return "%@ / year. The free month has already been claimed on this health account."
        }
    }

    static func cta(for offer: BillingOffer) -> String {
        switch offer {
        case .intro: return "START PRO"
        case .pay: return "START PRO"
        }
    }
}
