import XCTest
@testable import NextBodySyncCore

/// The user's day: real recovery can happen while awake, and physiological strain
/// can happen while still or asleep. These exercise the replay, not UI arithmetic.
final class BodyBatteryAdaptiveTests: XCTestCase {
    private let baseline = BodyBatteryEngine.Baseline(
        restingHeartRate: 55, maximumHeartRate: 190, hrvMS: 50, recoveryMultiplier: 1)

    private func replay(_ tick: BodyBatteryEngine.Tick, count: Int = 24,
                        anchor: Double = 50) -> BodyBatteryEngine.Result {
        BodyBatteryEngine.replay(anchor: anchor, ticks: Array(repeating: tick, count: count),
                                 baseline: baseline)
    }

    func testSustainedDaytimeRestActuallyRecharges() {
        let result = replay(.init(heartRate: 55, hrvMS: 55, stress: 20, steps: 0, met: 1))
        XCTAssertGreaterThan(result.value, 53, "Two hours of restorative rest must produce net recovery.")
    }

    func testSustainedRestingPulseCanRecoverWithMissingAutonomicChannels() {
        let result = replay(.init(heartRate: 55, steps: 0, met: 1))
        XCTAssertGreaterThan(result.value, 50,
            "Missing HRV and stress reduce confidence, but do not veto sustained heart and movement evidence.")
    }

    func testElevatedNonExerciseHeartRateCostsReserve() {
        let calm = replay(.init(heartRate: 72, steps: 0, met: 1))
        let elevated = replay(.init(heartRate: 90, steps: 0, met: 1))
        XCTAssertLessThan(elevated.value, calm.value - 3,
            "A raised resting pulse matters before crossing a workout HRR zone.")
    }

    func testSustainedSevereStrainCanReachLowReserveWithoutExercise() {
        let result = replay(.init(heartRate: 90, hrvMS: 20, stress: 90, steps: 0, met: 1),
                            count: 144, anchor: 85)
        XCTAssertLessThan(result.value, 20)
    }

    func testSleepWithSevereStrainDoesNotChargeLikeRestorativeSleep() {
        let calm = replay(.init(heartRate: 55, hrvMS: 55, stress: 20, steps: 0, met: 1, sleepStage: 1),
                          count: 72)
        let strained = replay(.init(heartRate: 90, hrvMS: 20, stress: 90, steps: 0, met: 1, sleepStage: 1),
                              count: 72)
        XCTAssertLessThan(strained.value, calm.value - 15)
        XCTAssertLessThanOrEqual(strained.value, 50,
            "The sleep label cannot override strong ongoing physiological strain.")
    }

    func testMissingEvidenceAndBriefRestCannotRefillTheBattery() {
        XCTAssertEqual(replay(.init(), count: 144).value, 50)
        XCTAssertLessThanOrEqual(replay(.init(heartRate: 55, stress: 20, steps: 0, met: 1), count: 1).value, 50)
        XCTAssertLessThanOrEqual(replay(.init(heartRate: 55, hrvMS: 55, stress: 90, steps: 0, met: 1)).value, 50)
    }

    func testARecordingGapRestartsTheRestWindow() {
        let quiet = BodyBatteryEngine.Tick(heartRate: 55, hrvMS: 55, stress: 20, steps: 0, met: 1)
        let interrupted = BodyBatteryEngine.replay(anchor: 50,
            ticks: Array(repeating: quiet, count: 4) + [.init()] + Array(repeating: quiet, count: 4),
            baseline: baseline)
        XCTAssertEqual(interrupted.drivers.restorativeRest, 0)
        XCTAssertLessThan(interrupted.value, 50)
    }

    func testZeroStepsDoNotMeanRestDuringNonWalkingExercise() {
        let result = replay(.init(heartRate: 150, hrvMS: 55, stress: 20, steps: 0, met: 8))
        XCTAssertEqual(result.drivers.restorativeRest, 0)
        XCTAssertLessThan(result.value, 35)
    }

    func testIsolatedOxygenDipDoesNotChangeSleepRecovery() {
        let quiet = BodyBatteryEngine.Tick(heartRate: 55, stress: 20, sleepStage: 1, oxygen: 98)
        var ticks = Array(repeating: quiet, count: 24)
        ticks[10].oxygen = 85
        let oneDip = BodyBatteryEngine.replay(anchor: 50, ticks: ticks, baseline: baseline)
        XCTAssertEqual(oneDip.value, replay(quiet).value, accuracy: 1e-10)
        for i in 10..<16 { ticks[i].oxygen = 92 }
        XCTAssertLessThan(BodyBatteryEngine.replay(anchor: 50, ticks: ticks, baseline: baseline).value, oneDip.value)
    }

