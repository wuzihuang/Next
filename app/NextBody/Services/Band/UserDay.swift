import Foundation

// Moved out of Models/Metrics.swift so the sync package can use it: `WearRun` counts a worn
// day in the user-day's own five-minute slots, and the type it counts them in cannot live
// in a file the package does not compile. Pure Foundation, unchanged otherwise.

/// F2 rule 03 · one calendar. A user day runs local 00:00 → 00:00 next day.
struct UserDay: Hashable, Identifiable, Comparable, Codable {
    /// The instant the window opens: local midnight on the day it starts.
    let date: Date
    var id: Date { date }

    /// Two user days are the same day if they start on the same calendar date.
    /// ⚠️ Comparing the instants directly breaks across a DST change and across the two
    /// places a UserDay is built — from `now`, and from a `yyyy-MM-dd` string off the wire.
    static func == (a: UserDay, b: UserDay) -> Bool {
        Calendar.current.isDate(a.date, inSameDayAs: b.date)
    }

    func hash(into hasher: inout Hasher) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        hasher.combine(c.year); hasher.combine(c.month); hasher.combine(c.day)
    }

    /// Issue #19 · the cards say TODAY and the person reads midnight. They now agree.
    /// A night that ends at 02:40 still belongs to the night it started, because a night is
    /// keyed to the day the person woke on and stored, never cut out of this window.
    static let boundaryHour = 0

    static func containing(_ instant: Date, calendar: Calendar = .current,
                           boundaryHour: Int = boundaryHour) -> UserDay {
        let comps = calendar.dateComponents([.year, .month, .day, .hour], from: instant)
        var start = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day))!
        if (comps.hour ?? 0) < boundaryHour {
            start = calendar.date(byAdding: .day, value: -1, to: start)!
        }
        return UserDay(date: calendar.date(bySettingHour: boundaryHour, minute: 0, second: 0, of: start)!)
    }

    /// Oldest → newest, `count` user days ending at `end`.
    static func last(_ count: Int, endingAt end: UserDay) -> [UserDay] {
        guard count > 0 else { return [] }
        return (0..<count).map { end.adding(days: -(count - 1 - $0)) }
    }

    /// Oldest → newest, `count` user days ending on this one.
    func rollingBack(_ count: Int) -> [UserDay] {
        Self.last(count, endingAt: self)
    }

    /// Elapsed hours since this day's local midnight (23 or 25 across DST, otherwise 24).
    static func hours(_ instant: Date, in day: UserDay) -> Double {
        instant.timeIntervalSince(day.start) / 3600
    }

    /// Partition `0..<count` from the end in sevens. Oldest group first.
    /// A 30-day window is 2 + 7 + 7 + 7 + 7; a 28-day window is four sevens.
    static func weekRolls(count: Int) -> [Range<Int>] {
        guard count > 0 else { return [] }
        var newestFirst: [Range<Int>] = []
        var cursor = count
        while cursor > 0 {
            let start = max(0, cursor - 7)
            newestFirst.append(start..<cursor)
            cursor = start
        }
        return newestFirst.reversed()
    }

    var start: Date { date }
    /// The server's `user_day` string for this day.
    var key: String { Self.keyFormatter.string(from: date) }
    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    var end: Date { Calendar.current.date(byAdding: .day, value: 1, to: date)! }

    func adding(days: Int) -> UserDay {
        UserDay(date: Calendar.current.date(byAdding: .day, value: days, to: date)!)
    }

    /// Minutes elapsed inside the window at `now`, capped to the full window.
    func elapsedMinutes(at now: Date = Date()) -> Int {
        max(0, Int(min(now, end).timeIntervalSince(start) / 60))
    }

    var isClosed: Bool { Date() >= end }

    /// Applies a clock to this user day. With a midnight seam every hour lands on the
    /// day itself; the branch survives so a non-zero `boundaryHour` still reads correctly.
    func pinningClock(_ instant: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: instant)
        let minute = calendar.component(.minute, from: instant)
        let base = hour < Self.boundaryHour
            ? (calendar.date(byAdding: .day, value: 1, to: start) ?? start)
            : start
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? start
    }

    static func < (a: UserDay, b: UserDay) -> Bool { a.date < b.date }
}
