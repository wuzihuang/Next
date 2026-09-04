import SwiftUI

/// 04 · 8 大指标二级页 · everything the page prints, derived from the day the app already
/// holds. No view in this feature computes a number; they only lay one out.
///
/// ⚠️ Nothing here reads the band and nothing here invents. Every field is either a value
/// that arrived — a tick, a night, a server-settled total — or nil, which renders as ——
/// (F2 rule 05). A zero is only ever printed when the band actually reported one: a still
/// hour is a fact, a missing hour is not.
struct VitalsReadout {
    var badge: VitalsBadge.Model?
    var value: String?
    var unit: String?
    var gauge: VitalsGauge.Model?
    var footLeft: String
    var footRight: String?
    /// The note at the right of the chart card — the ruler the curve is drawn against.
    var chartNote: String
    var splitTitle: String
    var splitTrailing: String?
    var bands: [VitalsSplit.Band]
    var statLeft: VitalsStatPair.Model
    var statRight: VitalsStatPair.Model
    /// The physiological band drawn behind the trace, in the chart's own units — the resting
    /// pulse, the stable temperature window. It is a reference, never a target.
    var referenceBand: ClosedRange<Double>?
    var referenceLabel: String?
    /// 05 · what the temperature trace is drawn as a deviation from. The chart needs the same
    /// number the hero subtracted, so it is carried rather than computed twice.
    var baseline: Double?

    /// One tick is five minutes wide, which is the finest any duration on these pages can
    /// be. 08 rule 02 · zone minutes are multiples of five, floored — 「Z5 4 MIN」 cannot exist.
    static let tickMinutes = 5
}

// MARK: - the day's three totals

extension VitalsReadout {
    /// Steps, metres and active kcal, each resolved the one way page two's cards resolve
    /// them: the settled figure when the server has one, the ticks' own sum until then.
    ///
    /// ⚠️ These are shared rather than re-derived per page on purpose. The steps page used
    /// `m.distanceM` alone for its distance tile while the distance page fell back to the
    /// ticks — so on a day the server had not settled, one page said 0.84 KM and the other
    /// said ——, about the same day. Two pages disagreeing about one number is worse than
    /// either number being absent.
    static func daySteps(_ m: DailyMetrics) -> Double? {
        m.steps.map(Double.init) ?? VitalsMath.total(
            VitalsMath.hourSum(m.vitalsCurve, day: m.day, value: { $0.steps.map(Double.init) }))
    }

    static func dayMetres(_ m: DailyMetrics) -> Double? {
        m.distanceM.map(Double.init) ?? VitalsMath.total(
            VitalsMath.hourSum(m.vitalsCurve, day: m.day, value: \.dis))
    }

    static func dayActiveKcal(_ m: DailyMetrics) -> Double? {
        m.eActive ?? VitalsMath.total(VitalsMath.hourSum(m.vitalsCurve, day: m.day, value: \.cal))
    }

    /// Metres under a kilometre read as metres. "0.0 KM" for a real 40-metre walk looks like
    /// a bug on the legend even though the number is honest.
    static func distanceLabel(_ metres: Double) -> String {
        metres < 1000 ? L("%d M", Int(metres.rounded())) : L("%.1f KM", metres / 1000)
    }
}

// MARK: - building it

extension VitalsReadout {

    static func make(_ metric: VitalsMetric,
                     m: DailyMetrics,
                     history: [DailyMetrics],
                     vitals: LiveVitals,
                     profile: Profile) -> VitalsReadout {
        switch metric {
        case .heart:    heart(m: m, history: history, vitals: vitals, profile: profile)
        case .sleep:    sleep(m: m)
        case .hrv:      hrv(m: m, history: history)
        case .stress:   stress(m: m, vitals: vitals)
        case .temp:     temp(m: m, history: history)
        case .steps:    steps(m: m, history: history)
        case .distance: distance(m: m, history: history)
        case .active:   active(m: m)
        }
    }

    // MARK: 01 · heart

