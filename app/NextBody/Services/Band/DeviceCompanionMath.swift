import Foundation

/// Inclusive user days this binding has lasted. The device page's WITH YOU cell.
///
/// `devices.bound_at` is the start of the current 手环归属. It is not consecutive
/// wear, and it is not how many days of history the firmware still holds.
enum DeviceCompanionMath: Sendable {
    /// Same user day is 1. A missing or future stamp is nil — the page draws a dash
    /// instead of inventing a day count.
    static func days(boundAt: Date?, now: Date, calendar: Calendar = .current) -> Int? {
        guard let boundAt else { return nil }
        let start = UserDay.containing(boundAt, calendar: calendar)
        let end = UserDay.containing(now, calendar: calendar)
        let delta = calendar.dateComponents([.day], from: start.date, to: end.date).day ?? 0
        guard delta >= 0 else { return nil }
        return delta + 1
    }
}
