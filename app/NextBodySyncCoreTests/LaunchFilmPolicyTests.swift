import XCTest
@testable import NextBodySyncCore

final class LaunchFilmPolicyTests: XCTestCase {
    func testColdStartHoldsTheMark() {
        XCTAssertTrue(LaunchFilmPolicy.shouldHoldStill(environment: [:]))
    }

    func testHarnessSkipsTheCover() {
        XCTAssertFalse(LaunchFilmPolicy.shouldHoldStill(
            environment: ["NB_DEBUG_STAGE": "root"]))
        XCTAssertFalse(LaunchFilmPolicy.shouldHoldStill(
            environment: ["NB_DEBUG_ROUTE": "device"]))
        XCTAssertFalse(LaunchFilmPolicy.shouldHoldStill(
            environment: ["NB_DEBUG_TAKEOVER": "wordmark"]))
        XCTAssertFalse(LaunchFilmPolicy.shouldHoldStill(
            environment: ["XCTestConfigurationFilePath": "/tmp/xctest"]))
    }
}