    private static func heart(m: DailyMetrics, history: [DailyMetrics],
                              vitals: LiveVitals, profile: Profile) -> VitalsReadout {
        let ticks = m.vitalsCurve
        let hrs = ticks.compactMap(\.hr)
        let gone = vitals.freshness == .gone
        let now = gone ? nil : (vitals.hr ?? ticks.last(where: { $0.hr != nil })?.hr)
        let dayLow = hrs.min()
        let dayHigh = m.peakHR ?? hrs.max()
        let resting = m.nightInputs?.rhr.map { Int($0.rounded()) }

        // The badge measures the reading against this wrist's own resting pulse, not against
        // a population number. Without a night on file there is nothing to measure it by.
        var badge: VitalsBadge.Model?
        if let now, let resting {
            let over = now - resting
            let text = over <= 15 ? L("NORMAL RESTING") : (over <= 45 ? L("ACTIVE") : L("ELEVATED"))
            badge = .init(text: text, tint: over <= 15 ? NB.optimal2 : (over <= 45 ? NB.lime1 : NB.ember1))
        }

        let restingBand = resting.map { Double($0)...Double($0 + 20) }
        let sevenDayResting = mean(history.suffix(8).dropLast().compactMap { $0.nightInputs?.rhr })

        var out = VitalsReadout(
            badge: badge,
            value: now.map(String.init),
            unit: "BPM",
            gauge: gauge(low: dayLow.map { L("MIN %d", $0) } ?? L("MIN %@", Fmt.dash),
                         now: now.map { L("NOW %d", $0) } ?? L("NOW %@", Fmt.dash),
                         high: dayHigh.map { L("PEAK %d", $0) } ?? L("PEAK %@", Fmt.dash),
                         value: now.map(Double.init), low: dayLow.map(Double.init), high: dayHigh.map(Double.init)),
            footLeft: vitals.at.map { L("LAST TICK %@", Fmt.clock($0)) } ?? L("NO TICK YET"),
            footRight: restingBand.map { L("RESTING BAND %d–%d", Int($0.lowerBound), Int($0.upperBound)) },
            chartNote: L("FIXED 40–160 BPM"),
            splitTitle: L("TIME IN ZONES"),
            splitTrailing: zoneTotal(m: m, ticks: ticks, profile: profile),
            bands: heartZoneBands(m: m, ticks: ticks, profile: profile),
            statLeft: .init(label: L("RESTING HR"), value: resting.map(String.init), unit: "BPM",
                            foot: delta(resting.map(Double.init), vs: sevenDayResting,
                                        unit: "BPM", suffix: "vs 7d", lowerIsBetter: true).text,
                            tint: delta(resting.map(Double.init), vs: sevenDayResting,
                                        unit: "BPM", suffix: "vs 7d", lowerIsBetter: true).tint),
            statRight: .init(label: L("HRV RMSSD"), value: m.nightInputs?.hrv.map { String(Int($0.rounded())) },
                             unit: "MS",
                             foot: m.nightInputs?.hrvBase.map { L("BASE %d MS", Int($0.rounded())) } ?? L("NO BASELINE YET"),
                             tint: NB.blue1))
        out.referenceBand = restingBand
        out.referenceLabel = restingBand.map { L("RESTING BAND %d–%d", Int($0.lowerBound), Int($0.upperBound)) }
        return out
    }

    /// 08 rule 04 · the five server zones collapsed onto the board's four bands, or derived
    /// from the ticks when the day has not settled. Age gives the ceiling; the ticks give
    /// the minutes. Never a guessed name for a band nobody was in.
    private static func heartZoneBands(m: DailyMetrics, ticks: [VitalSample],
                                       profile: Profile) -> [VitalsSplit.Band] {
        let names = [L("Rest"), L("Fat"), L("Aero"), L("Peak")]
        let tints = [NB.lime1, NB.optimal2, NB.caution2, NB.alert2]
        var minutes = [Int](repeating: 0, count: 4)

        if let zones = m.zoneMinutes, zones.count >= 5 {
            // Z1 · Z2 · Z3 · Z4+Z5 — the top two are one band on the board, because the
            // difference between them is not a difference a day page has to argue.
            minutes = [zones[0], zones[1], zones[2], zones[3] + zones[4]]
        } else {
            // Tanaka off the profile's own birthday — the same ceiling 11 prints, not a
            // second formula invented here.
            let maxHR = max(120, profile.hrMax)
            for tick in ticks {
                guard let hr = tick.hr, hr > 0 else { continue }
                let share = Double(hr) / Double(maxHR)
                let i = share < 0.60 ? 0 : (share < 0.70 ? 1 : (share < 0.80 ? 2 : 3))
                minutes[i] += tickMinutes
            }
        }

        let total = minutes.reduce(0, +)
        guard total > 0 else { return [] }
        return (0..<4).map { i in
            VitalsSplit.Band(name: names[i], tint: tints[i], share: Double(minutes[i]),
                             detail: "\(Int((Double(minutes[i]) / Double(total) * 100).rounded()))%")
        }
    }

    private static func zoneTotal(m: DailyMetrics, ticks: [VitalSample], profile: Profile) -> String? {
        let bands = heartZoneBands(m: m, ticks: ticks, profile: profile)
        let total = Int(bands.reduce(0) { $0 + $1.share })
        return total > 0 ? L("TOTAL %@", Fmt.duration(total)) : nil
    }

    // MARK: 02 · sleep

