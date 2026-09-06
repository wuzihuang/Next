import XCTest
@testable import NextBodySyncCore

final class WidgetFaceMathTests: XCTestCase {

    func testPlaceholderMatchesTheHomeSeed() {
        let glance = WidgetFaceMath.Glance.placeholder
        let read = WidgetFaceMath.today(glance, now: glance.numbersAt)
        XCTAssertEqual(read.batteryText, "72")
        XCTAssertEqual(read.loadText, "12.4")
        XCTAssertEqual(read.eatenText, "1,240")
        XCTAssertEqual(read.batteryProgress, 0.72, accuracy: 0.0001)
        XCTAssertEqual(read.loadProgress, 12.4 / 21, accuracy: 0.0001)
        XCTAssertEqual(read.eatenProgress, 1_240 / 1_900, accuracy: 0.0001)
        XCTAssertFalse(read.stale)
        XCTAssertNil(read.clock)
        XCTAssertEqual(read.bandText, "82%")
        XCTAssertEqual(read.bandProgress, 0.82, accuracy: 0.0001)
        XCTAssertFalse(read.bandLit)
        XCTAssertEqual(read.heartText, "72")
        XCTAssertEqual(read.stressText, "31")
        XCTAssertEqual(read.sleepText, "78")
        XCTAssertEqual(read.activeText, "320")
        XCTAssertEqual(read.stepsText, "8,432")
        XCTAssertEqual(read.distanceText, "6.2")
        XCTAssertEqual(read.stamp, WidgetFaceMath.clockText(glance.numbersAt))
    }

    func testUnloggedEatenIsADashNeverZero() {
        var glance = WidgetFaceMath.Glance.placeholder
        glance.eaten = nil
        let read = WidgetFaceMath.today(glance, now: glance.numbersAt)
        XCTAssertEqual(read.eatenText, WidgetFaceMath.dash)
        XCTAssertEqual(read.eatenProgress, 0)
    }

    func testFastedZeroIsAnAssertion() {
        var glance = WidgetFaceMath.Glance.placeholder
        glance.eaten = 0
        let read = WidgetFaceMath.today(glance, now: glance.numbersAt)
        XCTAssertEqual(read.eatenText, "0")
        XCTAssertEqual(read.eatenProgress, 0)
    }

