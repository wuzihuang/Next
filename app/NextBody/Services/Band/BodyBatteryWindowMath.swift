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

    /// Oldest first. A 30-day window becomes 2 + 7 + 7 + 7 + 7.
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

/// #25 · 未佩戴和真实的 0% 是两件事。An empty battery is a measurement someone earned;
/// a battery with no recent evidence is not, and every entry prints `——` for it rather
/// than a number the wrist never proved. The two states must never share a glyph.
enum BodyBatteryReadout: Equatable, Sendable {
    /// A settled value whose evidence is young enough to print. `dim` marks the
    /// 90-minute-to-six-hour window: the number is real, but it is no longer live.
    case reading(Int, dim: Bool)
    /// Nothing recent enough to print. `since` is the last real tick, when there was one.
    case notWorn(since: Date?)

    var value: Int? {
        if case let .reading(v, _) = self { return v }
        return nil
    }

    /// True while the entry must show a placeholder instead of a number.
    var isPlaceholder: Bool { value == nil }

    var isDim: Bool {
        if case let .reading(_, dim) = self { return dim }
        return true
    }
}

/// One set of thresholds for every body battery entry, so a card and its page can never
/// disagree about whether the wrist is still answering. `TickFreshness` reads them too.
enum BodyBatteryReadoutPolicy {
    /// The number stays real but stops being live.
    static let staleAfter: TimeInterval = 90 * 60
    /// The number stops being printable at all.
    static let goneAfter: TimeInterval = 6 * 3600

    static func readout(value: Int?, observedAt: Date?, now: Date) -> BodyBatteryReadout {
        guard let observedAt, let value else { return .notWorn(since: observedAt) }
        let age = now.timeIntervalSince(observedAt)
        // A future observation is a broken clock, not a fresh reading.
        guard age >= 0, age < goneAfter else { return .notWorn(since: observedAt) }
        return .reading(value, dim: age >= staleAfter)
    }
}
