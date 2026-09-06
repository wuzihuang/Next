import XCTest
@testable import NextBodySyncCore

/// ADR 0010 · simulated wear lives. Each case builds five-minute ticks the way a
/// day actually arrives, then asks the flame what it would show at that clock.
final class WearRunScenarioTests: XCTestCase {
    private let day0 = UserDay.containing(
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 12))!)

    // MARK: named lives

    func testEverydayDaytimeWearLightsByNoonAndKeepsYesterdayOvernight() {
        // Charge 23:00–08:00, wear 08:00–23:00. Closed day is 180 / 288 → worn.
        var prev: Settled?
        for back in 0..<7 {
            let day = day0.adding(days: back)
            let samples = wearTicks(on: day, worn: 48..<228)
            XCTAssertTrue(isClosedWorn(samples, day),
                          "day \(back) of an 08–23 wear should be a worn day")
            let prior = prev.map(WearRun.Yesterday.init)
            let held = prev?.worn == true ? prev!.run : 0
            assertOpenDay(samples, day, yesterday: prior,
                          lightsByHour: 8, runWhenLit: held + 1, runBeforeLit: held)
            prev = settle(worn: true, prev: prev)
            XCTAssertEqual(prev?.run, back + 1)
        }
    }

    func testOvernightChargeDoesNotAmberAnOpenMorning() {
        let yesterday = WearRun.Yesterday(worn: true, run: 5, miss: 0)
        let samples = wearTicks(on: day0, worn: 48..<228)
        XCTAssertEqual(flame(samples, day0, atHour: 0, minute: 15, yesterday: yesterday), .live(5))
        XCTAssertEqual(flame(samples, day0, atHour: 3, minute: 59, yesterday: yesterday), .live(5))
        XCTAssertFalse(WearRun.isWornDay(
            samples: samples, day: day0, now: clock(day0, hour: 3, minute: 59)))
    }

    func testEightAMPutOnCatchesHalfCoverageAtNoon() {
        let samples = wearTicks(on: day0, worn: 48..<228)
        // H hours after 04:00: elapsed = 12H, worn since 08:00 = 12·max(H−4, 0).
        // 2(H−4) ≥ H → H ≥ 8 → 12:00.
        XCTAssertFalse(WearRun.isWornDay(samples: samples, day: day0, now: clock(day0, hour: 7)))
        XCTAssertTrue(WearRun.isWornDay(samples: samples, day: day0, now: clock(day0, hour: 8)))
        let yesterday = WearRun.Yesterday(worn: true, run: 3, miss: 0)
        XCTAssertEqual(flame(samples, day0, atHour: 7, yesterday: yesterday), .live(3))
        XCTAssertEqual(flame(samples, day0, atHour: 8, yesterday: yesterday), .live(4))
    }

    func testShortDaytimeElevenHoursLightsThenDropsBeforeTheCut() {
        // 09:00–20:00 = 132 hearts. Against a still-open evening that is enough
        // (132·2 ≥ 192 at 20:00). Against the closed 288 it is not. After ~02:00
        // the empty night slots push elapsed past 264 and today falls back to
        // yesterday's number — then the cut is amber.
        let samples = wearTicks(on: day0, worn: 60..<192)
        let yesterday = WearRun.Yesterday(worn: true, run: 4, miss: 0)
        XCTAssertEqual(flame(samples, day0, atHour: 16, yesterday: yesterday), .live(5))
        XCTAssertEqual(flame(samples, day0, atHour: 22, minute: 5, yesterday: yesterday), .live(4))
        XCTAssertFalse(isClosedWorn(samples, day0))
        let closed = settle(worn: false, prev: Settled(worn: true, run: 4, miss: 0))
        XCTAssertEqual(closed.miss, 1)
        XCTAssertEqual(WearRun.display(todayWorn: false, yesterday: WearRun.Yesterday(closed)), .amber)
    }

    func testTwelveDaytimeHoursIsExactlyWorn() {
        XCTAssertTrue(isClosedWorn(wearTicks(on: day0, worn: 60..<204), day0))
        XCTAssertFalse(isClosedWorn(wearTicks(on: day0, worn: 60..<203), day0))
    }

    func testNightstandTemperatureAndZeroStepsNeverLight() {
        let samples = (0..<WearRun.slotsPerDay).map { slot in
            VitalSample(
                ts: day0.start.addingTimeInterval(TimeInterval(slot) * WearRun.slotSeconds),
                hr: nil, stress: nil, temp: 28.4, steps: 0, vendorCalories: 12)
        }
        XCTAssertFalse(isClosedWorn(samples, day0))
        XCTAssertEqual(flame(samples, day0, atHour: 16, yesterday: nil), .gray)
    }

    func testSparseTenMinuteHeartAllDayIsBarelyWorn() {
        XCTAssertTrue(isClosedWorn(wearTicks(on: day0, worn: 0..<288, every: 2), day0))
        XCTAssertFalse(isClosedWorn(wearTicks(on: day0, worn: 48..<240, every: 2), day0))
    }

    func testFifteenMinuteHeartWhileWornSixteenHoursNeverLights() {
        XCTAssertFalse(isClosedWorn(wearTicks(on: day0, worn: 48..<240, every: 3), day0))
    }

    func testStressHrvOrStepsCanStandInForHeart() {
        XCTAssertTrue(isClosedWorn(wearTicks(on: day0, worn: 0..<144) {
            VitalSample(ts: $0, hr: nil, stress: 31)
        }, day0))
        XCTAssertTrue(isClosedWorn(wearTicks(on: day0, worn: 0..<144) {
            VitalSample(ts: $0, hr: nil, stress: nil, hrv: 42)
        }, day0))
        XCTAssertTrue(isClosedWorn(wearTicks(on: day0, worn: 0..<144) {
            VitalSample(ts: $0, hr: nil, stress: nil, steps: 8)
        }, day0))
    }

    func testDuplicateTicksInOneSlotCountOnce() {
        let twice = [
            VitalSample(ts: day0.start, hr: 64, stress: nil),
            VitalSample(ts: day0.start.addingTimeInterval(10), hr: 66, stress: nil),
        ]
        XCTAssertTrue(WearRun.isWornDay(
            samples: twice, day: day0, now: day0.start.addingTimeInterval(600)))
        XCTAssertFalse(WearRun.isWornDay(
            samples: twice, day: day0, now: day0.start.addingTimeInterval(900)))
    }

    func testTicksOutsideTheUserDayDoNotCount() {
        let inside = wearTicks(on: day0, worn: 0..<144)
        let spilled = inside
            + wearTicks(on: day0.adding(days: 1), worn: 0..<144)
            + wearTicks(on: day0.adding(days: -1), worn: 0..<144)
        XCTAssertEqual(
            WearRun.isWornDay(samples: inside, day: day0, now: day0.end),
            WearRun.isWornDay(samples: spilled, day: day0, now: day0.end))
    }

    func testFirstUserDayStaysGrayUntilTodayItselfQualifies() {
        let samples = wearTicks(on: day0, worn: 48..<228)
        XCTAssertEqual(flame(samples, day0, atHour: 3, yesterday: nil), .gray)
        XCTAssertEqual(flame(samples, day0, atHour: 8, yesterday: nil), .live(1))
    }

    func testMissThenWearRestartsAtOneAndDoesNotFreeze() {
        var prev = Settled(worn: true, run: 9, miss: 0)
        prev = settle(worn: false, prev: prev)
        XCTAssertEqual(WearRun.display(todayWorn: false, yesterday: WearRun.Yesterday(prev)), .amber)
        prev = settle(worn: false, prev: prev)
        XCTAssertEqual(WearRun.display(todayWorn: false, yesterday: WearRun.Yesterday(prev)), .gray)
        prev = settle(worn: true, prev: prev)
        XCTAssertEqual(prev.run, 1)
        XCTAssertEqual(
            WearRun.display(todayWorn: true, yesterday: WearRun.Yesterday(worn: false, run: 0, miss: 2)),
            .live(1))
    }

    func testMissingServerColumnsPreviewYesterdayFromLocalTicks() {
        let local = WearRun.yesterday(worn: nil, run: nil, miss: nil, localWorn: true)
        XCTAssertEqual(WearRun.display(todayWorn: false, yesterday: local), .live(1))
        let empty = WearRun.yesterday(worn: nil, run: nil, miss: nil, localWorn: false)
        XCTAssertEqual(WearRun.display(todayWorn: false, yesterday: empty), .gray)
        let refused = WearRun.yesterday(worn: false, run: 0, miss: 1, localWorn: true)
        XCTAssertEqual(WearRun.display(todayWorn: false, yesterday: refused), .amber)
    }

    func testNinetyClosedWornDaysCountUpAndAGapBreaksThem() {
        var prev: Settled?
        for n in 1...90 {
            prev = settle(worn: true, prev: prev)
            XCTAssertEqual(prev?.run, n)
            XCTAssertEqual(prev?.miss, 0)
        }
        let broken = settle(worn: false, prev: prev)
        XCTAssertEqual(broken.run, 0)
        XCTAssertEqual(broken.miss, 1)
        XCTAssertEqual(WearRun.display(todayWorn: false, yesterday: WearRun.Yesterday(broken)), .amber)
        XCTAssertEqual(
            WearRun.display(todayWorn: true, yesterday: WearRun.Yesterday(broken)),
            .live(1),
            "amber is not a freeze")
    }

    // MARK: stress

    func testRandomLivesKeepFlameInvariants() {
        var seed: UInt64 = 0xC0FFEE_2026_0906
        func rnd() -> UInt64 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return seed
        }
        let patterns = Pattern.allCases
        var lit = 0
        var amber = 0
        var gray = 0
        for trial in 0..<200 {
            var prev: Settled?
            for back in 0..<30 {
                let day = day0.adding(days: back)
                let pattern = patterns[Int(rnd() % UInt64(patterns.count))]
                let samples = pattern.ticks(on: day)
                let wornClosed = isClosedWorn(samples, day)
                let next = settle(worn: wornClosed, prev: prev)
                assertSettled(next, after: prev, worn: wornClosed, trial: trial, day: back)
                for hour in [0, 4, 8, 12, 20] {
                    let todayWorn = WearRun.isWornDay(
                        samples: samples, day: day, now: clock(day, hour: hour))
                    let shown = WearRun.display(
                        todayWorn: todayWorn, yesterday: prev.map(WearRun.Yesterday.init))
                    assertFlame(shown, todayWorn: todayWorn, yesterday: prev, trial: trial, hour: hour)
                    switch shown {
                    case .live: lit += 1
                    case .amber: amber += 1
                    case .gray: gray += 1
                    }
                }
                prev = next
            }
        }
        XCTAssertGreaterThan(lit, 0)
        XCTAssertGreaterThan(amber, 0)
        XCTAssertGreaterThan(gray, 0)
    }

    func testHourlyClockOfAWeekNeverPrintsZeroOrPrematureAmber() {
        var prev: Settled?
        for back in 0..<7 {
            let day = day0.adding(days: back)
            let samples = wearTicks(on: day, worn: 48..<228)
            for hour in 0..<24 {
                let todayWorn = WearRun.isWornDay(
                    samples: samples, day: day, now: clock(day, hour: hour))
                let shown = WearRun.display(
                    todayWorn: todayWorn, yesterday: prev.map(WearRun.Yesterday.init))
                if case .live(let n) = shown {
                    XCTAssertGreaterThanOrEqual(n, 1, "hour \(hour) day \(back) printed 0")
                }
                if todayWorn {
                    XCTAssertEqual(shown, .live(back + 1), "hour \(hour) day \(back)")
                } else if let prev, prev.worn {
                    XCTAssertEqual(shown, .live(prev.run), "open morning cooled on day \(back) hour \(hour)")
                } else {
                    XCTAssertNotEqual(shown, .amber, "first open morning must not go amber")
                }
            }
            prev = settle(worn: true, prev: prev)
        }
    }
}

