import XCTest
@testable import NextBodySyncCore

final class DailyDirectionPolicyTests: XCTestCase {
    func testOpenDayWithTwoSlotsAndBalanceIsSurplus() {
        // The live account on 2026-09-04: breakfast + dinner, elapsed balance +721,
        // coverage never written to the phone. The cell used to stay GREY_NOTHING
        // because the day had not closed and coverage defaulted to 0.
        let color = DailyDirectionPolicy.color(
            balance: 721, fuel: .partial(slots: 2), bandCoverage: 0)
        XCTAssertEqual(color, .surplus)
    }

    func testTwoMealsInOneSlotStayGrey() {
        let color = DailyDirectionPolicy.color(
            balance: -1786, fuel: .partial(slots: 1), bandCoverage: 1)
        XCTAssertEqual(color, .greyNothing)
    }

    func testUnloggedDayStaysGreyEvenWithFullCoverage() {
        let color = DailyDirectionPolicy.color(
            balance: nil, fuel: .unlogged, bandCoverage: 1)
        XCTAssertEqual(color, .greyNothing)
    }

    func testKnownLowCoverageIsNoBurn() {
        let color = DailyDirectionPolicy.color(
            balance: 200, fuel: .confirmed, bandCoverage: 0.3)
        XCTAssertEqual(color, .greyNoBurn)
    }

    func testLoggedDayWithoutBalanceIsNoBurn() {
        let color = DailyDirectionPolicy.color(
            balance: nil, fuel: .confirmed, bandCoverage: 0.8)
        XCTAssertEqual(color, .greyNoBurn)
    }

    func testDeficitAndLevelBands() {
        XCTAssertEqual(
            DailyDirectionPolicy.color(balance: -150, fuel: .fasted, bandCoverage: 0.6),
            .deficit)
        XCTAssertEqual(
            DailyDirectionPolicy.color(balance: 0, fuel: .confirmed, bandCoverage: 0.6),
            .level)
        XCTAssertEqual(
            DailyDirectionPolicy.color(balance: 149, fuel: .confirmed, bandCoverage: 0.6),
            .level)
    }
}
