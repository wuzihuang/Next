import XCTest
@testable import NextBodySyncCore

/// #25 · 未佩戴 / 无数据 与真实 0% 必须是两种不同的读数。
final class BodyBatteryReadoutTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func readout(_ value: Int?, ageMinutes: Double?) -> BodyBatteryReadout {
        BodyBatteryReadoutPolicy.readout(
            value: value,
            observedAt: ageMinutes.map { now.addingTimeInterval(-$0 * 60) },
            now: now)
    }

    func testAnEmptyBatteryIsAMeasurementAndStillPrints() {
        XCTAssertEqual(readout(0, ageMinutes: 5), .reading(0, dim: false))
        XCTAssertEqual(readout(0, ageMinutes: 5).value, 0)
        XCTAssertFalse(readout(0, ageMinutes: 5).isPlaceholder)
    }

    func testAnUnwornWristIsNeverPrintedAsZero() {
        for state in [readout(nil, ageMinutes: nil), readout(nil, ageMinutes: 5),
                      readout(40, ageMinutes: nil), readout(40, ageMinutes: 6 * 60)] {
            XCTAssertTrue(state.isPlaceholder)
            XCTAssertNil(state.value, "A placeholder must not carry a number any entry could print.")
        }
    }

    func testTheStaleWindowKeepsTheNumberButDimsIt() {
        XCTAssertEqual(readout(40, ageMinutes: 89), .reading(40, dim: false))
        XCTAssertEqual(readout(40, ageMinutes: 90), .reading(40, dim: true))
        XCTAssertEqual(readout(40, ageMinutes: 359), .reading(40, dim: true))
    }

    func testAFutureObservationIsABrokenClockNotAFreshReading() {
        XCTAssertTrue(readout(40, ageMinutes: -1).isPlaceholder)
    }

    func testTheLastRealTickSurvivesInThePlaceholder() {
        guard case let .notWorn(since) = readout(40, ageMinutes: 7 * 60) else {
            return XCTFail("A six-hour-old tick is a placeholder.")
        }
        XCTAssertEqual(since, now.addingTimeInterval(-7 * 3600))
    }
}