private struct Settled: Equatable {
    var worn: Bool
    var run: Int
    var miss: Int
}

private enum Pattern: CaseIterable {
    case full
    case daytime
    case shortDay
    case sparseTen
    case nightstand
    case empty

    func ticks(on day: UserDay) -> [VitalSample] {
        switch self {
        case .full: return wearTicks(on: day, worn: 0..<288)
        case .daytime: return wearTicks(on: day, worn: 48..<228)
        case .shortDay: return wearTicks(on: day, worn: 60..<192)
        case .sparseTen: return wearTicks(on: day, worn: 48..<240, every: 2)
        case .nightstand:
            return (0..<288).map { slot in
                VitalSample(
                    ts: day.start.addingTimeInterval(TimeInterval(slot) * WearRun.slotSeconds),
                    hr: nil, stress: nil, temp: 27.0, steps: 0)
            }
        case .empty: return []
        }
    }
}

private extension WearRun.Yesterday {
    init(_ settled: Settled) {
        self.init(worn: settled.worn, run: settled.run, miss: settled.miss)
    }
}

private func settle(worn: Bool, prev: Settled?) -> Settled {
    guard let prev else {
        return worn ? Settled(worn: true, run: 1, miss: 0) : Settled(worn: false, run: 0, miss: 2)
    }
    if worn {
        return Settled(worn: true, run: prev.worn ? prev.run + 1 : 1, miss: 0)
    }
    return Settled(worn: false, run: 0, miss: prev.worn ? 1 : min(2, prev.miss + 1))
}

