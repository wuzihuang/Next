import XCTest
@testable import NextBodySyncCore

final class BodyBatteryWindowMathTests: XCTestCase {

    func testMonthIsThirtyUserDaysNotACalendarMonth() {
        XCTAssertEqual(DetailWindow(.bodyBattery, .day).days, 1)
        XCTAssertEqual(DetailWindow(.bodyBattery, .week).days, 7)
        XCTAssertEqual(DetailWindow(.bodyBattery, .month).days, 30)
        XCTAssertEqual(DetailWindow(.bodyBattery, .day).periodKey, "TODAY")
        XCTAssertEqual(DetailWindow(.bodyBattery, .week).periodKey, "LAST 7 DAYS")
        XCTAssertEqual(DetailWindow(.bodyBattery, .month).periodKey, "LAST 30 DAYS")
        XCTAssertEqual(DetailWindow(.bodyBattery, .month).load, .dailyResults(lookback: 29))
    }

    func testAverageIgnoresEmptySlotsAndKeepsTodayIfItHasAWake() {
        let today = UserDay.containing(Date())
        let facts = [
            fact(today.adding(days: -6), wake: 80),
            fact(today.adding(days: -5), wake: nil),
            fact(today.adding(days: -4), wake: 70),
            fact(today.adding(days: -3), wake: 74),
            fact(today.adding(days: -2), wake: nil),
            fact(today.adding(days: -1), wake: 68),
            fact(today, wake: 84, open: true),
        ]
        XCTAssertEqual(BodyBatteryWindowMath.averageWake(facts)!, 75.2, accuracy: 0.001)
        XCTAssertEqual(BodyBatteryWindowMath.typicalWake(facts)!, 75.2, accuracy: 0.001)
        XCTAssertEqual(BodyBatteryWindowMath.emptyCount(facts), 2)
        XCTAssertEqual(BodyBatteryWindowMath.wornCount(facts), 5)
        XCTAssertEqual(BodyBatteryWindowMath.peakDay(facts)?.wake, 84)
    }

    func testEmptyWindowPrintsNothingNotZero() {
        let today = UserDay.containing(Date())
        let facts = (0..<7).map { fact(today.adding(days: -$0), wake: nil) }
        XCTAssertNil(BodyBatteryWindowMath.averageWake(facts))
        XCTAssertNil(BodyBatteryWindowMath.typicalNightCharge(facts))
        XCTAssertEqual(BodyBatteryWindowMath.emptyCount(facts), 7)
        XCTAssertNil(BodyBatteryWindowMath.peakDay(facts))
    }

    func testTypicalNightChargeAveragesOnlyNightsThatPublished() {
        let today = UserDay.containing(Date())
        let facts = [
            fact(today.adding(days: -2), wake: 80, night: 40),
            fact(today.adding(days: -1), wake: 70, night: nil),
            fact(today, wake: 84, night: 38, open: true),
        ]
        XCTAssertEqual(BodyBatteryWindowMath.typicalNightCharge(facts)!, 39, accuracy: 0.001)
    }

    func testWeekRollsAreOldestFirstAndSkipEmptyDaysInTheAverage() {
        let today = UserDay.containing(Date())
        let facts = (0..<16).map { back -> BodyBatteryDayFacts in
            let day = today.adding(days: -(15 - back))
            if back == 3 { return fact(day, wake: nil) }
            return fact(day, wake: 70)
        }
        let rolls = BodyBatteryWindowMath.weekRolls(facts)
        XCTAssertEqual(rolls.count, 3)
        XCTAssertEqual(rolls[0].days, 2)
        XCTAssertEqual(rolls[1].days, 7)
        XCTAssertEqual(rolls[2].days, 7)
        XCTAssertEqual(rolls.last?.end, today)
        XCTAssertEqual(rolls[1].average!, 70, accuracy: 0.001)
    }

    private func fact(_ day: UserDay, wake: Int?, night: Double? = nil,
                      open: Bool = false) -> BodyBatteryDayFacts {
        BodyBatteryDayFacts(day: day, wake: wake, now: wake, nightCharge: night,
                            worn: wake != nil, isOpen: open)
    }
}
