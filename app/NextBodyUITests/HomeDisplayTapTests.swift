import XCTest

/// F1 · B · the display is a display. The panel's resting (standby) face is not a widget and
/// carries no target: F1 gives Body Battery's detail page one entrance — the morning widget —
/// so no tap on the standby display, mid-swipe or otherwise, may leave Home.
final class HomeDisplayTapTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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

    private func eveningISO() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f.string(from: Date().addingTimeInterval(-12 * 3600))
    }
}
