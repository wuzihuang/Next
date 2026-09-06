import XCTest

/// Returning users must see a changed data-consent screen instead of a silent BLE gate.
final class ConsentReconnectTests: XCTestCase {
    func testOldGrantPresentsConsentAndDeclineReturnsToDevice() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Consent fixtures are simulator-only; never change a real user's decision")
        #endif
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "device"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        // NSArgumentDomain is process-local, leaving persisted consent unchanged.
        app.launchArguments = ["-nb.consent", "{version = 1.2.0; choice = granted;}",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["What HOOP collects"].waitForExistence(timeout: 15),
                      "An obsolete grant must present its replacement before BLE readiness")
        app.buttons["consent.back"].tap()
        XCTAssertTrue(app.buttons["Sync now"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["What HOOP collects"].exists,
                       "Declining must return to the app without repeatedly reopening consent")
    }
}
