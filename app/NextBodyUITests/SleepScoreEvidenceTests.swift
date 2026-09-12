import XCTest

/// Simulator-only rendering evidence for explicit audit fixtures, not a claim that the
/// test device measured a night. Pure scoring math is covered by SleepScoreMathTests.
final class SleepScoreEvidenceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDayExplainsEffectiveWeightsCoverageAndTheFourRecoveryNumbers() {
        let app = launchSleep(range: "DAY")
        let hero = app.otherElements["vitals.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 30))
        XCTAssertTrue(hero.isHittable, "The score must be visible, not underneath an onboarding sheet")
        XCTAssertTrue((hero.value as? String ?? "").hasPrefix("87 "))
        XCTAssertTrue(app.staticTexts.matching(identifier: "WEIGHT 29.4%").firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(identifier: "WEIGHT 41.2%").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["WEIGHTS ARE SHARES OF THIS SCORE; MISSING GROUPS ARE EXCLUDED"].exists)
        capture(app, name: "sleep-fixture-day-score-breakdown")

        let coverage = app.staticTexts["NIGHT DATA COVERAGE"]
        reveal(coverage, in: app)
        XCTAssertTrue(app.staticTexts["51.6% OF SLEEP"].exists)
        XCTAssertTrue(app.staticTexts["99.5% OF SLEEP"].exists,
                      "A few missing oxygen minutes must not be rounded to full coverage")
        let gap = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "LONGEST GAP 4H 34M")).firstMatch
        XCTAssertTrue(gap.exists, "342/663 minutes must retain its 274-minute longest gap")
        reveal(gap, in: app)
        capture(app, name: "sleep-fixture-day-partial-coverage")

        // Recovery closes on four numbers, no HRV trace among them. The fixture's 342
        // measured HRV minutes are one 168 ms peak and 341 at 67 ms, so their mean prints
        // 67 — the peak is evidence for the coverage card above, not a curve to draw.
        let hrv = app.otherElements["NIGHT HRV"]
        reveal(hrv, in: app)
        XCTAssertTrue((hrv.value as? String ?? "").hasPrefix("67 MS"))
        for tile in ["NIGHT SPO2", "MEAN RESPIRATION", "SLEEP LOW HR"] {
            XCTAssertTrue(app.otherElements[tile].exists, "Missing \(tile) from the four numbers")
        }
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "SCALE 0–")).firstMatch.exists,
                       "The night HRV chart and its ruler are retired")
        capture(app, name: "sleep-fixture-day-recovery-numbers")
    }

    func testWeekExplainsAllFourGroups() {
        let app = launchSleep(range: "WEEK")
        verifyWindow(app, nights: 7)
        capture(app, name: "sleep-fixture-week-score-and-groups")
    }

    func testMonthExplainsAllFourGroups() {
        let app = launchSleep(range: "MONTH")
        verifyWindow(app, nights: 30)
        capture(app, name: "sleep-fixture-month-score-and-groups")
    }

    private func verifyWindow(_ app: XCUIApplication, nights: Int) {
        XCTAssertTrue(app.staticTexts["LAST \(nights) NIGHTS"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.otherElements["vitals.probe.score"].exists)
        let breakdown = app.staticTexts["GROUP MEDIANS"]
        reveal(breakdown, in: app)
        for title in ["DURATION", "STRUCTURE", "RECOVERY", "REGULARITY"] {
            XCTAssertTrue(app.staticTexts[title].exists, "Missing \(title) from the \(nights)-night breakdown")
        }
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "SCORED ")).count, 4)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "COMPLETE INPUTS")).firstMatch.exists)
        let explanation = app.staticTexts["GROUP MEDIANS ARE SHOWN SEPARATELY; THE TOTAL IS THE MEDIAN OF NIGHTLY SCORES"]
        reveal(explanation, in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "NIGHTS STILL LEARNING PERSONAL BASELINES")).firstMatch.exists)
    }

    private func launchSleep(range: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "vitals.sleep"
        app.launchEnvironment["NB_DEBUG_SLEEP_RANGE"] = range
        app.launchEnvironment["NB_DEBUG_SLEEP_EVIDENCE"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        // A fresh simulator can present the notification primer above the route.
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        for _ in 0..<14 {
            let frame = element.frame
            if element.isHittable, frame.minY > 90, frame.maxY < app.frame.maxY - 140 { return }
            // Scroll from the margin, away from the chart's horizontal probe surface.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.78))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.38))
            start.press(forDuration: 0.02, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable, "Could not scroll \(element.label) into view")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