    private static func sleep(m: DailyMetrics) -> VitalsReadout {
        guard let night = m.sleep, night.totalMinutes > 0 else {
            return empty(unit: L("ASLEEP"),
                         foot: L("NO NIGHT ON RECORD"),
                         chartNote: L("4 STAGES"),
                         splitTitle: L("STAGE PROPORTIONS"),
                         statLeft: .init(label: L("DEEP SLEEP"), value: nil, unit: nil,
                                         foot: L("WEAR IT TONIGHT"), tint: nil),
                         statRight: .init(label: L("WAKE EVENTS"), value: nil, unit: nil,
                                          foot: L("WEAR IT TONIGHT"), tint: nil))
        }

        let total = night.totalMinutes
        let deepShare = Double(night.deepMinutes) / Double(max(1, total))
        // 「不算分、不评价」 — the badge names the night's deep share, which is a measurement,
        // and stops there. It is not a sleep score.
        let badgeText = deepShare >= 0.20 ? L("RESTORATIVE") : (deepShare >= 0.13 ? L("ADEQUATE") : L("LIGHT NIGHT"))
        let badgeTint = deepShare >= 0.20 ? NB.optimal2 : (deepShare >= 0.13 ? NB.violet1 : NB.ember1)

        // A deep episode is one run of stage 0. The band files them; counting them is not
        // the same as claiming a 90-minute cycle model the device never used.
        let deepEpisodes = night.line.filter { $0.stage == 0 }.count

        var bands: [VitalsSplit.Band] = []
        if night.line.isEmpty {
            // A row stored before the line was kept: the two totals it does have, and no
            // invented REM band.
            bands = [
                .init(name: L("Deep"), tint: NB.violet1, share: Double(night.deepMinutes),
                      detail: Fmt.duration(night.deepMinutes)),
                .init(name: L("Light"), tint: NB.violet2, share: Double(night.lightMinutes),
                      detail: Fmt.duration(night.lightMinutes)),
            ]
        } else {
            bands = [
                .init(name: L("Deep"), tint: NB.violet1, share: Double(night.deepMinutes),
                      detail: Fmt.duration(night.deepMinutes)),
                .init(name: L("Light"), tint: NB.violet2, share: Double(night.lightMinutes),
                      detail: Fmt.duration(night.lightMinutes)),
                .init(name: L("REM"), tint: NB.blue1, share: Double(night.remMinutes),
                      detail: Fmt.duration(night.remMinutes)),
                .init(name: L("Awake"), tint: NB.white.opacity(0.35), share: Double(night.awakeMinutes),
                      detail: Fmt.duration(night.awakeMinutes)),
            ]
        }

        let window: String
        if let start = night.sleepStart, let wake = night.wakeAt {
            window = L("BED %@ · WAKE %@", Fmt.clock(start), Fmt.clock(wake))
        } else {
            window = L("WINDOW NOT ON RECORD")
        }

        return VitalsReadout(
            badge: .init(text: badgeText, tint: badgeTint),
            value: Fmt.duration(total),
            unit: L("ASLEEP"),
            gauge: nil,
            footLeft: window,
            footRight: deepEpisodes > 0 ? L("%d DEEP EPISODES", deepEpisodes) : nil,
            chartNote: night.line.isEmpty ? L("TOTALS ONLY") : L("AWAKE · REM · LIGHT · DEEP"),
            splitTitle: L("STAGE PROPORTIONS"),
            splitTrailing: L("TOTAL %@", Fmt.duration(total)),
            bands: bands,
            statLeft: .init(label: L("DEEP SLEEP"), value: Fmt.duration(night.deepMinutes), unit: nil,
                            foot: L("%d%% OF THE NIGHT", Int((deepShare * 100).rounded())), tint: NB.violet1),
            // Never the hero's own number again: the tile used to repeat TIME ASLEEP, which
            // is the one thing the page has already said in 52 pt type.
            statRight: .init(label: L("WAKE EVENTS"), value: String(night.wakeCount),
                             unit: night.wakeCount == 1 ? L("WAKE") : L("WAKES"),
                             foot: night.awakeMinutes > 0 ? L("%@ AWAKE", Fmt.duration(night.awakeMinutes))
                                                          : L("NONE STAGED AWAKE"),
                             tint: night.wakeCount > 2 ? NB.ember1 : nil))
    }

    // MARK: 03 · HRV

