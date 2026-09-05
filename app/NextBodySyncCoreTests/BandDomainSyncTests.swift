import XCTest
@testable import NextBodySyncCore

final class BandDomainSyncTests: XCTestCase {
    func testRRInputsRetainOriginalOrderForLaterReproduction() throws {
        let sample = try XCTUnwrap(HealthSampleMapping.hrv(from: ["time": "12:05", "hearts": [80, 84, 81]]))
        XCTAssertEqual(sample.rrMilliseconds, [800, 840, 810])
    }
    func testRejectedAcknowledgmentDoesNotConfirmReadRange() throws {
        let ack = try JSONDecoder().decode(BandIngestionAcknowledgment.self, from: Data(#"{"inserted":1,"completed":0,"unchanged":0,"rejected":1,"affected_days":["2026-09-04"]}"#.utf8))
        XCTAssertFalse(ack.confirms(offered: 2))
        XCTAssertFalse(ack.confirms(offered: 1))
    }
    func testLostResponseRetryAcknowledgesUnchangedFacts() throws {
        let ack = try JSONDecoder().decode(BandIngestionAcknowledgment.self, from: Data(#"{"inserted":0,"completed":0,"unchanged":2,"rejected":0,"affected_days":[]}"#.utf8))
        XCTAssertTrue(ack.confirms(offered: 2))
        XCTAssertFalse(ack.hasChanges)
    }
}
