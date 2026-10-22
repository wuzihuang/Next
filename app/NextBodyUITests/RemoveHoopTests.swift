import XCTest

final class RemoveHoopTests: XCTestCase {
    func testRemovalRequiresSelectingOneBandAndFailureKeepsBoth() {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "device"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_SECOND_HOOP"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remove = app.buttons["device.removeHoop"]
        XCTAssertTrue(remove.waitForExistence(timeout: 30))
        for _ in 0..<6 where !remove.isHittable { app.swipeUp() }
        remove.tap()
        XCTAssertTrue(app.buttons["SELECT A NEXTBODY"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["SELECT A NEXTBODY"].isEnabled)
        app.buttons["NEXTBODY A"].tap()
        XCTAssertTrue(app.buttons["REMOVE NEXTBODY A"].exists)
        app.buttons["NEXTBODY B"].tap()
        XCTAssertTrue(app.buttons["REMOVE NEXTBODY B"].exists)
        // The seeded band has no server binding ID. A failed removal must not dismiss
        // the sheet or clear either local slot.
        app.buttons["REMOVE NEXTBODY B"].tap()
        XCTAssertTrue(app.staticTexts["The pairing details are not loaded yet. Reopen Device and try again."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["NEXTBODY A"].exists)
        XCTAssertTrue(app.buttons["NEXTBODY B ✓"].exists)
        XCTAssertTrue(app.buttons["Keep it paired"].isEnabled)
    }
}
