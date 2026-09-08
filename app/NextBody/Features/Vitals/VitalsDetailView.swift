import SwiftUI

/// 04 · vitals 二级页 · the second level behind each vitals card on home page two.
/// Body Battery is its own page (`BodyBatteryDetailView`), not this board.
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

    /// ADR 0008 · sleep carries a window switcher. ADR 0012 / 0013 reopen the same
    /// three pills. `SegmentedPills` binds a String; `RollingPills` owns the grain.
    @State private var rangeRaw = RollingPills.day.rawValue
    private var range: RollingPills { .parse(rangeRaw) }
    private var detail: DetailWindow { DetailWindow(metric.detailSurface, range) }

    /// True only on the rolling windows of the five instruments this board opened. The day
    /// window is deliberately not "a window of one" — it is the original page, untouched.
    private var isMetricWindow: Bool { metric.hasMetricRange && range != .day }

    /// The window's samples are derived from every stored day's curve, and the board reads
    /// them twenty-odd times per body. Without a memo a month of minute ticks is merged and
    /// filtered twenty times per tap, which is the pause the pills used to have.
    /// The memo is a reference the view keeps across bodies; its contents are dropped the
    /// moment any input the derivation reads changes, so it can never show a stale window.
    @State private var memo = VitalsDetailMemo()

    /// A cheap fingerprint of everything the memoised values are computed from. Per-day
    /// counts and last timestamps stand in for the sample arrays themselves: a sync that
    /// replaces a day's curve changes one of those, and the memo empties.
    private var memoKey: VitalsDetailMemo.Key {
        VitalsDetailMemo.Key(
            metric: metric,
            ranges: [rangeRaw],
            history: data.history.map(VitalsDetailMemo.DayStamp.init),
            today: VitalsDetailMemo.DayStamp(m),
            mealPoints: data.mealResponsePoints.count,
            mealLast: data.mealResponsePoints.last?.ts,
            zerosToday: data.mealResponseZerosToday,
            minute: Int(now.timeIntervalSinceReferenceDate / 60))
    }

    private func memoised<T>(_ slot: ReferenceWritableKeyPath<VitalsDetailMemo, T?>,
                             _ compute: () -> T) -> T {
        memo.value(slot, for: memoKey, compute)
    }

    /// ⚠️ Read from `data.sleepScores`, never from `m.sleepScore`: a later `loadHome`
    /// replaces `store.today` wholesale, and the copy on that struct goes with it. The
    /// dictionary is the one that survives.
    private var todayScore: SleepScore? { data.sleepScores[m.day.key] }

    /// The header word follows the window, because the window is now the user's to choose.
    private var periodLabel: String {
        if metric.hasMetricRange { return range.metricPeriodLabel(for: metric) }
        guard metric.showsDetailPills else { return metric.periodLabel }
        let key = detail.periodKey
        return key.isEmpty ? metric.periodLabel : L(key)
    }

    private var heroSensor: String {
        if metric == .response { return range.responseHeroSensor }
        if metric.hasMetricRange { return range.metricHeroSensor(for: metric) }
        return metric.sensor
    }

    private var chartTitle: String {
        if metric == .response { return range.responseChartTitle }
        if metric.hasMetricRange { return range.metricChartTitle(for: metric) }
        return metric.chartTitle
    }

    private var m: DailyMetrics { data.today }
    private var now: Date { VitalsClock.now }

    private var window: VitalsWindow {
        VitalsWindowAssembly.window(metric: metric, range: range, day: m.day,
                                    now: now, sleep: m.sleep)
    }

    /// A multi-day window spans more than today's row, so today's row alone is insufficient.
    /// Merge history with the immediately synced local curve and then clip to the exact ruler.
    private var ticks: [VitalSample] {
        memoised(\.ticks) {
            VitalsWindowAssembly.ticks(metric: metric, window: window,
                                       history: data.history, today: m)
        }
    }

    private var displayMetrics: DailyMetrics {
        VitalsWindowAssembly.displayMetrics(metric: metric, range: range, today: m, ticks: ticks)
    }

    private var readout: VitalsReadout {
        if metric == .heart, range != .day {
            return VitalsReadout.heartWindow(daily: heartDaily { $0.hr.map(Double.init) },
                                             profile: data.profile, days: detail.days)
        }
        if isMetricWindow { return metricWindowReadout }
        return VitalsReadout.make(metric, m: displayMetrics, history: data.history,
                                  vitals: data.vitals, profile: data.profile,
                                  mealResponse: mealIndex,
                                  mealBoard: mealBoard)
    }

    /// One bucket a user day, in window order. Empty days stay empty arrays.
    private func heartDaily(_ value: (VitalSample) -> Double?) -> [[Double]] {
        let first = m.day.adding(days: -(detail.days - 1))
        return (0..<detail.days).map { offset in
            let day = first.adding(days: offset)
            return ticks.compactMap { sample in
                guard sample.ts >= day.start, sample.ts < day.end else { return nil }
                return value(sample)
            }
        }
    }

    private var heartOxygen: [OvernightOxygenPoint] {
        memoised(\.heartOxygen) { heartOxygenUncached }
    }

    private var heartOxygenUncached: [OvernightOxygenPoint] {
        // `history` can already hold today (the simulator seed does). Same timestamp
        // twice would draw two marks on one reading.
        let window = window
        return Dictionary(
            (data.history + [m])
                .flatMap { $0.sleep?.spo2 ?? [] }
                .filter { window.contains($0.ts) }
                .map { ($0.ts, $0) },
            uniquingKeysWith: { _, later in later }
        )
        .values
        .sorted { $0.ts < $1.ts }
    }

    private var heartSlotMinutes: Double {
        guard range != .day else { return detail.slotMinutes }
        return HeartWindowMath.slotSeconds(span: window.span, days: detail.days) / 60
    }

    // MARK: the five rolling windows · STRESS · TEMP · STEPS · DIST · CALS

    /// The window's user days, oldest first, today's row taken live rather than from
    /// `history` — a later `loadHome` replaces `store.today` wholesale and the copy in
    /// history goes stale behind it. A day with no row is an empty `DailyMetrics`, which
    /// yields nil totals rather than zeros.
    private var windowDays: [DailyMetrics] {
        memoised(\.windowDays) {
            let first = m.day.adding(days: -(detail.days - 1))
            let byDay = Dictionary(data.history.map { ($0.day, $0) }, uniquingKeysWith: { _, later in later })
            return (0..<detail.days).map { offset in
                let day = first.adding(days: offset)
                if day == m.day { return m }
                return byDay[day] ?? DailyMetrics(day: day)
            }
        }
    }

    private func metricDayTotal(_ day: DailyMetrics) -> Double? {
        switch metric {
        case .steps:    VitalsReadout.daySteps(day)
        case .distance: VitalsReadout.dayMetres(day)
        default:        VitalsReadout.dayTotalBurn(day)
        }
    }

    private var metricSlots: [MetricDayBars.Slot] {
        memoised(\.metricSlots) { MetricWindowMath.slots(days: windowDays, total: metricDayTotal) }
    }

    private func metricDaily(_ value: (VitalSample) -> Double?) -> [[Double]] {
        MetricWindowMath.dailyBuckets(ticks: ticks, endingOn: m.day,
                                      days: detail.days, value: value)
    }

    /// The window's median recorded day, drawn across the bars as this person's own habit.
    /// Under three days it is not a habit, it is the only day there is.
    private var metricMedianDay: Double? {
        let recorded = MetricWindowMath.recorded(metricSlots)
        return recorded.count >= 3 ? HeartWindowMath.median(recorded) : nil
    }

    private var metricWindowReadout: VitalsReadout {
        switch metric {
        case .stress:
            return .stressWindow(daily: metricDaily { $0.stress.map(Double.init) },
                                 ticks: ticks, days: detail.days)
        case .temp:
            return .tempWindow(daily: metricDaily { $0.temp }, days: detail.days,
                               range: SkinTempPresentation.nightRange(today: m, history: data.history,
                                                                     now: now).range)
        default:
            return .totalWindow(metric: metric, slots: metricSlots, days: windowDays,
                                ticks: ticks, count: detail.days)
        }
    }

    /// One user day an envelope on the trace windows, exactly as HEART's does.
    private var metricSlotMinutes: Double {
        guard isMetricWindow else { return VitalsTrace.defaultSlotMinutes }
        return HeartWindowMath.slotSeconds(span: window.span, days: detail.days) / 60
    }

    private var mealBoard: MealResponsePresentation.Board {
        memoised(\.mealBoard) { mealBoardUncached }
    }

    private var mealBoardUncached: MealResponsePresentation.Board {
        MealResponsePresentation.board(
            today: m,
            history: data.history,
            points: data.mealResponsePoints,
            zerosToday: data.mealResponseZerosToday,
            now: now,
            range: range)
    }

    private var mealIndex: MealResponseIndex.Result { mealBoard.index }

    private var activeModel: ActiveEnergyModel {
        memoised(\.activeModel) {
            ActiveEnergyModel.make(m: m, now: now, history: data.history)
        }
    }

    var body: some View {
        let r = readout
        return DetailScroll(glow: metric.tint, title: metric.title, trailing: {
            Text(periodLabel)
                .font(NBFont.dot(600, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.text3Prod)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }) {
            VStack(alignment: .leading, spacing: 14) {
                // The switcher sits above the hero because the hero changes with it: on a
                // multi-night window the value becomes a median and the feet become the
                // night count and the weakest group.
                if metric.showsDetailPills {
                    SegmentedPills(options: RollingPills.words, selection: $rangeRaw)
                }
                if metric == .sleep, let status = sleepScoreStatus {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(status).font(NBFont.dot(500, 10)).foregroundStyle(NB.text3Prod)
                            .fixedSize(horizontal: false, vertical: true)
                        if data.sleepScoreLoadState == .failed {
                            Button(L("RETRY")) {
                                Task { await Repository.shared.loadSleepScores(days: 30, endingAt: m.day, into: data) }
                            }
                            .font(NBFont.dot(600, 10)).foregroundStyle(metric.tint)
                        }
                    }
                }

                if metric == .sleep, range != .day {
                    multiNightHero
                } else if metric == .sleep, let score = todayScore {
                    // The card led with the score; the board must not lead with something else.
                    VitalsHero(sensor: heroSensor,
                               value: String(score.score), unit: r.value ?? L("OUT OF 100"),
                               tint: metric.tint, dial: VitalsReadout.sleepDial(score: score.score),
                               footLeft: r.footLeft, footRight: r.footRight)
                } else if metric == .active, !isMetricWindow {
                    ActiveEnergyHero(model: activeModel, sensor: heroSensor)
                } else {
                    VitalsHero(sensor: heroSensor, value: r.value, unit: r.unit,
                               tint: metric.tint, dial: r.dial,
                               footLeft: r.footLeft, footRight: r.footRight)
                }

                // The score explains itself on the screenful it appears on.
                if metric == .sleep, range == .day, let score = todayScore {
                    CardBlock(title: L("SCORE BREAKDOWN"), trailing: L("OUT OF 100")) {
                        SleepScoreBreakdown(score: score)
                    }
                    CardBlock(title: L("NIGHT DATA COVERAGE")) {
                        SleepScoreCoverage(score: score)
                    }
                }

                if metric == .sleep {
                    if range == .day { sleepBoard(r) } else { multiNightBoard }
                } else if metric == .heart {
                    HeartBoard(range: range, window: window, ticks: ticks,
                               oxygen: heartOxygen, readout: r,
                               slotMinutes: heartSlotMinutes, dial: r.dial)
                } else if metric == .active, !isMetricWindow {
                    ActiveEnergyBoard(model: activeModel)
                } else {
                    CardBlock(title: chartTitle, trailing: r.chartNote) {
                        chart(r)
                        if metric != .response || range == .day {
                            // The clock is inset by exactly the rail's gutter, or NOW lands
                            // under the ruler instead of under the window's last minute.
                            VitalsAxis(labels: axisLabels,
                                       highlightsLast: window.endsNow,
                                       tint: metric.tint)
                                .padding(.trailing, chartHasScaleRail ? VitalsScaleRail.gutter : 0)
                        } else if range == .week {
                            VitalsAxis(labels: weekAxisLabels, highlightsLast: false, tint: metric.tint)
                                .padding(.trailing, VitalsScaleRail.gutter)
                        }
                        chartLegend(r)
                    }
                }

                // Sleep owns its own order: the board below is organised by the score's
                // four groups, so the shared split card and stat pairs are placed inside it.
                if metric != .sleep,
                   metric != .heart || range == .day,
                   !(metric == .active && !isMetricWindow) {
                    CardBlock(title: r.splitTitle, trailing: r.splitTrailing) {
                        VitalsSplit(bands: r.bands)
                    }
                    VitalsStatPair(left: r.statLeft, right: r.statRight)
                    if let extraLeft = r.extraLeft, let extraRight = r.extraRight {
                        VitalsStatPair(left: extraLeft, right: extraRight)
                    }
                }
                if metric == .heart, range != .day {
                    VitalsStatPair(left: r.statLeft, right: r.statRight)
                }

                footer
            }
            .padding(.horizontal, NB.Layout.gutter)
            .padding(.bottom, 30)
            .task {
                #if DEBUG
                if let override = DetailWindow.debugRange(for: metric.detailSurface) {
                    rangeRaw = override.rawValue
                }
                #endif
            }
            .task(id: rangeRaw) {
                // ⚠️ 04B rule 09 still holds: this reads the server's `raw_samples`, not the
                // band. HEART and the five metric windows share one hydrate.
                guard !Band.allowsSeed else { return }
                await Repository.shared.hydrate(detail, endingAt: m.day, into: data)
            }
        } onBack: {
            router.backToRoot()
        }
        .onAppear { recordNightPresentation() }
        .onChange(of: m.sleep) { _, _ in recordNightPresentation() }
        .onChange(of: memoKey) { _, _ in recordNightPresentation() }
        .onChange(of: m.day) { _, _ in recordNightPresentation() }
        .task(id: m.day) {
            guard metric == .sleep, !Band.allowsSeed else { return }
            await Repository.shared.loadSleepScores(days: 30, endingAt: m.day, into: data)
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

    private var sleepScoreStatus: String? {
        let hasSaved = range == .day ? todayScore != nil : sleepWindow.recorded > 0
        switch data.sleepScoreLoadState {
        case .idle:
            if data.isOffline { return hasSaved ? L("OFFLINE · SHOWING SAVED SCORES") : L("OFFLINE · SCORES NOT LOADED") }
            return hasSaved ? L("SAVED SCORES · WAITING TO REFRESH") : L("SCORES NOT LOADED YET")
        case .loading:
            return hasSaved ? L("UPDATING SLEEP SCORES") : L("LOADING SLEEP SCORES")
        case .failed:
            return hasSaved ? L("REFRESH FAILED · SHOWING SAVED SCORES") : L("SLEEP SCORES COULD NOT BE LOADED")
        case .ready:
            if range == .day, todayScore == nil, m.sleep != nil { return L("SCORE NOT SETTLED YET") }
            return nil
        }
    }

    private var sleepScoreEmpty: (line: String, sub: String) {
        if let status = sleepScoreStatus { return (status, L("SYNC AGAIN TO REFRESH SCORES")) }
        return (L("NO SETTLED SCORES IN THIS WINDOW"), L("RECORDED NIGHTS APPEAR AFTER SCORING"))
    }

    /// Local evidence of the data handed to the visible sleep surface, not a render assertion.
    private func recordNightPresentation() {
        #if DEBUG
        guard metric == .sleep, NightDiagnostics.shared.isEnabled else { return }
        let samples = VitalsReadout.sleepHRVSamples(night: m.sleep, fallback: ticks)
        NightDiagnostics.shared.record("ui.sleep_input", fields: [
            "day": String(m.day.date.timeIntervalSince1970),
            "sleepPresent": String(m.sleep != nil),
            "archivedHRVMinutes": String(m.sleep?.hrv?.count ?? 0),
            "displayHRVPoints": String(samples.count),
            "respirationPoints": String(m.sleep?.respiration?.count ?? 0),
            "oxygenPoints": String(m.sleep?.spo2.count ?? 0),
            "windowStart": String(window.start.timeIntervalSince1970),
            "windowEnd": String(window.start.addingTimeInterval(window.span).timeIntervalSince1970)
        ])
        #endif
    }

    private var axisLabels: [String] {
        switch metric.timeline {
        // ⚠️ The hypnogram is laid out along the *line's own minutes*, not along a clock —
        // that is what drawing the band's staging as-is means. Printing the day's
        // `00 · 04 · 08 · 12 · 16 · 20` under it labelled a 7-hour chart as 24 hours.
        case .lastNight:
            sleepAxisLabels
        case .userDayToNow:
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

    /// ADR 0008 · the day board is laid out as the score's four groups, in the order the
    /// breakdown lists them, each heading followed by the charts that actually feed it. The
    /// earlier layout put the score at the top and a flat run of charts underneath with
    /// nothing tying them together, so "recovery 52" and the three traces that produced it
    /// were on the same page without ever being on the same subject.
    @ViewBuilder
    private func sleepBoard(_ r: VitalsReadout) -> some View {
        let score = todayScore

        // ---- DURATION · the night against the line it is scored on
        SleepSectionHeader(group: .duration, score: score?.duration, effectiveWeight: score?.effectiveWeight(of: .duration))
        CardBlock(title: L("TOTAL SLEEP"), trailing: r.footLeft) {
            if let night = m.sleep, night.totalMinutes > 0 {
                SleepDurationBar(minutes: night.totalMinutes)
            } else {
                VitalsChartEmpty(line: L("NO NIGHT ON RECORD"), sub: L("WEAR IT TONIGHT"))
            }
        }

        // ---- STRUCTURE · how the night was spent, and how broken it was
        SleepSectionHeader(group: .architecture, score: score?.architecture, effectiveWeight: score?.effectiveWeight(of: .architecture))
        CardBlock(title: metric.chartTitle, trailing: r.chartNote) {
            if let line = m.sleep?.line, !line.isEmpty {
                VitalsHypnogram(runs: line, tint: metric.tint,
                                windowMinutes: window.span / 60,
                                probeClock: window.clock(atFraction:))
            } else {
                VitalsChartEmpty(line: m.sleep == nil ? L("NO NIGHT ON RECORD") : L("TOTALS ONLY"),
                                 sub: m.sleep == nil ? L("WEAR IT TONIGHT")
                                                     : L("THE BAND FILED NO STAGE LINE"))
            }
            VitalsAxis(labels: axisLabels, highlightsLast: false, tint: metric.tint)
                .padding(.leading, VitalsHypnogram.labelGutter)
        }
        CardBlock(title: r.splitTitle, trailing: r.splitTrailing) {
            VitalsSplit(bands: r.bands)
        }
        if let wakes = r.extraRight {
            VitalsStatPair(left: wakes, right: .init(
                label: L("DEEP EPISODES"),
                value: m.sleep.map { String($0.line.filter { $0.stage == 0 }.count) },
                unit: nil, foot: L("RUNS OF DEEP SLEEP"), tint: nil))
        }

        // ---- RECOVERY · what the body did while it was down there
        SleepSectionHeader(group: .recovery, score: score?.recovery, effectiveWeight: score?.effectiveWeight(of: .recovery))
        let sleepHRV = VitalsReadout.sleepHRVSamples(night: m.sleep, fallback: ticks)
        let nightly = data.history.suffix(15).dropLast().compactMap { $0.nightInputs?.hrv }
        let habit = nightly.count >= 5 ? nightly.min()!...nightly.max()! : nil
        let hrvHigh = SleepScoreMath.hrvUpperBound(sleepHRV.compactMap(\.hrv) + (habit.map { [$0.upperBound] } ?? []))
        CardBlock(title: L("NIGHT HRV"), trailing: L("SCALE 0–%d MS", Int(hrvHigh))) {
            if !sleepHRV.isEmpty {
                VitalsTrace(samples: sleepHRV, value: { $0.hrv },
                            window: window, low: 0, high: hrvHigh, tint: NB.blue1,
                            referenceBand: habit,
                            unit: "MS")
                VitalsAxis(labels: window.labels, highlightsLast: false, tint: NB.blue1)
                    .padding(.trailing, VitalsScaleRail.gutter)
                VitalsChartLegend(
                    items: [
                        .init(text: L("EVERY %d MIN · MEASURED", Int(VitalsTrace.defaultSlotMinutes)),
                              tint: NB.blue1)
                    ] + (habit.map { _ in
                        [VitalsChartLegend.Item(text: L("14-NIGHT RANGE"), tint: NB.blue1, isArea: true)]
                    } ?? []),
                    trailing: sleepHRV.compactMap(\.hrv).max().map { L("NIGHT HIGH %d", Int($0.rounded())) },
                    trailingTint: NB.blue1)
            } else {
                let todaySamples = m.vitalsCurve.filter { $0.ts >= m.day.start && $0.ts < m.day.end }
                let hasOutsideReadings = VitalsReadout.hasHRVOutsideSleep(night: m.sleep, samples: todaySamples)
                VitalsChartEmpty(line: L("NO RMSSD IN THE WINDOW"),
                                 sub: hasOutsideReadings
                                     ? L("HRV RECEIVED OUTSIDE SLEEP; NO VALID SAMPLES DURING THIS SLEEP")
                                     : L("NO VALID HRV SAMPLES FOR THIS SLEEP"),
                                 subLineLimit: 2)
                VitalsAxis(labels: window.labels, highlightsLast: false, tint: NB.blue1)
            }
        }
        CardBlock(title: L("NIGHT SPO2"), trailing: L("FIXED 85–100 %")) {
            let points = (m.sleep?.spo2 ?? []).filter { m.sleep?.containsSleepTimestamp($0.ts) == true }
            if !points.isEmpty {
                VitalsTrace(samples: [], value: { _ in nil },
                            window: window, low: 85, high: 100, tint: NB.cyan1,
                            marksMaximum: false,
                            measuredPoints: points.map { (ts: $0.ts, value: Double($0.percent)) },
                            unit: "%")
                VitalsAxis(labels: window.labels, highlightsLast: false, tint: NB.cyan1)
                    .padding(.trailing, VitalsScaleRail.gutter)
                VitalsChartLegend(
                    items: [
                        .init(text: L("EVERY %d MIN · MEASURED", Int(VitalsTrace.defaultSlotMinutes)),
                              tint: NB.cyan1)
                    ],
                    trailing: points.map(\.percent).min().map { L("MIN %d", $0) },
                    trailingTint: NB.cyan1)
            } else {
                VitalsChartEmpty(line: L("NO OVERNIGHT OXYGEN"),
                                 sub: L("AUTO NIGHT MEASUREMENT WAS OFF OR EMPTY"))
                VitalsAxis(labels: window.labels, highlightsLast: false, tint: NB.cyan1)
            }
        }
        CardBlock(title: L("SLEEP RESPIRATION"), trailing: L("FIXED 0–60 /MIN")) {
            let points = (m.sleep?.respiration ?? []).filter {
                m.sleep?.containsSleepTimestamp($0.ts) == true && $0.breathsPerMinute.isFinite && $0.breathsPerMinute > 0
            }
            if !points.isEmpty {
                VitalsTrace(samples: [], value: { _ in nil }, window: window,
                            low: 0, high: 60,
                            tint: NB.violet2,
                            measuredPoints: points.map { (ts: $0.ts, value: $0.breathsPerMinute) },
                            unit: "/MIN")
                VitalsAxis(labels: window.labels, highlightsLast: false, tint: NB.violet2)
                    .padding(.trailing, VitalsScaleRail.gutter)
                VitalsChartLegend(
                    items: [
                        .init(text: L("EVERY %d MIN · MEASURED", Int(VitalsTrace.defaultSlotMinutes)),
                              tint: NB.violet2)
                    ],
                    trailing: points.map(\.breathsPerMinute).max().map {
                        L("NIGHT HIGH %d", Int($0.rounded()))
                    },
                    trailingTint: NB.violet2)
            } else {
                VitalsChartEmpty(line: L("NO SLEEP RESPIRATION"),
                                 sub: window.span > 0 ? L("THE BAND FILED NO RESPIRATION READINGS")
                                                     : L("WINDOW NOT ON RECORD"))
                VitalsAxis(labels: window.labels, highlightsLast: false, tint: NB.violet2)
            }
        }
        if let oxygenMin = r.extraLeft, let respiration = r.respirationLeft {
            VitalsStatPair(left: oxygenMin, right: respiration)
        }

        // ---- REGULARITY · only definable against this person's own habit
        SleepSectionHeader(group: .regularity, score: score?.regularity, effectiveWeight: score?.effectiveWeight(of: .regularity))
        CardBlock(title: L("BEDTIME VS YOUR HABIT"), trailing: bedtimeTrailing) {
            if let baseline = score?.inputs["bed_median"], let bedtime = score?.inputs["bed_offset"] {
                SleepBedtimeBox(baseline: baseline, tonight: bedtime)
            } else {
                VitalsChartEmpty(line: score?.inputs["bed_offset"] == nil ? L("NO BEDTIME RECORDED") : L("NO BASELINE YET"),
                                 sub: L("REGULARITY NEEDS ENOUGH PREVIOUS RECORDED BEDTIMES"))
            }
        }
    }

    private var bedtimeTrailing: String {
        guard let median = todayScore?.inputs["bed_median"] else { return Fmt.dash }
        return L("USUALLY %@", SleepScoreMath.bedClock(offset: median))
    }

    // MARK: the sleep window

    /// The last N wake-days ending today, each with whatever score settled for it. Built
    /// from `data.sleepScores` rather than `history`, which carries sleep for only the
    /// handful of days the band last synced.
    private var sleepSlots: [SleepNightSlot] {
        let today = m.day
        return (0..<detail.days).reversed().map { offset in
            let day = today.adding(days: -offset)
            return SleepNightSlot(day: day, score: data.sleepScores[day.key])
        }
    }

    private var sleepWindow: SleepWindowSummary { SleepWindowSummary(slots: sleepSlots) }

    /// A median score, how many nights it was taken over, and which group is dragging.
    /// The night count is not decoration: three nights not worn pulls a median down, and
    /// without it that reads as three bad nights.
    private var multiNightHero: some View {
        let summary = sleepWindow
        return VitalsHero(
            sensor: metric.sensor,
            value: summary.score.map(String.init),
            unit: L("MEDIAN"),
            tint: metric.tint,
            dial: summary.score.map(VitalsReadout.sleepDial(score:)),
            footLeft: L("%d OF %d NIGHTS", summary.recorded, summary.slots.count),
            footRight: summary.weakest.map { L("%@ LOWEST", $0.title) })
    }

    @ViewBuilder
    private var multiNightBoard: some View {
        let summary = sleepWindow
        CardBlock(title: L("SCORE BY NIGHT"),
                  trailing: L("%d NIGHTS · ROLLING", summary.slots.count)) {
            if summary.recorded > 0 {
                SleepScoreBars(slots: summary.slots)
                SleepScoreBars.legend
            } else {
                VitalsChartEmpty(line: sleepScoreEmpty.line, sub: sleepScoreEmpty.sub)
            }
        }
        if summary.recorded > 0 {
            CardBlock(title: L("SCORE BREAKDOWN"), trailing: L("GROUP MEDIANS")) {
                SleepWindowBreakdown(summary: summary)
            }
        }

        CardBlock(title: L("STAGE PROPORTIONS"),
                  trailing: summary.durationMinutes.map { L("MEDIAN %@", Fmt.duration($0)) }
                      ?? Fmt.dash) {
            let bands = summary.bands
            if bands.isEmpty {
                VitalsChartEmpty(line: L("NO STAGES ON RECORD"), sub: L("TOTALS ONLY"))
            } else {
                VitalsSplit(bands: bands)
            }
        }

        VitalsStatPair(
            left: .init(label: L("MEDIAN BEDTIME"), value: summary.bedClock, unit: nil,
                        foot: L("ACROSS %d NIGHTS", summary.recorded), tint: metric.tint),
            right: .init(label: L("MEDIAN WAKES"),
                         value: summary.wakes.map { String(Int($0.rounded())) }, unit: nil,
                         foot: L("PER NIGHT"), tint: nil))
    }

    private var chartHasScaleRail: Bool {
        if metric == .response { return range != .month }
        // Every rolling window draws its own rail — including ACTIVE, whose day page has
        // no chart at all and therefore no rail to inherit.
        if isMetricWindow { return true }
        return metric.chartHasScaleRail
    }

    private var weekAxisLabels: [String] {
        mealBoard.window.slots.map { Fmt.weekday($0.start) }
    }

    @ViewBuilder
    private func responseChart(_ r: VitalsReadout) -> some View {
        switch range {
        case .day:
            if !mealIndex.trendPoints.isEmpty, let axis = r.traceRange {
                let zones: VitalsDial.Model? = mealIndex.ownMedian.flatMap { median in
                    VitalsDialMath.ratioCuts(base: median).map {
                        VitalsReadout.dial(
                            scale: $0.scale, cuts: $0.cuts, value: mealIndex.latestPoint,
                            names: [L("BELOW"), L("NEAR"), L("ABOVE")],
                            tints: [NB.ember1, NB.compareAmber, NB.optimal2])
                    }
                }
                VitalsTrace(
                    samples: [],
                    value: { _ in nil },
                    window: window,
                    low: axis.lowerBound,
                    high: axis.upperBound,
                    tint: metric.tint,
                    zones: zones,
                    referenceBand: r.referenceBand,
                    measuredPoints: mealIndex.trendPoints.map { (ts: $0.ts, value: $0.optical) },
                    valueFormat: { MealResponseIndex.pointValue($0) })
            } else {
                VitalsChartEmpty(line: L("NO RESPONSE POINTS IN 24H"),
                                 sub: L("THE NEXT SYNC FILLS THE POINTS"))
            }
        case .week:
            if mealBoard.window.recordedDays > 0 {
                ResponseDayBars(slots: mealBoard.window.slots,
                                ownMedian: mealIndex.ownMedian,
                                tint: metric.tint)
            } else {
                VitalsChartEmpty(line: L("NO RESPONSE POINTS IN THIS WINDOW"),
                                 sub: L("THE NEXT SYNC FILLS THE POINTS"))
            }
        case .month:
            if mealBoard.window.recordedDays > 0 {
                ResponseDayHeat(slots: mealBoard.window.slots,
                                ownMedian: mealIndex.ownMedian,
                                tint: metric.tint)
            } else {
                VitalsChartEmpty(line: L("NO RESPONSE POINTS IN THIS WINDOW"),
                                 sub: L("THE NEXT SYNC FILLS THE POINTS"))
            }
        }
    }

    // MARK: the eight charts

    @ViewBuilder
    private func chart(_ r: VitalsReadout) -> some View {
        if isMetricWindow {
            metricWindowChart(r)
        } else {
            dayChart(r)
        }
    }

    /// The rolling window for the five. Trace instruments keep their trace and change only
    /// the grain — one envelope a user day rather than one every half hour. Accumulated
    /// instruments become one bar a day, because a cumulative climb across thirty days is
    /// a monotone ramp that says nothing about any day in it.
    @ViewBuilder
    private func metricWindowChart(_ r: VitalsReadout) -> some View {
        switch metric {
        case .stress:
            trace(value: { $0.stress.map(Double.init) }, low: 0, high: 100, r: r,
                  empty: (L("NO STRESS TICKS IN THIS WINDOW"), L("THE NEXT SYNC DRAWS THE LINE")),
                  has: ticks.contains { $0.stress != nil },
                  slotMinutes: metricSlotMinutes)

        case .temp:
            if let axis = r.traceRange, ticks.contains(where: { $0.temp != nil }) {
                VitalsTrace(samples: ticks, value: { $0.temp },
                            window: window, low: axis.lowerBound, high: axis.upperBound,
                            tint: metric.tint,
                            zones: r.dial,
                            slotMinutes: metricSlotMinutes,
                            valueFormat: { String(format: "%.1f", $0) },
                            unit: "°C")
            } else {
                VitalsChartEmpty(line: L("NO SKIN TICKS IN THIS WINDOW"),
                                 sub: L("THE NEXT SYNC DRAWS THE LINE"))
            }

        default:
            let slots = metricSlots
            if MetricWindowMath.sum(slots) != nil {
                MetricDayBars(slots: slots, tint: metric.tint, median: metricMedianDay,
                              format: VitalsReadout.windowFormat(metric))
            } else {
                VitalsChartEmpty(line: L("NO DAYS ON RECORD IN THIS WINDOW"),
                                 sub: L("THE NEXT SYNC FILLS THE DAYS"))
            }
        }
    }

    @ViewBuilder
    private func dayChart(_ r: VitalsReadout) -> some View {
        switch metric {
        case .heart:
            trace(value: { $0.hr.map(Double.init) }, low: 40, high: 160, r: r,
                  empty: (L("NO HEART TICKS IN 24H"), L("THE NEXT SYNC DRAWS THE LINE")),
                  has: ticks.contains { $0.hr != nil },
                  unit: "BPM")

        case .stress:
            trace(value: { $0.stress.map(Double.init) }, low: 0, high: 100, r: r,
                  empty: (L("NO STRESS TICKS IN 24H"), L("THE NEXT SYNC DRAWS THE LINE")),
                  has: ticks.contains { $0.stress != nil })

        case .temp:
            // Drawn in °C against this wrist's own ruler, with the night range banded across
            // last night alone. A first week without a range still draws every measured tick.
            if let axis = r.traceRange, ticks.contains(where: { $0.temp != nil }) {
                VitalsTrace(samples: ticks,
                            value: { $0.temp },
                            window: window, low: axis.lowerBound, high: axis.upperBound,
                            tint: metric.tint,
                            zones: r.dial,
                            referenceBand: r.referenceBand,
                            referenceSpan: r.referenceSpan,
                            valueFormat: { String(format: "%.1f", $0) },
                            unit: "°C")
            } else {
                VitalsChartEmpty(line: L("NO SKIN TICKS IN 24H"),
                                 sub: L("THE NEXT SYNC DRAWS THE LINE"))
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
            responseChart(r)

        case .steps:
            histogram(value: { $0.steps.map(Double.init) },
                      empty: (L("NO STEPS TODAY"), L("THE NEXT SYNC FILLS THE HOURS")))

        case .active:
            VitalsChartEmpty(line: L("HOURLY ENERGY NOT AVAILABLE"),
                             sub: L("DAILY ACTIVE ENERGY IS WEIGHT-AWARE AND SETTLED"))

        case .distance:
            let bins = VitalsMath.hourSum(ticks, range: window.range, value: \.dis)
            if VitalsMath.total(bins) != nil {
                VitalsClimb(bins: bins, window: window, tint: metric.tint)
            } else {
                VitalsChartEmpty(line: L("NO DISTANCE TODAY"), sub: L("THE NEXT SYNC DRAWS THE CLIMB"))
            }
        }
    }

    @ViewBuilder
    private func trace(value: @escaping (VitalSample) -> Double?, low: Double, high: Double,
                       r: VitalsReadout, empty: (String, String), has: Bool,
                       valueFormat: @escaping (Double) -> String = { String(format: "%.0f", $0) },
                       unit: String = "",
                       slotMinutes: Double = VitalsTrace.defaultSlotMinutes) -> some View {
        if has {
            VitalsTrace(samples: ticks, value: value, window: window,
                        low: low, high: high, tint: metric.tint,
                        zones: r.dial,
                        referenceBand: r.referenceBand,
                        referenceSpan: r.referenceSpan,
                        slotMinutes: slotMinutes,
                        valueFormat: valueFormat, unit: unit)
        } else {
            VitalsChartEmpty(line: empty.0, sub: empty.1)
        }
    }

    /// What the marks mean, said under the clock. Everything in this row used to be a plate
    /// printed on top of the field: the band's name, the extreme, and the envelope's width.
    @ViewBuilder
    private func chartLegend(_ r: VitalsReadout) -> some View {
        if isMetricWindow {
            metricWindowLegend(r)
        } else {
            dayChartLegend(r)
        }
    }

    @ViewBuilder
    private func metricWindowLegend(_ r: VitalsReadout) -> some View {
        switch metric {
        case .stress, .temp:
            if let extreme = traceExtreme {
                VitalsChartLegend(
                    items: [.init(text: L("EVERY DAY · MEASURED"), tint: metric.tint,
                                  stops: r.dial?.legendStops)]
                        + (r.referenceLabel.map {
                            [VitalsChartLegend.Item(text: $0, tint: metric.tint, isArea: true)]
                        } ?? []),
                    trailing: traceExtremeLabel(extreme),
                    trailingTint: metric.tint)
            }

        default:
            let slots = metricSlots
            if MetricWindowMath.sum(slots) != nil {
                MetricDayBars.legend(tint: metric.tint, median: metricMedianDay,
                                     format: VitalsReadout.windowFormat(metric))
            }
        }
    }

    @ViewBuilder
    private func dayChartLegend(_ r: VitalsReadout) -> some View {
        switch metric {
        case .heart, .stress, .temp:
            let hasTicks = traceExtreme != nil
            if hasTicks {
                VitalsChartLegend(
                    items: [
                        .init(text: L("EVERY %d MIN · MEASURED", Int(VitalsTrace.defaultSlotMinutes)),
                              tint: metric.tint, stops: r.dial?.legendStops)
                    ] + (r.referenceLabel.map { [VitalsChartLegend.Item(text: $0, tint: metric.tint, isArea: true)] } ?? []),
                    trailing: traceExtreme.map(traceExtremeLabel),
                    trailingTint: metric.tint)
            }

        case .steps:
            let bins = VitalsMath.hourSum(ticks, range: window.range, value: { $0.steps.map(Double.init) })
            if VitalsMath.total(bins) != nil {
                VitalsChartLegend(
                    items: [.init(text: L("PER HOUR"), tint: metric.tint)],
                    trailing: bins.compactMap { $0 }.max().map { L("PEAK %@/H", Fmt.kcal($0)) },
                    trailingTint: metric.tint)
            }

        case .distance:
            let bins = VitalsMath.hourSum(ticks, range: window.range, value: \.dis)
            // ⚠️ The climb's own end, not `m.distanceM`. The old chart drew the curve from
            // the hourly bins but labelled its last point with the day total, so a day whose
            // bins do not add up to the total printed a number the curve did not reach.
            // The rail names what is drawn; this names the same thing.
            if let climbed = VitalsMath.total(bins) {
                VitalsChartLegend(
                    items: [.init(text: L("CUMULATIVE"), tint: metric.tint)],
                    trailing: L("%@ NOW", VitalsReadout.distanceLabel(climbed)),
                    trailingTint: metric.tint)
            }

        case .response:
            switch range {
            case .day:
                if !mealIndex.trendPoints.isEmpty {
                    VitalsChartLegend(
                        items: [
                            .init(text: L("EVERY %d MIN · MEASURED", Int(VitalsTrace.defaultSlotMinutes)),
                                  tint: metric.tint)
                        ] + (r.referenceLabel.map {
                            [VitalsChartLegend.Item(text: $0, tint: metric.tint, isArea: true)]
                        } ?? []),
                        trailing: mealIndex.trendPoints.map(\.optical).max()
                            .map { L("HIGH %@", MealResponseIndex.pointValue($0)) },
                        trailingTint: metric.tint)
                }
            case .week:
                if mealBoard.window.recordedDays > 0 { ResponseDayBars.legend }
            case .month:
                if mealBoard.window.recordedDays > 0 { ResponseDayHeat.legend }
            }

        case .sleep, .hrv, .active:
            EmptyView()
        }
    }

    /// The window's extreme for the three metrics drawn as envelopes. The field picks its
    /// slot out in full-strength tint; this is the number that names it. `ticks` is already
    /// clipped to the window, so the max here and the marked slot are the same fact.
    /// What makes a day count as worn on a trace window — the instrument's own reading,
    /// never "any tick at all". A day of heart ticks with no thermometer reading is not a
    /// day of skin temperature.
    private func windowTickValue(_ sample: VitalSample) -> Double? {
        switch metric {
        case .stress: sample.stress.map(Double.init)
        case .temp:   sample.temp
        default:      nil
        }
    }

    private var traceExtreme: Double? {
        switch metric {
        case .heart:  ticks.compactMap { $0.hr.map(Double.init) }.max()
        case .stress: ticks.compactMap { $0.stress.map(Double.init) }.max()
        case .temp:   ticks.compactMap(\.temp).max()
        default:      nil
        }
    }

    private func traceExtremeLabel(_ value: Double) -> String {
        switch metric {
        case .heart:  L("MAX %d", Int(value.rounded()))
        case .stress: L("PEAK %d", Int(value.rounded()))
        case .temp:   L("HIGH %.1f", value)
        default:      Fmt.dash
        }
    }

    @ViewBuilder
    private func histogram(value: @escaping (VitalSample) -> Double?,
                           empty: (String, String)) -> some View {
        let bins = VitalsMath.hourSum(ticks, range: window.range, value: value)
        if VitalsMath.total(bins) != nil {
            VitalsHistogram(bins: bins, window: window, tint: metric.tint)
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
            mealIndex.trendPoints.last?.ts
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
        if metric == .sleep, range != .day {
            let summary = sleepWindow
            line = summary.recorded == 0
                ? sleepScoreEmpty.line
                : L("%d NIGHTS ENDING %@", summary.recorded, m.day.key)
        } else if metric == .heart, range != .day {
            let worn = HeartWindowMath.wornDays(heartDaily { $0.hr.map(Double.init) })
            line = worn == 0
                ? L("NO HEART TICKS IN THIS WINDOW")
                : L("%d DAYS ENDING %@", worn, m.day.key)
        } else if isMetricWindow {
            let worn = metric.windowIsAccumulated
                ? MetricWindowMath.recorded(metricSlots).count
                : HeartWindowMath.wornDays(metricDaily(windowTickValue))
            line = worn == 0
                ? L("NO RECORD IN THIS WINDOW")
                : L("%d DAYS ENDING %@", worn, m.day.key)
        } else if metric == .response, range != .day {
            let recorded = mealBoard.window.recordedDays
            line = recorded == 0
                ? L("NO RESPONSE POINTS IN THIS WINDOW")
                : L("%d DAYS ENDING %@", recorded, m.day.key)
        } else if metric.isNightly {
            line = m.sleep?.wakeAt.map { L("FROM THE NIGHT THAT ENDED %@", Fmt.clock($0)) }
                ?? L("FROM THE LAST NIGHT THE BAND FILED")
            if let at = todayScore?.computedAt {
                line += L(" · SCORE UPDATED %@", Fmt.clock(at))
            }
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

/// The per-body cache behind `VitalsDetailView`'s derived arrays. A class so the view
/// struct can fill it during `body` without a state write; a key so nothing survives an
/// input change. Every slot is filled at most once per key.
final class VitalsDetailMemo {
    struct DayStamp: Hashable {
        let day: UserDay
        let curve: Int
        let last: Date?
        let oxygen: Int
        let sleepWake: Date?
        init(_ d: DailyMetrics) {
            day = d.day
            curve = d.vitalsCurve.count
            last = d.vitalsCurve.last?.ts
            oxygen = d.sleep?.spo2.count ?? 0
            sleepWake = d.sleep?.wakeAt
        }
    }

    struct Key: Hashable {
        let metric: VitalsMetric
        let ranges: [String]
        let history: [DayStamp]
        let today: DayStamp
        let mealPoints: Int
        let mealLast: Date?
        let zerosToday: Bool
        let minute: Int
    }

    private var key: Key?
    var ticks: [VitalSample]?
    var heartOxygen: [OvernightOxygenPoint]?
    var windowDays: [DailyMetrics]?
    var metricSlots: [MetricDayBars.Slot]?
    var mealBoard: MealResponsePresentation.Board?
    var activeModel: ActiveEnergyModel?

    func value<T>(_ slot: ReferenceWritableKeyPath<VitalsDetailMemo, T?>,
                  for current: Key, _ compute: () -> T) -> T {
        if key != current {
            key = current
            ticks = nil; heartOxygen = nil; windowDays = nil; metricSlots = nil
            mealBoard = nil; activeModel = nil
        }
        if let cached = self[keyPath: slot] { return cached }
        let fresh = compute()
        self[keyPath: slot] = fresh
        return fresh
    }
}
