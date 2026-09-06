import Foundation

enum TrainingBand: String, Equatable, Sendable {
    case light = "LIGHT"
    case steady = "STEADY"
    case heavy = "HEAVY"
    case over = "OVER"
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
        days.filter { $0.load != nil || $0.worn == true }.count
    }

    static func emptyCount(_ days: [TrainingDayFacts]) -> Int {
        days.count - wornCount(days)
    }

    /// A day counts as a session when it spent 20 minutes at Z4 or above.
    static func sessionDays(_ days: [TrainingDayFacts]) -> Int {
        days.filter { ($0.hardMinutes ?? 0) >= hardSessionMinutes }.count
    }

    static func band(load: Double, zone: ClosedRange<Double>?) -> TrainingBand {
        if load >= 20.9 { return .over }
        if let zone {
            if load < zone.lowerBound { return .light }
            if load > zone.upperBound { return .heavy }
            return .steady
        }
        if load < 8 { return .light }
        if load < 14 { return .steady }
        if load < 18.5 { return .heavy }
        return .over
    }

    static func bandCounts(_ days: [TrainingDayFacts], zone: ClosedRange<Double>?) -> (light: Int, steady: Int, heavy: Int, over: Int) {
        var light = 0, steady = 0, heavy = 0, over = 0
        for day in days {
            guard let load = day.load, !day.isOpen else { continue }
            switch band(load: load, zone: day.zone ?? zone) {
            case .light:  light += 1
            case .steady: steady += 1
            case .heavy:  heavy += 1
            case .over:   over += 1
            }
        }
        return (light, steady, heavy, over)
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
