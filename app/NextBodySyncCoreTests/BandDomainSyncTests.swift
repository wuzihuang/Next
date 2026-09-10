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
        XCTAssertNil(ack.receipts, "legacy acknowledgments remain decodable")
    }
    func testAccountPurgeRemovesDailyOutcomeWithoutTouchingAnotherAccount() {
        let user = UUID().uuidString, other = UUID().uuidString
        let key = "nb.sync.day-outcome.v1.\(user).band.2026-09-08"
        let otherKey = "nb.sync.day-outcome.v1.\(other).band.2026-09-08"
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: key); defaults.removeObject(forKey: otherKey) }
        defaults.set("success", forKey: key)
        defaults.set("success", forKey: otherKey)
        BandDomainSyncState.purge(userId: user)
        XCTAssertNil(defaults.string(forKey: key))
        XCTAssertEqual(defaults.string(forKey: otherKey), "success")
    }
}
