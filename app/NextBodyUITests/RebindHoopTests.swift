import XCTest

final class RebindHoopTests: XCTestCase {
    func testRemovedBCanBeDiscoveredAndRetriedWithoutRemovingA() { rebind(slot: "B") }
    func testRemovedACanBeDiscoveredAndRetriedWithoutRenamingB() { rebind(slot: "A") }
    func testRemovedBCanBeAddedBackSuccessfully() { rebind(slot: "B", saved: true) }
    func testRemovedACanBeAddedBackSuccessfully() { rebind(slot: "A", saved: true) }

    private func rebind(slot: String, saved: Bool = false) {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "device"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_DEVICE_SHEET"] = "activateSecond"
        app.launchEnvironment["NB_DEBUG_RELEASED_SLOT"] = slot
        app.launchEnvironment["NB_DEBUG_ACTIVATION_SAVE"] = saved ? "success" : "failure"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let pair = app.buttons["PAIR AS \(slot)"]
        XCTAssertTrue(pair.waitForExistence(timeout: 30))
        pair.tap()
        if saved {
            XCTAssertTrue(app.buttons["DONE · STILL WEARING \(slot == "A" ? "B" : "A")"].waitForExistence(timeout: 30))
            XCTAssertTrue(app.buttons["activate.wearingNow"].exists)
            return
        }
        // Real mock BLE stages execute; registration is controlled at the repository
        // boundary. Failure must be retryable, never false success or a frozen 0%.
        let failure = app.staticTexts.matching(NSPredicate(format:
            "label CONTAINS[c] %@ AND label CONTAINS %@", "Pairing could not be saved.", "Your other HOOP remains paired.")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["activate.wearingNow"].exists)
        app.buttons["Try again"].tap()
        XCTAssertTrue(pair.waitForExistence(timeout: 30))
    }
}
