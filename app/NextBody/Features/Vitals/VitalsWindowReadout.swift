import SwiftUI

/// What the five rolling boards print. The day readouts stay in `VitalsReadout`; these are
/// their week and month counterparts, kept apart because a window number is a different
/// claim from a day number and the two must not quietly share a formula.
///
/// ⚠️ Nothing here invents a day. A day the band filed nothing for is absent from every
/// median, every total and every count — it is never a zero (F2 rule 05). That is why the
/// worn-day count sits in the hero's foot on every one of these: a median over three days
/// and a median over thirty are different facts wearing the same numeral.
extension VitalsReadout {

    /// How a window's numbers print for each instrument — the same shape the rail, the
    /// legend and the tiles all use, so one day cannot be `6.4 KM` in one place and
    /// `6420 M` in another.
    static func windowFormat(_ metric: VitalsMetric) -> (Double) -> String {
        switch metric {
        case .steps:    return { Fmt.kcal($0) }
        case .distance: return { distanceLabel($0) }
        case .active:   return { Fmt.kcal($0) }
        default:        return { String(Int($0.rounded())) }
        }
    }

    static func windowUnit(_ metric: VitalsMetric) -> String? {
        switch metric {
        case .steps:    return L("STEPS")
        case .distance: return "KM"
        case .active:   return "KCAL"
        default:        return nil
        }
    }

    // MARK: 04 · stress over a window

    /// The median of daily medians on the same 0–100 dial the live reading uses, so a week
    /// and a moment are read against one ruler. One loud afternoon cannot drag a month.
    static func stressWindow(daily: [[Double]], ticks: [VitalSample], days: Int) -> VitalsReadout {
        let median = HeartWindowMath.medianOfDailyMedians(daily)
        let worn = HeartWindowMath.wornDays(daily)
        let peak = HeartWindowMath.extreme(daily, pick: max)
        let low = HeartWindowMath.extreme(daily, pick: min)
        let cuts = VitalsDialMath.stressCuts()

        // The same four bands the day page splits, over every tick in the window. Each tick
        // is five minutes wide there and five minutes wide here.
        var minutes = [Int](repeating: 0, count: 4)
        for value in ticks.compactMap(\.stress) {
            let i = value < 25 ? 0 : (value < 50 ? 1 : (value < 75 ? 2 : 3))
            minutes[i] += tickMinutes
        }
        let names = [L("Rest"), L("Low"), L("Mid"), L("High")]
        let tints = [NB.optimal2, NB.lime1, NB.ember1, NB.alert2]
        let totalMinutes = minutes.reduce(0, +)
        let bands: [VitalsSplit.Band] = totalMinutes == 0 ? [] : (0..<4).map { i in
            .init(name: names[i], tint: tints[i], share: Double(minutes[i]),
                  detail: Fmt.duration(minutes[i]))
        }

        // Per worn day, not per window: "42 min of rest" over a month is not a comparison
        // anybody can make against "42 min of rest" over a week.
        let restPerDay = worn > 0 ? minutes[0] / worn : 0
        let highPerDay = worn > 0 ? minutes[3] / worn : 0

        return VitalsReadout(
            value: median.map { String(Int($0.rounded())) },
            unit: "/ 100",
            dial: dial(scale: cuts.scale, cuts: cuts.cuts, value: median,
                       names: [L("REST"), L("STEADY"), L("ELEVATED"), L("HIGH")],
                       tints: [NB.optimal2, NB.lime1, NB.ember1, NB.alert2]),
            footLeft: L("%d DAYS WORN", worn),
            footRight: peak.map { L("WINDOW PEAK %d", Int($0.rounded())) },
            chartNote: L("FIXED 0–100 INDEX"),
            splitTitle: L("TIME IN STRESS ZONES"),
            splitTrailing: totalMinutes > 0 ? L("TOTAL %@", Fmt.duration(totalMinutes)) : nil,
            bands: bands,
            statLeft: .init(label: L("RECOVERY TIME"),
                            value: restPerDay > 0 ? Fmt.duration(restPerDay) : nil, unit: nil,
                            foot: worn > 0 ? L("PER WORN DAY") : L("NO TICKS YET"),
                            tint: NB.optimal2),
            statRight: .init(label: L("DAYS WORN"), value: String(worn),
                             unit: L("OF %d", days),
                             foot: highPerDay > 0 ? L("%@ OVER 75 A DAY", Fmt.duration(highPerDay))
                                 : (low != nil ? L("NONE OVER 75") : L("NO TICKS YET")),
                             tint: highPerDay > 0 ? NB.ember1 : nil))
    }

    // MARK: 05 · temperature over a window

