import XCTest
@testable import NextBodySyncCore

final class EvidencePublicationDrainTests: XCTestCase {
    @MainActor
    func testBandRefreshWaitsForExistingSettlementAndOwnsTheNextSettlement() async {
        let drain = EvidencePublicationDrain()
        var release: CheckedContinuation<Void, Never>?
        var events: [String] = []
        let foreground = Task { @MainActor in
            await drain.run(authorized: { true }) {
                events.append("settlement started")
                await withCheckedContinuation { release = $0 }
                events.append("settlement finished")
            }
        }
        while release == nil { await Task.yield() }
        var refreshActive = true
        let refresh = Task { @MainActor in
            await drain.waitForCurrent()
            events.append("band upload")
        }
        await Task.yield()
        XCTAssertEqual(events, ["settlement started"])
        release?.resume()
        await foreground.value
        await refresh.value
        XCTAssertEqual(events, ["settlement started", "settlement finished", "band upload"])
        // A foreground retry arriving during that upload must leave settlement to
        // the refresh, even when a dirty calculation would normally bypass throttling.
        await drain.run(authorized: { true }) {
            if HomeLaunchPolicy.shouldSettleOnForeground(pending: [true], lastSettledAt: nil,
                                                         bandRefreshActive: refreshActive) {
                events.append("competing settlement")
            }
        }
        XCTAssertFalse(events.contains("competing settlement"))
        refreshActive = false
        XCTAssertTrue(HomeLaunchPolicy.shouldSettleOnForeground(pending: [true], lastSettledAt: nil,
                                                               bandRefreshActive: refreshActive),
                      "an interrupted refresh must not disable the next foreground repair")
    }

    @MainActor
    func testFinishingSessionDrainsEvidenceArrivingAfterTheInFlightSnapshot() async {
        let drain = EvidencePublicationDrain()
        var pending = [1]
        var published: [Int] = []
        var release: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            await drain.run(authorized: { true }) {
                let snapshot = pending
                pending.removeAll()
                await withCheckedContinuation { release = $0 }
                published += snapshot
            }
        }
        while release == nil { await Task.yield() }
        pending.append(2)
        let finish = Task { @MainActor in
            await drain.run(afterCurrent: true, authorized: { true }) {
                published += pending
                pending.removeAll()
            }
        }
        await Task.yield()
        release?.resume()
        await first.value
        await finish.value
        XCTAssertEqual(published, [1, 2])
        XCTAssertTrue(pending.isEmpty)
    }

    @MainActor
    func testAccountGenerationChangePreventsLateFinalDrain() async {
        let drain = EvidencePublicationDrain()
        var generation = 1
        var release: CheckedContinuation<Void, Never>?
        var finalPublications = 0
        let first = Task { @MainActor in
            await drain.run(authorized: { generation == 1 }) {
                await withCheckedContinuation { release = $0 }
            }
        }
        while release == nil { await Task.yield() }
        let finish = Task { @MainActor in
            await drain.run(afterCurrent: true, authorized: { generation == 1 }) {
                finalPublications += 1
            }
        }
        await Task.yield()
        generation += 1
        drain.cancel()
        release?.resume()
        await first.value
        await finish.value
        XCTAssertEqual(finalPublications, 0)
    }
}
