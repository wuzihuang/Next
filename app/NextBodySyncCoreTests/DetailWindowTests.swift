import XCTest
@testable import NextBodySyncCore

final class DetailWindowTests: XCTestCase {
    func testFuelMonthIsFourWeeksEveryoneElseIsThirty() {
        XCTAssertEqual(DetailWindow(.fuel, .month).days, 28)
        XCTAssertEqual(DetailWindow(.heart, .month).days, 30)
        XCTAssertEqual(DetailWindow(.sleep, .month).days, 30)
        XCTAssertEqual(DetailWindow(.training, .month).days, 30)
        XCTAssertEqual(DetailWindow(.bodyBattery, .month).days, 30)
        XCTAssertEqual(DetailWindow(.composition, .month).days, 30)
        XCTAssertEqual(DetailWindow(.battery, .month).days, 30)
        XCTAssertEqual(DetailWindow(.metric, .week).days, 7)
        XCTAssertEqual(DetailWindow(.response, .day).days, 1)
    }

    func testPeriodKeysStayPerInstrument() {
        XCTAssertEqual(DetailWindow(.fuel, .week).periodKey, "7 DAYS")
        XCTAssertEqual(DetailWindow(.fuel, .month).periodKey, "4 WEEKS")
        XCTAssertEqual(DetailWindow(.heart, .day).periodKey, "TODAY")
        XCTAssertEqual(DetailWindow(.heart, .week).periodKey, "LAST 7 DAYS")
        XCTAssertEqual(DetailWindow(.sleep, .week).periodKey, "LAST 7 NIGHTS")
        XCTAssertEqual(DetailWindow(.sleep, .month).periodKey, "LAST 30 NIGHTS")
        XCTAssertEqual(DetailWindow(.training, .day).periodKey, "TODAY")
        XCTAssertEqual(DetailWindow(.bodyBattery, .day).periodKey, "TODAY")
        XCTAssertEqual(DetailWindow(.battery, .day).periodKey, "TODAY")
        XCTAssertEqual(DetailWindow(.metric, .day).periodKey, "")
    }

    func testHeartSlotsAreQuarterHourOnDayAndOneBarADayAfter() {
        XCTAssertEqual(DetailWindow(.heart, .day).slotMinutes, 15)
        XCTAssertEqual(DetailWindow(.heart, .week).slotMinutes, 1440)
        XCTAssertEqual(DetailWindow(.heart, .month).slotMinutes, 1440)
        XCTAssertEqual(DetailWindow(.metric, .day).slotMinutes, 15)
    }

    func testBatteryHoursAreRollingNotCalendar() {
        XCTAssertEqual(DetailWindow(.battery, .day).hours, 24)
        XCTAssertEqual(DetailWindow(.battery, .week).hours, 7 * 24)
        XCTAssertEqual(DetailWindow(.battery, .month).hours, 30 * 24)
    }

    func testLoadDoesNotAskThePageToPickALoader() {
        XCTAssertEqual(DetailWindow(.fuel, .day).load, .dailyResults(lookback: 27))
        XCTAssertEqual(DetailWindow(.training, .week).load, .dailyResults(lookback: 29))
        XCTAssertEqual(DetailWindow(.bodyBattery, .month).load, .dailyResults(lookback: 29))
        XCTAssertEqual(DetailWindow(.heart, .day).load, .none)
        XCTAssertEqual(DetailWindow(.heart, .week).load, .heartTicks(days: 7))
        XCTAssertEqual(DetailWindow(.metric, .month).load, .heartTicks(days: 30))
        XCTAssertEqual(DetailWindow(.metric, .week).load, .heartTicks(days: 14))
        XCTAssertEqual(DetailWindow(.active, .day).load, .dailyResults(lookback: 6))
        XCTAssertEqual(DetailWindow(.active, .month).load,
                       .dailyResultsAndHeartTicks(lookback: 29, heartDays: 30))
        XCTAssertEqual(
            DetailWindow(.active, .week).load,
            .dailyResultsAndHeartTicks(lookback: 6, heartDays: 7))
        XCTAssertEqual(DetailWindow(.composition, .day).load, .composition)
        XCTAssertEqual(DetailWindow(.sleep, .month).load, .none)
        XCTAssertEqual(DetailWindow(.battery, .day).load, .dailyResults(lookback: 29))
    }

    func testRollingBackWalksOldestFirst() {
        let today = UserDay.containing(Date())
        let days = today.rollingBack(7)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last, today)
        XCTAssertEqual(days.first, today.adding(days: -6))
        XCTAssertEqual(today.rollingBack(0), [])
    }

    func testContainingHonoursAPassedCalendar() {
        var gmt = Calendar(identifier: .gregorian)
        gmt.timeZone = TimeZone(secondsFromGMT: 0)!
        let three = gmt.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 3))!
        let day = UserDay.containing(three, calendar: gmt)
        // Issue #19 · 03:00 is the small hours of the 6th, not the tail of the 5th.
        XCTAssertEqual(day.start, gmt.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 0)))
    }
}
