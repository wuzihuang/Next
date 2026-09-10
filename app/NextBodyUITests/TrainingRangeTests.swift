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
        XCTAssertFalse(app.staticTexts["LAST 7 DAYS"].exists)
        XCTAssertFalse(app.staticTexts["A typical finished day. Not a 30-day sum."].exists)
        reveal(app.staticTexts["ESTIMATE BASIS"], in: app)
        reveal(app.staticTexts["INGREDIENTS"], in: app)
        reveal(app.staticTexts["STEPS AND BURN"], in: app)
        reveal(app.buttons["START A SESSION"], in: app)
    }

    func testWeekAndMonthSwapThePeriodWord() {
        let week = launchTraining(range: "WEEK")
        XCTAssertTrue(week.staticTexts["LAST 7 DAYS"].waitForExistence(timeout: 30),
                      "WEEK should open the last 7 user days")
        XCTAssertTrue(week.staticTexts["SEVEN DAYS"].waitForExistence(timeout: 6))
        XCTAssertTrue(week.staticTexts["INGREDIENTS"].exists)
        XCTAssertFalse(week.staticTexts["THROUGH THE DAY"].exists)
        XCTAssertFalse(week.staticTexts["A typical finished day. Not a 30-day sum."].exists)
        reveal(week.staticTexts["HOW THE ZONES STACK"], in: week)
        XCTAssertTrue(week.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "SHARED SCALE")).firstMatch.exists)

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
        reveal(app.staticTexts["FIVE GROUPS"], in: app)
        XCTAssertTrue(app.staticTexts["2 days, then four groups of 7."].exists)
        XCTAssertFalse(app.staticTexts["Four rolling weeks, each one an average of finished days. Empty days stay empty."].exists)
    }

    func testMissingTargetStillShowsRecordedActivity() {
        let app = launchTraining(fixture: "no-target")
        XCTAssertTrue(app.staticTexts["NO TARGET YET"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["No suggested range yet. Recorded activity is still shown below."].exists)
        reveal(app.staticTexts["THROUGH THE DAY"], in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "LATEST LOAD SAMPLE")).firstMatch.exists)
        reveal(app.staticTexts["INGREDIENTS"], in: app)
        XCTAssertTrue(app.staticTexts["1,652"].exists, "the real day total survives a missing target")
        XCTAssertTrue(app.staticTexts["ELEVATED HR PERIOD"].exists)
        XCTAssertFalse(app.staticTexts["STRENGTH"].exists)
        reveal(app.staticTexts["TIME IN EACH ZONE"], in: app)
    }

    func testEmptyCurveShowsNoInventedSamples() {
        let app = launchTraining(fixture: "empty-curve")
        XCTAssertTrue(app.staticTexts["ESTIMATE BASIS"].waitForExistence(timeout: 30))
        reveal(app.staticTexts["NO LOAD SAMPLES"], in: app)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "LATEST LOAD SAMPLE")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["TARGET 16.0"].exists, "a horizontal target reference may remain without samples")
    }

    func testChineseEvidenceExplainsBaselineAndCoverage() {
        let app = launchTraining(fixture: "baseline", language: "zh-Hans")
        XCTAssertTrue(app.staticTexts["估算依据"].waitForExistence(timeout: 30))
        reveal(app.staticTexts["估算依据"], in: app)
        XCTAssertTrue(app.otherElements["training.evidence"].staticTexts["基线建立中"].isHittable)
        XCTAssertTrue(app.staticTexts["HRV 基线夜数"].exists)
        XCTAssertTrue(app.staticTexts["静息心率基线夜数"].exists)
        reveal(app.staticTexts["有效心率"], in: app)
        XCTAssertTrue(app.staticTexts["有记录时长"].exists)
        XCTAssertTrue(app.staticTexts["基线不足五夜，建议范围仍是初步估算。"].exists)
        XCTAssertTrue(app.staticTexts["覆盖率按有效记录时长与已过去时长计算，不是佩戴时长。"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Training Chinese calculation evidence"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<9 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "expected visible training content", file: file, line: line)
    }

    private func launchTraining(range: String? = nil, fixture: String? = nil,
                                language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = language
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "training"
        if let range {
            app.launchEnvironment["NB_DEBUG_TRAINING_RANGE"] = range
        }
        if let fixture { app.launchEnvironment["NB_DEBUG_TRAINING_FIXTURE"] = fixture }
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch()
        return app
    }
}
