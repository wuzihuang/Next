import XCTest
@testable import NextBodySyncCore

final class FuelWindowMathTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testMonthIsFourWeeksNotThirtyDays() {
        XCTAssertEqual(DetailWindow(.fuel, .day).days, 1)
        XCTAssertEqual(DetailWindow(.fuel, .week).days, 7)
        XCTAssertEqual(DetailWindow(.fuel, .month).days, 28)
        XCTAssertEqual(DetailWindow(.fuel, .week).periodKey, "7 DAYS")
        XCTAssertEqual(DetailWindow(.fuel, .month).periodKey, "4 WEEKS")
    }

    func testWindowWalksBackFromTodayOldestFirst() {
        let today = UserDay.containing(Date())
        let days = today.rollingBack(7)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last, today)
        XCTAssertEqual(days.first, today.adding(days: -6))
    }

    func testWeekSumIncludesAFastedZeroAndAShortToday() {
        let today = UserDay.containing(Date())
        let facts = [
            fact(today.adding(days: -6), intake: 2840, burned: 2710, foods: 6),
            fact(today.adding(days: -5), intake: 2650, burned: 2890, foods: 5),
            fact(today.adding(days: -4), intake: 0, burned: 2180, foods: 0, fasted: true),
            fact(today.adding(days: -3), intake: 3120, burned: 2760, foods: 8),
            fact(today.adding(days: -2), intake: 2410, burned: 2680, foods: 4),
            fact(today.adding(days: -1), intake: 2780, burned: 2540, foods: 6),
            fact(today, intake: 1070, burned: 820, foods: 3, open: true),
        ]
        let total = FuelWindowMath.sum(facts)
        XCTAssertEqual(total?.intake, 14_870)
        XCTAssertEqual(total?.burned, 16_580)
        XCTAssertEqual(total?.gap, -1_710)
        let per = FuelWindowMath.perDay(sum: total!, slots: 7)
        XCTAssertEqual(per?.intake ?? 0, 2_124.285, accuracy: 0.01)
    }

    func testEmptyWindowHasNoSum() {
        let today = UserDay.containing(Date())
        let facts = (0..<7).map { fact(today.adding(days: -$0), intake: nil, burned: nil, foods: 0) }
        XCTAssertNil(FuelWindowMath.sum(facts))
    }

    func testTypicalDayIsTheMeanOfWeekPerDayNumbersNotAMonthlyTotal() {
        let today = UserDay.containing(Date())
        var facts: [FuelDayFacts] = []
        let weeklyIn = [2_480.0, 2_210.0, 2_540.0, 2_120.0]
        for (week, daily) in weeklyIn.enumerated() {
            for day in 0..<7 {
                facts.append(fact(
                    today.adding(days: -((3 - week) * 7 + (6 - day))),
                    intake: daily, burned: daily + 200, foods: 4))
            }
        }
        let rolls = FuelWindowMath.weekRolls(facts)
        XCTAssertEqual(rolls.count, 4)
        XCTAssertEqual(rolls.first?.end, today)
        let typical = FuelWindowMath.typicalDay(rolls)
        XCTAssertEqual(typical?.intake ?? 0, 2_337.5, accuracy: 0.01)
        XCTAssertLessThan(typical?.intake ?? 0, 10_000)
    }

    func testClockFractionPutsAfternoonOnTheRightHalf() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 4))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 13, minute: 20))!
        XCTAssertEqual(FuelWindowMath.clockFraction(at: now, dayStart: start, calendar: calendar),
                       13.333 / 24, accuracy: 0.002)
        let late = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 1, minute: 20))!
        XCTAssertEqual(FuelWindowMath.clockFraction(at: late, dayStart: start, calendar: calendar), 1, accuracy: 0.001)
    }

    func testIntakeStepsJumpAtMealsAndHoldUntilNow() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 4))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 13, minute: 20))!
        let oats = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 7, minute: 40))!
        let lunch = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 12, minute: 35))!
        let line = FuelWindowMath.intakeSteps(
            meals: [(oats, 350), (lunch, 720)],
            dayStart: start, now: now, projectTo: 2_900, calendar: calendar)
        XCTAssertEqual(line.solid.last?.y, 1_070)
        XCTAssertEqual(line.dashed.last?.y, 2_900)
        XCTAssertGreaterThan(line.solid.last?.x ?? 0, 0.5)
        XCTAssertLessThan(line.solid.last?.x ?? 1, 0.6)
    }

    func testBurnLineStartsAtTheUserDayOpen() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 4))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 13, minute: 20))!
        let line = FuelWindowMath.burnLine(
            dayStart: start, now: now, burnedNow: 820, burnedFull: 2_280, calendar: calendar)
        XCTAssertEqual(line.solid.first?.x ?? 0, 4.0 / 24, accuracy: 0.001)
        XCTAssertEqual(line.solid.first?.y, 0)
        XCTAssertEqual(line.solid.last?.y, 820)
        XCTAssertEqual(line.dashed.last?.y, 2_280)
    }

    func testBurnCurveSteepensWhenStepsCluster() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 4))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 13, minute: 20))!
        var ticks: [(Date, Int?)] = []
        var cursor = start
        while cursor <= now {
            let hour = calendar.component(.hour, from: cursor)
            ticks.append((cursor, hour == 11 ? 400 : 8))
            cursor = calendar.date(byAdding: .minute, value: 5, to: cursor)!
        }
        let line = FuelWindowMath.burnCurve(
            dayStart: start, now: now, burnedNow: 820, burnedFull: 2_280,
            ticks: ticks, calendar: calendar)
        XCTAssertEqual(line.solid.last?.y, 820)
        XCTAssertGreaterThan(line.solid.count, 4)
        let midMorning = line.solid.last { $0.x < (10.0 / 24) }
        let afterWalk = line.solid.last { $0.x < (12.0 / 24) }
        let morningRise = (midMorning?.y ?? 0)
        let walkRise = (afterWalk?.y ?? 0) - morningRise
        XCTAssertGreaterThan(walkRise, morningRise * 0.15,
                             "a 400-step hour must bend the cyan line, not sit on a ruler")
    }

    private func fact(_ day: UserDay, intake: Double?, burned: Double?, foods: Int,
                      fasted: Bool = false, open: Bool = false) -> FuelDayFacts {
        FuelDayFacts(day: day, intake: intake, burned: burned,
                     foodCount: foods, isFasted: fasted, isOpen: open)
    }
}
