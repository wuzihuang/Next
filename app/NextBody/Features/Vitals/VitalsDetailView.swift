import SwiftUI

/// 04 · 8 大指标二级页 · the second level behind every card on home page two.
///
/// One view for eight pages, because the board is one anatomy drawn eight times: the hero,
/// the chart on its fixed ruler, the distribution, the two tiles. What changes between them
/// is the shape of the chart and the arithmetic behind the numbers — and the arithmetic all
/// lives in `VitalsReadout`, which is the only thing on this page that knows what a metric is.
///
/// ⚠️ 04B rule 09 · not one read of the band happens here. Every number is a tick Body
/// Battery already pulled, a night `sleep_nights` already stored, or a total the server
/// already settled. Opening a detail page must never start a measurement.
struct VitalsDetailView: View {
    let metric: VitalsMetric
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    private var m: DailyMetrics { data.today }
    private var now: Date { VitalsClock.now }

    private var window: VitalsWindow {
        switch metric.timeline {
        case .lastNight:
            VitalsWindow.night(
                start: m.sleep?.sleepStart,
                end: m.sleep?.wakeAt,
                fallback: m.day
            )
        case .rolling24Hours:
            VitalsWindow.rolling24Hours(endingAt: now)
        case .userDayToNow:
            VitalsWindow.userDay(m.day, now: now)
        }
    }

    /// A rolling window crosses the 04:00 boundary, so today's row alone is insufficient.
    /// Merge history with the immediately synced local curve and then clip to the exact ruler.
    private var ticks: [VitalSample] {
        guard metric.timeline != .lastNight || window.span > 0 else { return [] }
        let stored = data.history.flatMap(\.vitalsCurve)
        return VitalSample.merging(stored, with: m.vitalsCurve)
            .filter { window.contains($0.ts) && (metric.timeline != .lastNight || m.sleep?.containsSleepTimestamp($0.ts) == true) }
    }

    private var displayMetrics: DailyMetrics {
        var metrics = m
        metrics.vitalsCurve = ticks
        if metric.timeline == .rolling24Hours {
            // These are server-derived user-day values. A 24-hour page must derive its zones
            // and peak from the same 24-hour ticks rather than mix two different windows.
            metrics.zoneMinutes = nil
            metrics.peakHR = nil
        }
        return metrics
    }

    private var readout: VitalsReadout {
        VitalsReadout.make(metric, m: displayMetrics, history: data.history,
                           vitals: data.vitals, profile: data.profile,
                           mealResponse: mealIndex)
    }

    private var mealIndex: MealResponseIndex.Result {
        MealResponsePresentation.index(
            today: m,
            history: data.history,
            points: data.mealResponsePoints,
            zerosToday: data.mealResponseZerosToday,
            now: now)
    }

