import XCTest
@testable import NextBodySyncCore

final class BandMeasurementReplyTests: XCTestCase {
    @MainActor func testCancellationStopsBeforeResumingAndRejectsLateReply() async {
        let reply = BandMeasurementReply<Int>()
        var events: [String] = []
        var callback: ((Result<Int, Error>) -> Void)?
        let operation = Task { @MainActor in
            do {
                _ = try await reply.wait(seconds: 60, start: { done in
                    callback = done
                    events.append("start")
                }, stop: { events.append("stop") })
                XCTFail("cancelled measurement must throw")
            } catch is CancellationError { events.append("cancelled") }
            catch { XCTFail("unexpected error: \(error)") }
        }
        while callback == nil { await Task.yield() }
        operation.cancel()
        await operation.value
        callback?(.success(88))
        XCTAssertEqual(events, ["start", "stop", "cancelled"])
    }

    @MainActor func testAlreadyCancelledTaskDoesNotStartNativeMeasurement() async {
        let operation = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await BandMeasurementReply<Int>().wait(seconds: 60,
                    start: { _ in XCTFail("must not start") }, stop: { XCTFail("nothing started") })
                XCTFail("must throw")
            } catch is CancellationError {} catch { XCTFail("unexpected error") }
        }
        await operation.value
    }

    @MainActor func testSuccessStopsExactlyOnce() async throws {
        let reply = BandMeasurementReply<Int>()
        var stops = 0
        let value = try await reply.wait(seconds: 60, start: { done in
            done(.success(7))
            done(.success(8))
        }, stop: { stops += 1 })
        XCTAssertEqual(value, 7)
        XCTAssertEqual(stops, 1)
    }

    @MainActor func testTimeoutStopsBeforeThrowing() async {
        let reply = BandMeasurementReply<Int>()
        var stopped = false
        do {
            _ = try await reply.wait(seconds: 0, start: { _ in }, stop: { stopped = true })
            XCTFail("must time out")
        } catch is BandMeasurementReply<Int>.Timeout {
            XCTAssertTrue(stopped)
        } catch { XCTFail("unexpected error") }
    }
}
