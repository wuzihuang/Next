import XCTest

@available(iOS 26.0, *)
final class HomeTransitionPerfTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPager() {
        let app = launchRealHome()
        let readiness = homeReadiness(in: app)
        runPager(app, readiness: readiness)

        var options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            runPager(app, readiness: readiness)
        }
    }

    func testReadinessPushPop() {
        let app = launchRealHome()
        let readiness = homeReadiness(in: app)
        runReadinessPushPop(app, readiness: readiness)

        var options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            runReadinessPushPop(app, readiness: readiness)
        }
    }

    func testSleepPushScrollPop() {
        let app = launchRealHome()
        let sleep = homeSleep(in: app)
        runSleepPushScrollPop(app, sleep: sleep)

        var options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            runSleepPushScrollPop(app, sleep: sleep)
        }
    }

    func testTimelinePull() throws {
        let app = launchRealHome()
        _ = homeReadiness(in: app)
        guard runTimelinePull(app) else {
            throw XCTSkip("Timeline pull did not complete during warm-up")
        }

        var options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            XCTAssertTrue(runTimelinePull(app), "timeline pull did not complete")
        }
    }

    func testHomeTransitionScreenshots() {
        let app = launchRealHome()
        let readiness = app.buttons["READINESS"]
        let sleep = app.buttons["SLEEP"]
        XCTAssertTrue(readiness.waitForExistence(timeout: 60), "real-data Home never appeared")
        attachScreenshot(app, named: "home-planet")
        Thread.sleep(forTimeInterval: 2)
        attachScreenshot(app, named: "home-planet-after-2s")

        swipe(app, from: CGPoint(x: 0.82, y: 0.76), to: CGPoint(x: 0.12, y: 0.76))
        pause()
        attachScreenshot(app, named: "home-instruments")

        swipe(app, from: CGPoint(x: 0.12, y: 0.76), to: CGPoint(x: 0.82, y: 0.76))
        pause()
        swipe(app, from: CGPoint(x: 0.12, y: 0.76), to: CGPoint(x: 0.82, y: 0.76))
        pause()
        Thread.sleep(forTimeInterval: 2.5)
        attachScreenshot(app, named: "home-body-particles")
        swipe(app, from: CGPoint(x: 0.82, y: 0.76), to: CGPoint(x: 0.12, y: 0.76))
        pause()
        XCTAssertTrue(waitUntilHittable(readiness, in: app, timeout: 5))

        swipe(app, from: CGPoint(x: 0.5, y: 0.82), to: CGPoint(x: 0.5, y: 0.14))
        pause()
        XCTAssertTrue(app.buttons["TIMELINE_DISMISS"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "home-timeline")
        let dismiss = app.buttons["TIMELINE_DISMISS"]
        activateIfNeeded(app)
        let pull = dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        pull.press(forDuration: 0.05,
                   thenDragTo: pull.withOffset(CGVector(dx: 0, dy: 120)),
                   withVelocity: XCUIGestureVelocity(1000), thenHoldForDuration: 0)
        pause()

        activateIfNeeded(app)
        readiness.tap()
        pause()
        let readinessBack = detailBack(app)
        XCTAssertTrue(readinessBack.waitForExistence(timeout: 8))
        attachScreenshot(app, named: "readiness-detail")
        activateIfNeeded(app)
        readinessBack.tap()
        pause()

        activateIfNeeded(app)
        sleep.tap()
        pause()
        let sleepBack = detailBack(app)
        XCTAssertTrue(sleepBack.waitForExistence(timeout: 8))
        attachScreenshot(app, named: "sleep-detail")
        let detailScroll = app.scrollViews.firstMatch
        XCTAssertTrue(detailScroll.waitForExistence(timeout: 5))
        activateIfNeeded(app)
        detailScroll.swipeUp()
        pause()
        activateIfNeeded(app)
        detailScroll.swipeUp()
        pause()
        attachScreenshot(app, named: "sleep-detail-scrolled")
        activateIfNeeded(app)
        detailScroll.swipeDown()
        pause()
        activateIfNeeded(app)
        detailScroll.swipeDown()
        pause()
        activateIfNeeded(app)
        sleepBack.tap()
    }

    private func launchRealHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func detailBack(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Back", "返回"])).firstMatch
    }

    private func swipe(_ app: XCUIApplication, from: CGPoint, to: CGPoint) {
        activateIfNeeded(app)
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: from.x, dy: from.y))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: to.x, dy: to.y))
        start.press(forDuration: 0.3, thenDragTo: end)
    }

    private func waitUntilHittable(_ element: XCUIElement, in app: XCUIApplication,
                                  timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            activateIfNeeded(app)
            if element.exists && element.isHittable { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        activateIfNeeded(app)
        return element.exists && element.isHittable
    }

    private func activateIfNeeded(_ app: XCUIApplication) {
        if app.state != .runningForeground { app.activate() }
    }

    private func pause() {
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return !element.exists
    }

    private func waitUntilNotHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let hidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == false"), object: element)
        return XCTWaiter.wait(for: [hidden], timeout: timeout) == .completed
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
