import XCTest

/// ADR 0015 · TRAINING is the ring plus DAY / WEEK / MONTH. Week and month
/// heroes stay on the 0–21 day scale — never a 7-day or 30-day sum.
final class TrainingRangeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDayIsTheLandingRange() {
        let app = launchTraining()
        XCTAssertTrue(app.staticTexts["THROUGH THE DAY"].waitForExistence(timeout: 30),
                      "training should open on today's cumulative curve")
        XCTAssertTrue(app.buttons["range.DAY"].exists)
        XCTAssertTrue(app.buttons["range.WEEK"].exists)
        XCTAssertTrue(app.buttons["range.MONTH"].exists)
        XCTAssertTrue(app.staticTexts["INGREDIENTS"].exists)
        XCTAssertTrue(app.staticTexts["STEPS AND BURN"].exists)
        XCTAssertTrue(app.buttons["START A SESSION"].exists)
        XCTAssertFalse(app.staticTexts["LAST 7 DAYS"].exists)
        XCTAssertFalse(app.staticTexts["A typical finished day. Not a 30-day sum."].exists)
    }

    func testWeekAndMonthSwapThePeriodWord() {
        let week = launchTraining(range: "WEEK")
        XCTAssertTrue(week.staticTexts["LAST 7 DAYS"].waitForExistence(timeout: 30),
                      "WEEK should open the last 7 user days")
        XCTAssertTrue(week.staticTexts["SEVEN DAYS"].waitForExistence(timeout: 6))
        XCTAssertTrue(week.staticTexts["INGREDIENTS"].exists)
        XCTAssertFalse(week.staticTexts["THROUGH THE DAY"].exists)
        XCTAssertFalse(week.staticTexts["A typical finished day. Not a 30-day sum."].exists)

        let month = launchTraining(range: "MONTH")
        XCTAssertTrue(month.staticTexts["LAST 30 DAYS"].waitForExistence(timeout: 30),
                      "MONTH should open the last 30 user days")
        XCTAssertTrue(month.staticTexts["THIRTY DAYS"].waitForExistence(timeout: 6))
        XCTAssertTrue(month.staticTexts["A typical finished day. Not a 30-day sum."].waitForExistence(timeout: 6))
        XCTAssertFalse(month.staticTexts["THROUGH THE DAY"].exists)
    }

    func testDebugRangeOpensOnMonth() {
        let app = launchTraining(range: "MONTH")
        XCTAssertTrue(app.staticTexts["LAST 30 DAYS"].waitForExistence(timeout: 30),
                      "NB_DEBUG_TRAINING_RANGE should land on that window")
        XCTAssertTrue(app.staticTexts["THIRTY DAYS"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["A typical finished day. Not a 30-day sum."].exists)
    }

    private func launchTraining(range: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "training"
        if let range {
            app.launchEnvironment["NB_DEBUG_TRAINING_RANGE"] = range
        }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }
}
