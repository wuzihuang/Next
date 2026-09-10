import XCTest
@testable import NextBodySyncCore

final class BandRefreshCoordinatorTests: XCTestCase {
    @MainActor private final class Gate {
        var entered = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            entered = true
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { continuation?.resume(); continuation = nil }
    }

    @MainActor private final class Fixture {
        var account: String? = "alice"
        var binding: String? = "band-a"
        var consent = true
        var exclusive = false
        var connected = true
        var clock = Date(timeIntervalSince1970: 10_000)
        var events: [String] = []
        var prepareGate: Gate?
        var prepareSucceeds = true
        var dayGate: (offset: Int, gate: Gate)?
        var dayStatus: [Int: BandRefreshResult.Status] = [:]
        var historyStatus: BandRefreshResult.Status = .success
        var historyHasWork = true
        var historyRecoveredDays: Set<Int> = []
        var historyReceivedDays: [Int: BandRefreshResult] = [:]
        var checksHistory = false
        var finishGate: Gate?
        var afterDay: ((Int) -> Void)?
        lazy var coordinator = BandRefreshCoordinator(state: { [self] in
            .init(account: account, binding: binding, consent: consent, exclusive: exclusive, connected: connected)
        }, now: { self.clock })

        var work: BandRefreshCoordinator.Work {
            .init(prepare: { [self] reuse in
                events.append("prepare:\(account ?? "none"):\(reuse)")
                if let prepareGate { await prepareGate.wait() }
                guard prepareSucceeds else { return false }
                connected = true
                return true
            }, day: { [self] offset in
                events.append("day:\(account ?? "none"):\(offset)")
                if let dayGate, dayGate.offset == offset { await dayGate.gate.wait() }
                afterDay?(offset)
                return .init(status: dayStatus[offset] ?? .success, points: offset == 1 ? 2 : 3)
            }, history: { [self] days in
                historyReceivedDays = days
                events.append("history")
                return .init(result: historyHasWork ? .init(status: historyStatus, points: 7) : nil,
                             recoveredDays: historyRecoveredDays)
            }, checkHistory: { self.checksHistory }, finish: { [self] in
                if let finishGate { await finishGate.wait() }
            })
        }
        func refresh(_ request: BandRefreshRequest) async -> BandRefreshResult {
            await coordinator.refresh(request, cadence: 300, work: work)
        }
    }

    @MainActor private func entered(_ gate: Gate) async {
        for _ in 0..<1000 {
            if gate.entered { return }
            await Task.yield()
        }
        XCTFail("Refresh did not reach its controlled wait")
    }

    @MainActor func testAdmissionRejectsWithoutPreparingOrReading() async {
        let f = Fixture()
        f.account = nil
        var result = await f.refresh(.latest)
        XCTAssertEqual(result.status, .signedOut)
        f.account = "alice"; f.binding = nil
        result = await f.refresh(.latest)
        XCTAssertEqual(result.status, .unbound)
        f.binding = "band-a"; f.consent = false
        result = await f.refresh(.latest)
        XCTAssertEqual(result.status, .consentRequired)
        f.consent = true; f.exclusive = true
        result = await f.refresh(.latest)
        XCTAssertEqual(result.status, .busy)
        f.exclusive = false; f.connected = false
        result = await f.refresh(.phoneTool)
        XCTAssertEqual(result.status, .disconnected)
        XCTAssertNil(result.syncedAt)
        XCTAssertTrue(f.events.isEmpty)
        result = await f.refresh(.fullHistory)
        XCTAssertEqual(result.status, .success, "an explicit device refresh may reconnect")
        XCTAssertEqual(f.events, ["prepare:alice:false", "day:alice:1", "day:alice:0", "history"])
    }

    @MainActor func testConcurrentHistoryRequestUpgradesTheSharedRefresh() async {
        let f = Fixture(); let gate = Gate(); f.prepareGate = gate
        let first = Task { @MainActor in await f.refresh(.foreground) }
        await entered(gate)
        let second = Task { @MainActor in await f.refresh(.fullHistory) }
        await Task.yield()
        gate.release()
        let results = await (first.value, second.value)
        XCTAssertEqual(results.0, results.1)
        XCTAssertEqual(results.0, .init(status: .success, points: 12, syncedAt: f.clock))
        XCTAssertEqual(f.events, ["prepare:alice:true", "day:alice:1", "day:alice:0", "history"])
    }

