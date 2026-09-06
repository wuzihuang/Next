import XCTest
@testable import NextBodySyncCore

final class AIFreshnessPolicyTests: XCTestCase {
    @MainActor func testHungRefreshReturnsTimeoutWithinBudget() async {
        let result = await AIFreshnessPolicy.prepare(budget: .milliseconds(1)) {
            try? await Task.sleep(for: .milliseconds(100))
            return .ready
        }
        XCTAssertEqual(result, .timeout)
    }
    @MainActor func testFinishedRefreshReturnsItsActualState() async {
        let result = await AIFreshnessPolicy.prepare(budget: .seconds(1)) { .pending }
        XCTAssertEqual(result, .pending)
    }
}
