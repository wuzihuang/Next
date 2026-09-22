import XCTest
@testable import NextBodySyncCore

final class ActiveEnergyMathTests: XCTestCase {
    func testPublishedStrengthEnergyHasCurveAndSportShareWithoutOriginSamples() {
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(3600)
        let points = [FuelEnergyPoint(epoch: 1800, originWeight: 0, strengthWeight: 750)]
        let split = ActiveEnergyMath.split(dayStart: start, now: now, bmr: 80,
            bmrFull: 1920, eActive: 10, eTrain: nil, eOutNow: 90,
            ticks: [], sportWindows: [], energyDistribution: points)
        XCTAssertEqual(split.sport, 10)
        XCTAssertNil(split.steps)
        let curve = FuelWindowMath.burnCurve(dayStart: start, now: now, burnedNow: 90,
            burnedFull: nil, restingNow: 80, ticks: points.map(\.tick))
        XCTAssertFalse(curve.solid.isEmpty)
        XCTAssertEqual(curve.solid.last?.y, 90)
        XCTAssertTrue(curve.solid.contains { abs($0.y - 50) < 0.001 })
    }
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testMissingMovementDoesNotBecomeZeroActiveOrBasalOnlyOut() {
        let totals = ActiveEnergyMath.totals(bmr: 500, eActive: nil, eTrain: nil, eOutNow: nil)
        XCTAssertEqual(totals.resting, 500)
        XCTAssertNil(totals.active)
        XCTAssertNil(totals.out)
    }

    func testLegacyOutDoesNotOverwriteExplicitActivity() {
        let totals = ActiveEnergyMath.totals(bmr: 1_965, eActive: 524, eTrain: nil, eOutNow: 2_479)
        XCTAssertEqual(totals.active, 524)
        XCTAssertEqual(totals.out, 2_489)
    }

    func testSampleExactlyAtNowDoesNotLoseEnergyIntoAnUnstartedHour() {
        let ticks = [VitalSample(ts: date(hour: 12), hr: nil, stress: nil, steps: 0, met: 6)]
        let split = ActiveEnergyMath.split(
            dayStart: date(hour: 4), now: date(hour: 12), bmr: 500, bmrFull: 1_500,
            eActive: 175, eTrain: nil, eOutNow: 675, ticks: ticks, sportWindows: [])
        let hours = ActiveEnergyMath.hourly(dayStart: date(hour: 4), now: date(hour: 12),
                                           split: split, ticks: ticks, sportWindows: [])
        XCTAssertEqual(hours.filter(\.lived).reduce(0) { $0 + $1.kcal }, 175, accuracy: 0.01)
    }

    func testDSTHoursRetainEveryRecordedCalorieAndRecoverTheFullDayBMR() {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(identifier: "America/New_York")!
        for (month, day, count) in [(3, 7, 23), (10, 31, 25)] {
            let start = local.date(from: DateComponents(year: 2026, month: month, day: day, hour: 4))!
            let end = FuelWindowMath.dayEnd(dayStart: start, calendar: local)
            let middle = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            XCTAssertEqual(ActiveEnergyMath.derivedBmrFull(bmr: 850, bmrFull: nil,
                dayStart: start, now: middle, calendar: local), 1_700)
            let ticks = [VitalSample(ts: end.addingTimeInterval(-600), hr: nil, stress: nil, steps: 0, met: 6)]
            let split = ActiveEnergyMath.split(dayStart: start, now: end, bmr: 1_700, bmrFull: 1_700,
                eActive: 175, eTrain: nil, eOutNow: 1_875, ticks: ticks, sportWindows: [], calendar: local)
            let hours = ActiveEnergyMath.hourly(dayStart: start, now: end, split: split,
                ticks: ticks, sportWindows: [], calendar: local)
            XCTAssertEqual(hours.count, count)
            XCTAssertEqual(hours.reduce(0) { $0 + $1.kcal }, 175, accuracy: 0.01)
            XCTAssertEqual(ActiveEnergyMath.peakHour(hours)?.index, count - 1)
        }
    }

