import XCTest

/// Reported bug: tapping the dock's bottom-right orb does not open the plus / tools
/// bottom sheet. Drives a real hit on the orb (not VoiceOver's default action, which
/// bypasses `PressHold`).
final class DockOrbPlusMenuTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTappingDockOrbOpensPlusMenu() {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_NOW"] = eveningISO()
        app.launch()

        // Same home-ready signal the other UI tests use. The orb itself is a
        // UIViewRepresentable overlay and may not appear as a "Camera" button.
        let strip = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "TRAINING")).firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 30), "home strip never appeared")

        let orb = app.buttons["Camera"]
        XCTAssertTrue(orb.waitForExistence(timeout: 5), "dock orb never appeared as Camera")

        // Hit the glyph's centre. `orb.tap()` can take the accessibility default action,
        // which calls `onPlus` without going through PressHold — the path a finger uses.
        orb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.staticTexts["Photograph your meal"].waitForExistence(timeout: 4),
                      "tapping the dock orb did not open the plus menu")
    }

    private func eveningISO() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f.string(from: Date().addingTimeInterval(-12 * 3600))
    }
}
