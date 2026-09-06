import Foundation

/// How one five-minute tick sits above sitting. Sport is a raised-HR window or
/// MET ≥ 4; a walk is MET 1.5…4; incidental is the 1.0…1.5 leftover (standing,
/// chores). Sitting (MET 1.0) adds nothing — that energy is already in BMR.
enum ActiveEnergyKind: String, Sendable {
    case sport, steps, incidental
}

struct ActiveEnergySplit: Equatable, Sendable {
    var resting: Double?
    var sport: Double?
    var steps: Double?
    var incidental: Double?
    var active: Double?
    var out: Double?
    var sportMinutes: Int?
    var sportMet: Double?
    var stepCount: Int?
    var stepsMet: Double?
    var incidentalMinutes: Int?
    var incidentalMet: Double?
    var bmrFull: Double?
    var elapsedMinutes: Int?
}

struct ActiveEnergyHour: Equatable, Sendable {
    /// Full-hour BMR floor when the hour has not started; lived hours include movement.
    var kcal: Double
    var lived: Bool
}

struct ActiveEnergyWeekBar: Equatable, Sendable {
    var start: Date
    var out: Double?
    var isToday: Bool
}

/// Ledger arithmetic for ACTIVE ENERGY. The OUT polyline is
/// `FuelWindowMath.burnCurve` — the same points the calories page draws — so the
/// two pages cannot disagree about how a walk steepens the day. Movement parts
/// are relative MET minutes scaled onto the settled active total; this file
/// never invents a second kcal_out.
enum ActiveEnergyMath {
    static let stillMet = 1.0
    static let walkMet = 1.5
    static let sportMet = 4.0
    static let hoursInDay = 24

    static func activityMet(steps: Int?) -> Double? {
        FuelWindowMath.activityMet(steps: steps)
    }

    static func classify(met: Double, inSport: Bool) -> ActiveEnergyKind? {
        if inSport || met >= sportMet { return .sport }
        if met >= walkMet { return .steps }
        if met > stillMet { return .incidental }
        return nil
    }

    /// RESTING + ACTIVE = OUT. ACTIVE is whatever is left after elapsed BMR,
    /// so a local `eTrain` that the seed adds on top of `eActive` is not
    /// double-counted, and a server row that already folded training into
    /// `eOutNow` still closes.
    static func totals(bmr: Double?, eActive: Double?, eTrain: Double?,
                       eOutNow: Double?) -> (resting: Double?, active: Double?, out: Double?) {
        let out = eOutNow ?? sum([bmr, eActive, eTrain])
        let active: Double?
        if let out, let bmr {
            let moved = out - bmr
            active = moved >= 0 ? moved : sum([eActive, eTrain])
        } else {
            active = sum([eActive, eTrain])
        }
        return (bmr, active, out)
    }

    static func derivedBmrFull(bmr: Double?, bmrFull: Double?,
                               dayStart: Date, now: Date) -> Double? {
        if let bmrFull, bmrFull > 0 { return bmrFull }
        let elapsed = now.timeIntervalSince(dayStart) / 60
        guard let bmr, bmr > 0, elapsed > 0 else { return nil }
        return bmr * 1_440 / elapsed
    }

    static func split(dayStart: Date, now: Date, bmr: Double?, bmrFull: Double?,
                      eActive: Double?, eTrain: Double?, eOutNow: Double?,
                      ticks: [(Date, Int?)], sportWindows: [(Date, Date)],
                      calendar: Calendar = .current) -> ActiveEnergySplit {
        let totals = totals(bmr: bmr, eActive: eActive, eTrain: eTrain, eOutNow: eOutNow)
        let elapsed = max(0, Int(now.timeIntervalSince(dayStart) / 60))
        var raw = RawBuckets()
        let samples = ticks
            .filter { $0.0 >= dayStart && $0.0 <= now }
            .sorted { $0.0 < $1.0 }
        for (at, steps) in samples {
            guard let met = activityMet(steps: steps) else { continue }
            let kind = classify(met: met, inSport: inside(at, sportWindows))
            raw.add(kind: kind, met: met, steps: steps, minutes: 5)
        }

        var sport = scale(raw.sport, of: raw.total, onto: totals.active)
        var walk = scale(raw.steps, of: raw.total, onto: totals.active)
        var incidental = scale(raw.incidental, of: raw.total, onto: totals.active)

        if sport == nil, let train = eTrain, train > 0,
           let active = totals.active, active + 0.5 >= train {
            sport = min(train, active)
            let leftover = max(0, active - (sport ?? 0))
            let restRaw = raw.steps + raw.incidental
            walk = scale(raw.steps, of: restRaw, onto: leftover)
            incidental = scale(raw.incidental, of: restRaw, onto: leftover)
            if leftover > 0.5, walk == nil, incidental == nil {
                walk = leftover
            }
        }

        return ActiveEnergySplit(
            resting: totals.resting,
            sport: sport,
            steps: walk,
            incidental: incidental,
            active: totals.active,
            out: totals.out,
            sportMinutes: raw.sportMinutes > 0 ? raw.sportMinutes : nil,
            sportMet: raw.sportMet,
            stepCount: raw.stepCount > 0 ? raw.stepCount : nil,
            stepsMet: raw.stepsMet,
            incidentalMinutes: raw.incidentalMinutes > 0 ? raw.incidentalMinutes : nil,
            incidentalMet: raw.incidentalMet,
            bmrFull: derivedBmrFull(bmr: bmr, bmrFull: bmrFull, dayStart: dayStart, now: now),
            elapsedMinutes: elapsed > 0 ? elapsed : nil)
    }

