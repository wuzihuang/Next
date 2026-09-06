import XCTest
@testable import NextBodySleepCore

final class VitalsDialMathTests: XCTestCase {

    func testFractionSitsOnAFixedScale() {
        XCTAssertEqual(VitalsDialMath.fraction(value: 79, scale: 40...160), (79 - 40) / 120, accuracy: 0.0001)
    }

    func testFractionClampsOutsideTheScale() {
        XCTAssertEqual(VitalsDialMath.fraction(value: 10, scale: 40...160), 0)
        XCTAssertEqual(VitalsDialMath.fraction(value: 200, scale: 40...160), 1)
    }

    func testActiveIndexUsesInteriorCuts() {
        XCTAssertEqual(VitalsDialMath.activeIndex(value: 79, cuts: [108, 126, 144]), 0)
        XCTAssertEqual(VitalsDialMath.activeIndex(value: 108, cuts: [108, 126, 144]), 1)
        XCTAssertEqual(VitalsDialMath.activeIndex(value: 150, cuts: [108, 126, 144]), 3)
    }

    func testHeartCutsFollowTanakaSharesOnTheChartRuler() {
        let placed = VitalsDialMath.heartCuts(maxHR: 180)
        XCTAssertEqual(placed.scale, 40...160)
        XCTAssertEqual(placed.cuts[0], 108, accuracy: 0.01)
        XCTAssertEqual(placed.cuts[1], 126, accuracy: 0.01)
        XCTAssertEqual(placed.cuts[2], 144, accuracy: 0.01)
    }

    func testTheSameHeartRateDoesNotMoveWhenTheDayPeakChanges() {
        let scale = VitalsDialMath.heartCuts(maxHR: 180).scale
        let today = VitalsDialMath.fraction(value: 79, scale: scale)
        let quieter = VitalsDialMath.fraction(value: 79, scale: scale)
        XCTAssertEqual(today, quieter)
        XCTAssertNotEqual(today, (79 - 52) / (142 - 52), accuracy: 0.01)
    }

    func testStressCutsAreTheSameFourBandsThePageAlreadyCounts() {
        let placed = VitalsDialMath.stressCuts()
        XCTAssertEqual(placed.scale, 0...100)
        XCTAssertEqual(placed.cuts, [25, 50, 75])
        XCTAssertEqual(VitalsDialMath.activeIndex(value: 10, cuts: placed.cuts), 0)
        XCTAssertEqual(VitalsDialMath.activeIndex(value: 40, cuts: placed.cuts), 1)
        XCTAssertEqual(VitalsDialMath.activeIndex(value: 80, cuts: placed.cuts), 3)
    }

    func testRatioCutsNeedABase() {
        XCTAssertNil(VitalsDialMath.ratioCuts(base: 0))
        let placed = VitalsDialMath.ratioCuts(base: 50)
        XCTAssertEqual(placed!.cuts[0], 46, accuracy: 0.01)
        XCTAssertEqual(placed!.cuts[1], 54, accuracy: 0.01)
    }

    func testWeekCutsNeedThreeDays() {
        XCTAssertNil(VitalsDialMath.weekCuts(today: 8_420, week: [6_000, 7_000]))
        let placed = VitalsDialMath.weekCuts(today: 8_420, week: [5_000, 6_000, 7_000, 6_500])
        XCTAssertNotNil(placed)
        let mean = (5_000.0 + 6_000 + 7_000 + 6_500) / 4
        XCTAssertEqual(placed!.cuts[0], mean * 0.80, accuracy: 0.01)
        XCTAssertEqual(placed!.cuts[1], mean * 1.15, accuracy: 0.01)
        XCTAssertEqual(VitalsDialMath.activeIndex(value: 8_420, cuts: placed!.cuts), 2)
    }