private func assertSettled(_ next: Settled, after prev: Settled?, worn: Bool, trial: Int, day: Int) {
    XCTAssertEqual(next.worn, worn, "trial \(trial) day \(day)")
    if worn {
        XCTAssertEqual(next.miss, 0)
        XCTAssertGreaterThanOrEqual(next.run, 1)
        if let prev, prev.worn {
            XCTAssertEqual(next.run, prev.run + 1)
        } else {
            XCTAssertEqual(next.run, 1)
        }
    } else {
        XCTAssertEqual(next.run, 0)
        XCTAssertTrue((1...2).contains(next.miss))
        if prev?.worn == true { XCTAssertEqual(next.miss, 1) }
        if prev == nil { XCTAssertEqual(next.miss, 2) }
    }
}

private func assertFlame(
    _ shown: WearRun.Flame,
    todayWorn: Bool,
    yesterday: Settled?,
    trial: Int,
    hour: Int
) {
    if case .live(let n) = shown {
        XCTAssertGreaterThanOrEqual(n, 1, "trial \(trial) hour \(hour) live(0)")
    }
    if todayWorn {
        guard case .live = shown else {
            return XCTFail("trial \(trial) hour \(hour) today is worn but \(shown)")
        }
        return
    }
    if let yesterday, yesterday.worn {
        XCTAssertEqual(shown, .live(max(1, yesterday.run)), "trial \(trial) hour \(hour)")
    } else if yesterday?.miss == 1 {
        XCTAssertEqual(shown, .amber, "trial \(trial) hour \(hour)")
    } else {
        XCTAssertEqual(shown, .gray, "trial \(trial) hour \(hour)")
    }
}

