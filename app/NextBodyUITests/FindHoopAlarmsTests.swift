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
        XCTAssertTrue(app.buttons["device.trend"].waitForExistence(timeout: 4),
                      "TREND lead corridor should sit on the lime slab")
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
        XCTAssertFalse(app.staticTexts["2 / ?"].exists,
                       "the face never prints a running capacity")
    }

    /// The editor offers one way to agree and one way to walk away. `DONE` used to sit
    /// next to `SAVE` while meaning "discard", which is the opposite of what it says.
    func testEditorHasSaveAndCancelAndNeverDone() {
        let app = launchDevice(sheet: "bandAlarms")
        XCTAssertTrue(app.buttons["alarms.row.0"].waitForExistence(timeout: 30))
        app.buttons["alarms.row.0"].tap()

        XCTAssertTrue(app.buttons["alarms.save"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["alarms.cancel"].exists, "Cancel is the only way out that writes nothing")
        XCTAssertFalse(app.staticTexts["DONE"].exists, "DONE read as a second kind of Save")
        XCTAssertTrue(app.staticTexts["EDIT ALARM"].exists)

        app.buttons["alarms.cancel"].tap()
        XCTAssertTrue(app.buttons["alarms.add"].waitForExistence(timeout: 4),
                      "Cancel returns to the list")
        XCTAssertTrue(app.staticTexts["07:30"].exists, "and changes nothing")
    }

    /// Apple's Clock deletes an alarm with a left swipe, so this one does too.
    func testSwipingAClockLeftDeletesIt() {
        let app = launchDevice(sheet: "bandAlarms")
        let first = app.buttons["alarms.row.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["07:30"].exists)

        first.swipeLeft()
        let trash = app.buttons["DELETE"]
        XCTAssertTrue(trash.waitForExistence(timeout: 4), "a left swipe reveals DELETE")
        trash.tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["07:30"], handler: nil)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.staticTexts["08:45"].exists, "only the swiped clock goes")
    }

    /// A HOOP that has never been given an alarm gets one key in the middle of the face —
    /// no list, no eyebrow count, no rocker to misread.
    func testAnEmptyHoopIsOneCentredKey() {
        let app = launchDevice(sheet: "bandAlarms", edge: "noalarms")
        XCTAssertTrue(app.buttons["alarms.add"].waitForExistence(timeout: 30),
                      "the empty SWITCH face is the Add key")
        XCTAssertTrue(app.staticTexts["NO ALARMS YET"].exists)
        XCTAssertFalse(app.staticTexts["— / ?"].exists)
        XCTAssertFalse(app.staticTexts["0 / ?"].exists)
        XCTAssertEqual(app.switches.count, 0, "nothing to switch on an empty HOOP")
    }

    private func launchDevice(sheet: String? = nil, edge: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "device"
        if let sheet {
            app.launchEnvironment["NB_DEBUG_DEVICE_SHEET"] = sheet
        }
        if let edge {
            app.launchEnvironment["NB_DEBUG_EDGE"] = edge
        }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }
}
