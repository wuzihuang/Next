import XCTest
@testable import NextBodySyncCore

final class BandReadinessFlightTests: XCTestCase {
    @MainActor func testConcurrentRequestsShareOneRead() async {
        let flight = BandReadinessFlight()
        var reads = 0
        let first = Task { @MainActor in
            await flight.run(key: "a") { reads += 1; await Task.yield(); return true }
        }
        let second = Task { @MainActor in
            await flight.run(key: "a") { reads += 1; return false }
        }
        let results = await (first.value, second.value)
        XCTAssertTrue(results.0)
        XCTAssertTrue(results.1)
        XCTAssertEqual(reads, 1)
    }

    @MainActor func testChangedBindingWaitsForOldWorkWithoutSharingResult() async {
        let flight = BandReadinessFlight()
        var order: [String] = []
        let first = Task { @MainActor in
            await flight.run(key: "a") {
                order.append("a-start"); await Task.yield(); order.append("a-end"); return false
            }
        }
        let second = Task { @MainActor in
            await flight.run(key: "b") { order.append("b"); return true }
        }
        let results = await (first.value, second.value)
        XCTAssertFalse(results.0)
        XCTAssertTrue(results.1)
        XCTAssertEqual(order, ["a-start", "a-end", "b"])
    }

    @MainActor func testCompletedFailureCanRetry() async {
        let flight = BandReadinessFlight()
        let failed = await flight.run(key: "a") { false }
        let retry = await flight.run(key: "a") { true }
        XCTAssertFalse(failed)
        XCTAssertTrue(retry)
    }
}

final class BandReadinessReceiptPolicyTests: XCTestCase {
    func testOnlyRecentMatchingLiveReceiptCanReuse() {
        XCTAssertTrue(BandReadinessReceiptPolicy.canReuse(requested: true, connected: true, exclusive: false, ownerMatches: true, age: 2.99))
        for age in [-1.0, 3.01, Double.infinity, Double.nan] {
            XCTAssertFalse(BandReadinessReceiptPolicy.canReuse(requested: true, connected: true, exclusive: false, ownerMatches: true, age: age))
        }
        XCTAssertFalse(BandReadinessReceiptPolicy.canReuse(requested: false, connected: true, exclusive: false, ownerMatches: true, age: 1))
        XCTAssertFalse(BandReadinessReceiptPolicy.canReuse(requested: true, connected: false, exclusive: false, ownerMatches: true, age: 1))
        XCTAssertFalse(BandReadinessReceiptPolicy.canReuse(requested: true, connected: true, exclusive: true, ownerMatches: true, age: 1))
        XCTAssertFalse(BandReadinessReceiptPolicy.canReuse(requested: true, connected: true, exclusive: false, ownerMatches: false, age: 1))
    }
}

final class BandNativeDrainTests: XCTestCase {
    @MainActor func testManualStartWaitsForEveryAlreadyAdmittedNativeRead() async {
        let drain = BandNativeDrain()
        drain.begin()
        drain.begin()
        var manualStarted = false
        let waiter = Task { @MainActor in await drain.waitUntilIdle(); manualStarted = true }
        await Task.yield()
        XCTAssertFalse(manualStarted)
        drain.end()
        await Task.yield()
        XCTAssertFalse(manualStarted)
        drain.end()
        await waiter.value
        XCTAssertTrue(manualStarted)
    }

    @MainActor func testIdleDoesNotWaitAndSupportsNextTransaction() async {
        let drain = BandNativeDrain()
        await drain.waitUntilIdle()
        drain.begin()
        let waiter = Task { @MainActor in await drain.waitUntilIdle() }
        await Task.yield()
        drain.end()
        await waiter.value
        await drain.waitUntilIdle()
    }
}
