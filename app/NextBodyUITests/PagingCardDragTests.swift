import XCTest

/// Reported bug: pressing the fuel card and dragging LEFT — the custom paging gesture —
/// opens the fuel detail page instead of turning to page 1 (Vitals). This test drags left
/// from the fuel card and asserts the correct behavior: the page turns (SLEEP appears)
/// and no detail page is pushed (no Back).
final class PagingCardDragTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDraggingLeftFromFuelCardTurnsPageInsteadOfOpeningDetail() {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        // Evening, past the wake+6h window — same clock setup as HomeDisplayTapTests.
        app.launchEnvironment["NB_DEBUG_NOW"] = shiftedISO(-12 * 3600)
        app.launch()

        var cardPrefix = "CALORIES"
        var fuelCard = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", cardPrefix)).firstMatch
        if !fuelCard.waitForExistence(timeout: 20) {
            cardPrefix = "FUEL"
            fuelCard = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", cardPrefix)).firstMatch
            XCTAssertTrue(fuelCard.waitForExistence(timeout: 20),
                          "neither CALORIES nor FUEL strip card appeared")
        }
        print("PAGING-DRAG: fuel card matched label prefix \(cardPrefix)")

        // The fuel card is the right card of the strip; drag left across the window.
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.735, dy: 0.79))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.79))

        // Attempt 1: quick, decisive drag.
        start.press(forDuration: 0.05, thenDragTo: end,
                    withVelocity: XCUIGestureVelocity(1000), thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 2)
        var backExists = app.buttons["Back"].exists
        var sleepExists = sleepMarker(app).exists
        print("PAGING-DRAG: attempt 1 → Back=\(backExists) SLEEP=\(sleepExists)")

        if !backExists && !sleepExists {
            // Drag did nothing: neither navigation nor page turn. Retry once, slower.
            print("PAGING-DRAG: attempt 1 did nothing; retrying with a slow drag")
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.735, dy: 0.79))
                .press(forDuration: 0.3, thenDragTo: end)
            Thread.sleep(forTimeInterval: 2)
            backExists = app.buttons["Back"].exists
            sleepExists = sleepMarker(app).exists
            print("PAGING-DRAG: attempt 2 (slow) → Back=\(backExists) SLEEP=\(sleepExists)")
        }

        // Correct behavior: the page turned to Vitals and no detail page was pushed.
        XCTAssertTrue(sleepExists,
                      "dragging left from the fuel card did not turn to page 1 (SLEEP)")
        XCTAssertFalse(backExists,
                       "dragging left from the fuel card opened the fuel detail page")
    }

    // Q5-b · the ownership law must not overcorrect: a clean tap on the fuel card still
    // opens the fuel detail page.
    func testTappingFuelCardStillOpensFuelDetail() {
        let app = launchToHome()

        let fuelCard = fuelCard(app)
        fuelCard.tap()
        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 4),
                      "a clean tap on the fuel card no longer opens the fuel detail page")
    }

    // Q5-c · a SLOW drag starting on the card is still a page turn, never a tap — this is
    // the case the old swiping gate was written for and it must keep holding.
    func testSlowDragFromFuelCardStillTurnsPage() {
        let app = launchToHome()
        _ = fuelCard(app)

        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.735, dy: 0.79))
        start.press(forDuration: 0.3, thenDragTo: window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.10, dy: 0.79)))
        Thread.sleep(forTimeInterval: 2)

        XCTAssertTrue(sleepMarker(app).exists,
                      "slow-dragging left from the fuel card did not turn to page 1 (SLEEP)")
        XCTAssertFalse(app.buttons["Back"].exists,
                       "a slow drag from the fuel card opened the fuel detail page")
    }

    private func launchToHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        // Evening, past the wake+6h window — same clock setup as HomeDisplayTapTests.
        app.launchEnvironment["NB_DEBUG_NOW"] = shiftedISO(-12 * 3600)
        app.launch()
        return app
    }

    @discardableResult
    private func fuelCard(_ app: XCUIApplication) -> XCUIElement {
        var fuelCard = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "CALORIES")).firstMatch
        if !fuelCard.waitForExistence(timeout: 20) {
            fuelCard = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "FUEL")).firstMatch
            XCTAssertTrue(fuelCard.waitForExistence(timeout: 20),
                          "neither CALORIES nor FUEL strip card appeared")
        }
        return fuelCard
    }

    private func sleepMarker(_ app: XCUIApplication) -> XCUIElement {
        let text = app.staticTexts["SLEEP"]
        if text.exists { return text }
        return app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "SLEEP")).firstMatch
    }

    private func shiftedISO(_ seconds: TimeInterval) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f.string(from: Date().addingTimeInterval(seconds))
    }
}