    func testUnattributedActivityDoesNotCreateAPeakInTheLastHour() {
        let start = date(hour: 4)
        let now = date(hour: 12)
        let split = ActiveEnergyMath.split(
            dayStart: start, now: now, bmr: 500, bmrFull: 1_500,
            eActive: 300, eTrain: nil, eOutNow: 800,
            ticks: [], sportWindows: [], calendar: calendar)
        let hours = ActiveEnergyMath.hourly(dayStart: start, now: now, split: split,
                                           ticks: [], sportWindows: [], calendar: calendar)
        XCTAssertTrue(hours.isEmpty, "An aggregate without timed movement cannot identify an hourly peak")
    }

    func testNativeMETWithZeroStepsStillAllocatesCyclingEnergyToItsRecordedHour() {
        let start = date(hour: 4)
        let now = date(hour: 12)
        let ticks = [VitalSample(ts: date(hour: 8), hr: 130, stress: nil, steps: 0, met: 6)]
        let split = ActiveEnergyMath.split(
            dayStart: start, now: now, bmr: 500, bmrFull: 1_500,
            eActive: 175, eTrain: nil, eOutNow: 675,
            ticks: ticks, sportWindows: [], calendar: calendar)
        XCTAssertEqual(split.sport, 175)
        XCTAssertEqual(split.sportMet, 6)
        XCTAssertNil(split.steps)
        let hours = ActiveEnergyMath.hourly(dayStart: start, now: now, split: split,
                                           ticks: ticks, sportWindows: [], calendar: calendar)
        XCTAssertEqual(ActiveEnergyMath.peakHour(hours)?.index, 4)
        XCTAssertEqual(hours.filter(\.lived).reduce(0) { $0 + $1.kcal }, 175, accuracy: 0.01)
    }

    func testPrintedRoundedPartsStillAddToTheSettledActiveTotal() {
        let ticks = [6.0, 2.0, 1.25].enumerated().map { i, met in
            VitalSample(ts: date(hour: 8, minute: i * 5), hr: nil, stress: nil, steps: 0, met: met)
        }
        let split = ActiveEnergyMath.split(
            dayStart: date(hour: 4), now: date(hour: 12), bmr: 500, bmrFull: 1_500,
            eActive: 17, eTrain: nil, eOutNow: 517,
            ticks: ticks, sportWindows: [], calendar: calendar)
        XCTAssertEqual([split.sport, split.steps, split.incidental].compactMap { $0 }.reduce(0, +), 17)
        for part in [split.sport, split.steps, split.incidental].compactMap({ $0 }) {
            XCTAssertEqual(part, part.rounded())
        }
    }

    func testMissingIntensityDoesNotInventAStillMETReading() {
        let result = ActiveEnergyMath.intensity(dayStart: date(hour: 4), now: date(hour: 12),
            ticks: [VitalSample(ts: date(hour: 8), hr: 90, stress: nil)], calendar: calendar)
        XCTAssertTrue(result.solid.isEmpty)
        XCTAssertTrue(result.dashed.isEmpty)
    }

    func testIntensityBreaksAcrossMissingSlotsAndDoesNotExtendTheLastReadingToNow() {
        let first = date(hour: 8), next = date(hour: 10)
        let result = ActiveEnergyMath.intensity(dayStart: date(hour: 4), now: date(hour: 12),
            ticks: [VitalSample(ts: first, hr: nil, stress: nil, met: 6),
                    VitalSample(ts: date(hour: 8, minute: 5), hr: 90, stress: nil),
                    VitalSample(ts: next, hr: nil, stress: nil, met: 2)], calendar: calendar)
        XCTAssertEqual(result.solid.count, 4)
        XCTAssertTrue(result.solid[2].startsSegment)
        XCTAssertEqual(result.solid[1].x, FuelWindowMath.clockFraction(
            at: first.addingTimeInterval(300), dayStart: date(hour: 4), calendar: calendar))
        XCTAssertEqual(result.solid.last?.x, FuelWindowMath.clockFraction(
            at: next.addingTimeInterval(300), dayStart: date(hour: 4), calendar: calendar))
    }