    /// 24 user-day hours, 04:00 → 04:00. Hours not lived yet keep the BMR floor
    /// so the faded bars have a height; they are never 0.
    static func hourly(dayStart: Date, now: Date, split: ActiveEnergySplit,
                       ticks: [(Date, Int?)], sportWindows: [(Date, Date)],
                       calendar: Calendar = .current) -> [ActiveEnergyHour] {
        let floor = (split.bmrFull ?? 0) / Double(hoursInDay)
        var extra = [Double](repeating: 0, count: hoursInDay)
        for (at, steps) in ticks where at >= dayStart && at <= now {
            let index = Int(at.timeIntervalSince(dayStart) / 3600)
            guard (0..<hoursInDay).contains(index),
                  let met = activityMet(steps: steps),
                  classify(met: met, inSport: inside(at, sportWindows)) != nil else { continue }
            extra[index] += max(0, met - stillMet)
        }
        let extraLived = zip(0..<hoursInDay, extra).reduce(0.0) { sum, item in
            livedFraction(hour: item.0, dayStart: dayStart, now: now) > 0 ? sum + item.1 : sum
        }
        let active = split.active ?? 0
        var hours: [ActiveEnergyHour] = []
        var livedSum = 0.0
        var lastLived: Int?
        for i in 0..<hoursInDay {
            let frac = livedFraction(hour: i, dayStart: dayStart, now: now)
            let move = extraLived > 0 ? active * extra[i] / extraLived : 0
            let kcal = floor * (frac > 0 ? frac : 1) + (frac > 0 ? move : 0)
            hours.append(ActiveEnergyHour(kcal: kcal, lived: frac > 0))
            if frac > 0 {
                livedSum += kcal
                lastLived = i
            }
        }
        if let lastLived, let out = split.out, out >= 0 {
            let delta = out - livedSum
            hours[lastLived].kcal = max(0, hours[lastLived].kcal + delta)
        }
        return hours
    }

    static func peakHour(_ hours: [ActiveEnergyHour]) -> (index: Int, kcal: Double)? {
        var best: (Int, Double)?
        for (i, hour) in hours.enumerated() where hour.lived {
            if best == nil || hour.kcal > best!.1 { best = (i, hour.kcal) }
        }
        return best.map { (index: $0.0, kcal: $0.1) }
    }

    /// Same polyline the calories page draws for OUT.
    static func outCurve(dayStart: Date, now: Date, burnedNow: Double,
                         burnedFull: Double?, ticks: [(Date, Int?)],
                         calendar: Calendar = .current)
    -> (solid: [FuelClockPoint], dashed: [FuelClockPoint]) {
        FuelWindowMath.burnCurve(dayStart: dayStart, now: now, burnedNow: burnedNow,
                                 burnedFull: burnedFull, ticks: ticks, calendar: calendar)
    }

    /// Elapsed BMR as a straight ruler. The dashed run keeps that slope — leftover
    /// BMR only, no guessed evening walk.
    static func restCurve(dayStart: Date, now: Date, resting: Double,
                          calendar: Calendar = .current)
    -> (solid: [FuelClockPoint], dashed: [FuelClockPoint]) {
        let openX = FuelWindowMath.clockFraction(at: dayStart, dayStart: dayStart, calendar: calendar)
        let nowX = FuelWindowMath.clockFraction(at: now, dayStart: dayStart, calendar: calendar)
        let solid = [FuelClockPoint(x: openX, y: 0), FuelClockPoint(x: nowX, y: resting)]
        guard nowX < 1 else { return (solid, []) }
        let span = max(0.001, nowX - openX)
        let end = resting + resting / span * (1 - nowX)
        return (solid, [FuelClockPoint(x: nowX, y: resting), FuelClockPoint(x: 1, y: end)])
    }

