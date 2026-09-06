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

    static func activityMet(met: Double? = nil, steps: Int?) -> Double? {
        FuelWindowMath.activityMet(met: met, steps: steps)
    }

    static func classify(met: Double, inSport: Bool) -> ActiveEnergyKind? {
        if inSport || met >= sportMet { return .sport }
        if met >= walkMet { return .steps }
        if met > stillMet { return .incidental }
        return nil
    }

    /// RESTING + ACTIVE = OUT. Keep explicit server components intact. `eTrain`
    /// is a separate component only in local seeds; production folds it into active.
    static func totals(bmr: Double?, eActive: Double?, eTrain: Double?,
                       eOutNow: Double?) -> (resting: Double?, active: Double?, out: Double?) {
        let active = eActive.map { $0 + (eTrain ?? 0) }
        // Components are the server's explicit estimates. Older total-burn revisions
        // can disagree with them; never overwrite recorded activity by subtracting OUT.
        let out = bmr.flatMap { rest in active.map { rest + $0 } } ?? eOutNow
        return (bmr, active, out)
    }

    static func derivedBmrFull(bmr: Double?, bmrFull: Double?,
                               dayStart: Date, now: Date, calendar: Calendar = .current) -> Double? {
        if let bmrFull, bmrFull > 0 { return bmrFull }
        let dayEnd = FuelWindowMath.dayEnd(dayStart: dayStart, calendar: calendar)
        let elapsed = min(now, dayEnd).timeIntervalSince(dayStart)
        guard let bmr, bmr > 0, elapsed > 0 else { return nil }
        return bmr * dayEnd.timeIntervalSince(dayStart) / elapsed
    }

    static func split(dayStart: Date, now: Date, bmr: Double?, bmrFull: Double?,
                      eActive: Double?, eTrain: Double?, eOutNow: Double?,
                      ticks: [VitalSample], sportWindows: [(Date, Date)],
                      calendar: Calendar = .current) -> ActiveEnergySplit {
        let totals = totals(bmr: bmr, eActive: eActive, eTrain: eTrain, eOutNow: eOutNow)
        let dayEnd = FuelWindowMath.dayEnd(dayStart: dayStart, calendar: calendar)
        let elapsed = max(0, Int(min(now, dayEnd).timeIntervalSince(dayStart) / 60))
        var raw = RawBuckets()
        let samples = ticks
            .filter { $0.ts >= dayStart && $0.ts <= now }
            .sorted { $0.ts < $1.ts }
        for sample in samples {
            guard let met = activityMet(met: sample.met, steps: sample.steps) else { continue }
            let kind = classify(met: met, inSport: inside(sample.ts, sportWindows))
            raw.add(kind: kind, met: met, steps: sample.steps, minutes: 5)
        }

        let parts = allocate([raw.sport, raw.steps, raw.incidental], onto: totals.active)
        var sport = parts[0]
        var walk = parts[1]
        var incidental = parts[2]

        if sport == nil, let train = eTrain, train > 0,
           let active = totals.active, active + 0.5 >= train {
            sport = min(train, active)
            let leftover = max(0, active - (sport ?? 0))
            let restRaw = raw.steps + raw.incidental
            if restRaw > 0 {
                let remaining = allocate([raw.steps, raw.incidental], onto: leftover)
                walk = remaining[0]
                incidental = remaining[1]
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
            bmrFull: derivedBmrFull(bmr: bmr, bmrFull: bmrFull, dayStart: dayStart, now: now, calendar: calendar),
            elapsedMinutes: elapsed > 0 ? elapsed : nil)
    }

    /// User-day hours, 04:00 → 04:00 (23/25 on DST changes). Future hours keep the BMR floor
    /// so the faded bars have a height; they are never 0.
    static func hourly(dayStart: Date, now: Date, split: ActiveEnergySplit,
                       ticks: [VitalSample], sportWindows: [(Date, Date)],
                       calendar: Calendar = .current) -> [ActiveEnergyHour] {
        guard let resting = split.resting, let active = split.active, split.out != nil,
              resting >= 0, active >= 0, now > dayStart else { return [] }
        let dayEnd = FuelWindowMath.dayEnd(dayStart: dayStart, calendar: calendar)
        let hourCount = Int((dayEnd.timeIntervalSince(dayStart) / 3600).rounded())
        let floor = (split.bmrFull ?? 0) / Double(hourCount)
        var extra = [Double](repeating: 0, count: hourCount)
        for sample in ticks where sample.ts >= dayStart && sample.ts <= now {
            var index = Int(sample.ts.timeIntervalSince(dayStart) / 3600)
            if index > 0 && livedFraction(hour: index, dayStart: dayStart, now: now) == 0 { index -= 1 }
            guard (0..<hourCount).contains(index),
                  let met = activityMet(met: sample.met, steps: sample.steps) else { continue }
            extra[index] += max(0, met - stillMet)
        }
        let totalExtra = extra.reduce(0, +)
        // The daily total can arrive before its raw samples. Do not invent a last-hour peak.
        guard active == 0 || totalExtra > 0 else { return [] }
        let elapsedHours = min(Double(hourCount), now.timeIntervalSince(dayStart) / 3600)
        return (0..<hourCount).map { i in
            let fraction = livedFraction(hour: i, dayStart: dayStart, now: now)
            let movement = totalExtra > 0 ? active * extra[i] / totalExtra : 0
            return ActiveEnergyHour(
                kcal: fraction > 0 ? resting * fraction / elapsedHours + movement : floor,
                lived: fraction > 0)
        }
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
                         burnedFull: Double?, restingNow: Double?, ticks: [VitalSample],
                         calendar: Calendar = .current)
    -> (solid: [FuelClockPoint], dashed: [FuelClockPoint]) {
        FuelWindowMath.burnCurve(dayStart: dayStart, now: now, burnedNow: burnedNow,
                                 burnedFull: burnedFull, restingNow: restingNow, ticks: ticks, calendar: calendar)
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

    static func intensity(dayStart: Date, now: Date, ticks: [VitalSample],
                          calendar: Calendar = .current)
    -> (solid: [FuelClockPoint], dashed: [FuelClockPoint]) {
        let nowX = FuelWindowMath.clockFraction(at: now, dayStart: dayStart, calendar: calendar)
        let samples = ticks
            .filter { $0.ts >= dayStart && $0.ts <= now }
            .sorted { $0.ts < $1.ts }
        var solid: [FuelClockPoint] = []
        var previousEnd: Date?
        for sample in samples {
            guard let met = activityMet(met: sample.met, steps: sample.steps) else { continue }
            let x = FuelWindowMath.clockFraction(at: sample.ts, dayStart: dayStart, calendar: calendar)
            guard x <= nowX else { break }
            // A recorded MET describes one five-minute slot, never the hours until
            // the next reading. A skipped/unknown slot starts a separate path.
            let end = min(now, sample.ts.addingTimeInterval(5 * 60))
            solid.append(FuelClockPoint(x: x, y: met,
                                        startsSegment: previousEnd == nil || sample.ts > previousEnd!))
            solid.append(FuelClockPoint(
                x: FuelWindowMath.clockFraction(at: end, dayStart: dayStart, calendar: calendar), y: met))
            previousEnd = end
        }
        guard !solid.isEmpty else { return ([], []) }
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

    static func hoursLeft(dayStart: Date, now: Date, calendar: Calendar = .current) -> Int {
        max(0, Int(ceil(FuelWindowMath.dayEnd(dayStart: dayStart, calendar: calendar).timeIntervalSince(now) / 3600)))
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

    /// Round cumulative shares so the printed integer parts close to the printed total.
    private static func allocate(_ weights: [Double], onto active: Double?) -> [Double?] {
        let total = weights.reduce(0, +)
        guard let active, active > 0, total > 0 else { return weights.map { _ in nil } }
        var cumulative = 0.0
        var assigned = 0.0
        return weights.map { weight in
            guard weight > 0 else { return nil }
            cumulative += weight
            let next = (active * cumulative / total).rounded()
            defer { assigned = next }
            return next - assigned
        }
    }

    private static func livedFraction(hour: Int, dayStart: Date, now: Date) -> Double {
        let start = dayStart.addingTimeInterval(Double(hour) * 3600)
        let end = start.addingTimeInterval(3600)
        if now <= start { return 0 }
        if now >= end { return 1 }
        return now.timeIntervalSince(start) / 3600
    }

}
