import XCTest
@testable import NextBodySyncCore

final class BandSportSubscriptionTests: XCTestCase {
    @MainActor func testStateProbeSharesExistingSportSubscription() {
        let owner = BandSportSubscription()
        let live = UUID(), probe = UUID()
        XCTAssertTrue(owner.add(live))
        let generation = owner.generation
        XCTAssertFalse(owner.add(probe))
        XCTAssertFalse(owner.remove(probe))
        XCTAssertEqual(owner.generation, generation)
        XCTAssertTrue(owner.contains(live))
        XCTAssertTrue(owner.remove(live))
    }

    @MainActor func testLateCancellationCannotUnsubscribeNewSession() {
        let owner = BandSportSubscription()
        let old = UUID(), next = UUID()
        XCTAssertTrue(owner.add(old))
        let generation = owner.generation
        XCTAssertTrue(owner.remove(old))
        XCTAssertTrue(owner.add(next))
        XCTAssertNotEqual(owner.generation, generation)
        XCTAssertFalse(owner.remove(old))
        XCTAssertTrue(owner.contains(next))
    }

    @MainActor func testRepeatedReadersOnlyLastReaderStopsNativeSubscription() {
        let owner = BandSportSubscription()
        let readers = (0..<100).map { _ in UUID() }
        XCTAssertEqual(readers.filter { owner.add($0) }.count, 1)
        XCTAssertEqual(readers.dropLast().filter { owner.remove($0) }.count, 0)
        XCTAssertTrue(owner.remove(readers.last!))
        XCTAssertFalse(owner.remove(readers.last!))
    }
}
