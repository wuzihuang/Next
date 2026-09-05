import XCTest

/// Real account, consent and Veepoo transport. Never use the fake-session launch flag.
final class SportSessionStressTests: XCTestCase {
    private let app = XCUIApplication()
    private var restoreBluetooth = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires a paired physical iPhone and worn HOOP")
        #endif
        app.launch()
        try home()
    }

    override func tearDownWithError() throws {
        if restoreBluetooth {
            let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
            settings.activate()
            let radio = bluetoothRadio(in: settings)
            if radio.waitForExistence(timeout: 5), (radio.value as? String) == "0" { radio.tap() }
            restoreBluetooth = false
            app.activate()
        }
        let stop = app.descendants(matching: .any)["session-stop"].firstMatch
        if stop.exists && !stop.frame.isEmpty && stop.isEnabled {
            stop.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).press(forDuration: 1.3)
            _ = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Band · battery ")).firstMatch.waitForExistence(timeout: 15)
        }
    }

    func testRealSportSessionSmoke() throws {
        try start(mode: 0)
        try freshHeart(marker: "smoke")
        try stop(marker: "smoke")
    }

    func testSportMetricContinuity() throws {
        try recordMetricContinuity(mode: 0)
    }

    func testSportMetricsAcrossModes() throws {
        for mode in [2, 8] { try recordMetricContinuity(mode: mode) }
    }

    private func recordMetricContinuity(mode: Int) throws {
        try start(mode: mode)
        try freshHeart(marker: "metrics-first-heart")
        let heart = app.descendants(matching: .any)["session-heart-rate"].firstMatch
        let energy = app.descendants(matching: .any)["session-calories"].firstMatch
        var readings: [[String: String]] = []
        for _ in 0..<20 {
            readings.append(["time": String(Date().timeIntervalSince1970),
                             "heart": heart.value as? String ?? "missing",
                             "kcal": energy.value as? String ?? "missing"])
            Thread.sleep(forTimeInterval: 2)
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readings),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "sport-metric-readings-\(mode)"; attachment.lifetime = .keepAlways; add(attachment)
        try stop(marker: "metric-continuity")
        for pair in zip(readings, readings.dropFirst()) {
            if let previous = Double(pair.0["kcal"] ?? ""), let next = Double(pair.1["kcal"] ?? "") {
                XCTAssertLessThan(next - previous, 50, "Reported calorie count jumped by 50 or more between adjacent reads")
            }
        }
    }

    func testRepeatedStartStopAcrossLifecycleScenarios() throws {
        for cycle in 1...10 {
            print("SPORT cycle=\(cycle) BEGIN epoch=\(Date().timeIntervalSince1970)")
            if cycle == 1 || cycle == 6 {
                app.terminate()
                app.launch()
                try home()
            }
            if cycle.isMultiple(of: 2) {
                XCUIDevice.shared.press(.home)
                Thread.sleep(forTimeInterval: 3)
                app.activate()
                try home()
            }
            // Enter/leave the picker repeatedly before opening a real session.
            if cycle.isMultiple(of: 3) {
                for _ in 0..<3 {
                    try picker()
                    let back = app.buttons.matching(NSPredicate(format: "label IN %@", ["Back", "返回"])).firstMatch
                    XCTAssertTrue(back.waitForExistence(timeout: 5))
                    back.tap()
                    try home()
                }
            }
            try start(mode: cycle.isMultiple(of: 2) ? 2 : 0)
            try freshHeart(marker: "cycle-\(cycle)-foreground")
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
            Thread.sleep(forTimeInterval: cycle.isMultiple(of: 5) ? 30 : 5)
            app.activate()
            try freshHeart(marker: "cycle-\(cycle)-return")
            try stop(marker: "cycle-\(cycle)")
            print("SPORT cycle=\(cycle) PASS")
        }
    }

    func testStopAfterForegroundReturn() throws {
        try start(mode: 0)
        try freshHeart(marker: "stop-return-before-background")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        try freshHeart(marker: "stop-return-after-background")
        try stop(marker: "stop-after-return")
    }

    func testSustainedBackgroundSport() throws {
        try start(mode: 0)
        try freshHeart(marker: "sustained-background-before")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        print("SPORT SUSTAINED_BACKGROUND_BEGIN epoch=\(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 120)
        print("SPORT SUSTAINED_BACKGROUND_END epoch=\(Date().timeIntervalSince1970)")
        app.activate()
        try freshHeart(marker: "sustained-background-return")
        try stop(marker: "sustained-background")
    }

    func testStopRejectsShortTapAndSwipe() throws {
        try start(mode: 0)
        try freshHeart(marker: "hold-safety-before")
        let control = app.descendants(matching: .any)["session-stop"].firstMatch
        try requireStop(control, name: "Stop control")
        let center = control.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
        center.tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(control.exists, "Short tap must not stop the workout")
        center.press(forDuration: 0.1, thenDragTo: control.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: -2)))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(control.exists, "Swipe must not stop the workout")
        try stop(marker: "hold-safety-valid-hold")
    }

    func testImmediateStopAndSameModeRestart() throws {
        for cycle in 1...3 {
            try start(mode: 0)
            if cycle == 3 { try freshHeart(marker: "rapid-reopen-final") }
            try stop(marker: "rapid-reopen-\(cycle)")
        }
    }

    func testRelaunchWithSportStillRunning() throws {
        try start(mode: 0)
        try freshHeart(marker: "before-process-restart")
        app.terminate()
        app.launch()
        try home()
        try start(mode: 0)
        try freshHeart(marker: "after-process-restart")
        try stop(marker: "after-process-restart")
    }

    func testSportRecoversBluetoothDropout() throws {
        try start(mode: 0)
        try freshHeart(marker: "before-bluetooth-dropout")
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let bluetooth = settings.buttons["com.apple.settings.bluetooth"]
        for _ in 0..<5 {
            if bluetooth.exists { break }
            let back = settings.navigationBars.buttons.firstMatch
            guard back.exists && back.isHittable else { break }
            back.tap()
        }
        guard bluetooth.waitForExistence(timeout: 10) else {
            let tree = XCTAttachment(string: settings.debugDescription)
            tree.name = "Bluetooth settings discovery"; tree.lifetime = .keepAlways; add(tree)
            app.activate()
            XCTFail("Cannot locate Bluetooth settings; dropout not executed")
            return
        }
        bluetooth.tap()
        let radio = bluetoothRadio(in: settings)
        try require(radio, name: "Bluetooth radio switch")
        XCTAssertEqual(radio.value as? String, "1", "Expected Bluetooth enabled before dropout")
        // tearDown restores the radio on failure. After ON is verified, do not
        // query the background Settings app again: its AX request can time out.
        restoreBluetooth = true
        print("SPORT BLUETOOTH_OFF epoch=\(Date().timeIntervalSince1970)")
        let switchTree = XCTAttachment(string: settings.debugDescription)
        switchTree.name = "Bluetooth controls before toggle"; switchTree.lifetime = .keepAlways; add(switchTree)
        radio.tap()
        try requireRadio(radio, value: "0")
        Thread.sleep(forTimeInterval: 4)
        radio.tap()
        try requireRadio(radio, value: "1")
        restoreBluetooth = false
        print("SPORT BLUETOOTH_ON epoch=\(Date().timeIntervalSince1970)")
        app.activate()
        // Discard the pre-dropout readout's 15-second freshness window.
        Thread.sleep(forTimeInterval: 16)
        try freshHeart(marker: "after-bluetooth-recovery")
        try stop(marker: "after-bluetooth-recovery")
    }

    private func bluetoothRadio(in settings: XCUIApplication) -> XCUIElement {
        let row = settings.switches.firstMatch
        let nativeSwitch = row.switches.firstMatch
        return nativeSwitch.exists ? nativeSwitch : row
    }

    private func requireRadio(_ radio: XCUIElement, value: String) throws {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: radio)
        let result = XCTWaiter.wait(for: [changed], timeout: 5)
        guard result == .completed else {
            XCTFail("Bluetooth radio did not reach state \(value)")
            throw Failure.missing("Bluetooth radio state")
        }
    }

    private func home() throws {
        let band = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Band · battery ")).firstMatch
        try require(band, timeout: 60, name: "Signed-in real home")
    }

    private func picker() throws {
        let orb = app.buttons.matching(NSPredicate(format: "label IN %@", ["Camera", "相机"])).firstMatch
        // PressHold uses a native hit-test overlay; its accessibility proxy is not
        // reported hittable by XCTest. Drive a real touch at the observed proxy frame.
        XCTAssertTrue(orb.waitForExistence(timeout: 15), "Plus menu proxy missing")
        orb.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "Start a session", "开始一场")).firstMatch
        try require(entry, timeout: 60, name: "Start a session")
        entry.tap()
        try require(app.buttons["sport-mode-0"], timeout: 60, name: "Sport picker")
    }

    private func start(mode: Int) throws {
        try picker()
        app.buttons["sport-mode-\(mode)"].tap()
        try requireStop(app.descendants(matching: .any)["session-stop"].firstMatch,
                    timeout: 40, name: "Band acknowledged session start")
    }

    // A visible live readout is an UI check. Correlate device receipt logs for new
    // samples, especially returns shorter than the 15-second freshness window.
    private func freshHeart(marker: String) throws {
        let heart = app.descendants(matching: .any)["session-heart-rate"].firstMatch
        let predicate = NSPredicate { _, _ in
            guard heart.exists, let value = heart.value as? String, let bpm = Int(value) else { return false }
            return bpm > 0
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: heart)], timeout: 60)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = marker
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(result, .completed, "\(marker): no fresh sport heart rate")
        guard result == .completed else { throw Failure.missing(marker) }
        print("SPORT \(marker) LIVE_UI_READOUT PRESENT epoch=\(Date().timeIntervalSince1970)")
    }

    private func stop(marker: String) throws {
        let stop = app.descendants(matching: .any)["session-stop"].firstMatch
        try requireStop(stop, name: "Stop control")
        stop.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).press(forDuration: 1.3)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: stop)
        let result = XCTWaiter.wait(for: [gone], timeout: 30)
        XCTAssertEqual(result, .completed, "\(marker): session did not stop")
        guard result == .completed else { throw Failure.missing("stop") }
        try home()
    }

    private func requireStop(_ element: XCUIElement, timeout: TimeInterval = 15, name: String) throws {
        // The native hold recognizer overlays this accessibility proxy.
        // XCTest reports this custom accessibility proxy enabled even while its
        // native overlay is disabled. Wait for the visible opening status to finish,
        // then stop immediately; do not wait for a heart-rate sample or add a delay.
        let opening = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
            "OPENING ", "正在手环上打开 ")).firstMatch
        let predicate = NSPredicate { _, _ in
            element.exists && element.isEnabled && !element.frame.isEmpty
                && self.app.frame.intersects(element.frame) && !opening.exists
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
        guard result == .completed else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = name; tree.lifetime = .keepAlways; add(tree)
            XCTFail(name)
            throw Failure.missing(name)
        }
    }

    private func require(_ element: XCUIElement, timeout: TimeInterval = 15, name: String) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true AND enabled == true"), object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        guard result == .completed else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = name; tree.lifetime = .keepAlways; add(tree)
            XCTFail(name)
            throw Failure.missing(name)
        }
    }
    private enum Failure: Error { case missing(String) }
}
