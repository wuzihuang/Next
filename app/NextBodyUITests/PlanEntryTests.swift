import XCTest

/// 04D · Plan is the root's third face: up from the lip opens it, down closes it,
/// and a horizontal drag still turns the two home pages.
final class PlanEntryTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSwipeUpFromLipOpensPlan() {
        let app = launchHome()
        XCTAssertTrue(app.otherElements["plan.lip"].waitForExistence(timeout: 40),
                      "plan lip never appeared on home")

        swipeUpFromLip(app)
        XCTAssertTrue(planOpened(app),
                      "swipe up from the lip did not open the plan face")
        XCTAssertTrue(app.staticTexts["plan.eyebrow"].exists
                        || app.otherElements["plan.eyebrow"].exists
                        || app.descendants(matching: .any)["plan.thinking"].exists,
                      "plan page is missing its title")
    }

    func testSwipeDownFromPlanReturnsHome() {
        let app = launchHome()
        XCTAssertTrue(app.otherElements["plan.lip"].waitForExistence(timeout: 40),
                      "plan lip never appeared on home")
        swipeUpFromLip(app)
        XCTAssertTrue(planOpened(app), "plan did not open before the close swipe")

        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.12))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.62))
        start.press(forDuration: 0.05, thenDragTo: end,
                    withVelocity: XCUIGestureVelocity(800), thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 1.2)

        XCTAssertTrue(app.otherElements["plan.lip"].waitForExistence(timeout: 4),
                      "swipe down from the plan face did not return home")
        XCTAssertFalse(app.otherElements["plan.page"].exists,
                       "plan page stayed up after the close swipe")
    }

    func testSlowSwipeDownFromPlanReturnsHome() {
        let app = launchHome()
        XCTAssertTrue(app.otherElements["plan.lip"].waitForExistence(timeout: 40),
                      "plan lip never appeared on home")
        swipeUpFromLip(app)
        XCTAssertTrue(planOpened(app), "plan did not open before the slow close swipe")

        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.12))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.70))
        start.press(forDuration: 0.2, thenDragTo: end,
                    withVelocity: XCUIGestureVelocity(140), thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 1.4)

        XCTAssertTrue(app.otherElements["plan.lip"].waitForExistence(timeout: 4),
                      "a slow downward drag did not return home")
        XCTAssertFalse(app.otherElements["plan.page"].exists,
                       "plan page stayed up after the slow close swipe")
    }

    func testHorizontalSwipeStillTurnsPage() {
        let app = launchHome()
        XCTAssertTrue(app.otherElements["plan.lip"].waitForExistence(timeout: 40),
                      "plan lip never appeared on home")

        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.55))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.55))
        start.press(forDuration: 0.05, thenDragTo: end,
                    withVelocity: XCUIGestureVelocity(1000), thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 2)

        if !sleepMarker(app).exists {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.55))
                .press(forDuration: 0.3, thenDragTo: end)
            Thread.sleep(forTimeInterval: 2)
        }

        XCTAssertTrue(sleepMarker(app).exists,
                      "horizontal drag no longer turns to page two")
        XCTAssertTrue(app.otherElements["plan.lip"].waitForExistence(timeout: 2),
                      "a page turn hid the plan lip")
        XCTAssertFalse(app.otherElements["plan.page"].exists,
                       "a page turn opened the plan face")
        XCTAssertFalse(app.buttons["Back"].exists,
                       "a page turn pushed a detail page")
    }

    private func launchHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_NOW"] = shiftedISO(-12 * 3600)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func swipeUpFromLip(_ app: XCUIApplication) {
        let lip = app.otherElements["plan.lip"]
        if lip.exists && lip.isHittable {
            lip.swipeUp(velocity: XCUIGestureVelocity(800))
            Thread.sleep(forTimeInterval: 1.2)
            if planOpened(app) { return }
        }
        // Fall back: the lip sits just above the Home Indicator. 0.96 is the
        // system home gesture and never reaches the app.
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.93))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.38))
        start.press(forDuration: 0.05, thenDragTo: end,
                    withVelocity: XCUIGestureVelocity(800), thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 1.2)
        if !planOpened(app) {
            start.press(forDuration: 0.25, thenDragTo: end)
            Thread.sleep(forTimeInterval: 1.2)
        }
    }

    private func planOpened(_ app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)["plan.page"].waitForExistence(timeout: 3)
            || app.buttons["plan.regenerate"].waitForExistence(timeout: 1)
    }

    private func sleepMarker(_ app: XCUIApplication) -> XCUIElement {
        let text = app.staticTexts["SLEEP"]
        if text.exists { return text }
        return app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "SLEEP")).firstMatch
    }

    private func shiftedISO(_ seconds: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime,
                                   .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: Date().addingTimeInterval(seconds))
    }
}
