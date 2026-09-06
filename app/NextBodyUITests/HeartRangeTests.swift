import XCTest

/// Paper 04K · HEART is the instrument plus DAY / WEEK / MONTH, with HRV and
/// overnight SpO2 on the same clock. Default landing is the last 24 hours.
final class HeartRangeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDayIsTheLandingRange() {
        let app = launchHeart()
        XCTAssertTrue(app.staticTexts["LAST 24H"].waitForExistence(timeout: 30),
                      "heart should open on the last 24 hours")
        XCTAssertTrue(app.buttons["range.DAY"].exists)
        XCTAssertTrue(app.buttons["range.WEEK"].exists)
        XCTAssertTrue(app.buttons["range.MONTH"].exists)
        XCTAssertTrue(app.staticTexts["HEART RATE"].exists)
        XCTAssertTrue(app.staticTexts["ON THE SAME CLOCK"].exists)
        XCTAssertTrue(app.staticTexts["TIME IN ZONES"].exists)
    }

    func testWeekAndMonthSwapThePeriodWord() {
        let week = launchHeart(range: "WEEK")
        XCTAssertTrue(week.staticTexts["LAST 7 DAYS"].waitForExistence(timeout: 30),
                      "WEEK should open the last 7 user days")
        XCTAssertTrue(week.staticTexts["ON THE SAME CLOCK"].waitForExistence(timeout: 6))
        XCTAssertTrue(week.staticTexts["WINDOW MAX"].exists)
        XCTAssertFalse(week.staticTexts["TIME IN ZONES"].exists)

        let month = launchHeart(range: "MONTH")
        XCTAssertTrue(month.staticTexts["LAST 30 DAYS"].waitForExistence(timeout: 30),
                      "MONTH should open the last 30 user days")
        XCTAssertTrue(month.staticTexts["WINDOW MAX"].waitForExistence(timeout: 6))
        XCTAssertFalse(month.staticTexts["LAST 24H"].exists)
    }

    func testDebugRangeOpensOnMonth() {
        let app = launchHeart(range: "MONTH")
        XCTAssertTrue(app.staticTexts["LAST 30 DAYS"].waitForExistence(timeout: 30),
                      "NB_DEBUG_HEART_RANGE should land on that window")
        XCTAssertTrue(app.staticTexts["ON THE SAME CLOCK"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["WINDOW MAX"].exists)
    }

    private func launchHeart(range: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "vitals.heart"
        if let range {
            app.launchEnvironment["NB_DEBUG_HEART_RANGE"] = range
        }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }
}
