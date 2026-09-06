import Foundation

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
}

struct FuelClockPoint: Equatable, Sendable {
    var x: Double
    var y: Double
    init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Arithmetic for the calories page's three windows. No SwiftUI: the view only lays out
/// what this file already reduced.
enum FuelWindowMath {
    /// Sum of a week. Missing intake or burn on a slot counts as 0 so a fasted Tuesday
    /// and a short today still sit in the same 7-day denominator the page prints.
    /// Returns nil when the window has no known intake and no known burn.
    static func sum(_ days: [FuelDayFacts]) -> (intake: Double, burned: Double, gap: Double)? {
        let hasIn = days.contains { $0.intake != nil }
        let hasOut = days.contains { $0.burned != nil }
        guard hasIn || hasOut else { return nil }
        let intake = days.reduce(0.0) { $0 + ($1.intake ?? 0) }
        let burned = days.reduce(0.0) { $0 + ($1.burned ?? 0) }
        return (intake, burned, intake - burned)
    }

    /// One week's numbers as a day: the week sum divided by the slot count (always 7
    /// for a full group). That is the grain the month page speaks — 2,xxx, not 14,xxx.
    static func perDay(sum: (intake: Double, burned: Double, gap: Double), slots: Int) -> (intake: Double, burned: Double, gap: Double)? {
        guard slots > 0 else { return nil }
        let n = Double(slots)
        return (sum.intake / n, sum.burned / n, sum.gap / n)
    }

    /// Four week rolls, newest first. Each group is 7 slots walking backwards from the end.
    static func weekRolls(_ days: [FuelDayFacts]) -> [FuelWeekRoll] {
        UserDay.weekRolls(count: days.count).reversed().map { range in
            let slice = Array(days[range])
            let total = sum(slice)
            let per = total.flatMap { perDay(sum: $0, slots: slice.count) }
            return FuelWeekRoll(
                start: slice[0].day,
                end: slice[slice.count - 1].day,
                days: slice.count,
                fastedDays: slice.filter(\.isFasted).count,
                avgIn: per?.intake,
                avgOut: per?.burned,
                avgGap: per?.gap)
        }
    }

    /// Mean of the week-roll per-day numbers. Same grain as a day; not a monthly total.
    static func typicalDay(_ rolls: [FuelWeekRoll]) -> (intake: Double, burned: Double, gap: Double)? {
        let ins = rolls.compactMap(\.avgIn)
        let outs = rolls.compactMap(\.avgOut)
        let gaps = rolls.compactMap(\.avgGap)
        guard !ins.isEmpty || !outs.isEmpty else { return nil }
        func mean(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        let intake = mean(ins) ?? 0
        let burned = mean(outs) ?? 0
        return (intake, burned, mean(gaps) ?? (intake - burned))
    }

    /// 0…1 on a 00–24 wall clock whose midnight is the calendar date `dayStart` sits on.
    /// Hours after that midnight (the next morning 00:00–04:00) clamp to 1.
    static func clockFraction(at date: Date, dayStart: Date, calendar: Calendar = .current) -> Double {
        let midnight = calendar.startOfDay(for: dayStart)
        let hours = date.timeIntervalSince(midnight) / 3600
        return min(1, max(0, hours / 24))
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

    /// Same fallback as `nb.activity_met` when MET is missing: 500 steps in five
    /// minutes ≈ 3 MET, capped at 5. Relative units only — the curve is scaled to
    /// the settled `burnedNow` so this file never invents a second kcal total.
    static func activityMet(steps: Int?) -> Double? {
        guard let steps, steps >= 0 else { return nil }
        return 1 + 2 * min(2, Double(steps) / 500)
    }

    /// Cyan burn: basal accumulates with time, movement steepens the segments that
    /// had steps. A day with no ticks is still a basal line — there is nothing else
    /// to draw. The last solid point is always `burnedNow`.
    static func burnCurve(dayStart: Date, now: Date, burnedNow: Double, burnedFull: Double?,
                                 ticks: [(Date, Int?)], calendar: Calendar = .current)
    -> (solid: [FuelClockPoint], dashed: [FuelClockPoint]) {
        let openX = clockFraction(at: dayStart, dayStart: dayStart, calendar: calendar)
        let nowX = clockFraction(at: now, dayStart: dayStart, calendar: calendar)
        let samples = ticks
            .filter { $0.0 >= dayStart && $0.0 <= now }
            .sorted { $0.0 < $1.0 }

        var raw = [FuelClockPoint(x: openX, y: 0)]
        var y = 0.0
        var cursor = dayStart
        for (at, steps) in samples {
            let minutes = at.timeIntervalSince(cursor) / 60
            guard minutes > 0 else { continue }
            y += minutes
            if let met = activityMet(steps: steps) {
                y += max(0, met - 1) * min(5, minutes)
            }
            let x = clockFraction(at: at, dayStart: dayStart, calendar: calendar)
            if x <= nowX { raw.append(FuelClockPoint(x: x, y: y)) }
            cursor = at
        }
        let tail = now.timeIntervalSince(cursor) / 60
        if tail > 0 { y += tail }
        if raw.last?.x != nowX {
            raw.append(FuelClockPoint(x: nowX, y: y))
        }

        let peak = raw.last?.y ?? 0
        let scale = peak > 0 ? burnedNow / peak : 0
        var solid = raw.map { FuelClockPoint(x: $0.x, y: $0.y * scale) }
        if let last = solid.last {
            solid[solid.count - 1] = FuelClockPoint(x: last.x, y: burnedNow)
        }
        let end = burnedFull ?? burnedNow
        let dashed = nowX < 1
            ? [FuelClockPoint(x: nowX, y: burnedNow), FuelClockPoint(x: 1, y: end)]
            : []
        return (solid, dashed)
    }

    /// Basal-only fallback when the day has no movement ticks.
    static func burnLine(dayStart: Date, now: Date, burnedNow: Double, burnedFull: Double?,
                                calendar: Calendar = .current) -> (solid: [FuelClockPoint], dashed: [FuelClockPoint]) {
        burnCurve(dayStart: dayStart, now: now, burnedNow: burnedNow, burnedFull: burnedFull,
                  ticks: [], calendar: calendar)
    }

    static func chartMax(budget: Double?, intake: Double, burnedNow: Double?, burnedFull: Double?) -> Double {
        let raw = [budget, intake, burnedNow, burnedFull].compactMap { $0 }.max() ?? 0
        return max(raw, 1)
    }
}