    var body: some View {
        let r = readout
        return DetailScroll(glow: metric.tint, title: metric.title, trailing: {
            Text(metric.periodLabel)
                .font(NBFont.dot(600, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.text3Prod)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }) {
            VStack(alignment: .leading, spacing: 14) {
                VitalsHero(sensor: metric.sensor, badge: r.badge, value: r.value, unit: r.unit,
                           tint: metric.tint, gauge: r.gauge,
                           footLeft: r.footLeft, footRight: r.footRight)

                if metric == .sleep {
                    sleepBoard(r)
                } else {
                    CardBlock(title: metric.chartTitle, trailing: r.chartNote) {
                        chart(r)
                        VitalsAxis(labels: axisLabels,
                                   highlightsLast: window.endsNow,
                                   tint: metric.tint)
                    }
                }

                CardBlock(title: r.splitTitle, trailing: r.splitTrailing) {
                    VitalsSplit(bands: r.bands)
                }

                VitalsStatPair(left: r.statLeft, right: r.statRight)
                if let extraLeft = r.extraLeft, let extraRight = r.extraRight {
                    VitalsStatPair(left: extraLeft, right: extraRight)
                }

                footer
            }
            .padding(.horizontal, NB.Layout.gutter)
            .padding(.bottom, 30)
        } onBack: {
            router.backToRoot()
        }
        .task {
            // The card and the page file the same key, so 「点了哪张卡、看到的是数还是 ——」
            // is one join rather than two guesses.
            let states = VitalsPage.cardStates(
                m: m, vitals: data.vitals, history: data.history,
                mealResponsePoints: data.mealResponsePoints,
                mealResponseZerosToday: data.mealResponseZerosToday)
            await Analytics.shared.track("VITALS_DETAIL_OPEN", [
                "CARD": metric.cardKey,
                "STATE": states[metric.cardKey] ?? "EMPTY",
            ])
            if metric == .response {
                await Analytics.shared.track("RESPONSE_DETAIL_OPEN", [
                    "STATE": states["RESPONSE"] ?? "EMPTY",
                ])
            }
        }
    }

    private var axisLabels: [String] {
        switch metric.timeline {
        // ⚠️ The hypnogram is laid out along the *line's own minutes*, not along a clock —
        // that is what drawing the band's staging as-is means. Printing the day's
        // `04 · 08 · 12 · 16 · 20` under it labelled a 7-hour chart as 24 hours.
        case .lastNight:
            sleepAxisLabels
        case .rolling24Hours, .userDayToNow:
            window.labels
        }
    }

    /// The night's own clock when the band recorded its ends, and the hours elapsed into it
    /// when it did not — either way a ruler the staircase above it is actually drawn on.
    private var sleepAxisLabels: [String] {
        // No staircase means no ruler: a night stored as totals only has nothing laid out
        // along an axis, and a clock under an empty card describes nothing.
        guard let night = m.sleep, night.totalMinutes > 0, !night.line.isEmpty else { return [] }
        if let start = night.sleepStart, let wake = night.wakeAt, wake > start,
           (night.intervals?.count ?? 1) <= 1 || night.line.allSatisfy({ $0.offsetMinutes != nil }) {
            let span = wake.timeIntervalSince(start)
            return (0...4).map { Fmt.clock(start.addingTimeInterval(span * Double($0) / 4)) }
        }
        return (0...4).map { i in
            i == 0 ? "0H" : Fmt.duration(night.totalMinutes * i / 4)
        }
    }

    // MARK: sleep board — hypnogram, then night HRV, then overnight SpO2 on one clock

    @ViewBuilder
    private func sleepBoard(_ r: VitalsReadout) -> some View {
        CardBlock(title: metric.chartTitle, trailing: r.chartNote) {
            if let line = m.sleep?.line, !line.isEmpty {
                VitalsHypnogram(runs: line, tint: metric.tint, windowMinutes: window.span / 60)
            } else {
                VitalsChartEmpty(line: m.sleep == nil ? L("NO NIGHT ON RECORD") : L("TOTALS ONLY"),
                                 sub: m.sleep == nil ? L("WEAR IT TONIGHT")
                                                     : L("THE BAND FILED NO STAGE LINE"))
            }
            VitalsAxis(labels: axisLabels, highlightsLast: false, tint: metric.tint)
                .padding(.leading, VitalsHypnogram.labelGutter)
        }

        CardBlock(title: L("NIGHT HRV"), trailing: L("RMSSD IN THE WINDOW")) {
            let sleepHRV = VitalsReadout.sleepHRVSamples(night: m.sleep, fallback: ticks)
            if !sleepHRV.isEmpty {
                let nightly = data.history.suffix(15).dropLast().compactMap { $0.nightInputs?.hrv }
                VitalsScatter(samples: sleepHRV, window: window,
                              envelope: nightly.count >= 5 ? nightly.min()!...nightly.max()! : nil,
                              baseline: m.nightInputs?.hrvBase, tint: NB.blue1)
            } else {
                VitalsChartEmpty(line: L("NO RMSSD IN THE WINDOW"),
                                 sub: L("NO VALID HRV SAMPLES FOR THIS SLEEP"))
            }
            VitalsAxis(labels: window.labels, highlightsLast: false, tint: NB.blue1)
        }

        CardBlock(title: L("NIGHT SPO2"), trailing: L("FIXED 85–100 %")) {
            let points = (m.sleep?.spo2 ?? []).filter { m.sleep?.containsSleepTimestamp($0.ts) == true }
            if !points.isEmpty {
                VitalsOxygenTrace(points: points, window: window, tint: NB.cyan1)
            } else {
                VitalsChartEmpty(line: L("NO OVERNIGHT OXYGEN"),
                                 sub: L("AUTO NIGHT MEASUREMENT WAS OFF OR EMPTY"))
            }
            VitalsAxis(labels: window.labels, highlightsLast: false, tint: NB.cyan1)
        }

        CardBlock(title: L("SLEEP RESPIRATION"), trailing: L("FIXED 0–60 /MIN")) {
            let points = (m.sleep?.respiration ?? []).filter {
                m.sleep?.containsSleepTimestamp($0.ts) == true && $0.breathsPerMinute.isFinite && $0.breathsPerMinute > 0
            }
            if !points.isEmpty {
                VitalsTrace(samples: [], value: { _ in nil }, window: window,
                            low: 0, high: 60,
                            tint: NB.violet2,
                            measuredPoints: points.map { (ts: $0.ts, value: $0.breathsPerMinute) })
            } else {
                VitalsChartEmpty(line: L("NO SLEEP RESPIRATION"),
                                 sub: window.span > 0 ? L("THE BAND FILED NO RESPIRATION READINGS")
                                                     : L("WINDOW NOT ON RECORD"))
            }
            VitalsAxis(labels: window.labels, highlightsLast: false, tint: NB.violet2)
        }
        if let left = r.respirationLeft, let right = r.respirationRight {
            VitalsStatPair(left: left, right: right)
        }
    }

    // MARK: the eight charts

    @ViewBuilder
    private func chart(_ r: VitalsReadout) -> some View {
        switch metric {
        case .heart:
            trace(value: { $0.hr.map(Double.init) }, low: 40, high: 160, r: r,
                  extreme: { L("MAX %d", Int($0.rounded())) },
                  empty: (L("NO HEART TICKS IN 24H"), L("THE NEXT SYNC DRAWS THE LINE")),
                  has: ticks.contains { $0.hr != nil })

        case .stress:
            trace(value: { $0.stress.map(Double.init) }, low: 0, high: 100, r: r,
                  extreme: { L("PEAK %d", Int($0.rounded())) },
                  empty: (L("NO STRESS TICKS IN 24H"), L("THE NEXT SYNC DRAWS THE LINE")),
                  has: ticks.contains { $0.stress != nil })

        case .temp:
            // Drawn as a deviation, which is the only form this page uses. Without a
            // baseline there is nothing to deviate from and the card says so.
            if let baseline = r.baseline, ticks.contains(where: { $0.temp != nil }) {
                VitalsTrace(samples: ticks,
                            value: { $0.temp.map { $0 - baseline } },
                            window: window, low: -1.0, high: 1.0, tint: metric.tint,
                            referenceBand: r.referenceBand, referenceLabel: r.referenceLabel,
                            extremeLabel: { L("HIGH %+.1f", $0) })
            } else {
                VitalsChartEmpty(line: ticks.contains { $0.temp != nil } ? L("NO BASELINE YET") : L("NO SKIN TICKS IN 24H"),
                                 sub: ticks.contains { $0.temp != nil }
                                     ? L("A DEVIATION NEEDS THE DAYS BEHIND TODAY")
                                     : L("THE NEXT SYNC DRAWS THE LINE"))
            }

        case .sleep:
            EmptyView()

        case .hrv:
            if ticks.contains(where: { $0.hrv != nil }) {
                let nightly = data.history.suffix(15).dropLast().compactMap { $0.nightInputs?.hrv }
                VitalsScatter(samples: ticks, window: window,
                              envelope: nightly.count >= 5 ? nightly.min()!...nightly.max()! : nil,
                              baseline: m.nightInputs?.hrvBase, tint: metric.tint)
            } else {
                VitalsChartEmpty(line: L("NO RMSSD TICKS IN 24H"),
                                 sub: L("THE BAND MEASURES IT EVERY TEN MINUTES"))
            }

        case .response:
            if !mealIndex.percents.isEmpty {
                VitalsIndexScatter(points: mealIndex.percents, window: window, tint: metric.tint)
            } else {
                VitalsChartEmpty(line: L("NO RESPONSE POINTS IN 24H"),
                                 sub: mealIndex.empty == .needs5Days
                                    ? L("OWN MEDIAN TAKES FIVE DAYS")
                                    : L("THE NEXT SYNC FILLS THE POINTS"))
            }

        case .steps:
            histogram(value: { $0.steps.map(Double.init) },
                      peak: { L("PEAK %@/H", Fmt.kcal($0)) },
                      empty: (L("NO STEPS TODAY"), L("THE NEXT SYNC FILLS THE HOURS")))

        case .active:
            VitalsChartEmpty(line: L("HOURLY ENERGY NOT AVAILABLE"),
                             sub: L("DAILY ACTIVE ENERGY IS WEIGHT-AWARE AND SETTLED"))

        case .distance:
            let bins = VitalsMath.hourSum(ticks, range: window.range, value: \.dis)
            if VitalsMath.total(bins) != nil {
                VitalsClimb(bins: bins, window: window, tint: metric.tint,
                            endLabel: (m.distanceM.map(Double.init) ?? VitalsMath.total(bins))
                                .map { String(format: "%.2f KM", $0 / 1000) })
            } else {
                VitalsChartEmpty(line: L("NO DISTANCE TODAY"), sub: L("THE NEXT SYNC DRAWS THE CLIMB"))
            }
        }
    }

    @ViewBuilder
    private func trace(value: @escaping (VitalSample) -> Double?, low: Double, high: Double,
                       r: VitalsReadout, extreme: @escaping (Double) -> String,
                       empty: (String, String), has: Bool) -> some View {
        if has {
            VitalsTrace(samples: ticks, value: value, window: window,
                        low: low, high: high, tint: metric.tint,
                        referenceBand: r.referenceBand, referenceLabel: r.referenceLabel,
                        extremeLabel: extreme)
        } else {
            VitalsChartEmpty(line: empty.0, sub: empty.1)
        }
    }

    @ViewBuilder
    private func histogram(value: @escaping (VitalSample) -> Double?,
                           peak: @escaping (Double) -> String,
                           empty: (String, String)) -> some View {
        let bins = VitalsMath.hourSum(ticks, range: window.range, value: value)
        if VitalsMath.total(bins) != nil {
            VitalsHistogram(bins: bins, window: window, tint: metric.tint, peakLabel: peak)
        } else {
            VitalsChartEmpty(line: empty.0, sub: empty.1)
        }
    }

    // MARK: foot

    private var latestTickAt: Date? {
        switch metric {
        case .heart:
            ticks.last(where: { $0.hr != nil })?.ts
        case .sleep:
            m.sleep?.wakeAt
        case .hrv:
            ticks.last(where: { $0.hrv != nil })?.ts
        case .response:
            mealIndex.percents.last?.ts
        case .stress:
            ticks.last(where: { $0.stress != nil })?.ts
        case .temp:
            ticks.last(where: { $0.temp != nil })?.ts
        case .steps:
            ticks.last(where: { $0.steps != nil })?.ts
        case .distance:
            ticks.last(where: { $0.dis != nil })?.ts
        case .active:
            ticks.last(where: { $0.steps != nil || $0.dis != nil })?.ts
        }
    }

    /// The one line that says where the page's numbers came from. 04B rule 05 · the age of
    /// the last tick belongs on the page that prints it, not only on the strip.
    private var footer: some View {
        var line: String
        if metric.isNightly {
            line = m.sleep?.wakeAt.map { L("FROM THE NIGHT THAT ENDED %@", Fmt.clock($0)) }
                ?? L("FROM THE LAST NIGHT THE BAND FILED")
        } else if let at = latestTickAt {
            line = L("LAST TICK %@ · %@", Fmt.clock(at), VitalsMath.age(of: at, now: now))
            if [.heart, .stress, .temp, .response].contains(metric),
               let gap = VitalsMath.offWrist(ticks), gap.minutes >= 60 {
                line += L(" · %@ OFF WRIST", Fmt.duration(gap.minutes))
            }
        } else {
            line = L("NO TICKS YET · FIRST SYNC DRAWS THE LINE")
        }
        return Text(line)
            .font(NBFont.dot(500, 9.5)).tracking(0.12 * 9.5)
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(NB.white.opacity(0.38))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }
}

private enum VitalsClock {
    static var now: Date {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["NB_DEBUG_NOW"],
           let debugNow = ISO8601DateFormatter().date(from: raw) {
            return debugNow
        }
        #endif
        return Date()
    }
}
