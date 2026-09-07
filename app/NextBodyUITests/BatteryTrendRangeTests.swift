import XCTest

/// Paper 12F · the battery trend is the instrument plus DAY / WEEK / MONTH.
/// The lime readout stays on the device page.
final class BatteryTrendRangeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDayIsTheLandingRange() {
        let app = launchTrend()
        XCTAssertTrue(app.staticTexts["TODAY"].waitForExistence(timeout: 30),
                      "battery trend should open on the last 24 hours")
        XCTAssertTrue(app.buttons["range.DAY"].exists)
        XCTAssertTrue(app.buttons["range.WEEK"].exists)
        XCTAssertTrue(app.buttons["range.MONTH"].exists)
        XCTAssertTrue(app.staticTexts["OVERNIGHT"].exists)
        XCTAssertTrue(app.otherElements["battery.probe"].waitForExistence(timeout: 6),
                      "the trend must take a finger the way HEART does")
        XCTAssertTrue(app.staticTexts["HIGH"].exists)
        XCTAssertTrue(app.staticTexts["LOW"].exists)
        XCTAssertTrue(app.staticTexts["LAST PLUG"].exists)
        XCTAssertTrue(app.staticTexts["LEFT"].waitForExistence(timeout: 6),
                      "the seed log has a learned slope — LEFT is how many days remain")
        XCTAssertFalse(app.staticTexts["Every plug-in and unplug is a step on this line."].exists,
                       "the lime hero does not belong on this page")
    }

    func testWeekAndMonthSwapThePeriodWord() {
        let app = launchTrend()
        let week = app.buttons["range.WEEK"]
        XCTAssertTrue(week.waitForExistence(timeout: 30))
        XCTAssertTrue(week.isHittable, "WEEK pill is on screen but not tappable")

        week.tap()
        XCTAssertTrue(app.staticTexts["LAST 7 DAYS"].waitForExistence(timeout: 6),
                      "WEEK should switch the window to the last 7 days")
        XCTAssertFalse(app.staticTexts["TODAY"].exists)

        app.buttons["range.MONTH"].tap()
        XCTAssertTrue(app.staticTexts["LAST 30 DAYS"].waitForExistence(timeout: 6),
                      "MONTH should switch the window to the last 30 days")
        XCTAssertFalse(app.staticTexts["LAST 7 DAYS"].exists)
    }

    func testDebugRangeOpensOnMonth() {
        let app = launchTrend(range: "MONTH")
        XCTAssertTrue(app.staticTexts["LAST 30 DAYS"].waitForExistence(timeout: 30),
                      "NB_DEBUG_BATTERY_RANGE should land on that window")
    }

    private func launchTrend(range: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "battery"
        if let range {
            app.launchEnvironment["NB_DEBUG_BATTERY_RANGE"] = range
        }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }
}
