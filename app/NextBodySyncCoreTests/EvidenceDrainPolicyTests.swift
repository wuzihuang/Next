import XCTest
@testable import NextBodySyncCore

final class EvidenceDrainPolicyTests: XCTestCase {
    func testLargeBacklogDrainsInBoundedBatchesExactlyOnce() {
        let ids = (0..<2848).map(String.init)
        let batches = EvidenceDrainPolicy.batches(ids, limit: 200)
        XCTAssertEqual(batches.count, 15)
        XCTAssertEqual(batches.last?.count, 48)
        XCTAssertEqual(batches.flatMap { $0 }, ids)
    }
    func testPartialOrRejectedAcknowledgmentCannotDropAnyOperations() {
        let partial = BandIngestionAcknowledgment(inserted: 1, completed: 0, unchanged: 0, rejected: 0, affectedDays: [])
        XCTAssertEqual(EvidenceDrainPolicy.confirmedIDs(["a", "b"], offeredSamples: 2, acknowledgment: partial), [])
        let rejected = BandIngestionAcknowledgment(inserted: 1, completed: 0, unchanged: 0, rejected: 1, affectedDays: [])
        XCTAssertEqual(EvidenceDrainPolicy.confirmedIDs(["a", "b"], offeredSamples: 2, acknowledgment: rejected), [])
        let retry = BandIngestionAcknowledgment(inserted: 0, completed: 0, unchanged: 2, rejected: 0, affectedDays: [])
        XCTAssertEqual(EvidenceDrainPolicy.confirmedIDs(["a", "b"], offeredSamples: 2, acknowledgment: retry), ["a", "b"])
    }
    func testNoProgressStopsAndEmptyOffersNeverAcknowledge() {
        XCTAssertFalse(EvidenceDrainPolicy.shouldContinue(acknowledged: 0))
        XCTAssertTrue(EvidenceDrainPolicy.shouldContinue(acknowledged: 1))
        let empty = BandIngestionAcknowledgment(inserted: 0, completed: 0, unchanged: 0, rejected: 0, affectedDays: [])
        XCTAssertEqual(EvidenceDrainPolicy.confirmedIDs(["a"], offeredSamples: 0, acknowledgment: empty), [])
    }
}
