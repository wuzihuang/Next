import XCTest
@testable import NextBodySyncCore

/// Given these sleep windows and these skin ticks, this is the verdict. Nothing here asserts
/// on a string, a colour or a view — the readout formats this result, it does not compute one.
final class SkinTempNightRangeTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    // MARK: the range itself

    func testFourteenSteadyNightsGiveARangeFlooredAtTwoTenths() {
        let world = world(sample: (6...19, 33.5), lastNight: (20, 33.5))
        let result = make(world)

        let range = try! XCTUnwrap(result.range)
        XCTAssertEqual(range.median, 33.5, accuracy: 0.0001)
        XCTAssertEqual(range.lower, 33.3, accuracy: 0.0001)
        XCTAssertEqual(range.upper, 33.7, accuracy: 0.0001)
        XCTAssertEqual(range.nights, 14)
        XCTAssertNil(result.empty)
        XCTAssertEqual(result.tier, .within)
        XCTAssertEqual(result.delta ?? .nan, 0, accuracy: 0.0001)
    }

    func testOneLooseStrapNightDoesNotWidenTheRange() {
        var world = world(sample: (6...18, 33.5), lastNight: (20, 33.5))
        let loose = night(day: 19, mean: 36.0)
        world.nights += loose.nights
        world.points += loose.points
        let result = make(world)

        // A standard deviation would be dragged to ±1.3 by that one night; MAD is not.
        let range = try! XCTUnwrap(result.range)
        XCTAssertEqual(range.nights, 14)
        XCTAssertEqual(range.median, 33.5, accuracy: 0.0001)
        XCTAssertEqual(range.upper, 33.7, accuracy: 0.0001)
    }

    func testLastNightIsNotPartOfTheRangeItIsJudgedBy() {
        let world = world(sample: (6...19, 33.5), lastNight: (20, 35.0))
        let result = make(world)

        let range = try! XCTUnwrap(result.range)
        XCTAssertEqual(range.median, 33.5, accuracy: 0.0001)
        XCTAssertEqual(range.nights, 14)
        XCTAssertEqual(result.lastNightMean ?? .nan, 35.0, accuracy: 0.0001)
    }

    func testFourValidNightsAreNotEnoughToConclude() {
        let world = world(sample: (16...19, 33.5), lastNight: (20, 33.5))
        let result = make(world)

        XCTAssertNil(result.range)
        XCTAssertEqual(result.sampleNights, 4)
        XCTAssertEqual(result.empty, .needsFiveNights)
        XCTAssertNil(result.tier)
        XCTAssertNil(result.delta)
        // The page can still print what the wrist measured.
        XCTAssertEqual(result.lastNightMean ?? .nan, 33.5, accuracy: 0.0001)
    }

    // MARK: what counts as a night

    func testANightShorterThanThreeHoursGetsNoVerdictAndLeavesTheSample() {
        var withShortNightBehind = world(sample: (6...19, 33.5), lastNight: (20, 33.5))
        withShortNightBehind.nights.removeAll { $0.start == instant(day: 19, hour: 0) }
        withShortNightBehind.points.removeAll {
            $0.ts >= instant(day: 19, hour: 0) && $0.ts < instant(day: 19, hour: 8)
        }
        let short = night(day: 19, mean: 33.5, hours: 2 + 50.0 / 60)
        withShortNightBehind.nights += short.nights
        withShortNightBehind.points += short.points
        XCTAssertEqual(make(withShortNightBehind).sampleNights, 13)

        let tonight = world(sample: (6...19, 33.5), lastNightWorn: (20, 33.5, 2 + 50.0 / 60, 1.0))
        let result = make(tonight)
        XCTAssertEqual(result.empty, .nightTooShort)
        XCTAssertNil(result.tier)
        XCTAssertNotNil(result.range)
    }

    func testANightWornLooselyEnoughToLoseTicksGetsNoVerdict() {
        let world = world(sample: (6...19, 33.5), lastNightWorn: (20, 33.5, 7, 0.4))
        let result = make(world)

        XCTAssertEqual(result.empty, .tooFewTicks)
        XCTAssertNil(result.tier)
        XCTAssertNotNil(result.range)
    }

    func testNoClosedNightAtAllSaysSo() {
        let result = SkinTempNightRange.make(
            points: [], nights: [], now: instant(day: 20, hour: 12), calendar: calendar)

        XCTAssertEqual(result.empty, .noNight)
        XCTAssertNil(result.range)
    }

    func testAnOpenSleepWindowStillReadsAsLastNight() {
        var world = world(sample: (6...19, 33.5), lastNight: (20, 33.5))
        let settled = make(world, now: instant(day: 20, hour: 23))
        world.nights.append(SkinTempNightRange.Night(start: instant(day: 20, hour: 22),
                                                     end: instant(day: 21, hour: 6)))
        let result = make(world, now: instant(day: 20, hour: 23))

        XCTAssertEqual(result.lastNightMean, settled.lastNightMean)
        XCTAssertEqual(result.tier, settled.tier)
        XCTAssertEqual(result.range, settled.range)
    }

    // MARK: the 28-day look-back

    func testFourteenNightsSpreadOverTwentyFiveDaysStillBuildARange() {
        var world = World()
        // Fourteen nights worn, eleven nights not — twenty-five days end to end.
        for day in [2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18, 20, 21] {
            let built = night(day: day, mean: 33.5)
            world.nights += built.nights
            world.points += built.points
        }
        let last = night(day: 26, mean: 33.5)
        world.nights += last.nights
        world.points += last.points
        let result = make(world, now: instant(day: 26, hour: 12))

        XCTAssertEqual(result.range?.nights, 14)
    }

    func testNightsOlderThanTwentyEightDaysDropOutOfTheSample() {
        var world = World()
        // Four nights a month back, five recent ones.
        for day in 1...4 {
            let built = night(day: day, mean: 30.0)
            world.nights += built.nights
            world.points += built.points
        }
        for day in 26...30 {
            let built = night(day: day, mean: 33.5)
            world.nights += built.nights
            world.points += built.points
        }
        let result = make(world, now: instant(day: 31, hour: 12))

        // Last night is day 30; day 1 sits 29 days back and is gone, day 2 is not.
        XCTAssertEqual(result.sampleNights, 7)
        XCTAssertEqual(result.range?.nights, 7)
    }

    // MARK: the three tiers

    func testTierBoundariesAreInclusiveAtTheRangeAndAtOneRangeWidthOut() {
        // 14 steady nights → 33.3–33.7, one range width is 0.4 °C.
        XCTAssertEqual(tier(lastNightMean: 33.7), .within)
        XCTAssertEqual(tier(lastNightMean: 34.1), .mildAbove)
        XCTAssertEqual(tier(lastNightMean: 34.11), .wellAbove)
        XCTAssertEqual(tier(lastNightMean: 33.3), .within)
        XCTAssertEqual(tier(lastNightMean: 32.9), .mildBelow)
        XCTAssertEqual(tier(lastNightMean: 32.89), .wellBelow)
    }

    // MARK: last night's minutes, and the daytime that is never judged

    func testMinutesOffRangeCoverEveryTickOfTheNight() {
        let world = world(sample: (6...19, 33.5), lastNight: (20, 33.5))
        let result = make(world)

        let total = result.minutesBelow + result.minutesWithin + result.minutesAbove
        XCTAssertEqual(total, 8 * 60)
        XCTAssertEqual(result.minutesWithin, 8 * 60)
    }

    func testADaytimeTickWellAboveTheNightMedianChangesNothing() {
        var world = world(sample: (6...19, 33.5), lastNight: (20, 33.5))
        world.points.append(.init(ts: instant(day: 20, hour: 10), celsius: 34.8))
        let result = make(world)

        XCTAssertEqual(result.tier, .within)
        XCTAssertEqual(result.delta ?? .nan, 0, accuracy: 0.0001)
        XCTAssertEqual(result.dayHigh ?? .nan, 34.8, accuracy: 0.0001)
    }

    func testDayNightGapIsDescribedNotJudged() {
        var world = world(sample: (6...19, 33.5), lastNight: (20, 33.5))
        for hour in [9, 10, 11] {
            world.points.append(.init(ts: instant(day: 20, hour: hour), celsius: 34.5))
        }
        let result = make(world)

        XCTAssertEqual(result.dayMean ?? .nan, 34.5, accuracy: 0.0001)
        XCTAssertEqual(result.dayLow ?? .nan, 34.5, accuracy: 0.0001)
        XCTAssertEqual(result.dayNightGap ?? .nan, 1.0, accuracy: 0.0001)
        XCTAssertEqual(result.tier, .within)
    }

    /// The shape `DataStore.seedHistory` + `seedToday` actually produce: twenty-one nights
    /// behind today at ~33.85 °C with one skipped and one 2 h nap, and a 7.2 h night ending
    /// this morning. A simulator walk must land on a verdict, not on LEARNING forever.
    func testTheSimulatorSeedShapeLandsOnAVerdict() {
        var world = World()
        for back in stride(from: 21, through: 1, by: -1) where back != 6 {
            let day = 20 - back
            let built = back == 9
                ? night(day: day, mean: 33.7, hours: 2)
                : night(day: day, mean: 33.85 + Double((back % 5)) * 0.05 - 0.1)
            world.nights += built.nights
            world.points += built.points
        }
        let tonight = night(day: 20, mean: 33.9, hours: 7.2)
        world.nights += tonight.nights
        world.points += tonight.points
        let result = make(world)

        XCTAssertNil(result.empty)
        XCTAssertEqual(result.tier, .within)
        XCTAssertNotNil(result.range)
        XCTAssertGreaterThanOrEqual(result.sampleNights, 5)
    }

    // MARK: fixtures

    private struct World {
        var nights: [SkinTempNightRange.Night] = []
        var points: [SkinTempNightRange.Point] = []
    }

    private func tier(lastNightMean: Double) -> SkinTempNightRange.Tier? {
        make(world(sample: (6...19, 33.5), lastNight: (20, lastNightMean))).tier
    }

    private func make(_ world: World, now: Date? = nil) -> SkinTempNightRange.Result {
        SkinTempNightRange.make(
            points: world.points,
            nights: world.nights,
            now: now ?? instant(day: 20, hour: 12),
            calendar: calendar)
    }

    private func world(sample: (ClosedRange<Int>, Double),
                       lastNightWorn: (Int, Double, Double, Double)) -> World {
        let lastNight = lastNightWorn
        var world = World()
        for day in sample.0 {
            let built = night(day: day, mean: sample.1)
            world.nights += built.nights
            world.points += built.points
        }
        let last = night(day: lastNight.0, mean: lastNight.1,
                         hours: lastNight.2, coverage: lastNight.3)
        world.nights += last.nights
        world.points += last.points
        return world
    }

    private func world(sample: (ClosedRange<Int>, Double), lastNight: (Int, Double)) -> World {
        world(sample: sample, lastNightWorn: (lastNight.0, lastNight.1, 8, 1.0))
    }

    /// One night from 00:00, and a tick every five minutes across the covered share of it.
    private func night(day: Int, mean: Double, hours: Double = 8,
                       coverage: Double = 1.0) -> World {
        let start = instant(day: day, hour: 0)
        let end = start.addingTimeInterval(hours * 3600)
        let slots = Int(hours * 60 / 5)
        let covered = Int((Double(slots) * coverage).rounded(.down))
        let points = (0..<covered).map { slot in
            SkinTempNightRange.Point(ts: start.addingTimeInterval(Double(slot) * 300),
                                     celsius: mean)
        }
        return World(nights: [.init(start: start, end: end)], points: points)
    }

    private func instant(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day,
                                           hour: hour, minute: minute))!
    }
}