    /// ADR 0009 holds across the window too: the range is learned from nights and the
    /// daytime ticks are described, never scored. The reference band is deliberately not
    /// drawn here — a night range painted across thirty daytimes would be judging every
    /// afternoon the arm spent out from under the covers.
    static func tempWindow(daily: [[Double]], days: Int,
                           range: SkinTempNightRange.Range?) -> VitalsReadout {
        let median = HeartWindowMath.medianOfDailyMedians(daily)
        let worn = HeartWindowMath.wornDays(daily)
        let high = HeartWindowMath.extreme(daily, pick: max)
        let low = HeartWindowMath.extreme(daily, pick: min)

        // Days, not minutes: this window's grain is a day, so its split counts days whose
        // own median sat below, inside or above the learned range.
        var counts = [Int](repeating: 0, count: 3)
        if let range {
            for day in daily {
                guard let dayMedian = HeartWindowMath.median(day) else { continue }
                let i = dayMedian < range.lower ? 0 : (dayMedian > range.upper ? 2 : 1)
                counts[i] += 1
            }
        }
        let names = [L("Below"), L("In range"), L("Above")]
        let tints = [NB.blue1, NB.optimal2, NB.ember1]
        let totalDays = counts.reduce(0, +)
        let bands: [VitalsSplit.Band] = totalDays == 0 ? [] : (0..<3).map { i in
            .init(name: names[i], tint: tints[i], share: Double(counts[i]),
                  detail: L("%d D", counts[i]))
        }

        var out = VitalsReadout(
            value: median.map { String(format: "%.1f", $0) },
            unit: L("°C SKIN"),
            dial: range.flatMap { VitalsDialMath.rangeCuts(lower: $0.lower, upper: $0.upper) }
                .map {
                    dial(scale: $0.scale, cuts: $0.cuts, value: median,
                         names: [L("BELOW"), L("IN RANGE"), L("ABOVE")],
                         tints: [NB.blue1, NB.optimal2, NB.ember1])
                },
            footLeft: range.map { L("YOUR RANGE %.1f–%.1f °C · %d NIGHTS", $0.lower, $0.upper, $0.nights) }
                ?? L("%d DAYS WORN", worn),
            footRight: L("%d DAYS WORN", worn),
            chartNote: range == nil ? L("FIXED 30–38 °C") : L("SCALED TO YOUR RANGE"),
            splitTitle: L("DAYS OFF YOUR RANGE"),
            splitTrailing: totalDays > 0 ? L("%d DAYS MEDIANED", totalDays) : nil,
            bands: bands,
            statLeft: .init(label: L("WINDOW LOW"), value: low.map { String(format: "%.1f", $0) },
                            unit: "°C",
                            foot: worn > 0 ? L("ACROSS %d DAYS", worn) : L("NO TICKS YET"),
                            tint: NB.blue1),
            statRight: .init(label: L("WINDOW HIGH"), value: high.map { String(format: "%.1f", $0) },
                             unit: "°C",
                             foot: median.map { L("MEDIAN %.1f °C", $0) } ?? L("NO TICKS YET"),
                             tint: NB.ember1))
        out.traceRange = SkinTempPresentation.axis(range, pad: 1.5)
        // ⚠️ Deliberately nil. See the note above the function.
        out.referenceBand = nil
        out.referenceLabel = range.map { L("YOUR NIGHT RANGE %.1f–%.1f °C", $0.lower, $0.upper) }
        return out
    }

    // MARK: 06 · 07 · 08 — the accumulated instruments over a window

    /// Steps, metres and kilocalories share one window shape: a bar a day, a median day for
    /// the hero, and the window's own total in the foot. What differs is the split
    /// underneath, which stays each instrument's own question.
    static func totalWindow(metric: VitalsMetric, slots: [MetricDayBars.Slot],
                            days: [DailyMetrics], ticks: [VitalSample], count: Int) -> VitalsReadout {
        let recorded = MetricWindowMath.recorded(slots)
        let median = HeartWindowMath.median(recorded)
        let total = MetricWindowMath.sum(slots)
        let best = MetricWindowMath.best(slots)
        let format = windowFormat(metric)
        let worn = recorded.count

        // The hero is the middle day, not the sum: a window's headline number has to be
        // comparable with the day page's, and a month's total is not.
        let heroValue: String? = metric == .distance
            ? median.map { String(format: "%.2f", $0 / 1000) }
            : median.map(format)

        return VitalsReadout(
            value: heroValue,
            unit: windowUnit(metric),
            dial: nil,
            footLeft: L("%d OF %d DAYS", worn, count),
            footRight: total.map { L("TOTAL %@", metric == .distance ? distanceLabel($0) : format($0)) },
            chartNote: L("PER DAY · ROLLING"),
            splitTitle: windowSplitTitle(metric),
            splitTrailing: total.map { metric == .distance ? distanceLabel($0) : format($0) },
            bands: windowBands(metric, days: days, ticks: ticks),
            statLeft: .init(label: L("BEST DAY"),
                            value: best?.total.map { metric == .distance ? String(format: "%.2f", $0 / 1000) : format($0) },
                            unit: windowUnit(metric),
                            foot: best.map { L("ON %@", Fmt.displayDate($0.start, format: "d MMM").uppercased()) }
                                ?? L("NO DAYS ON RECORD"),
                            tint: metric.tint),
            statRight: .init(label: L("MEDIAN DAY"),
                             value: heroValue, unit: windowUnit(metric),
                             foot: worn > 0 ? L("ACROSS %d DAYS", worn) : L("NO DAYS ON RECORD"),
                             tint: nil))
    }

