import XCTest
@testable import NextBodySyncCore

final class TrainingWindowMathTests: XCTestCase {

    func testMonthIsThirtyUserDaysNotACalendarMonth() {
        XCTAssertEqual(DetailWindow(.training, .day).days, 1)
        XCTAssertEqual(DetailWindow(.training, .week).days, 7)
        XCTAssertEqual(DetailWindow(.training, .month).days, 30)
        XCTAssertEqual(DetailWindow(.training, .week).periodKey, "LAST 7 DAYS")
        XCTAssertEqual(DetailWindow(.training, .month).periodKey, "LAST 30 DAYS")
    }

    func testWindowWalksBackFromTodayOldestFirst() {
        let today = UserDay.containing(Date())
        let days = today.rollingBack(7)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last, today)
        XCTAssertEqual(days.first, today.adding(days: -6))
    }

    func testAverageIgnoresTodayAndEmptySlots() {
        let today = UserDay.containing(Date())
        let facts = [
            fact(today.adding(days: -6), load: 14.0),
            fact(today.adding(days: -5), load: nil),
            fact(today.adding(days: -4), load: 10.0),
            fact(today.adding(days: -3), load: 12.0),
            fact(today.adding(days: -2), load: nil),
            fact(today.adding(days: -1), load: 8.0),
            fact(today, load: 3.0, open: true),
        ]
        XCTAssertEqual(TrainingWindowMath.averageLoad(facts)!, 11.0, accuracy: 0.001)
        XCTAssertEqual(TrainingWindowMath.typicalLoad(facts)!, 11.0, accuracy: 0.001)
        XCTAssertEqual(TrainingWindowMath.wornCount(facts), 5)
        XCTAssertEqual(TrainingWindowMath.emptyCount(facts), 2)
    }

    func testEmptyWindowPrintsNothingNotZero() {
        let today = UserDay.containing(Date())
        let facts = (0..<7).map { fact(today.adding(days: -$0), load: nil) }
        XCTAssertNil(TrainingWindowMath.averageLoad(facts))
        XCTAssertNil(TrainingWindowMath.typicalZones(facts))
        XCTAssertEqual(TrainingWindowMath.wornCount(facts), 0)
    }

    func testTypicalZonesAverageOnlyDaysThatPublishedZones() {
        let today = UserDay.containing(Date())
        let facts = [
            fact(today.adding(days: -2), load: 12, zones: [60, 30, 20, 10, 5]),
            fact(today.adding(days: -1), load: 8, zones: nil),
            fact(today, load: 10, zones: [40, 20, 10, 20, 5], open: true),
        ]
        let zones = TrainingWindowMath.typicalZones(facts)
        XCTAssertEqual(zones, [60, 30, 20, 10, 5])
    }

    func testSessionDaysNeedTwentyHardMinutes() {
        let today = UserDay.containing(Date())
        let facts = [
            fact(today.adding(days: -2), load: 16, zones: [10, 10, 10, 15, 10]),
            fact(today.adding(days: -1), load: 9, zones: [40, 20, 10, 5, 0]),
            fact(today, load: 12, zones: [10, 10, 10, 30, 0]),
        ]
        XCTAssertEqual(TrainingWindowMath.sessionDays(facts), 2)
    }

    func testBandUsesTheDayZoneAndCapsOver() {
        XCTAssertEqual(TrainingWindowMath.band(load: 12.4, zone: 12...16.5), .steady)
        XCTAssertEqual(TrainingWindowMath.band(load: 10.0, zone: 12...16.5), .light)
        XCTAssertEqual(TrainingWindowMath.band(load: 17.0, zone: 12...16.5), .heavy)
        XCTAssertEqual(TrainingWindowMath.band(load: 20.9, zone: 12...16.5), .over)
        XCTAssertEqual(TrainingWindowMath.band(load: 9.0, zone: nil), .steady)
    }

    func testWeekRollsAreOldestFirstAndSkipEmptyDaysInTheAverage() {
        let today = UserDay.containing(Date())
        let facts = (0..<16).map { back -> TrainingDayFacts in
            let day = today.adding(days: -(15 - back))
            if back == 3 { return fact(day, load: nil) }
            return fact(day, load: 10)
        }
        let rolls = TrainingWindowMath.weekRolls(facts)
        XCTAssertEqual(rolls.count, 3)
        XCTAssertEqual(rolls[0].days, 2)
        XCTAssertEqual(rolls[1].days, 7)
        XCTAssertEqual(rolls[2].days, 7)
        XCTAssertEqual(rolls.last?.end, today)
        XCTAssertEqual(rolls[1].average!, 10, accuracy: 0.001)
    }

    func testHoursInUserDayStartAtTheFourOClockCut() {
        let day = UserDay.containing(Date())
        XCTAssertEqual(UserDay.hours(day.start, in: day), 0, accuracy: 0.001)
        XCTAssertEqual(UserDay.hours(day.end, in: day), 24, accuracy: 0.001)
    }

    private func fact(_ day: UserDay, load: Double?, zones: [Int]? = nil, open: Bool = false) -> TrainingDayFacts {
        TrainingDayFacts(day: day, load: load, target: nil, zone: nil,
                         zoneMinutes: zones, steps: nil, activeKcal: nil,
                         totalKcal: nil, worn: load != nil, isOpen: open)
    }
}
