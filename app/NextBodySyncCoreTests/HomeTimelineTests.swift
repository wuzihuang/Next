import XCTest
@testable import NextBodySyncCore

final class HomeTimelineTests: XCTestCase {
    private let day = UserDay.containing(
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!)

    func testTodayContainsOnlyEventsThatHaveActuallyHappenedOnThisDay() {
        let now = day.start.addingTimeInterval(12 * 3600)
        let entries = [
            item("yesterday", at: day.start.addingTimeInterval(-60)),
            item("midnight", at: day.start),
            item("morning", at: day.start.addingTimeInterval(8 * 3600)),
            item("now", at: now),
            item("future", at: now.addingTimeInterval(60)),
            item("tomorrow", at: day.end),
        ]

        let visible = HomeTimeline.visible(entries, on: day, earlier: false, now: now)

        XCTAssertEqual(visible.map(\.id), ["now", "morning", "midnight"])
    }

    func testRecordedWorkoutReplacesItsAutomaticActivityButKeepsSeparateMovement() {
        let entries = [
            item("workout", at: at(8), accent: .workout, endAt: at(8, 40)),
            item("same-activity", at: at(7, 55), accent: .activity, endAt: at(8, 40)),
            item("later-walk", at: at(10), accent: .activity, endAt: at(10, 20)),
        ]

        let visible = HomeTimeline.visible(entries, on: day, earlier: false, now: at(12))

        XCTAssertEqual(visible.map(\.id), ["later-walk", "workout"])
    }

    func testIncompleteAndReversedIntervalsAreNotCompletedEvents() {
        let entries = [
            item("future-finish", at: at(11), accent: .workout, endAt: at(13)),
            item("reversed", at: at(9), accent: .sleep, endAt: at(8)),
            item("finished", at: at(8), accent: .workout, endAt: at(9)),
        ]

        let visible = HomeTimeline.visible(entries, on: day, earlier: false, now: at(12))

        XCTAssertEqual(visible.map(\.id), ["finished"])
    }

    func testPastWeekIncludesTodayAndThePreviousSixCalendarDays() {
        let entries = (0...7).map {
            item("\($0)", at: day.adding(days: -$0).start.addingTimeInterval(3600))
        }

        let visible = HomeTimeline.visible(entries, on: day, earlier: true, now: at(12))

        XCTAssertEqual(visible.map(\.id), ["0", "1", "2", "3", "4", "5", "6"])
    }

    func testRhythmMonthIncludesThirtyCalendarDaysAndNeverFutureEvents() {
        let entries = (0...30).map {
            item("\($0)", at: day.adding(days: -$0).start.addingTimeInterval(3600))
        } + [item("tomorrow", at: day.end)]

        let visible = HomeTimeline.visible(entries, on: day, earlier: true,
                                           now: at(12), lookbackDays: 29)

        XCTAssertEqual(visible.count, 30)
        XCTAssertEqual(visible.first?.id, "0")
        XCTAssertEqual(visible.last?.id, "29")
    }

    func testSleepStartAndWakeBelongToTheirActualCalendarDates() {
        let start = day.start.addingTimeInterval(-30 * 60)
        let entries = [
            item("asleep", at: start, accent: .sleep, endAt: at(7)),
            item("awake", at: at(7), accent: .wake),
        ]

        let today = HomeTimeline.visible(entries, on: day, earlier: false, now: at(12))
        let week = HomeTimeline.visible(entries, on: day, earlier: true, now: at(12))

        XCTAssertEqual(today.map(\.id), ["awake"])
        XCTAssertEqual(week.map(\.id), ["awake", "asleep"])
        XCTAssertEqual(week.map(\.day), [day, day.adding(days: -1)])
        XCTAssertEqual(week.last?.at, start)
    }

    func testAClosedDaysWindowStillExcludesTheNextMidnight() {
        let entries = [
            item("last-minute", at: day.end.addingTimeInterval(-60)),
            item("next-day", at: day.end),
        ]

        let visible = HomeTimeline.visible(entries, on: day, earlier: false,
                                           now: day.adding(days: 1).end)

        XCTAssertEqual(visible.map(\.id), ["last-minute"])
    }

