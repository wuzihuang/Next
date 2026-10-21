import XCTest
@testable import NextBodySyncCore

final class SportMetricAccumulatorTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_000)
    private var empty: SportMetricAccumulator {
        SportMetricAccumulator(weightKg: 70, age: 34, male: true, sportMode: 3)
    }
    private func report(_ state: SportMetricAccumulator, _ seconds: Double,
                        hr: Int? = 120, kcal: Double? = nil, run: Int? = 1) -> SportMetricAccumulator {
        state.accepting(timestamp: epoch.addingTimeInterval(seconds), heartRate: hr,
                        caloriesKcal: kcal, runState: run)
    }

    func testNativeZeroIsAuthoritativeAndDoesNotResumeEstimation() {
        let estimated = report(report(empty, 0), 10)
        XCTAssertGreaterThan(estimated.kcal, 0)
        let nativeZero = report(estimated, 11, kcal: 0)
        XCTAssertEqual(nativeZero.kcal, 0)
        XCTAssertEqual(nativeZero.calorieSource, .band)
        XCTAssertTrue(nativeZero.hasEnergyEvidence)
        XCTAssertEqual(nativeZero.calorieCorrection?.previousKcal, estimated.kcal)
        XCTAssertEqual(nativeZero.calorieCorrection?.replacementKcal, 0)
        XCTAssertEqual(report(nativeZero, 15).kcal, 0)
    }

    func testProfileAloneDoesNotPublishZeroAsMeasuredEnergy() {
        XCTAssertTrue(empty.estimationAvailable)
        XCTAssertFalse(empty.hasEnergyEvidence)
        XCTAssertFalse(report(empty, 0).hasEnergyEvidence)
        XCTAssertFalse(report(report(empty, 0), 16).hasEnergyEvidence)
        XCTAssertTrue(report(report(empty, 0), 15).hasEnergyEvidence)
    }

    func testStrengthModeUsesObservedRunningIntervalsWithoutRequiringHeartRate() {
        let strength = SportMetricAccumulator(
            weightKg: 70, age: 34, male: true, sportMode: 25)
        let first = report(strength, 0, hr: nil)
        let second = report(first, 10, hr: nil)

        let expected = (3.5 - 1) * 3.5 * 70 / 200 * 10 / 60
        XCTAssertEqual(second.kcal, expected, accuracy: 0.000001)
        XCTAssertEqual(second.estimatedSeconds, 10, accuracy: 0.000001)
        XCTAssertTrue(second.hasEnergyEvidence)
        XCTAssertNil(second.heartRate)
    }

    func testStrengthModeDoesNotInferDurationFromFallbackHeartCallbacks() {
        let strength = SportMetricAccumulator(
            weightKg: 70, age: 34, male: true, sportMode: 25)
        let second = report(report(strength, 0, run: nil), 10, run: nil)

        XCTAssertEqual(second.kcal, 0)
        XCTAssertEqual(second.estimatedSeconds, 0)
        XCTAssertFalse(second.hasEnergyEvidence)
        XCTAssertEqual(second.heartRate, 120)
    }

    func testStrengthModesHaveExplicitConservativeMETMappings() {
        XCTAssertEqual(SportMetricAccumulator.strengthMET(sportMode: 25), 3.5)
        XCTAssertEqual(SportMetricAccumulator.strengthMET(sportMode: 29), 5.0)
        XCTAssertEqual(SportMetricAccumulator.strengthMET(sportMode: 46), 3.0)
        XCTAssertEqual(SportMetricAccumulator.strengthMET(sportMode: 47), 3.5)
        XCTAssertNil(SportMetricAccumulator.strengthMET(sportMode: 24))
        XCTAssertNil(SportMetricAccumulator.strengthMET(sportMode: nil))
    }

    func testCumulativeNativeTotalsReplaceRatherThanAddIncludingCorrections() {
        let first = report(empty, 0, kcal: 50)
        let duplicate = report(first, 1, kcal: 50)
        XCTAssertEqual(duplicate.kcal, 50)
        let next = report(duplicate, 2, kcal: 100)
        XCTAssertEqual(next.kcal, 100)
        let correction = report(next, 3, kcal: 75)
        XCTAssertEqual(correction.kcal, 75)
        XCTAssertNotNil(correction.calorieCorrection)
    }

    func testNewSessionResetsAllMetricsAndNativeAuthority() {
        let old = report(empty, 0, hr: 170, kcal: 50)
        let fresh = empty
        XCTAssertEqual(old.sampleCount, 1)
        XCTAssertEqual(fresh.sampleCount, 0)
        XCTAssertNil(fresh.heartRate)
        XCTAssertNil(fresh.averageHR)
        XCTAssertNil(fresh.peakHR)
        XCTAssertEqual(fresh.kcal, 0)
        XCTAssertEqual(fresh.calorieSource, .estimate)
    }

    func testNoIntegrationAcrossPauseStopMissingHeartRateOrInterruption() {
        let first = report(empty, 0)
        for state in [report(first, 5, run: 0), report(first, 5, run: 2),
                      report(first, 5, hr: nil), first.interrupted()] {
            XCTAssertNil(state.heartRate)
            XCTAssertEqual(report(state, 10).kcal, 0)
            XCTAssertGreaterThan(report(report(state, 10), 11).kcal, 0)
        }
    }

    func testNoIntegrationAcrossLongGapOrBackwardClock() {
        let first = report(empty, 0)
        XCTAssertEqual(report(first, 16).kcal, 0)
        XCTAssertEqual(report(first, -1).kcal, 0)
        XCTAssertGreaterThan(report(first, 15).kcal, 0)
    }

    func testInvalidRawHeartRatesAreRejectedWithoutClamping() {
        for value in [-1, 0, 256, 65535] {
            let state = report(empty, 0, hr: value)
            XCTAssertNil(state.heartRate)
            XCTAssertEqual(state.sampleCount, 0)
            XCTAssertNil(state.averageHR)
        }
    }

    func testRealFiftyBPMChangesRemainExactAndAveragesUseAcceptedSamples() {
        let first = report(empty, 0, hr: 50)
        let second = report(first, 1, hr: 100)
        let third = report(second, 2, hr: 150)
        XCTAssertEqual(first.heartRate, 50)
        XCTAssertEqual(second.heartRate, 100)
        XCTAssertEqual(third.heartRate, 150)
        XCTAssertEqual(third.averageHR, 100)
        XCTAssertEqual(third.peakHR, 150)
        XCTAssertEqual(third.sampleCount, 3)
    }

    func testFreshnessRequiresNonnegativeAgeInsideWindow() {
        let state = report(empty, 0)
        XCTAssertEqual(state.liveHR(at: epoch.addingTimeInterval(14)), 120)
        XCTAssertNil(state.liveHR(at: epoch.addingTimeInterval(15)))
        XCTAssertNil(state.liveHR(at: epoch.addingTimeInterval(-1)))
    }

    func testUnknownRunStateAllowsFallbackButOtherStatesDoNot() {
        XCTAssertEqual(report(empty, 0, run: nil).heartRate, 120)
        for run in [0, 2, 3, -1] {
            XCTAssertNil(report(empty, 0, run: run).heartRate)
        }
    }

    func testAerobicEstimateSubtractsRestingEnergyBeforeIntegration() {
        let state = report(report(empty, 0, hr: 100), 10, hr: 150)
        let maleHeart = -55.0969 + 0.6309 * 125.0
        let averageRate = (maleHeart + 0.1988 * 70.0 + 0.2017 * 34.0) / 4.184
        XCTAssertEqual(state.kcal, (averageRate - 3.5 * 70 / 200) * 10 / 60, accuracy: 0.000001)
        let female = SportMetricAccumulator(weightKg: 60, age: 30, male: false, sportMode: 8)
        let femaleHeart = -20.4022 + 0.4472 * 120.0
        let expected = (femaleHeart - 0.1263 * 60.0 + 0.0740 * 30.0) / 4.184
        XCTAssertEqual(report(report(female, 0), 10).kcal,
                       (expected - 3.5 * 60 / 200) * 10 / 60, accuracy: 0.000001)
        for weight in [Double.nan, .infinity, 0, -70] {
            let invalid = SportMetricAccumulator(weightKg: weight, age: 34, male: true, sportMode: 3)
            XCTAssertEqual(report(report(invalid, 0), 10).kcal, 0)
        }
        for age in [nil, 0, -1] as [Int?] {
            let invalid = SportMetricAccumulator(weightKg: 70, age: age, male: true, sportMode: 3)
            XCTAssertEqual(report(report(invalid, 0), 10).kcal, 0)
        }
    }

    func testInvalidCaloriesDoNotTakeNativeAuthorityOrPoisonTotals() {
        for kcal in [Double.nan, .infinity, -1] {
            let state = report(report(empty, 0, kcal: kcal), 10)
            XCTAssertEqual(state.calorieSource, .estimate)
            XCTAssertGreaterThan(state.kcal, 0)
            XCTAssertTrue(state.kcal.isFinite)
        }
    }

    func testOneHourEstimateStaysInPhysiologicalKilocalorieScale() {
        var state = empty
        for second in stride(from: 0, through: 3_600, by: 10) {
            state = report(state, Double(second), hr: 100)
        }

        XCTAssertGreaterThan(state.kcal, 300)
        XCTAssertLessThan(state.kcal, 500)
    }

    func testLowOrOutOfRangeHeartRateIsNotCalorieEvidenceOrMeasuredZero() {
        for heart in [1, 50, 80, 89, 151, 220, 255] {
            let state = report(report(empty, 0, hr: heart), 10, hr: heart)
            XCTAssertEqual(state.heartRate, heart)
            XCTAssertEqual(state.kcal, 0)
            XCTAssertEqual(state.estimatedSeconds, 0)
            XCTAssertFalse(state.hasEnergyEvidence)
        }
    }

    func testUnsupportedActivityDoesNotBorrowAnAerobicEquation() {
        for mode in [nil, 0, 13, 16, 24, 32, 34, 65535] as [Int?] {
            let start = SportMetricAccumulator(weightKg: 70, age: 34, male: true, sportMode: mode)
            let state = report(report(start, 0), 10)
            XCTAssertFalse(start.estimationAvailable)
            XCTAssertFalse(state.hasEnergyEvidence)
            XCTAssertEqual(state.heartRate, 120)
        }
    }

    func testAerobicModelDoesNotExtrapolateOutsideItsStudyPopulation() {
        for (weight, age) in [(46.0, 34), (121.0, 34), (70.0, 17), (70.0, 46)] {
            let start = SportMetricAccumulator(weightKg: weight, age: age, male: true, sportMode: 3)
            XCTAssertFalse(start.estimationAvailable)
            XCTAssertFalse(report(report(start, 0), 10).hasEnergyEvidence)
        }
        let strength = SportMetricAccumulator(weightKg: 130, age: 60, male: true, sportMode: 25)
        XCTAssertTrue(strength.estimationAvailable)
        XCTAssertTrue(report(report(strength, 0, hr: nil), 10, hr: nil).hasEnergyEvidence)
    }

    func testRejectedHeartRateBreaksEnergyCoverageWithoutErasingAcceptedEnergy() {
        let valid = report(report(empty, 0), 10)
        let rejected = report(valid, 11, hr: 80)
        let resumed = report(rejected, 12)
        XCTAssertEqual(resumed.kcal, valid.kcal)
        XCTAssertEqual(resumed.estimatedSeconds, 10)
        XCTAssertGreaterThan(report(resumed, 13).kcal, valid.kcal)
    }

    func testDuplicateTimestampCannotChangeTheNextIntervalOrCountAnotherBeat() {
        let first = report(empty, 0, hr: 100)
        let duplicate = report(first, 0, hr: 150)
        XCTAssertEqual(duplicate.sampleCount, first.sampleCount)
        XCTAssertEqual(duplicate.heartRate, first.heartRate)
        XCTAssertEqual(report(duplicate, 10, hr: 100).kcal,
                       report(first, 10, hr: 100).kcal, accuracy: 0.000001)
    }

    func testOutOfOrderReportCannotRollBackACumulativeCounter() {
        let first = report(empty, 10, kcal: 50)
        let stale = report(first, 9, kcal: 1)
        XCTAssertEqual(stale.kcal, 50)
        XCTAssertNil(stale.calorieCorrection)
        XCTAssertEqual(stale.sampleCount, 1)
    }

    func testStrengthEnergyDoesNotChangeWithHeartRateSexOrAge() {
        for mode in [25, 29, 46, 47] {
            let low = SportMetricAccumulator(weightKg: 70, age: nil, male: false, sportMode: mode)
            let high = SportMetricAccumulator(weightKg: 70, age: 70, male: true, sportMode: mode)
            XCTAssertEqual(report(report(low, 0, hr: nil), 10, hr: nil).kcal,
                           report(report(high, 0, hr: 200), 10, hr: 200).kcal)
        }
    }

    func testUnsupportedEstimateCanStillUseVerifiedNativeEnergy() {
        let start = SportMetricAccumulator(weightKg: nil, age: nil, male: false, sportMode: 16)
        let state = report(start, 0, kcal: 0)
        XCTAssertTrue(state.hasEnergyEvidence)
        XCTAssertEqual(report(state, 1, kcal: 12).kcal, 12)
    }

    func testConstantRateDoesNotDependOnCallbackFrequency() {
        let expected = report(report(empty, 0), 10)
        var everySecond = empty
        for second in 0...10 { everySecond = report(everySecond, Double(second)) }
        XCTAssertEqual(everySecond.kcal, expected.kcal, accuracy: 0.000001)
        XCTAssertEqual(everySecond.estimatedSeconds, expected.estimatedSeconds)
    }

    func testInterruptedStreamRetainsTimestampHighWaterMark() {
        let state = report(empty, 10).interrupted()
        XCTAssertFalse(state.canAccept(at: epoch.addingTimeInterval(10)))
        XCTAssertFalse(state.canAccept(at: epoch.addingTimeInterval(9)))
        XCTAssertFalse(state.canAccept(at: Date(timeIntervalSince1970: .nan)))
        XCTAssertTrue(state.canAccept(at: epoch.addingTimeInterval(11)))
    }

    func testNonpositiveAerobicPredictionIsUnknownRatherThanMeasuredZero() {
        let start = SportMetricAccumulator(weightKg: 120, age: 18, male: false, sportMode: 8)
        let state = report(report(start, 0, hr: 90), 10, hr: 90)
        XCTAssertFalse(state.hasEnergyEvidence)
        XCTAssertEqual(state.estimatedSeconds, 0)
        XCTAssertEqual(state.heartRate, 90)
    }
}
