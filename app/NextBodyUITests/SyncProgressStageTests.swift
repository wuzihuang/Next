import XCTest
import UIKit

final class SyncProgressStageTests: XCTestCase {
    func testConnectionVerificationIsPartOfProgress() {
        let app = launch(stage: "verifying")
        XCTAssertTrue(app.staticTexts["日常同步 · App · 8% · 正在验证设备"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["立即同步"].value as? String, "正在验证设备")
        assertSyncColor(app.buttons["立即同步"], cloud: false)
        assertHomeMatches(app, line: "日常同步 · App · 8% · 正在验证设备")
    }

    func testBandReadingIsYellowAndNamesApp() {
        let app = launch(stage: "reading")
        XCTAssertTrue(app.buttons["立即同步"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["立即同步"].value as? String, "正在同步到 App")
        assertSyncColor(app.buttons["立即同步"], cloud: false)
        assertHomeMatches(app, line: "日常同步 · App · 55% · 正在读取第 3 / 3")
    }

    func testCloudUploadIsBlueBeforeResultsUpdate() {
        let app = launch(stage: "saving")
        XCTAssertTrue(app.staticTexts["日常同步 · 云端 · 55% · 正在同步到云端"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["立即同步"].value as? String, "正在同步到云端")
        assertSyncColor(app.buttons["立即同步"], cloud: true)
        assertHomeMatches(app, line: "日常同步 · 云端 · 55% · 正在同步到云端")
    }

    func testDumpCompleteStillShowsLessThanWholeSyncComplete() {
        let app = launch(stage: "updating")
        XCTAssertTrue(app.staticTexts["日常同步 · 云端 · 92% · 正在更新云端结果"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["立即同步"].value as? String, "正在更新云端结果")
        assertSyncColor(app.buttons["立即同步"], cloud: true)
        assertHomeMatches(app, line: "日常同步 · 云端 · 92% · 正在更新云端结果")
    }

    func testCompletionClearsTheBarAndTheButtonTogether() {
        let app = launch(stage: "complete")
        XCTAssertTrue(app.buttons["立即同步"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["立即同步"].value as? String ?? "", "")
        XCTAssertFalse(app.otherElements["device.syncProgress"].exists,
                       "A finished sync must not leave the bar sitting at 100%")
        XCTAssertFalse(app.staticTexts["100% · 同步完成"].exists)
        // Nothing here waits for a late label, so give the page its entry beat before
        // tapping back; a tap during the transition is swallowed.
        let back = app.buttons["返回"]
        XCTAssertTrue(back.waitForExistence(timeout: 20))
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: back)], timeout: 10)
        back.tap()
        let close = app.buttons["panel-dismiss"]
        if close.exists { close.tap() }
        XCTAssertFalse(app.otherElements["home.syncProgress"].exists)
        XCTAssertFalse(app.otherElements["panel.syncProgress"].exists)
    }

    private func assertHomeMatches(_ app: XCUIApplication, line: String) {
        app.buttons["返回"].tap()
        let close = app.buttons["panel-dismiss"]
        if close.exists { close.tap() }
        let status = app.otherElements["home.syncProgress"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        XCTAssertEqual(status.value as? String, line, "Returning home must not start a second progress calculation")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = line
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func assertSyncColor(_ element: XCUIElement, cloud: Bool,
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard let image = element.screenshot().image.cgImage else {
            return XCTFail("Sync control screenshot unavailable", file: file, line: line)
        }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(rendered, file: file, line: line)
        let target = cloud ? [56, 189, 248] : [239, 246, 90]
        let matching = stride(from: 0, to: pixels.count, by: 4).filter { offset in
            (0..<3).allSatisfy { abs(Int(pixels[offset + $0]) - target[$0]) <= 12 }
        }.count
        XCTAssertGreaterThan(Double(matching) / Double(width * height), 0.2,
                             cloud ? "Cloud sync must be blue" : "App sync must be yellow",
                             file: file, line: line)
    }

    private func launch(stage: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NB_DEBUG_STAGE"] = "root"
        app.launchEnvironment["NB_DEBUG_LANG"] = "zh-Hans"
        app.launchEnvironment["NB_DEBUG_ROUTE"] = "device"
        app.launchEnvironment["NB_DEBUG_CONSENT"] = "granted"
        app.launchEnvironment["NB_DEBUG_SYNC_STAGE"] = stage
        app.launch()
        return app
    }
}
