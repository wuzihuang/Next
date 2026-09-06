import SwiftUI

/// 04 · 8 大指标二级页 · everything the page prints, derived from the day the app already
/// holds. No view in this feature computes a number; they only lay one out.
///
/// ⚠️ Nothing here reads the band and nothing here invents. Every field is either a value
/// that arrived — a tick, a night, a server-settled total — or nil, which renders as ——
/// (F2 rule 05). A zero is only ever printed when the band actually reported one: a still
/// hour is a fact, a missing hour is not.
struct VitalsReadout {
    var value: String?
    var unit: String?
    var dial: VitalsDial.Model?
    var footLeft: String
    var footRight: String?
    /// The note at the right of the chart card — the ruler the curve is drawn against.
    var chartNote: String
    var splitTitle: String
    var splitTrailing: String?
    var bands: [VitalsSplit.Band]
    var statLeft: VitalsStatPair.Model
    var statRight: VitalsStatPair.Model
    /// Sleep carries a second pair (min SpO2 · wakes). Other pages leave this empty.
    var extraLeft: VitalsStatPair.Model? = nil
    var extraRight: VitalsStatPair.Model? = nil
    var respirationLeft: VitalsStatPair.Model? = nil
    var respirationRight: VitalsStatPair.Model? = nil
    /// The physiological band drawn behind the trace, in the chart's own units — the resting
    /// pulse, the stable temperature window. It is a reference, never a target.
    var referenceBand: ClosedRange<Double>?
    var referenceLabel: String?
    /// 05 · the vertical ruler the skin-temperature trace is drawn against, in °C. It is this
    /// person's own night range with room around it, so a 33 °C wrist is not flattened.
    var traceRange: ClosedRange<Double>?
    /// The stretch of the chart the reference band belongs to — last night's sleep window.
    /// A band drawn across the daytime hours would be judging them (ADR 0009).
    var referenceSpan: ClosedRange<Date>?

    /// One tick is five minutes wide, which is the finest any duration on these pages can
    /// be. 08 rule 02 · zone minutes are multiples of five, floored — 「Z5 4 MIN」 cannot exist.
    static let tickMinutes = 5
}

// MARK: - the day's three totals

