import XCTest

/// 探点 on vitals detail chart cards. The arithmetic lives in `VitalsProbeMathTests`;
/// these drive a real finger on the seeded simulator so the shell, the 标线, and the
/// hero staying put are not only true on paper.
final class VitalsProbeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHeartProbeReadsASampleWithoutMovingTheHero() {
        let app = launchDetail("vitals.heart")
        let probe = waitForProbe(app)
        let hero = app.otherElements["vitals.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 6), "heart hero never appeared")

        let idle = readout(probe)
        XCTAssertTrue(idle.contains(" · "), "idle readout should be time · value, got \(idle)")
        XCTAssertTrue(idle.contains("BPM"), "heart idle should name BPM, got \(idle)")

        let heroBefore = hero.value as? String ?? ""
        XCTAssertFalse(heroBefore.isEmpty, "heart hero has no accessibility value")

        dragProbe(probe, from: 0.88, to: 0.18)
        XCTAssertEqual(hero.value as? String, heroBefore,
                       "探点 must not rewrite the hero")
        XCTAssertEqual(readout(probe), idle,
                       "lift-off should restore the last sample in the window")

        let last = lastProbe(app, named: "vitals.probe")
        XCTAssertTrue(last.contains(" · "), "drag never named a sample, last=\(last)")
        XCTAssertNotEqual(last, idle,
                        "a drag across the field should leave a different sample than idle")
        XCTAssertGreaterThanOrEqual(probe.frame.height, 160,
                                     "plot field plus readout should be at least the 160pt field")
    }

    func testStressProbeUsesTheSameShell() {
        let app = launchDetail("vitals.stress")
        let probe = waitForProbe(app)
        let idle = readout(probe)
        XCTAssertTrue(idle.contains(" · "), "stress idle was \(idle)")
        dragProbe(probe, from: 0.8, to: 0.25)
        XCTAssertEqual(readout(probe), idle, "stress did not restore idle on lift")
        XCTAssertTrue(app.buttons["Back"].exists, "stress probe popped the page")
    }

    func testStepsHistogramNamesAVacantOrFilledHour() {
        let app = launchDetail("vitals.steps")
        let probe = waitForProbe(app)
        let idle = readout(probe)
        XCTAssertTrue(idle.contains(" · "), "steps idle was \(idle)")
        dragProbe(probe, from: 0.9, to: 0.2)
        XCTAssertEqual(readout(probe), idle)
        let last = lastProbe(app, named: "vitals.probe")
        XCTAssertTrue(last.contains(" · "), "steps drag last=\(last)")
    }

    func testDistanceClimbProbeKeepsACumulativeReadout() {
        let app = launchDetail("vitals.distance")
        let probe = waitForProbe(app)
        let idle = readout(probe)
        XCTAssertTrue(idle.contains(" · "), "distance idle was \(idle)")
        XCTAssertTrue(idle.contains("M") || idle.contains("KM"),
                      "climb idle should be metres or kilometres, got \(idle)")
        dragProbe(probe, from: 0.85, to: 0.2)
        XCTAssertEqual(readout(probe), idle)
        XCTAssertNotEqual(lastProbe(app, named: "vitals.probe"), "")
    }

    func testResponseProbeOpensOnSeededOpticalPoints() {
        let app = launchDetail("vitals.response")
        let probe = waitForProbe(app)
        XCTAssertTrue(readout(probe).contains(" · "))
        dragProbe(probe, from: 0.8, to: 0.3)
        XCTAssertTrue(app.buttons["Back"].exists)
    }

