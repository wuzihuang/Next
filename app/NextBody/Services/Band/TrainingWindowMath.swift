import Foundation

enum TrainingBand: String, Equatable, Sendable {
    case light = "LIGHT"
    case steady = "STEADY"
    case heavy = "HEAVY"
    case over = "OVER"
    case unknown = "NO TARGET"
}

enum TrainingRangeStatus: Equatable, Sendable {
    case noLoad, noTarget, below(Double), inRange, above(Double), capped
}

struct TrainingCurvePoint: Equatable, Sendable {
    var ts: Date
    var load: Double
}

struct TrainingCurveData: Equatable, Sendable {
    var segments: [[TrainingCurvePoint]]
    var gaps: [DateInterval]
}

struct TrainingDayFacts: Equatable, Sendable {
    var day: UserDay
    var load: Double?
    var target: Double?
    var zone: ClosedRange<Double>?
    var zoneMinutes: [Int]?
    var steps: Int?
    var activeKcal: Double?
    var totalKcal: Double?
    var worn: Bool?
    var isOpen: Bool

    var hardMinutes: Int? {
        guard let zoneMinutes, zoneMinutes.count >= 5 else { return nil }
        return zoneMinutes.dropFirst(3).reduce(0, +)
    }

    var easyMinutes: Int? {
        guard let zoneMinutes, zoneMinutes.count >= 5 else { return nil }
        return zoneMinutes.prefix(3).reduce(0, +)
    }

    /// A finished day that actually published a load. Today and a missing day stay out.
    var isFinishedLoad: Bool { !isOpen && load != nil }
}

struct TrainingWeekRoll: Equatable, Sendable {
    var start: UserDay
    var end: UserDay
    var days: Int
    var wornDays: Int
    var average: Double?
}

/// Arithmetic for the training page's three windows. No SwiftUI: the view only
/// lays out what this file already reduced.
enum TrainingWindowMath {
    static let fullRing: Double = 21
    static let hardSessionMinutes = 20

