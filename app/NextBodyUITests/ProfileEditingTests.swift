import XCTest

final class ProfileEditingTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testBodyMetricsAllowsManualWeightAndBodyFieldsWithoutHealth() {
        let app = launchProfile()
        openBodyMetrics(app)
        XCTAssertTrue(app.buttons["profile.height"].exists)
        XCTAssertTrue(app.datePickers["profile.birthday"].exists)
        XCTAssertTrue(app.segmentedControls["profile.sex"].exists)
        replaceWeight(in: app, with: "83.2")
        app.buttons["profile.save"].tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !app.buttons["profile.save"].exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 15), .completed)
        openBodyMetrics(app)
        XCTAssertEqual(app.textFields["profile.weight"].value as? String, "83.2")
    }

    func testInvalidManualWeightDoesNotCloseOrSave() {
        let app = launchProfile()
        openBodyMetrics(app)
        replaceWeight(in: app, with: "0")
        app.buttons["profile.save"].tap()
        XCTAssertTrue(app.staticTexts["Weight is out of range."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile.save"].exists)
    }

    private func replaceWeight(in app: XCUIApplication, with value: String) {
        let field = app.textFields["profile.weight"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        for _ in 0..<4 where !field.isHittable { app.swipeUp() }
        field.tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + value)
    }

    private func openBodyMetrics(_ app: XCUIApplication) {
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "BODY METRICS")).firstMatch
        for _ in 0..<8 {
            if entry.exists && entry.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.buttons["profile.save"].waitForExistence(timeout: 10))
    }

    private func launchProfile() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["NB_DEBUG_STAGE": "root", "NB_DEBUG_ROUTE": "profile",
                                 "NB_DEBUG_CONSENT": "granted", "NB_DEBUG_LANG": "en"]
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        return app
    }
}
