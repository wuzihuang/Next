import XCTest
@testable import NextBodySyncCore

final class MealMicroTotalsTests: XCTestCase {
    func testADayEveryRowKnowsIsSummed() {
        XCTAssertEqual(MealMicroTotals.total([3, 4, 9]), 16)
        XCTAssertEqual(MealMicroTotals.unknownCount([3, 4, 9]), 0)
    }

    /// The whole point: a partial sum looks like a whole-day number and is not one.
    func testOneSilentRowSilencesTheDay() {
        XCTAssertNil(MealMicroTotals.total([3, nil, 9]))
        XCTAssertEqual(MealMicroTotals.unknownCount([3, nil, 9]), 1)
        XCTAssertTrue(MealMicroTotals.anyKnown([3, nil, 9]))
    }

    func testADayThatKnowsNothingSaysNothing() {
        XCTAssertNil(MealMicroTotals.total([nil, nil]))
        XCTAssertFalse(MealMicroTotals.anyKnown([nil, nil]))
    }

    func testFractionalTotalsRetainSmallAmountsAndUnknowns() {
        XCTAssertEqual(MealMicroTotals.total([0.1, 0.2])!, 0.3, accuracy: 0.00001)
        XCTAssertNil(MealMicroTotals.total([0.1, nil]))
    }

    func testAnEmptyDayIsNotAZero() {
        XCTAssertNil(MealMicroTotals.total([]))
        XCTAssertFalse(MealMicroTotals.anyKnown([]))
    }
}
