import XCTest
@testable import NextBodySyncCore

final class SportHeartRateEvidenceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_788_271_200)

    private func report(_ stream: inout SportHeartRateEvidenceStream, seconds: Double,
                        heart: Int? = 120, state: Int? = 1, mode: Int? = 1) -> SportHeartRateEvidence? {
        stream.accept(at: start.addingTimeInterval(seconds), heartRate: heart,
                      runState: state, sportMode: mode, timeZone: "America/New_York")
    }

    func testReceiptsKeepExactTimestampAndHeartWithoutSmoothing() throws {
        var stream = SportHeartRateEvidenceStream()
        let first = try XCTUnwrap(report(&stream, seconds: 0.123, heart: 100))
        let next = try XCTUnwrap(report(&stream, seconds: 2.456, heart: 180))
        XCTAssertEqual(first.observedAt, start.addingTimeInterval(0.123))
        XCTAssertEqual(next.heartRate, 180)
        XCTAssertEqual(first.continuityID, next.continuityID)
        XCTAssertEqual(first.sessionID, next.sessionID)
        XCTAssertNotEqual(first.id, next.id)
        XCTAssertEqual(first.sampledTimeZone, "America/New_York")
        XCTAssertEqual(try JSONDecoder().decode(SportHeartRateEvidence.self,
            from: JSONEncoder().encode(first)), first)
    }

    func testPausedMissingAndInvalidHeartEndContinuity() throws {
        for (heart, state): (Int?, Int?) in [(120, 2), (120, 0), (120, 3), (nil, 1),
                                                   (0, 1), (251, 1), (-1, nil)] {
            var stream = SportHeartRateEvidenceStream()
            let before = try XCTUnwrap(report(&stream, seconds: 0))
            XCTAssertNil(report(&stream, seconds: 1, heart: heart, state: state))
            let after = try XCTUnwrap(report(&stream, seconds: 2))
            XCTAssertNotEqual(before.continuityID, after.continuityID)
            XCTAssertEqual(before.sessionID, after.sessionID)
        }
    }

    func testDisconnectAndStreamReplacementEndContinuity() throws {
        var stream = SportHeartRateEvidenceStream()
        let before = try XCTUnwrap(report(&stream, seconds: 0))
        stream.interrupted()
        let after = try XCTUnwrap(report(&stream, seconds: 1))
        XCTAssertNotEqual(before.continuityID, after.continuityID)
    }

    func testOnlyIntervalsUpToFifteenSecondsShareContinuity() throws {
        var stream = SportHeartRateEvidenceStream()
        let first = try XCTUnwrap(report(&stream, seconds: 0))
        let atLimit = try XCTUnwrap(report(&stream, seconds: 15))
        let afterGap = try XCTUnwrap(report(&stream, seconds: 30.001))
        XCTAssertEqual(first.continuityID, atLimit.continuityID)
        XCTAssertNotEqual(atLimit.continuityID, afterGap.continuityID)
    }

    func testClockReversalAndDuplicateDoNotInventElapsedTime() throws {
        var stream = SportHeartRateEvidenceStream()
        let first = try XCTUnwrap(report(&stream, seconds: 10))
        XCTAssertNil(report(&stream, seconds: 10))
        let reversed = try XCTUnwrap(report(&stream, seconds: 9))
        XCTAssertNotEqual(first.continuityID, reversed.continuityID)
    }

    func testHeartTestFallbackAndUnknownJoinedModeRemainHonest() throws {
        var stream = SportHeartRateEvidenceStream()
        let joined = try XCTUnwrap(report(&stream, seconds: 0, state: nil, mode: nil))
        XCTAssertNil(joined.sportMode)
        var restarted = SportHeartRateEvidenceStream()
        let next = try XCTUnwrap(report(&restarted, seconds: 5))
        XCTAssertNotEqual(joined.sessionID, next.sessionID)
        XCTAssertNotEqual(joined.continuityID, next.continuityID)
    }
}
