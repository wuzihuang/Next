import XCTest
@testable import NextBodySyncCore

final class MealResponseIndexTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testFiveDaysOfDaytimePointsYieldSignedHeroVersusOwnMedian() {
        let points = fiveDayBaseline(median: 100) + [
            point(day: 10, hour: 15, minute: 0, optical: 108),
        ]
        let result = MealResponseIndex.make(
            points: points,
            sleepWindows: [],
            now: instant(day: 10, hour: 18),
            calendar: calendar)

        XCTAssertEqual(result.hero, 8)
        XCTAssertEqual(MealResponseIndex.signedPercent(result.hero!), "+8")
        XCTAssertTrue(result.ownMedianReady)
        XCTAssertNil(result.empty)
        XCTAssertEqual(result.analyticsState, "FRESH")
    }

    func testOnMedianPrintsZeroWithoutASign() {
        let points = fiveDayBaseline(median: 100) + [
            point(day: 10, hour: 15, optical: 100),
        ]
        let result = MealResponseIndex.make(
            points: points,
            sleepWindows: [],
            now: instant(day: 10, hour: 18),
            calendar: calendar)

        XCTAssertEqual(result.hero, 0)
        XCTAssertEqual(MealResponseIndex.signedPercent(0), "0")
    }

    func testBelowMedianUsesMinusSignNotALabUnit() {
        let points = fiveDayBaseline(median: 100) + [
            point(day: 10, hour: 15, optical: 97),
        ]
        let result = MealResponseIndex.make(
            points: points,
            sleepWindows: [],
            now: instant(day: 10, hour: 18),
            calendar: calendar)

        XCTAssertEqual(result.hero, -3)
        XCTAssertEqual(MealResponseIndex.signedPercent(-3), "−3")
        XCTAssertFalse(MealResponseIndex.signedPercent(-3).contains("mmol"))
        XCTAssertFalse(MealResponseIndex.signedPercent(-3).contains("/100"))
    }

    func testFewerThanFiveDaysStillExposesMeasuredTrend() {
        let points = (8...9).map { point(day: $0, hour: 12, optical: 100) }
            + [point(day: 10, hour: 15, optical: 108)]
        let result = MealResponseIndex.make(
            points: points,
            sleepWindows: [],
            now: instant(day: 10, hour: 18),
            calendar: calendar)

        XCTAssertNil(result.hero)
        XCTAssertEqual(result.latestPoint, 108)
        XCTAssertEqual(result.trendPoints.map(\.optical), [108])
        XCTAssertEqual(result.median24hPoint, 108)
        XCTAssertEqual(result.baselineDays, 3)
        XCTAssertFalse(result.ownMedianReady)
        XCTAssertNil(result.empty)
        XCTAssertEqual(result.analyticsState, "FRESH")
        XCTAssertTrue(result.percents.isEmpty)
    }

    func testSwitchOffIsTheEmptyReasonWhenThereIsNoHero() {
        let result = MealResponseIndex.make(
            points: fiveDayBaseline(median: 100),
            sleepWindows: [],
            now: instant(day: 10, hour: 18),
            switchOff: true,
            calendar: calendar)

        XCTAssertNil(result.hero)
        XCTAssertEqual(result.empty, .switchOff)
        XCTAssertEqual(result.analyticsState, "OFF")
    }

    func testAllZerosIsNotAReadingOnTheMedian() {
        let result = MealResponseIndex.make(
            points: [],
            sleepWindows: [],
            now: instant(day: 10, hour: 18),
            allZeros: true,
            calendar: calendar)

        XCTAssertNil(result.hero)
        XCTAssertEqual(result.empty, .allZeros)
        XCTAssertEqual(result.analyticsState, "ZERO")
    }

    func testSwitchOffWinsOverAllZerosWhenThereIsNoHero() {
        let result = MealResponseIndex.make(
            points: [],
            sleepWindows: [],
            now: instant(day: 10, hour: 18),
            switchOff: true,
            allZeros: true,
            calendar: calendar)

        XCTAssertEqual(result.empty, .switchOff)
        XCTAssertEqual(result.analyticsState, "OFF")
    }

    func testZerosAndNonFiniteValuesNeverBecomePoints() {
        XCTAssertNil(HealthSampleMapping.opticalResponse(from: [
            "time": "16:30",
            "bloodGlucoses": ["0.00", "0", 0],
        ]))
        XCTAssertNil(HealthSampleMapping.opticalResponse(from: [
            "time": "16:30",
            "bloodGlucoses": [Double.nan],
        ]))
        let sample = HealthSampleMapping.opticalResponse(from: [
            "time": "16:30",
            "bloodGlucoses": ["0.00", "563", "0"],
            "bloodGlucoseLevels": ["2"],
        ])
        XCTAssertEqual(sample?.time, "16:30")
        XCTAssertEqual(sample?.optical, 563)
        let dump = String(describing: sample!)
        XCTAssertFalse(dump.lowercased().contains("glucose"))
        XCTAssertFalse(dump.lowercased().contains("mmol"))
        XCTAssertFalse(dump.contains("/100"))
        XCTAssertFalse(dump.contains("SPIKE"))
    }

    func testRiskLevelsCannotLeakIntoTheMappedPoint() {
        let sample = HealthSampleMapping.opticalResponse(from: [
            "Time": "08:00",
            "bloodGlucoses": [110.0],
            "bloodGlucoseLevels": ["3"],
        ])
        XCTAssertEqual(sample?.optical, 110)
        XCTAssertEqual(Mirror(reflecting: sample!).children.map(\.label), ["time", "optical"])
    }

    func testSleepWindowPointsAreExcludedFromOwnMedian() {
        let night = MealResponseIndex.SleepWindow(
            start: instant(day: 10, hour: 0, minute: 0),
            end: instant(day: 10, hour: 7, minute: 0))
        var points = fiveDayBaseline(median: 100)
        points.append(contentsOf: (0..<10).map { point(day: 10, hour: 1, minute: $0 * 5, optical: 1_000) })
        points.append(point(day: 10, hour: 15, optical: 108))
        let result = MealResponseIndex.make(
            points: points,
            sleepWindows: [night],
            now: instant(day: 10, hour: 18),
            calendar: calendar)

        XCTAssertEqual(result.hero, 8)
        XCTAssertEqual(MealResponseIndex.signedPercent(result.hero!), "+8")
    }

    func testNightlessDayUsesEveryValidPointForThatDay() {
        let points = (5...9).map { point(day: $0, hour: 12, optical: 100) }
            + [
                point(day: 10, hour: 2, optical: 100),
                point(day: 10, hour: 15, optical: 108),
            ]
        let result = MealResponseIndex.make(
            points: points,
            sleepWindows: [],
            now: instant(day: 10, hour: 18),
            calendar: calendar)

        XCTAssertTrue(result.ownMedianReady)
        XCTAssertEqual(result.hero, 8)
    }

    func testMedianReadyWithNoTicksTodayLeavesHeroEmptyAndOwnMedianZero() {
        let result = MealResponseIndex.make(
            points: fiveDayBaseline(median: 100),
            sleepWindows: [],
            now: instant(day: 10, hour: 18),
            calendar: calendar)

        XCTAssertNil(result.hero)
        XCTAssertNil(result.median24h)
        XCTAssertTrue(result.ownMedianReady)
        XCTAssertEqual(result.empty, .empty)
        XCTAssertEqual(result.analyticsState, "EMPTY")
    }

    func testNearBandIsPlusOrMinusEightPercent() {
        let points = fiveDayBaseline(median: 100) + [
            point(day: 10, hour: 12, optical: 92),
            point(day: 10, hour: 13, optical: 100),
            point(day: 10, hour: 14, optical: 108),
            point(day: 10, hour: 15, optical: 80),
            point(day: 10, hour: 16, optical: 120),
        ]
        let result = MealResponseIndex.make(
            points: points,
            sleepWindows: [],
            now: instant(day: 10, hour: 18),
            calendar: calendar)

        XCTAssertEqual(result.below, 1)
        XCTAssertEqual(result.near, 3)
        XCTAssertEqual(result.above, 1)
        XCTAssertEqual(result.median24h, 0)
        XCTAssertEqual(result.hero, 20)
        XCTAssertEqual(result.ownMedian, 100)
    }

    func testWeekHeroIsTheMeanOfDailyMeansNotOfEveryTick() {
        // Two quiet 100s on day 8, one high 130 on day 9. A point-mean would be
        // (100+100+130)/3 = 110; the daily-mean is (100+130)/2 = 115.
        let points = [
            point(day: 8, hour: 11, optical: 100),
            point(day: 8, hour: 16, optical: 100),
            point(day: 9, hour: 12, optical: 130),
        ]
        let window = MealResponseIndex.horizonWindow(
            points: points,
            ownMedian: 100,
            now: instant(day: 10, hour: 18),
            horizon: .userDays(3),
            calendar: calendar)

        XCTAssertEqual(window.slots.count, 3)
        XCTAssertEqual(window.recordedDays, 2)
        XCTAssertEqual(window.dailyMean!, 115, accuracy: 0.01)
        XCTAssertNil(window.slots.last?.mean)
        XCTAssertEqual(MealResponseIndex.percent(of: window.dailyMean!, ownMedian: 100), 15)
    }

    func testEmptyUserDayStaysAVacantSlot() {
        let points = [
            point(day: 8, hour: 12, optical: 100),
            point(day: 10, hour: 12, optical: 110),
        ]
        let window = MealResponseIndex.horizonWindow(
            points: points,
            ownMedian: 100,
            now: instant(day: 10, hour: 18),
            horizon: .userDays(7),
            calendar: calendar)

        XCTAssertEqual(window.slots.count, 7)
        XCTAssertEqual(window.recordedDays, 2)
        let vacant = window.slots.filter { $0.mean == nil }
        XCTAssertEqual(vacant.count, 5)
        XCTAssertEqual(window.dailyMean!, 105, accuracy: 0.01)
    }

    func testMonthWindowCountsThirtyUserDays() {
        let points = (1...10).map { point(day: $0, hour: 12, optical: 100) }
        let window = MealResponseIndex.horizonWindow(
            points: points,
            ownMedian: 100,
            now: instant(day: 10, hour: 18),
            horizon: .userDays(30),
            calendar: calendar)

        XCTAssertEqual(window.slots.count, 30)
        XCTAssertEqual(window.recordedDays, 10)
        XCTAssertEqual(window.below + window.near + window.above, 10)
        XCTAssertEqual(window.near, 10)
    }

    func testBandCutsAtPlusOrMinusEightPercent() {
        XCTAssertEqual(MealResponseIndex.Band.of(optical: 91, ownMedian: 100), .below)
        XCTAssertEqual(MealResponseIndex.Band.of(optical: 92, ownMedian: 100), .near)
        XCTAssertEqual(MealResponseIndex.Band.of(optical: 108, ownMedian: 100), .near)
        XCTAssertEqual(MealResponseIndex.Band.of(optical: 109, ownMedian: 100), .above)
        XCTAssertNil(MealResponseIndex.Band.of(optical: 100, ownMedian: 0))
    }

    func testAxisKeepsRoomAroundTheOwnMedian() {
        let axis = MealResponseIndex.axis(values: [100, 108], ownMedian: 100)
        XCTAssertEqual(axis!.lowerBound, 85, accuracy: 0.01)
        XCTAssertEqual(axis!.upperBound, 115, accuracy: 0.01)
    }

    // MARK: fixtures

    private func fiveDayBaseline(median: Double) -> [MealResponseIndex.Point] {
        (5...9).map { point(day: $0, hour: 12, optical: median) }
    }

    private func point(day: Int, hour: Int, minute: Int = 0, optical: Double) -> MealResponseIndex.Point {
        MealResponseIndex.Point(ts: instant(day: day, hour: hour, minute: minute), optical: optical)
    }

    private func instant(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
    }
}
