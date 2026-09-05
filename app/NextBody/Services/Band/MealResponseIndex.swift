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
        let todayStart = userDayStart(containing: now, calendar: calendar, dayBoundaryHour: dayBoundaryHour)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400)
        let windowStart = now.addingTimeInterval(-24 * 60 * 60)

        let daysWithPoints = Set(valid.map {
            userDayStart(containing: $0.ts, calendar: calendar, dayBoundaryHour: dayBoundaryHour)
        })
        let daytime = valid.filter { point in
            let dayStart = userDayStart(containing: point.ts, calendar: calendar, dayBoundaryHour: dayBoundaryHour)
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

    static func userDayStart(containing instant: Date, calendar: Calendar, dayBoundaryHour: Int) -> Date {
        let cal = calendar
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: instant)
        var start = cal.date(from: DateComponents(
            year: comps.year, month: comps.month, day: comps.day, hour: 0, minute: 0, second: 0))!
        if (comps.hour ?? 0) < dayBoundaryHour {
            start = cal.date(byAdding: .day, value: -1, to: start) ?? start
        }
        return cal.date(byAdding: .hour, value: dayBoundaryHour, to: start) ?? start
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
