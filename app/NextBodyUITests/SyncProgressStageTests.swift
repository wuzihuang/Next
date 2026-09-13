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

    func test100AndButtonCompletionAgree() {
        let app = launch(stage: "complete")
        XCTAssertTrue(app.staticTexts["100% · 同步完成"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["立即同步"].value as? String ?? "", "")
        assertHomeMatches(app, line: "100% · 同步完成")
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
