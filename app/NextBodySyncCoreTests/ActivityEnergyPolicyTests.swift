import XCTest
@testable import NextBodySyncCore

final class ActivityEnergyPolicyTests: XCTestCase {
    func testRawVendorCaloriesNeverBecomeDisplayedActiveEnergy() {
        let rawVendorCounters = Array(repeating: 50.0, count: 288)

        XCTAssertNil(ActivityEnergyPolicy.displayTotal(
            settledActiveKcal: nil,
            archivedVendorCalories: rawVendorCounters
        ))
    }

    func testSettledActiveEnergyWinsEvenWhenVendorCounterIsHuge() {
        XCTAssertEqual(ActivityEnergyPolicy.displayTotal(
            settledActiveKcal: 158,
            archivedVendorCalories: [14_400]
        ), 158)
    }

    func testInvalidSettledEnergyStaysUnknown() {
        for value in [Double.nan, .infinity, -1] {
            XCTAssertNil(ActivityEnergyPolicy.displayTotal(
                settledActiveKcal: value,
                archivedVendorCalories: [500]
            ))
        }
    }

    func testHourlyChartCannotPlotArchivedVendorCalories() {
        XCTAssertEqual(
            ActivityEnergyPolicy.hourlyBins(
                count: 24,
                archivedVendorCalories: Array(repeating: 600, count: 24)
            ),
            Array<Double?>(repeating: nil, count: 24)
        )
    }
}
