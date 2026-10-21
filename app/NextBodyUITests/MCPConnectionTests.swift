import XCTest

final class MCPConnectionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testGuideOpensConnectionManagement() {
        let app = launch(language: "en")
        app.buttons["MCP_MANAGE_CONNECTIONS"].tap()
        XCTAssertTrue(app.staticTexts["AI assistants"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Copy the MCP address"].exists)
    }

    func testEnglishAndChinesePromptsExplainDiscoveryPermissionAndSafeRetries() {
        for language in ["en", "zh-Hans"] {
            let app = launch(language: language)
            let preview = app.buttons["MCP_PROMPT_PREVIEW"]
            for _ in 0..<8 where !preview.isHittable { app.swipeUp() }
            XCTAssertTrue(preview.isHittable)
            preview.tap()
            let text = app.staticTexts["MCP_PROMPT_TEXT"]
            for _ in 0..<3 where !text.exists { app.swipeUp() }
            XCTAssertTrue(text.waitForExistence(timeout: 5))
            for required in ["https://mcp.nextbody.ai/mcp", "OAuth", "list_metrics",
                             "get_health_profile", "read_health_records", "log_meal",
                             "request_id", "dayTotalsUpdated", "401", "403", "429"] {
                XCTAssertTrue(text.label.contains(required), "\(language) prompt lacks \(required)")
            }
            XCTAssertTrue(text.label.contains(language == "en" ? "same arguments" : "相同参数"))
            app.terminate()
        }
    }

    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "profile"
        app.launchEnvironment["NB_DEBUG_LANG"] = language
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", "en_US"]
        app.launch()
        let entry = app.buttons["AI_ASSISTANTS"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        for _ in 0..<6 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        XCTAssertTrue(app.buttons["MCP_MANAGE_CONNECTIONS"].waitForExistence(timeout: 8))
        return app
    }
}