    func testAuxiliaryEvidenceRequiresFifteenMinutesRegardlessOfSampleFrequency() {
        let quiet = BodyBatteryEngine.Tick(durationMinutes: 1, heartRate: 55, stress: 20,
                                            sleepStage: 1, oxygen: 98)
        var ticks = Array(repeating: quiet, count: 60)
        let normal = BodyBatteryEngine.replay(anchor: 50, ticks: ticks, baseline: baseline)
        for i in 20..<23 { ticks[i].oxygen = 85 }
        XCTAssertEqual(BodyBatteryEngine.replay(anchor: 50, ticks: ticks, baseline: baseline).value,
                       normal.value, accuracy: 1e-10, "Three minute readings are not fifteen minutes of evidence.")
        for i in 20..<40 { ticks[i].oxygen = 92 }
        XCTAssertLessThan(BodyBatteryEngine.replay(anchor: 50, ticks: ticks, baseline: baseline).value,
                          normal.value)
    }

    func testIncreasingStressNeverImprovesReserveAndAllDriversClose() {
        for anchor in [0.0, 0.1, 20, 50, 90, 100] {
            var previous = Double.infinity
            for stress in stride(from: 20, through: 100, by: 10) {
                let result = replay(.init(heartRate: 55, hrvMS: 50, stress: stress, steps: 0, met: 1), anchor: anchor)
                XCTAssertLessThanOrEqual(result.value, previous + 1e-9)
                XCTAssertTrue((0...100).contains(result.value))
                let d = result.drivers
                XCTAssertEqual(result.value - anchor, d.recovery + d.restorativeRest - d.awake - d.movement - d.stress,
                               accuracy: 1e-9)
                previous = result.value
            }
        }
    }
}

final class BodyBatteryEngineTests: XCTestCase {
    private let baseline = BodyBatteryEngine.Baseline(
        restingHeartRate: 55, maximumHeartRate: 190, hrvMS: 50, recoveryMultiplier: 1)

    func testEffectiveDriversCloseAtZero() {
        let result = BodyBatteryEngine.replay(anchor: 0.1, ticks: [
            .init(heartRate: 190, hrvMS: 10, stress: 100, steps: 1_000, met: 10)
        ], baseline: baseline)
        let d = result.drivers
        XCTAssertEqual(result.value, 0)
        XCTAssertEqual(result.value - 0.1,
            d.recovery - d.awake - d.movement - d.stress + d.restorativeRest,
            accuracy: 1e-10)
    }

    func testMissingAutonomicChannelsReduceButDoNotVetoRest() {
        let complete = BodyBatteryEngine.replay(anchor: 50,
            ticks: Array(repeating: .init(heartRate: 55, hrvMS: 50, stress: 20, steps: 0, met: 1), count: 24),
            baseline: baseline)
        for tick in [
            BodyBatteryEngine.Tick(heartRate: 55, hrvMS: 50, steps: 0, met: 1),
            .init(heartRate: 55, stress: 20, steps: 0, met: 1)
        ] {
            let result = BodyBatteryEngine.replay(anchor: 50,
                ticks: Array(repeating: tick, count: 24), baseline: baseline)
            XCTAssertGreaterThan(result.drivers.restorativeRest, 0)
            XCTAssertLessThan(result.value, complete.value)
        }
        let missingMovement = BodyBatteryEngine.replay(anchor: 50,
            ticks: Array(repeating: .init(heartRate: 55, hrvMS: 50, stress: 20), count: 24), baseline: baseline)
        XCTAssertEqual(missingMovement.drivers.restorativeRest, 0)
    }

    func testRestCreditStartsAfterTwentyCompletedQuietMinutes() {
        let tick = BodyBatteryEngine.Tick(heartRate: 55, hrvMS: 55, stress: 20, steps: 0, met: 1)
        let twenty = BodyBatteryEngine.replay(anchor: 50,
            ticks: Array(repeating: tick, count: 4), baseline: baseline)
        let twentyFive = BodyBatteryEngine.replay(anchor: 50,
            ticks: Array(repeating: tick, count: 5), baseline: baseline)
        XCTAssertEqual(twenty.drivers.restorativeRest, 0)
        XCTAssertGreaterThan(twentyFive.drivers.restorativeRest, 0)
        XCTAssertGreaterThan(twentyFive.value, twenty.value,
            "A sustained restorative state can overcome awake drain.")
    }

    func testRecoveryMultiplierUsesTheServerLowerBound() {
        let normal = BodyBatteryEngine.Baseline(restingHeartRate: 55,
            maximumHeartRate: 190, hrvMS: 50, recoveryMultiplier: 0.65)
        let result = BodyBatteryEngine.replay(anchor: 20,
            ticks: Array(repeating: .init(sleepStage: 2), count: 96), baseline: normal)
        XCTAssertEqual(result.value, 95 - 75 * exp(-0.011 * 0.65 * 96), accuracy: 1e-9)
    }
}

