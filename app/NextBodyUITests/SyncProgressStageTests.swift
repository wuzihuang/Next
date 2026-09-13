import XCTest

final class SyncProgressStageTests: XCTestCase {
    func testConnectionVerificationIsPartOfProgress() {
        let app = launch(stage: "verifying")
        XCTAssertTrue(app.staticTexts["8% · 正在验证设备"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["立即同步"].value as? String, "正在验证设备")
        assertHomeMatches(app, line: "8% · 正在验证设备")
    }

    func testDumpCompleteStillShowsLessThanWholeSyncComplete() {
        let app = launch(stage: "updating")
        XCTAssertTrue(app.staticTexts["92% · 正在更新结果"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["立即同步"].value as? String, "正在更新结果")
        assertHomeMatches(app, line: "92% · 正在更新结果")
    }

    func testCompletionClearsTheBarAndTheButtonTogether() {
        let app = launch(stage: "complete")
        XCTAssertTrue(app.buttons["立即同步"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["立即同步"].value as? String ?? "", "")
        XCTAssertFalse(app.otherElements["device.syncProgress"].exists,
                       "A finished sync must not leave the bar sitting at 100%")
        XCTAssertFalse(app.staticTexts["100% · 同步完成"].exists)
        // Nothing here waits for a late label, so give the page its entry beat before
        // tapping back; a tap during the transition is swallowed.
        let back = app.buttons["返回"]
        XCTAssertTrue(back.waitForExistence(timeout: 20))
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: back)], timeout: 10)
        back.tap()
        let close = app.buttons["panel-dismiss"]
        if close.exists { close.tap() }
        let status = app.staticTexts["panel.syncStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        XCTAssertNotEqual(status.label, "100% · 同步完成")
        XCTAssertFalse(app.otherElements["panel.syncProgress"].exists)
    }

    private func assertHomeMatches(_ app: XCUIApplication, line: String) {
        app.buttons["返回"].tap()
        let close = app.buttons["panel-dismiss"]
        if close.exists { close.tap() }
        let status = app.staticTexts["panel.syncStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        XCTAssertEqual(status.label, line, "Returning home must not start a second progress calculation")
    }

    private func launch(stage: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_LANG"] = "zh-Hans"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "device"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_SYNC_STAGE"] = stage
        app.launch()
        return app
    }
}
