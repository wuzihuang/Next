import Foundation

/// When the next body scan is worth taking, and what has changed since the first one.
///
/// A wrist BIA reading moves with hydration, food and the hour of the day, so two scans a
/// day apart mostly measure the difference between two mornings rather than a change in the
/// body. A week is the shortest gap where the difference is likely to be the person.
///
/// ⚠️ This is a cadence, not a streak. Missing it costs nothing, there is no run to keep,
/// and an overdue scan says DUE rather than counting days of failure — the product's whole
/// position on 打卡 is in the 词表, and this must not smuggle one in.
public enum BodyScanCadence {
    public static let days = 7

    /// Whole days until the next worthwhile scan. Zero means it is worth taking now.
    public static func daysLeft(since last: Date, now: Date = Date(),
                                calendar: Calendar = .current) -> Int {
        let elapsed = calendar.dateComponents([.day],
                                              from: calendar.startOfDay(for: last),
                                              to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, days - max(0, elapsed))
    }

    public static func isDue(since last: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        daysLeft(since: last, now: now, calendar: calendar) == 0
    }

    /// What the first scan and the latest one say, as a difference.
    ///
    /// Two scans taken on the same day are one data point, not a trend: a "since baseline"
    /// built from them would print a change that is entirely the hour of the measurement.
    public struct Change: Equatable {
        public let days: Int
        public let bodyFatPoints: Double?
        public let leanKg: Double?
        public init(days: Int, bodyFatPoints: Double?, leanKg: Double?) {
            self.days = days
            self.bodyFatPoints = bodyFatPoints
            self.leanKg = leanKg
        }
    }

    public static func change(firstAt: Date, firstFat: Double?, firstLean: Double?,
                              latestAt: Date, latestFat: Double?, latestLean: Double?,
                              calendar: Calendar = .current) -> Change? {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: firstAt),
                                           to: calendar.startOfDay(for: latestAt)).day ?? 0
        guard days >= 1 else { return nil }
        let fat = (firstFat != nil && latestFat != nil) ? latestFat! - firstFat! : nil
        let lean = (firstLean != nil && latestLean != nil) ? latestLean! - firstLean! : nil
        guard fat != nil || lean != nil else { return nil }
        return Change(days: days, bodyFatPoints: fat, leanKg: lean)
    }
}
