import XCTest

/// Second-level back: `‹ TITLE` is one control, and a left-edge swipe follows the finger.
/// `buttons["Back"].tap()` used to pass because the accessibility centre landed on the
/// word — to the right of a leading-edge overlay that ate the mark. These tests tap the
/// mark, the word, and the vertical band around them; they also swipe from the left
/// edge (not the button) to commit or cancel.
final class DetailBackTapTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTappingTheLeadingBackMarkReturnsHome() {
        let app = launchDetail("fuel")
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 30), "fuel detail never opened")
        XCTAssertGreaterThanOrEqual(back.frame.height, 44, "back hit target shorter than 44 pt")

        back.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()

        XCTAssertTrue(waitUntilGone(back, timeout: 6),
                      "a tap on the leading back mark did not pop the detail page")
    }

    func testTappingChatLeadingBackMarkReturnsHome() {
        let app = launchDetail("chat")
        XCTAssertTrue(app.buttons["HISTORY"].waitForExistence(timeout: 45),
                      "chat never opened")
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 6), "chat has no Back control")
        XCTAssertGreaterThanOrEqual(back.frame.height, 44, "chat back shorter than 44 pt")

        back.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()

        XCTAssertTrue(waitUntilGone(back, timeout: 6),
                      "a tap on chat's leading back mark did not pop")
    }

    func testFuelBackTapMatrixReturnsFromEverySpot() {
        let spots: [(CGFloat, CGFloat, String)] = [
            (0.06, 0.50, "chevron centre"),
            (0.04, 0.50, "leading of chevron"),
            (0.14, 0.50, "between mark and word"),
            (0.38, 0.50, "title left"),
            (0.62, 0.50, "title centre"),
            (0.08, 0.16, "above the mark"),
            (0.08, 0.84, "below the mark"),
            (0.22, 0.28, "title upper"),
            (0.22, 0.72, "title lower"),
        ]
        for spot in spots {
            let app = launchDetail("fuel")
            let back = app.buttons["Back"]
            XCTAssertTrue(back.waitForExistence(timeout: 30),
                          "fuel not open for \(spot.2)")
            XCTAssertGreaterThanOrEqual(back.frame.height, 44,
                                        "hit target shorter than 44 pt at \(spot.2)")
            print("BACK-TAP: fuel \(spot.2) frame=\(back.frame)")
            back.coordinate(withNormalizedOffset: CGVector(dx: spot.0, dy: spot.1)).tap()
            XCTAssertTrue(waitUntilGone(back, timeout: 6),
                          "tap \(spot.2) did not pop the fuel page")
            app.terminate()
        }
    }

    func testChatBackTapMatrixReturnsFromEverySpot() {
        let app = launchDetail("chat")
        XCTAssertTrue(app.buttons["HISTORY"].waitForExistence(timeout: 45),
                      "chat never opened")
        let spots: [(CGFloat, CGFloat, String)] = [
            (0.08, 0.50, "chevron centre"),
            (0.18, 0.50, "title left"),
            (0.45, 0.50, "AI COACH word"),
            (0.20, 0.18, "above the title"),
            (0.20, 0.84, "below the title"),
        ]
        for (i, spot) in spots.enumerated() {
            let back = app.buttons["Back"]
            XCTAssertTrue(back.waitForExistence(timeout: i == 0 ? 6 : 12),
                          "chat not open for \(spot.2)")
            XCTAssertGreaterThanOrEqual(back.frame.height, 44,
                                        "chat hit target shorter than 44 pt at \(spot.2)")
            print("BACK-TAP: chat \(spot.2) frame=\(back.frame)")
            back.coordinate(withNormalizedOffset: CGVector(dx: spot.0, dy: spot.1)).tap()
            XCTAssertTrue(waitUntilGone(back, timeout: 6),
                          "tap \(spot.2) did not pop chat")
            if i < spots.count - 1 {
                reopenChat(app)
            }
        }
    }

    func testWindowTapOnTheChevronItselfReturns() {
        let app = launchDetail("fuel")
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 30), "fuel detail never opened")
        let frame = back.frame
        let chevron = app.windows.firstMatch
            .coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX + 8, dy: frame.midY))
        chevron.tap()
        XCTAssertTrue(waitUntilGone(back, timeout: 6),
                      "a window tap on the ‹ mark itself did not pop")
    }

    func testTrainingChevronTapReturns() {
        let app = launchDetail("training")
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 30), "training detail never opened")
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilGone(back, timeout: 6),
                      "training leading mark did not pop")
    }

    func testLeftEdgeSwipePopsFuel() {
        let app = launchDetail("fuel")
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 30), "fuel detail never opened")
        edgeSwipe(app, to: 0.62, velocity: XCUIGestureVelocity(700))
        XCTAssertTrue(waitUntilGone(back, timeout: 6),
                      "a left-edge swipe did not pop the fuel page")
    }

    func testShortLeftEdgeSwipeStaysOnFuel() {
        let app = launchDetail("fuel")
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 30), "fuel detail never opened")
        edgeSwipe(app, to: 0.10, velocity: XCUIGestureVelocity(40), hold: 0.25)
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(back.exists, "a short left-edge swipe popped the fuel page")
    }

    func testLeftEdgeSwipePopsChat() {
        let app = launchDetail("chat")
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 45), "chat never opened")
        edgeSwipe(app, to: 0.62, velocity: XCUIGestureVelocity(700))
        XCTAssertTrue(waitUntilGone(back, timeout: 6),
                      "a left-edge swipe did not pop chat")
    }

    func testShortLeftEdgeSwipeStaysOnChat() {
        let app = launchDetail("chat")
        XCTAssertTrue(app.buttons["HISTORY"].waitForExistence(timeout: 45),
                      "chat never opened")
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 6), "chat has no Back control")
        edgeSwipe(app, to: 0.10, velocity: XCUIGestureVelocity(40), hold: 0.25)
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(back.exists, "a short left-edge swipe popped chat")
        XCTAssertTrue(app.buttons["HISTORY"].exists, "chat chrome left after a cancelled swipe")
    }

    private func launchDetail(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = route
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func reopenChat(_ app: XCUIApplication) {
        app.buttons["AI COACH"].tap()
        XCTAssertTrue(app.buttons["HISTORY"].waitForExistence(timeout: 8),
                      "dock keyboard did not reopen chat")
    }

    private func edgeSwipe(_ app: XCUIApplication, to dx: CGFloat,
                           velocity: XCUIGestureVelocity, hold: TimeInterval = 0) {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.55))
        start.press(forDuration: 0.08, thenDragTo: end,
                    withVelocity: velocity, thenHoldForDuration: hold)
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return !element.exists
    }
}
