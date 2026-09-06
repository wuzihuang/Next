import XCTest

final class EdgeBackNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCancelledThenCompletedSwipeRestoresHomePageTwo() {
        let app = launch(route: "vitals.heart", homePage: "1")
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 30))
        swipe(app, to: 0.10, velocity: 40, hold: 1.0)
        XCTAssertTrue(back.exists, "cancelling must retain the detail page")
        swipe(app, to: 0.75, velocity: 700)
        XCTAssertTrue(back.waitForNonExistence(timeout: 6))
        let sleep = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "SLEEP")).firstMatch
        XCTAssertTrue(sleep.waitForExistence(timeout: 6), "return must restore home page two")
        sleep.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 6), "the path must accept another push after a pop")
        swipe(app, to: 0.75, velocity: 700)
        XCTAssertTrue(back.waitForNonExistence(timeout: 6))
    }

    func testNestedSwipeReturnsToProfileThenHome() {
        let app = launch(route: "profile")
        let entry = app.buttons["ALL_MEASUREMENTS"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        for _ in 0..<5 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        let kept = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "KEPT")).firstMatch
        XCTAssertTrue(kept.waitForExistence(timeout: 8))
        swipe(app, to: 0.75, velocity: 700)
        XCTAssertTrue(kept.waitForNonExistence(timeout: 6))
        XCTAssertTrue(entry.waitForExistence(timeout: 6), "nested pop must return to Profile")
        XCTAssertTrue(app.buttons["Back"].isHittable,
                      "the edge drag must not open a measurement sheet over Profile")
        swipe(app, to: 0.75, velocity: 700)
        XCTAssertTrue(app.buttons["Back"].waitForNonExistence(timeout: 6))
    }

    private func launch(route: String, homePage: String = "0") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = route
        app.launchEnvironment["NB_DEBUG_HOME_PAGE"] = homePage
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func swipe(_ app: XCUIApplication, to x: CGFloat, velocity: CGFloat, hold: TimeInterval = 0) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55))
            .press(forDuration: 0.08,
                   thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.55)),
                   withVelocity: XCUIGestureVelocity(velocity), thenHoldForDuration: hold)
    }
}
