import XCTest
@testable import NextBodySyncCore

final class BandSyncProgressTests: XCTestCase {
    func testHistoryAndDailyModesHaveSeparateCopy() {
        var progress = BandSyncProgress()
        progress.begin()
        XCTAssertEqual(progress.modeLabel, "DAILY SYNC")
        progress.beginHistory()
        XCTAssertEqual(progress.modeLabel, "BACKFILLING HISTORY")
        progress.begin()
        XCTAssertEqual(progress.modeLabel, "DAILY SYNC")
    }

    func testHistoryDeadlineTracksProgressInsteadOfRepeatedCallbacks() {
        let deadline = BandSyncDeadline(startedAt: 100)
        XCTAssertFalse(deadline.expired(at: 144))
        deadline.advance("day1:10", at: 120)
        deadline.advance("day1:10", at: 140)
        XCTAssertFalse(deadline.expired(at: 164))
        XCTAssertTrue(deadline.expired(at: 165), "A repeated callback cannot hide a stuck command")
        deadline.advance("day1:20", at: 165)
        XCTAssertFalse(deadline.expired(at: 166))
        deadline.advance("day7:99", at: 399)
        XCTAssertTrue(deadline.expired(at: 400), "Progress cannot exceed the absolute ceiling")
    }

    @MainActor func testSharedRefreshWaitsForAsyncCompletionReceipt() async {
        var persisted = false
        let coordinator = BandRefreshCoordinator(state: {
            .init(account: "account", binding: "band", consent: true, exclusive: false, connected: true)
        })
        let result = await coordinator.refresh(.latest, cadence: 0, work: .init(
            prepare: { _ in true }, day: { _ in .init(status: .success) },
            history: { _ in .init(result: nil) }, completed: { _ in
                await Task.yield()
                XCTAssertFalse(coordinator.isIdle)
                persisted = true
            }))
        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(persisted)
        XCTAssertTrue(coordinator.isIdle)
    }

    @MainActor func testScopeChangeDuringCleanupCannotPublish100() async {
        var binding = "A"
        var progress = BandSyncProgress()
        let coordinator = BandRefreshCoordinator(state: {
            .init(account: "account", binding: binding, consent: true, exclusive: false, connected: true)
        })
        let result = await coordinator.refresh(.fullHistory, cadence: 0, work: .init(
            prepare: { _ in progress.begin(); return true },
            day: { _ in .init(status: .success) },
            history: { _ in .init(result: .init(status: .success)) },
            finish: { binding = "B" },
            completed: { progress.finish(success: $0.status == .success) }))
        XCTAssertEqual(result.status, .cancelled)
        XCTAssertEqual(progress.stage, .stopped)
        XCTAssertLessThan(progress.fraction, 1)
    }

    func testDumpAt100DoesNotCompleteWholeSync() {
        var progress = BandSyncProgress()
        progress.begin()
        progress.show(.reading)
        progress.read(1)
        XCTAssertLessThan(progress.fraction, 1)
        XCTAssertTrue(progress.active)
        progress.expect(3)
        for _ in 0..<3 { progress.filedDay() }
        progress.updatingResults()
        progress.resultsLoaded()
        progress.show(.finishing)
        XCTAssertLessThan(progress.fraction, 1)
        progress.finish(success: true)
        XCTAssertEqual(progress.fraction, 1)
        XCTAssertFalse(progress.active)
        XCTAssertEqual(progress.stage, .complete)
    }

    func testConnectionStepsAdvanceWithoutTimersAndRetryDoesNotRewind() {
        var progress = BandSyncProgress()
        progress.begin()
        for stage in [BandSyncProgress.Stage.connecting, .verifying, .identity, .battery, .capabilities] {
            let before = progress.fraction
            progress.show(stage)
            XCTAssertGreaterThan(progress.fraction, before)
            XCTAssertEqual(progress.stage, stage)
        }
        let beforeRetry = progress.fraction
        progress.show(.searching)
        XCTAssertEqual(progress.stage, .searching)
        XCTAssertEqual(progress.fraction, beforeRetry)
    }

    func testPartialFailureLateEventsAndNewAttempt() {
        var progress = BandSyncProgress()
        progress.begin()
        progress.read(1)
        progress.show(.finishing)
        progress.finish(success: false)
        XCTAssertLessThan(progress.fraction, 1)
        XCTAssertEqual(progress.stage, .stopped)
        progress.read(1)
        progress.show(.identity)
        progress.finish(success: true)
        XCTAssertEqual(progress.stage, .stopped)
        progress.begin()
        XCTAssertEqual(progress.fraction, 0)
        XCTAssertTrue(progress.active)
        progress.read(.nan)
        XCTAssertEqual(progress.fraction, 0)
    }

    @MainActor func testSharedRefreshPublishesCompletionOnlyAfterCleanup() async {
        var progress = BandSyncProgress()
        let coordinator = BandRefreshCoordinator(state: {
            .init(account: "account", binding: "band", consent: true, exclusive: false, connected: true)
        })
        let result = await coordinator.refresh(.fullHistory, cadence: 0, work: .init(
            prepare: { _ in progress.begin(); return true },
            day: { _ in progress.read(1); return .init(status: .success) },
            history: { _ in progress.updatingResults(); return .init(result: .init(status: .success)) },
            finish: {
                XCTAssertTrue(progress.active)
                XCTAssertLessThan(progress.fraction, 1)
                await Task.yield()
            }, completed: { result in progress.finish(success: result.status == .success) }))
        XCTAssertEqual(result.status, .success)
        XCTAssertFalse(progress.active)
        XCTAssertEqual(progress.fraction, 1)
    }
}
