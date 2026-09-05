import XCTest

final class ChatPageTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMarkdownRendersWordsInsteadOfRawMarkers() {
        let app = launchChat(fixture: "markdown")

        XCTAssertTrue(app.staticTexts["Overnight recovery"].waitForExistence(timeout: 8),
                      "the heading never rendered")
        XCTAssertTrue(app.staticTexts["Deep sleep held"].exists, "the list item never rendered")
        XCTAssertTrue(app.staticTexts["RMSSD"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "RMSSD")).firstMatch.exists,
                      "inline code never rendered")
        XCTAssertFalse(app.staticTexts["**rate**"].exists)
        XCTAssertFalse(app.staticTexts["Heart **rate** looks *steady*. Use `RMSSD` as the overnight marker."].exists)
        XCTAssertFalse(app.staticTexts["## Overnight recovery"].exists)
    }

    func testEnteringChatLandsOnTheLatestMessage() {
        let app = launchChat(fixture: "long")

        let latest = app.staticTexts["CHAT_FIXTURE_LATEST"]
        XCTAssertTrue(latest.waitForExistence(timeout: 8), "the latest line never appeared")
        XCTAssertTrue(
            latest.isHittable,
            "entering chat left the thread at the top instead of the latest message"
        )

        let earliest = app.staticTexts["CHAT_FIXTURE_EARLIEST"]
        XCTAssertTrue(earliest.exists, "the seeded history was missing")
        XCTAssertFalse(
            earliest.isHittable,
            "the first message was still on screen; the page did not scroll to the latest"
        )
    }

    private func launchChat(fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "chat"
        app.launchEnvironment["NB_DEBUG_CHAT_FIXTURE"] = fixture
        app.launch()
        XCTAssertTrue(
            app.buttons["HISTORY"].waitForExistence(timeout: 45),
            "chat never opened from NB_DEBUG_ROUTE"
        )
        return app
    }
}
