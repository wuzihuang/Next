import XCTest

final class ChatHistoryTests: XCTestCase {
    func testSentMessageSurvivesAppRelaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "chat"
        app.launch()

        let input = app.textFields["coach-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        let question = "Remember this test word: " + UUID().uuidString
        input.tap()
        input.typeText(question)
        app.buttons["coach-send"].tap()
        XCTAssertTrue(app.staticTexts[question].waitForExistence(timeout: 5))

        // Relaunch the process, not just the view: the message must come from disk.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["coach-input"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts[question].waitForExistence(timeout: 10),
                      "The persisted conversation was lost after relaunch")
    }
}
