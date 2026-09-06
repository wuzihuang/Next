import XCTest
@testable import NextBodySyncCore

final class FindDistanceMathTests: XCTestCase {
    func testCutsAreDistanceNotQuality() {
        XCTAssertEqual(FindDistance.from(rssi: -52), .near)
        XCTAssertEqual(FindDistance.from(rssi: -59), .near)
        XCTAssertEqual(FindDistance.from(rssi: -60), .close)
        XCTAssertEqual(FindDistance.from(rssi: -69), .close)
        XCTAssertEqual(FindDistance.from(rssi: -70), .close)
        XCTAssertEqual(FindDistance.from(rssi: -71), .away)
        XCTAssertEqual(FindDistance.from(rssi: -84), .away)
        XCTAssertEqual(FindDistance.from(rssi: -85), .away)
        XCTAssertEqual(FindDistance.from(rssi: -86), .far)
        XCTAssertEqual(FindDistance.from(rssi: -89), .far)
    }

    func testLampGlowIsAFalloffNotASingleCell() {
        XCTAssertEqual(FindDistance.glow(of: .near, current: .near), .hot)
        XCTAssertEqual(FindDistance.glow(of: .close, current: .near), .warm)
        XCTAssertEqual(FindDistance.glow(of: .away, current: .near), .off)
        XCTAssertEqual(FindDistance.glow(of: .far, current: .near), .off)
        XCTAssertEqual(FindDistance.glow(of: .close, current: .close), .hot)
        XCTAssertEqual(FindDistance.glow(of: .away, current: .close), .warm)
        XCTAssertEqual(FindDistance.glow(of: .near, current: .close), .off)
        XCTAssertEqual(FindDistance.glow(of: .far, current: .far), .hot)
        XCTAssertEqual(FindDistance.glow(of: .away, current: .far), .off)
        XCTAssertEqual(FindDistance.glow(of: .near, current: nil), .off)
        XCTAssertEqual(FindDistance.glyph(-52), "−52")
        XCTAssertEqual(FindDistance.near.barsLit, 4)
        XCTAssertEqual(FindDistance.far.barsLit, 1)
    }

    func testLabelsNeverSayGoodOrPoor() {
        for distance in FindDistance.allCases {
            XCTAssertFalse(distance.label.contains("GOOD"))
            XCTAssertFalse(distance.label.contains("POOR"))
            XCTAssertFalse(distance.label.contains("MID"))
        }
        XCTAssertEqual(FindDistance.near.label, "NEAR")
        XCTAssertEqual(FindDistance.close.label, "CLOSE")
        XCTAssertEqual(FindDistance.away.label, "AWAY")
        XCTAssertEqual(FindDistance.far.label, "FAR")
    }

    func testFirmwarePhasesMatchVendorOrdinals() {
        XCTAssertEqual(FindHoopPhase.from(rawValue: 0), .unsupported)
        XCTAssertEqual(FindHoopPhase.from(rawValue: 1), .enter)
        XCTAssertEqual(FindHoopPhase.from(rawValue: 2), .exit)
        XCTAssertEqual(FindHoopPhase.from(rawValue: 3), .timeout)
        XCTAssertEqual(FindHoopPhase.from(rawValue: 9), .unsupported)
    }
}
