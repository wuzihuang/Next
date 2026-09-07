import XCTest
@testable import NextBodySyncCore

final class NotificationReachMathTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func snap(
        now: Date,
        quiet: Bool = false,
        deliveredCount: Int = 0,
        delivered: Set<NotifyKind> = [],
        page: NotifyPage = .other,
        morningOn: Bool = false,
        trainingOn: Bool = false,
        mealsOn: Bool = false,
        wrapOn: Bool = false,
        energyOn: Bool = false,
        bandOn: Bool = false,
        wakePeak: Date? = nil,
        morningShown: Bool = false,
        daySealed: Bool = false,
        mealsInLast7Days: Int = 0,
        breakfast: Bool = false,
        lunch: Bool = false,
        dinner: Bool = false,
        moved: Bool = false,
        trainingLoad: Double? = nil,
        targetLoad: Double? = nil,
        reserveNow: Int? = nil,
        prevReserve: Int? = nil,
        bbWake: Int? = nil,
        dayHigh: Int? = nil,
        liveSession: Bool = false,
        reserveFresh: Bool = true,
        hasNightCharge: Bool = false,
        hasConfirmedMeal: Bool = false,
        weekRolled: Bool = false,
        priorWeekValidDays: Int = 0,
        appOpened: Bool = false,
        bandBound: Bool = true,
        bandConnected: Bool = true,
        bandCharging: Bool = false,
        bandPercent: Int? = nil,
        bandBars: Int? = nil,
        disconnectStarted: Date? = nil
    ) -> NotifySnapshot {
        NotifySnapshot(
            now: now, quietEnabled: quiet, deliveredCount: deliveredCount, delivered: delivered,
            page: page, morningOn: morningOn, trainingOn: trainingOn, mealsOn: mealsOn,
            wrapOn: wrapOn, energyOn: energyOn, bandOn: bandOn, wakePeak: wakePeak,
            morningShown: morningShown, daySealed: daySealed, mealsInLast7Days: mealsInLast7Days,
            breakfastConfirmed: breakfast, lunchConfirmed: lunch, dinnerConfirmed: dinner,
            moved: moved, trainingLoad: trainingLoad, targetLoad: targetLoad, reserveNow: reserveNow,
            prevReserve: prevReserve, bbWake: bbWake, dayHighReserve: dayHigh, liveSession: liveSession,
            reserveFresh: reserveFresh, hasNightCharge: hasNightCharge, hasConfirmedMeal: hasConfirmedMeal,
            weekRolled: weekRolled, priorWeekValidDays: priorWeekValidDays,
            appOpenedAfterComplete: appOpened, bandBound: bandBound, bandConnected: bandConnected,
            bandCharging: bandCharging, bandPercent: bandPercent, bandBars: bandBars,
            disconnectStarted: disconnectStarted)
    }

    func testDeepLinksMatchF1() {
        XCTAssertEqual(
            NotificationDeepLink.parse(URL(string: "nextbody://home?panel=body_battery")!),
            .homePanel)
        XCTAssertEqual(NotificationDeepLink.parse(URL(string: "nextbody://home")!), .home)
        XCTAssertEqual(
            NotificationDeepLink.parse(URL(string: "nextbody://fuel?slot=dinner")!),
            .fuel(slot: "dinner"))
        XCTAssertEqual(NotificationDeepLink.parse(URL(string: "nextbody://device")!), .device)
        XCTAssertEqual(
            NotificationDeepLink.parse(URL(string: "nextbody://composition?date=2025-11-02")!),
            .composition(day: "2025-11-02"))
        XCTAssertEqual(
            NotificationDeepLink.parse(URL(string: "nextbody://log?via=photo")!),
            .logPhoto)
        XCTAssertEqual(NotificationDeepLink.parse(URL(string: "nextbody://training")!), .training)
        XCTAssertNil(NotificationDeepLink.parse(URL(string: "nextbody://home?panel=sleep")!))
        XCTAssertNil(NotificationDeepLink.parse(URL(string: "https://nextbody.app")!))
    }

    func testWakePeakIsTheMorningHigh() {
        let start = date(2026, 9, 6, 4)
        let curve: [(Date, Int)] = [
            (date(2026, 9, 6, 5), 40),
            (date(2026, 9, 6, 7, 12), 72),
            (date(2026, 9, 6, 10), 60),
            (date(2026, 9, 6, 16), 30),
        ]
        XCTAssertEqual(NotificationReachMath.wakePeak(dayStart: start, curve: curve), date(2026, 9, 6, 7, 12))
    }

    func testQuietHoursStopAtSeven() {
        XCTAssertTrue(NotificationReachMath.isQuiet(date(2026, 9, 6, 22, 30), calendar: calendar))
        XCTAssertTrue(NotificationReachMath.isQuiet(date(2026, 9, 6, 6, 59), calendar: calendar))
        XCTAssertFalse(NotificationReachMath.isQuiet(date(2026, 9, 6, 7), calendar: calendar))
        XCTAssertFalse(NotificationReachMath.isQuiet(date(2026, 9, 6, 12), calendar: calendar))
    }

    func testMorningHoldsThroughQuietThenFires() {
        let wake = date(2026, 9, 6, 6, 12)
        let plan = NotificationReachMath.decide(
            snap(now: date(2026, 9, 6, 6, 20), quiet: true, morningOn: true, wakePeak: wake),
            calendar: calendar)
        XCTAssertEqual(plan, .later(.morning, at: date(2026, 9, 6, 7), mealSlot: nil, weekly: false))
    }

    func testLateWakeFiresWhenNightLands() {
        let wake = date(2026, 9, 6, 8, 40)
        let now = date(2026, 9, 6, 8, 45)
        let plan = NotificationReachMath.decide(
            snap(now: now, morningOn: true, wakePeak: wake), calendar: calendar)
        XCTAssertEqual(plan, .fire(.morning, mealSlot: nil, weekly: false))
    }

    func testPastWindowAndShownStaySilent() {
        let wake = date(2026, 9, 6, 7)
        XCTAssertEqual(
            NotificationReachMath.planMorning(
                now: date(2026, 9, 6, 14), wakePeak: wake, alreadyShown: false,
                morningEnabled: true, quietEnabled: true, calendar: calendar),
            .skip("PAST_WINDOW"))
        XCTAssertEqual(
            NotificationReachMath.planMorning(
                now: date(2026, 9, 6, 8), wakePeak: wake, alreadyShown: true,
                morningEnabled: true, quietEnabled: true, calendar: calendar),
            .skip("ALREADY_SHOWN"))
        XCTAssertEqual(
            NotificationReachMath.planMorning(
                now: date(2026, 9, 6, 8), wakePeak: nil, alreadyShown: false,
                morningEnabled: true, quietEnabled: true, calendar: calendar),
            .skip("NO_NIGHT"))
    }

    func testMealAsksLunchAfterBreakfastWhenTheyMoved() {
        let now = date(2026, 9, 6, 13)
        let plan = NotificationReachMath.decide(
            snap(now: now, mealsOn: true, mealsInLast7Days: 3, breakfast: true, moved: true),
            calendar: calendar)
        XCTAssertEqual(plan, .fire(.meal, mealSlot: "lunch", weekly: false))
    }

    func testMealStaysSilentWithoutMovementOrHistory() {
        let now = date(2026, 9, 6, 13)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, mealsOn: true, mealsInLast7Days: 3, breakfast: true, moved: false),
                calendar: calendar),
            .skip)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, mealsOn: true, mealsInLast7Days: 0, breakfast: true, moved: true),
                calendar: calendar),
            .skip)
    }

    func testTrainingFiresWhenReserveCrossesSixtyOfWake() {
        let now = date(2026, 9, 6, 15)
        let plan = NotificationReachMath.decide(
            snap(now: now, trainingOn: true, trainingLoad: 3.9, targetLoad: 14.5,
                 reserveNow: 40, prevReserve: 55, bbWake: 72, dayHigh: 72),
            calendar: calendar)
        XCTAssertEqual(plan, .fire(.training, mealSlot: nil, weekly: false))
    }

    func testTrainingSilentWhenReserveStaysHigh() {
        let now = date(2026, 9, 6, 15)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, trainingOn: true, trainingLoad: 3.9, targetLoad: 14.5,
                     reserveNow: 70, prevReserve: 72, bbWake: 72, dayHigh: 72),
                calendar: calendar),
            .skip)
    }

    func testDailyWrapWhenTwoFactsLand() {
        let now = date(2026, 9, 6, 16)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, wrapOn: true, trainingLoad: 3.9, hasNightCharge: true),
                calendar: calendar),
            .fire(.daily, mealSlot: nil, weekly: false))
    }

    func testDailyBecomesWeeklyOnWeekRoll() {
        let now = date(2026, 9, 7, 8)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, wrapOn: true, trainingLoad: 4, hasNightCharge: true,
                     weekRolled: true, priorWeekValidDays: 5),
                calendar: calendar),
            .fire(.daily, mealSlot: nil, weekly: true))
    }

    func testReserveCrossesTwentyFiveBelowWake() {
        let now = date(2026, 9, 6, 16)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, energyOn: true, reserveNow: 24, prevReserve: 40, bbWake: 72, dayHigh: 72),
                calendar: calendar),
            .fire(.reserve, mealSlot: nil, weekly: false))
    }

    func testReserveSilentWhenWakeAlreadyLow() {
        let now = date(2026, 9, 6, 8)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, energyOn: true, reserveNow: 22, prevReserve: 22, bbWake: 22, dayHigh: 22),
                calendar: calendar),
            .skip)
    }

    func testBandBatteryAndAway() {
        let now = date(2026, 9, 6, 14)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, bandOn: true, bandPercent: 12),
                calendar: calendar),
            .fire(.bandBattery, mealSlot: nil, weekly: false))
        let start = date(2026, 9, 6, 8)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, bandOn: true, bandConnected: false, disconnectStarted: start),
                calendar: calendar),
            .fire(.bandAway, mealSlot: nil, weekly: false))
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: date(2026, 9, 6, 10), bandOn: true, bandConnected: false, disconnectStarted: start),
                calendar: calendar),
            .later(.bandAway, at: date(2026, 9, 6, 12), mealSlot: nil, weekly: false))
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, delivered: [.bandBattery], bandOn: true, bandConnected: false,
                     disconnectStarted: start),
                calendar: calendar),
            .skip)
    }

    func testLaterAwayDoesNotBlockMorning() {
        let now = date(2026, 9, 6, 12)
        let wake = date(2026, 9, 6, 7)
        let start = date(2026, 9, 6, 11)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, morningOn: true, bandOn: true, wakePeak: wake,
                     bandConnected: false, disconnectStarted: start),
                calendar: calendar),
            .fire(.morning, mealSlot: nil, weekly: false))
        XCTAssertEqual(
            NotificationReachMath.awayFireAt(
                snap(now: now, bandOn: true, bandConnected: false, disconnectStarted: start)),
            date(2026, 9, 6, 15))
    }

    func testBudgetAndDestinationSwallow() {
        let now = date(2026, 9, 6, 12)
        let wake = date(2026, 9, 6, 7)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, deliveredCount: 4, morningOn: true, wakePeak: wake),
                calendar: calendar),
            .skip)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, page: .fuel, mealsOn: true, mealsInLast7Days: 2, breakfast: true, moved: true),
                calendar: calendar),
            .skip)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, page: .other, mealsOn: true, mealsInLast7Days: 2, breakfast: true, moved: true),
                calendar: calendar),
            .fire(.meal, mealSlot: "lunch", weekly: false))
    }

    func testBandBeatsMorningWhenBothReady() {
        let now = date(2026, 9, 6, 12)
        let wake = date(2026, 9, 6, 7)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, morningOn: true, bandOn: true, wakePeak: wake, bandPercent: 10),
                calendar: calendar),
            .fire(.bandBattery, mealSlot: nil, weekly: false))
    }

    func testTrainingSilentOnceLoadMeetsTarget() {
        let now = date(2026, 9, 6, 16)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, trainingOn: true, trainingLoad: 14.5, targetLoad: 14.5,
                     reserveNow: 40, prevReserve: 55, bbWake: 72, dayHigh: 72),
                calendar: calendar),
            .skip)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, trainingOn: true, trainingLoad: 15, targetLoad: 14.5,
                     reserveNow: 40, prevReserve: 55, bbWake: 72, dayHigh: 72),
                calendar: calendar),
            .skip)
    }

    func testDailyDoesNotRefireAndDoesNotSwallowOnHome() {
        let now = date(2026, 9, 6, 16)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: now, delivered: [.daily], wrapOn: true,
                     trainingLoad: 3.9, hasNightCharge: true, hasConfirmedMeal: true),
                calendar: calendar),
            .skip)
        XCTAssertFalse(NotificationReachMath.swallows(.daily, page: .other))
        XCTAssertTrue(NotificationReachMath.swallows(.meal, page: .fuel))
        XCTAssertTrue(NotificationReachMath.swallows(.morning, page: .bodyBattery))
    }

    func testQuietHoldDropsIfWindowAlreadyClosed() {
        let wake = date(2026, 9, 6, 3)
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: date(2026, 9, 6, 3, 20), quiet: true, morningOn: true, wakePeak: wake),
                calendar: calendar),
            .later(.morning, at: date(2026, 9, 6, 7), mealSlot: nil, weekly: false))
        XCTAssertEqual(
            NotificationReachMath.decide(
                snap(now: date(2026, 9, 6, 10), quiet: true, morningOn: true, wakePeak: wake),
                calendar: calendar),
            .skip)
    }
}
