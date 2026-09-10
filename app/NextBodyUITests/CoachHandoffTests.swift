import XCTest

final class CoachHandoffTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSmallTalkOpensCoachWithOriginalMessageAndOneAnswer() {
        assertHandoff(text: "I had a rough day and just want to talk.")
    }

    func testChineseSmallTalkKeepsTheOriginalWords() {
        assertHandoff(text: "今天心情不太好，想找你随便聊聊。")
    }

    func testInterruptedHandoffKeepsTheMessageAndShowsAnError() {
        assertHandoff(text: "Can we talk for a bit?", failure: true)
    }

    private func assertHandoff(text: String, failure: Bool = false) {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_DOCK"] = "keyboard"
        app.launchEnvironment["NB_DEBUG_DRAFT"] = text
        app.launchEnvironment["NB_DEBUG_CHAT_FIXTURE"] = "empty"
        app.launchEnvironment["NB_DEBUG_COACH_HANDOFF"] = failure ? "failure" : "1"
        app.launch()

        let send = app.buttons["dock-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 45))
        send.tap()

        XCTAssertTrue(app.buttons["HISTORY"].waitForExistence(timeout: 8), "Coach did not open automatically")
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5), "The original message was not transferred")
        let answer = failure ? "I couldn't complete this reply. Please try again."
            : "Tell me what happened. I'm listening."
        XCTAssertTrue(app.staticTexts[answer].waitForExistence(timeout: 8), "The handoff did not finish in Coach")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", text)).count, 1,
                       "Opening Coach submitted the original message a second time")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", answer)).count, 1)
        XCTAssertTrue(app.textFields["coach-input"].exists)

        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["AI COACH"].waitForExistence(timeout: 5))
        app.buttons["AI COACH"].tap()
        XCTAssertTrue(app.staticTexts[answer].waitForExistence(timeout: 5), "The conversation was lost on return")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", text)).count, 1)
    }
}
