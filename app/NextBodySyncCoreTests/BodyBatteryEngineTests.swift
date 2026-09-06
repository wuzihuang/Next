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