    static func intensity(dayStart: Date, now: Date, ticks: [(Date, Int?)],
                          calendar: Calendar = .current)
    -> (solid: [FuelClockPoint], dashed: [FuelClockPoint]) {
        let openX = FuelWindowMath.clockFraction(at: dayStart, dayStart: dayStart, calendar: calendar)
        let nowX = FuelWindowMath.clockFraction(at: now, dayStart: dayStart, calendar: calendar)
        let samples = ticks
            .filter { $0.0 >= dayStart && $0.0 <= now }
            .sorted { $0.0 < $1.0 }
        var solid = [FuelClockPoint(x: openX, y: stillMet)]
        var y = stillMet
        for (at, steps) in samples {
            let x = FuelWindowMath.clockFraction(at: at, dayStart: dayStart, calendar: calendar)
            guard x <= nowX else { break }
            let met = activityMet(steps: steps) ?? stillMet
            if solid.last?.x != x || solid.last?.y != y {
                solid.append(FuelClockPoint(x: x, y: y))
            }
            y = met
            solid.append(FuelClockPoint(x: x, y: y))
        }
        if solid.last?.x != nowX {
            solid.append(FuelClockPoint(x: nowX, y: y))
        }
        let dashed = nowX < 1
            ? [FuelClockPoint(x: nowX, y: stillMet), FuelClockPoint(x: 1, y: stillMet)]
            : []
        return (solid, dashed)
    }

    static func week(days: [(start: Date, out: Double?)], todayStart: Date)
    -> (bars: [ActiveEnergyWeekBar], average: Double?, todayDelta: Double?) {
        let bars = days.map {
            ActiveEnergyWeekBar(start: $0.start, out: $0.out, isToday: $0.start == todayStart)
        }
        let values = bars.compactMap(\.out)
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let today = bars.first(where: \.isToday)?.out
        let delta = today.flatMap { t in average.map { t - $0 } }
        return (bars, average, delta)
    }

    static func hoursLeft(dayStart: Date, now: Date) -> Int {
        max(0, Int(ceil((dayStart.addingTimeInterval(86_400).timeIntervalSince(now)) / 3600)))
    }

    // MARK: - private

    private struct RawBuckets {
        var sport = 0.0
        var steps = 0.0
        var incidental = 0.0
        var sportMinutes = 0
        var incidentalMinutes = 0
        var stepCount = 0
        var sportMetSum = 0.0
        var sportMetN = 0
        var stepsMetSum = 0.0
        var stepsMetN = 0
        var incidentalMetSum = 0.0
        var incidentalMetN = 0

        var total: Double { sport + steps + incidental }
        var sportMet: Double? { sportMetN > 0 ? sportMetSum / Double(sportMetN) : nil }
        var stepsMet: Double? { stepsMetN > 0 ? stepsMetSum / Double(stepsMetN) : nil }
        var incidentalMet: Double? { incidentalMetN > 0 ? incidentalMetSum / Double(incidentalMetN) : nil }

        mutating func add(kind: ActiveEnergyKind?, met: Double, steps: Int?, minutes: Int) {
            guard let kind else { return }
            let extra = max(0, met - ActiveEnergyMath.stillMet) * Double(minutes)
            switch kind {
            case .sport:
                sport += extra
                sportMinutes += minutes
                sportMetSum += met
                sportMetN += 1
            case .steps:
                self.steps += extra
                stepCount += max(0, steps ?? 0)
                stepsMetSum += met
                stepsMetN += 1
            case .incidental:
                incidental += extra
                incidentalMinutes += minutes
                incidentalMetSum += met
                incidentalMetN += 1
            }
        }
    }

    private static func inside(_ at: Date, _ windows: [(Date, Date)]) -> Bool {
        windows.contains { at >= $0.0 && at < $0.1 }
    }

    private static func scale(_ raw: Double, of total: Double, onto active: Double?) -> Double? {
        guard let active, active > 0, total > 0, raw > 0 else { return nil }
        return active * raw / total
    }

    private static func livedFraction(hour: Int, dayStart: Date, now: Date) -> Double {
        let start = dayStart.addingTimeInterval(Double(hour) * 3600)
        let end = start.addingTimeInterval(3600)
        if now <= start { return 0 }
        if now >= end { return 1 }
        return now.timeIntervalSince(start) / 3600
    }

    private static func sum(_ parts: [Double?]) -> Double? {
        let present = parts.compactMap { $0 }
        return present.isEmpty ? nil : present.reduce(0, +)
    }
}
