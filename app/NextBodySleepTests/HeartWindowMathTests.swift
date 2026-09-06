import XCTest
@testable import NextBodySleepCore

final class HeartWindowMathTests: XCTestCase {

    func testMedianOfDailyMediansIgnoresAnEmptyDay() {
        let daily: [[Double]] = [
            [60, 62, 64],
            [],
            [80, 82],
        ]
        XCTAssertEqual(HeartWindowMath.medianOfDailyMedians(daily), 71.5)
        XCTAssertEqual(HeartWindowMath.wornDays(daily), 2)
    }

    func testASingleQuietHourDoesNotDragTheWeek() {
        let daily: [[Double]] = [
            [60, 61, 62],
            [60, 61, 62],
            [60, 61, 180],
        ]
        XCTAssertEqual(HeartWindowMath.medianOfDailyMedians(daily), 61)
        XCTAssertEqual(HeartWindowMath.extreme(daily, pick: max), 180)
    }

    func testEmptyWindowPrintsNothingNotZero() {
        XCTAssertNil(HeartWindowMath.medianOfDailyMedians([[], [], []]))
        XCTAssertEqual(HeartWindowMath.wornDays([[], []]), 0)
        XCTAssertNil(HeartWindowMath.extreme([[]], pick: max))
    }

    func testEqualSlotsDivideADstWeekWithoutInventingAnEighthDay() {
        let span: TimeInterval = 7 * 86400 - 3600
        let seconds = HeartWindowMath.slotSeconds(span: span, days: 7)
        XCTAssertEqual(seconds * 7, span, accuracy: 0.001)
        XCTAssertEqual(HeartWindowMath.slotIndex(fraction: 0, days: 7), 0)
        XCTAssertEqual(HeartWindowMath.slotIndex(fraction: 0.999, days: 7), 6)
        XCTAssertEqual(HeartWindowMath.slotIndex(fraction: 1, days: 7), 6)
    }
}
