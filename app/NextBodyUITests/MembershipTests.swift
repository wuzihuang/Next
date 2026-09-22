import XCTest

/// Exercises the shared native Paper layout and gate routing with store-free
/// previews. These do not validate SDK product configuration or real purchases.
final class MembershipTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testWelcomePreviewCloseEntersHomeWithoutAutomaticCard() {
        let app = launch(offer: "offerA", onboarding: true)
        assertPreview(app)
        screenshot(app, name: "Membership gate preview")
        app.buttons["membership.close"].tap()
        assertHome(app)
        let unexpectedCard = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.buttons["membership.close"].exists }, object: nil)
        unexpectedCard.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedCard], timeout: 5), .completed)
    }

    func testNativePaperLayoutScreenshot() {
        let app = launch(offer: "offerA", onboarding: true)
        assertPreview(app)
        let button = app.buttons["membership.start"]
        XCTAssertEqual(button.frame.width, app.windows.firstMatch.frame.width, accuracy: 1)
        XCTAssertEqual(button.frame.height, 84, accuracy: 1)
        XCTAssertEqual(button.frame.maxY, app.windows.firstMatch.frame.maxY, accuracy: 1)
        XCTAssertEqual(app.staticTexts["membership.preview"].label, "NextBody Pro")
        XCTAssertTrue(app.staticTexts["Say what you want. Your AI agent handles it all."].exists)
        XCTAssertTrue(app.staticTexts["Answers, personal plans, custom features and advice tailored to you."].exists)
        XCTAssertTrue(app.staticTexts["Top-tier AI nutrition expertise. Understand today's meals with a personal dietary assessment."].exists)
        screenshot(app, name: "Native Paper 390x844")
    }

    func testBaselineFinishesIntoMembershipBeforeHome() {
        var samples: [TimeInterval] = []
        for _ in 0..<5 {
            let app = launch(offer: "offerA", onboarding: true, extra: ["NB_DEBUG_ONB_STEP": "baseline"])
            let enter = app.buttons["Enter NEXTBODY"]
            XCTAssertTrue(enter.waitForExistence(timeout: 30))
            // Includes XCTest's tap delivery and idle wait; this is simulator latency,
            // not production analytics or the duration of the baseline launch fixture.
            let started = Date()
            enter.tap()
            XCTAssertTrue(app.buttons["membership.close"].waitForExistence(timeout: 2),
                          "Baseline completion must show membership before entering Home")
            samples.append(Date().timeIntervalSince(started))
            assertPreview(app)
            app.terminate()
        }
        let median = samples.sorted()[samples.count / 2]
        let result = "iPhone simulator baseline tap-to-card seconds (includes XCTest idle): \(samples); P50: \(median)"
        print(result)
        let attachment = XCTAttachment(string: result)
        attachment.name = "Baseline membership latency — 5 samples"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThanOrEqual(median, 2)
    }

    func testStoreFreePreviewCannotPurchaseOrRestore() {
        let app = launch(offer: "offerB", onboarding: true)
        assertPreview(app)
        screenshot(app, name: "Unavailable store preview")
        app.buttons["membership.options"].tap()
        app.buttons["membership.restore"].tap()
        XCTAssertTrue(app.staticTexts["App Store purchases are not configured on this build."].waitForExistence(timeout: 5))
        assertPreview(app)
        app.buttons["membership.start"].tap()
        assertPreview(app)
    }

    func testProfileReopensSameCardAfterDismissal() {
        let app = launch(offer: "offerB", route: "profile")
        dismissWelcomeIfPresent(app)
        let card = app.buttons["profile.pro"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        assertPreview(app)
        app.buttons["membership.close"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        assertPreview(app)
    }

    func testActiveProProfileOpensCustomerCenterPreview() {
        let app = launch(offer: "active", route: "profile")
        let card = app.buttons["profile.pro"]
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        XCTAssertTrue(card.isEnabled)
        card.tap()
        let preview = app.staticTexts["customer-center.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["membership.close"].exists)
        app.buttons["customer-center.close"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    func testDockKeyboardAndPhotoAskForPro() {
        let app = launch(offer: "offerA", extra: ["NB_DEBUG_DOCK": "keyboard", "NB_DEBUG_DRAFT": "How is my recovery?"])
        dismissWelcomeIfPresent(app)
        let send = app.buttons["dock-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        send.tap()
        assertPreview(app)
        app.buttons["membership.close"].tap()
        let camera = app.buttons["Camera"]
        XCTAssertTrue(camera.waitForExistence(timeout: 5))
        camera.tap()
        let photograph = app.staticTexts["Photograph your meal"]
        XCTAssertTrue(photograph.waitForExistence(timeout: 5))
        photograph.tap()
        assertPreview(app)
    }

    func testDockVoiceAsksForPro() {
        let app = launch(offer: "offerB")
        dismissWelcomeIfPresent(app)
        let voice = app.descendants(matching: .any).matching(identifier: "Hold to talk").firstMatch
        XCTAssertTrue(voice.waitForExistence(timeout: 10))
        voice.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7)
        assertPreview(app)
    }

    func testChatSendAsksForPro() {
        let app = launch(offer: "offerB", route: "chat")
        dismissWelcomeIfPresent(app)
        let input = app.textFields["coach-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText("How is my recovery?")
        app.buttons["coach-send"].tap()
        assertPreview(app)
    }

    func testAdviceRefreshAsksForPro() {
        let app = launch(offer: "offerA", extra: ["NB_DEBUG_PLAN": "1"])
        dismissWelcomeIfPresent(app)
        let refresh = app.buttons["plan.regenerate"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["membership.close"].exists)
        refresh.tap()
        assertPreview(app)
    }

    private func launch(offer: String, onboarding: Bool = false, route: String? = nil,
                        extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["NB_DEBUG_STAGE": onboarding ? "gateOnboarding" : "root",
                                 "NB_DEBUG_CONSENT": "granted", "NB_DEBUG_LANG": "en", "NB_DEBUG_PRO": offer]
        if onboarding { app.launchEnvironment["NB_DEBUG_ONB_STEP"] = "membership" }
        if let route { app.launchEnvironment["NB_DEBUG_ROUTE"] = route }
        app.launchEnvironment.merge(extra) { _, new in new }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func dismissWelcomeIfPresent(_ app: XCUIApplication) {
        if app.buttons["membership.close"].waitForExistence(timeout: 8) { app.buttons["membership.close"].tap() }
    }

    private func assertPreview(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.buttons["membership.close"].waitForExistence(timeout: 30), file: file, line: line)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "membership.preview").firstMatch.exists,
                      "Store-free fixtures must never be mistaken for RevenueCat Paywalls", file: file, line: line)
        let start = app.buttons["membership.start"]
        XCTAssertTrue(start.isHittable, file: file, line: line)
        XCTAssertEqual(start.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 1,
                       "The primary action must retain equal horizontal gutters", file: file, line: line)
        XCTAssertTrue(app.buttons["membership.options"].isHittable, file: file, line: line)
        XCTAssertFalse(app.buttons["Not now"].exists, file: file, line: line)
        XCTAssertTrue(app.staticTexts["A MONTH · CANCEL ANYTIME"].exists, file: file, line: line)
    }

    private func assertHome(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Camera"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["membership.close"].exists)
    }

    private func screenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Opt-in network test using an already-authorized simulator account and RevenueCat
/// Test Store. Enable NB_RUN_RC_TESTSTORE=1 in the test runner environment explicitly.
final class RevenueCatPaywallIntegrationTests: XCTestCase {
    func testBaselineToNativePaywallLatency() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NB_RUN_RC_TESTSTORE"] == "1")
        _ = try XCTUnwrap(ProcessInfo.processInfo.environment["NB_RC_EXPECT_IDENTITY"])
        continueAfterFailure = false
        var samples: [TimeInterval] = []
        for _ in 0..<5 {
            let app = XCUIApplication()
            app.launchEnvironment = ["NB_DEBUG_STAGE": "gateOnboarding", "NB_DEBUG_ONB_STEP": "baseline",
                                     "NB_DEBUG_CONSENT": "granted", "NB_DEBUG_LANG": "en"]
            app.launchEnvironment["NB_DEBUG_BILLING_EXPECT_IDENTITY"] = ProcessInfo.processInfo.environment["NB_RC_EXPECT_IDENTITY"]
            app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            let enter = app.buttons["Enter NEXTBODY"]
            XCTAssertTrue(enter.waitForExistence(timeout: 30))
            let started = Date()
            enter.tap()
            let purchase = purchaseButton(in: app)
            XCTAssertTrue(purchase.waitForExistence(timeout: 20))
            if !purchase.isEnabled {
                let purchasable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    purchase.exists && purchase.isEnabled
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [purchasable], timeout: 20), .completed)
            }
            samples.append(Date().timeIntervalSince(started))
            XCTAssertFalse(app.staticTexts["membership.preview"].exists)
            XCTAssertFalse(app.staticTexts["No Paywall configured"].exists)
            app.terminate()
        }
        let median = samples.sorted()[samples.count / 2]
        let report = "Native paywall with RevenueCat product: 5 process-cold launches with retained disk caches/session; tap invocation through START PRO enabled with the loaded SDK product, includes XCTest idle/polling overhead. Seconds: \(samples); P50=\(median)"
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "Native paywall baseline latency"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThanOrEqual(median, 2)
    }

    func testCurrentOfferingPaywallLoadsAndCanBeClosed() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NB_RUN_RC_TESTSTORE"] == "1")
        _ = try XCTUnwrap(ProcessInfo.processInfo.environment["NB_RC_EXPECT_IDENTITY"])
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["NB_DEBUG_STAGE": "root", "NB_DEBUG_ROUTE": "profile",
                                 "NB_DEBUG_CONSENT": "granted", "NB_DEBUG_LANG": "en"]
        app.launchEnvironment["NB_DEBUG_BILLING_EXPECT_IDENTITY"] = ProcessInfo.processInfo.environment["NB_RC_EXPECT_IDENTITY"]
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let close = app.buttons["membership.close"]
        if !close.waitForExistence(timeout: 8) {
            let pro = app.buttons["profile.pro"]
            XCTAssertTrue(pro.waitForExistence(timeout: 15))
            pro.tap()
        }
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["membership.preview"].exists)
        XCTAssertTrue(purchaseButton(in: app).waitForExistence(timeout: 30),
                      "The RevenueCat package must enable the native purchase action")
        XCTAssertFalse(app.staticTexts["No Paywall configured"].exists)
        XCTAssertTrue(app.otherElements["membership.price"].exists || app.staticTexts["6"].exists,
                      "The USD Test Store package must display its configured price")
        XCTAssertTrue(app.buttons["membership.options"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native Paper Paywall — real RevenueCat product"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        close.tap()
        XCTAssertFalse(close.exists)
    }

    /// Requires a test account without an active store subscription. The final
    /// step creates a Test Store subscription, so reruns need a fresh test fixture.
    func testTestStoreCancelFailureAndPurchase() throws {
        let expected = ProcessInfo.processInfo.environment["NB_EXPECT_BILLING_RESULT"] ?? ""
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NB_RUN_RC_TESTSTORE"] == "1"
                          && ["active", "pending"].contains(expected))
        _ = try XCTUnwrap(ProcessInfo.processInfo.environment["NB_RC_EXPECT_IDENTITY"])
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["NB_DEBUG_STAGE": "root", "NB_DEBUG_ROUTE": "profile",
                                 "NB_DEBUG_CONSENT": "granted", "NB_DEBUG_LANG": "en"]
        app.launchEnvironment["NB_DEBUG_BILLING_EXPECT_IDENTITY"] = ProcessInfo.processInfo.environment["NB_RC_EXPECT_IDENTITY"]
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let close = app.buttons["membership.close"]
        if !close.waitForExistence(timeout: 8) {
            let pro = app.buttons["profile.pro"]
            XCTAssertTrue(pro.waitForExistence(timeout: 15))
            pro.tap()
        }
        let purchase = purchaseButton(in: app)
        XCTAssertTrue(purchase.waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["No Paywall configured"].exists)
        let skipPrior = ProcessInfo.processInfo.environment["NB_RC_SKIP_PRIOR"] == "1"
        let store = app.alerts["Test Store Purchase"]
        if !skipPrior {
            app.buttons["membership.options"].tap()
            let restore = app.buttons["membership.restore"]
            XCTAssertTrue(restore.isHittable)
            restore.tap()
            XCTAssertTrue(app.staticTexts["No Pro purchase to restore for this health account."].waitForExistence(timeout: 30))
            XCTAssertTrue(close.exists)

            waitUntilEnabled(purchase)
            purchase.tap()
            XCTAssertTrue(store.waitForExistence(timeout: 10))
            store.buttons["Cancel"].tap()
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["membership.message"].exists,
                           "Cancelling the Test Store sheet must not become an error")
        }

        if ProcessInfo.processInfo.environment["NB_RC_SUCCESS_ONLY"] != "1" {
            waitUntilEnabled(purchase)
            purchase.tap()
            XCTAssertTrue(store.waitForExistence(timeout: 10))
            store.buttons["Test failed purchase"].tap()
            XCTAssertTrue(app.staticTexts["membership.message"].waitForExistence(timeout: 10))
            let failedScreenshot = XCTAttachment(screenshot: app.screenshot())
            failedScreenshot.name = "Failed purchase leaves retry available"
            failedScreenshot.lifetime = .keepAlways
            add(failedScreenshot)
            XCTAssertTrue(close.exists)
        }

        waitUntilEnabled(purchase)
        purchase.tap()
        XCTAssertTrue(store.waitForExistence(timeout: 10))
        store.buttons["Test valid purchase"].tap()
        if expected == "pending" {
            XCTAssertTrue(app.staticTexts["Purchase did not activate yet. Try Restore."].waitForExistence(timeout: 45),
                          "A Test Store receipt must not grant AI while the server ledger is unsynchronized")
            XCTAssertTrue(close.exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Test Store purchase awaits server entitlement"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            close.tap()
        } else {
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !close.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 45), .completed,
                           "The allowlisted test purchase must dismiss only after server activation")
            let card = app.buttons["profile.pro"]
            XCTAssertTrue(card.waitForExistence(timeout: 30))
            let active = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                card.exists && (card.label.contains("Pro is on") || card.label.contains("Free month"))
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [active], timeout: 30), .completed)
            card.tap()
            let centerClose = app.buttons["customer-center.close"]
            XCTAssertTrue(centerClose.waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["customer-center.preview"].exists)
            let loaded = app.staticTexts["Test Store"]
            let didLoad = loaded.waitForExistence(timeout: 20)
            let centerScreenshot = XCTAttachment(screenshot: app.screenshot())
            centerScreenshot.name = "Customer Center after server activation"
            centerScreenshot.lifetime = .keepAlways
            add(centerScreenshot)
            XCTAssertTrue(didLoad, "Customer Center must load the purchased subscription")
            centerClose.tap()
            app.terminate()
            app.launch()
            XCTAssertTrue(card.waitForExistence(timeout: 30))
            let retained = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                card.exists && (card.label.contains("Pro is on") || card.label.contains("Free month"))
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [retained], timeout: 30), .completed,
                           "A restart within the Test Store subscription lifetime must retain server Pro")
        }
    }

    /// Continue read-only verification while a separately purchased Test Store
    /// subscription is active. This method never purchases or restores.
    func testActiveTestStoreCenterAndColdRestart() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NB_RUN_RC_TESTSTORE"] == "1")
        let identity = try XCTUnwrap(ProcessInfo.processInfo.environment["NB_RC_EXPECT_IDENTITY"])
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["NB_DEBUG_STAGE": "root", "NB_DEBUG_ROUTE": "profile",
                                 "NB_DEBUG_CONSENT": "granted", "NB_DEBUG_LANG": "en",
                                 "NB_DEBUG_BILLING_EXPECT_IDENTITY": identity]
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let card = app.buttons["profile.pro"]
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        let active = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            card.exists && (card.label.contains("Pro is on") || card.label.contains("Free month"))
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [active], timeout: 30), .completed)
        card.tap()
        let close = app.buttons["customer-center.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Test Store"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "PurchaseInformationCardView.Badge_active").firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["customer-center.preview"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Live Test Store Customer Center"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        close.tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        let retained = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            card.exists && (card.label.contains("Pro is on") || card.label.contains("Free month"))
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [retained], timeout: 30), .completed)
    }

    private func waitUntilEnabled(_ button: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            button.exists && button.isEnabled && button.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

    private func purchaseButton(in app: XCUIApplication) -> XCUIElement {
        if let title = ProcessInfo.processInfo.environment["NB_RC_PAYWALL_CTA"] {
            return app.buttons.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch
        }
        return app.buttons.matching(NSPredicate(format: "label IN %@", ["START PRO", "START FREE TRIAL"])).firstMatch
    }

}

