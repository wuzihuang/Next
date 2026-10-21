import XCTest
@testable import NextBodySyncCore

final class CompositionWindowMathTests: XCTestCase {
    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func scan(_ at: Date, fat: Double?, fatMass: Double? = 13.4, lean: Double? = 62.1) -> CompositionScan {
        CompositionScan(
            id: UUID(),
            at: at,
            bodyFatPercent: fat,
            fatMassKg: fatMass,
            leanMassKg: lean,
            bmrKcal: 1_640,
            inputWeightKg: 75.5
        )
    }

    func testCurrentIgnoresAScanAfterTheWindow() {
        let now = day(2026, 9, 5, hour: 10)
        let scans = [
            scan(day(2026, 9, 5, hour: 18), fat: 17.0),
            scan(day(2026, 9, 5, hour: 7), fat: 17.8),
            scan(day(2026, 9, 3, hour: 7), fat: 18.0),
        ]
        let current = CompositionWindowMath.current(in: scans, asOf: now)
        XCTAssertEqual(current?.bodyFatPercent, 17.8)
    }

    func testDayReadingNamesThePreviousScanAndTheDelta() {
        let now = day(2026, 9, 5, hour: 10)
        let scans = [
            scan(day(2026, 9, 5, hour: 7), fat: 17.8, fatMass: 13.4, lean: 62.1),
            scan(day(2026, 9, 3, hour: 7), fat: 18.0, fatMass: 13.6, lean: 62.0),
        ]
        let reading = CompositionWindowMath.dayReading(scans: scans, asOf: now)
        XCTAssertEqual(reading?.bodyFat.now, 17.8)
        XCTAssertEqual(reading?.bodyFat.before, 18.0)
        XCTAssertEqual(reading?.bodyFat.delta ?? 0, -0.2, accuracy: 0.0001)
        XCTAssertEqual(reading?.fatMass.delta ?? 0, -0.2, accuracy: 0.0001)
        XCTAssertEqual(reading?.leanMass.delta ?? 0, 0.1, accuracy: 0.0001)
        XCTAssertEqual(reading?.previous?.bodyFatPercent, 18.0)
    }

    func testALoneScanHasNoDelta() {
        let now = day(2026, 9, 5, hour: 10)
        let reading = CompositionWindowMath.dayReading(
            scans: [scan(day(2026, 9, 5, hour: 7), fat: 17.8)],
            asOf: now
        )
        XCTAssertNil(reading?.previous)
        XCTAssertNil(reading?.bodyFat.delta)
    }

    func testEmptyHistoryHasNoDayReading() {
        XCTAssertNil(CompositionWindowMath.dayReading(scans: [], asOf: day(2026, 9, 5)))
    }

