import SwiftUI

/// The three rolling windows, reopened for the five instruments that still only had a day:
/// STRESS · TEMP · STEPS · DIST · CALS. Same three words sleep (ADR 0008), response
/// (ADR 0012) and heart (ADR 0013) already carry, and the same grain heart counts in —
/// user days, 04:00 → 04:00.
///
/// ⚠️ Rolling last-N, never a calendar week or month. A natural week collapses to one bar
/// every Monday, which reads as data loss on a page whose whole job is to show wear.
extension RollingPills {
    func metricPeriodLabel(for metric: VitalsMetric) -> String {
        self == .day ? metric.periodLabel : L(DetailWindow(.metric, self).periodKey)
    }

    func metricHeroSensor(for metric: VitalsMetric) -> String {
        self == .day
            ? metric.sensor
            : L("%@ · %@", metric.sensor, L(DetailWindow(.metric, self).periodKey))
    }

    /// What the chart card is headed on this window. The day heads stay exactly as they
    /// were; the rolling ones name the grain, because a bar a day and a bar an hour are
    /// the same shape and only the head separates them.
    func metricChartTitle(for metric: VitalsMetric) -> String {
        guard self != .day else { return metric.chartTitle }
        switch metric {
        case .stress:   return L("DAILY AUTONOMIC LOAD")
        case .temp:     return L("DAILY SKIN TEMPERATURE")
        case .steps:    return L("STEPS BY DAY")
        case .distance: return L("DISTANCE BY DAY")
        case .active:   return L("BURN BY DAY")
        default:        return metric.chartTitle
        }
    }
}

// MARK: - which metrics carry the switcher, and how their window is drawn

extension VitalsMetric {
    /// The five instruments this board opened, plus nothing else: HEART, SLEEP and
    /// RESPONSE own their own range types and their own boards.
    var hasMetricRange: Bool {
        switch self {
        case .stress, .temp, .steps, .distance, .active: true
        case .heart, .sleep, .hrv, .response:            false
        }
    }

    var detailSurface: DetailSurface {
        switch self {
        case .sleep, .hrv: .sleep
        case .heart:       .heart
        case .response:    .response
        case .active:      .active
        case .stress, .temp, .steps, .distance: .metric
        }
    }

    var showsDetailPills: Bool {
        self == .sleep || self == .response || self == .heart || hasMetricRange
    }

    /// A trace metric's window is an envelope a day — low and high of that day's ticks.
    /// An accumulated metric's window is one bar a day — that day's settled total.
    var windowIsAccumulated: Bool {
        switch self {
        case .steps, .distance, .active: true
        default:                         false
        }
    }
}

// MARK: - one bar a user day

/// The rolling window for the three accumulated instruments. One bar a user day, scaled to
/// the busiest day in the window, with the window's own median drawn across it. A day the
/// band filed nothing for is a dotted slot at full height — thirty bars with four silently
/// missing cannot be read, and a missing day is not a zero day (F2 rule 05).
///
/// ⚠️ A day that was worn and did not move is a real zero: it keeps a 2 pt floor bar so it
/// is visibly a day, not a gap.
struct MetricDayBars: View {
    struct Slot: Equatable {
        let start: Date
        let total: Double?
    }

    let slots: [Slot]
    let tint: Color
    /// The window's median recorded day, drawn as a dashed line. nil until three days.
    var median: Double?
    var format: (Double) -> String
    var height: CGFloat = 160

