import XCTest
@testable import NextBodySyncCore

final class IdlePlateLockTests: XCTestCase {
    private let wearer = "wearer-lock-tests"
    private let day = "2026-09-13"
    private let next = "2026-09-14"

    func testSameWearerAndUserDayYieldsTheSamePlateOnFiveAppears() {
        var stored: IdlePlateLock.Snapshot?
        var plates: [Int] = []
        for i in 0..<5 {
            stored = IdlePlateLock.appear(
                wearer: wearer, day: day, stored: stored, idleVisible: false,
                hour: 8 + i, bpm: 60 + i * 10)
            plates.append(stored!.plate)
        }
        XCTAssertEqual(Set(plates).count, 1)
        XCTAssertEqual(stored?.day, day)
        XCTAssertEqual(stored?.lockedBy, .daily)
        XCTAssertFalse(IdlePlateLock.forbidden.contains(plates[0]))
        XCTAssertTrue(IdlePlateLock.dayPool.contains(plates[0]))
    }

    func testHourAndBpmDoNotChangeThePlate() {
        let a = IdlePlateLock.appear(
            wearer: wearer, day: day, stored: nil, idleVisible: false,
            hour: 8, bpm: 58)
        let b = IdlePlateLock.appear(
            wearer: wearer, day: day, stored: a, idleVisible: false,
            hour: 21, bpm: 172)
        XCTAssertEqual(a.plate, b.plate)
        XCTAssertEqual(a.day, b.day)
    }

    func testNewUserDayTakesOnTheNextAppearAndSkipsYesterday() {
        let first = IdlePlateLock.appear(
            wearer: wearer, day: day, stored: nil, idleVisible: false)
        let watching = IdlePlateLock.appear(
            wearer: wearer, day: next, stored: first, idleVisible: true,
            hour: 0, bpm: 90)
        XCTAssertEqual(watching.plate, first.plate)
        XCTAssertEqual(watching.day, first.day)

        let flipped = IdlePlateLock.appear(
            wearer: wearer, day: next, stored: watching, idleVisible: false)
        XCTAssertEqual(flipped.day, next)
        XCTAssertNotEqual(flipped.plate, first.plate)
        XCTAssertTrue(IdlePlateLock.dayPool.contains(flipped.plate))
    }

    func testDailyDrawAvoidsYesterdaysPlate() {
        let today = IdlePlateLock.dailyPlate(
            wearer: wearer, day: day, yesterday: nil)
        let tomorrow = IdlePlateLock.dailyPlate(
            wearer: wearer, day: next, yesterday: today)
        XCTAssertNotEqual(tomorrow, today)
    }

    func testForbiddenPlatesAreNeverDrawnDaily() {
        for d in 0..<40 {
            let plate = IdlePlateLock.dailyPlate(
                wearer: wearer, day: String(format: "2026-09-%02d", 1 + d % 28),
                yesterday: nil)
            XCTAssertFalse(IdlePlateLock.forbidden.contains(plate), "drew forbidden \(plate)")
            XCTAssertFalse([11, 20, 25].contains(plate), "event plate \(plate) in day pool")
        }
    }

    func testLowReserveMapsToPlate25AndDoesNotRevert() {
        var snap = IdlePlateLock.appear(
            wearer: wearer, day: day, stored: nil, idleVisible: false)
        XCTAssertEqual(IdlePlateLock.edge(
            reserve: 22, wakeReserve: 70, bandPercent: 80, charging: false,
            disconnectedFor: 0), .lowReserve)
        snap = IdlePlateLock.applyEvent(.lowReserve, stored: snap, day: day)
        XCTAssertEqual(snap.plate, 25)
        XCTAssertEqual(snap.lockedBy, .event)

        let recovered = IdlePlateLock.appear(
            wearer: wearer, day: day, stored: snap, idleVisible: false,
            hour: 18, bpm: 64)
        XCTAssertEqual(recovered.plate, 25)
        XCTAssertEqual(recovered.lockedBy, .event)
        XCTAssertNil(IdlePlateLock.edge(
            reserve: 48, wakeReserve: 70, bandPercent: 80, charging: false,
            disconnectedFor: 0))
    }

    func testLowBandChargeMapsToPlate11() {
        XCTAssertEqual(IdlePlateLock.edge(
            reserve: 60, wakeReserve: 70, bandPercent: 12, charging: false,
            disconnectedFor: 0), .lowBandCharge)
        XCTAssertNil(IdlePlateLock.edge(
            reserve: 60, wakeReserve: 70, bandPercent: 12, charging: true,
            disconnectedFor: 0))
        var snap = IdlePlateLock.appear(
            wearer: wearer, day: day, stored: nil, idleVisible: false)
        snap = IdlePlateLock.applyEvent(.lowBandCharge, stored: snap, day: day)
        XCTAssertEqual(snap.plate, 11)
    }

