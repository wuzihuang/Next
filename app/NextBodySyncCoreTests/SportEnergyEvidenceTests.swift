import XCTest
@testable import NextBodySyncCore

final class SportEnergyEvidenceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testRunningStrengthReportsPersistWithoutHeartRate() {
        var stream = SportEnergyEvidenceStream()
        let first = stream.accept(at: start, runState: 1, sportMode: 25, timeZone: "UTC")
        let second = stream.accept(at: start.addingTimeInterval(10), runState: 1,
                                   sportMode: 25, timeZone: "UTC")

        XCTAssertNotNil(first)
        XCTAssertEqual(first?.sessionID, second?.sessionID)
        XCTAssertEqual(first?.continuityID, second?.continuityID)
        XCTAssertEqual(second?.sportMode, 25)
    }

    func testPauseGapAndUnknownModeCannotEstablishStrengthInterval() {
        var stream = SportEnergyEvidenceStream()
        let first = stream.accept(at: start, runState: 1, sportMode: 25, timeZone: "UTC")
        XCTAssertNil(stream.accept(at: start.addingTimeInterval(5), runState: 2,
                                   sportMode: 25, timeZone: "UTC"))
        let afterPause = stream.accept(at: start.addingTimeInterval(10), runState: 1,
                                       sportMode: 25, timeZone: "UTC")
        XCTAssertNotEqual(first?.continuityID, afterPause?.continuityID)
        let afterGap = stream.accept(at: start.addingTimeInterval(30), runState: 1,
                                     sportMode: 25, timeZone: "UTC")
        XCTAssertNotEqual(afterPause?.continuityID, afterGap?.continuityID)
        XCTAssertNil(stream.accept(at: start.addingTimeInterval(31), runState: 1,
                                   sportMode: 24, timeZone: "UTC"))
        XCTAssertNil(stream.accept(at: start.addingTimeInterval(32), runState: 1,
                                   sportMode: nil, timeZone: "UTC"))
    }

    func testDuplicateAndInvalidReportsAreNotAdditionalEvidence() {
        var stream = SportEnergyEvidenceStream()
        XCTAssertNotNil(stream.accept(at: start, runState: 1, sportMode: 47, timeZone: "UTC"))
        XCTAssertNil(stream.accept(at: start, runState: 1, sportMode: 47, timeZone: "UTC"))
        XCTAssertNil(stream.accept(at: Date(timeIntervalSince1970: .infinity), runState: 1,
                                   sportMode: 47, timeZone: "UTC"))
    }
}