    /// Oldest → newest, `count` user days ending at `end`.
    /// Mean of finished days that published a load. An open today and an empty
    /// slot stay out of the denominator — they are not zero.
    static func averageLoad(_ days: [TrainingDayFacts]) -> Double? {
        let values = days.filter(\.isFinishedLoad).compactMap(\.load)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Month hero: a typical finished day. Same grain as the week hero — never a 30-day sum.
    static func typicalLoad(_ days: [TrainingDayFacts]) -> Double? {
        averageLoad(days)
    }

    static func typicalSteps(_ days: [TrainingDayFacts]) -> Double? {
        let values = days.filter(\.isFinishedLoad).compactMap { $0.steps.map(Double.init) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func typicalActiveKcal(_ days: [TrainingDayFacts]) -> Double? {
        let values = days.filter(\.isFinishedLoad).compactMap(\.activeKcal)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func typicalTotalKcal(_ days: [TrainingDayFacts]) -> Double? {
        let values = days.filter(\.isFinishedLoad).compactMap(\.totalKcal)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// One typical day's five zones. Days without zones stay out.
    static func typicalZones(_ days: [TrainingDayFacts]) -> [Double]? {
        let rows = days.filter(\.isFinishedLoad).compactMap { day -> [Int]? in
            guard let z = day.zoneMinutes, z.count >= 5 else { return nil }
            return Array(z.prefix(5))
        }
        guard !rows.isEmpty else { return nil }
        return (0..<5).map { i in
            Double(rows.reduce(0) { $0 + $1[i] }) / Double(rows.count)
        }
    }

    static func wornCount(_ days: [TrainingDayFacts]) -> Int {
        days.filter { $0.worn == true }.count
    }

    /// A published zero is a recorded load; it is not proof of wearing the band.
    static func recordedCount(_ days: [TrainingDayFacts]) -> Int {
        days.filter { $0.load != nil }.count
    }

    static func emptyCount(_ days: [TrainingDayFacts]) -> Int {
        days.count - recordedCount(days)
    }

    /// A day counts as a session when it spent 20 minutes at Z4 or above.
    static func sessionDays(_ days: [TrainingDayFacts]) -> Int {
        days.filter { ($0.hardMinutes ?? 0) >= hardSessionMinutes }.count
    }

    static func band(load: Double, zone: ClosedRange<Double>?) -> TrainingBand {
        guard let zone else { return .unknown }
        if load >= 20.9 { return .over }
        if load < zone.lowerBound { return .light }
        if load > zone.upperBound { return .heavy }
        return .steady
    }

    static func bandCounts(_ days: [TrainingDayFacts]) -> (light: Int, steady: Int, heavy: Int, over: Int, unknown: Int) {
        var light = 0, steady = 0, heavy = 0, over = 0, unknown = 0
        for day in days {
            guard let load = day.load, !day.isOpen else { continue }
            switch band(load: load, zone: day.zone) {
            case .light:  light += 1
            case .steady: steady += 1
            case .heavy:  heavy += 1
            case .over:   over += 1
            case .unknown: unknown += 1
            }
        }
        return (light, steady, heavy, over, unknown)
    }

    static func rangeStatus(load: Double?, target: Double?, zone: ClosedRange<Double>?) -> TrainingRangeStatus {
        guard let load, load.isFinite else { return .noLoad }
        if load >= 20.9 { return .capped }
        guard let range = zone ?? target.map({ $0...$0 }) else { return .noTarget }
        if load < range.lowerBound { return .below(range.lowerBound - load) }
        if load > range.upperBound { return .above(load - range.upperBound) }
        return .inRange
    }

    /// All columns share a minute scale, so 100 minutes is ten times 10 minutes.
    static func zoneScaleMinutes(_ days: [TrainingDayFacts]) -> Double {
        max(1, days.map { Double(($0.easyMinutes ?? 0) + ($0.hardMinutes ?? 0)) }.max() ?? 0)
    }

    /// A five-minute sample contributes only its recorded value. Missing slots split
    /// the line; first/last missing intervals are visible too. Future time is not a gap.
    static func curveData(_ input: [TrainingCurvePoint], day: UserDay, through: Date) -> TrainingCurveData {
        let end = max(day.start, min(through, day.end))
        let points = input.filter {
            $0.ts >= day.start && $0.ts <= end && $0.load.isFinite && (0...21).contains($0.load)
        }.sorted { $0.ts < $1.ts }
        guard let first = points.first else {
            return TrainingCurveData(segments: [], gaps: end > day.start ? [DateInterval(start: day.start, end: end)] : [])
        }
        var segments = [[first]]
        var gaps: [DateInterval] = []
        if first.ts > day.start {
            gaps.append(DateInterval(start: day.start, end: first.ts))
        }
        for point in points.dropFirst() {
            guard let previous = segments.last?.last else { continue }
            if point.ts == previous.ts { continue }
            if point.ts.timeIntervalSince(previous.ts) > 450 {
                gaps.append(DateInterval(start: previous.ts.addingTimeInterval(300), end: point.ts))
                segments.append([point])
            } else {
                segments[segments.count - 1].append(point)
            }
        }
        if let last = segments.last?.last {
            let coveredThrough = last.ts.addingTimeInterval(300)
            if end.timeIntervalSince(coveredThrough) >= 300 {
                gaps.append(DateInterval(start: coveredThrough, end: end))
            }
        }
        return TrainingCurveData(segments: segments, gaps: gaps)
    }

    static func dayFraction(_ instant: Date, day: UserDay) -> Double {
        max(0, min(1, instant.timeIntervalSince(day.start) / day.end.timeIntervalSince(day.start)))
    }

    /// Week rolls, oldest first. Groups of seven walking back from the end;
    /// a 30-day window is 2 + 7 + 7 + 7 + 7.
    static func weekRolls(_ days: [TrainingDayFacts]) -> [TrainingWeekRoll] {
        UserDay.weekRolls(count: days.count).map { range in
            let slice = Array(days[range])
            return TrainingWeekRoll(
                start: slice[0].day,
                end: slice[slice.count - 1].day,
                days: slice.count,
                wornDays: wornCount(slice),
                average: averageLoad(slice))
        }
    }
}