    private static func hrv(m: DailyMetrics, history: [DailyMetrics]) -> VitalsReadout {
        let night = m.nightInputs
        let value = night?.hrv
        let base = night?.hrvBase
        let ticks = m.vitalsCurve.compactMap(\.hrv)

        var badge: VitalsBadge.Model?
        if let value, let base, base > 0 {
            let ratio = value / base
            let text = ratio >= 1.08 ? L("ABOVE BASELINE") : (ratio >= 0.92 ? L("WITHIN RANGE") : L("BELOW BASELINE"))
            let tint = ratio >= 1.08 ? NB.optimal2 : (ratio >= 0.92 ? NB.blue1 : NB.ember1)
            badge = .init(text: text, tint: tint)
        }

        // The envelope is the fortnight's own spread of nightly readings — 04B rule 06 · with
        // fewer than five nights there is no baseline and therefore no band to draw.
        let nightly = history.suffix(15).dropLast().compactMap { $0.nightInputs?.hrv }
        let envelope: ClosedRange<Double>? = nightly.count >= 5
            ? (nightly.min()!)...(nightly.max()!)
            : nil

        // Where the night's own ticks fell relative to the baseline. Derived from the ticks,
        // so it is a distribution of measurements rather than a verdict.
        var bands: [VitalsSplit.Band] = []
        if let base, base > 0, !ticks.isEmpty {
            let below = ticks.filter { $0 < base * 0.92 }.count
            let inBand = ticks.filter { $0 >= base * 0.92 && $0 <= base * 1.08 }.count
            let above = ticks.filter { $0 > base * 1.08 }.count
            bands = [
                .init(name: L("Below"), tint: NB.ember1, share: Double(below), detail: "\(below)"),
                .init(name: L("In band"), tint: NB.blue1, share: Double(inBand), detail: "\(inBand)"),
                .init(name: L("Above"), tint: NB.optimal2, share: Double(above), detail: "\(above)"),
            ]
        }

        return VitalsReadout(
            badge: badge,
            value: value.map { String(Int($0.rounded())) },
            unit: "MS",
            gauge: gauge(low: envelope.map { L("LOW %d", Int($0.lowerBound.rounded())) } ?? L("LOW %@", Fmt.dash),
                         now: value.map { L("NIGHT %d", Int($0.rounded())) } ?? L("NIGHT %@", Fmt.dash),
                         high: envelope.map { L("HIGH %d", Int($0.upperBound.rounded())) } ?? L("HIGH %@", Fmt.dash),
                         value: value, low: envelope?.lowerBound, high: envelope?.upperBound),
            footLeft: L("%d/14 NIGHTS ON FILE", night?.hrvNights ?? 0),
            footRight: base.map { L("BASE %d MS", Int($0.rounded())) },
            chartNote: ticks.isEmpty ? L("NO RMSSD TICKS") : L("%d TICKS · 14-NIGHT ENVELOPE", ticks.count),
            splitTitle: L("TICKS VS BASELINE"),
            splitTrailing: ticks.isEmpty ? nil : L("%d TICKS", ticks.count),
            bands: bands,
            statLeft: .init(label: L("24H MEDIAN"), value: median(ticks).map { String(Int($0.rounded())) },
                            unit: "MS",
                            foot: ticks.isEmpty ? L("NO TICKS YET")
                                : L("LOW %d · HIGH %d", Int(ticks.min()!.rounded()), Int(ticks.max()!.rounded())),
                            tint: NB.blue1),
            statRight: .init(label: L("VS BASELINE"),
                             value: (value != nil && (base ?? 0) > 0)
                                 ? String(format: "%.2f", value! / base!) : nil,
                             unit: L("RATIO"),
                             foot: (night?.hrvNights ?? 0) >= 5 ? L("%d NIGHTS WEIGHED", night!.hrvNights)
                                                                : L("NEEDS 5 NIGHTS"),
                             tint: nil))
    }

    // MARK: 04 · stress