    @MainActor func testThrottleRunsBeforeReadinessAndExplicitRefreshBypassesIt() async {
        let f = Fixture()
        _ = await f.refresh(.latest)
        var result = await f.refresh(.automatic)
        XCTAssertEqual(result.status, .throttled)
        XCTAssertEqual(f.events.count, 3)
        f.clock.addTimeInterval(150)
        result = await f.refresh(.foreground)
        XCTAssertEqual(result.status, .throttled)
        result = await f.refresh(.automatic)
        XCTAssertEqual(result.status, .success)
        result = await f.refresh(.latest)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(f.events.count, 9)
        f.binding = "band-b"
        result = await f.refresh(.foreground)
        XCTAssertEqual(result.status, .success, "a different band cannot inherit cadence")
    }

    @MainActor func testFailedReadinessDoesNotConsumeCadence() async {
        let f = Fixture(); f.prepareSucceeds = false
        let failed = await f.refresh(.foreground)
        XCTAssertEqual(failed.status, .failed)
        f.prepareSucceeds = true
        let retry = await f.refresh(.foreground)
        XCTAssertEqual(retry.status, .success)
        XCTAssertEqual(f.events, ["prepare:alice:true", "prepare:alice:true", "day:alice:1", "day:alice:0"])
    }

    @MainActor func testHistoryCanJoinWhileTodayIsStillReading() async {
        let f = Fixture(); let gate = Gate(); f.dayGate = (0, gate)
        let recent = Task { @MainActor in await f.refresh(.latest) }
        await entered(gate)
        let history = Task { @MainActor in await f.refresh(.fullHistory) }
        await Task.yield()
        gate.release()
        let results = await (recent.value, history.value)
        XCTAssertEqual(results.0, results.1)
        XCTAssertEqual(f.events, ["prepare:alice:false", "day:alice:1", "day:alice:0", "history"])
    }

    @MainActor func testRevokedConsentWhilePreparingStopsBeforeAnyDay() async {
        let f = Fixture(); let gate = Gate(); f.prepareGate = gate
        let request = Task { @MainActor in await f.refresh(.latest) }
        await entered(gate)
        f.consent = false
        gate.release()
        let result = await request.value
        XCTAssertEqual(result.status, .consentRequired)
        XCTAssertNil(result.syncedAt)
        XCTAssertEqual(f.events, ["prepare:alice:false"])
    }

    @MainActor func testAllRequestedDaysContributeToCompletion() async {
        let f = Fixture(); f.dayStatus[1] = .failed
        var result = await f.refresh(.latest)
        XCTAssertEqual(result.status, .partial, "today's success cannot hide yesterday's failure")
        XCTAssertEqual(result.points, 5)
        XCTAssertNil(result.syncedAt)
        f.dayStatus[0] = .failed
        result = await f.refresh(.latest)
        XCTAssertEqual(result.status, .failed)
        f.dayStatus = [:]; f.historyStatus = .failed
        result = await f.refresh(.fullHistory)
        XCTAssertEqual(result.status, .partial)
        XCTAssertNil(result.syncedAt)
    }

    @MainActor func testAccountChangeBetweenDaysStopsOldWork() async {
        let f = Fixture()
        f.afterDay = { offset in if offset == 1 { f.account = "bob" } }
        let result = await f.refresh(.fullHistory)
        XCTAssertEqual(result.status, .cancelled)
        XCTAssertEqual(result.points, 2)
        XCTAssertEqual(f.events, ["prepare:alice:false", "day:alice:1"])
        XCTAssertNil(result.syncedAt)
    }

