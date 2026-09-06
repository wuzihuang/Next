import XCTest
@testable import NextBodySyncCore

final class BatteryLogTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testIdenticalReadingInsideThePlateauIsDropped() {
        let first = BatteryLog.record([], at: t0, isPercent: true, percent: 82,
                                      level: nil, charge: .unplugged, connected: true)
        let again = BatteryLog.record(first, at: t0.addingTimeInterval(60), isPercent: true,
                                      percent: 82, level: nil, charge: .unplugged, connected: true)
        XCTAssertEqual(again.count, 1)
    }

    func testChargingAtOneHundredIsRecordedAsFull() {
        let row = BatteryLog.record([], at: t0, isPercent: true, percent: 100,
                                    level: nil, charge: .charging, connected: true)
        XCTAssertEqual(row.map(\.charge), [.full])
        XCTAssertEqual(row.first?.percent, 100)
    }

    func testChargingAtNinetyNineStaysCharging() {
        let row = BatteryLog.record([], at: t0, isPercent: true, percent: 99,
                                    level: nil, charge: .charging, connected: true)
        XCTAssertEqual(row.map(\.charge), [.charging])
    }

    func testChargeSwitchIsKeptEvenWhenPercentDoesNotMove() {
        let first = BatteryLog.record([], at: t0, isPercent: true, percent: 40,
                                      level: nil, charge: .unplugged, connected: true)
        let plugged = BatteryLog.record(first, at: t0.addingTimeInterval(5), isPercent: true,
                                        percent: 40, level: nil, charge: .charging, connected: true)
        XCTAssertEqual(plugged.map(\.charge), [.unplugged, .charging])
    }

    func testDisconnectIsKeptAtTheSamePercent() {
        let on = BatteryLog.record([], at: t0, isPercent: true, percent: 70,
                                   level: nil, charge: .unplugged, connected: true)
        let off = BatteryLog.record(on, at: t0.addingTimeInterval(10), isPercent: true,
                                    percent: 70, level: nil, charge: .unplugged, connected: false)
        XCTAssertEqual(off.map(\.connected), [true, false])
    }

    func testAQuietHourStillLeavesAKeepalivePoint() {
        let first = BatteryLog.record([], at: t0, isPercent: true, percent: 82,
                                      level: nil, charge: .unplugged, connected: true)
        let later = BatteryLog.record(first, at: t0.addingTimeInterval(30 * 60), isPercent: true,
                                      percent: 82, level: nil, charge: .unplugged, connected: true)
        XCTAssertEqual(later.count, 2)
    }

    func testOldSamplesFallOffTheThirtyDayKeep() {
        let old = BatteryLog.record([], at: t0.addingTimeInterval(-31 * 24 * 3600),
                                    isPercent: true, percent: 10, level: nil,
                                    charge: .unplugged, connected: true)
        let now = BatteryLog.record(old, at: t0, isPercent: true, percent: 80,
                                    level: nil, charge: .unplugged, connected: true)
        XCTAssertEqual(now.map(\.percent), [80])
    }

    func testATwentyNineDaySampleSurvivesTheKeep() {
        let old = BatteryLog.record([], at: t0.addingTimeInterval(-29 * 24 * 3600),
                                    isPercent: true, percent: 10, level: nil,
                                    charge: .unplugged, connected: true)
        let now = BatteryLog.record(old, at: t0, isPercent: true, percent: 80,
                                    level: nil, charge: .unplugged, connected: true)
        XCTAssertEqual(now.map(\.percent), [10, 80])
    }

    func testWindowsAreRollingHours() {
        let day = BatteryLog.window(endingAt: t0, range: .day)
        let week = BatteryLog.window(endingAt: t0, range: .week)
        let month = BatteryLog.window(endingAt: t0, range: .month)
        XCTAssertEqual(day.end.timeIntervalSince(day.start), 24 * 3600, accuracy: 0.001)
        XCTAssertEqual(week.end.timeIntervalSince(week.start), 7 * 24 * 3600, accuracy: 0.001)
        XCTAssertEqual(month.end.timeIntervalSince(month.start), 30 * 24 * 3600, accuracy: 0.001)
        XCTAssertEqual(DetailWindow(.battery, .day).periodKey, "LAST 24H")
        XCTAssertEqual(DetailWindow(.battery, .week).periodKey, "LAST 7 DAYS")
        XCTAssertEqual(DetailWindow(.battery, .month).periodKey, "LAST 30 DAYS")
    }

    func testPlotFillsAQuietStretchWithADrainCurve() {
        let samples = [
            obs(t0, 80, .unplugged, true),
            obs(t0.addingTimeInterval(3600), 78, .unplugged, true),
            obs(t0.addingTimeInterval(3600), 78, .unplugged, false),
            obs(t0.addingTimeInterval(7200), 77, .unplugged, true),
        ]
        let end = t0.addingTimeInterval(10_800)
        let plot = BatteryLog.plot(samples, from: t0, to: end)
        let points = plot.points
        XCTAssertEqual(points.first?.value, 80)
        XCTAssertEqual(points.last?.at, end)
        XCTAssertEqual(points.last?.estimated, true)
        XCTAssertEqual(points.last!.value, 75, accuracy: 0.01)
        XCTAssertTrue(points.contains { $0.value == 77 && !$0.estimated })
        XCTAssertGreaterThan(points.filter(\.estimated).count, 2)
        XCTAssertEqual(plot.high, 80)
        let midAt = t0.addingTimeInterval(1800)
        let mid = points.min {
            abs($0.at.timeIntervalSince(midAt)) < abs($1.at.timeIntervalSince(midAt))
        }
        XCTAssertNotEqual(mid!.value, 79, accuracy: 0.05)
    }

    func testRecordDropsAValuedUnknownPacket() {
        let first = BatteryLog.record([], at: t0, isPercent: true, percent: 30,
                                      level: nil, charge: .charging, connected: true)
        let ghost = BatteryLog.record(first, at: t0.addingTimeInterval(10 * 3600),
                                      isPercent: true, percent: 23, level: nil,
                                      charge: .unknown, connected: true)
        XCTAssertEqual(ghost.map(\.percent), [30])
        XCTAssertEqual(ghost.map(\.charge), [.charging])
    }

    func testRecordStillKeepsAnUnknownLinkRowWithNoReading() {
        let first = BatteryLog.record([], at: t0, isPercent: true, percent: 70,
                                      level: nil, charge: .unplugged, connected: true)
        let link = BatteryLog.record(first, at: t0.addingTimeInterval(60),
                                     isPercent: true, percent: nil, level: nil,
                                     charge: .unknown, connected: true)
        XCTAssertEqual(link.count, 2)
        XCTAssertNil(link.last?.percent)
        XCTAssertEqual(link.last?.charge, .unknown)
    }

    func testUnknownChargeGhostsDoNotDipTheChargeClimb() {
        let samples = [
            obs(t0, 30, .charging, true),
            obs(t0.addingTimeInterval(29.7), 23, .unknown, true),
            obs(t0.addingTimeInterval(29.9), 31, .charging, true),
            obs(t0.addingTimeInterval(80), 37, .charging, true),
            obs(t0.addingTimeInterval(124.8), 32, .unknown, true),
            obs(t0.addingTimeInterval(125), 39, .charging, true),
        ]
        let plot = BatteryLog.plot(samples, from: t0, to: t0.addingTimeInterval(180))
        let heard = plot.points.filter { !$0.estimated }.map(\.value)
        XCTAssertEqual(heard, [30, 31, 37, 39])
        XCTAssertFalse(heard.contains { $0 < 30 })
    }

    func testAFirstConnectCliffDoesNotDrawANoonDrop() {
        let noon = t0.addingTimeInterval(9 * 3600)
        let samples = [
            obs(t0, 80, .unplugged, true),
            obs(noon, 80, .unplugged, true),
            obs(noon.addingTimeInterval(2), 46, .unplugged, true),
        ]
        let plot = BatteryLog.plot(samples, from: t0, to: noon.addingTimeInterval(30))
        let heard = plot.points.filter { !$0.estimated }
        XCTAssertEqual(heard.map(\.value), [80, 46])
        XCTAssertFalse(plot.points.contains { $0.estimated && abs($0.at.timeIntervalSince(noon)) < 120 })
        XCTAssertGreaterThan(plot.low ?? 0, 40)
    }

    func testAnOpenDisconnectDoesNotHoldTheLastPercentToNow() {
        let noon = t0.addingTimeInterval(9 * 3600)
        let samples = [obs(t0, 80, .unplugged, true)]
        let plot = BatteryLog.plot(samples, from: t0, to: noon)
        XCTAssertEqual(plot.points.last?.at, noon)
        XCTAssertEqual(plot.points.last?.estimated, true)
        XCTAssertLessThan(plot.points.last?.value ?? 80, 80)
        XCTAssertGreaterThan(plot.points.filter(\.estimated).count, 4)
        let half = t0.addingTimeInterval(4.5 * 3600)
        let nearest = plot.points.min {
            abs($0.at.timeIntervalSince(half)) < abs($1.at.timeIntervalSince(half))
        }
        let projected = plot.points.last!.value
        let linear = 80 + (projected - 80) * 0.5
        XCTAssertNotEqual(nearest?.value ?? linear, linear, accuracy: 0.15)
    }

    func testPlotPaintsChargingAsAClosedSpan() {
        let samples = [
            obs(t0, 40, .unplugged, true),
            obs(t0.addingTimeInterval(60), 40, .charging, true),
            obs(t0.addingTimeInterval(3600), 70, .charging, true),
            obs(t0.addingTimeInterval(7200), 100, .full, true),
        ]
        let plot = BatteryLog.plot(samples, from: t0, to: t0.addingTimeInterval(7200))
        XCTAssertEqual(plot.charging.count, 1)
        XCTAssertEqual(plot.charging[0].start, t0.addingTimeInterval(60))
        XCTAssertEqual(plot.charging[0].end, t0.addingTimeInterval(7200))
    }

    func testBarsStayOnAFourStepRuler() {
        let samples = [
            BatteryObservation(at: t0, isPercent: false, percent: nil, level: 3,
                               charge: .unplugged, connected: true),
        ]
        let plot = BatteryLog.plot(samples, from: t0, to: t0.addingTimeInterval(60))
        XCTAssertFalse(plot.isPercent)
        XCTAssertEqual(plot.yMax, 4)
        XCTAssertEqual(plot.high, 3)
    }

    /// A connect/disconnect row carries no reading. Letting it vote put a bars-only band
    /// on a 0–100 ruler, where 3 bars draw as 3 %.
    func testLinkRowsWithNoReadingDoNotDecideTheUnit() {
        let samples = [
            BatteryObservation(at: t0, isPercent: true, percent: nil, level: nil,
                               charge: .unknown, connected: false),
            BatteryObservation(at: t0.addingTimeInterval(60), isPercent: true, percent: nil,
                               level: nil, charge: .unknown, connected: true),
            BatteryObservation(at: t0.addingTimeInterval(120), isPercent: true, percent: nil,
                               level: nil, charge: .unknown, connected: false),
            BatteryObservation(at: t0.addingTimeInterval(180), isPercent: false, percent: nil,
                               level: 3, charge: .unplugged, connected: true),
        ]
        let plot = BatteryLog.plot(samples, from: t0, to: t0.addingTimeInterval(240))
        XCTAssertFalse(plot.isPercent)
        XCTAssertEqual(plot.yMax, 4)
        XCTAssertEqual(plot.high, 3)
    }

    func testASampleInTheOtherUnitBreaksTheLineInsteadOfDiving() {
        let samples = [
            obs(t0, 80, .unplugged, true),
            BatteryObservation(at: t0.addingTimeInterval(60), isPercent: false, percent: nil,
                               level: 3, charge: .unplugged, connected: true),
            obs(t0.addingTimeInterval(120), 78, .unplugged, true),
        ]
        let plot = BatteryLog.plot(samples, from: t0, to: t0.addingTimeInterval(120))
        XCTAssertTrue(plot.isPercent)
        XCTAssertEqual(plot.runs.count, 2)
        XCTAssertEqual(plot.low, 78)
        XCTAssertFalse(plot.points.contains { $0.value == 3 })
    }

    func testChargingRightNowIsStillShadedWhenTheLastReadingLandsOnTheEdge() {
        let end = t0.addingTimeInterval(3600)
        let samples = [
            obs(t0, 40, .charging, true),
            obs(end, 62, .charging, true),
        ]
        let plot = BatteryLog.plot(samples, from: t0, to: end)
        XCTAssertEqual(plot.charging.count, 1)
        XCTAssertEqual(plot.charging[0].start, t0)
        XCTAssertEqual(plot.charging[0].end, end)
    }

    func testSeedEndsOnTheLivePercentAndContainsAChargeCycle() {
        let seed = BatteryLog.seed(now: t0, percent: 82)
        XCTAssertEqual(seed.last?.percent, 82)
        XCTAssertTrue(seed.contains { $0.charge == .charging })
        XCTAssertTrue(seed.contains { $0.charge == .unplugged })
        XCTAssertTrue(seed.contains { $0.connected == false })
        let window = BatteryLog.window(endingAt: t0)
        let plot = BatteryLog.plot(seed, from: window.start, to: window.end)
        XCTAssertGreaterThan(plot.runs.flatMap { $0 }.count, 8)
        XCTAssertFalse(plot.charging.isEmpty)
        XCTAssertEqual(plot.runs.last?.last?.value, 82)
        XCTAssertLessThanOrEqual(seed.first?.at ?? t0, t0.addingTimeInterval(-28 * 24 * 3600))
        let month = BatteryLog.window(endingAt: t0, range: .month)
        let monthPlot = BatteryLog.plot(seed, from: month.start, to: month.end)
        XCTAssertGreaterThan(monthPlot.charging.count, 4)
    }

    func testLastPlugIsTheMostRecentChargingSample() {
        let samples = [
            obs(t0, 80, .unplugged, true),
            obs(t0.addingTimeInterval(60), 80, .charging, true),
            obs(t0.addingTimeInterval(120), 90, .full, true),
            obs(t0.addingTimeInterval(180), 88, .unplugged, true),
        ]
        XCTAssertEqual(BatteryLog.lastPlug(in: samples), t0.addingTimeInterval(60))
        XCTAssertNil(BatteryLog.lastPlug(in: [obs(t0, 80, .unplugged, true)]))
    }

    func testLastPlugHonoursTheWindow() {
        let samples = [
            obs(t0, 40, .charging, true),
            obs(t0.addingTimeInterval(2 * 24 * 3600), 50, .charging, true),
        ]
        XCTAssertEqual(
            BatteryLog.lastPlug(in: samples, from: t0.addingTimeInterval(24 * 3600),
                                to: t0.addingTimeInterval(3 * 24 * 3600)),
            t0.addingTimeInterval(2 * 24 * 3600))
        XCTAssertNil(BatteryLog.lastPlug(
            in: samples,
            from: t0.addingTimeInterval(3 * 24 * 3600),
            to: t0.addingTimeInterval(4 * 24 * 3600)))
    }

    func testLastLinkIsTheMostRecentConnectedSample() {
        let samples = [
            obs(t0, 80, .unplugged, true),
            obs(t0.addingTimeInterval(60), 80, .unplugged, false),
            obs(t0.addingTimeInterval(120), 79, .unplugged, true),
        ]
        XCTAssertEqual(BatteryLog.lastLink(in: samples), t0.addingTimeInterval(120))
        XCTAssertNil(BatteryLog.lastLink(in: [obs(t0, 80, .unplugged, false)]))
    }

    func testStoreRoundTripKeepsChargeSwitches() {
        let owner = "test.\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: BatteryLogStore.key(owner)) }
        let samples = BatteryLog.seed(now: t0, percent: 64)
        BatteryLogStore.save(samples, owner: owner, defaults: defaults)
        let loaded = BatteryLogStore.load(owner: owner, defaults: defaults)
        XCTAssertEqual(loaded.map(\.percent), samples.map(\.percent))
        XCTAssertEqual(loaded.map(\.charge), samples.map(\.charge))
    }

    private func obs(_ at: Date, _ percent: Int, _ charge: BatteryObservation.Charge,
                     _ connected: Bool) -> BatteryObservation {
        BatteryObservation(at: at, isPercent: true, percent: percent, level: nil,
                           charge: charge, connected: connected)
    }
}
