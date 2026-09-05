import XCTest

final class FastingActionTests: XCTestCase {
    func testRecordedFoodRequiresConfirmationAndCancelPreservesIt() {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "fuel"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["Back"].value as? String, "CALORIES")
        let action = app.buttons["fasting-action"]
        for _ in 0..<10 where !action.isHittable { app.swipeUp() }
        XCTAssertTrue(action.isHittable)
        action.tap()
        XCTAssertTrue(app.buttons["fasting-confirm"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["fasting-confirm"].exists)
        XCTAssertTrue(action.isEnabled)
        action.tap()
        XCTAssertTrue(app.buttons["fasting-confirm"].waitForExistence(timeout: 5),
                      "cancel must leave existing food intact and require confirmation again")
    }
}