    @MainActor func testChangedAccountWaitsWithoutSharingTheOldResult() async {
        let f = Fixture(); let gate = Gate(); f.prepareGate = gate
        let old = Task { @MainActor in await f.refresh(.latest) }
        await entered(gate)
        f.account = "bob"; f.prepareGate = nil
        let next = Task { @MainActor in await f.refresh(.latest) }
        await Task.yield()
        XCTAssertEqual(f.events, ["prepare:alice:false"])
        gate.release()
        let results = await (old.value, next.value)
        XCTAssertEqual(results.0.status, .cancelled)
        XCTAssertEqual(results.1.status, .success)
        XCTAssertEqual(f.events, ["prepare:alice:false", "prepare:bob:false", "day:bob:1", "day:bob:0"])
    }

    @MainActor func testCancellingOneWaiterDoesNotCancelSharedWork() async {
        let f = Fixture(); let gate = Gate(); f.prepareGate = gate
        let view = Task { @MainActor in await f.refresh(.latest) }
        await entered(gate)
        view.cancel()
        let other = Task { @MainActor in await f.refresh(.latest) }
        await Task.yield()
        gate.release()
        let results = await (view.value, other.value)
        XCTAssertEqual(results.0.status, .cancelled)
        XCTAssertEqual(results.1.status, .success)
        XCTAssertEqual(f.events, ["prepare:alice:false", "day:alice:1", "day:alice:0"])
    }

    @MainActor func testConsentResumeIsScopedAndConsumedOnce() async {
        let f = Fixture(); f.consent = false
        _ = await f.refresh(.fullHistory)
        f.consent = true
        var result = await f.coordinator.refreshAfterConsent(cadence: 300, work: f.work)
        XCTAssertEqual(result?.status, .success)
        XCTAssertEqual(f.events.last, "history")
        result = await f.coordinator.refreshAfterConsent(cadence: 300, work: f.work)
        XCTAssertNil(result)
        f.events = []; f.consent = false
        _ = await f.refresh(.fullHistory)
        f.account = "bob"; f.consent = true
        result = await f.coordinator.refreshAfterConsent(cadence: 300, work: f.work)
        XCTAssertEqual(result?.status, .cancelled)
        XCTAssertTrue(f.events.isEmpty)
        f.consent = false
        _ = await f.refresh(.fullHistory)
        result = await f.coordinator.refreshAfterConsent(cadence: 300, work: f.work)
        XCTAssertEqual(result?.status, .consentRequired)
        f.consent = true
        result = await f.coordinator.refreshAfterConsent(cadence: 300, work: f.work)
        XCTAssertNil(result, "declining must discard the old manual request")
    }

    @MainActor func testRoutineRefreshCanCheckForMissingHistoryAndPassesRecentDayResults() async {
        let f = Fixture(); f.checksHistory = true
        let result = await f.refresh(.latest)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(f.events.last, "history")
        XCTAssertEqual(f.historyReceivedDays[1]?.status, .success)
        XCTAssertEqual(f.historyReceivedDays[0]?.status, .success)
    }

    @MainActor func testRecoveredYesterdayDoesNotLeaveAFalsePartialResult() async {
        let f = Fixture(); f.dayStatus[1] = .failed; f.historyRecoveredDays = [1]
        let result = await f.refresh(.fullHistory)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.points, 12, "already published points remain counted when a retry repairs its day")
        XCTAssertEqual(f.historyReceivedDays[1]?.status, .failed)
    }

    @MainActor func testFinishingRefreshIsAwaitedBeforeAnotherAccountStarts() async {
        let f = Fixture(); let gate = Gate(); f.finishGate = gate
        let first = Task { @MainActor in await f.refresh(.latest) }
        await entered(gate)
        f.account = "bob"; f.finishGate = nil
        let second = Task { @MainActor in await f.refresh(.latest) }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.events, ["prepare:alice:false", "day:alice:1", "day:alice:0"])
        gate.release()
        let results = await (first.value, second.value)
        XCTAssertEqual(results.0.status, .cancelled)
        XCTAssertEqual(results.1.status, .success)
    }


    @MainActor func testNoHistoryWorkDoesNotTurnFailedRecentReadsIntoPartialSuccess() async {
        let f = Fixture(); f.historyHasWork = false; f.dayStatus = [0: .failed, 1: .failed]
        let result = await f.refresh(.fullHistory)
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.points, 5)
    }

}
