import Foundation

/// Arithmetic for the heart page's three windows. No SwiftUI: the view only lays out
/// what this file already reduced.
public enum HeartWindowMath {
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }

    /// One median a day, then the median of those. A two-hour nap does not drag a week.
    public static func medianOfDailyMedians(_ daily: [[Double]]) -> Double? {
        median(daily.compactMap { median($0) })
    }

    /// A day counts as worn when it filed at least one value. Empty is not zero.
    public static func wornDays(_ daily: [[Double]]) -> Int {
        daily.filter { !$0.isEmpty }.count
    }

    public static func extreme(_ daily: [[Double]], pick: (Double, Double) -> Double) -> Double? {
        let flat = daily.flatMap { $0 }
        guard let first = flat.first else { return nil }
        return flat.dropFirst().reduce(first, pick)
    }

    /// How wide one equal slot is when `span` covers `days` user days. DST makes a day
    /// 23 or 25 hours; dividing the real span keeps one bar a day.
    public static func slotSeconds(span: TimeInterval, days: Int) -> TimeInterval {
        guard days > 0, span > 0 else { return 0 }
        return span / Double(days)
    }

    /// Which of `days` equal slots `fraction` lands in. Clamped, never extrapolated.
    public static func slotIndex(fraction: Double, days: Int) -> Int {
        guard days > 0 else { return 0 }
        let clamped = min(1, max(0, fraction))
        return min(days - 1, max(0, Int((clamped * Double(days)).rounded(.down))))
    }
}
