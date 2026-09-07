import Foundation

/// Published energy weights, not raw sensor MET. Both components exclude resting.
struct FuelEnergyPoint: Codable, Hashable {
    let epoch: Double
    let originWeight: Double
    let strengthWeight: Double
    var tick: VitalSample {
        VitalSample(ts: Date(timeIntervalSince1970: epoch), hr: nil, stress: nil,
                    met: 1 + (originWeight + strengthWeight) / 300)
    }
}

struct FuelDayFacts: Equatable, Sendable {
    var day: UserDay
    var intake: Double?
    var burned: Double?
    var foodCount: Int
    var isFasted: Bool
    var isOpen: Bool

    init(day: UserDay, intake: Double?, burned: Double?,
                foodCount: Int, isFasted: Bool, isOpen: Bool) {
        self.day = day
        self.intake = intake
        self.burned = burned
        self.foodCount = foodCount
        self.isFasted = isFasted
        self.isOpen = isOpen
    }

    var gap: Double? {
        guard let intake, let burned else { return nil }
        return intake - burned
    }
}

struct FuelWeekRoll: Equatable, Sendable {
    var start: UserDay
    var end: UserDay
    var days: Int
    var fastedDays: Int
    var avgIn: Double?
    var avgOut: Double?
    var avgGap: Double?
    var intakeDays: Int
    var burnedDays: Int
    var pairedDays: Int
}

struct FuelWindowTotal: Equatable, Sendable {
    var intake: Double?
    var burned: Double?
    var gap: Double?
    var intakeDays: Int
    var burnedDays: Int
    var pairedDays: Int
}

struct FuelClockPoint: Equatable, Sendable {
    var x: Double
    var y: Double
    var startsSegment: Bool
    init(x: Double, y: Double, startsSegment: Bool = false) {
        self.x = x; self.y = y; self.startsSegment = startsSegment
    }
}

