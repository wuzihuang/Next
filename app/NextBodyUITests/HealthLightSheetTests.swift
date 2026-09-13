import XCTest

/// 12S · walks the Device page to the health-light row in the debug card. Only reads the
/// lamp status; the user observes the physical writes.
final class HealthLightSheetTests: XCTestCase {
    func testDeviceLightRowExposesFourStates() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let band = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Band · battery ")).firstMatch
        XCTAssertTrue(band.waitForExistence(timeout: 60))
        band.tap()
        let probe = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS %@", "Health light", "健康灯")).firstMatch
        for _ in 0..<7 {
            if probe.exists && probe.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        XCTAssertTrue(probe.isHittable)
        probe.tap()
        for raw in 0...3 {
            XCTAssertTrue(app.buttons["healthLight.state.\(raw)"].waitForExistence(timeout: 10))
        }
        let refresh = app.buttons["healthLight.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 60), .completed)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Health light states"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
