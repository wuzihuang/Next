import XCTest

/// 04 · 8 大指标二级页 · every card on home page two is a hot zone, and each one opens its
/// own second level. Night HRV is no longer a card; it lives on the sleep page. RESPONSE
/// occupies the retired HRV slot.
final class VitalsSecondLevelTests: XCTestCase {

    /// The eight cards, in the order page two lays them out, each with the sensor line its own
    /// hero prints. The sensor line is what proves the right page arrived: it is unique per
    /// metric and it sits on the page rather than on the card that opened it. `title` is the
    /// nav word — the metric's own name, never a `VITALS ·` prefix.
    private static let cards: [(card: String, title: String, sensor: String, period: String)] = [
        ("SLEEP",    "SLEEP",          "OVERNIGHT STAGING",           "LAST NIGHT"),
        ("HEART",    "HEART",          "OPTICAL PPG SENSOR",          "TODAY"),
        ("RESPONSE", "RESPONSE",       "RESPONSE · LAST 24H",         "TODAY"),
        ("STRESS",   "STRESS",         "PHYSIOLOGICAL STRAIN",        "TODAY"),
        ("TEMP",     "TEMP",           "SKIN BASELINE OFFSET",        "TODAY"),
        ("STEPS",    "STEPS",          "DAILY CADENCE ACCUMULATED",   "TODAY"),
        ("DISTANCE", "DISTANCE",       "SPATIAL DISPLACEMENT",        "TODAY"),
        ("ACTIVE",   "ACTIVE ENERGY",  "DAILY METABOLIC BURN",        "TODAY"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEveryPageTwoCardOpensItsOwnDetailPage() {
        let app = launch()

        for entry in Self.cards {
            turnToVitals(app)

            let card = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", entry.card)).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10),
                          "\(entry.card) is not a hot zone on page two")
            XCTAssertTrue(card.isHittable, "\(entry.card) is on page two but cannot be pressed")
            card.tap()

            XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 6),
                          "tapping \(entry.card) pushed no page")
            XCTAssertEqual(app.buttons["Back"].value as? String, entry.title,
                           "\(entry.card) should title the page \(entry.title), not a VITALS prefix")
            // 04 · the hero's own sensor line. A wrong page would show a different one.
            let hero = app.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", entry.sensor)).firstMatch
            XCTAssertTrue(hero.waitForExistence(timeout: 6),
                          "\(entry.card) opened a page whose hero is not \(entry.sensor)")
            XCTAssertTrue(app.staticTexts[entry.period].waitForExistence(timeout: 2),
                          "\(entry.card) uses the wrong timeline period")

            app.buttons["Back"].tap()
            // Page two must come back with the stack — not page one. TEMP hittable means
            // the vitals board is showing again; the next card is already in reach.
            let pageTwo = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "TEMP")).firstMatch
            XCTAssertTrue(waitUntilHittable(pageTwo, timeout: 8),
                          "back from \(entry.card) should land on home page two")
        }
    }

    // MARK: driving

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        // Evening, past the wake+6h window — the same clock the other home tests use, so
        // the morning widget is not sitting over the strip.
        app.launchEnvironment["NB_DEBUG_NOW"] = shiftedISO(-12 * 3600)
        app.launch()
        XCTAssertTrue(fuelCard(app).waitForExistence(timeout: 40), "home never appeared")
        // ⚠️ Existence is not readiness: the strip fades in with the dock (FirstRun), and a
        // drag thrown at it before then is swallowed — which is why this test passed alone
        // and failed behind the rest of the suite on a busier simulator. `isHittable` is no
        // help here, it reads false for the strip's cards even as they take taps.
        Thread.sleep(forTimeInterval: 2)
        return app
    }

    /// Poll rather than sleep: `isHittable` has no `waitFor` of its own.
    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    /// ⚠️ Hittable is not *still*: the paging animation carries on after the cards become
    /// reachable, and `HotZoneTap` only fires on lift-off inside a 10 pt dead zone — a tap
    /// thrown at a card that is still travelling is retired by the movement instead of
    /// opening anything. Wait for the frame to stop changing before pressing.
    private func waitUntilStill(_ element: XCUIElement, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        var last = element.frame
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            let now = element.frame
            if now == last { return }
            last = now
        }
    }

    /// The page turn. ⚠️ Page two exists in the hierarchy at rest — it is parked off the
    /// right edge, not conditionally built — so `exists` is true for all eight cards before
    /// the page has turned, and tapping one of them fails on scroll-to-visible. TEMP being
    /// *hittable* is the only honest reading of "page two is showing".
    private func turnToVitals(_ app: XCUIApplication) {
        let marker = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "TEMP")).firstMatch
        let window = app.windows.firstMatch
        for _ in 0..<6 {
            if marker.exists && marker.isHittable { return waitUntilStill(marker, timeout: 3) }
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.735, dy: 0.79))
                .press(forDuration: 0.05,
                       thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.79)),
                       withVelocity: XCUIGestureVelocity(1000), thenHoldForDuration: 0)
            if waitUntilHittable(marker, timeout: 3) { return waitUntilStill(marker, timeout: 3) }
        }
        XCTFail("could not turn to home page two")
    }

    private func fuelCard(_ app: XCUIApplication) -> XCUIElement {
        let calories = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "CALORIES")).firstMatch
        if calories.exists { return calories }
        return app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "FUEL")).firstMatch
    }

    private func shiftedISO(_ seconds: TimeInterval) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f.string(from: Date().addingTimeInterval(seconds))
    }
}