    private static func stress(m: DailyMetrics, vitals: LiveVitals) -> VitalsReadout {
        let ticks = m.vitalsCurve
        let values = ticks.compactMap(\.stress)
        let gone = vitals.freshness == .gone
        let now = gone ? nil : (vitals.stress ?? ticks.last(where: { $0.stress != nil })?.stress)
        let peak = ticks.filter { $0.stress != nil }.max(by: { ($0.stress ?? 0) < ($1.stress ?? 0) })
        let dayMean = mean(values.map(Double.init))

        var badge: VitalsBadge.Model?
        if let now {
            let text = now < 25 ? L("REST STATE") : (now < 50 ? L("STEADY") : (now < 75 ? L("ELEVATED") : L("HIGH LOAD")))
            let tint = now < 25 ? NB.optimal2 : (now < 50 ? NB.lime1 : (now < 75 ? NB.ember1 : NB.alert2))
            badge = .init(text: text, tint: tint)
        }

        // Four bands of the same index, each tick five minutes wide.
        var minutes = [Int](repeating: 0, count: 4)
        for value in values {
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

        // A sympathetic event is a run of ticks over 75 — counted as runs, not as ticks, so
        // one long spike is one event rather than twelve.
        var events = 0
        var inEvent = false
        for tick in ticks {
            guard let s = tick.stress else { continue }
            if s > 75 { if !inEvent { events += 1; inEvent = true } } else { inEvent = false }
        }

        return VitalsReadout(
            badge: badge,
            value: now.map(String.init),
            unit: "/ 100",
            gauge: gauge(low: values.min().map { L("LOW %d", $0) } ?? L("LOW %@", Fmt.dash),
                         now: now.map { L("NOW %d", $0) } ?? L("NOW %@", Fmt.dash),
                         high: values.max().map { L("PEAK %d", $0) } ?? L("PEAK %@", Fmt.dash),
                         value: now.map(Double.init),
                         low: values.min().map(Double.init), high: values.max().map(Double.init)),
            footLeft: dayMean.map { L("24H MEAN %d", Int($0.rounded())) } ?? L("NO TICKS YET"),
            footRight: peak.flatMap { tick in tick.stress.map { L("PEAK %d AT %@", $0, Fmt.clock(tick.ts)) } },
            chartNote: L("FIXED 0–100 INDEX"),
            splitTitle: L("TIME IN STRESS ZONES"),
            splitTrailing: totalMinutes > 0 ? L("TOTAL %@", Fmt.duration(totalMinutes)) : nil,
            bands: bands,
            statLeft: .init(label: L("RECOVERY TIME"), value: minutes[0] > 0 ? Fmt.duration(minutes[0]) : nil,
                            unit: nil,
                            foot: totalMinutes > 0
                                ? L("%d%% OF 24H", Int((Double(minutes[0]) / Double(totalMinutes) * 100).rounded()))
                                : L("NO TICKS YET"),
                            tint: NB.optimal2),
            statRight: .init(label: L("HIGH-LOAD EVENTS"), value: values.isEmpty ? nil : String(events),
                             unit: events == 1 ? L("EVENT") : L("EVENTS"),
                             foot: minutes[3] > 0 ? L("%@ OVER 75", Fmt.duration(minutes[3])) : L("NONE OVER 75"),
                             tint: events > 0 ? NB.ember1 : nil))
    }

    // MARK: 05 · temperature

    private static func temp(m: DailyMetrics, history: [DailyMetrics]) -> VitalsReadout {
        let ticks = m.vitalsCurve
        let today = ticks.compactMap(\.temp)
        let source = tempBaseline(m: m, history: history)
        let baseline = source?.value
        let last = ticks.last(where: { $0.temp != nil })?.temp
        let deviation = (last != nil && baseline != nil) ? last! - baseline! : nil

        var badge: VitalsBadge.Model?
        if let deviation {
            let magnitude = abs(deviation)
            let text = magnitude <= 0.3 ? L("BASELINE STABLE") : (magnitude <= 0.6 ? L("MILD SHIFT") : L("DEVIATION"))
            let tint = magnitude <= 0.3 ? NB.optimal2 : (magnitude <= 0.6 ? NB.cyan1 : NB.ember1)
            badge = .init(text: text, tint: tint)
        }

        let deviations = baseline.map { base in today.map { $0 - base } } ?? []
        var minutes = [Int](repeating: 0, count: 3)
        for value in deviations {
            let i = value < -0.3 ? 0 : (value <= 0.3 ? 1 : 2)
            minutes[i] += tickMinutes
        }
        let names = [L("Below"), L("Stable"), L("Above")]
        let tints = [NB.blue1, NB.optimal2, NB.ember1]
        let totalMinutes = minutes.reduce(0, +)
        let bands: [VitalsSplit.Band] = totalMinutes == 0 ? [] : (0..<3).map { i in
            .init(name: names[i], tint: tints[i], share: Double(minutes[i]),
                  detail: Fmt.duration(minutes[i]))
        }

        var out = VitalsReadout(
            badge: badge,
            value: deviation.map { String(format: "%+.1f", $0) },
            unit: L("°C VS BASELINE"),
            gauge: gauge(low: deviations.min().map { L("LOW %+.1f", $0) } ?? L("LOW %@", Fmt.dash),
                         now: deviation.map { L("NOW %+.1f", $0) } ?? L("NOW %@", Fmt.dash),
                         high: deviations.max().map { L("HIGH %+.1f", $0) } ?? L("HIGH %@", Fmt.dash),
                         value: deviation, low: deviations.min(), high: deviations.max()),
            // The window is named, not just the number: +0.2 against last night and +0.2
            // against the last seven days are two different claims.
            footLeft: source.map { L("BASELINE %.1f °C · %@", $0.value, L($0.source)) }
                ?? L("NO BASELINE YET"),
            footRight: last.map { L("SKIN %.1f °C", $0) },
            chartNote: L("FIXED ±1.0 °C"),
            splitTitle: L("TIME OFF BASELINE"),
            splitTrailing: totalMinutes > 0 ? L("TOTAL %@", Fmt.duration(totalMinutes)) : nil,
            bands: bands,
            statLeft: .init(label: L("24H LOW"), value: today.min().map { String(format: "%.1f", $0) },
                            unit: "°C",
                            foot: today.isEmpty ? L("NO TICKS YET") : L("%d TICKS · 24H", today.count),
                            tint: NB.blue1),
            statRight: .init(label: L("24H HIGH"), value: today.max().map { String(format: "%.1f", $0) },
                             unit: "°C",
                             foot: baseline.map { L("BASELINE %.1f °C", $0) } ?? L("NO BASELINE YET"),
                             tint: NB.ember1))
        out.baseline = baseline
        out.referenceBand = -0.3...0.3
        out.referenceLabel = L("STABLE ±0.3 °C")
        return out
    }

    // MARK: 06 · steps

    private static func steps(m: DailyMetrics, history: [DailyMetrics]) -> VitalsReadout {
        let ticks = m.vitalsCurve
        let bins = VitalsMath.hourSum(ticks, day: m.day, value: { $0.steps.map(Double.init) })
        let total = daySteps(m)
        let metres = dayMetres(m)
        let activeKcal = dayActiveKcal(m)
        let peak = VitalsMath.peak(bins)
        let week = history.suffix(8).dropLast().compactMap { daySteps($0) }
        let weekMean = mean(week)

        var badge: VitalsBadge.Model?
        if let total, let weekMean, weekMean > 0 {
            let ahead = total >= weekMean
            badge = .init(text: ahead ? L("ABOVE 7D MEAN") : L("BELOW 7D MEAN"),
                          tint: ahead ? NB.optimal2 : NB.ember1)
        }

        // Cadence, per tick: five minutes of walking at a stroll, at a pace, or at a run.
        // The thresholds are steps in five minutes, which is what the band actually filed —
        // never a cadence in steps per minute the device never reported.
        var casual = 0.0, active = 0.0, run = 0.0
        for tick in ticks {
            guard let s = tick.steps, s > 0 else { continue }
            if s < 150 { casual += Double(s) } else if s < 400 { active += Double(s) } else { run += Double(s) }
        }
        let bands: [VitalsSplit.Band] = (casual + active + run) == 0 ? [] : [
            .init(name: L("Casual"), tint: NB.optimal2.opacity(0.45), share: casual, detail: Fmt.kcal(casual)),
            .init(name: L("Active"), tint: NB.optimal2, share: active, detail: Fmt.kcal(active)),
            .init(name: L("Run"), tint: NB.lime1, share: run, detail: Fmt.kcal(run)),
        ]

        return VitalsReadout(
            badge: badge,
            value: total.map { Fmt.kcal($0) },
            unit: L("STEPS"),
            gauge: gauge(low: week.min().map { L("7D LOW %@", Fmt.kcal($0)) } ?? L("7D LOW %@", Fmt.dash),
                         now: total.map { L("TODAY %@", Fmt.kcal($0)) } ?? L("TODAY %@", Fmt.dash),
                         high: week.max().map { L("7D HIGH %@", Fmt.kcal($0)) } ?? L("7D HIGH %@", Fmt.dash),
                         value: total, low: week.min(), high: week.max()),
            footLeft: m.activeMinutes.map { L("ACTIVE TIME %@", Fmt.duration($0)) } ?? L("NO ACTIVE TIME YET"),
            footRight: peak.map { L("PEAK %@/H AT %@", Fmt.kcal($0.value), VitalsMath.clock(day: m.day, minute: $0.index * 60)) },
            chartNote: L("TODAY · PER HOUR"),
            splitTitle: L("CADENCE INTENSITY"),
            splitTrailing: total.map { L("%@ STEPS", Fmt.kcal($0)) },
            bands: bands,
            statLeft: .init(label: L("DISTANCE"), value: metres.map { String(format: "%.2f", $0 / 1000) },
                            unit: "KM",
                            foot: metres.map { L("%@ M WALKED", Fmt.kcal($0)) } ?? L("NO DISTANCE YET"),
                            tint: NB.violetPink),
            statRight: .init(label: L("ACTIVITY BURN"), value: activeKcal.map { Fmt.kcal($0) }, unit: "KCAL",
                             foot: activeKcal == nil ? L("NEEDS YOUR WEIGHT") : L("MOVEMENT ONLY"),
                             tint: NB.run1))
    }

    // MARK: 07 · distance

    private static func distance(m: DailyMetrics, history: [DailyMetrics]) -> VitalsReadout {
        let ticks = m.vitalsCurve
        let metres = dayMetres(m)
        let steps = daySteps(m)
        let activeKcal = dayActiveKcal(m)
        let week = history.suffix(8).dropLast().compactMap { dayMetres($0) }
        let weekMean = mean(week)

        var badge: VitalsBadge.Model?
        if let metres, let weekMean, weekMean > 0 {
            let ahead = metres >= weekMean
            badge = .init(text: ahead ? L("ABOVE 7D MEAN") : L("BELOW 7D MEAN"),
                          tint: ahead ? NB.optimal2 : NB.ember1)
        }

        // When the ground was covered, on the user day's own thirds. The band files metres
        // per five minutes, so this is a sum of ticks and not a route.
        var morning = 0.0, afternoon = 0.0, night = 0.0
        for tick in ticks {
            guard let d = tick.dis, d > 0 else { continue }
            let hour = tick.ts.timeIntervalSince(m.day.start) / 3600
            if hour < 8 { morning += d } else if hour < 16 { afternoon += d } else { night += d }
        }
        let bands: [VitalsSplit.Band] = (morning + afternoon + night) == 0 ? [] : [
            .init(name: "04–12", tint: NB.violetPink.opacity(0.45), share: morning,
                  detail: distanceLabel(morning)),
            .init(name: "12–20", tint: NB.violetPink, share: afternoon,
                  detail: distanceLabel(afternoon)),
            .init(name: "20–04", tint: NB.violet1, share: night, detail: distanceLabel(night)),
        ]

        // Stride is the day's own two numbers divided, which is why it is here and not a
        // setting: metres over steps, in centimetres.
        let stride: Double? = {
            guard let metres, let steps, steps > 0 else { return nil }
            return metres / steps * 100
        }()

        return VitalsReadout(
            badge: badge,
            value: metres.map { String(format: "%.2f", $0 / 1000) },
            unit: "KM",
            gauge: gauge(low: week.min().map { L("7D LOW %.1f", $0 / 1000) } ?? L("7D LOW %@", Fmt.dash),
                         now: metres.map { L("TODAY %.2f", $0 / 1000) } ?? L("TODAY %@", Fmt.dash),
                         high: week.max().map { L("7D HIGH %.1f", $0 / 1000) } ?? L("7D HIGH %@", Fmt.dash),
                         value: metres, low: week.min(), high: week.max()),
            footLeft: metres.map { L("%@ METRES TODAY", Fmt.kcal($0)) } ?? L("NO DISTANCE YET"),
            footRight: m.activeMinutes.map { L("ACTIVE %@", Fmt.duration($0)) },
            chartNote: L("CUMULATIVE · TODAY"),
            splitTitle: L("WHEN IT HAPPENED"),
            splitTrailing: metres.map { L("%.2f KM", $0 / 1000) },
            bands: bands,
            statLeft: .init(label: L("STRIDE LENGTH"), value: stride.map { String(format: "%.0f", $0) },
                            unit: "CM",
                            foot: steps.map { L("%@ STEPS", Fmt.kcal($0)) } ?? L("NEEDS STEPS"),
                            tint: NB.violetPink),
            statRight: .init(label: L("ACTIVITY BURN"), value: activeKcal.map { Fmt.kcal($0) }, unit: "KCAL",
                             foot: activeKcal == nil ? L("NEEDS YOUR WEIGHT") : L("MOVEMENT ONLY"),
                             tint: NB.run1))
    }

    // MARK: 08 · metabolic burn

    private static func active(m: DailyMetrics) -> VitalsReadout {
        let bmr = m.bmr
        let move = m.eActive
        let train = m.eTrain
        // The board's hero is the whole burn; the card that opened this page showed the
        // active part, which is why that number is repeated in the badge and the foot.
        let total = m.eOutNow ?? sum([bmr, move, train])
        let bins = VitalsMath.hourSum(m.vitalsCurve, day: m.day, value: \.cal)
        let peak = VitalsMath.peak(bins)

        var bands: [VitalsSplit.Band] = []
        let parts: [(String, Color, Double?)] = [
            (L("Resting"), NB.macroValue, bmr),
            (L("Active"), NB.run1, move),
            (L("Training"), NB.cyan1, train),
        ]
        for (name, tint, value) in parts {
            guard let value, value > 0 else { continue }
            bands.append(.init(name: name, tint: tint, share: value, detail: Fmt.kcal(value)))
        }

        return VitalsReadout(
            badge: move.map { .init(text: L("ACTIVE %@", Fmt.kcal($0)), tint: NB.run1) },
            value: total.map { Fmt.kcal($0) },
            unit: "KCAL",
            gauge: gauge(low: bmr.map { L("RESTING %@", Fmt.kcal($0)) } ?? L("RESTING %@", Fmt.dash),
                         now: move.map { L("ACTIVE %@", Fmt.kcal($0)) } ?? L("ACTIVE %@", Fmt.dash),
                         high: total.map { L("TOTAL %@", Fmt.kcal($0)) } ?? L("TOTAL %@", Fmt.dash),
                         // How much of the burn was moved for, rather than simply elapsed.
                         value: move, low: 0, high: total),
            footLeft: (bmr != nil || move != nil)
                ? L("RESTING %@ + ACTIVE %@", Fmt.kcal(bmr), Fmt.kcal(move))
                : L("NEEDS YOUR WEIGHT"),
            footRight: m.bmrFull.map { L("FULL DAY BASELINE %@", Fmt.kcal($0)) },
            chartNote: L("TODAY · PER HOUR"),
            splitTitle: L("WHERE THE BURN CAME FROM"),
            splitTrailing: total.map { L("%@ KCAL", Fmt.kcal($0)) },
            bands: bands,
            // The peak hour rather than the active-minute count: 補屏 B leaves activeMinutes
            // nil on a day with no weight, and a nil tile whose foot read "PEAK 19 KCAL/H"
            // was two unrelated facts stacked on each other.
            statLeft: .init(label: L("PEAK BURN HOUR"), value: peak.map { Fmt.kcal($0.value) },
                            unit: "KCAL",
                            foot: peak.map { L("AT %@", VitalsMath.clock(day: m.day, minute: $0.index * 60)) }
                                ?? L("NO TICKS YET"),
                            tint: NB.run1),
            // ⚠️ bmrFull is the whole day's baseline and bmr is the part that has elapsed.
            // The tile used to print —— for bmrFull with the foot "NEEDS YOUR WEIGHT" while
            // RESTING 1,480 — which only exists because the weight does — sat right above it.
            statRight: .init(label: L("RESTING BASELINE"), value: (m.bmrFull ?? bmr).map { Fmt.kcal($0) },
                             unit: "KCAL",
                             foot: m.bmrFull != nil ? L("WHOLE DAY, UNMOVED")
                                 : (bmr != nil ? L("ELAPSED SO FAR") : L("NEEDS YOUR WEIGHT")),
                             tint: nil))
    }
}

// MARK: - arithmetic

private extension VitalsReadout {