    private static func windowSplitTitle(_ metric: VitalsMetric) -> String {
        switch metric {
        case .steps:    L("CADENCE INTENSITY")
        case .distance: L("WHEN IT HAPPENED")
        case .active:   L("WHERE THE BURN CAME FROM")
        default:        L("DISTRIBUTION")
        }
    }

    /// Each instrument's own split, summed across the window rather than re-asked per day.
    private static func windowBands(_ metric: VitalsMetric, days: [DailyMetrics],
                                    ticks: [VitalSample]) -> [VitalsSplit.Band] {
        switch metric {
        case .steps:
            var casual = 0.0, active = 0.0, run = 0.0
            for tick in ticks {
                guard let s = tick.steps, s > 0 else { continue }
                if s < 150 { casual += Double(s) } else if s < 400 { active += Double(s) } else { run += Double(s) }
            }
            guard casual + active + run > 0 else { return [] }
            return [
                .init(name: L("Casual"), tint: NB.optimal2.opacity(0.45), share: casual, detail: Fmt.kcal(casual)),
                .init(name: L("Active"), tint: NB.optimal2, share: active, detail: Fmt.kcal(active)),
                .init(name: L("Run"), tint: NB.lime1, share: run, detail: Fmt.kcal(run)),
            ]

        case .distance:
            // The user day's own thirds, taken against the day each tick belongs to — a
            // window crosses 04:00 six or thirty times and one fixed origin would smear them.
            var morning = 0.0, afternoon = 0.0, night = 0.0
            for tick in ticks {
                guard let d = tick.dis, d > 0 else { continue }
                let hour = tick.ts.timeIntervalSince(UserDay.containing(tick.ts).start) / 3600
                if hour < 8 { morning += d } else if hour < 16 { afternoon += d } else { night += d }
            }
            guard morning + afternoon + night > 0 else { return [] }
            return [
                .init(name: "04–12", tint: NB.violetPink.opacity(0.45), share: morning, detail: distanceLabel(morning)),
                .init(name: "12–20", tint: NB.violetPink, share: afternoon, detail: distanceLabel(afternoon)),
                .init(name: "20–04", tint: NB.violet1, share: night, detail: distanceLabel(night)),
            ]

        case .active:
            var resting = 0.0, sport = 0.0, walk = 0.0, incidental = 0.0
            let now = VitalsClock.now
            for day in days {
                let end = day.day.isClosed ? day.day.end : now
                let split = ActiveEnergyMath.split(
                    dayStart: day.day.start, now: min(end, now),
                    bmr: day.bmr, bmrFull: day.bmrFull,
                    eActive: day.eActive, eTrain: day.eTrain, eOutNow: day.eOutNow,
                    ticks: day.vitalsCurve.map { ($0.ts, $0.steps) },
                    sportWindows: ActiveEnergyModel.sportWindows(day))
                resting += split.resting ?? 0
                sport += split.sport ?? 0
                walk += split.steps ?? 0
                incidental += split.incidental ?? 0
            }
            let parts: [(String, Color, Double)] = [
                (L("RESTING"), NB.white.opacity(0.45), resting),
                (L("SPORT"), NB.lime1, sport),
                (L("STEPS"), NB.lime1.opacity(0.75), walk),
                (L("INCIDENTAL"), NB.lime1.opacity(0.55), incidental),
            ]
            return parts.compactMap { name, tint, value in
                value > 0 ? .init(name: name, tint: tint, share: value, detail: Fmt.kcal(value)) : nil
            }

        default:
            return []
        }
    }

    /// The whole burn for one day — the number the ACTIVE page's hero already prints, named
    /// once so the day page and the window page cannot settle it differently.
    static func dayTotalBurn(_ m: DailyMetrics) -> Double? {
        if let settled = m.eOutNow { return settled }
        let parts = [m.bmr, m.eActive, m.eTrain].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }
}
