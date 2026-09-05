import XCTest

/// Run on a paired phone with -only-testing:NextBodyUITests/BandConnectionStressTests.
/// Requires an unlocked, signed-in physical iPhone and its paired HOOP nearby.
/// Uses the existing account, consent, clock, and real Bluetooth transport unchanged.
final class BandConnectionStressTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires a physical iPhone and its paired HOOP")
        #endif
    }

    /// Captures real values for SDK/local-database reconciliation; never injects fixture data.
    func testRealBandRepeatedSyncDataAudit() throws {
        let app = XCUIApplication()
        app.launch()
        try requireHome(app)
        captureAudit(app, marker: "baseline-home")
        bandEntry(app).tap()
        try requireDetail(app, titles: ["DEVICE", "设备"])
        let connected = app.staticTexts.matching(
            NSPredicate(format: "label IN %@", ["CONNECTED", "已连接"])).firstMatch
        try require(connected, "Connected real band", timeout: 60)

        for iteration in 1...3 {
            let sync = app.buttons.matching(
                NSPredicate(format: "label IN %@", ["Sync now", "立即同步"])).firstMatch
            try require(sync, "Sync now")
            try waitForAuditState(sync, predicate: "enabled == true", timeout: 180,
                                  app: app, marker: "sync-\(iteration)-ready")
            print("DATA AUDIT sync-\(iteration) BEGIN \(Date())")
            sync.tap()
            // Observe the transition, so the idle state from before the tap cannot pass.
            try waitForAuditState(sync, predicate: "enabled == false AND value != ''", timeout: 15,
                                  app: app, marker: "sync-\(iteration)-started")
            try waitForAuditState(sync, predicate: "enabled == true AND value == ''", timeout: 300,
                                  app: app, marker: "sync-\(iteration)-completed")
            captureAudit(app, marker: "sync-\(iteration)-device")
            print("DATA AUDIT sync-\(iteration) COMPLETE \(Date())")
        }
        back(app).tap()
        try requireHome(app)
        try captureVitalsAudit(app, phase: "after-sync")

        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launch()
        try requireHome(app)
        captureAudit(app, marker: "relaunch-home")
        try captureVitalsAudit(app, phase: "relaunch")
        print("DATA AUDIT COMPLETE: 3 syncs and all 8 vitals panels before/after relaunch")
    }

    private func captureVitalsAudit(_ app: XCUIApplication, phase: String) throws {
        let cards = [("SLEEP", "睡眠"), ("HEART", "心率"), ("RESPONSE", "RESPONSE"),
                     ("STRESS", "压力"), ("TEMP", "体温"), ("STEPS", "步数"),
                     ("DISTANCE", "距离"), ("ACTIVE", "活动")]
        try turnToAuditVitals(app)
        captureAudit(app, marker: "\(phase)-vitals-overview")
        print("DATA AUDIT respiration: no dedicated respiration card in current 8-panel UI; RESPONSE is meal response")
        for (english, chinese) in cards {
            let card = app.buttons.matching(NSPredicate(
                format: "label BEGINSWITH %@ OR label BEGINSWITH %@", english, chinese)).firstMatch
            try require(card, "\(english) card")
            card.tap()
            try require(back(app), "\(english) detail back")
            captureAudit(app, marker: "\(phase)-\(english)-top")
            // Preserve lower tiles (night HRV/oxygen, summaries) as well as the hero.
            for page in 1...2 {
                app.swipeUp()
                captureAudit(app, marker: "\(phase)-\(english)-scroll-\(page)")
            }
            back(app).tap()
            try require(card, "\(english) returned card")
        }
    }

    private func turnToAuditVitals(_ app: XCUIApplication) throws {
        let marker = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "TEMP", "体温")).firstMatch
        let window = app.windows.firstMatch
        for _ in 0..<6 {
            if marker.exists && marker.isHittable {
                // A visible card can still be moving while the page turn settles.
                let still = NSPredicate { _, _ in
                    let previous = marker.frame
                    Thread.sleep(forTimeInterval: 0.25)
                    return marker.isHittable && marker.frame == previous
                }
                let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: still, object: marker)], timeout: 5)
                if result == .completed { return }
            }
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.735, dy: 0.79))
                .press(forDuration: 0.05,
                       thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.79)),
                       withVelocity: XCUIGestureVelocity(1000), thenHoldForDuration: 0)
        }
        captureAudit(app, marker: "vitals-navigation-failed")
        XCTFail("Could not reach real vitals page")
        throw StressFailure.missing("vitals page")
    }

    private func waitForAuditState(_ element: XCUIElement, predicate: String, timeout: TimeInterval,
                                   app: XCUIApplication, marker: String) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            captureAudit(app, marker: "\(marker)-timeout")
            XCTFail("\(marker): state did not reach \(predicate) within \(timeout)s")
            throw StressFailure.missing(marker)
        }
    }

    private func captureAudit(_ app: XCUIApplication, marker: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "data-audit-\(marker)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: "Captured: \(Date())\n\(app.debugDescription)")
        tree.name = "data-audit-\(marker)-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }

    func testRealBandSurvivesRelaunchBackgroundAndPageNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        try requireHome(app)
        try verifyConnectionAndReturnHome(app, marker: "baseline")

        for iteration in 1...5 {
            print("STRESS relaunch \(iteration)/5 BEGIN")
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
            app.launch()
            try requireHome(app)
            try verifyConnectionAndReturnHome(app, marker: "relaunch-\(iteration)")
        }

        for iteration in 1...10 {
            print("STRESS background \(iteration)/10 BEGIN")
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
            // Exercise both quick returns and longer suspended/background intervals.
            Thread.sleep(forTimeInterval: iteration.isMultiple(of: 5) ? 15 : 2)
            app.activate()
            try requireHome(app)
            try verifyConnectionAndReturnHome(app, marker: "background-\(iteration)")
        }

        for iteration in 1...20 {
            print("STRESS navigation \(iteration)/20 BEGIN")
            try verifyConnectionAndReturnHome(app, marker: "navigation-\(iteration)")
            let profile = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Profile · ")).firstMatch
            try require(profile, "Home profile entry")
            profile.tap()
            try requireDetail(app, titles: ["ME", "我"])
            XCTAssertEqual(app.state, .runningForeground)
            back(app).tap()
            try requireHome(app)
            print("STRESS navigation-\(iteration) PROFILE_RETURN PASS")
        }
        try verifyConnectionAndReturnHome(app, marker: "final")
        print("STRESS COMPLETE: 5 relaunch, 10 background, 20 device/profile round trips")
    }

    private func verifyConnectionAndReturnHome(_ app: XCUIApplication, marker: String) throws {
        let started = Date()
        print("STRESS \(marker) CONNECTION_CHECK BEGIN \(started)")
        try requireHome(app)
        bandEntry(app).tap()
        try requireDetail(app, titles: ["DEVICE", "设备"])
        // This is DeviceView's live data.band.connected status, not cached battery text.
        let connected = app.staticTexts.matching(
            NSPredicate(format: "label IN %@", ["CONNECTED", "已连接"])).firstMatch
        let ready = connected.waitForExistence(timeout: 60)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(marker)-\(ready ? "connected" : "connection-failed")"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        guard ready else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "\(marker)-failed-accessibility-tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("\(marker): real band did not report CONNECTED within 60 seconds")
            throw StressFailure.missing("CONNECTED")
        }
        XCTAssertEqual(app.state, .runningForeground)
        print("STRESS \(marker) CONNECTED PASS elapsed=\(Date().timeIntervalSince(started))s")
        back(app).tap()
        try requireHome(app)
    }

    private func requireHome(_ app: XCUIApplication) throws {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        try require(bandEntry(app), "Real signed-in home", timeout: 45)
        XCTAssertFalse(back(app).exists, "Expected home, but a detail page is still open")
    }

    private func requireDetail(_ app: XCUIApplication, titles: [String]) throws {
        let chevron = back(app)
        try require(chevron, "Detail back button")
        let expected = NSPredicate(format: "value IN %@", titles)
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: expected, object: chevron)], timeout: 10)
        XCTAssertEqual(result, .completed, "Expected detail title \(titles), got \(String(describing: chevron.value))")
        guard result == .completed else { throw StressFailure.missing("detail \(titles)") }
    }

    private func require(_ element: XCUIElement, _ name: String, timeout: TimeInterval = 15) throws {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        let result = XCTWaiter.wait(for: [ready], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(name) did not become visible and tappable")
        guard result == .completed else { throw StressFailure.missing(name) }
    }

    private func bandEntry(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Band · battery ")).firstMatch
    }

    private func back(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Back", "返回"])).firstMatch
    }

    private enum StressFailure: Error {
        case missing(String)
    }
}
