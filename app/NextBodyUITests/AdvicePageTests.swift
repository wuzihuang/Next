import XCTest

/// ADR 0022 · the face reads the day's set. Opening never generates a second one; REFRESH
/// is the only in-day regeneration, and a run keeps going when the app leaves.
final class AdvicePageTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testNumberedSuggestionsAreReadableAndReopeningReadsTheSameSet() {
        let app = launchAdvice("numbered")
        let heading = element("plan.eyebrow", in: app)
        XCTAssertTrue(heading.waitForExistence(timeout: 40))
        XCTAssertEqual(heading.label, "Suggestions 1")
        let first = element("plan.suggestion.1", in: app)
        XCTAssertTrue(first.exists)
        XCTAssertTrue(first.label.contains("1."))
        XCTAssertTrue(first.label.contains("several lines."), "Advice must retain its full text")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "plan.check.")).firstMatch.exists)
        XCTAssertFalse(element("plan.stale", in: app).exists)

        let fifth = element("plan.suggestion.5", in: app)
        for _ in 0..<6 where !fifth.isHittable { app.swipeUp() }
        XCTAssertTrue(fifth.isHittable, "The full list must be scrollable above the refresh control")
        XCTAssertTrue(fifth.label.contains("5."))
        let sources = app.buttons["ai.web-sources"]
        for _ in 0..<3 where !sources.isHittable { app.swipeUp() }
        XCTAssertTrue(sources.isHittable)
        sources.tap()
        XCTAssertTrue(app.staticTexts["NIH Office of Dietary Supplements"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        closeAdvice(app)
        openAdvice(app)
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "Suggestions 1", "Reopening on the same day reads the day's set, never generates again")
        XCTAssertFalse(element("plan.thinking", in: app).exists)
    }

    func testRefreshIsTheOnlyWayToGenerateAgain() {
        let app = launchAdvice("numbered")
        let heading = element("plan.eyebrow", in: app)
        XCTAssertTrue(heading.waitForExistence(timeout: 40))
        XCTAssertEqual(heading.label, "Suggestions 1")
        app.buttons["plan.regenerate"].tap()
        XCTAssertTrue(waitUntil(timeout: 10) { heading.exists && heading.label == "Suggestions 2" },
                      "REFRESH must replace the day's set")
    }

    func testInsufficientEvidenceHasNoFillerRows() {
        let app = launchAdvice("empty")
        let empty = element("plan.empty", in: app)
        XCTAssertTrue(empty.waitForExistence(timeout: 40))
        XCTAssertTrue(empty.label.contains("not enough recent evidence"))
        XCTAssertFalse(element("plan.suggestion.1", in: app).exists)
    }

    func testFailedRefreshLabelsRetainedSuggestionsAsEarlier() {
        let app = launchAdvice("failure")
        let heading = element("plan.eyebrow", in: app)
        XCTAssertTrue(heading.waitForExistence(timeout: 40))
        app.buttons["plan.regenerate"].tap()
        let error = element("plan.error", in: app)
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "Could not refresh. These are earlier suggestions.")
        XCTAssertEqual(heading.label, "Suggestions 1")
    }

    func testReopeningDuringGenerationAttachesToTheSameRun() {
        let app = launchAdvice("slow")
        XCTAssertTrue(element("plan.thinking", in: app).waitForExistence(timeout: 40))
        XCTAssertTrue(element("plan.hint", in: app).exists, "The wait says leaving does not lose it")
        closeAdvice(app)
        openAdvice(app)
        let heading = element("plan.eyebrow", in: app)
        XCTAssertTrue(heading.waitForExistence(timeout: 20))
        XCTAssertEqual(heading.label, "Suggestions 1")
    }

    func testYesterdaysSetStaysReadableWhileTodaysIsMade() {
        let app = launchAdvice("slow", yesterday: true)
        XCTAssertTrue(element("plan.making", in: app).waitForExistence(timeout: 40))
        XCTAssertTrue(element("plan.stale", in: app).exists, "Yesterday's set must be marked as such")
        XCTAssertTrue(element("plan.suggestion.1", in: app).exists, "Yesterday's set stays readable")
        XCTAssertFalse(element("plan.thinking", in: app).exists, "No thinking stage when there is an earlier set")
        let heading = element("plan.eyebrow", in: app)
        XCTAssertTrue(waitUntil(timeout: 20) { heading.exists && heading.label == "Suggestions 1" })
        XCTAssertFalse(element("plan.stale", in: app).exists)
        XCTAssertFalse(element("plan.making", in: app).exists)
    }

    func testRelaunchDuringGenerationAttachesInsteadOfStartingOver() {
        let app = launchAdvice("slow")
        XCTAssertTrue(element("plan.thinking", in: app).waitForExistence(timeout: 40))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "NB_DEBUG_ADVICE_FRESH")
        app.launch()
        let heading = element("plan.eyebrow", in: app)
        XCTAssertTrue(heading.waitForExistence(timeout: 40))
        XCTAssertEqual(heading.label, "Suggestions 1", "The relaunch attaches to the run it started")
    }

    private func launchAdvice(_ fixture: String, yesterday: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_PLAN"] = "1"
        app.launchEnvironment["NB_DEBUG_ADVICE_FIXTURE"] = fixture
        app.launchEnvironment["NB_DEBUG_ADVICE_FRESH"] = "1"
        if yesterday { app.launchEnvironment["NB_DEBUG_ADVICE_YESTERDAY"] = "1" }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return condition()
    }

    private func closeAdvice(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70)),
                   withVelocity: XCUIGestureVelocity(800), thenHoldForDuration: 0)
        XCTAssertTrue(element("plan.lip", in: app).waitForExistence(timeout: 5))
    }

    private func openAdvice(_ app: XCUIApplication) {
        element("plan.lip", in: app).swipeUp(velocity: XCUIGestureVelocity(800))
        XCTAssertTrue(element("plan.page", in: app).waitForExistence(timeout: 5))
    }
}
