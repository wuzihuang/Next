import XCTest
@testable import NextBodyBillingCore

final class BillingOfferTests: XCTestCase {
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
            "expires_at": "2026-10-15T00:00:00Z",
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
}
