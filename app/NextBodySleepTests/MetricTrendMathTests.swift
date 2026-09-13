import XCTest
@testable import NextBodySleepCore

final class MetricTrendMathTests: XCTestCase {

    func testHeadlineIsTheMedianOfRecordedDaysOnly() {
        XCTAssertEqual(MetricTrendMath.headline([60, nil, 64, nil, 62]), 62)
        XCTAssertNil(MetricTrendMath.headline([nil, nil]))
    }

    func testHabitNeedsThreeDays() {
        XCTAssertNil(MetricTrendMath.habit([60, 62]))
        XCTAssertEqual(MetricTrendMath.habit([60, 62, 70]), 62)
    }

    func testDeltaComparesMediansAndNeedsBothWindows() {
        XCTAssertEqual(MetricTrendMath.delta(current: [60, 62, 64], prior: [58, 58, 60]), 4)
        XCTAssertNil(MetricTrendMath.delta(current: [60, 62, 64], prior: [58, nil, nil]))
        XCTAssertNil(MetricTrendMath.delta(current: [60, nil], prior: [58, 58, 60]))
    }

    func testAMonthRollsAsTwoDaysThenFourWeeks() {
        let values: [Double?] = (0..<30).map { Double($0) }
        let rolls = MetricTrendMath.weekRolls(values)
        XCTAssertEqual(rolls.map(\.count), [2, 7, 7, 7, 7])
        XCTAssertEqual(rolls.map(\.start), [0, 2, 9, 16, 23])
        XCTAssertEqual(rolls[0].average, 0.5)
        XCTAssertEqual(rolls[4].average, 26)
    }

    func testARollWithNoRecordedDayHasNoAverage() {
        let values: [Double?] = [nil, nil, 1, 2, 3, 4, 5, 6, 7]
        let rolls = MetricTrendMath.weekRolls(values)
        XCTAssertEqual(rolls.map(\.count), [2, 7])
        XCTAssertNil(rolls[0].average)
        XCTAssertEqual(rolls[0].recorded, 0)
        XCTAssertEqual(rolls[1].recorded, 7)
        XCTAssertEqual(rolls[1].average, 4)
    }

    func testFittedScaleSnapsOutwardAndKeepsAMinimumSpan() {
        let scale = MetricTrendMath.fittedScale([56, 58, 61], step: 5, pad: 4, minimumSpan: 20,
                                                fallback: 40...80)
        XCTAssertEqual(scale.lowerBound, 45)
        XCTAssertEqual(scale.upperBound, 70)

        let narrow = MetricTrendMath.fittedScale([60, 60, 60], step: 5, pad: 1, minimumSpan: 20,
                                                 fallback: 40...80)
        XCTAssertGreaterThanOrEqual(narrow.upperBound - narrow.lowerBound, 20)
        XCTAssertTrue(narrow.contains(60))
    }

    func testFittedScaleFallsBackWhenNothingWasRecordedAndIncludesABand() {
        XCTAssertEqual(MetricTrendMath.fittedScale([nil], step: 5, pad: 1, minimumSpan: 10,
                                                   fallback: 40...80), 40...80)
        let withBand = MetricTrendMath.fittedScale([34.2], step: 0.5, pad: 0.5, minimumSpan: 2,
                                                   fallback: 30...38, including: 33.0...35.0)
        XCTAssertLessThanOrEqual(withBand.lowerBound, 32.5)
        XCTAssertGreaterThanOrEqual(withBand.upperBound, 35.5)
    }

    func testFractionIsClampedToTheRuler() {
        XCTAssertEqual(MetricTrendMath.fraction(50, in: 0...100), 0.5)
        XCTAssertEqual(MetricTrendMath.fraction(120, in: 0...100), 1)
        XCTAssertEqual(MetricTrendMath.fraction(-5, in: 0...100), 0)
    }
}
