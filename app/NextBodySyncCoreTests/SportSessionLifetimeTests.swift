import XCTest
@testable import NextBodySyncCore

final class SportSessionLifetimeTests: XCTestCase {
    @MainActor func testFinalCloseWaitsForCancelledNativeOpenAndReaderCleanup() async {
        var order: [String] = []
        var callback: CheckedContinuation<Void, Never>?
        let opening = Task { @MainActor in
            await withCheckedContinuation { callback = $0 }
            order.append("open callback")
        }
        while callback == nil { await Task.yield() }
        let reading = Task { @MainActor in
            while !Task.isCancelled { await Task.yield() }
            order.append("reader cleanup")
        }
        let stop = Task { @MainActor in
            await SportSessionTaskFence.cancelAndWait(opening, reading)
            order.append("final stop")
        }
        while !opening.isCancelled { await Task.yield() }
        XCTAssertFalse(order.contains("final stop"))
        callback?.resume()
        await stop.value
        XCTAssertEqual(order.last, "final stop")
        XCTAssertTrue(order.contains("reader cleanup"))
    }

    func testDisconnectedRetryBacksOffAndRemainsBounded() {
        XCTAssertEqual(SportReconnectPolicy.delay(failures: 1), 3)
        XCTAssertEqual(SportReconnectPolicy.delay(failures: 2), 6)
        XCTAssertEqual(SportReconnectPolicy.delay(failures: 20), 30)
    }

    @MainActor func testBusyAttemptSettlesTwiceThenOpensWithoutClose() async throws {
        var calls: [String] = []
        var disposition = SportStartDisposition.notIssued
        var attempts = 0
        try await SportStartRetry.perform(settle: { calls.append("settle") }, start: {
            calls.append("start")
            attempts += 1
            if attempts == 1 { throw Busy.busy }
        }, isBusy: { $0 is Busy }, disposition: { disposition = $0 })
        XCTAssertEqual(calls, ["settle", "start", "settle", "start"])
        XCTAssertTrue(disposition.needsCleanup)
    }

    @MainActor func testRepeatedBusyStopsAfterSecondAttemptWithoutCleanup() async {
        var attempts = 0
        var disposition = SportStartDisposition.notIssued
        do {
            try await SportStartRetry.perform(settle: {}, start: {
                attempts += 1
                throw Busy.busy
            }, isBusy: { $0 is Busy }, disposition: { disposition = $0 })
            XCTFail("Busy must surface after its single retry")
        } catch { XCTAssertTrue(error is Busy) }
        XCTAssertEqual(attempts, 2)
        XCTAssertFalse(disposition.needsCleanup)
    }

    private enum Busy: Error { case busy }

    func testBusyOnlyJoinsWhenFreshSportStateProvesRunning() {
        XCTAssertTrue(SportStartDisposition.canJoin(observedRunState: 1))
        XCTAssertFalse(SportStartDisposition.canJoin(observedRunState: nil))
        XCTAssertFalse(SportStartDisposition.canJoin(observedRunState: 0))
        XCTAssertFalse(SportStartDisposition.canJoin(observedRunState: 2))
    }

    func testBusyRetriesOnceAndDoesNotRequireDestructiveCleanup() {
        XCTAssertTrue(SportStartDisposition.shouldRetryBusy(previousRetries: 0))
        XCTAssertFalse(SportStartDisposition.shouldRetryBusy(previousRetries: 1))
        XCTAssertFalse(SportStartDisposition.busy.needsCleanup)
        XCTAssertFalse(SportStartDisposition.notIssued.needsCleanup)
        XCTAssertTrue(SportStartDisposition.issued.needsCleanup)
        XCTAssertTrue(SportStartDisposition.opened.needsCleanup)
    }

    func testRestartOfSameOwnerRejectsPreviousLifetime() {
        let first = SportSessionLifetime(account: "a", binding: "b")
        let next = SportSessionLifetime(account: "a", binding: "b")
        XCTAssertFalse(first.accepts(current: next, account: "a", binding: "b", consent: true))
        XCTAssertTrue(next.accepts(current: next, account: "a", binding: "b", consent: true))
    }
    func testAccountBindingConsentAndEndInvalidateResults() {
        let owner = SportSessionLifetime(account: "a", binding: "b")
        XCTAssertFalse(owner.accepts(current: owner, account: "c", binding: "b", consent: true))
        XCTAssertFalse(owner.accepts(current: owner, account: "a", binding: "c", consent: true))
        XCTAssertFalse(owner.accepts(current: owner, account: "a", binding: "b", consent: false))
        XCTAssertFalse(owner.accepts(current: nil, account: "a", binding: "b", consent: true))
    }
}
