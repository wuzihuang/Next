import XCTest

final class SportRecapTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCompletedSessionShowsCurveZonesAndReopensAfterRestart() {
        let app = launchSession(missingHeart: false)
        XCTAssertTrue(app.staticTexts["TIME IN EACH ZONE"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["AVG HR"].exists)
        XCTAssertTrue(app.staticTexts["Z1"].exists)
        XCTAssertTrue(app.staticTexts["Z5"].exists)
        XCTAssertTrue(app.staticTexts["Gaps have no heart-rate observations."].exists)
        app.buttons["DONE"].tap()
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "NB_DEBUG_SESSION")
        app.launchEnvironment.removeValue(forKey: "NB_DEBUG_SESSION_STOP")
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "training"
        app.launch()
        let last = app.descendants(matching: .any)["training.lastSession"].firstMatch
        for _ in 0..<5 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.waitForExistence(timeout: 20))
        last.tap()
        XCTAssertTrue(app.staticTexts["TIME IN EACH ZONE"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Gaps have no heart-rate observations."].exists)
    }

    func testMissingHeartShowsReasonInsteadOfInventedCurveAndZones() {
        let app = launchSession(missingHeart: true)
        XCTAssertTrue(app.staticTexts["TIME IN EACH ZONE"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["No heart-rate record."].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["0.0 MIN · 0%"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "——")).count >= 3)
    }

    private func launchSession(missingHeart: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment = ["NB_DEBUG_STAGE": "root", "NB_DEBUG_CONSENT": "granted",
            "NB_DEBUG_LANG": "en", "NB_DEBUG_SESSION": "1", "NB_DEBUG_SESSION_STOP": "5"]
        if missingHeart { app.launchEnvironment["NB_DEBUG_SESSION_WRIST"] = "off" }
        app.launch()
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 2) { notNow.tap() }
        return app
    }
}
