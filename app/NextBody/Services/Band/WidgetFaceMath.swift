import Foundation

/// The home-screen widgets' numbers, and the rules that decide what they may print.
///
/// The glance is a copy of the facts each size is allowed to draw — body battery
/// (0–100), training load (0–21), EATEN, the band's own charge, the last
/// heart / stress tick, last night's sleep score, and today's ACTIVE / steps /
/// metres. Unlogged intake is `nil`, never `0`. FASTED is `0`. After ninety
/// minutes the live body numbers withdraw; an unlogged EATEN stays "——"
/// because that is still the truth. Last night's score and the band pip do
/// not withdraw with them.
enum WidgetFaceMath {
    static let staleAfter: TimeInterval = 90 * 60
    static let loadCeiling = 21.0
    static let batteryCeiling = 100.0
    static let dash = "——"

    struct Glance: Equatable, Codable, Sendable {
        var numbersAt: Date
        var battery: Int?
        var load: Double?
        var eaten: Double?
        var target: Double?
        var signedIn: Bool
        var bandPercent: Int?
        var bandCharge: String?
        var heartRate: Int?
        var stress: Int?
        var sleepScore: Int?
        var sleepMinutes: Int?
        var activeKcal: Double?
        var steps: Int?
        var distanceM: Int?

        static let empty = Glance(
            numbersAt: .distantPast,
            battery: nil,
            load: nil,
            eaten: nil,
            target: nil,
            signedIn: false,
            bandPercent: nil,
            bandCharge: nil,
            heartRate: nil,
            stress: nil,
            sleepScore: nil,
            sleepMinutes: nil,
            activeKcal: nil,
            steps: nil,
            distanceM: nil)

        /// Gallery / placeholder — the same board numbers as `DataStore.seedToday`.
        static let placeholder = Glance(
            numbersAt: Date(timeIntervalSince1970: 1_778_086_800),
            battery: 72,
            load: 12.4,
            eaten: 1_240,
            target: 1_900,
            signedIn: true,
            bandPercent: 82,
            bandCharge: "unplugged",
            heartRate: 72,
            stress: 31,
            sleepScore: 78,
            sleepMinutes: 432,
            activeKcal: 320,
            steps: 8_432,
            distanceM: 6_200)
    }

    struct TodayReadout: Equatable, Sendable {
        var batteryText: String
        var batteryProgress: Double
        var loadText: String
        var loadProgress: Double
        var eatenText: String
        var eatenProgress: Double
        var bandText: String
        var bandProgress: Double
        var bandLit: Bool
        var heartText: String
        var stressText: String
        var sleepText: String
        var activeText: String
        var stepsText: String
        var distanceText: String
        var stale: Bool
        /// `HH:mm` of `numbersAt` when the live numbers have been withdrawn.
        var clock: String?
        /// `HH:mm` of `numbersAt` while signed in — the large face prints it as TIME.
        var stamp: String?
    }

    static func isFresh(_ glance: Glance, now: Date) -> Bool {
        now.timeIntervalSince(glance.numbersAt) < staleAfter
    }

    static func progress(value: Double?, ceiling: Double) -> Double {
        guard let value, ceiling > 0 else { return 0 }
        return min(1, max(0, value / ceiling))
    }

    static func batteryText(_ value: Int?) -> String {
        guard let value else { return dash }
        return String(value)
    }

    static func loadText(_ value: Double?) -> String {
        guard let value else { return dash }
        return String(format: "%.1f", min(value, 20.9))
    }

    static func kcalText(_ value: Double?) -> String {
        guard let value else { return dash }
        return kcalFormatter.string(from: NSNumber(value: value)) ?? dash
    }

    static func percentText(_ value: Int?) -> String {
        guard let value else { return dash }
        return "\(value)%"
    }

    static func countText(_ value: Int?) -> String {
        guard let value else { return dash }
        return String(value)
    }

    static func groupedText(_ value: Int?) -> String {
        guard let value else { return dash }
        return kcalFormatter.string(from: NSNumber(value: value)) ?? dash
    }

    /// Score first. Duration only when the night has not settled — same hero as page two.
    static func sleepText(score: Int?, minutes: Int?) -> String {
        if let score { return String(score) }
        guard let minutes, minutes > 0 else { return dash }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func kmText(_ metres: Int?) -> String {
        guard let metres else { return dash }
        return String(format: "%.1f", Double(metres) / 1000)
    }

    static func clockText(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    static func bandIsLit(_ charge: String?) -> Bool {
        charge == "charging" || charge == "full"
    }

    /// When the timeline should fire next: the 90-minute withdraw, else a 15-minute tick.
    static func nextReload(after glance: Glance, now: Date) -> Date {
        let staleAt = glance.numbersAt.addingTimeInterval(staleAfter)
        let tick = now.addingTimeInterval(15 * 60)
        if staleAt > now { return min(staleAt, tick) }
        return tick
    }

    static func today(_ glance: Glance, now: Date = Date()) -> TodayReadout {
        let signedOut = !glance.signedIn
        let stale = !signedOut && !isFresh(glance, now: now)
        let hideLive = signedOut || stale
        let eatenKnown = glance.eaten != nil
        let eatenHidden = hideLive && eatenKnown
        let eaten = eatenHidden ? nil : glance.eaten
        return TodayReadout(
            batteryText: hideLive ? dash : batteryText(glance.battery),
            batteryProgress: hideLive ? 0 : progress(
                value: glance.battery.map(Double.init), ceiling: batteryCeiling),
            loadText: hideLive ? dash : loadText(glance.load),
            loadProgress: hideLive ? 0 : progress(value: glance.load, ceiling: loadCeiling),
            eatenText: kcalText(eaten),
            eatenProgress: hideLive
                ? 0
                : FuelCardMath.readout(eaten: glance.eaten, target: glance.target).fill,
            bandText: signedOut ? dash : percentText(glance.bandPercent),
            bandProgress: signedOut
                ? 0
                : progress(value: glance.bandPercent.map(Double.init), ceiling: batteryCeiling),
            bandLit: !signedOut && bandIsLit(glance.bandCharge),
            heartText: hideLive ? dash : countText(glance.heartRate),
            stressText: hideLive ? dash : countText(glance.stress),
            sleepText: signedOut ? dash : sleepText(
                score: glance.sleepScore, minutes: glance.sleepMinutes),
            activeText: hideLive ? dash : kcalText(glance.activeKcal),
            stepsText: hideLive ? dash : groupedText(glance.steps),
            distanceText: hideLive ? dash : kmText(glance.distanceM),
            stale: stale,
            clock: stale ? clockText(glance.numbersAt) : nil,
            stamp: signedOut || glance.numbersAt == .distantPast
                ? nil
                : clockText(glance.numbersAt))
    }

    private static let kcalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
