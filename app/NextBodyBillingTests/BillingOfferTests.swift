import XCTest
@testable import NextBodyBillingCore

final class BillingOfferTests: XCTestCase {
    func testOnlyIOSPublicKeysConfigurePurchases() {
        XCTAssertTrue(BillingCatalog.isConfiguredSDKKey("appl_example"))
        for key in ["", "$(REVENUECAT_API_KEY)", "sk_example", "goog_example", "appl_", "appl_bad key"] {
            XCTAssertFalse(BillingCatalog.isConfiguredSDKKey(key), key)
        }
    }

    func testTestStoreKeysRequireExplicitDebugAllowance() {
        XCTAssertFalse(BillingCatalog.isConfiguredSDKKey("test_example"))
        XCTAssertTrue(BillingCatalog.isConfiguredSDKKey("test_example", allowTestStore: true))
        XCTAssertFalse(BillingCatalog.isConfiguredSDKKey("sk_example", allowTestStore: true))
        XCTAssertFalse(BillingCatalog.isConfiguredSDKKey("test_", allowTestStore: true))
        XCTAssertEqual(BillingCatalog.entitlementID, "next_pro")
    }

    func testUnusedIntroIsOfferA() {
        let snap = BillingSnapshot.unknown
        XCTAssertEqual(snap.offer, .intro)
        XCTAssertFalse(snap.isActive)
        XCTAssertEqual(BillingCopy.title(for: snap.offer), "One month of Pro, free")
    }

    func testClaimedIntroWithoutEntitlementIsOfferB() {
        var snap = BillingSnapshot.unknown
        snap.introClaimed = true
        XCTAssertEqual(snap.offer, .pay)
        XCTAssertFalse(snap.isActive)
        XCTAssertNotEqual(BillingCopy.title(for: .pay), "One month of Pro, free")
        XCTAssertTrue(BillingCopy.conditionKey(for: .pay).contains("already been claimed"))
    }

    func testServerRowWithFutureExpiryIsActive() {
        let row: [String: Any] = [
            "product_id": "hoop_pro_monthly",
            "period_type": "trial",
            "expires_at": ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)),
            "intro_claimed_at": "2026-09-15T00:00:00Z",
            "will_renew": true,
        ]
        let snap = BillingSnapshot.fromServer(row: row, price: "$6")
        XCTAssertTrue(snap.isActive)
        XCTAssertTrue(snap.introClaimed)
        XCTAssertTrue(snap.isTrial)
        XCTAssertEqual(snap.offer, .pay)
    }

    func testExpiredRowKeepsIntroClaimed() {
        let row: [String: Any] = [
            "product_id": "hoop_pro_monthly",
            "period_type": "normal",
            "expires_at": "2026-08-01T00:00:00Z",
            "intro_claimed_at": "2026-07-01T00:00:00Z",
            "will_renew": false,
        ]
        let snap = BillingSnapshot.fromServer(row: row, price: "$6")
        XCTAssertFalse(snap.isActive)
        XCTAssertTrue(snap.introClaimed)
        XCTAssertEqual(snap.offer, .pay)
    }

    func testEmptySubscriberCannotGrantLifetimePro() {
        for row: [String: Any] in [[:], ["expires_at": NSNull(), "product_id": NSNull()],
                                   ["product_id": ""], ["product_id": "   "]] {
            XCTAssertFalse(BillingSnapshot.fromServer(row: row, price: "$6").isActive)
        }
    }

    func testMalformedExpiryDoesNotBecomeLifetimeGrant() {
        let row: [String: Any] = ["product_id": "hoop_pro_monthly", "expires_at": "broken"]
        XCTAssertFalse(BillingSnapshot.fromServer(row: row, price: "$6").isActive)
    }

    func testExplicitNonExpiringProductAndLocalizedPrice() {
        let row: [String: Any] = ["product_id": "hoop_pro_monthly", "expires_at": NSNull()]
        let snapshot = BillingSnapshot.fromServer(row: row, price: "¥42.00")
        XCTAssertTrue(snapshot.isActive)
        XCTAssertEqual(snapshot.localizedPrice, "¥42.00")
        XCTAssertEqual(snapshot.offer, .intro)
    }
}
