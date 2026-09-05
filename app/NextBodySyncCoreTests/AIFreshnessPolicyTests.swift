import XCTest
@testable import NextBodySyncCore

final class AIFreshnessPolicyTests: XCTestCase {
    func testJustRecordedAndQueuedDataRequestRefresh() {
        XCTAssertTrue(AIFreshnessPolicy.requiresRefresh(question: "分析我刚记录的体重", pending: 0))
        XCTAssertTrue(AIFreshnessPolicy.requiresRefresh(question: "last week", pending: 1))
        XCTAssertFalse(AIFreshnessPolicy.requiresRefresh(question: "last week", pending: 0))
        XCTAssertTrue(AIFreshnessPolicy.requiresRefresh(question: "last week", pending: nil))
    }
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
