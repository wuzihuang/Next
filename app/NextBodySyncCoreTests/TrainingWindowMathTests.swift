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
        XCTAssertEqual(TrainingWindowMath.band(load: 9.0, zone: nil), .unknown)
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

    func testPublishedZeroDoesNotEstablishWearing() {
        let today = UserDay.containing(Date())
        var zero = fact(today, load: 0)
        zero.worn = false
        var unknown = fact(today.adding(days: -1), load: 6)
        unknown.worn = nil
        let days = [zero, unknown, fact(today.adding(days: -2), load: nil)]
        XCTAssertEqual(TrainingWindowMath.wornCount(days), 0)
        XCTAssertEqual(TrainingWindowMath.recordedCount(days), 2)
        XCTAssertEqual(TrainingWindowMath.emptyCount(days), 1)
    }

    func testHistoryWithoutItsOwnTargetRemainsUnknown() {
        let today = UserDay.containing(Date())
        var historical = fact(today.adding(days: -1), load: 16)
        var current = fact(today, load: 6, open: true)
        current.zone = 3...7
        let first = TrainingWindowMath.bandCounts([historical, current])
        current.zone = 17...20
        let second = TrainingWindowMath.bandCounts([historical, current])
        XCTAssertEqual(first.unknown, 1)
        XCTAssertEqual(first.heavy, 0)
        XCTAssertEqual(second.unknown, first.unknown)
        historical.zone = 10...14
        XCTAssertEqual(TrainingWindowMath.bandCounts([historical, current]).heavy, 1)
    }

    func testRangeStatesDoNotCallExcessZeroToGo() {
        XCTAssertEqual(TrainingWindowMath.rangeStatus(load: nil, target: 16, zone: 14...18), .noLoad)
        XCTAssertEqual(TrainingWindowMath.rangeStatus(load: 6.4, target: nil, zone: nil), .noTarget)
        XCTAssertEqual(TrainingWindowMath.rangeStatus(load: 10, target: 16, zone: 14...18), .below(4))
        XCTAssertEqual(TrainingWindowMath.rangeStatus(load: 14, target: 16, zone: 14...18), .inRange)
        XCTAssertEqual(TrainingWindowMath.rangeStatus(load: 18, target: 16, zone: 14...18), .inRange)
        XCTAssertEqual(TrainingWindowMath.rangeStatus(load: 19, target: 16, zone: 14...18), .above(1))
        XCTAssertEqual(TrainingWindowMath.rangeStatus(load: 20.9, target: 16, zone: 14...18), .capped)
    }

    func testZoneColumnsUseOneScaleAcrossDays() {
        let today = UserDay.containing(Date())
        let days = [fact(today, load: 1, zones: [10, 0, 0, 0, 0]),
                    fact(today.adding(days: -1), load: 6, zones: [100, 0, 0, 0, 0])]
        let scale = TrainingWindowMath.zoneScaleMinutes(days)
        XCTAssertEqual(scale, 100)
        XCTAssertEqual(Double(days[0].easyMinutes!) / scale, 0.1, accuracy: 0.001)
        XCTAssertEqual(Double(days[1].easyMinutes!) / scale, 1, accuracy: 0.001)
    }

    func testEmptyCurveHasNoInventedValuesOrFutureCoverage() {
        let day = UserDay.containing(Date())
        let end = day.start.addingTimeInterval(3600)
        let curve = TrainingWindowMath.curveData([], day: day, through: end)
        XCTAssertTrue(curve.segments.isEmpty)
        XCTAssertEqual(curve.gaps, [DateInterval(start: day.start, end: end)])
    }

    func testCurveSplitsInteriorGapAndShowsLeadingAndTrailingMissingSlots() {
        let day = UserDay.containing(Date())
        let points = [point(day, minute: 60, load: 2), point(day, minute: 65, load: 3),
                      point(day, minute: 90, load: 5)]
        let curve = TrainingWindowMath.curveData(points, day: day,
                                                 through: day.start.addingTimeInterval(120 * 60))
        XCTAssertEqual(curve.segments, [Array(points.prefix(2)), [points[2]]])
        XCTAssertEqual(curve.gaps.map { $0.duration / 60 }, [60, 20, 25])
        XCTAssertEqual(curve.gaps[1].start, day.start.addingTimeInterval(70 * 60))
        XCTAssertEqual(curve.segments.last?.last?.load, 5)
    }

    func testCurveKeepsFirstRecordedValueAndRejectsFutureSamples() {
        let day = UserDay.containing(Date())
        let first = point(day, minute: 0, load: 2)
        let second = point(day, minute: 5, load: 3)
        let future = point(day, minute: 120, load: 9)
        let curve = TrainingWindowMath.curveData([second, future, first], day: day,
                                                 through: day.start.addingTimeInterval(10 * 60))
        XCTAssertEqual(curve.segments, [[first, second]])
        XCTAssertTrue(curve.gaps.isEmpty)
    }

    func testDayFractionUsesActualWindowLength() {
        let day = UserDay.containing(Date())
        XCTAssertEqual(TrainingWindowMath.dayFraction(day.start, day: day), 0)
        XCTAssertEqual(TrainingWindowMath.dayFraction(day.end, day: day), 1)
        let middle = day.start.addingTimeInterval(day.end.timeIntervalSince(day.start) / 2)
        XCTAssertEqual(TrainingWindowMath.dayFraction(middle, day: day), 0.5)
    }

    func testThirtyDayRollHasFiveGroupsIncludingTwoDayStart() {
        let today = UserDay.containing(Date())
        let days = today.rollingBack(30).map { fact($0, load: 6) }
        XCTAssertEqual(TrainingWindowMath.weekRolls(days).map(\.days), [2, 7, 7, 7, 7])
    }

    func testLineRunsBreakAtEmptyDaysAndNeverInventAZero() {
        XCTAssertEqual(indexes([1, 2, nil, 4]), [[0, 1], [3]])
        XCTAssertEqual(indexes([nil, 3, 4, nil, nil, 9]), [[1, 2], [5]])
        XCTAssertEqual(indexes([Double?.none, nil]), [])
        XCTAssertEqual(indexes([8]), [[0]])
    }

    private func indexes(_ values: [Double?]) -> [[Int]] {
        TrainingWindowMath.lineRuns(values).map { $0.map(\.index) }
    }

    private func point(_ day: UserDay, minute: Double, load: Double) -> TrainingCurvePoint {
        TrainingCurvePoint(ts: day.start.addingTimeInterval(minute * 60), load: load)
    }

    private func fact(_ day: UserDay, load: Double?, zones: [Int]? = nil, open: Bool = false) -> TrainingDayFacts {
        TrainingDayFacts(day: day, load: load, target: nil, zone: nil,
                         zoneMinutes: zones, steps: nil, activeKcal: nil,
                         totalKcal: nil, worn: load != nil, isOpen: open)
    }
}