/// #24 · 电量必须能描述一天。These pin the direction and rough size of the calibration,
/// not the coefficients themselves: an ordinary working day has to cost far more than it
/// did, a short night has to cost more than a full one, and a workout more than either.
final class BodyBatteryDrainCalibrationTests: XCTestCase {
    private func baseline(sleptMinutes: Double?, wornThroughTheNight: Bool = false)
    -> BodyBatteryEngine.Baseline {
        .init(restingHeartRate: 55, maximumHeartRate: 190, hrvMS: 50, recoveryMultiplier: 1,
              sleepDebt: BodyBatteryEngine.sleepDebt(sleptMinutes: sleptMinutes,
                                                     wornThroughTheNight: wornThroughTheNight))
    }

    /// Eighteen waking hours of ordinary work: mostly sitting, a lot of light movement,
    /// and some real labour. No session.
    private func workingDay(withWorkout: Bool) -> [BodyBatteryEngine.Tick] {
        var ticks = (0..<216).map { i -> BodyBatteryEngine.Tick in
            switch i % 20 {
            case ..<8:  .init(heartRate: 60, hrvMS: 50, stress: 45, steps: 10, met: 1.1)
            case ..<17: .init(heartRate: 80, hrvMS: 47, stress: 50, steps: 150, met: 2.0)
            default:    .init(heartRate: 100, hrvMS: 44, stress: 60, steps: 450, met: 3.5)
            }
        }
        guard withWorkout else { return ticks }
        for i in 0..<12 {
            ticks[120 + i] = .init(heartRate: 150, hrvMS: 38, stress: 75, steps: 900, met: 9)
            ticks[132 + i] = .init(heartRate: 102, hrvMS: 40, stress: 68, steps: 120, met: 1.6)
        }
        return ticks
    }

    private func close(sleptMinutes: Double?, workout: Bool, from: Double = 100,
                       wornThroughTheNight: Bool = false) -> Double {
        BodyBatteryEngine.replay(
            anchor: from, ticks: workingDay(withWorkout: workout),
            baseline: baseline(sleptMinutes: sleptMinutes,
                               wornThroughTheNight: wornThroughTheNight)).value
    }

    func testSleepDebtIsOneOnAFullNightAndCapsAtFourHours() {
        XCTAssertEqual(BodyBatteryEngine.sleepDebt(sleptMinutes: 480), 1)
        XCTAssertEqual(BodyBatteryEngine.sleepDebt(sleptMinutes: 420), 1)
        XCTAssertEqual(BodyBatteryEngine.sleepDebt(sleptMinutes: 240), 1.6, accuracy: 1e-12)
        XCTAssertEqual(BodyBatteryEngine.sleepDebt(sleptMinutes: 60), 1.6, accuracy: 1e-12)
        XCTAssertEqual(BodyBatteryEngine.sleepDebt(sleptMinutes: nil), 1,
                       "A night with no record is not evidence of a short night.")
        XCTAssertEqual(BodyBatteryEngine.sleepDebt(sleptMinutes: nil, wornThroughTheNight: true), 1.6,
                       "A wrist that sat through the night without sleeping did not sleep.")
    }

    func testAShortNightAndAWorkingDayEndsNearThirty() {
        let close = close(sleptMinutes: 240, workout: false)
        XCTAssertGreaterThan(close, 25)
        XCTAssertLessThan(close, 45, "A full day of work used to land near 60 whatever the night was.")
    }

    func testAddingOneSessionCostsAnotherTwentyPoints() {
        let plain = close(sleptMinutes: 240, workout: false)
        let trained = close(sleptMinutes: 240, workout: true)
        XCTAssertLessThan(trained, plain - 15)
        XCTAssertLessThan(trained, 25)
    }

    func testAShortNightDrainsFasterThanAFullOne() {
        XCTAssertLessThan(close(sleptMinutes: 240, workout: false),
                          close(sleptMinutes: 480, workout: false) - 5)
    }

    func testASecondDayWithoutSleepReachesZero() {
        let first = close(sleptMinutes: 240, workout: false)
        XCTAssertEqual(
            close(sleptMinutes: nil, workout: false, from: first, wornThroughTheNight: true), 0,
            "A day that truly never slept is allowed to reach empty.")
        let morning = Array(workingDay(withWorkout: false).prefix(72))
        let unknown = BodyBatteryEngine.replay(anchor: first, ticks: morning, baseline: baseline(sleptMinutes: nil))
        let sleepless = BodyBatteryEngine.replay(anchor: first, ticks: morning,
            baseline: baseline(sleptMinutes: nil, wornThroughTheNight: true))
        XCTAssertGreaterThan(unknown.value, sleepless.value,
                             "Before either reaches zero, an unobserved night incurs no sleep-debt penalty.")
    }

    func testAQuietRestDayStillEndsHigh() {
        let quiet = BodyBatteryEngine.replay(
            anchor: 100,
            ticks: Array(repeating: .init(heartRate: 60, hrvMS: 50, stress: 42, steps: 5, met: 1.05),
                         count: 216),
            baseline: baseline(sleptMinutes: 480)).value
        XCTAssertGreaterThan(quiet, 55, "Resting all day must not read like working all day.")
    }
}
