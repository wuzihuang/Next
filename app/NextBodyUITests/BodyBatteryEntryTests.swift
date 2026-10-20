import XCTest

/// Body Battery stays on Home. ME no longer draws a second copy of it.
final class BodyBatteryEntryTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testProfileDoesNotHostBodyBattery() {
        let app = launch(route: "profile")
        XCTAssertTrue(app.buttons["COMPOSITION"].waitForExistence(timeout: 30),
                      "profile never showed the year map")
        XCTAssertFalse(app.buttons["BODY_BATTERY"].exists,
                       "ME should not draw a second Body Battery")
        XCTAssertTrue(app.buttons["BODY_LINK"].exists)
        XCTAssertTrue(app.staticTexts["MEASUREMENTS"].exists)
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
        XCTAssertEqual(app.buttons["Back"].value as? String, "READINESS")
        XCTAssertTrue(app.buttons["range.DAY"].exists)

        app.buttons["Back"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 8),
                      "back from Body Battery should land on home page two")
    }

    func testProfileCompositionReturnsToMe() {
        let app = launch(route: "profile")
        let entry = app.buttons["COMPOSITION"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30),
                      "profile never showed the year map")
        entry.tap()
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 30))
        back.tap()
        XCTAssertTrue(app.buttons["COMPOSITION"].waitForExistence(timeout: 8),
                      "composition opened from ME should return to ME")
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
