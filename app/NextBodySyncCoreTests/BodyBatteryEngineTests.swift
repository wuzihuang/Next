import XCTest
@testable import NextBodySyncCore

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

    func testMissingQuietEvidenceNeverEarnsRestCredit() {
        for tick in [
            BodyBatteryEngine.Tick(heartRate: 55, hrvMS: 50, steps: 0, met: 1),
            .init(heartRate: 55, stress: 20, steps: 0, met: 1),
            .init(heartRate: 55, hrvMS: 50, stress: 20, met: 1)
        ] {
            let result = BodyBatteryEngine.replay(anchor: 50,
                ticks: Array(repeating: tick, count: 24), baseline: baseline)
            XCTAssertEqual(result.drivers.restorativeRest, 0)
        }
    }

    func testRestCreditStartsAfterTwentyCompletedQuietMinutes() {
        let tick = BodyBatteryEngine.Tick(heartRate: 55, hrvMS: 55, stress: 20, steps: 0, met: 1)
        let twenty = BodyBatteryEngine.replay(anchor: 50,
            ticks: Array(repeating: tick, count: 4), baseline: baseline)
        let twentyFive = BodyBatteryEngine.replay(anchor: 50,
            ticks: Array(repeating: tick, count: 5), baseline: baseline)
        XCTAssertEqual(twenty.drivers.restorativeRest, 0)
        XCTAssertGreaterThan(twentyFive.drivers.restorativeRest, 0)
        XCTAssertLessThan(twentyFive.value, twenty.value,
            "Rest credit moderates drain; it is not advertised as net charging.")
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
        XCTAssertGreaterThan(close(sleptMinutes: nil, workout: false, from: first), 0,
                             "A night the band never saw is not a sleepless night.")
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
