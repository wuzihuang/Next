import XCTest
@testable import NextBodySyncCore

final class FuelCardMathTests: XCTestCase {

    func testUnloggedCannotNameADelta() {
        let read = FuelCardMath.readout(eaten: nil, target: 2_900)
        XCTAssertNil(read.eaten)
        XCTAssertEqual(read.target, 2_900)
        XCTAssertEqual(read.pair, .silent)
        XCTAssertEqual(read.fill, 0)
    }

    func testUnloggedWithoutATargetStaysSilent() {
        let read = FuelCardMath.readout(eaten: nil, target: nil)
        XCTAssertEqual(read.pair, .silent)
        XCTAssertEqual(read.fill, 0)
    }

    func testLoggedWithoutATargetOnlyCountsEaten() {
        let read = FuelCardMath.readout(eaten: 350, target: nil)
        XCTAssertEqual(read.eaten, 350)
        XCTAssertEqual(read.pair, .silent)
        XCTAssertEqual(read.fill, 0)
    }

    func testNotThereYetIsASignedShortfall() {
        let read = FuelCardMath.readout(eaten: 350, target: 2_900)
        XCTAssertEqual(read.pair, .toGo(-2_550))
        XCTAssertEqual(read.fill, 350 / 2_900, accuracy: 0.0001)
    }

    func testEqualIsZeroToGoAndAFullBar() {
        let read = FuelCardMath.readout(eaten: 2_900, target: 2_900)
        XCTAssertEqual(read.pair, .toGo(0))
        XCTAssertEqual(read.fill, 1)
    }

    func testOverStopsTheBarAtFullAndKeepsEmberMath() {
        let read = FuelCardMath.readout(eaten: 3_140, target: 2_900)
        XCTAssertEqual(read.pair, .over(240))
        XCTAssertEqual(read.fill, 1)
    }

    func testFastedZeroIsAnAssertion() {
        let read = FuelCardMath.readout(eaten: 0, target: 2_900)
        XCTAssertEqual(read.eaten, 0)
        XCTAssertEqual(read.pair, .toGo(-2_900))
        XCTAssertEqual(read.fill, 0)
    }

    func testZeroTargetCannotFill() {
        let read = FuelCardMath.readout(eaten: 350, target: 0)
        XCTAssertEqual(read.pair, .silent)
        XCTAssertEqual(read.fill, 0)
    }

    func testVisibleMealsAreEatenEvenWhenTheServerHeaderIsStillZero() {
        XCTAssertEqual(FuelCardMath.eaten(mealKcals: [420, 380], server: 0, fasted: false), 800)
        XCTAssertEqual(FuelCardMath.eaten(mealKcals: [420], server: nil, fasted: false), 420)
        XCTAssertEqual(
            FuelCardMath.readout(
                eaten: FuelCardMath.eaten(mealKcals: [350], server: 0, fasted: false),
                target: 2_900).eaten,
            350)
    }

    func testEmptyMealListKeepsASettledHeaderAndFastedStaysZero() {
        XCTAssertEqual(FuelCardMath.eaten(mealKcals: [], server: 650, fasted: false), 650)
        XCTAssertNil(FuelCardMath.eaten(mealKcals: [], server: nil, fasted: false))
        XCTAssertEqual(FuelCardMath.eaten(mealKcals: [], server: nil, fasted: true), 0)
        XCTAssertEqual(FuelCardMath.eaten(mealKcals: [], server: 0, fasted: true), 0)
    }
}
