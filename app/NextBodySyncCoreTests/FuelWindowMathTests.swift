import XCTest
@testable import NextBodySyncCore

final class FuelWindowMathTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testMeasuredMETWinsOverStepsAndInvalidMETFallsBackToCadence() {
        XCTAssertEqual(FuelWindowMath.activityMet(met: 6, steps: 0), 6)
        XCTAssertEqual(FuelWindowMath.activityMet(met: 0, steps: 500), 3)
        XCTAssertEqual(FuelWindowMath.activityMet(met: .nan, steps: 500), 3)
        XCTAssertNil(FuelWindowMath.activityMet(met: 26, steps: nil))
    }

    func testBurnCurveKeepsTheSettledRestingSlopeAndIncludesTheOpeningTick() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 4))!
        let now = start.addingTimeInterval(8 * 3600)
        let middle = start.addingTimeInterval(4 * 3600)
        let ticks = [VitalSample(ts: start, hr: nil, stress: nil, steps: 0, met: 6),
                     VitalSample(ts: middle, hr: nil, stress: nil, steps: 0, met: 1)]
        let line = FuelWindowMath.burnCurve(dayStart: start, now: now,
            burnedNow: 800, burnedFull: 1_800, restingNow: 500, ticks: ticks, calendar: calendar)
        XCTAssertEqual(line.solid.last?.y, 800)
        let middleX = FuelWindowMath.clockFraction(at: middle, dayStart: start, calendar: calendar)
        XCTAssertEqual(line.solid.last(where: { $0.x == middleX })?.y, 550,
                       "300 activity at the opening tick plus half of 500 resting")
    }

    func testSettledMovementWithoutTimedEvidenceHasNoInventedCurve() {
        let start = Date()
        let line = FuelWindowMath.burnCurve(dayStart: start, now: start.addingTimeInterval(3600),
            burnedNow: 500, burnedFull: 2_000, restingNow: 60, ticks: [], calendar: calendar)
        XCTAssertTrue(line.solid.isEmpty)
    }

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

    func testUnknownChannelStaysNilAndDifferentDaysCannotCreateADifference() {
        let today = UserDay.containing(Date())
        let onlyBurn = FuelWindowMath.sum([fact(today, intake: nil, burned: 2_000, foods: 0)])
        XCTAssertNil(onlyBurn?.intake)
        XCTAssertNil(onlyBurn?.gap)
        let mismatched = FuelWindowMath.sum([
            fact(today.adding(days: -1), intake: 1_800, burned: nil, foods: 3),
            fact(today, intake: nil, burned: 2_000, foods: 0),
        ])
        XCTAssertEqual(mismatched?.intake, 1_800)
        XCTAssertEqual(mismatched?.burned, 2_000)
        XCTAssertNil(mismatched?.gap)
        XCTAssertEqual(mismatched?.pairedDays, 0)
    }

    func testTypicalDayUsesObservedClosedDaysAndPairsDifferences() {
        let today = UserDay.containing(Date())
        var facts = (0..<28).map {
            fact(today.adding(days: $0 - 27), intake: nil, burned: nil, foods: 0)
        }
        facts[0] = fact(facts[0].day, intake: 1_800, burned: 2_000, foods: 3)
        facts[8] = fact(facts[8].day, intake: 2_200, burned: nil, foods: 3)
        facts[9] = fact(facts[9].day, intake: 2_300, burned: nil, foods: 3)
        facts[27] = fact(today, intake: 200, burned: 150, foods: 1, open: true)
        let typical = FuelWindowMath.typicalDay(FuelWindowMath.weekRolls(facts))
        XCTAssertEqual(typical?.intake, 2_100)
        XCTAssertEqual(typical?.burned, 2_000)
        XCTAssertEqual(typical?.gap, -200)
        XCTAssertEqual(typical?.intakeDays, 3)
        XCTAssertEqual(typical?.burnedDays, 1)
        XCTAssertEqual(typical?.pairedDays, 1)
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

    func testClockFractionKeepsTheWholeUserDayIncludingAfterMidnight() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 4))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 13, minute: 20))!
        XCTAssertEqual(FuelWindowMath.clockFraction(at: now, dayStart: start, calendar: calendar),
                       9.333 / 24, accuracy: 0.002)
        let late = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 1, minute: 20))!
        XCTAssertEqual(FuelWindowMath.clockFraction(at: late, dayStart: start, calendar: calendar), 21.333 / 24, accuracy: 0.001)
    }

    func testClockAndLabelsUseTheActualDSTUserDayDuration() {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(identifier: "America/New_York")!
        for (month, day, hours) in [(3, 7, 23.0), (10, 31, 25.0)] {
            let start = local.date(from: DateComponents(year: 2026, month: month, day: day, hour: 4))!
            let end = FuelWindowMath.dayEnd(dayStart: start, calendar: local)
            XCTAssertEqual(end.timeIntervalSince(start) / 3600, hours)
            XCTAssertEqual(FuelWindowMath.clockFraction(at: start.addingTimeInterval(hours * 1800),
                                                       dayStart: start, calendar: local), 0.5)
            XCTAssertEqual(FuelWindowMath.clockFraction(at: end, dayStart: start, calendar: local), 1)
            let labels = FuelWindowMath.clockLabels(dayStart: start, calendar: local)
            XCTAssertEqual(labels.first, "04")
            XCTAssertEqual(labels.last, "04")
            XCTAssertEqual(labels.count, 5)
        }
    }

    func testUserDayStillStartsAtFourOnTheDSTTransitionDate() {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(identifier: "America/New_York")!
        for (month, day) in [(3, 8), (11, 1)] {
            let noon = local.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
            let userDay = UserDay.containing(noon, calendar: local)
            XCTAssertEqual(local.component(.hour, from: userDay.start), 4)
        }
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
        XCTAssertGreaterThan(line.solid.last?.x ?? 0, 0.3)
        XCTAssertLessThan(line.solid.last?.x ?? 1, 0.4)
    }

    func testBurnLineStartsAtTheUserDayOpen() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 4))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 13, minute: 20))!
        let line = FuelWindowMath.burnLine(
            dayStart: start, now: now, burnedNow: 820, burnedFull: 2_280, calendar: calendar)
        XCTAssertEqual(line.solid.first?.x ?? 0, 0, accuracy: 0.001)
        XCTAssertEqual(line.solid.first?.y, 0)
        XCTAssertEqual(line.solid.last?.y, 820)
        XCTAssertEqual(line.dashed.last?.y, 2_280)
    }

    func testBurnCurveSteepensWhenStepsCluster() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 4))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 13, minute: 20))!
        var ticks: [VitalSample] = []
        var cursor = start
        while cursor <= now {
            let hour = calendar.component(.hour, from: cursor)
            ticks.append(VitalSample(ts: cursor, hr: nil, stress: nil, steps: hour == 11 ? 400 : 8))
            cursor = calendar.date(byAdding: .minute, value: 5, to: cursor)!
        }
        let line = FuelWindowMath.burnCurve(
            dayStart: start, now: now, burnedNow: 820, burnedFull: 2_280,
            restingNow: 700, ticks: ticks, calendar: calendar)
        XCTAssertEqual(line.solid.last?.y, 820)
        XCTAssertGreaterThan(line.solid.count, 4)
        let midMorning = line.solid.last { $0.x < (6.0 / 24) }
        let afterWalk = line.solid.last { $0.x < (8.0 / 24) }
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