    func testAdjacentMeasuredIntensitySlotsStayConnected() {
        let result = ActiveEnergyMath.intensity(dayStart: date(hour: 4), now: date(hour: 12),
            ticks: [VitalSample(ts: date(hour: 8), hr: nil, stress: nil, met: 6),
                    VitalSample(ts: date(hour: 8, minute: 5), hr: nil, stress: nil, met: 2)], calendar: calendar)
        XCTAssertFalse(result.solid[2].startsSegment)
        XCTAssertEqual(result.solid[1].x, result.solid[2].x)
    }

    func testOutCurveIsTheCaloriesPageBurnCurve() {
        let start = date(hour: 4)
        let now = date(hour: 16, minute: 40)
        var ticks: [VitalSample] = []
        var cursor = start
        while cursor <= now {
            let hour = calendar.component(.hour, from: cursor)
            ticks.append(VitalSample(ts: cursor, hr: nil, stress: nil, steps: hour == 16 ? 400 : 8))
            cursor = calendar.date(byAdding: .minute, value: 5, to: cursor)!
        }
        let fuel = FuelWindowMath.burnCurve(
            dayStart: start, now: now, burnedNow: 1_387, burnedFull: 2_194,
            restingNow: 901, ticks: ticks, calendar: calendar)
        let active = ActiveEnergyMath.outCurve(
            dayStart: start, now: now, burnedNow: 1_387, burnedFull: 2_194,
            restingNow: 901, ticks: ticks, calendar: calendar)
        XCTAssertEqual(active.solid, fuel.solid)
        XCTAssertEqual(active.dashed, fuel.dashed)
        XCTAssertEqual(active.solid.last?.y, 1_387)
        XCTAssertEqual(active.dashed.last?.y, 2_194)
    }

    func testSplitPartsSumToSettledActiveAndCloseTheOutLedger() {
        let start = date(hour: 4)
        let now = date(hour: 16, minute: 40)
        let session = date(hour: 15, minute: 48)
        let ticks = walk(from: start, to: now) { hour, _ in
            if hour == 16 { return 900 }
            if hour == 7 || hour == 12 { return 220 }
            return hour >= 8 && hour <= 16 ? 40 : 0
        }
        let split = ActiveEnergyMath.split(
            dayStart: start, now: now, bmr: 901, bmrFull: 1_708,
            eActive: 486, eTrain: nil, eOutNow: 1_387,
            ticks: ticks,
            sportWindows: [(session, session.addingTimeInterval(52 * 60))],
            calendar: calendar)
        XCTAssertEqual(split.resting, 901)
        XCTAssertEqual(split.active, 486)
        XCTAssertEqual(split.out, 1_387)
        let parts = [split.sport, split.steps, split.incidental].compactMap { $0 }
        XCTAssertEqual(parts.reduce(0, +), 486, accuracy: 0.01)
        XCTAssertEqual((split.resting ?? 0) + (split.active ?? 0), 1_387, accuracy: 0.01)
        XCTAssertNotNil(split.sport)
        XCTAssertGreaterThan(split.sport ?? 0, split.steps ?? 0)
        XCTAssertGreaterThan(split.steps ?? 0, split.incidental ?? 0)
    }

    func testSittingTicksDoNotInventIncidentalAndAMissingPartStaysNil() {
        let start = date(hour: 4)
        let now = date(hour: 12)
        let ticks = walk(from: start, to: now) { _, _ in 0 }
        let split = ActiveEnergyMath.split(
            dayStart: start, now: now, bmr: 500, bmrFull: 1_500,
            eActive: 80, eTrain: nil, eOutNow: 580,
            ticks: ticks, sportWindows: [], calendar: calendar)
        XCTAssertNil(split.sport)
        XCTAssertNil(split.steps)
        XCTAssertNil(split.incidental)
        XCTAssertEqual(split.active, 80)
        XCTAssertEqual(split.out, 580)
    }