    func testDisconnectSixtySecondsIsNotBandAway() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let stamp = now.addingTimeInterval(-60)
        let dt = IdlePlateLock.disconnectedFor(
            bound: true, connected: false, disconnectStamp: stamp, now: now)
        XCTAssertEqual(dt, 60, accuracy: 0.001)
        XCTAssertNil(IdlePlateLock.edge(
            reserve: 60, wakeReserve: 70, bandPercent: 80, charging: false,
            disconnectedFor: dt))
        let snap = IdlePlateLock.appear(
            wearer: wearer, day: day, stored: nil, idleVisible: false)
        XCTAssertNotEqual(snap.plate, 20)
        XCTAssertEqual(snap.lockedBy, .daily)
    }

    func testBleDownFourHoursWhenBoundMapsToPlate20() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let stamp = now.addingTimeInterval(-IdlePlateLock.bandAwaySeconds)
        let dt = IdlePlateLock.disconnectedFor(
            bound: true, connected: false, disconnectStamp: stamp, now: now)
        XCTAssertEqual(dt, IdlePlateLock.bandAwaySeconds, accuracy: 0.001)
        XCTAssertEqual(IdlePlateLock.edge(
            reserve: 60, wakeReserve: 70, bandPercent: 80, charging: false,
            disconnectedFor: dt), .bandAway)
        var snap = IdlePlateLock.appear(
            wearer: wearer, day: day, stored: nil, idleVisible: false)
        snap = IdlePlateLock.applyEvent(.bandAway, stored: snap, day: day)
        XCTAssertEqual(snap.plate, 20)
        XCTAssertEqual(snap.lockedBy, .event)
    }

    func testUnboundOrUnknownDisconnectIsNotBandAway() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = now.addingTimeInterval(-10 * 3600)
        XCTAssertEqual(IdlePlateLock.disconnectedFor(
            bound: false, connected: false, disconnectStamp: old, now: now), 0)
        XCTAssertEqual(IdlePlateLock.disconnectedFor(
            bound: true, connected: false, disconnectStamp: nil, now: now), 0)
        XCTAssertEqual(IdlePlateLock.disconnectedFor(
            bound: true, connected: true, disconnectStamp: old, now: now), 0)
        let dt = IdlePlateLock.disconnectedFor(
            bound: false, connected: false, disconnectStamp: old, now: now)
        XCTAssertNil(IdlePlateLock.edge(
            reserve: 60, wakeReserve: 70, bandPercent: 80, charging: false,
            disconnectedFor: dt))
        let snap = IdlePlateLock.appear(
            wearer: wearer, day: day, stored: nil, idleVisible: false)
        XCTAssertNotEqual(snap.plate, 20)
        XCTAssertEqual(snap.lockedBy, .daily)
        XCTAssertTrue(IdlePlateLock.dayPool.contains(snap.plate))
    }

    func testSecondEdgeTheSameDayIsIgnored() {
        var snap = IdlePlateLock.appear(
            wearer: wearer, day: day, stored: nil, idleVisible: false)
        snap = IdlePlateLock.applyEvent(.lowReserve, stored: snap, day: day)
        let held = IdlePlateLock.applyEvent(.bandAway, stored: snap, day: day)
        XCTAssertEqual(held.plate, 25)
        XCTAssertEqual(held.lockedBy, .event)
    }

    func testReachingNoContactAndBpmAreNotEdges() {
        XCTAssertNil(IdlePlateLock.edge(
            reserve: 60, wakeReserve: 70, bandPercent: 80, charging: false,
            disconnectedFor: 60, reaching: true, noContact: true, bpm: 180))
        let low = IdlePlateLock.edge(
            reserve: 22, wakeReserve: 70, bandPercent: 80, charging: false,
            disconnectedFor: 0, reaching: true, noContact: true, bpm: 180)
        XCTAssertEqual(low, .lowReserve)
    }

    func testAdvanceVisitWalksEveryPaintedLook() {
        var previous: Int?
        var seen: [Int] = []
        for _ in 0..<IdlePlateLock.reviewRoster.count {
            previous = IdlePlateLock.advanceVisit(previous: previous)
            seen.append(previous!)
        }
        XCTAssertEqual(seen, Array(1...28))
        XCTAssertEqual(IdlePlateLock.advanceVisit(previous: 28), 1)
        XCTAssertEqual(IdlePlateLock.advanceVisit(previous: 7), 8)
        XCTAssertEqual(IdlePlateLock.advanceVisit(previous: nil), 1)
        XCTAssertEqual(IdlePlateLock.advanceVisit(previous: 99), 1)
    }

    func testVisitLockIsNotCoveredByAnEvent() {
        let snap = IdlePlateLock.Snapshot(day: day, plate: 4, lockedBy: .visit)
        let held = IdlePlateLock.applyEvent(.lowReserve, stored: snap, day: day)
        XCTAssertEqual(held.plate, 4)
        XCTAssertEqual(held.lockedBy, .visit)
    }

    func testReserveAt25IsNotLowUnlessBelowWake() {
        XCTAssertNil(IdlePlateLock.edge(
            reserve: 25, wakeReserve: 20, bandPercent: 80, charging: false,
            disconnectedFor: 0))
        XCTAssertEqual(IdlePlateLock.edge(
            reserve: 25, wakeReserve: 40, bandPercent: 80, charging: false,
            disconnectedFor: 0), .lowReserve)
    }
}
