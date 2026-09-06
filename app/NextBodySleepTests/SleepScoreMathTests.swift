import XCTest
@testable import NextBodySleepCore

/// ADR 0008 · the sleep board's week and month windows. The scoring itself is exercised
/// against a real Postgres by supabase/tests/night_score/run.sh; what is left in Swift is
/// the reduction over nights, and these are the parts of it that can be quietly wrong.
final class SleepScoreMathTests: XCTestCase {

    // MARK: median

    func testMedianOfOddCountIsTheMiddleValue() {
        XCTAssertEqual(SleepScoreMath.median([90, 40, 70]), 70)
    }

    func testMedianOfEvenCountAveragesTheMiddleTwo() {
        XCTAssertEqual(SleepScoreMath.median([40, 60, 80, 100]), 70)
    }

    func testMedianOfNothingIsNothing() {
        XCTAssertNil(SleepScoreMath.median([]))
    }

    /// The whole reason this is a median: a wrist taken off at 01:00 files a two-hour night,
    /// and a mean would let that one night read as a bad week.
    func testOneRuinedNightDoesNotMoveTheMedian() {
        let week: [Double] = [82, 79, 85, 81, 80, 83, 12]
        XCTAssertEqual(SleepScoreMath.median(week), 81)
        XCTAssertLessThan(week.reduce(0, +) / 7, 75)
    }

    // MARK: weakest group

    func testWeakestIsTheLowestMedianNotTheLowestSingleNight() {
        // Recovery is worse on average; duration merely had one terrible night.
        let weakest = SleepScoreMath.weakest([
            (key: "duration", values: [95, 92, 8]),
            (key: "recovery", values: [55, 58, 52]),
        ])
        XCTAssertEqual(weakest, "recovery")
    }

    func testAGroupWithNoValuesCannotBeTheWeakest() {
        let weakest = SleepScoreMath.weakest([
            (key: "regularity", values: []),
            (key: "duration", values: [70]),
        ])
        XCTAssertEqual(weakest, "duration")
    }

    func testWeakestOfNothingIsNil() {
        XCTAssertNil(SleepScoreMath.weakest([(key: "a", values: [Double]())]))
    }

    /// A tie must not flicker between two groups from one morning to the next.
    func testTiesGoToTheGivenOrder() {
        XCTAssertEqual(SleepScoreMath.weakest([
            (key: "duration", values: [60]),
            (key: "recovery", values: [60]),
        ]), "duration")
    }

    // MARK: bedtime

    func testBedClockUnwindsTheEveningOffset() {
        XCTAssertEqual(SleepScoreMath.bedClock(offset: 330), "23:30")   // 18:00 + 5h30
        XCTAssertEqual(SleepScoreMath.bedClock(offset: 0), "18:00")
    }

    /// The offset exists so that a bedtime after midnight stays near an evening one. It has
    /// to survive the trip back out.
    func testBedClockCrossesMidnight() {
        XCTAssertEqual(SleepScoreMath.bedClock(offset: 440), "01:20")
        XCTAssertEqual(SleepScoreMath.bedClock(offset: 340), "23:40")
    }

    func testBedClockHandlesAnOffsetThatWrappedPastTheDay() {
        XCTAssertEqual(SleepScoreMath.bedClock(offset: 1440 + 330), "23:30")
        XCTAssertEqual(SleepScoreMath.bedClock(offset: -60), "17:00")
    }

    // MARK: stage proportions

    func testStagesRenormaliseToOneHundred() {
        let shares = SleepScoreMath.renormalised([20, 55, 20])
        XCTAssertEqual(shares.reduce(0, +), 100, accuracy: 0.001)
    }

    /// Nights the band filed no stage line for contribute no REM. The bar must still read
    /// as a whole rather than leaving a third of itself silently unaccounted for.
    func testDeepAndLightAloneStillFillTheBar() {
        let shares = SleepScoreMath.renormalised([26, 62])
        XCTAssertEqual(shares.reduce(0, +), 100, accuracy: 0.001)
        XCTAssertEqual(shares[0], 26.0 / 88 * 100, accuracy: 0.001)
    }

    func testEmptyStagesDoNotDivideByZero() {
        XCTAssertEqual(SleepScoreMath.renormalised([0, 0]), [0, 0])
    }
}
