import XCTest
@testable import NextBodySyncCore

/// 13 · WHY <n> as a ledger: four integer rows whose running balance ends on the number
/// at the top of the page, whatever rounding the server's doubles carried.
final class BodyBatteryLedgerMathTests: XCTestCase {

    func testRowsRunFromAnchorToCurrent() {
        let rows = BodyBatteryLedgerMath.rows(anchor: 46, recovery: 38, awake: -4,
                                              movement: -6, stress: -2, current: 72)
        XCTAssertEqual(rows.map(\.delta), [38, -4, -6, -2])
        XCTAssertEqual(rows.map(\.balance), [84, 80, 74, 72])
        XCTAssertEqual(rows.map(\.term), [.recovery, .awake, .movement, .stress])
    }

    func testRoundingResidualLandsOnTheWidestTerm() {
        // 37.6 − 4.4 − 6.4 − 1.6 = 25.2 → published 46 → 71. Rounded rows give 38−4−6−2 = 26.
        let rows = BodyBatteryLedgerMath.rows(anchor: 46, recovery: 37.6, awake: -4.4,
                                              movement: -6.4, stress: -1.6, current: 71)
        XCTAssertEqual(rows.map(\.delta), [37, -4, -6, -2])
        XCTAssertEqual(rows.last?.balance, 71)
    }

    func testAResidualNeverBreaksTheClose() {
        for current in 60...75 {
            let rows = BodyBatteryLedgerMath.rows(anchor: 46, recovery: 37.5, awake: -4.5,
                                                  movement: -6.5, stress: -1.5, current: current)
            XCTAssertEqual(rows.last?.balance, current)
            XCTAssertEqual(46 + rows.map(\.delta).reduce(0, +), current)
        }
    }

    func testAwakeMinutesNeedARecordedWake() {
        let day = UserDay.containing(Date())
        let wake = day.start.addingTimeInterval(7 * 3600 + 12 * 60)
        let observed = day.start.addingTimeInterval(14 * 3600 + 33 * 60)
        XCTAssertEqual(BodyBatteryLedgerMath.awakeMinutes(wakeAt: wake, dayStart: day.start,
                                                          observedAt: observed), 440)
        XCTAssertNil(BodyBatteryLedgerMath.awakeMinutes(wakeAt: nil, dayStart: day.start,
                                                        observedAt: observed))
        XCTAssertNil(BodyBatteryLedgerMath.awakeMinutes(wakeAt: wake, dayStart: day.start,
                                                        observedAt: nil))
        // A wake before the user day opened counts from the day's own start.
        let early = day.start.addingTimeInterval(-3600)
        XCTAssertEqual(BodyBatteryLedgerMath.awakeMinutes(wakeAt: early, dayStart: day.start,
                                                          observedAt: day.start.addingTimeInterval(3600)), 60)
    }

    func testStressedMinutesCountTicksAboveFortyAndStayNilWithoutAnIndex() {
        let t = Date()
        let ticks = [
            VitalSample(ts: t, hr: 70, stress: 55),
            VitalSample(ts: t.addingTimeInterval(300), hr: 72, stress: 40),
            VitalSample(ts: t.addingTimeInterval(600), hr: 71, stress: nil),
            VitalSample(ts: t.addingTimeInterval(900), hr: 74, stress: 61),
        ]
        XCTAssertEqual(BodyBatteryLedgerMath.stressedMinutes(ticks), 10)
        XCTAssertEqual(BodyBatteryLedgerMath.stressedMinutes([VitalSample(ts: t, hr: 70, stress: 12)]), 0)
        XCTAssertNil(BodyBatteryLedgerMath.stressedMinutes([VitalSample(ts: t, hr: 70, stress: nil)]))
        XCTAssertNil(BodyBatteryLedgerMath.stressedMinutes([]))
    }

    func testPaceWordsAroundOne() {
        XCTAssertEqual(BodyBatteryLedgerMath.pace(of: 0.88), .slower)
        XCTAssertEqual(BodyBatteryLedgerMath.pace(of: 1.00), .usual)
        XCTAssertEqual(BodyBatteryLedgerMath.pace(of: 1.02), .usual)
        XCTAssertEqual(BodyBatteryLedgerMath.pace(of: 1.12), .faster)
    }
}
