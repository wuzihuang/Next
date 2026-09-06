import XCTest

/// ADR 0017 · BODY BATTERY is the curve plus DAY / WEEK / MONTH. Week and
/// month heroes stay on the 0–100 day scale — never a 7-day or 30-day sum.
final class BodyBatteryRangeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDayIsTheLandingRange() {
        let app = launchBodyBattery()
        XCTAssertTrue(app.staticTexts["OF 100"].waitForExistence(timeout: 30),
                      "body battery should open on today's charge curve")
        XCTAssertTrue(app.buttons["range.DAY"].exists)
        XCTAssertTrue(app.buttons["range.WEEK"].exists)
        XCTAssertTrue(app.buttons["range.MONTH"].exists)
        XCTAssertTrue(app.staticTexts["TODAY'S TARGET"].exists)
        XCTAssertFalse(app.staticTexts["LAST 7 DAYS"].exists)
        XCTAssertFalse(app.staticTexts["A typical morning peak. Not a 30-day sum."].exists)
    }

    func testWeekAndMonthSwapThePeriodWord() {
        let week = launchBodyBattery(range: "WEEK")
        XCTAssertTrue(week.staticTexts["LAST 7 DAYS"].waitForExistence(timeout: 30),
                      "WEEK should open the last 7 user days")
        XCTAssertTrue(week.staticTexts["SEVEN DAYS"].waitForExistence(timeout: 6))
        XCTAssertTrue(week.staticTexts["WAKE PEAKS"].exists)
        XCTAssertFalse(week.staticTexts["TODAY'S TARGET"].exists)
        XCTAssertFalse(week.staticTexts["A typical morning peak. Not a 30-day sum."].exists)

        let month = launchBodyBattery(range: "MONTH")
        XCTAssertTrue(month.staticTexts["LAST 30 DAYS"].waitForExistence(timeout: 30),
                      "MONTH should open the last 30 user days")
        XCTAssertTrue(month.staticTexts["THIRTY DAYS"].waitForExistence(timeout: 6))
        XCTAssertTrue(month.staticTexts["A typical morning peak. Not a 30-day sum."].waitForExistence(timeout: 6))
        XCTAssertFalse(month.staticTexts["TODAY'S TARGET"].exists)
    }

    func testDebugRangeOpensOnMonth() {
        let app = launchBodyBattery(range: "MONTH")
        XCTAssertTrue(app.staticTexts["LAST 30 DAYS"].waitForExistence(timeout: 30),
                      "NB_DEBUG_BODY_BATTERY_RANGE should land on that window")
        XCTAssertTrue(app.staticTexts["THIRTY DAYS"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["A typical morning peak. Not a 30-day sum."].exists)
    }

    private func launchBodyBattery(range: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "bodyBattery"
        if let range {
            app.launchEnvironment["NB_DEBUG_BODY_BATTERY_RANGE"] = range
        }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }
}