    func testResponseWeekOpensDailyBars() {
        let app = launchDetail("vitals.response", extra: ["NB_DEBUG_RESPONSE_RANGE": "WEEK"])
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 30), "response week never opened")
        XCTAssertTrue(app.buttons["range.WEEK"].waitForExistence(timeout: 6))
        let probe = app.otherElements["vitals.probe.response.days"]
        XCTAssertTrue(probe.waitForExistence(timeout: 20), "week daily bars never appeared")
        XCTAssertTrue(app.staticTexts["LAST 7 DAYS"].waitForExistence(timeout: 2))
        dragProbe(probe, from: 0.85, to: 0.2)
        XCTAssertTrue(app.buttons["Back"].exists)
    }

    func testResponseMonthOpensTheHeatGrid() {
        let app = launchDetail("vitals.response", extra: ["NB_DEBUG_RESPONSE_RANGE": "MONTH"])
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 30), "response month never opened")
        let probe = app.otherElements["vitals.probe.response.heat"]
        XCTAssertTrue(probe.waitForExistence(timeout: 20), "month heat never appeared")
        XCTAssertTrue(app.staticTexts["LAST 30 DAYS"].waitForExistence(timeout: 2))
        dragProbe(probe, from: 0.9, to: 0.15)
        XCTAssertTrue(app.buttons["Back"].exists)
    }

    func testSleepDayHasIndependentChartProbes() {
        let app = launchDetail("vitals.sleep")
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 30))
        let probes = app.otherElements.matching(identifier: "vitals.probe")
        let probe = probes.firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 20),
                      "sleep day should probe the hypnogram")
        XCTAssertGreaterThanOrEqual(probes.count, 3,
                      "sleep day should probe hypnogram, SpO2 and respiration independently")
        let idle = readout(probe)
        XCTAssertTrue(idle.contains(" · "), "hypnogram idle was \(idle)")
        XCTAssertNotNil(idle.range(of: #"\d{1,2}:\d{2} · "#, options: .regularExpression),
                        "hypnogram idle should name a clock, got \(idle)")
        dragProbe(probe, from: 0.7, to: 0.25)
        XCTAssertEqual(readout(probe), idle)
        XCTAssertEqual(app.otherElements["vitals.hero"].label, "OVERNIGHT STAGING")
    }

    func testSleepMonthProbeNamesAMissingNight() {
        let app = launchDetail("vitals.sleep", extra: ["NB_DEBUG_SLEEP_RANGE": "MONTH"])
        let probe = app.otherElements["vitals.probe.score"]
        XCTAssertTrue(probe.waitForExistence(timeout: 30), "month score bars never appeared")
        let idle = readout(probe)
        XCTAssertTrue(idle.contains(" · "), "month idle was \(idle)")
        dragProbe(probe, from: 0.92, to: 0.12)
        XCTAssertEqual(readout(probe), idle)
        let last = lastProbe(app, named: "vitals.probe.score")
        XCTAssertTrue(last.contains(" · "), "month drag last=\(last)")
        XCTAssertTrue(last.contains("——") || last.range(of: #"[0-9]+$"#, options: .regularExpression) != nil,
                      "month probe should name a score or a vacant night, got \(last)")
    }

    func testActiveEnergyHasNoProbeOnTheEmptyCard() {
        let app = launchDetail("vitals.active")
        XCTAssertTrue(app.staticTexts["ACCUMULATED"].waitForExistence(timeout: 30),
                      "active energy board never appeared")
        XCTAssertTrue(app.staticTexts["PER HOUR"].exists)
        XCTAssertFalse(app.otherElements["vitals.probe"].exists,
                       "the active board must not grow a 探点")
        XCTAssertTrue(app.otherElements["vitals.hero"].exists)
    }

    private func launchDetail(_ route: String, extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = route
        for (key, value) in extra { app.launchEnvironment[key] = value }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func waitForProbe(_ app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 30), "detail never opened")
        let probe = app.otherElements.matching(identifier: "vitals.probe").firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 20), "chart probe never appeared")
        return probe
    }

    private func readout(_ probe: XCUIElement) -> String {
        (probe.value as? String) ?? ""
    }

    private func lastProbe(_ app: XCUIApplication, named identifier: String) -> String {
        let last = app.otherElements["\(identifier).last"]
        if last.waitForExistence(timeout: 2) {
            return (last.value as? String) ?? last.label
        }
        let text = app.staticTexts["\(identifier).last"]
        return (text.value as? String) ?? text.label
    }

    private func dragProbe(_ probe: XCUIElement, from: CGFloat, to: CGFloat) {
        let start = probe.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.72))
        let end = probe.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.72))
        start.press(forDuration: 0.12, thenDragTo: end,
                     withVelocity: XCUIGestureVelocity(180), thenHoldForDuration: 0.05)
    }
}