private func assertOpenDay(
    _ samples: [VitalSample],
    _ day: UserDay,
    yesterday: WearRun.Yesterday?,
    lightsByHour: Int,
    runWhenLit: Int,
    runBeforeLit: Int
) {
    let before = flame(samples, day, atHour: lightsByHour - 1, yesterday: yesterday)
    let after = flame(samples, day, atHour: lightsByHour, yesterday: yesterday)
    if runBeforeLit == 0 {
        XCTAssertEqual(before, .gray)
    } else {
        XCTAssertEqual(before, .live(runBeforeLit))
    }
    XCTAssertEqual(after, .live(runWhenLit))
}

private func flame(
    _ samples: [VitalSample],
    _ day: UserDay,
    atHour hour: Int,
    minute: Int = 0,
    yesterday: WearRun.Yesterday?
) -> WearRun.Flame {
    WearRun.display(
        todayWorn: WearRun.isWornDay(samples: samples, day: day, now: clock(day, hour: hour, minute: minute)),
        yesterday: yesterday)
}

private func isClosedWorn(_ samples: [VitalSample], _ day: UserDay) -> Bool {
    WearRun.isWornDay(samples: samples, day: day, now: day.end)
}

private func clock(_ day: UserDay, hour: Int, minute: Int = 0) -> Date {
    day.start.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
}

private func wearTicks(
    on day: UserDay,
    worn: Range<Int>,
    every: Int = 1,
    make: ((Date) -> VitalSample)? = nil
) -> [VitalSample] {
    var out: [VitalSample] = []
    var slot = worn.lowerBound
    while slot < worn.upperBound {
        if (slot - worn.lowerBound) % every == 0 {
            let ts = day.start.addingTimeInterval(TimeInterval(slot) * WearRun.slotSeconds)
            out.append(make?(ts) ?? VitalSample(ts: ts, hr: 64, stress: nil))
        }
        slot += 1
    }
    return out
}
