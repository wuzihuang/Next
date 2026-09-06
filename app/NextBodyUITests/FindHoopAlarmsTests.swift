import XCTest

/// Paper 12X / 12Y · device home is 04 ACTION TILES; FIND is LED with START then STOP;
/// ALARMS is SWITCH with no hairline above the first clock and no rocker on Add.
final class FindHoopAlarmsTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testActionTilesSitUnderTheLimeSlab() {
        let app = launchDevice()
        XCTAssertTrue(app.buttons["device.findHoop"].waitForExistence(timeout: 30),
                      "Find HOOP brick should sit on the device page")
        XCTAssertTrue(app.buttons["device.alarms"].exists)
        XCTAssertTrue(app.staticTexts["PING"].exists)
        XCTAssertTrue(app.staticTexts["Find HOOP"].exists)
        XCTAssertTrue(app.staticTexts["Alarms"].exists)
        XCTAssertTrue(app.staticTexts["WORN"].exists)
        XCTAssertTrue(app.staticTexts["SYNC"].exists || app.buttons["Sync now"].exists)
        XCTAssertTrue(app.otherElements["device.battery"].waitForExistence(timeout: 4)
                      || app.staticTexts["POWER"].exists,
                      "the charge ring stays on the device page")
        XCTAssertTrue(app.buttons["device.trend"].exists || app.staticTexts["TREND"].exists,
                      "TREND is the door back into the chart")
    }

    func testFindOpensReadyThenStartBecomesStop() {
        let app = launchDevice()
        let find = app.buttons["device.findHoop"]
        XCTAssertTrue(find.waitForExistence(timeout: 30))
        find.tap()

        XCTAssertTrue(app.staticTexts["READY"].waitForExistence(timeout: 6)
                        || app.staticTexts["READY · LIVE"].waitForExistence(timeout: 2),
                      "FIND opens READY, not already ringing")
        let start = app.buttons["find.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 4), "START must be the first action")
        XCTAssertFalse(app.buttons["find.stop"].exists)

        start.tap()
        XCTAssertTrue(app.buttons["find.stop"].waitForExistence(timeout: 6),
                      "STOP only appears after START")
        XCTAssertFalse(app.buttons["find.start"].exists)
        XCTAssertTrue(app.otherElements["find.lamp.NEAR"].exists
                        || app.staticTexts["NEAR"].exists)
        XCTAssertTrue(app.staticTexts["dBm"].exists, "KLF-0 hero keeps the dBm unit")

        app.buttons["find.stop"].tap()
        XCTAssertTrue(app.buttons["find.start"].waitForExistence(timeout: 1),
                      "STOP must return READY without waiting on the band")
    }

    func testAlarmsFirstRowHasNoTopHairlineAndAddHasNoRocker() {
        let app = launchDevice(sheet: "bandAlarms")
        XCTAssertTrue(app.buttons["alarms.add"].waitForExistence(timeout: 30),
                      "Add an alarm is always on the SWITCH list")
        XCTAssertTrue(app.staticTexts["07:30"].waitForExistence(timeout: 8)
                        || app.staticTexts["7:30"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.otherElements["alarms.hairline.0"].exists,
                       "no hairline above the first clock")
        XCTAssertFalse(app.switches["alarms.add.switch"].exists,
                       "Add an alarm has no rocker")
        XCTAssertTrue(app.switches["alarms.switch.1"].exists
                        || app.switches.firstMatch.exists,
                      "a repeating alarm keeps its rocker")
    }

    private func launchDevice(sheet: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "device"
        if let sheet {
            app.launchEnvironment["NB_DEBUG_DEVICE_SHEET"] = sheet
        }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }
}
