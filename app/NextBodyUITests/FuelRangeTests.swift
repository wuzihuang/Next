import XCTest

/// Paper 09H · CALORIES is the clock plus DAY / WEEK / MONTH. Month is four
/// weeks spoken as a typical day, not a 70k total.
final class FuelRangeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDayIsTheLandingRange() {
        let app = launchFuel()
        XCTAssertTrue(app.staticTexts["THE DAY SO FAR"].waitForExistence(timeout: 30),
                      "calories should open on today's clock")
        XCTAssertTrue(app.buttons["range.DAY"].exists)
        XCTAssertTrue(app.buttons["range.WEEK"].exists)
        XCTAssertTrue(app.buttons["range.MONTH"].exists)
        XCTAssertTrue(app.staticTexts["FOOD"].exists)
        XCTAssertFalse(app.staticTexts["A TYPICAL DAY"].exists)
    }

    func testWeekAndMonthSwapThePeriodWord() {
        let week = launchFuel(range: "WEEK")
        XCTAssertTrue(week.staticTexts["7 DAYS"].waitForExistence(timeout: 30),
                      "WEEK should open the last 7 user days")
        XCTAssertTrue(week.staticTexts["THIS WEEK"].waitForExistence(timeout: 6))
        XCTAssertFalse(week.staticTexts["THE DAY SO FAR"].exists)
        XCTAssertFalse(week.staticTexts["A TYPICAL DAY"].exists)

        let month = launchFuel(range: "MONTH")
        XCTAssertTrue(month.staticTexts["4 WEEKS"].waitForExistence(timeout: 30),
                      "MONTH should open the last 4 weeks")
        XCTAssertTrue(month.staticTexts["A TYPICAL DAY"].waitForExistence(timeout: 6))
        XCTAssertTrue(month.staticTexts["PER DAY"].exists)
        XCTAssertFalse(month.staticTexts["THE DAY SO FAR"].exists)
    }

    func testLogAMealIsAnEmberStateThatOpensAPlate() {
        let app = launchFuel()
        let log = app.buttons["log-a-meal"]
        XCTAssertTrue(log.waitForExistence(timeout: 30),
                      "DAY should show the ember LOG A MEAL state")
        log.tap()
        XCTAssertTrue(app.otherElements["fuel.plate"].waitForExistence(timeout: 6)
                      || app.staticTexts["Log a meal"].waitForExistence(timeout: 6),
                      "tapping LOG A MEAL should raise the plate")
        XCTAssertTrue(app.otherElements["fuel.plate.dim"].exists
                      || app.otherElements["fuel.plate"].exists)
    }

    func testDebugRangeOpensOnMonth() {
        let app = launchFuel(range: "MONTH")
        XCTAssertTrue(app.staticTexts["4 WEEKS"].waitForExistence(timeout: 30),
                      "NB_DEBUG_FUEL_RANGE should land on that window")
        XCTAssertTrue(app.staticTexts["A TYPICAL DAY"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["PER DAY"].exists)
    }

    func testManualMealRemainsVisibleInSeedMode() {
        let app = launchFuel(manualPlate: true)
        let plate = app.otherElements["fuel.plate"]
        XCTAssertTrue(plate.waitForExistence(timeout: 30))
        // SwiftUI propagates the plate identifier to its accessible sibling fields.
        let fields = app.textFields.matching(identifier: "fuel.plate")
        let name = fields.element(boundBy: 0)
        let calories = fields.element(boundBy: 1)
        XCTAssertTrue(name.waitForExistence(timeout: 6))
        name.tap()
        name.typeText("Architecture test lunch\n")
        calories.tap()
        calories.typeText("525.4")
        let save = app.buttons["Save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["Architecture test lunch"].waitForExistence(timeout: 6),
                      "The simulator's memory-only meal must survive closing the plate without a signed-in account")
        XCTAssertTrue(app.staticTexts["525.4"].waitForExistence(timeout: 6),
                      "Food energy must retain its decimal after saving")
    }

    func testEditMealKeepsNameAndSaveReachableAboveKeyboard() {
        let app = launchFuel(editPlate: true)
        let name = app.textFields["fuel.edit.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        name.tap()
        let focusShot = XCTAttachment(screenshot: app.screenshot())
        focusShot.lifetime = .keepAlways
        add(focusShot)
        name.typeText(" Edited")
        let keyboardAppeared = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        if !keyboardAppeared { print(app.debugDescription) }
        XCTAssertTrue(keyboardAppeared)
        let edited = name.value as? String ?? ""
        XCTAssertTrue(edited.contains("Edited"))
        let save = app.buttons.matching(NSPredicate(format: "label == %@", "Save")).firstMatch
        XCTAssertTrue(name.isHittable, "The focused food name must remain visible")
        if !save.isHittable { print(app.debugDescription) }
        XCTAssertTrue(save.isHittable, "The keyboard must leave Save reachable")
        XCTAssertGreaterThanOrEqual(app.staticTexts["Edit this meal"].frame.minY, app.frame.minY)
        save.tap()
        let saved = app.staticTexts[edited].waitForExistence(timeout: 6)
        if !saved { print(app.debugDescription) }
        XCTAssertTrue(saved)
    }

    private func launchFuel(range: String? = nil, manualPlate: Bool = false, editPlate: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "fuel"
        if manualPlate { app.launchEnvironment["NB_DEBUG_FUEL_PLATE"] = "1" }
        if editPlate { app.launchEnvironment["NB_DEBUG_FUEL_PLATE"] = "edit" }
        if let range {
            app.launchEnvironment["NB_DEBUG_FUEL_RANGE"] = range
        }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        // The first-morning notification primer can cover this route on a fresh install.
        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        return app
    }
}
