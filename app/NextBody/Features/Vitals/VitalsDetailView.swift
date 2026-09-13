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

    /// #28 · the sleep page's own entry to correcting a night's start and end.
    @State private var correctingNight = false

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
            sleepScores: data.sleepScores.count,
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
                // Each night vouches for its own points. `spo2` can hold a reading from a
                // gap between two sleep intervals, and the sleep page drops those; the
                // companion under the pulse must print the same night as the sleep board.
                .flatMap { day -> [OvernightOxygenPoint] in
                    guard let night = day.sleep else { return [] }
                    return night.spo2.filter { night.containsSleepTimestamp($0.ts) }
                }
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
        memoised(\.windowDays) { rows(endingOn: m.day, count: detail.days) }
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

    // MARK: the trend hero · one mark a user day on every rolling window

    /// Every rolling window but RESPONSE leads with the trend hero. RESPONSE keeps its own
    /// week bars and month heat (ADR 0012), which already are its shape.
    private var showsTrendHero: Bool {
        range != .day && metric.showsDetailPills && metric != .response
    }

    /// The user days before the window, same length, oldest first — what "vs prior 7 days"
    /// is measured against. A day with no row is an empty `DailyMetrics`, never a zero day.
    private var priorDays: [DailyMetrics] {
        memoised(\.priorDays) {
            rows(endingOn: m.day.adding(days: -detail.days), count: detail.days)
        }
    }

    private func rows(endingOn last: UserDay, count: Int) -> [DailyMetrics] {
        let first = last.adding(days: -(count - 1))
        let byDay = Dictionary(data.history.map { ($0.day, $0) }, uniquingKeysWith: { _, later in later })
        return (0..<count).map { offset in
            let day = first.adding(days: offset)
            if day == m.day { return m }
            return byDay[day] ?? DailyMetrics(day: day)
        }
    }

    /// Every tick the two windows can see, merged once and filed by the user day its clock
    /// falls in — the same way the worn-day tile under the page buckets them. A night's
    /// ticks begin on the evening before the morning that owns the night, and a row can
    /// carry a neighbour's evening; filing by clock rather than by row keeps the hero and
    /// the tile counting the same days.
    private var trendTicksByDay: [UserDay: [VitalSample]] {
        memoised(\.trendTicksByDay) {
            let eve = rows(endingOn: m.day.adding(days: -(2 * detail.days)), count: 1)
            let curve = VitalSample.merging((eve + priorDays + windowDays).flatMap(\.vitalsCurve), with: [])
            return Dictionary(grouping: curve, by: { UserDay.containing($0.ts) })
        }
    }

    /// The value the hero marks for one user day.
    private func trendValue(_ day: DailyMetrics, ticks: [UserDay: [VitalSample]]) -> Double? {
        switch metric {
        case .heart:    day.nightInputs?.rhr
        case .stress:   MetricTrendMath.mean((ticks[day.day] ?? []).compactMap { $0.stress.map(Double.init) })
        case .temp:     nightSkinMedian(day, ticks: (ticks[day.day.adding(days: -1)] ?? []) + (ticks[day.day] ?? []))
        case .steps:    VitalsReadout.daySteps(day)
        case .distance: VitalsReadout.dayMetres(day)
        case .active:   VitalsReadout.dayTotalBurn(day)
        case .sleep:    data.sleepScores[day.day.key].map { Double($0.score) }
        case .hrv, .response: nil
        }
    }

    /// ADR 0009 · skin temperature is a night reading. The median of the ticks the band
    /// took inside the recorded sleep — not an afternoon with the arm out of a sleeve.
    private func nightSkinMedian(_ day: DailyMetrics, ticks: [VitalSample]) -> Double? {
        guard let night = day.sleep, let start = night.sleepStart, let wake = night.wakeAt,
              wake > start else { return nil }
        let temps = ticks.compactMap { sample -> Double? in
            guard sample.ts >= start, sample.ts < wake, night.containsSleepTimestamp(sample.ts)
            else { return nil }
            return sample.temp
        }
        // Six ticks is half an hour: fewer is a wrist that came off, not a night.
        return temps.count >= 6 ? MetricTrendMath.median(temps) : nil
    }

    private var windowTrendValues: [Double?] {
        memoised(\.windowTrendValues) {
            let ticks = trendTicksByDay
            return windowDays.map { trendValue($0, ticks: ticks) }
        }
    }

    private var priorTrendValues: [Double?] {
        memoised(\.priorTrendValues) {
            let ticks = trendTicksByDay
            return priorDays.map { trendValue($0, ticks: ticks) }
        }
    }

    /// How each instrument's window is drawn: the mark, the ruler, the rule or band across
    /// it, and the words. The day page's readouts are untouched — a window number is a
    /// different claim from a day number and the two do not share a formula.
    private struct TrendSpec {
        var style: MetricTrendHero.Style
        var scale: ClosedRange<Double>
        var zones: VitalsDial.Model? = nil
        var rule: MetricTrendHero.Rule? = nil
        var band: MetricTrendHero.Band? = nil
        var format: (Double) -> String
        var unit: String
        var seriesLabel: String
        var nightly: Bool
        var empty: (line: String, sub: String)
    }

    private func trendSpec(values: [Double?]) -> TrendSpec {
        let habit = MetricTrendMath.habit(values)
        let whole: (Double) -> String = { String(Int($0.rounded())) }
        switch metric {
        case .heart:
            // The resting pulse, one a night, against the fourteen-night baseline the
            // morning reading is already judged by. Not the day's mean: a walk to the
            // shops moves that, and the shape it makes is the shape of the errands.
            let base = m.nightInputs?.rhrBase
            return TrendSpec(
                style: .line,
                scale: MetricTrendMath.fittedScale(values, step: 5, pad: 4, minimumSpan: 20,
                                                   fallback: 40...80, including: base.map { $0...$0 }),
                rule: base.map { .init(value: $0, label: L("BASELINE %@", whole($0))) }
                    ?? habit.map { .init(value: $0, label: L("MEDIAN %@", whole($0))) },
                format: whole, unit: "BPM",
                seriesLabel: L("RESTING · PER NIGHT"), nightly: true,
                empty: (L("NO RESTING PULSE IN THIS WINDOW"), L("A RECORDED NIGHT SETS THE NEXT POINT")))

        case .stress:
            let cuts = VitalsDialMath.stressCuts()
            return TrendSpec(
                style: .bars, scale: cuts.scale,
                zones: VitalsReadout.dial(scale: cuts.scale, cuts: cuts.cuts, value: nil,
                                          names: [L("REST"), L("STEADY"), L("ELEVATED"), L("HIGH")],
                                          tints: [NB.optimal2, NB.lime1, NB.ember1, NB.alert2]),
                rule: habit.map { .init(value: $0, label: L("MEDIAN %@", whole($0))) },
                format: whole, unit: "/ 100",
                seriesLabel: L("AVERAGE · PER DAY"), nightly: false,
                empty: (L("NO STRESS TICKS IN THIS WINDOW"), L("THE NEXT SYNC DRAWS THE LINE")))

        case .temp:
            let tenth: (Double) -> String = { String(format: "%.1f", $0) }
            let range = SkinTempPresentation.nightRange(today: m, history: data.history, now: now).range
            let own = range.map { $0.lower...$0.upper }
            return TrendSpec(
                style: .line,
                scale: MetricTrendMath.fittedScale(values, step: 0.5, pad: 0.5, minimumSpan: 2,
                                                   fallback: 30...38, including: own),
                rule: own == nil ? habit.map { .init(value: $0, label: L("MEDIAN %@ °C", tenth($0))) } : nil,
                band: range.map { .init(range: $0.lower...$0.upper,
                                        label: L("YOUR RANGE %.1f–%.1f °C", $0.lower, $0.upper)) },
                format: tenth, unit: "°C",
                seriesLabel: L("NIGHT MEDIAN · PER NIGHT"), nightly: true,
                empty: (L("NO NIGHT SKIN TICKS IN THIS WINDOW"), L("A RECORDED NIGHT SETS THE NEXT POINT")))

        case .sleep:
            return TrendSpec(
                style: .bars, scale: VitalsDialMath.sleepCuts().scale,
                zones: VitalsReadout.sleepDial(score: 0),
                rule: habit.map { .init(value: $0, label: L("MEDIAN %@", whole($0))) },
                format: whole, unit: "/ 100",
                seriesLabel: L("SCORE · PER NIGHT"), nightly: true,
                empty: sleepScoreEmpty)

        case .steps, .distance, .active, .hrv, .response:
            let format = VitalsReadout.windowFormat(metric)
            let peak = MetricTrendMath.recorded(values).max() ?? 0
            return TrendSpec(
                style: .bars, scale: 0...max(peak, 1),
                rule: habit.map { .init(value: $0, label: L("MEDIAN %@", format($0))) },
                format: format,
                // Distance prints its own unit — `6.4 KM` — so none is appended.
                unit: metric == .distance ? "" : (VitalsReadout.windowUnit(metric) ?? ""),
                seriesLabel: L("TOTAL · PER DAY"), nightly: false,
                empty: (L("NO DAYS ON RECORD IN THIS WINDOW"), L("THE NEXT SYNC FILLS THE DAYS")))
        }
    }

    private var trendHero: some View {
        let values = windowTrendValues
        let spec = trendSpec(values: values)
        let days = windowDays
        let recorded = MetricTrendMath.recorded(values).count
        let headline = MetricTrendMath.headline(values)
        let delta = MetricTrendMath.delta(current: values, prior: priorTrendValues)
        let rolls: [MetricTrendHero.Roll] = range == .month
            ? MetricTrendMath.weekRolls(values).enumerated().map { i, roll in
                .init(id: i, label: L("%dD", roll.count), value: roll.average)
            }
            : []
        return MetricTrendHero(
            caption: L("%@ · %@", metric.sensor, L(detail.periodKey)),
            points: zip(days, values).map { .init(start: $0.day.start, value: $1) },
            style: spec.style, scale: spec.scale, tint: metric.tint,
            zones: spec.zones, rule: spec.rule, band: spec.band,
            format: spec.format, unit: spec.unit,
            seriesLabel: spec.seriesLabel,
            summary: .init(
                headline: L("MEDIAN %@", headline.map(spec.format) ?? Fmt.dash),
                unit: spec.unit.isEmpty ? nil : spec.unit,
                delta: trendDeltaText(delta, nightly: spec.nightly, format: spec.format),
                worn: spec.nightly
                    ? L("%d OF %d NIGHTS", recorded, days.count)
                    : L("%d OF %d DAYS", recorded, days.count)),
            rolls: rolls,
            rollCaption: spec.nightly ? L("AVERAGE OF RECORDED NIGHTS") : L("AVERAGE OF RECORDED DAYS"),
            emptyLine: spec.empty.line, emptySub: spec.empty.sub)
    }

    /// "+2 VS PRIOR 7D": this window's median against the one before it. A change that
    /// rounds away to nothing says so rather than printing a signed zero.
    private func trendDeltaText(_ delta: Double?, nightly: Bool,
                                format: (Double) -> String) -> String? {
        guard let delta else { return nil }
        let span = nightly ? L("PRIOR %d NIGHTS", detail.days) : L("PRIOR %dD", detail.days)
        let magnitude = format(abs(delta))
        if magnitude == format(0) { return L("LEVEL WITH %@", span) }
        return L("%@%@ VS %@", delta > 0 ? "+" : "−", magnitude, span)
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

                if showsTrendHero {
                    // A rolling window has no single reading, so it leads with its shape:
                    // one mark a user day, the median printed once underneath.
                    trendHero
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
                    // On a window the hero already drew the pulse's shape; the board keeps
                    // only the companions that share its clock.
                    HeartBoard(range: range, window: window, ticks: ticks,
                               oxygen: heartOxygen, readout: r,
                               slotMinutes: heartSlotMinutes, dial: r.dial,
                               showsLead: range == .day)
                } else if metric == .active, !isMetricWindow {
                    ActiveEnergyBoard(model: activeModel)
                } else if !isMetricWindow {
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
                }
                if metric == .heart, range != .day {
                    VitalsStatPair(left: r.statLeft, right: r.statRight)
                }

                footer
                correctNightLine
            }
            .padding(.horizontal, NB.Layout.gutter)
            .padding(.bottom, 30)
            .onReceive(router.$windowRequest) { request in
                guard let request else { return }
                rangeRaw = request.rawValue
                router.windowRequest = nil
            }
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
        .sheet(isPresented: $correctingNight) {
            SleepWindowSheet(day: m.day, night: m.sleep)
                .environmentObject(data)
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

    // MARK: sleep board — hypnogram, then the two overnight traces, then four numbers

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
        // #28 · the window the rest of this page is counted over, and the way to say it is
        // wrong. A night with no record has nothing to correct, so it offers nothing.
        if let night = m.sleep, night.sleepStart != nil, night.wakeAt != nil {
            SleepWindowCard(night: night,
                            editable: SleepCorrection.canCorrect(day: m.day),
                            edit: { correctingNight = true })
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
        CardBlock(title: L("NIGHT SPO2"), trailing: L("FIXED 85–100 %")) {
            let points = (m.sleep?.spo2 ?? []).filter { m.sleep?.containsSleepTimestamp($0.ts) == true }
            if !points.isEmpty {
                let series = points.map { (ts: $0.ts, value: Double($0.percent)) }
                VitalsLineTrace(points: series, window: window,
                                low: 85, high: 100, tint: NB.cyan1,
                                marksMaximum: false, unit: "%")
                VitalsAxis(labels: window.labels, highlightsLast: false, tint: NB.cyan1)
                    .padding(.trailing, VitalsScaleRail.gutter)
                VitalsChartLegend(
                    items: [.init(text: L("MEASURED POINTS · LINE"), tint: NB.cyan1)]
                        + (VitalsLineTrace.runs(series, window: window).count > 1
                           ? [VitalsChartLegend.Item(text: L("DASHED · NOT MEASURED"),
                                                     tint: NB.cyan1.opacity(0.45))]
                           : []),
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
                let series = points.map { (ts: $0.ts, value: $0.breathsPerMinute) }
                VitalsLineTrace(points: series, window: window,
                                low: 0, high: 60, tint: NB.violet2, unit: "/MIN")
                VitalsAxis(labels: window.labels, highlightsLast: false, tint: NB.violet2)
                    .padding(.trailing, VitalsScaleRail.gutter)
                VitalsChartLegend(
                    items: [.init(text: L("MEASURED POINTS · LINE"), tint: NB.violet2)]
                        + (VitalsLineTrace.runs(series, window: window).count > 1
                           ? [VitalsChartLegend.Item(text: L("DASHED · NOT MEASURED"),
                                                     tint: NB.violet2.opacity(0.45))]
                           : []),
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
        // ⚠️ Night HRV is a tile, not a trace. The band files RMSSD only at the minutes it
        // caught a clean RR run — a scattering of readings across seven hours — and a curve
        // drawn through them invents every slope between them. One night mean, read against
        // this person's own baseline, is the whole of what those readings support.
        //
        // So the recovery section closes on four numbers, in the order the body gives them
        // up: what it carried, how it breathed, how it recovered, how low it went.
        if let respiration = r.respirationLeft, let heartLow = r.heartLow {
            VitalsStatPair(left: r.statRight, right: respiration)
            VitalsStatPair(left: r.statLeft, right: heartLow)
        }

        // ---- REGULARITY · only definable against this person's own habit
        SleepSectionHeader(group: .regularity, score: score?.regularity, effectiveWeight: score?.effectiveWeight(of: .regularity))
        CardBlock(title: L("SLEEP BY NIGHT"), trailing: bedtimeTrailing) {
            scheduleChart(nights: scheduleNights(count: 7), baseline: score?.inputs["bed_median"],
                          empty: score?.inputs["bed_offset"] == nil ? L("NO BEDTIME RECORDED") : L("NO NIGHTS ON RECORD"))
        }
    }

    /// The last N wake-days as columns from asleep to awake. A night the band synced to this
    /// phone draws its own window; one that only settled a score draws the score's bedtime
    /// and recorded minutes; one with neither is a dotted gap the reader can point at.
    private func scheduleNights(count: Int) -> [SleepScheduleNight] {
        let today = m.day
        let byDay = Dictionary(data.history.map { ($0.day.key, $0) }, uniquingKeysWith: { _, later in later })
        return (0..<count).reversed().map { offset in
            let day = today.adding(days: -offset)
            let summary = day == today ? m.sleep : byDay[day.key]?.sleep
            return SleepScheduleNight(day: day, score: data.sleepScores[day.key], summary: summary)
        }
    }

    /// Ready-made: the schedule, its key, and the baseline count while the habit is still
    /// being learned — the one line that says why the band is not drawn yet.
    @ViewBuilder
    private func scheduleChart(nights: [SleepScheduleNight], baseline: Double?, empty: String) -> some View {
        if nights.contains(where: \.isRecorded) {
            SleepScheduleBars(nights: nights, baseline: baseline)
            SleepScheduleBars.legend(baseline: baseline)
            if baseline == nil {
                Text(L("BASELINE %d / %d NIGHTS · SCORED FROM THE THIRD NIGHT",
                       Int(todayScore?.inputs["baseline_bed_nights"] ?? 0),
                       SleepScoreMath.regularityBaselineNights))
                    .font(NBFont.dot(500, 9)).tracking(0.05 * 9)
                    .foregroundStyle(NB.text3Prod)
            }
        } else {
            VitalsChartEmpty(line: empty,
                             sub: L("BASELINE %d / %d NIGHTS · SCORED FROM THE THIRD NIGHT",
                                    Int(todayScore?.inputs["baseline_bed_nights"] ?? 0),
                                    SleepScoreMath.regularityBaselineNights))
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

    /// The score by night now leads the page as the trend hero; the board underneath is
    /// what a median score cannot say by itself — which group is dragging, how the stages
    /// split, when the nights began.
    @ViewBuilder
    private var multiNightBoard: some View {
        let summary = sleepWindow
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

        CardBlock(title: L("SLEEP BY NIGHT"),
                  trailing: summary.bedClock.map { L("USUALLY %@", $0) } ?? Fmt.dash) {
            scheduleChart(nights: scheduleNights(count: summary.slots.count),
                          baseline: summary.bedOffset, empty: L("NO NIGHTS ON RECORD"))
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

    /// The day page's chart. The rolling windows no longer draw a chart card: their shape
    /// is the trend hero at the top of the page.
    @ViewBuilder
    private func chart(_ r: VitalsReadout) -> some View {
        dayChart(r)
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
        dayChartLegend(r)
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
    /// #28 · the last line of the sleep page is the way back to the night's own start and
    /// end. The window card near the top offers the same correction, but the page runs four
    /// score groups deep, and the doubt about when the night began usually arrives at the
    /// bottom of it — after the score, not before. Both open the same wheels.
    @ViewBuilder
    private var correctNightLine: some View {
        if metric == .sleep, let night = m.sleep, night.sleepStart != nil, night.wakeAt != nil,
           SleepCorrection.canCorrect(day: m.day) {
            Button { correctingNight = true } label: {
                // A multi-night window is not looking at one night, so the line says which
                // one it would change.
                Text(range == .day ? L("CHANGE TIMES") : L("CHANGE TIMES · %@", m.day.key))
                    .font(NBFont.dot(600, 10)).tracking(0.12 * 10)
                    .foregroundStyle(NB.lime1.opacity(0.85))
                    // Centred: the page's last line is an offer, not another footnote in
                    // the column of left-aligned grey the footer above it belongs to.
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sleep.changeTimes")
        }
    }

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
        /// The sleep trend reads `data.sleepScores`, which arrives after the page opens.
        let sleepScores: Int
        let minute: Int
    }

    private var key: Key?
    var ticks: [VitalSample]?
    var heartOxygen: [OvernightOxygenPoint]?
    var windowDays: [DailyMetrics]?
    var priorDays: [DailyMetrics]?
    var trendTicksByDay: [UserDay: [VitalSample]]?
    var windowTrendValues: [Double?]?
    var priorTrendValues: [Double?]?
    var metricSlots: [MetricDayBars.Slot]?
    var mealBoard: MealResponsePresentation.Board?
    var activeModel: ActiveEnergyModel?

    func value<T>(_ slot: ReferenceWritableKeyPath<VitalsDetailMemo, T?>,
                  for current: Key, _ compute: () -> T) -> T {
        if key != current {
            key = current
            ticks = nil; heartOxygen = nil; windowDays = nil; metricSlots = nil
            priorDays = nil; trendTicksByDay = nil; windowTrendValues = nil; priorTrendValues = nil
            mealBoard = nil; activeModel = nil
        }
        if let cached = self[keyPath: slot] { return cached }
        let fresh = compute()
        self[keyPath: slot] = fresh
        return fresh
    }
}
