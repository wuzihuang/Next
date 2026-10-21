import Foundation

/// The home-screen widgets' numbers, and the rules that decide what they may print.
///
/// The glance is a copy of the facts each size is allowed to draw — body battery
/// (0–100), training load (0–21), last night's SLEEP, the band's own charge, the
/// last heart / stress tick, today's ACTIVE / steps / metres, and last night's
/// resting pulse / HRV / SpO2. After ninety minutes the live body numbers
/// withdraw. Last night's score, resting pulse, HRV, SpO2 and the band pip do
/// not withdraw with them.
///
/// Body battery is the exception: it keeps `TickFreshness`'s three states so
/// the widget and the app agree about the same tick. Ninety minutes only dims
/// it (the app shows SYNCED HH:MM at that point); the number itself withdraws
/// at six hours. A widget that blanked at ninety while the app still printed
/// the score read as a bug, not as a freshness rule.
enum WidgetFaceMath {
    static let staleAfter: TimeInterval = 90 * 60
    /// `TickFreshness.gone` — the age at which the reserve score stops being printable.
    static let goneAfter: TimeInterval = 6 * 3600
    static let loadCeiling = 21.0
    static let batteryCeiling = 100.0
    static let dash = "——"

    struct Glance: Equatable, Codable, Sendable {
        var numbersAt: Date
        var battery: Int?
        var load: Double?
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
        var nightRhr: Int?
        var nightHrv: Int?
        var spo2: Int?
        /// Independent clock: a meal/heart update cannot renew an old reserve score.
        /// Absent in legacy glances, which cannot prove reserve freshness.
        var batteryObservedAt: Date? = nil

        static let empty = Glance(
            numbersAt: .distantPast,
            battery: nil,
            load: nil,
            signedIn: false,
            bandPercent: nil,
            bandCharge: nil,
            heartRate: nil,
            stress: nil,
            sleepScore: nil,
            sleepMinutes: nil,
            activeKcal: nil,
            steps: nil,
            distanceM: nil,
            nightRhr: nil,
            nightHrv: nil,
            spo2: nil)

        /// Gallery / placeholder — the same board numbers as `DataStore.seedToday`.
        static let placeholder = Glance(
            numbersAt: Date(timeIntervalSince1970: 1_778_086_800),
            battery: 72,
            load: 12.4,
            signedIn: true,
            bandPercent: 82,
            bandCharge: "unplugged",
            heartRate: 72,
            stress: 31,
            sleepScore: 78,
            sleepMinutes: 432,
            activeKcal: 320,
            steps: 8_432,
            distanceM: 6_200,
            nightRhr: 52,
            nightHrv: 54,
            spo2: 96,
            batteryObservedAt: Date(timeIntervalSince1970: 1_778_086_800))
    }

    struct TodayReadout: Equatable, Sendable {
        var batteryText: String
        var batteryProgress: Double
        /// The reserve tick is 90 minutes to under 6 hours old — printed, but unlit.
        var batteryDim: Bool = false
        var loadText: String
        var loadProgress: Double
        var bandText: String
        var bandProgress: Double
        var bandLit: Bool
        var heartText: String
        var stressText: String
        var sleepText: String
        var sleepProgress: Double
        /// Last night's `h:mm` — the large face's SLEPT cell, the duration the
        /// score ring does not carry.
        var sleepClockText: String
        var activeText: String
        var stepsText: String
        var distanceText: String
        var rhrText: String
        var hrvText: String
        var spo2Text: String
        var stale: Bool
        /// `HH:mm` of `numbersAt` when the live numbers have been withdrawn.
        var clock: String?
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
        return nightClock(minutes)
    }

    /// The night's `h:mm`, regardless of whether a score landed.
    static func nightClock(_ minutes: Int?) -> String {
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
        var next = staleAt > now ? min(staleAt, tick) : tick
        if let at = glance.batteryObservedAt {
            // Both reserve edges: the dim at ninety minutes and the withdraw at six hours.
            for edge in [at.addingTimeInterval(staleAfter), at.addingTimeInterval(goneAfter)]
            where edge > now {
                next = min(next, edge)
            }
        }
        return next
    }

    static func today(_ glance: Glance, now: Date = Date()) -> TodayReadout {
        let signedOut = !glance.signedIn
        let stale = !signedOut && !isFresh(glance, now: now)
        let hideLive = signedOut || stale
        // The reserve score answers to its own clock, so a meal or a heart tick cannot
        // renew it — but a glance too old to carry `batteryObservedAt` proves nothing
        // either way, and falls back to the live window rather than blanking outright.
        let batteryAge = glance.batteryObservedAt.map { now.timeIntervalSince($0) }
        let hideBattery = signedOut
            || (batteryAge.map { $0 < 0 || $0 >= goneAfter } ?? hideLive)
        let dimBattery = !hideBattery && (batteryAge.map { $0 >= staleAfter } ?? false)
        return TodayReadout(
            batteryText: hideBattery ? dash : batteryText(glance.battery),
            batteryProgress: hideBattery ? 0 : progress(
                value: glance.battery.map(Double.init), ceiling: batteryCeiling),
            batteryDim: dimBattery,
            loadText: hideLive ? dash : loadText(glance.load),
            loadProgress: hideLive ? 0 : progress(value: glance.load, ceiling: loadCeiling),
            bandText: signedOut ? dash : percentText(glance.bandPercent),
            bandProgress: signedOut
                ? 0
                : progress(value: glance.bandPercent.map(Double.init), ceiling: batteryCeiling),
            bandLit: !signedOut && bandIsLit(glance.bandCharge),
            heartText: hideLive ? dash : countText(glance.heartRate),
            stressText: hideLive ? dash : countText(glance.stress),
            sleepText: signedOut ? dash : sleepText(
                score: glance.sleepScore, minutes: glance.sleepMinutes),
            sleepProgress: signedOut ? 0 : progress(
                value: glance.sleepScore.map(Double.init), ceiling: batteryCeiling),
            sleepClockText: signedOut ? dash : nightClock(glance.sleepMinutes),
            activeText: hideLive ? dash : kcalText(glance.activeKcal),
            stepsText: hideLive ? dash : groupedText(glance.steps),
            distanceText: hideLive ? dash : kmText(glance.distanceM),
            rhrText: signedOut ? dash : countText(glance.nightRhr),
            hrvText: signedOut ? dash : countText(glance.nightHrv),
            spo2Text: signedOut ? dash : countText(glance.spo2),
            stale: stale,
            clock: stale ? clockText(glance.numbersAt) : nil)
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
