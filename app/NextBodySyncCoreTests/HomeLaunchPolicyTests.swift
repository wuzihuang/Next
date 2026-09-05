import XCTest
@testable import NextBodySyncCore

final class HomeLaunchPolicyTests: XCTestCase {
    func testSameUserDaySnapshotPaintsImmediately() {
        XCTAssertTrue(HomeLaunchPolicy.shouldPaintToday(
            snapshotDayKey: "2026-09-04",
            currentDayKey: "2026-09-04"))
    }

    func testPreviousUserDaySnapshotIsNotTodaysNumbers() {
        XCTAssertFalse(HomeLaunchPolicy.shouldPaintToday(
            snapshotDayKey: "2026-09-03",
            currentDayKey: "2026-09-04"))
    }

    func testFastLoadOnlyAsksTodayAndYesterday() {
        XCTAssertEqual(HomeLaunchPolicy.fastLoadLookbackDays, 1)
    }

    func testAccessTokenUsableWhenExpiryIsInTheFuture() {
        let token = Self.jwt(sub: "user-1", email: "a@b.c", exp: 2_000_000_000)
        XCTAssertTrue(HomeLaunchPolicy.isAccessTokenUsable(
            token, now: Date(timeIntervalSince1970: 1_900_000_000)))
        XCTAssertEqual(HomeLaunchPolicy.jwtSubject(token), "user-1")
        XCTAssertEqual(HomeLaunchPolicy.jwtEmail(token), "a@b.c")
    }

    func testAccessTokenRejectedInsideLeewayAndWhenExpired() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expiring = Self.jwt(sub: "user-1", email: "a@b.c",
                                exp: Int(now.timeIntervalSince1970) + 10)
        let expired = Self.jwt(sub: "user-1", email: "a@b.c",
                               exp: Int(now.timeIntervalSince1970) - 1)
        XCTAssertFalse(HomeLaunchPolicy.isAccessTokenUsable(expiring, now: now))
        XCTAssertFalse(HomeLaunchPolicy.isAccessTokenUsable(expired, now: now))
        XCTAssertFalse(HomeLaunchPolicy.isAccessTokenUsable("not-a-jwt", now: now))
    }

    func testPostgrestInSkipsAnEmptyIdList() {
        XCTAssertNil(HomeLaunchPolicy.postgrestIn([]))
        XCTAssertNil(HomeLaunchPolicy.postgrestIn(["", ""]))
        XCTAssertEqual(
            HomeLaunchPolicy.postgrestIn(["aaa", "bbb"]),
            "in.(aaa,bbb)")
    }

    private static func jwt(sub: String, email: String, exp: Int) -> String {
        func encode(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return encode(["alg": "none", "typ": "JWT"])
            + "."
            + encode(["sub": sub, "email": email, "exp": exp])
            + ".sig"
    }
}

final class HomeReadIsolationTests: XCTestCase {
    func testLateReadCannotApplyAfterAccountChangeOrNewerRefresh() {
        XCTAssertFalse(HomeLaunchPolicy.acceptsRead(account: "a", currentAccount: "b", generation: 1, currentGeneration: 1))
        XCTAssertFalse(HomeLaunchPolicy.acceptsRead(account: "a", currentAccount: "a", generation: 1, currentGeneration: 2))
        XCTAssertTrue(HomeLaunchPolicy.acceptsRead(account: "a", currentAccount: "a", generation: 2, currentGeneration: 2))
        XCTAssertFalse(HomeLaunchPolicy.acceptsRead(account: nil, currentAccount: nil, generation: 1, currentGeneration: 1))
    }
}


final class AccountDisplayLifecycleTests: XCTestCase {
    func testSignedOutDisplayRejectsOldAccountAndResignedInStaleRequests() {
        XCTAssertFalse(HomeLaunchPolicy.acceptsRead(account: "owner", currentAccount: nil,
            generation: 4, currentGeneration: 5))
        XCTAssertFalse(HomeLaunchPolicy.acceptsRead(account: "owner", currentAccount: "owner",
            generation: 4, currentGeneration: 5))
        XCTAssertTrue(HomeLaunchPolicy.acceptsRead(account: "owner", currentAccount: "owner",
            generation: 5, currentGeneration: 5))
    }
}

final class LegacySummaryReadTests: XCTestCase {
    func testExistingHistoryWithoutNewRevisionStillLoadsAfterUpgrade() {
        XCTAssertTrue(HomeLaunchPolicy.shouldRefreshSummary(revision: nil, cachedRevision: nil, hasCachedRow: false))
        XCTAssertTrue(HomeLaunchPolicy.shouldRefreshSummary(revision: nil, cachedRevision: nil, hasCachedRow: true))
        XCTAssertFalse(HomeLaunchPolicy.shouldRefreshSummary(revision: "r1", cachedRevision: "r1", hasCachedRow: true))
        XCTAssertTrue(HomeLaunchPolicy.shouldRefreshSummary(revision: "r2", cachedRevision: "r1", hasCachedRow: true))
        XCTAssertTrue(HomeLaunchPolicy.shouldRefreshSummary(revision: "r1", cachedRevision: "r1", hasCachedRow: false))
    }
}

final class EvidenceSettlementPolicyTests: XCTestCase {
    func testPersistedDirtyResultRequiresSettlementEvenWhenOutboxIsEmpty() {
        XCTAssertTrue(HomeLaunchPolicy.needsEvidenceSettlement(pending: [true]))
        XCTAssertTrue(HomeLaunchPolicy.needsEvidenceSettlement(pending: [false, true]))
    }
    func testCurrentAcknowledgedResultsDoNotSettleAgain() {
        XCTAssertFalse(HomeLaunchPolicy.needsEvidenceSettlement(pending: [false]))
        XCTAssertFalse(HomeLaunchPolicy.needsEvidenceSettlement(pending: [false, false]))
    }
    func testMissingLegacyOrUnknownStatusNeedsIdempotentSettlement() {
        XCTAssertTrue(HomeLaunchPolicy.needsEvidenceSettlement(pending: nil))
        XCTAssertTrue(HomeLaunchPolicy.needsEvidenceSettlement(pending: []))
        XCTAssertTrue(HomeLaunchPolicy.needsEvidenceSettlement(pending: [nil]))
    }
}
