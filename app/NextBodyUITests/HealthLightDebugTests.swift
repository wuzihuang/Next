import XCTest

/// Uses the existing phone/account and only reads lamp status; the user observes physical writes.
final class HealthLightDebugTests: XCTestCase {
    func testDeviceDebugEntryExposesFourStates() {
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
        capture.name = "Health light debug states"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
