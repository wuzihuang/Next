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
        XCTAssertFalse(read.batteryDim)
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
        XCTAssertEqual(read.responseText, "108")
        XCTAssertEqual(read.hrvText, "54")
        XCTAssertEqual(read.spo2Text, "96")
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
        glance.batteryObservedAt = glance.numbersAt
        let now = Date(timeIntervalSince1970: WidgetFaceMath.staleAfter + 1)
        let read = WidgetFaceMath.today(glance, now: now)
        XCTAssertTrue(read.stale)
        // The reserve score dims at ninety minutes instead of withdrawing — the app
        // still prints it until six hours, and the two faces must not disagree.
        XCTAssertEqual(read.batteryText, "72")
        XCTAssertTrue(read.batteryDim)
        XCTAssertEqual(read.batteryProgress, 0.72, accuracy: 0.0001)
        XCTAssertEqual(read.loadText, WidgetFaceMath.dash)
        XCTAssertEqual(read.eatenText, WidgetFaceMath.dash)
        XCTAssertEqual(read.clock, WidgetFaceMath.clockText(glance.numbersAt))
        XCTAssertEqual(read.bandText, "82%")
        XCTAssertEqual(read.heartText, WidgetFaceMath.dash)
        XCTAssertEqual(read.stressText, WidgetFaceMath.dash)
        XCTAssertEqual(read.sleepText, "78")
        XCTAssertEqual(read.activeText, WidgetFaceMath.dash)
        XCTAssertEqual(read.stepsText, WidgetFaceMath.dash)
        XCTAssertEqual(read.distanceText, WidgetFaceMath.dash)
        XCTAssertEqual(read.responseText, WidgetFaceMath.dash)
        XCTAssertEqual(read.hrvText, "54")
        XCTAssertEqual(read.spo2Text, "96")
        XCTAssertEqual(read.stamp, WidgetFaceMath.clockText(glance.numbersAt))
    }

    func testStaleAlsoWithdrawsALoggedEaten() {
        var glance = WidgetFaceMath.Glance.placeholder
        glance.numbersAt = Date(timeIntervalSince1970: 0)
        glance.batteryObservedAt = glance.numbersAt
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
        XCTAssertEqual(read.responseText, WidgetFaceMath.dash)
        XCTAssertEqual(read.hrvText, WidgetFaceMath.dash)
        XCTAssertEqual(read.spo2Text, WidgetFaceMath.dash)
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

    func testMealRefreshCannotRenewAnOldBodyBattery() {
        var glance = WidgetFaceMath.Glance.placeholder
        let now = glance.numbersAt.addingTimeInterval(2 * 3600)
        glance.numbersAt = now
        glance.eaten = 1_500
        let read = WidgetFaceMath.today(glance, now: now)
        // A fresh meal makes the rest of the face live again; the two-hour-old
        // reserve score stays on its own clock and only dims.
        XCTAssertEqual(read.batteryText, "72")
        XCTAssertTrue(read.batteryDim)
        XCTAssertEqual(read.eatenText, "1,500")
        XCTAssertEqual(read.loadText, "12.4")
    }

    /// The widget's three reserve states are `TickFreshness`'s: lit under ninety
    /// minutes, dim to six hours, withdrawn after — same rule the app applies in
    /// `Metrics.bodyBatteryForDisplay`.
    func testBodyBatteryFollowsTheAppsThreeFreshnessStates() {
        var glance = WidgetFaceMath.Glance.placeholder
        let observed = glance.numbersAt
        glance.batteryObservedAt = observed

        let lit = WidgetFaceMath.today(
            glance, now: observed.addingTimeInterval(WidgetFaceMath.staleAfter - 1))
        XCTAssertEqual(lit.batteryText, "72")
        XCTAssertFalse(lit.batteryDim)

        let dimmed = WidgetFaceMath.today(
            glance, now: observed.addingTimeInterval(92 * 60))
        XCTAssertEqual(dimmed.batteryText, "72")
        XCTAssertTrue(dimmed.batteryDim)
        XCTAssertEqual(dimmed.batteryProgress, 0.72, accuracy: 0.0001)

        let edge = WidgetFaceMath.today(
            glance, now: observed.addingTimeInterval(WidgetFaceMath.goneAfter - 1))
        XCTAssertEqual(edge.batteryText, "72")
        XCTAssertTrue(edge.batteryDim)

        let gone = WidgetFaceMath.today(
            glance, now: observed.addingTimeInterval(WidgetFaceMath.goneAfter))
        XCTAssertEqual(gone.batteryText, WidgetFaceMath.dash)
        XCTAssertFalse(gone.batteryDim)
        XCTAssertEqual(gone.batteryProgress, 0)
    }

    func testAFutureReserveTimestampIsNotATick() {
        var glance = WidgetFaceMath.Glance.placeholder
        glance.batteryObservedAt = glance.numbersAt.addingTimeInterval(60)
        let read = WidgetFaceMath.today(glance, now: glance.numbersAt)
        XCTAssertEqual(read.batteryText, WidgetFaceMath.dash)
        XCTAssertFalse(read.batteryDim)
        XCTAssertEqual(read.batteryProgress, 0)
    }

    /// A glance written before `batteryObservedAt` existed cannot prove the reserve
    /// score's age, so it borrows the live window rather than blanking a number the
    /// app is still showing.
    func testLegacyGlanceWithoutReserveTimestampFallsBackToTheLiveWindow() throws {
        var glance = WidgetFaceMath.Glance.placeholder
        glance.batteryObservedAt = nil
        let encoded = try JSONEncoder().encode(glance)
        let decoded = try JSONDecoder().decode(WidgetFaceMath.Glance.self, from: encoded)
        XCTAssertNil(decoded.batteryObservedAt)

        let fresh = WidgetFaceMath.today(decoded, now: decoded.numbersAt)
        XCTAssertEqual(fresh.batteryText, "72")
        XCTAssertFalse(fresh.batteryDim)
        XCTAssertEqual(fresh.batteryProgress, 0.72, accuracy: 0.0001)

        let stale = WidgetFaceMath.today(
            decoded, now: decoded.numbersAt.addingTimeInterval(WidgetFaceMath.staleAfter))
        XCTAssertEqual(stale.batteryText, WidgetFaceMath.dash)
        XCTAssertFalse(stale.batteryDim)
        XCTAssertEqual(stale.batteryProgress, 0)
    }

    func testSignedOutBatteryIsNeverDim() {
        var glance = WidgetFaceMath.Glance.placeholder
        glance.signedIn = false
        glance.batteryObservedAt = glance.numbersAt.addingTimeInterval(-2 * 3600)
        let read = WidgetFaceMath.today(glance, now: glance.numbersAt)
        XCTAssertEqual(read.batteryText, WidgetFaceMath.dash)
        XCTAssertFalse(read.batteryDim)
    }

    func testBatteryExpirySchedulesReloadEvenWhenOtherNumbersAreNew() {
        var glance = WidgetFaceMath.Glance.placeholder
        let start = glance.numbersAt
        let now = start.addingTimeInterval(80 * 60)
        glance.numbersAt = now
        XCTAssertEqual(WidgetFaceMath.nextReload(after: glance, now: now),
                       start.addingTimeInterval(WidgetFaceMath.staleAfter))
    }

    /// Past the dim edge the next thing that changes is the withdraw, and the
    /// timeline has to be awake for it — the fifteen-minute tick would land later.
    func testTheSixHourWithdrawIsAlsoAScheduledEdge() {
        var glance = WidgetFaceMath.Glance.placeholder
        let start = glance.numbersAt
        let now = start.addingTimeInterval(WidgetFaceMath.goneAfter - 5 * 60)
        glance.numbersAt = now
        XCTAssertEqual(WidgetFaceMath.nextReload(after: glance, now: now),
                       start.addingTimeInterval(WidgetFaceMath.goneAfter))
    }
}