    func testSleepCutsMatchTheADRColourBands() {
        let placed = VitalsDialMath.sleepCuts()
        XCTAssertEqual(placed.cuts, [40, 60, 80])
        XCTAssertEqual(VitalsDialMath.activeIndex(value: 79, cuts: placed.cuts), 2)
        XCTAssertEqual(VitalsDialMath.activeIndex(value: 80, cuts: placed.cuts), 3)
    }

    func testRangeCutsPadBothSidesOfTheMeasuredWindow() {
        XCTAssertNil(VitalsDialMath.rangeCuts(lower: 33.0, upper: 33.0))
        let placed = VitalsDialMath.rangeCuts(lower: 33.1, upper: 33.6)!
        XCTAssertEqual(placed.scale, 32.6...34.1)
        XCTAssertEqual(placed.cuts, [33.1, 33.6])
        XCTAssertEqual(VitalsDialMath.activeIndex(value: 33.4, cuts: placed.cuts), 1)
    }

    func testResponseCutsKeepNearAtPlusMinusEight() {
        let placed = VitalsDialMath.responseCuts(percent: 12)
        XCTAssertEqual(placed.cuts, [-8, 8])
        XCTAssertEqual(placed.scale, -40...40)
        XCTAssertEqual(VitalsDialMath.activeIndex(value: -3, cuts: placed.cuts), 1)
        XCTAssertEqual(VitalsDialMath.activeIndex(value: 12, cuts: placed.cuts), 2)
    }

    // MARK: - zone runs · how a mark that spans a range is coloured

    func testAMarkInsideOneZoneIsASingleRun() {
        let runs = VitalsDialMath.zoneRuns(low: 62, high: 71, cuts: [108, 126, 144])
        XCTAssertEqual(runs, [.init(zone: 0, from: 0, to: 1)])
    }

    func testAReducedMarkStillNamesItsOwnZone() {
        let runs = VitalsDialMath.zoneRuns(low: 130, high: 130, cuts: [108, 126, 144])
        XCTAssertEqual(runs, [.init(zone: 2, from: 0, to: 1)])
    }

    /// The half hour that climbed out of resting into aerobic carries both colours, and the
    /// edge sits on the cut rather than at the middle of the capsule.
    func testAMarkCrossingACutSplitsOnTheCut() {
        let runs = VitalsDialMath.zoneRuns(low: 98, high: 118, cuts: [108, 126, 144])
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].zone, 1)
        XCTAssertEqual(runs[0].from, 0)
        XCTAssertEqual(runs[0].to, 0.5, accuracy: 0.0001)
        XCTAssertEqual(runs[1].zone, 0)
        XCTAssertEqual(runs[1].from, 0.5, accuracy: 0.0001)
        XCTAssertEqual(runs[1].to, 1)
    }

    /// Runs are ordered from the high end down, because that is the order a capsule and a
    /// column are both drawn in — 0 at the top of the mark.
    func testRunsRunFromTheHighEndDown() {
        let runs = VitalsDialMath.zoneRuns(low: 60, high: 150, cuts: [108, 126, 144])
        XCTAssertEqual(runs.map(\.zone), [3, 2, 1, 0])
        XCTAssertEqual(runs.first?.from, 0)
        XCTAssertEqual(runs.last?.to, 1)
        // Contiguous: no gap and no overlap between neighbours.
        for (a, b) in zip(runs, runs.dropFirst()) {
            XCTAssertEqual(a.to, b.from, accuracy: 0.0001)
        }
    }

    func testCutsOutsideTheMarkDoNotSplitIt() {
        let runs = VitalsDialMath.zoneRuns(low: 20, high: 24, cuts: [25, 50, 75])
        XCTAssertEqual(runs, [.init(zone: 0, from: 0, to: 1)])
    }

    func testAMarkWithNoCutsIsOneRun() {
        XCTAssertEqual(VitalsDialMath.zoneRuns(low: 10, high: 90, cuts: []),
                       [.init(zone: 0, from: 0, to: 1)])
    }
}