    /// The hero's rail. Without both ends there is no span to place the reading in, and the
    /// rail is drawn empty rather than full.
    static func gauge(low: String, now: String, high: String,
                      value: Double?, low lowValue: Double?, high highValue: Double?) -> VitalsGauge.Model {
        var fraction: Double?
        if let value, let lowValue, let highValue, highValue > lowValue {
            fraction = (value - lowValue) / (highValue - lowValue)
        }
        return .init(lowLabel: low, nowLabel: now, highLabel: high, fraction: fraction)
    }

    /// 05 · what the deviation is measured from, and the name of the window it came from.
    ///
    /// The order is physiological rather than convenient: skin temperature has a circadian
    /// floor, so the night the band staged is the truest reference; failing that, the day's
    /// own 04:00–08:00 hours are the same trough addressed by the clock instead of by the
    /// band's staging; failing both, the days behind today. The page used to take only the
    /// last of the three, which left the hero at —— on a first day holding a hundred real
    /// skin ticks — a page dashing out the very thing it had measured.
    static func tempBaseline(m: DailyMetrics, history: [DailyMetrics]) -> (value: Double, source: String)? {
        if let start = m.sleep?.sleepStart, let wake = m.sleep?.wakeAt, wake > start {
            let staged = m.vitalsCurve.filter { $0.ts >= start && $0.ts <= wake }.compactMap(\.temp)
            if let value = mean(staged) { return (value, "NIGHT MEAN") }
        }
        let trough = m.vitalsCurve.filter {
            let hours = $0.ts.timeIntervalSince(m.day.start) / 3600
            return hours >= 0 && hours < 4
        }.compactMap(\.temp)
        if let value = mean(trough) { return (value, "04–08 TROUGH") }

        let past = history.suffix(8).dropLast().flatMap { $0.vitalsCurve.compactMap(\.temp) }
        if let value = mean(past) { return (value, "7 DAYS") }
        return nil
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// nil when every part is nil — a total of nothing is not zero.
    static func sum(_ parts: [Double?]) -> Double? {
        let present = parts.compactMap { $0 }
        return present.isEmpty ? nil : present.reduce(0, +)
    }

    /// "↓ 2 BPM vs 7d", and the colour that goes with the direction. Without both numbers it
    /// says so instead of printing a delta against a baseline that does not exist.
    static func delta(_ value: Double?, vs baseline: Double?, unit: String, suffix: String,
                      lowerIsBetter: Bool) -> (text: String, tint: Color?) {
        guard let value, let baseline else { return (L("NO BASELINE YET"), nil) }
        let diff = value - baseline
        let rounded = Int(abs(diff).rounded())
        guard rounded > 0 else { return (L("LEVEL %@", L(suffix)), nil) }
        let better = lowerIsBetter ? diff < 0 : diff > 0
        return (L("%@ %d %@ %@", diff < 0 ? "↓" : "↑", rounded, unit, L(suffix)),
                better ? NB.optimal2 : NB.ember1)
    }

    /// A page whose metric has nothing on record at all. It keeps every frame the board drew
    /// and fills none of them in — 04B F5 · an empty page, not a zeroed one.
    static func empty(unit: String?, foot: String, chartNote: String, splitTitle: String,
                      statLeft: VitalsStatPair.Model,
                      statRight: VitalsStatPair.Model) -> VitalsReadout {
        VitalsReadout(badge: nil, value: nil, unit: unit, gauge: nil,
                      footLeft: foot, footRight: nil,
                      chartNote: chartNote, splitTitle: splitTitle, splitTrailing: nil,
                      bands: [], statLeft: statLeft, statRight: statRight)
    }
}
