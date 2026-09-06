import XCTest

/// ADR 0010 · 「我的」那块 MEASUREMENTS 的两条硬规则，各用一次真触摸验一遍：
/// 底部那行是这张卡唯一的热区，而清单里的一行点开是 sheet 不是第三级页面。
///
/// ⚠️ 这两条都验不了「看起来对不对」，只验能不能到达。卡本身的排布看截图。
final class MeasurementsEntryTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 11C · YEAR / COMPOSITION 是同一张卡的头，点头进今天的成分页。
    func testCompositionHeaderOpensToday() {
        let app = launch(route: "profile")
        XCTAssertTrue(app.staticTexts["YEAR"].waitForExistence(timeout: 30),
                      "profile never showed the instrument composition card")
        XCTAssertTrue(app.staticTexts["MEASUREMENTS"].exists,
                      "measurements must stay a plate of its own")

        let entry = app.buttons["COMPOSITION"]
        XCTAssertTrue(entry.waitForExistence(timeout: 6), "卡头没有 COMPOSITION 这个入口")
        entry.tap()

        XCTAssertTrue(app.staticTexts["NO CHART"].waitForExistence(timeout: 30),
                      "COMPOSITION 卡头没有进到 10E 成分页")
        XCTAssertTrue(app.buttons["range.DAY"].exists)
    }

    /// 10E · 日 / 周 / 月共用一套铬，DAY 不画线，WEEK / MONTH 换窗口词。
    func testCompositionWindowsShareOneChrome() {
        let app = launch(route: "composition")
        XCTAssertTrue(app.staticTexts["NO CHART"].waitForExistence(timeout: 30),
                      "composition route never opened the 10E page")
        XCTAssertTrue(app.buttons["range.DAY"].exists)
        XCTAssertTrue(app.staticTexts["BODY FAT"].exists,
                      "DAY must show the persisted body-fat row")

        let week = app.buttons["range.WEEK"]
        XCTAssertTrue(week.isHittable, "WEEK pill is on screen but not tappable")
        week.tap()
        XCTAssertTrue(app.staticTexts["WEEK BAND"].waitForExistence(timeout: 6),
                      "WEEK must keep the personal band")
        XCTAssertTrue(app.staticTexts["EVERY SCAN"].waitForExistence(timeout: 6),
                      "WEEK lists every scan, newest first")

        app.buttons["range.MONTH"].tap()
        XCTAssertTrue(app.staticTexts["YOUR BAND"].waitForExistence(timeout: 6),
                      "MONTH must keep the personal band")
        XCTAssertTrue(app.staticTexts["WEEK AVERAGES"].waitForExistence(timeout: 6),
                      "MONTH lists week averages")
    }

    /// 卡的底部那行进二级页；行本身不可点。
    func testAllMeasurementsOpensTheSecondLevel() {
        let app = launch(route: "profile")
        XCTAssertTrue(app.staticTexts["MEASUREMENTS"].waitForExistence(timeout: 30),
                      "profile never showed the measurements card")

        // ⚠️ 这张卡的底部那行在首屏折叠线以下，要滚到才点得到。按 id 找，不按文案——
        // 文案会随语言变，而且 SwiftUI 会把整个 Button 收成一个元素。
        let entry = app.buttons["ALL_MEASUREMENTS"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "卡上没有 ALL MEASUREMENTS 这个入口")
        for _ in 0..<5 where !entry.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(entry.isHittable, "ALL MEASUREMENTS 滚不到，点不着")

        // 清单页独有的那句话——「留下几条」。卡上没有这个串。
        let kept = app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH %@", "KEPT")).firstMatch

        // ⚠️ 行不是热区：卡上的行从来不是按钮，只有底部那行是。
        // 这里不去点它——滚动之后行的坐标会失效，而且「点了没反应」本来就不该用一次
        // 可能落在别处的触摸去证明。
        XCTAssertFalse(app.buttons["BODY SCAN"].exists,
                       "卡上的一行成了按钮——这张卡唯一的热区应该是底部那行")

        entry.tap()
        XCTAssertTrue(kept.waitForExistence(timeout: 8),
                      "ALL MEASUREMENTS 没有进到测量记录页")
    }

    /// 清单里的一行点开是 sheet：底下那一页还在，返回键仍然在场。
    func testARowOpensASheetOverTheList() throws {
        let app = launch(route: "measurements")
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 30), "measurements page never opened")

        let row = app.staticTexts["BODY SCAN"].firstMatch
        guard row.waitForExistence(timeout: 10) else {
            throw XCTSkip("这个账号还没有测量记录，没有行可以点")
        }
        row.tap()

        // sheet 上的标题是 Body scan（句首大写），和行上的 BODY SCAN 不是同一个串。
        XCTAssertTrue(app.staticTexts["Body scan"].waitForExistence(timeout: 6),
                      "点开一行没有打开记录 sheet")
        // 盖在上面，不是推走：底下那一页的返回键还在。
        XCTAssertTrue(back.exists, "记录被做成了第三级页面——它应该是盖在清单上的 sheet")
    }

    private func launch(route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_LANG"] = "en"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = route
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }
}
