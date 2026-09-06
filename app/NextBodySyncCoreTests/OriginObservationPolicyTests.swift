import XCTest
@testable import NextBodySyncCore

final class OriginObservationPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_788_235_200)

    func testFutureAndStillAccumulatingSlotsAreExcluded() {
        let now = start.addingTimeInterval(12 * 3600 + 2 * 60)
        XCTAssertTrue(accepts(start.addingTimeInterval(11 * 3600 + 55 * 60), at: now))
        XCTAssertFalse(accepts(start.addingTimeInterval(12 * 3600), at: now))
        XCTAssertFalse(accepts(start.addingTimeInterval(12 * 3600 + 5 * 60), at: now))
    }

    func testADeferredSlotIsIncludedOnTheNextFullPageRead() {
        let slot = start.addingTimeInterval(3600)
        XCTAssertFalse(accepts(slot, at: slot.addingTimeInterval(299)))
        XCTAssertTrue(accepts(slot, at: slot.addingTimeInterval(300)))
        XCTAssertTrue(accepts(slot, at: slot.addingTimeInterval(600)))
    }

    func testWindowIsBoundedAtBothEndsIncludingClosingTheLastSlot() {
        let end = start.addingTimeInterval(86400)
        XCTAssertFalse(accepts(start.addingTimeInterval(-300), at: end))
        XCTAssertTrue(accepts(start, at: end))
        XCTAssertTrue(accepts(end.addingTimeInterval(-300), at: end))
        XCTAssertFalse(accepts(end, at: end.addingTimeInterval(300)))
    }

    private func accepts(_ slot: Date, at now: Date) -> Bool {
        OriginObservationPolicy.accepts(slot: slot, dayStart: start,
            dayEnd: start.addingTimeInterval(86400), readStartedAt: now)
    }
}