    func testDuplicateIDsKeepTheFirstRecordAndEqualTimesHaveStableOrder() {
        var amended = item("meal-b", at: at(10))
        amended.title = "Edited meal"
        let entries = [amended, item("meal-a", at: at(10)), item("meal-b", at: at(9))]

        let visible = HomeTimeline.visible(entries, on: day, earlier: false, now: at(12))

        XCTAssertEqual(visible.map(\.id), ["meal-a", "meal-b"])
        XCTAssertEqual(visible.last?.title, "Edited meal")
    }

    func testAnEmptyDayDoesNotInventNowSyncOrHealthEvents() {
        XCTAssertTrue(HomeTimeline.visible([], on: day, earlier: false, now: at(12)).isEmpty)
    }

    func testSavedRecordKindsKeepTheirSourceIdentities() {
        let recordID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        var scan = item("scan", at: at(8), accent: .bodyScan)
        scan.recordID = recordID
        let entries = [
            item("meal", at: at(12)),
            item("stress", at: at(11), accent: .stress),
            item("weight", at: at(10), accent: .weighIn),
            item("balance", at: at(9), accent: .balanceCheck),
            scan,
        ]

        let visible = HomeTimeline.visible(entries, on: day, earlier: false, now: at(12))

        XCTAssertEqual(visible.map(\.accent), [.meal, .stress, .weighIn, .balanceCheck, .bodyScan])
        XCTAssertEqual(visible.last?.recordID, recordID)
    }

    func testAShortOverlapDoesNotEraseALongerActivity() {
        let entries = [
            item("activity", at: at(8), accent: .activity, endAt: at(9)),
            item("workout", at: at(8, 50), accent: .workout, endAt: at(9, 10)),
        ]

        let visible = HomeTimeline.visible(entries, on: day, earlier: false, now: at(12))

        XCTAssertEqual(visible.map(\.id), ["workout", "activity"])
    }

    func testAnActivityWithSubstantialTimeOutsideTheWorkoutIsKept() {
        let entries = [
            item("activity", at: at(7, 30), accent: .activity, endAt: at(9, 30)),
            item("workout", at: at(8), accent: .workout, endAt: at(9, 20)),
        ]

        let visible = HomeTimeline.visible(entries, on: day, earlier: false, now: at(12))

        XCTAssertEqual(visible.map(\.id), ["workout", "activity"])
    }

    func testAdjacentActivityIsNotPartOfTheWorkout() {
        let entries = [
            item("workout", at: at(8), accent: .workout, endAt: at(9)),
            item("activity", at: at(9), accent: .activity, endAt: at(9, 20)),
        ]

        let visible = HomeTimeline.visible(entries, on: day, earlier: false, now: at(12))

        XCTAssertEqual(visible.map(\.id), ["activity", "workout"])
    }

    func testAnOvernightWorkoutIsNotDuplicatedAsNextDaysActivity() {
        let entries = [
            item("workout", at: day.start.addingTimeInterval(-30 * 60),
                 accent: .workout, endAt: at(1)),
            item("activity", at: day.start, accent: .activity, endAt: at(1)),
        ]

        let visible = HomeTimeline.visible(entries, on: day, earlier: true, now: at(12))

        XCTAssertEqual(visible.map(\.id), ["workout"])
    }

    func testAnActivityWithOnlyAStartTimeIsDeduplicatedInsideARecordedWorkout() {
        let entries = [
            item("workout", at: at(8), accent: .workout, endAt: at(9)),
            item("inside", at: at(8, 10), accent: .activity),
            item("after", at: at(9), accent: .activity),
        ]

        let visible = HomeTimeline.visible(entries, on: day, earlier: false, now: at(12))

        XCTAssertEqual(visible.map(\.id), ["after", "workout"])
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        day.start.addingTimeInterval(Double(hour * 60 + minute) * 60)
    }

    private func item(_ id: String, at: Date, accent: HomeTimeline.Accent = .meal,
                      endAt: Date? = nil) -> HomeTimeline.Item {
        .init(id: id, at: at, title: id, detail: "", accent: accent,
              meal: nil, trailing: nil, endAt: endAt)
    }
}