    func testStaleWithdrawsLiveNumbersAndKeepsUnloggedEatenAsADash() {
        var glance = WidgetFaceMath.Glance.placeholder
        glance.eaten = nil
        glance.numbersAt = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: WidgetFaceMath.staleAfter + 1)
        let read = WidgetFaceMath.today(glance, now: now)
        XCTAssertTrue(read.stale)
        XCTAssertEqual(read.batteryText, WidgetFaceMath.dash)
        XCTAssertEqual(read.loadText, WidgetFaceMath.dash)
        XCTAssertEqual(read.eatenText, WidgetFaceMath.dash)
        XCTAssertEqual(read.batteryProgress, 0)
        XCTAssertEqual(read.clock, WidgetFaceMath.clockText(glance.numbersAt))
        XCTAssertEqual(read.bandText, "82%")
        XCTAssertEqual(read.heartText, WidgetFaceMath.dash)
        XCTAssertEqual(read.stressText, WidgetFaceMath.dash)
        XCTAssertEqual(read.sleepText, "78")
        XCTAssertEqual(read.activeText, WidgetFaceMath.dash)
        XCTAssertEqual(read.stepsText, WidgetFaceMath.dash)
        XCTAssertEqual(read.distanceText, WidgetFaceMath.dash)
        XCTAssertEqual(read.stamp, WidgetFaceMath.clockText(glance.numbersAt))
    }

    func testStaleAlsoWithdrawsALoggedEaten() {
        var glance = WidgetFaceMath.Glance.placeholder
        glance.numbersAt = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: WidgetFaceMath.staleAfter)
        let read = WidgetFaceMath.today(glance, now: now)
        XCTAssertTrue(read.stale)
        XCTAssertEqual(read.eatenText, WidgetFaceMath.dash)
        XCTAssertEqual(read.eatenProgress, 0)
    }

    func testSignedOutIsDashesWithoutAStaleClock() {
        let read = WidgetFaceMath.today(.empty, now: Date())
        XCTAssertFalse(read.stale)
        XCTAssertNil(read.clock)
        XCTAssertEqual(read.batteryText, WidgetFaceMath.dash)
        XCTAssertEqual(read.loadText, WidgetFaceMath.dash)
        XCTAssertEqual(read.eatenText, WidgetFaceMath.dash)
    }

    func testSignedOutHidesEvenWhenNumbersArePresent() {
        var glance = WidgetFaceMath.Glance.placeholder
        glance.signedIn = false
        let read = WidgetFaceMath.today(glance, now: glance.numbersAt)
        XCTAssertFalse(read.stale)
        XCTAssertNil(read.clock)
        XCTAssertEqual(read.batteryText, WidgetFaceMath.dash)
        XCTAssertEqual(read.loadText, WidgetFaceMath.dash)
        XCTAssertEqual(read.eatenText, WidgetFaceMath.dash)
        XCTAssertEqual(read.batteryProgress, 0)
        XCTAssertEqual(read.loadProgress, 0)
        XCTAssertEqual(read.eatenProgress, 0)
        XCTAssertEqual(read.bandText, WidgetFaceMath.dash)
        XCTAssertFalse(read.bandLit)
        XCTAssertEqual(read.heartText, WidgetFaceMath.dash)
        XCTAssertEqual(read.stressText, WidgetFaceMath.dash)
        XCTAssertEqual(read.sleepText, WidgetFaceMath.dash)
        XCTAssertEqual(read.activeText, WidgetFaceMath.dash)
        XCTAssertEqual(read.stepsText, WidgetFaceMath.dash)
        XCTAssertEqual(read.distanceText, WidgetFaceMath.dash)
        XCTAssertNil(read.stamp)
    }

    func testNextReloadHitsTheNinetyMinuteEdge() {
        let start = Date(timeIntervalSince1970: 1_000)
        var glance = WidgetFaceMath.Glance.placeholder
        glance.numbersAt = start
        let soon = WidgetFaceMath.nextReload(after: glance, now: start)
        XCTAssertEqual(soon, start.addingTimeInterval(15 * 60))
        let late = WidgetFaceMath.nextReload(
            after: glance, now: start.addingTimeInterval(80 * 60))
        XCTAssertEqual(late, start.addingTimeInterval(WidgetFaceMath.staleAfter))
    }

    func testLoadDisplayCapsWithTheHomeCard() {
        XCTAssertEqual(WidgetFaceMath.loadText(21), "20.9")
        XCTAssertEqual(WidgetFaceMath.loadText(nil), WidgetFaceMath.dash)
    }

    func testChargingLightsTheBandPip() {
        XCTAssertTrue(WidgetFaceMath.bandIsLit("charging"))
        XCTAssertTrue(WidgetFaceMath.bandIsLit("full"))
        XCTAssertFalse(WidgetFaceMath.bandIsLit("unplugged"))
        XCTAssertFalse(WidgetFaceMath.bandIsLit(nil))
    }

    func testSleepFallsBackToTheNightClock() {
        var glance = WidgetFaceMath.Glance.placeholder
        glance.sleepScore = nil
        glance.sleepMinutes = 432
        let read = WidgetFaceMath.today(glance, now: glance.numbersAt)
        XCTAssertEqual(read.sleepText, "7:12")
    }

    func testDistanceIsKilometresOneDecimal() {
        XCTAssertEqual(WidgetFaceMath.kmText(6_200), "6.2")
        XCTAssertEqual(WidgetFaceMath.kmText(nil), WidgetFaceMath.dash)
    }
}
