import XCTest

/// F1 · B · the display is a display. The panel's resting (standby) face is not a widget and
/// carries no target: F1 gives Body Battery's detail page one entrance — the morning widget —
/// so no tap on the standby display, mid-swipe or otherwise, may leave Home.
final class HomeDisplayTapTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHeaderFlameUsesTheSeededWearRun() {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let flame = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "wear run")).firstMatch
        XCTAssertTrue(flame.waitForExistence(timeout: 30),
                      "home header never received the seeded wear-run flame")
    }

    func testTappingStandbyDisplayStaysOnHome() {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        // Evening, past the wake+6h window: the morning widget is suppressed and the panel
        // stays in standby, the face this test is about.
        app.launchEnvironment["NB_DEBUG_NOW"] = eveningISO()
        app.launch()

        // Standby face is up only once the first-run ceremony has folded away.
        let hint = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "I'M UP")).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 30), "standby readout never appeared")

        // The strip's training card — a button on Home and only on Home.
        let stripCard = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "TRAINING")).firstMatch
        XCTAssertTrue(stripCard.waitForExistence(timeout: 10), "home strip never appeared")

        // Tap the middle of the display, where the BODY BATTERY hero number block sits.
        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.47)).tap()

        Thread.sleep(forTimeInterval: 1.5)   // enough for any push to land

        // Every detail page carries the pinned back chevron ("Back"); Home never does.
        // That button appearing is exactly the reported bug.
        XCTAssertFalse(app.buttons["Back"].exists,
                       "tapping the standby display opened a detail page")
        XCTAssertTrue(hint.exists, "home is no longer frontmost")
    }

    func testDismissingPersonalizedDisplayReturnsToStandby() {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_NOW"] = eveningISO()
        app.launchEnvironment["NB_DEBUG_PANEL"] = "line"
        app.launch()

        let dismiss = app.buttons["panel-dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 30),
                      "personalized display never exposed its dismiss control")

        dismiss.tap()

        let hint = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "I'M UP")).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 5),
                      "dismissing the personalized display did not restore standby")
        XCTAssertFalse(dismiss.exists, "dismiss control remained after returning to standby")
    }

    func testThinkingDisplayAlsoExposesDismissControl() {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_NOW"] = eveningISO()
        app.launchEnvironment["NB_DEBUG_PANEL"] = "thinking"
        app.launch()

        // THINKING is a continuously animating TimelineView; on iOS 18.5 XCTest omits its
        // overlay button from accessibility snapshots even though the control is visible and
        // hit-testable. Exercise the actual top-right hit region instead.
        Thread.sleep(forTimeInterval: 10)
        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.915, dy: 0.15))
            .tap()

        let hint = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "I'M UP")).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 5),
                      "dismissing THINKING did not restore standby")
        XCTAssertFalse(app.buttons["panel-dismiss"].exists,
                       "THINKING dismiss control remained on standby")
    }

    private func eveningISO() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f.string(from: Date().addingTimeInterval(-12 * 3600))
    }
}
