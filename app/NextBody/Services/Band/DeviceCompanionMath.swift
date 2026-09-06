import Foundation

/// Inclusive user days this HOOP has been with the health account. WITH YOU.
///
/// The start is the earliest wrist tick or bind on this account — not the latest
/// `devices.bound_at` after a radio swap, and not firmware saveDays.
enum DeviceCompanionMath: Sendable {
    /// Earliest real instant wins. Empty / all-nil is missing.
    static func start(candidates: [Date?]) -> Date? {
        candidates.compactMap { $0 }.min()
    }

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
