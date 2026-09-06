import XCTest
@testable import NextBodySyncCore

final class ActiveEnergyMathTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testOutCurveIsTheCaloriesPageBurnCurve() {
        let start = date(hour: 4)
        let now = date(hour: 16, minute: 40)
        var ticks: [(Date, Int?)] = []
        var cursor = start
        while cursor <= now {
            let hour = calendar.component(.hour, from: cursor)
            ticks.append((cursor, hour == 16 ? 400 : 8))
            cursor = calendar.date(byAdding: .minute, value: 5, to: cursor)!
        }
        let fuel = FuelWindowMath.burnCurve(
            dayStart: start, now: now, burnedNow: 1_387, burnedFull: 2_194,
            ticks: ticks, calendar: calendar)
        let active = ActiveEnergyMath.outCurve(
            dayStart: start, now: now, burnedNow: 1_387, burnedFull: 2_194,
            ticks: ticks, calendar: calendar)
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

    func testHourlyLivedHoursSumToOutAndFutureKeepsTheBmrFloor() {
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
        XCTAssertEqual(lived.reduce(0) { $0 + $1.kcal }, 1_387, accuracy: 0.5)
        let future = hours.filter { !$0.lived }
        XCTAssertFalse(future.isEmpty)
        XCTAssertEqual(future[0].kcal, 1_708 / 24, accuracy: 0.01)
        let peak = ActiveEnergyMath.peakHour(hours)
        XCTAssertEqual(peak?.index, 12)
    }

    func testVendorCaloriesNeverEnterTheSplit() {
        let start = date(hour: 4)
        let now = date(hour: 10)
        let ticks = [(start.addingTimeInterval(3600), Optional(0))]
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
        let ticks = [(date(hour: 16), Optional(500))]
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
        XCTAssertEqual(week.bars.compactMap(\.out).count, 6)
        XCTAssertNotNil(week.average)
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: hour, minute: minute))!
    }

    private func walk(from start: Date, to now: Date,
                      steps: (Int, Date) -> Int) -> [(Date, Int?)] {
        var ticks: [(Date, Int?)] = []
        var cursor = start
        while cursor <= now {
            let hour = calendar.component(.hour, from: cursor)
            ticks.append((cursor, steps(hour, cursor)))
            cursor = calendar.date(byAdding: .minute, value: 5, to: cursor)!
        }
        return ticks
    }
}
