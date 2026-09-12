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

/// 13 · WHY <n> as a ledger. One signed row per term and the balance after it; the last
/// balance is the hero number. Terms carry their own sign: recovery is the only one that
/// ever charges, the other three only ever drain.
struct BodyBatteryLedgerRow: Equatable, Sendable {
    enum Term: Equatable, Sendable { case recovery, awake, movement, stress }
    var term: Term
    var delta: Int
    var balance: Int
}

enum BodyBatteryLedgerMath {
    /// The server closes its four terms to `current − anchor` within ±0.5 before it publishes.
    /// The page prints integers, so the rounding residual (at most ±2) lands on the largest
    /// term instead of leaving the column one short of the number at the top.
    static func rows(anchor: Int, recovery: Double, awake: Double, movement: Double,
                     stress: Double, current: Int) -> [BodyBatteryLedgerRow] {
        let terms: [(BodyBatteryLedgerRow.Term, Double)] = [
            (.recovery, recovery), (.awake, awake), (.movement, movement), (.stress, stress),
        ]
        var deltas = terms.map { Int($0.1.rounded()) }
        let residual = (current - anchor) - deltas.reduce(0, +)
        if residual != 0,
           let widest = terms.indices.max(by: { abs(terms[$0].1) < abs(terms[$1].1) }) {
            deltas[widest] += residual
        }
        var balance = anchor
        return zip(terms, deltas).map { term, delta in
            balance += delta
            return BodyBatteryLedgerRow(term: term.0, delta: delta, balance: balance)
        }
    }

    /// Minutes awake inside this user day up to the last observation, on the five-minute
    /// grid the ticks live on. nil without a recorded wake: a day that started from an
    /// assumed anchor has no moment the wearer is known to have woken.
    static func awakeMinutes(wakeAt: Date?, dayStart: Date, observedAt: Date?) -> Int? {
        guard let wakeAt, let observedAt else { return nil }
        let minutes = observedAt.timeIntervalSince(max(wakeAt, dayStart)) / 60
        guard minutes >= 5 else { return nil }
        return Int((minutes / 5).rounded()) * 5
    }

    /// Five-minute ticks the drain model charged for stress: the index sat above 40.
    /// nil when no tick carried a stress index at all — missing is not calm.
    static func stressedMinutes(_ samples: [VitalSample], above threshold: Int = 40) -> Int? {
        let scored = samples.compactMap(\.stress)
        guard !scored.isEmpty else { return nil }
        return scored.filter { $0 > threshold }.count * 5
    }

    /// One of three words for the night's charge multiplier, around a ±3 % band of 1.00.
    enum Pace: Equatable, Sendable { case slower, usual, faster }
    static func pace(of multiplier: Double) -> Pace {
        if multiplier < 0.97 { return .slower }
        if multiplier > 1.03 { return .faster }
        return .usual
    }
}
