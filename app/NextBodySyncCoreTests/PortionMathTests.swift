import XCTest
@testable import NextBodySyncCore

final class PortionMathTests: XCTestCase {
    func testAPortionWithANumberScalesWithIt() {
        XCTAssertEqual(PortionMath.scale("1 碗", by: 1.5), "1.5 碗")
        XCTAssertEqual(PortionMath.scale("200 g", by: 0.5), "100 g")
        XCTAssertEqual(PortionMath.scale("2 slices", by: 2), "4 slices")
        XCTAssertEqual(PortionMath.scale("1/2 cup", by: 2), "1 cup")
        XCTAssertEqual(PortionMath.scale("200g", by: 0.5), "100 g")
    }

    func testTheIdentityLeavesEverythingAlone() {
        XCTAssertEqual(PortionMath.scale("1 碗", by: 1), "1 碗")
        XCTAssertEqual(PortionMath.scale(240, by: 1), 240)
    }

    /// Words that carry no number cannot carry a new amount either.
    func testWordsWithoutANumberAreDroppedRatherThanLie() {
        XCTAssertNil(PortionMath.scale("半份", by: 2))
        XCTAssertNil(PortionMath.scale("a handful", by: 0.5))
        XCTAssertNil(PortionMath.scale(nil, by: 2))
    }

    func testNutrientsRoundAndNeverFallToZeroFromSomething() {
        XCTAssertEqual(PortionMath.scale(240.0, by: 0.5, floorAtOne: true), 120)
        XCTAssertEqual(PortionMath.scale(1.0, by: 0.25, floorAtOne: true), 1)
        XCTAssertEqual(PortionMath.scale(7, by: 0.5), 4)
        XCTAssertEqual(PortionMath.scale(0.0, by: 2, floorAtOne: true), 0)
    }

    func testDecimalNutrientsScaleWithoutIntegerRounding() {
        XCTAssertEqual(PortionMath.scale(23.6, by: 0.5), 11.8)
        XCTAssertEqual(PortionMath.scale(7.0, by: 0.5), 3.5)
        XCTAssertEqual(PortionMath.scale(0.2, by: 0.5), 0.1)
        XCTAssertEqual(PortionMath.scale(123.4, by: 1), 123.4)
    }

    func testAnUnusableFactorChangesNothing() {
        XCTAssertEqual(PortionMath.scale("1 碗", by: 0), "1 碗")
        XCTAssertEqual(PortionMath.scale(240.0, by: .nan), 240)
        XCTAssertFalse(PortionMath.isUsable(-1))
        XCTAssertFalse(PortionMath.isUsable(100))
    }
}
