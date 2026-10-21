import XCTest

final class HomeTimelineEntryTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTodayShowsSavedMealsWakeAndBodyScanWithoutSystemEvents() {
        let app = launch()

        for kind in ["meal", "wake", "bodyScan"] {
            XCTAssertTrue(event(kind, in: app).waitForExistence(timeout: 10))
        }
        XCTAssertFalse(event("now", in: app).exists)
        XCTAssertFalse(event("sync", in: app).exists)
        XCTAssertTrue(app.staticTexts["Today"].exists)
    }

    func testHistoryOpensRhythmAndSwitchesBetweenMonthAndWeek() {
        let app = launch()
        let range = app.buttons["TIMELINE_RANGE"]
        scrollTo(range, in: app)
        range.tap()

        XCTAssertTrue(app.buttons["RHYTHM_30D"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Rhythm 30D"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let days = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "RHYTHM_DAY_"))
        XCTAssertGreaterThanOrEqual(days.count, 30)
        app.buttons["RHYTHM_7D"].tap()
        XCTAssertEqual(days.count, 7)
        let weekScreenshot = XCTAttachment(screenshot: app.screenshot())
        weekScreenshot.name = "Rhythm 7D"
        weekScreenshot.lifetime = .keepAlways
        add(weekScreenshot)
        days.firstMatch.tap()
        XCTAssertTrue(app.otherElements["RHYTHM_DAY_DETAIL"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        app.buttons["RHYTHM_BACK"].tap()
        XCTAssertTrue(app.buttons["TIMELINE_DISMISS"].waitForExistence(timeout: 5))
    }

    func testBodyScanOpensTheActualSavedMeasurement() {
        let app = launch()
        let scan = event("bodyScan", in: app)
        scrollTo(scan, in: app)
        scan.tap()

        XCTAssertTrue(app.staticTexts["Body scan"].waitForExistence(timeout: 10))
    }

    func testHeaderPullStillDismissesTheTimeline() {
        let app = launch()
        let dismiss = app.buttons["TIMELINE_DISMISS"]
        let start = dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 120)))

        let hidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == false"), object: dismiss)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_HOME_SLOT"] = "timeline"
        let evening = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date())!
        app.launchEnvironment["NB_DEBUG_NOW"] = ISO8601DateFormatter().string(from: evening)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["TIMELINE_DISMISS"].waitForExistence(timeout: 30))
        return app
    }

    private func event(_ kind: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "TIMELINE_EVENT_\(kind)_")).firstMatch
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        let list = app.scrollViews["TIMELINE_LIST"]
        for _ in 0..<8 where !element.isHittable {
            list.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
