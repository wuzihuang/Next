import Foundation

struct BodyBatteryDayFacts: Equatable, Sendable {
    var day: UserDay
    var wake: Int?
    var now: Int?
    var nightCharge: Double?
    var worn: Bool?
    var isOpen: Bool

    /// A morning peak the page can put on a bar or a heat cell. Today counts
    /// once `bbWake` is set — that number is frozen at wake, unlike training load.
    var hasWake: Bool { wake != nil }
}

struct BodyBatteryWeekRoll: Equatable, Sendable {
    var start: UserDay
    var end: UserDay
    var days: Int
    var wornDays: Int
    var average: Double?
}

/// Arithmetic for BODY BATTERY's three windows. No SwiftUI: the view only
/// lays out what this file already reduced. Week and month heroes are a
/// typical morning peak, never a 7-day or 30-day sum.
enum BodyBatteryWindowMath {
    /// Mean of days that published a wake peak. Empty slots stay out of the
    /// denominator — they are not zero.
    static func averageWake(_ days: [BodyBatteryDayFacts]) -> Double? {
        let values = days.filter(\.hasWake).compactMap { $0.wake.map(Double.init) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Month hero: a typical morning. Same grain as the week hero.
    static func typicalWake(_ days: [BodyBatteryDayFacts]) -> Double? {
        averageWake(days)
    }

    static func typicalNightCharge(_ days: [BodyBatteryDayFacts]) -> Double? {
        let values = days.filter(\.hasWake).compactMap(\.nightCharge)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func wornCount(_ days: [BodyBatteryDayFacts]) -> Int {
        days.filter { $0.hasWake || $0.worn == true }.count
    }

    static func emptyCount(_ days: [BodyBatteryDayFacts]) -> Int {
        days.filter { !$0.hasWake }.count
    }

    static func peakDay(_ days: [BodyBatteryDayFacts]) -> BodyBatteryDayFacts? {
        days.filter(\.hasWake).max { ($0.wake ?? 0) < ($1.wake ?? 0) }
    }

    /// Four week rolls, oldest first. A 30-day window becomes 9 + 7 + 7 + 7.
    static func weekRolls(_ days: [BodyBatteryDayFacts]) -> [BodyBatteryWeekRoll] {
        guard !days.isEmpty else { return [] }
        var rolls: [BodyBatteryWeekRoll] = []
        var cursor = days.count
        while cursor > 0 {
            let start = max(0, cursor - 7)
            let slice = Array(days[start..<cursor])
            cursor = start
            rolls.append(BodyBatteryWeekRoll(
                start: slice[0].day,
                end: slice[slice.count - 1].day,
                days: slice.count,
                wornDays: wornCount(slice),
                average: averageWake(slice)))
        }
        return rolls.reversed()
    }
}
