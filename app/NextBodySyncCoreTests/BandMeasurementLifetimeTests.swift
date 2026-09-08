import Foundation
import XCTest
@testable import NextBodySyncCore

@MainActor
private final class MeasurementGate {
    var waiting: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { waiting = $0 } }
    func release() { let value = waiting; waiting = nil; value?.resume() }
}

final class BandMeasurementLifetimeTests: XCTestCase {
    @MainActor private func until(_ predicate: @MainActor () -> Bool,
                                  file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 { if predicate() { return }; await Task.yield() }
        XCTFail("Controlled suspension was not reached", file: file, line: line)
    }

    @MainActor func testDismissCancelsSilentStreamAndKeepsAdmissionClosedUntilSDKStopDrains() async {
        let stopGate = MeasurementGate()
        var events: [String] = []
        let lifetime = BandMeasurementLifetime(acquire: { events.append("acquire") }, release: {
            events.append("stop queued")
            await stopGate.wait()
            events.append("stop drained")
        }, changed: {})
        let id = UUID()
        let stream = AsyncStream<Int> { continuation in
            continuation.yield(0) // waitingForContact; the SDK never sends another event.
        }
        let task = lifetime.start(id: id) {
            for await _ in stream { events.append("waiting") }
            events.append("native consumer ended")
        }
        XCTAssertTrue(lifetime.isBusy)
        await until { events.contains("waiting") }
        lifetime.cancel(id: id)
        await until { stopGate.waiting != nil }
        XCTAssertTrue(events.contains("native consumer ended"))
        XCTAssertTrue(lifetime.isBusy)
        stopGate.release()
        await task.value
        XCTAssertFalse(lifetime.isBusy)
        XCTAssertEqual(events, ["acquire", "waiting", "native consumer ended", "stop queued", "stop drained"])
    }

    @MainActor func testSuccessorAndSameViewRestartWaitForPredecessorNativeStop() async {
        for sameView in [false, true] {
            let oldStop = MeasurementGate()
            let nextGate = MeasurementGate()
            var acquired = 0
            var released = 0
            var oldWaiting = false
            var newStarted = false
            let lifetime = BandMeasurementLifetime(acquire: { acquired += 1 }, release: {
                released += 1
                if released == 1 { await oldStop.wait() }
            }, changed: {})
            let oldID = UUID()
            let oldStream = AsyncStream<Int> { $0.yield(0) }
            let old = lifetime.start(id: oldID) { for await _ in oldStream { oldWaiting = true } }
            await until { oldWaiting }
            let nextID = sameView ? oldID : UUID()
            let next = lifetime.start(id: nextID) { newStarted = true; await nextGate.wait() }
            await until { oldStop.waiting != nil }
            XCTAssertFalse(newStarted)
            XCTAssertEqual(acquired, 1)
            XCTAssertTrue(lifetime.isBusy)
            oldStop.release()
            await old.value
            await until { nextGate.waiting != nil }
            XCTAssertTrue(lifetime.isBusy, "Old completion cannot clear a new generation, even with the same view ID")
            if !sameView { lifetime.cancel(id: oldID); XCTAssertFalse(next.isCancelled) }
            nextGate.release()
            await next.value
            XCTAssertFalse(lifetime.isBusy)
            XCTAssertEqual(acquired, 2)
            XCTAssertEqual(released, 2)
        }
    }

    @MainActor func testCancelledAdmissionNeverStartsMeasurementAndStillReleasesLease() async {
        let admission = MeasurementGate()
        var measured = false
        var released = false
        let lifetime = BandMeasurementLifetime(acquire: { await admission.wait() },
                                               release: { released = true }, changed: {})
        let id = UUID()
        let task = lifetime.start(id: id) { measured = true }
        await until { admission.waiting != nil }
        lifetime.cancel(id: id)
        admission.release()
        await task.value
        XCTAssertFalse(measured)
        XCTAssertTrue(released)
        XCTAssertFalse(lifetime.isBusy)
    }
}