/// Arithmetic for the calories page's three windows. No SwiftUI: the view only lays out
/// what this file already reduced.
enum FuelWindowMath {
    /// Known values accumulate independently. A difference needs both values on
    /// the same day; an unlogged day is not a fasted zero.
    static func sum(_ days: [FuelDayFacts]) -> FuelWindowTotal? {
        let ins = days.compactMap(\.intake)
        let outs = days.compactMap(\.burned)
        let gaps = days.compactMap(\.gap)
        guard !ins.isEmpty || !outs.isEmpty else { return nil }
        func sumKnown(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +)
        }
        return FuelWindowTotal(intake: sumKnown(ins), burned: sumKnown(outs), gap: sumKnown(gaps),
                               intakeDays: ins.count, burnedDays: outs.count, pairedDays: gaps.count)
    }

    /// Only days with a recorded value enter that channel's denominator.
    static func perDay(sum: FuelWindowTotal, slots: Int) -> FuelWindowTotal? {
        guard slots > 0 else { return nil }
        return FuelWindowTotal(
            intake: sum.intake.flatMap { sum.intakeDays > 0 ? $0 / Double(sum.intakeDays) : nil },
            burned: sum.burned.flatMap { sum.burnedDays > 0 ? $0 / Double(sum.burnedDays) : nil },
            gap: sum.gap.flatMap { sum.pairedDays > 0 ? $0 / Double(sum.pairedDays) : nil },
            intakeDays: sum.intakeDays, burnedDays: sum.burnedDays, pairedDays: sum.pairedDays)
    }

    /// Four week rolls, newest first. Today remains visible in the daily bars but
    /// an unfinished day cannot lower the estimate of a typical whole day.
    static func weekRolls(_ days: [FuelDayFacts]) -> [FuelWeekRoll] {
        UserDay.weekRolls(count: days.count).reversed().map { range in
            let slice = Array(days[range])
            let closed = slice.filter { !$0.isOpen }
            let total = sum(closed)
            let per = total.flatMap { perDay(sum: $0, slots: slice.count) }
            return FuelWeekRoll(
                start: slice[0].day, end: slice[slice.count - 1].day,
                days: slice.count, fastedDays: closed.filter(\.isFasted).count,
                avgIn: per?.intake, avgOut: per?.burned, avgGap: per?.gap,
                intakeDays: per?.intakeDays ?? 0, burnedDays: per?.burnedDays ?? 0,
                pairedDays: per?.pairedDays ?? 0)
        }
    }

    /// Weight week averages by their observed days; sparse weeks do not count as
    /// seven zeros or carry the same weight as a fully observed week.
    static func typicalDay(_ rolls: [FuelWeekRoll]) -> FuelWindowTotal? {
        let intakeDays = rolls.reduce(0) { $0 + $1.intakeDays }
        let burnedDays = rolls.reduce(0) { $0 + $1.burnedDays }
        let pairedDays = rolls.reduce(0) { $0 + $1.pairedDays }
        guard intakeDays > 0 || burnedDays > 0 else { return nil }
        let intake = rolls.reduce(0.0) { $0 + ($1.avgIn ?? 0) * Double($1.intakeDays) }
        let burned = rolls.reduce(0.0) { $0 + ($1.avgOut ?? 0) * Double($1.burnedDays) }
        let gap = rolls.reduce(0.0) { $0 + ($1.avgGap ?? 0) * Double($1.pairedDays) }
        return FuelWindowTotal(
            intake: intakeDays > 0 ? intake / Double(intakeDays) : nil,
            burned: burnedDays > 0 ? burned / Double(burnedDays) : nil,
            gap: pairedDays > 0 ? gap / Double(pairedDays) : nil,
            intakeDays: intakeDays, burnedDays: burnedDays, pairedDays: pairedDays)
    }

    /// The full user day, local 04:00 to the following 04:00. Calendar arithmetic
    /// preserves the extra/missing hour when daylight saving changes.
    static func dayEnd(dayStart: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: dayStart)!
    }

    static func clockFraction(at date: Date, dayStart: Date, calendar: Calendar = .current) -> Double {
        let span = dayEnd(dayStart: dayStart, calendar: calendar).timeIntervalSince(dayStart)
        return min(1, max(0, date.timeIntervalSince(dayStart) / span))
    }

    static func clockLabels(dayStart: Date, calendar: Calendar = .current) -> [String] {
        let span = dayEnd(dayStart: dayStart, calendar: calendar).timeIntervalSince(dayStart)
        return (0...4).map { i in
            let at = dayStart.addingTimeInterval(span * Double(i) / 4)
            let clock = calendar.dateComponents([.hour, .minute], from: at)
            let hour = clock.hour ?? 0, minute = clock.minute ?? 0
            return minute == 0 ? String(format: "%02d", hour) : String(format: "%02d:%02d", hour, minute)
        }
    }

    /// Step polyline: hold, jump at each meal, hold to `now`, then a dashed run to `projectTo`.
    static func intakeSteps(meals: [(Date, Double)], dayStart: Date, now: Date,
                                   projectTo: Double?, calendar: Calendar = .current) -> (solid: [FuelClockPoint], dashed: [FuelClockPoint]) {
        let nowX = clockFraction(at: now, dayStart: dayStart, calendar: calendar)
        let ordered = meals.sorted { $0.0 < $1.0 }
        var y = 0.0
        var solid = [FuelClockPoint(x: 0, y: 0)]
        for meal in ordered {
            let x = clockFraction(at: meal.0, dayStart: dayStart, calendar: calendar)
            if x > nowX { break }
            if solid.last?.x != x || solid.last?.y != y {
                solid.append(FuelClockPoint(x: x, y: y))
            }
            y += meal.1
            solid.append(FuelClockPoint(x: x, y: y))
        }
        if solid.last?.x != nowX {
            solid.append(FuelClockPoint(x: nowX, y: y))
        }
        var dashed: [FuelClockPoint] = []
        if let projectTo, nowX < 1 {
            dashed = [FuelClockPoint(x: nowX, y: y), FuelClockPoint(x: 1, y: projectTo)]
        } else if nowX < 1 {
            dashed = [FuelClockPoint(x: nowX, y: y), FuelClockPoint(x: 1, y: y)]
        }
        return (solid, dashed)
    }

    /// Same source priority and valid range as `nb.activity_met`: use native MET,
    /// otherwise 500 steps in five minutes approximates 3 MET, capped at 5.
    static func activityMet(met: Double? = nil, steps: Int?) -> Double? {
        if let met, met.isFinite, (0.5...25).contains(met) { return met }
        guard let steps, steps >= 0 else { return nil }
        return 1 + 2 * min(2, Double(steps) / 500)
    }

    /// Resting accumulates with time; activity uses the same net MET as settlement.
    /// Scaling these two components separately keeps exercise from changing the resting
    /// slope. A settled aggregate with no timed activity evidence has no invented curve.
    static func burnCurve(dayStart: Date, now: Date, burnedNow: Double, burnedFull: Double?,
                          restingNow: Double?, ticks: [VitalSample], calendar: Calendar = .current)
    -> (solid: [FuelClockPoint], dashed: [FuelClockPoint]) {
        guard let restingNow, restingNow >= 0, burnedNow >= restingNow, now > dayStart else {
            return ([], [])
        }
        let active = burnedNow - restingNow
        let samples = ticks.filter { $0.ts >= dayStart && $0.ts <= now }.sorted { $0.ts < $1.ts }
        let weights = samples.map { max(0, (activityMet(met: $0.met, steps: $0.steps) ?? 1) - 1) }
        let total = weights.reduce(0, +)
        guard active == 0 || total > 0 else { return ([], []) }
        let elapsed = now.timeIntervalSince(dayStart)
        func point(_ at: Date, movement: Double) -> FuelClockPoint {
            FuelClockPoint(x: clockFraction(at: at, dayStart: dayStart, calendar: calendar),
                           y: restingNow * at.timeIntervalSince(dayStart) / elapsed + movement)
        }
        var solid = [point(dayStart, movement: 0)]
        var cumulative = 0.0
        for (sample, weight) in zip(samples, weights) {
            // Recorded ticks are discrete five-minute energy contributions, including
            // the opening tick; no duration or movement is invented across a missing run.
            let prior = total > 0 ? active * cumulative / total : 0
            solid.append(point(sample.ts, movement: prior))
            cumulative += weight
            let movement = total > 0 ? active * cumulative / total : 0
            if weight > 0 { solid.append(point(sample.ts, movement: movement)) }
        }
        solid.append(FuelClockPoint(x: clockFraction(at: now, dayStart: dayStart, calendar: calendar),
                                    y: burnedNow))
        let nowX = clockFraction(at: now, dayStart: dayStart, calendar: calendar)
        let dashed = nowX < 1 && burnedFull != nil
            ? [FuelClockPoint(x: nowX, y: burnedNow), FuelClockPoint(x: 1, y: max(burnedNow, burnedFull!))]
            : []
        return (solid, dashed)
    }

    /// Explicitly basal-only: callers without movement cannot label total burn as basal.
    static func burnLine(dayStart: Date, now: Date, burnedNow: Double, burnedFull: Double?,
                         calendar: Calendar = .current) -> (solid: [FuelClockPoint], dashed: [FuelClockPoint]) {
        burnCurve(dayStart: dayStart, now: now, burnedNow: burnedNow, burnedFull: burnedFull,
                  restingNow: burnedNow, ticks: [], calendar: calendar)
    }

    static func chartMax(budget: Double?, intake: Double, burnedNow: Double?, burnedFull: Double?) -> Double {
        let raw = [budget, intake, burnedNow, burnedFull].compactMap { $0 }.max() ?? 0
        return max(raw, 1)
    }
}