/// Physical-device read-only check. Uses the existing health-account Keychain
/// session and App Store storefront; never starts a purchase or restore.
final class RevenueCatAppStoreReadOnlyTests: XCTestCase {
    func testNativePaywallShowsLocalOfferAndCanClose() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["NB_RUN_RC_APPSTORE"] == "1")
        let expectedIdentity = try XCTUnwrap(environment["NB_RC_EXPECT_IDENTITY"],
                                            "Provide the verified health-account identity")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["NB_DEBUG_RC_STORE": "app_store", "NB_DEBUG_STAGE": "root",
                                 "NB_DEBUG_ROUTE": "profile", "NB_DEBUG_CONSENT": "granted",
                                 "NB_DEBUG_BILLING_EXPECT_IDENTITY": expectedIdentity]
        app.launch()
        let close = app.buttons["membership.close"]
        if !close.waitForExistence(timeout: 8) {
            let pro = app.buttons["profile.pro"]
            XCTAssertTrue(pro.waitForExistence(timeout: 30), "Existing health-account login is required")
            pro.tap()
        }
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        let purchase = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "START PRO")).firstMatch
        XCTAssertTrue(purchase.waitForExistence(timeout: 45))
        XCTAssertFalse(app.staticTexts["membership.preview"].exists)
        XCTAssertFalse(app.staticTexts["No Paywall configured"].exists)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: purchase)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed,
                       "A real monthly package and matching account must be ready")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "membership.price").firstMatch.exists)
        XCTAssertTrue(app.buttons["membership.options"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "App Store localized offer and eligibility — read only"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        close.tap()
        XCTAssertFalse(close.exists)
    }
}

