import Foundation

/// Unitless meal-response index versus this wrist's own daytime median.
///
/// Vendor optical scalars stay opaque. Screens print only the signed percent, the empty
/// reason, and the Below / Near / Above counts. Near is ±8 % (ratio 0.92–1.08).
enum MealResponseIndex {
    struct Point: Equatable, Hashable, Sendable {
        var ts: Date
        var optical: Double
    }

    struct SleepWindow: Equatable, Sendable {
        var start: Date
        var end: Date

        func contains(_ ts: Date) -> Bool {
            ts >= start && ts < end
        }
    }

    enum Empty: String, Equatable, Sendable {
        case needs5Days = "NEEDS5"
        case switchOff = "OFF"
        case allZeros = "ZERO"
        case empty = "EMPTY"
    }

    struct ScatterPoint: Equatable, Sendable {
        var ts: Date
        var percent: Int
    }

    struct Result: Equatable, Sendable {
        /// Latest valid vendor point in today's 04:00 user day. This can be shown before
        /// the five-day personal baseline is ready.
        var latestPoint: Double?
        /// Raw valid points in the rolling 24-hour chart window.
        var trendPoints: [Point]
        var median24hPoint: Double?
        /// Daytime median after five valid days. Nil until then — never a guessed centre.
        var ownMedian: Double?
        var baselineDays: Int
        var hero: Int?
        var median24h: Int?
        var ownMedianReady: Bool
        var below: Int
        var near: Int
        var above: Int
        var empty: Empty?
        var percents: [ScatterPoint]

        var analyticsState: String {
            if latestPoint != nil { return "FRESH" }
            return empty?.rawValue ?? "EMPTY"
        }
    }