extension VitalsReadout {
    /// Steps and metres may be summed from measured tick increments. Active kcal may not:
    /// the archived vendor calorie field is a differently-defined counter, so energy waits
    /// for the server's weight-aware settled value.
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
        ActivityEnergyPolicy.displayTotal(
            settledActiveKcal: m.eActive,
            archivedVendorCalories: m.vitalsCurve.compactMap(\.vendorCalories))
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
                     profile: Profile,
                     mealResponse: MealResponseIndex.Result? = nil,
                     mealBoard: MealResponsePresentation.Board? = nil) -> VitalsReadout {
        switch metric {
        case .heart:    heart(m: m, history: history, vitals: vitals, profile: profile)
        case .sleep:    sleep(m: m)
        case .hrv:      hrv(m: m)
        case .response: response(mealBoard, fallback: mealResponse)
        case .stress:   stress(m: m, vitals: vitals)
        case .temp:     temp(m: m, history: history)
        case .steps:    steps(m: m, history: history)
        case .distance: distance(m: m, history: history)
        case .active:   active(m: m, history: history)
        }
    }

    // MARK: 01 · heart

    private static func heart(m: DailyMetrics, history: [DailyMetrics],
                              vitals: LiveVitals, profile: Profile) -> VitalsReadout {
        let ticks = m.vitalsCurve
        let hrs = ticks.compactMap(\.hr)
        let gone = vitals.freshness == .gone
        let now = gone ? nil : (vitals.hr ?? ticks.last(where: { $0.hr != nil })?.hr)
        let resting = m.nightInputs?.rhr.map { Int($0.rounded()) }

        let restingBand = resting.map { Double($0)...Double($0 + 20) }
        let sevenDayResting = mean(history.suffix(8).dropLast().compactMap { $0.nightInputs?.rhr })
        let placed = VitalsDialMath.heartCuts(maxHR: profile.hrMax)
        let cuts = placed.cuts.map { Int($0.rounded()) }

        var out = VitalsReadout(
            value: now.map(String.init),
            unit: "BPM",
            dial: dial(scale: placed.scale, cuts: placed.cuts, value: now.map(Double.init),
                       names: [L("RESTING"), L("EASY"), L("AEROBIC"), L("PEAK")],
                       tints: [NB.blue1, NB.lime2, NB.ember1, NB.alert2]),
            footLeft: vitals.at.map { L("LAST TICK %@", Fmt.clock($0)) } ?? L("NO TICK YET"),
            footRight: L("BOUNDS %d · %d · %d BPM", cuts[0], cuts[1], cuts[2]),
            chartNote: L("FIXED 40–160 BPM"),
            splitTitle: L("TIME IN ZONES"),
            splitTrailing: zoneTotal(m: m, ticks: ticks, profile: profile),
            bands: heartZoneBands(m: m, ticks: ticks, profile: profile),
            statLeft: .init(label: L("RESTING HR"), value: resting.map(String.init), unit: "BPM",
                            foot: delta(resting.map(Double.init), vs: sevenDayResting,
                                        unit: "BPM", suffix: "vs 7d", lowerIsBetter: true).text,
                            tint: delta(resting.map(Double.init), vs: sevenDayResting,
                                        unit: "BPM", suffix: "vs 7d", lowerIsBetter: true).tint),
            statRight: .init(label: L("24H MEAN"), value: mean(hrs.map(Double.init)).map { String(Int($0.rounded())) },
                             unit: "BPM",
                             foot: hrs.isEmpty ? L("NO TICKS YET")
                                 : L("LOW %d · HIGH %d", hrs.min()!, hrs.max()!),
                             tint: NB.lime1))
        out.referenceBand = restingBand
        out.referenceLabel = restingBand.map { L("RESTING BAND %d–%d", Int($0.lowerBound), Int($0.upperBound)) }
        return out
    }

    /// Week and month hero: a median on the same dial the live reading uses. The number
    /// is the median of daily medians so one loud hour cannot drag the window.
    static func heartWindow(daily: [[Double]], profile: Profile, days: Int) -> VitalsReadout {
        let placed = VitalsDialMath.heartCuts(maxHR: profile.hrMax)
        let cuts = placed.cuts.map { Int($0.rounded()) }
        let median = HeartWindowMath.medianOfDailyMedians(daily)
        let worn = HeartWindowMath.wornDays(daily)
        let high = HeartWindowMath.extreme(daily, pick: max)
        let low = HeartWindowMath.extreme(daily, pick: min)
        var out = VitalsReadout(
            value: median.map { String(Int($0.rounded())) },
            unit: "BPM",
            dial: dial(scale: placed.scale, cuts: placed.cuts, value: median,
                       names: [L("RESTING"), L("EASY"), L("AEROBIC"), L("PEAK")],
                       tints: [NB.blue1, NB.lime2, NB.ember1, NB.alert2]),
            footLeft: L("%d DAYS WORN", worn),
            footRight: L("BOUNDS %d · %d · %d BPM", cuts[0], cuts[1], cuts[2]),
            chartNote: L("FIXED 40–160 BPM"),
            splitTitle: L("TIME IN ZONES"),
            splitTrailing: nil,
            bands: [],
            statLeft: .init(label: L("%d DAYS WORN", worn),
                            value: String(worn), unit: L("OF %d", days),
                            foot: L("ROLLING"), tint: nil),
            statRight: .init(label: L("WINDOW MAX"),
                             value: high.map { String(Int($0.rounded())) }, unit: "BPM",
                             foot: low.map { L("LOW %d", Int($0.rounded())) } ?? L("NO TICKS YET"),
                             tint: NB.lime1))
        out.referenceBand = nil
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

    static func sleepHRVSamples(night: SleepSummary?, fallback: [VitalSample]) -> [VitalSample] {
        guard let night else { return [] }
        let samples = night.hrv.map { points in
            points.map { VitalSample(ts: $0.ts, hr: nil, stress: nil, hrv: $0.rmssdMS) }
        } ?? fallback
        return samples.filter {
            guard night.containsSleepTimestamp($0.ts), let value = $0.hrv else { return false }
            return value.isFinite && value > 0
        }.sorted { $0.ts < $1.ts }
    }

    static func hasHRVOutsideSleep(night: SleepSummary?, samples: [VitalSample]) -> Bool {
        guard let night, let start = night.sleepStart, let wake = night.wakeAt, wake > start else { return false }
        return samples.contains {
            guard let value = $0.hrv, value.isFinite, value > 0 else { return false }
            return !night.containsSleepTimestamp($0.ts)
        }
    }

    private static func sleep(m: DailyMetrics) -> VitalsReadout {
        guard let night = m.sleep, night.totalMinutes > 0 else {
            var out = empty(unit: L("ASLEEP"),
                            foot: L("NO NIGHT ON RECORD"),
                            chartNote: L("4 STAGES"),
                            splitTitle: L("STAGE PROPORTIONS"),
                            statLeft: .init(label: L("NIGHT HRV"), value: nil, unit: "MS",
                                            foot: L("WEAR IT TONIGHT"), tint: nil),
                            statRight: .init(label: L("NIGHT SPO2"), value: nil, unit: "%",
                                             foot: L("WEAR IT TONIGHT"), tint: nil))
            out.extraLeft = .init(label: L("SPO2 MIN"), value: nil, unit: "%",
                                  foot: L("WEAR IT TONIGHT"), tint: nil)
            out.extraRight = .init(label: L("WAKE EVENTS"), value: nil, unit: nil,
                                   foot: L("WEAR IT TONIGHT"), tint: nil)
            return out
        }

        let total = night.totalMinutes
        let spo2Percents = night.spo2.filter { night.containsSleepTimestamp($0.ts) }.map(\.percent)
        let spo2 = HealthSampleMapping.overnightOxygenSummary(spo2Percents)
        let hrv = mean(sleepHRVSamples(night: night, fallback: m.vitalsCurve).compactMap(\.hrv))
        let hrvBase = m.nightInputs?.hrvBase

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
            // ⚠️ A stage line is not a promise of every stage. Whether a night carries REM is
            // decided per record by `VPAccurateSleepModel.accurateType`: 1 (精准睡眠) files
            // stage 2 runs, 0 (普通睡眠) files only deep and light — both on the same band, on
            // consecutive nights. Measured 2026-09-05: accurateType 1 gave `2:83`, while the
            // two nights before it, accurateType 0, gave none. Drawing a zero-width REM band
            // on those nights tells the reader they had no REM sleep, which is not what the
            // band said — it said it was not measuring for it. An absent stage is left out.
            bands = [
                .init(name: L("Deep"), tint: NB.violet1, share: Double(night.deepMinutes),
                      detail: Fmt.duration(night.deepMinutes)),
                .init(name: L("Light"), tint: NB.violet2, share: Double(night.lightMinutes),
                      detail: Fmt.duration(night.lightMinutes)),
            ]
            if night.remMinutes > 0 {
                bands.append(.init(name: L("REM"), tint: NB.blue1, share: Double(night.remMinutes),
                                   detail: Fmt.duration(night.remMinutes)))
            }
            if night.awakeMinutes > 0 {
                bands.append(.init(name: L("Awake"), tint: NB.white.opacity(0.35),
                                   share: Double(night.awakeMinutes),
                                   detail: Fmt.duration(night.awakeMinutes)))
            }
        }

        let window: String
        if let start = night.sleepStart, let wake = night.wakeAt, wake > start {
            window = L("BED %@ · WAKE %@", Fmt.clock(start), Fmt.clock(wake))
        } else {
            window = L("WINDOW NOT ON RECORD")
        }

        var out = VitalsReadout(
            value: Fmt.duration(total),
            unit: L("ASLEEP"),
            dial: nil,
            footLeft: window,
            footRight: deepEpisodes > 0 ? L("%d DEEP EPISODES", deepEpisodes) : nil,
            chartNote: night.line.isEmpty ? L("TOTALS ONLY") : L("AWAKE · REM · LIGHT · DEEP"),
            splitTitle: L("STAGE PROPORTIONS"),
            splitTrailing: L("TOTAL %@", Fmt.duration(total)),
            bands: bands,
            statLeft: .init(label: L("NIGHT HRV"), value: hrv.map { String(Int($0.rounded())) },
                            unit: "MS",
                            foot: hrvBase.map { L("BASE %d MS", Int($0.rounded())) } ?? L("NO BASELINE YET"),
                            tint: NB.blue1),
            statRight: .init(label: L("NIGHT SPO2"), value: spo2.map { String($0.mean) },
                             unit: "%",
                             foot: spo2.map { _ in L("%d READINGS", spo2Percents.count) }
                                 ?? L("NO OVERNIGHT OXYGEN"),
                             tint: NB.cyan1))
        out.extraLeft = .init(label: L("SPO2 MIN"), value: spo2.map { String($0.min) },
                              unit: "%",
                              foot: spo2 == nil ? L("NO OVERNIGHT OXYGEN")
                                  : L("IN THE NIGHT WINDOW"),
                              tint: NB.cyan1)
        out.extraRight = .init(label: L("WAKE EVENTS"), value: String(night.wakeCount),
                               unit: night.wakeCount == 1 ? L("WAKE") : L("WAKES"),
                               foot: night.awakeMinutes > 0 ? L("%@ AWAKE", Fmt.duration(night.awakeMinutes))
                                                            : L("NONE STAGED AWAKE"),
                               tint: nil)
        let respiration = (night.respiration ?? []).filter {
            night.containsSleepTimestamp($0.ts) && $0.breathsPerMinute.isFinite && $0.breathsPerMinute > 0
        }.map(\.breathsPerMinute)
        let respirationMean = respiration.isEmpty ? nil : respiration.reduce(0, +) / Double(respiration.count)
        out.respirationLeft = .init(label: L("MEAN RESPIRATION"),
                                    value: respirationMean.map { String(format: "%.1f", $0) },
                                    unit: L("BREATHS / MIN"),
                                    foot: respiration.isEmpty ? L("NO SLEEP RESPIRATION") : L("%d READINGS", respiration.count),
                                    tint: NB.violet2)
        out.respirationRight = .init(label: L("RESPIRATION RANGE"),
                                     value: respiration.min().flatMap { low in
                                         respiration.max().map { String(format: "%.1f–%.1f", low, $0) }
                                     }, unit: L("BREATHS / MIN"),
                                     foot: L("IN THE NIGHT WINDOW"), tint: NB.violet2)
        return out
    }

    // MARK: 03b · meal response

    private static func response(_ board: MealResponsePresentation.Board?,
                                 fallback: MealResponseIndex.Result?) -> VitalsReadout {
        let result = board?.index ?? fallback ?? MealResponseIndex.make(
            points: [], sleepWindows: [], now: Date())
        let range = board?.range ?? .day
        let heroPoint = board?.heroPoint ?? result.latestPoint
        let heroPercent = board?.heroPercent ?? result.hero
        // ⚠️ The annotation is load-bearing. `??` is generic, and a tuple's labels are
        // stripped when they pass through a generic parameter, so without it `split` comes
        // out as a bare `(Int, Int, Int)` and `.below` stops resolving.
        let split: (below: Int, near: Int, above: Int) =
            board?.split ?? (below: result.below, near: result.near, above: result.above)
        let pointCount = board?.pointCount ?? result.trendPoints.count
        let hero = heroPoint.map(MealResponseIndex.pointValue)
        let bands: [VitalsSplit.Band]
        if split.below + split.near + split.above == 0 {
            bands = []
        } else {
            bands = [
                .init(name: L("Below"), tint: NB.ember1, share: Double(split.below),
                      detail: "\(split.below)"),
                .init(name: L("Near"), tint: NB.compareAmber, share: Double(split.near),
                      detail: "\(split.near)"),
                .init(name: L("Above"), tint: NB.optimal2, share: Double(split.above),
                      detail: "\(split.above)"),
            ]
        }
        let versus = heroPercent.map(MealResponseIndex.signedPercent)
        let foot: String
        if heroPoint != nil {
            if result.ownMedianReady, let versus {
                foot = range == .day
                    ? L("%@ VS OWN MEDIAN", versus)
                    : L("%@ VS OWN", versus)
            } else {
                foot = L("%d / 5 BASELINE DAYS", result.baselineDays)
            }
        } else if range != .day {
            foot = L("NO RESPONSE POINTS IN THIS WINDOW")
        } else {
            switch result.empty {
            case .needs5Days: foot = L("NEEDS 5 DAYS")
            case .switchOff:  foot = L("SWITCH OFF")
            case .allZeros:   foot = L("ALL ZEROS")
            case .empty:      foot = L("NO TICKS TODAY")
            case nil:         foot = L("NO TICKS TODAY")
            }
        }
        let footRight: String?
        switch range {
        case .day:
            footRight = pointCount == 0 ? nil : L("%d POINTS", pointCount)
        case .week, .month:
            let days = board?.window.recordedDays ?? 0
            footRight = days == 0 ? nil : L("%d DAYS", days)
        }
        var out = VitalsReadout(
            value: hero,
            unit: nil,
            dial: heroPercent.map {
                let placed = VitalsDialMath.responseCuts(percent: Double($0))
                return dial(scale: placed.scale, cuts: placed.cuts, value: Double($0),
                            names: [L("BELOW"), L("NEAR"), L("ABOVE")],
                            tints: [NB.ember1, NB.compareAmber, NB.optimal2])
            },
            footLeft: foot,
            footRight: footRight,
            chartNote: range == .day
                ? L("EVERY %d MIN · LOW–HIGH", Int(VitalsTrace.defaultSlotMinutes))
                : L("DAILY VS OWN"),
            splitTitle: L("VS OWN MEDIAN"),
            splitTrailing: pointCount == 0 ? nil : L("%d POINTS", pointCount),
            bands: bands,
            statLeft: .init(
                label: range.responseAverageLabel,
                value: (range == .day ? result.median24hPoint : heroPoint)
                    .map(MealResponseIndex.pointValue),
                unit: nil,
                foot: range == .day
                    ? (result.median24hPoint == nil ? L("NO TICKS TODAY") : L("MEASURED POINTS"))
                    : L("%d OF %d DAYS", board?.window.recordedDays ?? 0, DetailWindow(.response, range).days),
                tint: NB.compareAmber),
            statRight: .init(
                label: range == .day ? L("VS OWN MEDIAN") : L("VS OWN"),
                value: versus,
                unit: nil,
                foot: result.ownMedianReady
                    ? (range == .day ? L("LATEST POINT") : L("WINDOW AVERAGE"))
                    : L("%d / 5 BASELINE DAYS", result.baselineDays),
                tint: result.ownMedianReady ? NB.compareAmber : nil))
        if let median = result.ownMedian, median > 0 {
            out.referenceBand = (median * 0.92)...(median * 1.08)
            out.referenceLabel = L("OWN MEDIAN %@", MealResponseIndex.pointValue(median))
            let values = result.trendPoints.map(\.optical)
            out.traceRange = MealResponseIndex.axis(values: values, ownMedian: median)
        } else {
            out.traceRange = MealResponseIndex.axis(values: result.trendPoints.map(\.optical),
                                                    ownMedian: nil)
        }
        return out
    }

    // MARK: 03 · HRV

    private static func hrv(m: DailyMetrics) -> VitalsReadout {
        let night = m.nightInputs
        let value = night?.hrv
        let base = night?.hrvBase
        let ticks = m.vitalsCurve.compactMap(\.hrv)

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
            value: value.map { String(Int($0.rounded())) },
            unit: "MS",
            dial: VitalsDialMath.ratioCuts(base: base ?? 0).map {
                dial(scale: $0.scale, cuts: $0.cuts, value: value,
                     names: [L("BELOW"), L("IN RANGE"), L("ABOVE")],
                     tints: [NB.ember1, NB.blue1, NB.optimal2])
            },
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
            value: now.map(String.init),
            unit: "/ 100",
            dial: dial(scale: VitalsDialMath.stressCuts().scale,
                       cuts: VitalsDialMath.stressCuts().cuts,
                       value: now.map(Double.init),
                       names: [L("REST"), L("STEADY"), L("ELEVATED"), L("HIGH")],
                       tints: [NB.optimal2, NB.lime1, NB.ember1, NB.alert2]),
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

    /// ADR 0009 · last night against this wrist's own night range. Nothing daytime is judged:
    /// the arm is out from under the covers and runs 1–2 °C cooler, which is exactly how a
    /// single baseline point plus a fixed ±0.3 °C step came to call an ordinary afternoon a
    /// deviation. The daytime ticks stay on the page as description.
    private static func temp(m: DailyMetrics, history: [DailyMetrics]) -> VitalsReadout {
        let ticks = m.vitalsCurve
        let today = ticks.compactMap(\.temp)
        let night = SkinTempPresentation.nightRange(today: m, history: history)
        let range = night.range

        let names = [L("Below"), L("In range"), L("Above")]
        let tints = [NB.blue1, NB.optimal2, NB.ember1]
        let minutes = [night.minutesBelow, night.minutesWithin, night.minutesAbove]
        let totalMinutes = minutes.reduce(0, +)
        let bands: [VitalsSplit.Band] = totalMinutes == 0 ? [] : (0..<3).map { i in
            .init(name: names[i], tint: tints[i], share: Double(minutes[i]),
                  detail: Fmt.duration(minutes[i]))
        }

        // Before the range exists the hero prints the measured skin temperature rather than
        // a deviation from nothing — a first week of real ticks is not an empty page.
        let hasVerdict = night.delta != nil
        let value = hasVerdict
            ? night.delta.map { String(format: "%+.1f", $0) }
            : night.latestSkin.map { String(format: "%.1f", $0) }

        var out = VitalsReadout(
            value: value,
            unit: hasVerdict ? L("°C · LAST NIGHT") : L("°C SKIN"),
            dial: (hasVerdict ? range.flatMap { VitalsDialMath.rangeCuts(lower: $0.lower, upper: $0.upper) } : nil)
                .map {
                    dial(scale: $0.scale, cuts: $0.cuts, value: night.lastNightMean,
                         names: [L("BELOW"), L("IN RANGE"), L("ABOVE")],
                         tints: [NB.blue1, NB.optimal2, NB.ember1])
                },
            footLeft: range.map { L("YOUR RANGE %.1f–%.1f °C · %d NIGHTS", $0.lower, $0.upper, $0.nights) }
                ?? L("LEARNING · %d / 5 NIGHTS", night.learningNights),
            // The learning count is already the left foot; the right one stays the measurement.
            footRight: night.empty.flatMap { empty in
                empty == .needsFiveNights ? nil
                    : SkinTempPresentation.reason(empty, learningNights: night.learningNights)
            } ?? night.latestSkin.map { L("SKIN %.1f °C", $0) },
            chartNote: range == nil ? L("FIXED 30–38 °C") : L("SCALED TO YOUR RANGE"),
            splitTitle: L("TIME OFF YOUR RANGE"),
            splitTrailing: totalMinutes > 0 ? L("LAST NIGHT %@", Fmt.duration(totalMinutes)) : nil,
            bands: bands,
            statLeft: .init(label: L("24H LOW"), value: today.min().map { String(format: "%.1f", $0) },
                            unit: "°C",
                            foot: today.isEmpty ? L("NO TICKS YET") : L("%d TICKS · 24H", today.count),
                            tint: NB.blue1),
            statRight: .init(label: L("24H HIGH"), value: today.max().map { String(format: "%.1f", $0) },
                             unit: "°C",
                             // The daytime number is described, never scored (ADR 0009).
                             foot: night.dayMean.map { L("DAY MEAN %.1f °C", $0) } ?? L("NO TICKS YET"),
                             tint: NB.ember1))
        out.traceRange = SkinTempPresentation.axis(range, pad: 1.5)
        out.referenceBand = range.map { $0.lower...$0.upper }
        out.referenceLabel = range.map { L("YOUR RANGE %.1f–%.1f °C", $0.lower, $0.upper) }
        out.referenceSpan = night.lastNight.map { $0.start...$0.end }
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
            value: total.map { Fmt.kcal($0) },
            unit: L("STEPS"),
            dial: total.flatMap { today in
                VitalsDialMath.weekCuts(today: today, week: week).map {
                    dial(scale: $0.scale, cuts: $0.cuts, value: today,
                         names: [L("WELL BELOW"), L("YOUR USUAL RANGE"), L("ABOVE")],
                         tints: [NB.white.opacity(0.45), NB.optimal2, NB.lime2])
                }
            },
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
            value: metres.map { String(format: "%.2f", $0 / 1000) },
            unit: "KM",
            dial: metres.flatMap { today in
                VitalsDialMath.weekCuts(today: today, week: week).map {
                    dial(scale: $0.scale, cuts: $0.cuts, value: today,
                         names: [L("WELL BELOW"), L("YOUR USUAL RANGE"), L("ABOVE")],
                         tints: [NB.white.opacity(0.45), NB.violetPink, NB.lime2])
                }
            },
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

    private static func active(m: DailyMetrics, history: [DailyMetrics]) -> VitalsReadout {
        let now = VitalsClock.now
        let ticks = m.vitalsCurve.map { ($0.ts, $0.steps) }
        let windows = ActiveEnergyModel.sportWindows(m)
        let split = ActiveEnergyMath.split(
            dayStart: m.day.start, now: now, bmr: m.bmr, bmrFull: m.bmrFull,
            eActive: m.eActive, eTrain: m.eTrain, eOutNow: m.eOutNow,
            ticks: ticks, sportWindows: windows)
        let hours = ActiveEnergyMath.hourly(
            dayStart: m.day.start, now: now, split: split,
            ticks: ticks, sportWindows: windows)
        let peak = ActiveEnergyMath.peakHour(hours)
        let bands: [VitalsSplit.Band] = [
            (L("RESTING"), NB.white.opacity(0.45), split.resting),
            (L("SPORT"), NB.lime1, split.sport),
            (L("STEPS"), NB.lime1.opacity(0.75), split.steps),
            (L("INCIDENTAL"), NB.lime1.opacity(0.55), split.incidental),
        ].compactMap { name, tint, value in
            guard let value, value > 0 else { return nil }
            return .init(name: name, tint: tint, share: value, detail: Fmt.kcal(value))
        }

        let week = history.suffix(8).dropLast().compactMap { $0.eOutNow ?? sum([$0.bmr, $0.eActive, $0.eTrain]) }
        return VitalsReadout(
            value: split.out.map { Fmt.kcal($0) },
            unit: "KCAL",
            dial: split.out.flatMap { today in
                VitalsDialMath.weekCuts(today: today, week: week).map {
                    dial(scale: $0.scale, cuts: $0.cuts, value: today,
                         names: [L("WELL BELOW"), L("YOUR USUAL RANGE"), L("ABOVE")],
                         tints: [NB.white.opacity(0.45), NB.lime1, NB.lime2])
                }
            },
            footLeft: (split.resting != nil || split.active != nil)
                ? L("RESTING %@ + ACTIVE %@", Fmt.kcal(split.resting), Fmt.kcal(split.active))
                : L("NEEDS YOUR WEIGHT"),
            footRight: split.bmrFull.map { L("FULL DAY BASELINE %@", Fmt.kcal($0)) },
            chartNote: L("TODAY · PER HOUR"),
            splitTitle: L("WHERE THE BURN CAME FROM"),
            splitTrailing: split.out.map { L("%@ KCAL", Fmt.kcal($0)) },
            bands: bands,
            statLeft: .init(label: L("PEAK BURN HOUR"),
                            value: peak.map { Fmt.kcal($0.kcal) },
                            unit: "KCAL",
                            foot: peak.map { L("PEAK %@", VitalsMath.clock(day: m.day, minute: $0.index * 60)) }
                                ?? L("HOURLY ENERGY NOT AVAILABLE"),
                            tint: NB.lime1),
            statRight: .init(label: L("RESTING BASELINE"),
                             value: (split.bmrFull ?? split.resting).map { Fmt.kcal($0) },
                             unit: "KCAL",
                             foot: split.bmrFull != nil ? L("WHOLE DAY, UNMOVED")
                                 : (split.resting != nil ? L("ELAPSED SO FAR") : L("NEEDS YOUR WEIGHT")),
                             tint: nil))
    }
}

// MARK: - arithmetic

extension VitalsReadout {

    static func dial(scale: ClosedRange<Double>, cuts: [Double], value: Double?,
                     names: [String], tints: [Color]) -> VitalsDial.Model {
        let edges = [scale.lowerBound] + cuts + [scale.upperBound]
        let count = min(names.count, tints.count, max(0, edges.count - 1))
        let zones: [VitalsDial.Zone] = (0..<count).map { i in
            .init(name: names[i], tint: tints[i],
                  weight: max(0.001, edges[i + 1] - edges[i]))
        }
        return .init(zones: zones,
                     fraction: value.map { VitalsDialMath.fraction(value: $0, scale: scale) },
                     activeIndex: value.map { min(count - 1, VitalsDialMath.activeIndex(value: $0, cuts: cuts)) },
                     cuts: cuts)
    }

    /// ADR 0008 · the score's own colour bands, without naming the night.
    static func sleepDial(score: Int) -> VitalsDial.Model {
        let placed = VitalsDialMath.sleepCuts()
        return dial(scale: placed.scale, cuts: placed.cuts, value: Double(score),
                    names: ["", "", "", ""],
                    tints: [NB.ember1, NB.compareAmber, NB.violet1, NB.optimal2])
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
        VitalsReadout(value: nil, unit: unit, dial: nil,
                      footLeft: foot, footRight: nil,
                      chartNote: chartNote, splitTitle: splitTitle, splitTrailing: nil,
                      bands: [], statLeft: statLeft, statRight: statRight)
    }
}