    func testWeekPointsSkipEmptyDaysAndBreakTheLine() {
        let friday = UserDay.containing(day(2026, 9, 4, hour: 12))
        let days = friday.rollingBack(7)
        let scans = [
            scan(friday.start.addingTimeInterval(3 * 3600), fat: 17.8),
            scan(friday.adding(days: -1).start.addingTimeInterval(3 * 3600), fat: 17.9),
            scan(friday.adding(days: -3).start.addingTimeInterval(3 * 3600), fat: 18.0),
        ]
        let points = CompositionWindowMath.weekPoints(scans: scans, days: days)
        XCTAssertEqual(points.map(\.value), [18.0, 17.9, 17.8])
        let runs = CompositionWindowMath.runs(from: points, days: days)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].map(\.value), [18.0])
        XCTAssertEqual(runs[1].map(\.value), [17.9, 17.8])
    }

    func testWeekPlotUsesThePersonalBand() {
        let friday = UserDay.containing(day(2026, 9, 4, hour: 12))
        let scans = [
            scan(friday.start.addingTimeInterval(3 * 3600), fat: 17.8),
            scan(friday.adding(days: -2).start.addingTimeInterval(3 * 3600), fat: 18.1),
        ]
        let plot = CompositionWindowMath.plot(
            scans: scans,
            range: .week,
            endingOn: friday,
            now: friday.start.addingTimeInterval(10 * 3600)
        )
        XCTAssertEqual(plot.scanCount, 2)
        XCTAssertEqual(plot.windowLow, 17.8)
        XCTAssertEqual(plot.windowHigh, 18.1)
        XCTAssertEqual(plot.median ?? 0, 17.95, accuracy: 0.0001)
        XCTAssertGreaterThan(plot.yMax, 18.1)
        XCTAssertLessThan(plot.yMin, 17.8)
        XCTAssertTrue(plot.runs.allSatisfy { !$0.isEmpty })
    }

    func testDayPlotIsEmptyBecauseOnePointIsNotALine() {
        let day = UserDay.containing(self.day(2026, 9, 5, hour: 12))
        let plot = CompositionWindowMath.plot(
            scans: [scan(self.day(2026, 9, 5, hour: 7), fat: 17.8)],
            range: .day,
            endingOn: day,
            now: self.day(2026, 9, 5, hour: 10)
        )
        XCTAssertTrue(plot.points.isEmpty)
        XCTAssertEqual(plot.scanCount, 1)
    }

    func testMonthConnectsEveryScanOnTheClock() {
        let end = UserDay.containing(day(2026, 9, 5, hour: 12))
        let scans = [
            scan(day(2026, 8, 10, hour: 7), fat: 18.4),
            scan(day(2026, 8, 20, hour: 7), fat: 18.1),
            scan(day(2026, 9, 5, hour: 7), fat: 17.8),
        ]
        let plot = CompositionWindowMath.plot(
            scans: scans,
            range: .month,
            endingOn: end,
            now: day(2026, 9, 5, hour: 10)
        )
        XCTAssertEqual(plot.runs.count, 1)
        XCTAssertEqual(plot.points.map(\.value), [18.4, 18.1, 17.8])
        XCTAssertEqual(plot.windowLow, 17.8)
        XCTAssertEqual(plot.windowHigh, 18.4)
    }

    func testWeekBucketsAverageNewestFirstAndDeltaAgainstTheOlderWeek() {
        let end = UserDay.containing(day(2026, 9, 5, hour: 12))
        let scans = [
            scan(day(2026, 9, 5, hour: 7), fat: 17.8),
            scan(day(2026, 9, 3, hour: 7), fat: 18.0),
            scan(day(2026, 8, 28, hour: 7), fat: 18.2),
            scan(day(2026, 8, 26, hour: 7), fat: 18.4),
        ]
        let buckets = CompositionWindowMath.weekBuckets(scans: scans, endingOn: end, count: 4)
        XCTAssertEqual(buckets.map(\.offset), [0, 1, 2, 3])
        XCTAssertEqual(buckets[0].averageFat ?? 0, 17.9, accuracy: 0.0001)
        XCTAssertEqual(buckets[1].averageFat ?? 0, 18.3, accuracy: 0.0001)
        XCTAssertEqual(buckets[0].delta!, -0.4, accuracy: 0.0001)
        XCTAssertNil(buckets[3].delta)
    }

    func testSpanReadsOldestToNewest() {
        let scans = [
            scan(day(2026, 9, 5, hour: 7), fat: 17.8, fatMass: 13.4),
            scan(day(2026, 8, 10, hour: 7), fat: 18.4, fatMass: 14.0),
        ]
        let span = CompositionWindowMath.span(\.fatMassKg, in: scans)
        XCTAssertEqual(span.first, 14.0)
        XCTAssertEqual(span.last, 13.4)
    }

    func testQuietScaleStillLeavesRoom() {
        let scale = CompositionWindowMath.scale([18.0, 18.0])
        XCTAssertEqual(scale.min, 17.6, accuracy: 0.001)
        XCTAssertEqual(scale.max, 18.4, accuracy: 0.001)
    }

    // 11 §03 · one cell is one week; colour is measured direction, never a meal log.

    func testWeekCellsReadThePreviousMeasuredWeek() {
        let end = UserDay.containing(day(2026, 9, 26, hour: 12))
        let week = { (offset: Int) in end.adding(days: -offset * 7) }
        let scans = [
            // anchor week — nothing to compare against, so HELD, not aligned
            scan(week(24).start.addingTimeInterval(3600), fat: 18.0, fatMass: 14.0, lean: 60.0),
            // fat down → aligned for a recomp aim
            scan(week(10).start.addingTimeInterval(3600), fat: 17.0, fatMass: 13.0, lean: 60.2),
            // fat up without lean → drift
            scan(week(4).start.addingTimeInterval(3600), fat: 18.2, fatMass: 14.3, lean: 60.2),
            // inside the band → held
            scan(week(1).start.addingTimeInterval(3600), fat: 18.2, fatMass: 14.4, lean: 60.15),
        ]
        let cells = CompositionWindowMath.weekCells(scans: scans, aim: .recomp, endingOn: end)
        XCTAssertEqual(cells.count, 26)
        XCTAssertEqual(cells[0].tone, .noScan)
        XCTAssertEqual(cells[1].tone, .held)     // week 24: first anchor
        XCTAssertEqual(cells[15].tone, .aligned) // week 10: fat −1.0 vs the anchor
        XCTAssertEqual(cells[21].tone, .drift)   // week 4: fat +1.3, lean flat
        XCTAssertEqual(cells[24].tone, .held)    // week 1: inside the band
        XCTAssertEqual(cells[25].tone, .noScan)  // this week has no scan yet
    }

    func testWeekCellsSkipEmptyWeeksAndKeepTheOldBaseline() {
        let end = UserDay.containing(day(2026, 9, 26, hour: 12))
        let scans = [
            scan(end.adding(days: -170).start.addingTimeInterval(3600), fat: 18.0, fatMass: 14.0, lean: 60.0),
            scan(end.adding(days: -10).start.addingTimeInterval(3600), fat: 17.5, fatMass: 13.3, lean: 60.1),
        ]
        let cells = CompositionWindowMath.weekCells(scans: scans, aim: .cut, endingOn: end)
        XCTAssertEqual(cells[25].tone, .noScan)
        XCTAssertEqual(cells[24].tone, .aligned) // compared across ~24 empty weeks
    }

    func testClassifyFollowsTheAim() {
        // fat up with lean up is BULK: drift for cut/recomp, aligned for bulk
        XCTAssertEqual(CompositionWindowMath.classify(fatDelta: 0.3, leanDelta: 0.2, aim: .bulk), .aligned)
        XCTAssertEqual(CompositionWindowMath.classify(fatDelta: 0.3, leanDelta: 0.2, aim: .cut), .drift)
        XCTAssertEqual(CompositionWindowMath.classify(fatDelta: 0.3, leanDelta: 0.2, aim: .recomp), .drift)
        // lean down without fat down is drift for every aim
        XCTAssertEqual(CompositionWindowMath.classify(fatDelta: 0, leanDelta: -0.2, aim: .bulk), .drift)
        XCTAssertEqual(CompositionWindowMath.classify(fatDelta: 0, leanDelta: -0.2, aim: .recomp), .drift)
        // inside the band, or nothing to compare, is held — never aligned
        XCTAssertEqual(CompositionWindowMath.classify(fatDelta: nil, leanDelta: nil, aim: .cut), .held)
    }
}
