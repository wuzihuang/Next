import XCTest
@testable import NextBodySyncCore

final class BatteryDrainMathTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testDischargeProgressHoldsThenFalls() {
        XCTAssertEqual(BatteryDrainMath.progress(0, rising: false), 0, accuracy: 0.0001)
        XCTAssertEqual(BatteryDrainMath.progress(1, rising: false), 1, accuracy: 0.0001)
        XCTAssertLessThan(BatteryDrainMath.progress(0.5, rising: false), 0.5)
    }

    func testChargeProgressClimbsThenTapers() {
        XCTAssertEqual(BatteryDrainMath.progress(0, rising: true), 0, accuracy: 0.0001)
        XCTAssertEqual(BatteryDrainMath.progress(1, rising: true), 1, accuracy: 0.0001)
        XCTAssertGreaterThan(BatteryDrainMath.progress(0.5, rising: true), 0.5)
    }

    func testDrainRateLearnsFromUnpluggedDrops() {
        let samples = [
            obs(t0, 90),
            obs(t0.addingTimeInterval(3600), 88),
            obs(t0.addingTimeInterval(7200), 86),
        ]
        XCTAssertEqual(BatteryDrainMath.drainRate(in: samples, yMax: 100), 2, accuracy: 0.01)
    }

    func testDrainRateFallsBackToThePackWhenNothingDropped() {
        let samples = [obs(t0, 80)]
        XCTAssertEqual(
            BatteryDrainMath.drainRate(in: samples, yMax: 100),
            100 / BatteryDrainMath.packHours,
            accuracy: 0.0001)
    }

    func testProjectDropsAnUnpluggedReadingAndLiftsACharge() {
        let unplugged = BatteryPoint(at: t0, value: 80, charge: .unplugged)
        let charging = BatteryPoint(at: t0, value: 40, charge: .charging)
        let hour = t0.addingTimeInterval(3600)
        XCTAssertEqual(
            BatteryDrainMath.project(from: unplugged, to: hour, yMax: 100, drainPerHour: 2),
            78, accuracy: 0.01)
        XCTAssertEqual(
            BatteryDrainMath.project(from: charging, to: hour, yMax: 100, drainPerHour: 2),
            80, accuracy: 0.01)
    }

    func testInteriorCurveOmitsTheEndsAndBends() {
        let start = BatteryPoint(at: t0, value: 80, charge: .unplugged)
        let end = BatteryPoint(at: t0.addingTimeInterval(9 * 3600), value: 70, charge: .unplugged)
        let mid = BatteryDrainMath.interiorCurve(from: start, to: end)
        XCTAssertFalse(mid.isEmpty)
        XCTAssertTrue(mid.allSatisfy(\.estimated))
        XCTAssertGreaterThan(mid.first!.at, start.at)
        XCTAssertLessThan(mid.last!.at, end.at)
        let half = t0.addingTimeInterval(4.5 * 3600)
        let nearest = mid.min {
            abs($0.at.timeIntervalSince(half)) < abs($1.at.timeIntervalSince(half))
        }
        XCTAssertNotEqual(nearest?.value ?? 75, 75, accuracy: 0.15)
    }

    func testCollapseDropsAnUnknownGhostDipDuringCharge() {
        // Copied from zihuang's iPhone log: 30 charging → 23 unknown → 31 charging.
        let samples = [
            obs(t0, 30, .charging),
            BatteryObservation(at: t0.addingTimeInterval(29.7), isPercent: true,
                               percent: 23, level: nil, charge: .unknown, connected: true),
            obs(t0.addingTimeInterval(29.9), 31, .charging),
            obs(t0.addingTimeInterval(90), 32, .unknown),
            obs(t0.addingTimeInterval(90.2), 32, .charging),
        ]
        XCTAssertEqual(BatteryDrainMath.collapse(samples).compactMap(\.percent), [30, 31, 32])
    }

    func testCollapseKeepsTheLaterPacketOfAFirstConnectCliff() {
        let noon = t0.addingTimeInterval(9 * 3600)
        let stale = BatteryObservation(at: noon, isPercent: true, percent: 80, level: nil,
                                       charge: .unplugged, connected: true)
        let fresh = BatteryObservation(at: noon.addingTimeInterval(2), isPercent: true,
                                       percent: 46, level: nil, charge: .unplugged, connected: true)
        let kept = BatteryDrainMath.collapse([
            BatteryObservation(at: t0, isPercent: true, percent: 80, level: nil,
                               charge: .unplugged, connected: true),
            stale, fresh,
        ])
        XCTAssertEqual(kept.map(\.percent), [80, 46])
    }

    func testScrubDropsEstimatedPointsOnTopOfAHeardPacket() {
        let heard = BatteryPoint(at: t0, value: 80, charge: .unplugged)
        let ghost = BatteryPoint(at: t0.addingTimeInterval(30), value: 40,
                                 charge: .unplugged, estimated: true)
        let later = BatteryPoint(at: t0.addingTimeInterval(3600), value: 70,
                                 charge: .unplugged, estimated: true)
        let kept = BatteryDrainMath.scrub([heard, ghost, later])
        XCTAssertEqual(kept.map(\.value), [80, 70])
    }

    func testClipKeepsTheOverlapWithTheWindow() {
        let spans = BatteryDrainMath.clip(
            [BatterySpan(start: t0.addingTimeInterval(-3600),
                         end: t0.addingTimeInterval(3600))],
            from: t0, to: t0.addingTimeInterval(7200))
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].start, t0)
        XCTAssertEqual(spans[0].end, t0.addingTimeInterval(3600))
    }

    func testAShortSpanHasNoInterior() {
        let start = BatteryPoint(at: t0, value: 80, charge: .unplugged)
        let end = BatteryPoint(at: t0.addingTimeInterval(60), value: 79, charge: .unplugged)
        XCTAssertTrue(BatteryDrainMath.interiorCurve(from: start, to: end).isEmpty)
    }

    private func obs(_ at: Date, _ percent: Int,
                     _ charge: BatteryObservation.Charge = .unplugged) -> BatteryObservation {
        BatteryObservation(at: at, isPercent: true, percent: percent, level: nil,
                           charge: charge, connected: true)
    }
}