    var body: some View {
        VitalsChartProbe(
            series: .bins(probeBins),
            tint: tint,
            height: height,
            trailingInset: VitalsScaleRail.gutter,
            accessibilityTitle: L("BY DAY"),
            accessibilityName: "vitals.probe.metric.days"
        ) { _ in
            HStack(spacing: VitalsScaleRail.gap) {
                GeometryReader { geo in
                    let count = max(slots.count, 1)
                    let spacing: CGFloat = slots.count > 10 ? 2 : 6
                    let width = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
                    let radius = min(width / 2, 6)
                    ZStack(alignment: .bottom) {
                        HStack(alignment: .bottom, spacing: spacing) {
                            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                                        .foregroundStyle(NB.hairline)
                                        .opacity(slot.total == nil ? 1 : 0)
                                    if let total = slot.total, total > 0 {
                                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                                            .fill(tint)
                                            .frame(height: max(2, height * CGFloat(fraction(total))))
                                    }
                                }
                                .frame(width: width, height: height)
                            }
                        }
                        if let median, peak > 0 {
                            // The habit line, not a target: it is this window's own middle day.
                            Path { path in
                                let y = geo.size.height * (1 - CGFloat(fraction(median)))
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: geo.size.width, y: y))
                            }
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(tint.opacity(0.55))
                        }
                    }
                }

                VitalsScaleRail(labels: railLabels, tint: tint)
            }
        }
    }

    static func legend(tint: Color, median: Double?, format: (Double) -> String) -> VitalsChartLegend {
        VitalsChartLegend(
            items: [.init(text: L("PER DAY"), tint: tint)]
                + (median.map { [VitalsChartLegend.Item(text: L("MEDIAN %@", format($0)), tint: tint, isArea: true)] } ?? []),
            trailing: L("DOTTED · NO RECORD"),
            trailingTint: NB.white.opacity(0.45))
    }

    /// The rail is scaled to the busiest day, so its top mark is that day and its floor is
    /// a real zero — the same contract `VitalsHistogram` prints its hours against.
    private var peak: Double { slots.compactMap(\.total).max() ?? 0 }

    private var railLabels: [String] {
        [peak, peak / 2, 0].map(format)
    }

    private func fraction(_ value: Double) -> Double {
        guard peak > 0 else { return 0 }
        return min(1, max(0, value / peak))
    }

    private var probeBins: [VitalsProbeMath.Bin] {
        let ranges = VitalsProbeMath.equalSlots(count: slots.count)
        return zip(slots, ranges).map { slot, range in
            let clock = MetricWindowMath.slotLabel(slot.start, count: slots.count)
            guard let total = slot.total else {
                return .init(start: range.start, end: range.end, yFraction: nil,
                             text: VitalsProbeCopy.gap(clock), vacant: true)
            }
            return .init(start: range.start, end: range.end,
                         yFraction: 1 - fraction(total),
                         text: VitalsProbeCopy.line(clock, format(total)))
        }
    }
}

// MARK: - the window's arithmetic

/// What the five rolling boards reduce before anything is laid out. The medians and the
/// worn-day count come from `HeartWindowMath`, which already settled that vocabulary for
/// the heart window — a second copy of "median of daily medians" would eventually disagree
/// with the first.
enum MetricWindowMath {
    /// A weekday inside a week, a day-of-month across a month. Seven `12`s in a row tell
    /// you nothing; seven weekday names do.
    static func slotLabel(_ start: Date, count: Int) -> String {
        count > 10 ? String(Calendar.current.component(.day, from: start)) : Fmt.weekday(start)
    }

    /// One bucket a user day, in window order. A day the band filed nothing for stays an
    /// empty array — never a zero, which is a reading the band never took.
    static func dailyBuckets(ticks: [VitalSample], endingOn day: UserDay, days: Int,
                             value: (VitalSample) -> Double?) -> [[Double]] {
        let first = day.adding(days: -(days - 1))
        return (0..<days).map { offset in
            let bucket = first.adding(days: offset)
            return ticks.compactMap { sample in
                guard sample.ts >= bucket.start, sample.ts < bucket.end else { return nil }
                return value(sample)
            }
        }
    }

    static func slots(days: [DailyMetrics], total: (DailyMetrics) -> Double?) -> [MetricDayBars.Slot] {
        days.map { .init(start: $0.day.start, total: total($0)) }
    }

    static func recorded(_ slots: [MetricDayBars.Slot]) -> [Double] {
        slots.compactMap(\.total)
    }

    /// The window's own total, which is only a number when at least one day recorded one.
    static func sum(_ slots: [MetricDayBars.Slot]) -> Double? {
        let values = recorded(slots)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    /// The best day in the window and when it was, for the tile that names it.
    static func best(_ slots: [MetricDayBars.Slot]) -> MetricDayBars.Slot? {
        slots.filter { $0.total != nil }.max { ($0.total ?? 0) < ($1.total ?? 0) }
    }
}
