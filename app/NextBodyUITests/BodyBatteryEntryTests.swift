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

    func testPageTwoCardOpensBodyBattery() {
        let app = launchPageTwo()
        let card = app.buttons["BODY_BATTERY"]
        XCTAssertTrue(card.waitForExistence(timeout: 30),
                      "page two should show the Body Battery card")
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !(card.exists && card.isHittable) {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(card.isHittable, "Body Battery on page two cannot be pressed")
        var last = card.frame
        for _ in 0..<12 {
            Thread.sleep(forTimeInterval: 0.25)
            if card.frame == last { break }
            last = card.frame
        }
        card.tap()

        XCTAssertTrue(app.staticTexts["OF 100"].waitForExistence(timeout: 30),
                      "page two Body Battery should open the reserve page")
        XCTAssertEqual(app.buttons["Back"].value as? String, "BODY BATTERY")
        XCTAssertTrue(app.buttons["range.DAY"].exists)

        app.buttons["Back"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 8),
                      "back from Body Battery should land on home page two")
    }

    func testBackFromProfileEntryReturnsToMe() {
        let app = launch(route: "profile")
        XCTAssertTrue(app.buttons["BODY_BATTERY"].waitForExistence(timeout: 30),
                      "profile never showed the body battery plate")
        app.buttons["BODY_BATTERY"].tap()
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
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

    private func launchPageTwo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_HOME_PAGE"] = "1"
        app.launchEnvironment["NB_DEBUG_NOW"] = shiftedISO(-12 * 3600)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        Thread.sleep(forTimeInterval: 2)
        return app
    }

    private func shiftedISO(_ seconds: TimeInterval) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f.string(from: Date().addingTimeInterval(seconds))
    }

    private func launch(route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = route
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        // A fresh simulator may present the first-morning notification primer.
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        return app
    }
}