    func testLocalTrainFillsSportWhenNoRaisedWindowExists() {
        let start = date(hour: 4)
        let now = date(hour: 16)
        let ticks = walk(from: start, to: now) { hour, _ in
            hour == 8 || hour == 12 ? 200 : 20
        }
        let split = ActiveEnergyMath.split(
            dayStart: start, now: now, bmr: 900, bmrFull: 1_700,
            eActive: 320, eTrain: 60, eOutNow: 1_280,
            ticks: ticks, sportWindows: [], calendar: calendar)
        XCTAssertEqual(split.sport ?? 0, 60, accuracy: 0.01)
        XCTAssertEqual((split.sport ?? 0) + (split.steps ?? 0) + (split.incidental ?? 0),
                       380, accuracy: 0.01)
        XCTAssertEqual(split.out, 1_280)
        XCTAssertEqual(split.active, 380)
    }

    func testHourlyLivedHoursSumToActiveAndFutureHasNoHeight() {
        let start = date(hour: 4)
        let now = date(hour: 16, minute: 40)
        let ticks = walk(from: start, to: now) { hour, _ in hour == 16 ? 400 : 10 }
        let split = ActiveEnergyMath.split(
            dayStart: start, now: now, bmr: 901, bmrFull: 1_708,
            eActive: 486, eTrain: nil, eOutNow: 1_387,
            ticks: ticks, sportWindows: [], calendar: calendar)
        let hours = ActiveEnergyMath.hourly(
            dayStart: start, now: now, split: split,
            ticks: ticks, sportWindows: [], calendar: calendar)
        XCTAssertEqual(hours.count, 24)
        let lived = hours.filter(\.lived)
        XCTAssertEqual(lived.count, 13)
        XCTAssertEqual(lived.reduce(0) { $0 + $1.kcal }, 486, accuracy: 0.5)
        let future = hours.filter { !$0.lived }
        XCTAssertFalse(future.isEmpty)
        XCTAssertEqual(future[0].kcal, 0, accuracy: 0.01)
        let peak = ActiveEnergyMath.peakHour(hours)
        XCTAssertEqual(peak?.index, 12)
    }

    func testRestOnlyLivedHoursHaveNoBarHeight() {
        let start = date(hour: 4)
        let now = date(hour: 12)
        let ticks = walk(from: start, to: now) { _, _ in 0 }
        let split = ActiveEnergyMath.split(
            dayStart: start, now: now, bmr: 500, bmrFull: 1_500,
            eActive: 0, eTrain: nil, eOutNow: 500,
            ticks: ticks, sportWindows: [], calendar: calendar)
        let hours = ActiveEnergyMath.hourly(
            dayStart: start, now: now, split: split,
            ticks: ticks, sportWindows: [], calendar: calendar)
        XCTAssertFalse(hours.isEmpty)
        XCTAssertEqual(hours.filter(\.lived).reduce(0) { $0 + $1.kcal }, 0, accuracy: 0.01)
        XCTAssertNil(ActiveEnergyMath.peakHour(hours))
    }

    func testMissingActivityCannotBorrowRestingEnergyForHourlyBars() {
        let start = date(hour: 4)
        let now = date(hour: 12)
        let split = ActiveEnergyMath.split(dayStart: start, now: now, bmr: 500,
            bmrFull: 1500, eActive: nil, eTrain: nil, eOutNow: 500,
            ticks: [], sportWindows: [], calendar: calendar)
        XCTAssertNil(split.active)
        XCTAssertTrue(ActiveEnergyMath.hourly(dayStart: start, now: now, split: split,
            ticks: [], sportWindows: [], calendar: calendar).isEmpty)
    }

