import XCTest
@testable import NextBodySyncCore

final class RollingPillsTests: XCTestCase {
    func testDefaultUserDaysAreOneSevenThirty() {
        XCTAssertEqual(RollingPills.day.userDays, 1)
        XCTAssertEqual(RollingPills.week.userDays, 7)
        XCTAssertEqual(RollingPills.month.userDays, 30)
        XCTAssertEqual(RollingPills.month.userDays(month: 28), 28)
    }

    func testDefaultPeriodKeysAreTodayAndLastNDays() {
        XCTAssertEqual(RollingPills.day.periodKey, "TODAY")
        XCTAssertEqual(RollingPills.week.periodKey, "LAST 7 DAYS")
        XCTAssertEqual(RollingPills.month.periodKey, "LAST 30 DAYS")
        XCTAssertEqual(
            RollingPills.month.periodKey(week: "7 DAYS", month: "4 WEEKS"),
            "4 WEEKS")
        XCTAssertEqual(
            RollingPills.day.periodKey(day: "LAST 24H"),
            "LAST 24H")
    }

    func testParseFallsBackToDay() {
        XCTAssertEqual(RollingPills.parse("WEEK"), .week)
        XCTAssertEqual(RollingPills.parse("nope"), .day)
        XCTAssertEqual(RollingPills.words, ["DAY", "WEEK", "MONTH"])
    }
}
