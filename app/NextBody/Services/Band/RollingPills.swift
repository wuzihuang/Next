import Foundation

/// DAY / WEEK / MONTH on a second-level page. Same three English words;
/// grain and hero stay per instrument (ADR 0012). A natural week is not a window.
///
/// Default last-N is 1 / 7 / 30 user days. Fuel's month is 28 — the caller
/// writes `userDays(month: 28)`. Battery borrows the words and keeps wall hours.
enum RollingPills: String, CaseIterable, Sendable {
    case day = "DAY"
    case week = "WEEK"
    case month = "MONTH"

    static var words: [String] { allCases.map(\.rawValue) }

    static func parse(_ raw: String) -> RollingPills {
        RollingPills(rawValue: raw) ?? .day
    }

    var userDays: Int { userDays(month: 30) }

    func userDays(month: Int) -> Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: month
        }
    }

    var periodKey: String {
        periodKey(day: "TODAY", week: "LAST 7 DAYS", month: "LAST 30 DAYS")
    }

    func periodKey(
        day: String = "TODAY",
        week: String = "LAST 7 DAYS",
        month: String = "LAST 30 DAYS"
    ) -> String {
        switch self {
        case .day: day
        case .week: week
        case .month: month
        }
    }
}
