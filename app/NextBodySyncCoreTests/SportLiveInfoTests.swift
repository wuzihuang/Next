import XCTest
@testable import NextBodySyncCore

final class SportLiveInfoTests: XCTestCase {
    func testUnknownEnergyUnitsNeverBecomeKcal() {
        for raw: UInt32 in [0, 50, 100, 150, 11_273, UInt32.max] {
            let report = SportLiveInfo.deviceReport(heartRate: 80, rawCalories: raw, durationSec: 0, runState: 1)
            XCTAssertEqual(report.rawCalories, raw)
            XCTAssertNil(report.caloriesKcal)
            XCTAssertEqual(report.durationSec, 0)
        }
    }

    func testNewSessionsResetAndPreserveExactHeartRate() {
        for _ in 0..<3 {
            var metrics = SportMetricAccumulator(weightKg: 70, age: 34, male: true)
            XCTAssertEqual(metrics.kcal, 0)
            XCTAssertNil(metrics.heartRate)
            for (index, heart) in [50, 100, 150, 95].enumerated() {
                let report = SportLiveInfo.deviceReport(heartRate: heart, rawCalories: UInt32(index * 50),
                                                       durationSec: index * 2, runState: 1)
                metrics = metrics.accepting(timestamp: Date(timeIntervalSince1970: Double(index * 2)),
                                            heartRate: report.heartRate, caloriesKcal: report.caloriesKcal,
                                            runState: report.runState)
                XCTAssertEqual(metrics.heartRate, heart)
                XCTAssertLessThan(metrics.kcal, 5, "Raw counters must not inflate kcal")
            }
            XCTAssertEqual(metrics.sampleCount, 4)
        }
    }
}
