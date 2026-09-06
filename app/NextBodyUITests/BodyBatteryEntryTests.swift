import XCTest

/// ADR 0017 · 「我的」身份卡与 COMPOSITION 之间那块身体电量是整块一热区，
/// 点进去是 BODY BATTERY 页，返回回「我的」。
final class BodyBatteryEntryTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testProfileModuleOpensBodyBattery() {
        let app = launch(route: "profile")
        XCTAssertTrue(app.staticTexts["YEAR"].waitForExistence(timeout: 30),
                      "profile never showed the instrument plates")

        let entry = app.buttons["BODY_BATTERY"]
        XCTAssertTrue(entry.waitForExistence(timeout: 6), "身份卡下没有身体电量模块")
        entry.tap()

        XCTAssertTrue(app.staticTexts["OF 100"].waitForExistence(timeout: 30),
                      "身体电量卡没有进到 13 详情页")
        XCTAssertTrue(app.buttons["range.DAY"].exists)
        XCTAssertTrue(app.buttons["range.WEEK"].exists)
        XCTAssertTrue(app.staticTexts["TODAY'S TARGET"].exists)
    }

    func testBackFromProfileEntryReturnsToMe() {
        let app = launch(route: "profile")
        XCTAssertTrue(app.buttons["BODY_BATTERY"].waitForExistence(timeout: 30),
                      "profile never showed the body battery plate")
        app.buttons["BODY_BATTERY"].tap()
        XCTAssertTrue(app.staticTexts["OF 100"].waitForExistence(timeout: 30),
                      "detail never opened")

        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 6))
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()

        XCTAssertTrue(app.staticTexts["YEAR"].waitForExistence(timeout: 8),
                      "从「我的」进身体电量，返回应该回「我的」")
        XCTAssertTrue(app.buttons["BODY_BATTERY"].exists)
        XCTAssertTrue(app.staticTexts["MEASUREMENTS"].exists)
    }

    private func launch(route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = route
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }
}