    func testWeekPreservesMeasuredZeroAndMissingDaysSeparately() {
        let today = date(hour: 4)
        let week = ActiveEnergyMath.week(days: [(today, 0),
            (today.addingTimeInterval(-86400), nil),
            (today.addingTimeInterval(-172800), 300)], todayStart: today)
        XCTAssertEqual(week.bars[0].active, 0)
        XCTAssertNil(week.bars[1].active)
        XCTAssertEqual(week.average, 150)
        XCTAssertEqual(week.todayDelta, -150)
    }

    func testVendorCaloriesNeverEnterTheSplit() {
        let start = date(hour: 4)
        let now = date(hour: 10)
        let ticks = [VitalSample(ts: start.addingTimeInterval(3600), hr: nil, stress: nil, steps: 0)]
        let split = ActiveEnergyMath.split(
            dayStart: start, now: now, bmr: nil, bmrFull: nil,
            eActive: nil, eTrain: nil, eOutNow: nil,
            ticks: ticks, sportWindows: [], calendar: calendar)
        XCTAssertNil(split.out)
        XCTAssertNil(split.active)
        XCTAssertNil(split.sport)
    }

    func testRestCurveHoldsTheSettledElapsedBmrAtNow() {
        let start = date(hour: 4)
        let now = date(hour: 16, minute: 40)
        let line = ActiveEnergyMath.restCurve(
            dayStart: start, now: now, resting: 901, calendar: calendar)
        XCTAssertEqual(line.solid.last?.y, 901)
        XCTAssertGreaterThan(line.dashed.last?.y ?? 0, 901)
        let openX = FuelWindowMath.clockFraction(at: start, dayStart: start, calendar: calendar)
        let nowX = FuelWindowMath.clockFraction(at: now, dayStart: start, calendar: calendar)
        let slope = 901 / (nowX - openX)
        let expected = 901 + slope * (1 - nowX)
        XCTAssertEqual(line.dashed.last?.y ?? 0, expected, accuracy: 0.01)
    }

    func testIntensityDropsToStillAfterNow() {
        let start = date(hour: 4)
        let now = date(hour: 16)
        let ticks = [VitalSample(ts: date(hour: 16), hr: nil, stress: nil, steps: 500)]
        let line = ActiveEnergyMath.intensity(
            dayStart: start, now: now, ticks: ticks, calendar: calendar)
        XCTAssertEqual(line.solid.last?.y ?? 0, 3, accuracy: 0.01)
        XCTAssertEqual(line.dashed.first?.y, 1)
        XCTAssertEqual(line.dashed.last?.y, 1)
    }

    func testWeekAverageLeavesAMissingDayOutOfTheDenominator() {
        let today = date(hour: 4)
        let days = (0..<7).map { back -> (Date, Double?) in
            let start = today.addingTimeInterval(Double(-back) * 86_400)
            return (start, back == 2 ? nil : 1_200 + Double(back) * 10)
        }.reversed()
        let week = ActiveEnergyMath.week(days: Array(days), todayStart: today)
        XCTAssertEqual(week.bars.count, 7)
        XCTAssertEqual(week.bars.last?.isToday, true)
        XCTAssertEqual(week.bars.compactMap(\.active).count, 6)
        XCTAssertNotNil(week.average)
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: hour, minute: minute))!
    }

    private func walk(from start: Date, to now: Date,
                      steps: (Int, Date) -> Int) -> [VitalSample] {
        var ticks: [VitalSample] = []
        var cursor = start
        while cursor <= now {
            let hour = calendar.component(.hour, from: cursor)
            ticks.append(VitalSample(ts: cursor, hr: nil, stress: nil, steps: steps(hour, cursor)))
            cursor = calendar.date(byAdding: .minute, value: 5, to: cursor)!
        }
        return ticks
    }
}