/// Read-only gate coverage with an isolated, signed-in account without Pro.
final class RevenueCatRealGateTests: XCTestCase {
    func testFiveAIEntrypointsAndAutomaticPlanStayGated() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NB_RUN_RC_REAL_GATES"] == "1")
        _ = try XCTUnwrap(ProcessInfo.processInfo.environment["NB_RC_EXPECT_IDENTITY"])
        continueAfterFailure = false
        var app = launch(extra: ["NB_DEBUG_DOCK": "keyboard", "NB_DEBUG_DRAFT": "How is my recovery?"])
        XCTAssertTrue(app.buttons["dock-send"].waitForExistence(timeout: 15))
        app.buttons["dock-send"].tap()
        assertPaywallAndClose(app)
        app.buttons["Camera"].tap()
        let photo = app.staticTexts["Photograph your meal"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        assertPaywallAndClose(app)
        app.terminate()

        app = launch()
        let voice = app.descendants(matching: .any).matching(identifier: "Hold to talk").firstMatch
        XCTAssertTrue(voice.waitForExistence(timeout: 15))
        voice.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7)
        assertPaywallAndClose(app)
        app.terminate()

        app = launch(extra: ["NB_DEBUG_ROUTE": "chat"])
        let input = app.textFields["coach-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText("How is my recovery?")
        app.buttons["coach-send"].tap()
        assertPaywallAndClose(app)
        app.terminate()

        app = launch(extra: ["NB_DEBUG_PLAN": "1"])
        let refresh = app.buttons["plan.regenerate"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 15))
        let automaticCard = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["membership.close"].exists
        }, object: nil)
        automaticCard.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [automaticCard], timeout: 5), .completed)
        refresh.tap()
        assertPaywallAndClose(app)
    }

    private func launch(extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["NB_DEBUG_STAGE": "root", "NB_DEBUG_CONSENT": "granted", "NB_DEBUG_LANG": "en"]
        app.launchEnvironment["NB_DEBUG_BILLING_EXPECT_IDENTITY"] = ProcessInfo.processInfo.environment["NB_RC_EXPECT_IDENTITY"]
        app.launchEnvironment.merge(extra) { _, new in new }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if app.buttons["membership.close"].waitForExistence(timeout: 8) {
            assertPaywallAndClose(app)
        }
        return app
    }

    private func assertPaywallAndClose(_ app: XCUIApplication) {
        let purchase = app.buttons["START PRO"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 30))
        XCTAssertTrue(purchase.isHittable)
        XCTAssertTrue(purchase.isEnabled)
        XCTAssertFalse(app.staticTexts["membership.preview"].exists)
        XCTAssertFalse(app.staticTexts["No Paywall configured"].exists)
        XCTAssertTrue(app.buttons["membership.options"].isHittable)
        app.buttons["membership.close"].tap()
        XCTAssertFalse(app.buttons["membership.close"].exists)
    }
}
