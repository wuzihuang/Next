import XCTest
@testable import NextBodySyncCore

final class LaunchGateTests: XCTestCase {
    func testReturningUserGoesHome() {
        XCTAssertEqual(LaunchGate.stage(hasBoundBand: true, profileComplete: true), "root")
    }

    func testBandWithoutProfileGoesToOnboarding() {
        XCTAssertEqual(LaunchGate.stage(hasBoundBand: true, profileComplete: false), "gateOnboarding")
    }

    func testNoBandGoesToConnectWhetherOrNotProfileExists() {
        XCTAssertEqual(LaunchGate.stage(hasBoundBand: false, profileComplete: true), "gateConnect")
        XCTAssertEqual(LaunchGate.stage(hasBoundBand: false, profileComplete: false), "gateConnect")
    }

    func testFirstRunIsOnlyUnpairedAndUnfinished() {
        XCTAssertTrue(LaunchGate.isFirstRun(hasBoundBand: false, profileComplete: false))
        XCTAssertFalse(LaunchGate.isFirstRun(hasBoundBand: false, profileComplete: true))
        XCTAssertFalse(LaunchGate.isFirstRun(hasBoundBand: true, profileComplete: false))
    }

    func testGoTrueExpiredBodyIsExpiredNotWrong() {
        let body = #"{"error_code":"otp_expired","msg":"Token has expired or is invalid"}"#
        XCTAssertTrue(LaunchGate.isExpiredCode(status: 403, body: body))
        XCTAssertFalse(LaunchGate.isExpiredCode(status: 429, body: body))
        XCTAssertFalse(LaunchGate.isExpiredCode(status: 403, body: "Invalid login credentials"))
    }
}
