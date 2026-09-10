import XCTest
@testable import NextBodySyncCore

final class BandHistoryReadCacheTests: XCTestCase {
    private let scope = BandHistoryReadCache.Scope(account: "alice", binding: "band-a", device: "sdk-a")
    private let now = Date(timeIntervalSince1970: 10_000)

    func testCompletedNativeDomainsAreReusedUntilRefreshFinishes() {
        let cache = BandHistoryReadCache()
        cache.beginRefresh(scope: scope)
        let token = cache.generation(scope: scope)
        cache.record(.complete, for: .all, generation: token, at: now)
        XCTAssertEqual(cache.status(for: .all, scope: scope, at: now.addingTimeInterval(600)), .complete)
        cache.endRefresh()
        XCTAssertNil(cache.status(for: .all, scope: scope, at: now.addingTimeInterval(600)))
        cache.beginRefresh(scope: scope)
        XCTAssertNil(cache.status(for: .all, scope: scope, at: now))
    }

    func testIndependentFailureDoesNotRepeatSuccessfulDomainsOrInventCompleteness() {
        let cache = BandHistoryReadCache()
        cache.beginRefresh(scope: scope)
        let token = cache.generation(scope: scope)
        cache.record(.complete, for: .hrv, generation: token, at: now)
        cache.record(.failed, for: .temperature, generation: token, at: now)
        cache.record(.unsupported, for: .oxygen, generation: token, at: now)
        XCTAssertEqual(cache.status(for: .hrv, scope: scope, at: now.addingTimeInterval(600)), .complete)
        XCTAssertNil(cache.status(for: .temperature, scope: scope, at: now))
        XCTAssertEqual(cache.status(for: .oxygen, scope: scope, at: now), .unsupported)
        cache.record(.complete, for: .temperature, generation: token, at: now.addingTimeInterval(600))
        XCTAssertEqual(cache.status(for: .temperature, scope: scope, at: now.addingTimeInterval(700)), .complete)
    }

    func testScopeChangesAndConnectionInvalidationRejectStaleCompletions() {
        for other in [BandHistoryReadCache.Scope(account: "bob", binding: "band-a", device: "sdk-a"),
                      .init(account: "alice", binding: "band-b", device: "sdk-a"),
                      .init(account: "alice", binding: "band-a", device: "sdk-b"),
                      .init(account: "alice", binding: "band-a", device: "sdk-a", sessionGeneration: UUID())] {
            let cache = BandHistoryReadCache()
            cache.beginRefresh(scope: scope)
            let old = cache.generation(scope: scope)
            cache.record(.complete, for: .all, generation: old, at: now)
            XCTAssertNil(cache.status(for: .all, scope: other, at: now))
            cache.record(.complete, for: .all, generation: old, at: now)
            XCTAssertNil(cache.status(for: .all, scope: other, at: now))
        }
        let cache = BandHistoryReadCache()
        cache.beginRefresh(scope: scope)
        let old = cache.generation(scope: scope)
        cache.invalidate()
        cache.record(.complete, for: .all, generation: old, at: now)
        XCTAssertNil(cache.status(for: .all, scope: scope, at: now))
    }

    func testOutsideRefreshReceiptExpiresAndNeverReusesFutureTimestamps() {
        let cache = BandHistoryReadCache()
        let token = cache.generation(scope: scope)
        cache.record(.complete, for: .all, generation: token, at: now)
        XCTAssertEqual(cache.status(for: .all, scope: scope, at: now.addingTimeInterval(59)), .complete)
        XCTAssertNil(cache.status(for: .all, scope: scope, at: now.addingTimeInterval(60)))
        XCTAssertNil(cache.status(for: .all, scope: scope, at: now.addingTimeInterval(-1)))
    }

    func testReusedPageRetainsActualNativeStartAndCompletionAcrossSlowReads() throws {
        let cache = BandHistoryReadCache()
        cache.beginRefresh(scope: scope)
        let token = cache.generation(scope: scope)
        let completed = now.addingTimeInterval(360)
        cache.record(.complete, for: .all, generation: token, startedAt: now, at: completed)
        let reused = try XCTUnwrap(cache.receipt(for: .all, scope: scope, at: now.addingTimeInterval(1200)))
        XCTAssertEqual(reused.startedAt, now)
        XCTAssertEqual(reused.completedAt, completed, "database query time cannot promote an old snapshot to a new revision")
    }

}