    static func signedPercent(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "−\(abs(value))" }
        return "0"
    }

    static func pointValue(_ value: Double) -> String {
        let rounded = value.rounded()
        return abs(value - rounded) < 0.05
            ? String(Int(rounded))
            : String(format: "%.1f", value)
    }

    static func make(
        points: [Point],
        sleepWindows: [SleepWindow],
        now: Date,
        switchOff: Bool = false,
        allZeros: Bool = false,
        calendar: Calendar = .current,
        dayBoundaryHour: Int = 4
    ) -> Result {
        let valid = points.filter { $0.optical.isFinite && $0.optical > 0 }
        let todayStart = UserDay.containing(now, calendar: calendar, boundaryHour: dayBoundaryHour).start
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400)
        let windowStart = now.addingTimeInterval(-24 * 60 * 60)

        let daysWithPoints = Set(valid.map {
            UserDay.containing($0.ts, calendar: calendar, boundaryHour: dayBoundaryHour).start
        })
        let daytime = valid.filter { point in
            let dayStart = UserDay.containing(point.ts, calendar: calendar, boundaryHour: dayBoundaryHour).start
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
            let hasNight = sleepWindows.contains { window in
                window.start < dayEnd && window.end > dayStart
            }
            if !hasNight { return true }
            return !sleepWindows.contains { $0.contains(point.ts) }
        }
        let ownMedian = daysWithPoints.count >= 5 ? median(daytime.map(\.optical)) : nil
        let ownMedianReady = ownMedian != nil && (ownMedian ?? 0) > 0

        func percent(of optical: Double) -> Int? {
            guard let ownMedian, ownMedian > 0 else { return nil }
            return Int((100 * (optical / ownMedian - 1)).rounded())
        }

        let todayPoints = valid.filter { $0.ts >= todayStart && $0.ts < todayEnd && $0.ts <= now }
            .sorted { $0.ts < $1.ts }
        let heroOptical = todayPoints.last?.optical
        let hero = heroOptical.flatMap(percent)

        let trendPoints = valid.filter { $0.ts >= windowStart && $0.ts <= now }
            .sorted { $0.ts < $1.ts }
        let median24hPoint = median(trendPoints.map(\.optical))

        let todayPercents = todayPoints.compactMap { point -> Int? in
            percent(of: point.optical)
        }
        let median24h = median(todayPercents.map(Double.init)).map { Int($0.rounded()) }

        let percents: [ScatterPoint]
        if ownMedianReady {
            percents = valid.compactMap { point -> ScatterPoint? in
                guard point.ts >= windowStart, point.ts <= now, let value = percent(of: point.optical)
                else { return nil }
                return ScatterPoint(ts: point.ts, percent: value)
            }
            .sorted { $0.ts < $1.ts }
        } else {
            percents = []
        }

        var below = 0, near = 0, above = 0
        if let ownMedian, ownMedian > 0 {
            for point in valid where point.ts >= windowStart && point.ts <= now {
                let ratio = point.optical / ownMedian
                if ratio < 0.92 { below += 1 }
                else if ratio > 1.08 { above += 1 }
                else { near += 1 }
            }
        }

        let empty: Empty?
        if heroOptical == nil, switchOff {
            empty = .switchOff
        } else if heroOptical == nil, allZeros {
            empty = .allZeros
        } else if heroOptical != nil {
            empty = nil
        } else if !ownMedianReady {
            empty = .needs5Days
        } else {
            empty = .empty
        }

        return Result(
            latestPoint: heroOptical,
            trendPoints: trendPoints,
            median24hPoint: median24hPoint,
            ownMedian: ownMedian,
            baselineDays: min(daysWithPoints.count, 5),
            hero: hero,
            median24h: median24h,
            ownMedianReady: ownMedianReady,
            below: below,
            near: near,
            above: above,
            empty: empty,
            percents: percents)
    }

    /// Rolling windows the RESPONSE board can open. Day is a clock; week and month are
    /// user days counted backwards from today, never a calendar week or month.
    enum Horizon: Equatable, Sendable {
        case rolling24Hours
        case userDays(Int)
    }

    /// One user day on the week / month board. `mean` is the day's own arithmetic mean.
    /// A day with no valid point stays empty — it is never a zero.
    struct DaySlot: Equatable, Sendable {
        var start: Date
        var mean: Double?
        var count: Int
    }

    /// Below / Near / Above versus this wrist's own daytime median. Near is ±8 %.
    enum Band: Equatable, Sendable {
        case below, near, above

        static func of(optical: Double, ownMedian: Double) -> Band? {
            guard ownMedian > 0, optical.isFinite, optical > 0 else { return nil }
            let ratio = optical / ownMedian
            if ratio < 0.92 { return .below }
            if ratio > 1.08 { return .above }
            return .near
        }
    }

    /// What a week or month window reduces to, once. The hero is the mean of the daily
    /// means — two high days pull it up, a busy day of twenty ticks does not outweigh a
    /// quiet one. Empty days stay out of the average so a gap cannot read as a low week.
    struct HorizonWindow: Equatable, Sendable {
        var horizon: Horizon
        var points: [Point]
        var slots: [DaySlot]
        var dailyMean: Double?
        var below: Int
        var near: Int
        var above: Int
        var recordedDays: Int
    }

    static func percent(of optical: Double, ownMedian: Double) -> Int? {
        guard ownMedian > 0, optical.isFinite, optical > 0 else { return nil }
        return Int((100 * (optical / ownMedian - 1)).rounded())
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Observed optical range with room around the own median, so a quiet day is not
    /// flattened against a 1-point ruler.
    static func axis(values: [Double], ownMedian: Double?) -> ClosedRange<Double>? {
        guard let lo = values.min(), let hi = values.max() else { return nil }
        let pad = max(4, (hi - lo) * 0.12)
        var lower = lo - pad
        var upper = hi + pad
        if let ownMedian, ownMedian > 0 {
            lower = min(lower, ownMedian * 0.85)
            upper = max(upper, ownMedian * 1.15)
        }
        if upper - lower < 8 { upper = lower + 8 }
        return lower...upper
    }

    static func daySlots(
        points: [Point],
        todayStart: Date,
        days: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [DaySlot] {
        let valid = points.filter { $0.optical.isFinite && $0.optical > 0 && $0.ts <= now }
        return (0..<max(1, days)).reversed().map { offset in
            let start = calendar.date(byAdding: .day, value: -offset, to: todayStart)
                ?? todayStart.addingTimeInterval(Double(-offset) * 86_400)
            let end = calendar.date(byAdding: .day, value: 1, to: start)
                ?? start.addingTimeInterval(86_400)
            let inDay = valid.filter { $0.ts >= start && $0.ts < end }
            return DaySlot(start: start, mean: mean(inDay.map(\.optical)), count: inDay.count)
        }
    }

    static func horizonWindow(
        points: [Point],
        ownMedian: Double?,
        now: Date,
        horizon: Horizon,
        calendar: Calendar = .current,
        dayBoundaryHour: Int = 4
    ) -> HorizonWindow {
        let valid = points.filter { $0.optical.isFinite && $0.optical > 0 && $0.ts <= now }
        let todayStart = UserDay.containing(now, calendar: calendar, boundaryHour: dayBoundaryHour).start

        let windowPoints: [Point]
        let slots: [DaySlot]
        switch horizon {
        case .rolling24Hours:
            let start = now.addingTimeInterval(-24 * 60 * 60)
            windowPoints = valid.filter { $0.ts >= start }.sorted { $0.ts < $1.ts }
            slots = []
        case .userDays(let days):
            slots = daySlots(points: valid, todayStart: todayStart, days: days, now: now, calendar: calendar)
            let start = slots.first?.start ?? todayStart
            windowPoints = valid.filter { $0.ts >= start }.sorted { $0.ts < $1.ts }
        }

        var below = 0, near = 0, above = 0
        if let ownMedian, ownMedian > 0 {
            for point in windowPoints {
                switch Band.of(optical: point.optical, ownMedian: ownMedian) {
                case .below: below += 1
                case .near:  near += 1
                case .above: above += 1
                case nil:    break
                }
            }
        }

        let recorded = slots.filter { $0.mean != nil }
        return HorizonWindow(
            horizon: horizon,
            points: windowPoints,
            slots: slots,
            dailyMean: mean(recorded.map { $0.mean! }),
            below: below,
            near: near,
            above: above,
            recordedDays: recorded.count)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
