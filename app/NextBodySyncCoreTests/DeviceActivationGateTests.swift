import XCTest
@testable import NextBodySyncCore

final class DeviceActivationGateTests: XCTestCase {
    @MainActor func testAddingDuringFullHistoryStopsOldPullBeforeScanning() async throws {
        let gate = DeviceActivationGate()
        let refresh = BandRefreshCoordinator(state: {
            .init(account: "account", binding: "A", consent: true,
                  exclusive: gate.isHeld, connected: true)
        })
        var finishDay: CheckedContinuation<Void, Never>?
        var days = 0, histories = 0
        var cleaned = false, scanned = false
        let pull = Task { @MainActor in
            await refresh.refresh(.fullHistory, cadence: 0, work: .init(
                prepare: { _ in true }, day: { _ in
                    days += 1
                    await withCheckedContinuation { finishDay = $0 }
                    return .init(status: .success)
                }, history: { _ in
                    histories += 1
                    return .init(result: .init(status: .success))
                }, finish: { cleaned = true }))
        }
        while finishDay == nil { await Task.yield() }
        let pairing = Task { @MainActor in
            try await gate.prepare(owner: UUID()) { refresh.isIdle }
            XCTAssertTrue(cleaned)
            scanned = true
        }
        while !gate.isHeld { await Task.yield() }
        XCTAssertFalse(scanned)
        finishDay?.resume()
        let result = await pull.value
        try await pairing.value
        XCTAssertEqual(result.status, .busy)
        XCTAssertEqual(days, 1)
        XCTAssertEqual(histories, 0)
        XCTAssertTrue(scanned)
    }

    @MainActor func testRebindClosesAdmissionBeforeWaitingForOldNativeRead() async throws {
        let gate = DeviceActivationGate()
        let drain = BandNativeDrain()
        let owner = UUID()
        drain.begin()
        var scanned = false
        let task = Task { @MainActor in
            try await gate.prepare(owner: owner) { drain.isIdle }
            scanned = true
        }
        while !gate.isHeld { await Task.yield() }
        XCTAssertFalse(scanned)
        let state = BandRefreshCoordinator.State(account: "account", binding: "survivor",
            consent: true, exclusive: gate.isHeld, connected: true)
        XCTAssertEqual(state.rejection(), .busy)
        drain.end()
        try await task.value
        XCTAssertTrue(scanned)
        XCTAssertTrue(gate.isHeld, "Scanning and pairing still own the radio")
        gate.release(owner: owner)
        XCTAssertFalse(gate.isHeld)
        // Removing/re-adding again must not leave a stale reservation behind.
        try await gate.prepare(owner: UUID()) { true }
        XCTAssertTrue(gate.isHeld)
    }

    @MainActor func testTimeoutDoesNotDisconnectOrReleaseNativeReadAndCanRetry() async throws {
        let gate = DeviceActivationGate()
        let drain = BandNativeDrain()
        drain.begin()
        do {
            try await gate.prepare(owner: UUID(), timeout: .zero) { drain.isIdle }
            XCTFail("Must stop instead of waiting forever")
        } catch { XCTAssertTrue(error is DeviceActivationGate.Failure) }
        XCTAssertFalse(gate.isHeld)
        XCTAssertFalse(drain.isIdle)
        drain.end()
        try await gate.prepare(owner: UUID()) { drain.isIdle }
    }

    @MainActor func testCancellationAndStaleSheetCannotReleaseAnotherOwner() async throws {
        let gate = DeviceActivationGate()
        let old = UUID(), next = UUID()
        let task = Task { @MainActor in try await gate.prepare(owner: old) { false } }
        while !gate.isHeld { await Task.yield() }
        task.cancel()
        do { try await task.value; XCTFail("Cancelled scan cannot start") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(gate.isHeld)
        try await gate.prepare(owner: next) { true }
        gate.release(owner: old)
        XCTAssertEqual(gate.owner, next)
        do { try await gate.prepare(owner: old) { true }; XCTFail("Concurrent activation") }
        catch { XCTAssertTrue(error is DeviceActivationGate.Failure) }
        XCTAssertEqual(gate.owner, next)
    }
}
