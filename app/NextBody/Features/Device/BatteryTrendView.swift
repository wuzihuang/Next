import SwiftUI

/// Second-level behind the device lime slab. Paper 12F is only the instrument:
/// DAY / WEEK / MONTH pills, overnight columns on the sleep clock, and the line
/// this phone kept. Landing is DAY — last 24 hours — the same default HEART uses.
struct BatteryTrendView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @State private var rangeRaw = RollingPills.day.rawValue
    private var range: RollingPills { .parse(rangeRaw) }
    private var detail: DetailWindow { DetailWindow(.battery, range) }

    private var now: Date { Date() }
    private var window: (start: Date, end: Date) {
        BatteryLog.window(endingAt: now, range: range)
    }
    private var plot: BatteryPlot {
        BatteryLog.plot(data.batteryLog, from: window.start, to: window.end)
    }

    /// The night the sleep page uses — sleepStart → wakeAt — not a 04:00 cut and
    /// not a charge span the phone invented.
    private var overnightNights: [BatterySpan] {
        var seen = Set<Date>()
        var spans: [BatterySpan] = []
        for row in data.history + [data.today] {
            guard seen.insert(row.day.date).inserted,
                  let start = row.sleep?.sleepStart,
                  let wake = row.sleep?.wakeAt, wake > start else { continue }
            spans.append(BatterySpan(start: start, end: wake))
        }
        return spans
    }

    private var overnight: [BatterySpan] {
        BatteryDrainMath.clip(overnightNights, from: plot.start, to: plot.end)
    }

    var body: some View {
        DetailScroll(glow: NB.lime1, title: L("BATTERY"), trailing: {
            Text(L(detail.periodKey))
                .font(NBFont.dot(600, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.text3Prod)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }) {
            VStack(alignment: .leading, spacing: 14) {
                SegmentedPills(options: RollingPills.words,
                               selection: $rangeRaw)
                instrument
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .task {
                #if DEBUG
                if let override = DetailWindow.debugRange(for: .battery) {
                    rangeRaw = override.rawValue
                }
                #endif
                guard !Band.allowsSeed else { return }
                await Repository.shared.hydrate(detail, endingAt: UserDay.containing(now), into: data)
            }
        } onBack: {
            router.back()
        }
    }

    private var instrument: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L(detail.periodKey))
                        .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                        .foregroundStyle(NB.white.opacity(0.60))
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(NB.lime1.opacity(0.28))
                            .frame(width: 10, height: 10)
                        Text(L("OVERNIGHT"))
                            .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                            .foregroundStyle(NB.white.opacity(0.60))
                    }
                }

                if plot.points.isEmpty {
                    Text(L("Nothing recorded yet. Charge, unplug, or sync this HOOP to start the line."))
                        .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                        .foregroundStyle(NB.text3Prod)
                        .frame(height: 148, alignment: .topLeading)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(spacing: 8) {
                            VitalsChartProbe(
                                series: .points(probePoints),
                                tint: NB.lime1,
                                height: 148,
                                gapFraction: VitalsProbeMath.gapFraction(
                                    span: plot.end.timeIntervalSince(plot.start)),
                                leadingInset: 3,
                                trailingInset: 3,
                                clockAt: probeClock,
                                accessibilityTitle: L("Battery trend"),
                                accessibilityName: "battery.probe"
                            ) { probing in
                                BatteryTrendChart(
                                    plot: plot,
                                    overnight: overnight,
                                    dayTicks: gridTicks,
                                    lineWidth: range == .month ? 1.5 : 1.8,
                                    showPip: !probing)
                            }
                            HStack(spacing: 0) {
                                ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                                    let last = i == labels.count - 1
                                    Text(label)
                                        .font(NBFont.dot(last ? 700 : 500, 9))
                                        .tracking(0.08 * 9)
                                        .foregroundStyle(last ? NB.lime1 : NB.white.opacity(0.34))
                                    if i < labels.count - 1 { Spacer(minLength: 0) }
                                }
                            }
                        }
                        BatteryScaleRail(labels: railLabels)
                            .frame(height: 148)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle().fill(NB.hairline).frame(height: 1)

            HStack(spacing: 0) {
                BatteryFact(label: L("HIGH"), value: highParts.value, unit: highParts.unit)
                Rectangle().fill(NB.hairline).frame(width: 1)
                BatteryFact(label: L("LOW"), value: lowParts.value, unit: lowParts.unit)
                Rectangle().fill(NB.hairline).frame(width: 1)
                BatteryFact(label: L("LAST PLUG"), value: lastPlug)
            }

            if let leftParts {
                Rectangle().fill(NB.hairline).frame(height: 1)
                BatteryFact(label: L("LEFT"), value: leftParts.value, unit: leftParts.unit)
                    .accessibilityIdentifier("battery.left")
            }

            if let etaLine {
                Rectangle().fill(NB.hairline).frame(height: 1)
                Text(etaLine)
                    // This is a sentence with a weekday and clock. Use one UI face;
                    // Doto's punctuation/numerals misalign with its Chinese fallback.
                    .font(NBFont.ui(500, 12))
                    .tracking(0.02 * 12)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("battery.eta")
            }
        }
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
        .clipShape(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Battery trend"))
        .accessibilityValue(L(detail.periodKey))
    }

    private var railLabels: [String] {
        plot.isPercent ? ["100", "50", "0"] : ["4", "2", "0"]
    }

    private var highParts: (value: String, unit: String?) {
        factParts(plot.high)
    }
    private var lowParts: (value: String, unit: String?) {
        factParts(plot.low)
    }
    private func factParts(_ value: Double?) -> (String, String?) {
        guard let value else { return (Fmt.dash, nil) }
        return ("\(Int(value.rounded()))", plot.isPercent ? "%" : "/4")
    }

    /// Learned unplugged slope only. Silent with `eta` — never the five-day pack.
    private var leftParts: (value: String, unit: String)? {
        guard plot.isPercent, !plot.points.isEmpty,
              let left = BatteryDrainMath.left(in: data.batteryLog, now: now) else { return nil }
        switch left {
        case .hours(let n): return ("\(n)", L("HRS"))
        case .days(let n): return ("\(n)", L("DAYS"))
        }
    }

    /// Small because it is a slope, not a reading. Silent when the log has not
    /// learned a rate — the five-day pack must not become a clock.
    private var etaLine: String? {
        guard plot.isPercent, !plot.points.isEmpty,
              let eta = BatteryDrainMath.eta(in: data.batteryLog, now: now) else { return nil }
        switch eta {
        case .full(let at):
            return L("EST · FULL %@", stamp(at))
        case .empty(let at):
            return L("EST · EMPTY %@", stamp(at))
        }
    }

    private func stamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let clock = Fmt.clock(date)
        if calendar.isDate(date, inSameDayAs: now) { return L("TODAY %@", clock) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return L("TOMORROW %@", clock)
        }
        let start = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
        if (1...6).contains(days) {
            return "\(Fmt.weekday(date)) \(clock)"
        }
        return "\(Fmt.displayDate(date, format: "MM-dd")) \(clock)"
    }

    private var lastPlug: String {
        guard let at = BatteryLog.lastPlug(in: data.batteryLog, from: window.start, to: window.end)
        else { return L("NEVER") }
        return Fmt.clock(at)
    }

    /// Week marks each recorded night's start — the same clock the sleep page
    /// uses — not the 04:00 user-day cut. Day and month keep the four-way split
    /// the axis labels use.
    private var gridTicks: [Date] {
        switch range {
        case .week:
            let starts = overnightNights.map(\.start)
                .filter { $0 > plot.start && $0 < plot.end }
                .sorted()
            if !starts.isEmpty { return starts }
            var day = UserDay.containing(plot.start)
            if day.start <= plot.start { day = day.adding(days: 1) }
            var ticks: [Date] = []
            while day.start < plot.end {
                ticks.append(day.start)
                day = day.adding(days: 1)
            }
            return ticks
        case .day, .month:
            let span = plot.end.timeIntervalSince(plot.start)
            return (1...3).map { i in
                plot.start.addingTimeInterval(span * Double(i) / 4)
            }
        }
    }

    private var labels: [String] {
        let span = max(0.001, plot.end.timeIntervalSince(plot.start))
        let marks = (0..<5).map { i in
            plot.start.addingTimeInterval(span * Double(i) / 4)
        }
        return marks.enumerated().map { i, date in
            if i == marks.count - 1 { return L("NOW") }
            return switch range {
            case .day:
                Fmt.clock(date)
            case .week:
                Fmt.weekday(date)
            case .month:
                String(format: "%02d", Calendar.current.component(.day, from: date))
            }
        }
    }

    private var probePoints: [VitalsProbeMath.Point] {
        let span = max(0.001, plot.end.timeIntervalSince(plot.start))
        return plot.points.filter { !$0.estimated }.map { point in
            let fraction = VitalsProbeMath.clamp(point.at.timeIntervalSince(plot.start) / span)
            let value = plot.isPercent
                ? "\(Int(point.value.rounded()))%"
                : "\(Int(point.value.rounded()))/4"
            return VitalsProbeMath.Point(
                fraction: fraction,
                yFraction: VitalsProbeMath.yFraction(value: point.value, low: 0, high: plot.yMax),
                text: VitalsProbeCopy.line(Fmt.clock(point.at), value))
        }
    }

    private func probeClock(_ fraction: Double) -> String {
        if fraction >= 0.999 { return L("NOW") }
        let span = max(0, plot.end.timeIntervalSince(plot.start))
        return Fmt.clock(plot.start.addingTimeInterval(span * fraction))
    }
}

/// Paper 12F · overnight lime columns, a lime polyline, a NOW pip.
/// The ruler lives beside the field. A stretch the phone did not hear is a
/// dashed drain curve, not a ruler.
private struct BatteryTrendChart: View {
    let plot: BatteryPlot
    var overnight: [BatterySpan] = []
    let dayTicks: [Date]
    var height: CGFloat = 148
    var lineWidth: CGFloat = 1.8
    var showPip = true

    var body: some View {
        Canvas { ctx, size in
            let spanY = max(0.001, plot.yMax)
            let spanX = max(0.001, plot.end.timeIntervalSince(plot.start))
            let inset: CGFloat = 3
            func y(_ v: Double) -> CGFloat {
                let clamped = min(plot.yMax, max(0, v))
                return size.height - 1 - clamped / spanY * (size.height - 2)
            }
            func x(_ date: Date) -> CGFloat {
                inset + CGFloat(date.timeIntervalSince(plot.start) / spanX) * (size.width - inset * 2)
            }
            func point(_ p: BatteryPoint) -> CGPoint {
                CGPoint(x: x(p.at), y: y(p.value))
            }

            for tick in dayTicks {
                var lane = Path()
                let at = x(tick)
                lane.move(to: CGPoint(x: at, y: 0))
                lane.addLine(to: CGPoint(x: at, y: size.height))
                ctx.stroke(lane, with: .color(NB.white.opacity(0.06)), lineWidth: 1)
            }

            for span in overnight {
                let left = x(span.start)
                let width = max(2, x(span.end) - left)
                ctx.fill(Path(CGRect(x: left, y: 0, width: width, height: size.height)),
                         with: .color(NB.lime1.opacity(0.10)))
            }

            for (i, run) in plot.runs.enumerated() {
                guard let first = run.first else { continue }
                var heard = Path()
                var guess = Path()
                var prev = first
                if run.count == 1 {
                    heard.move(to: point(first))
                    heard.addLine(to: CGPoint(x: point(first).x + 0.5, y: point(first).y))
                }
                for p in run.dropFirst() {
                    var segment = Path()
                    segment.move(to: point(prev))
                    segment.addLine(to: point(p))
                    if prev.estimated || p.estimated { guess.addPath(segment) }
                    else { heard.addPath(segment) }
                    prev = p
                }
                ctx.stroke(heard, with: .color(NB.lime1),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                ctx.stroke(guess, with: .color(NB.lime1.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round, dash: [2, 3]))
                if i + 1 < plot.runs.count,
                   let next = plot.runs[i + 1].first,
                   let last = run.last,
                   last.estimated || next.estimated {
                    var join = Path()
                    join.move(to: point(last))
                    join.addLine(to: point(next))
                    ctx.stroke(join, with: .color(NB.lime1.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                }
            }

            if showPip, let end = plot.runs.last?.last {
                let at = point(end)
                ctx.fill(Path(ellipseIn: CGRect(x: at.x - 3, y: at.y - 3, width: 6, height: 6)),
                         with: .color(NB.lime1))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Doto rail on the right, top mark first — 100 / 50 / 0, or 4 / 2 / 0 for bars.
private struct BatteryScaleRail: View {
    let labels: [String]

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                    let fraction = labels.count > 1
                        ? Double(i) / Double(labels.count - 1)
                        : 0
                    let y = g.size.height * fraction
                    Rectangle()
                        .fill(NB.white.opacity(0.22))
                        .frame(width: 6, height: 1)
                        .offset(x: 0, y: y)
                    Text(label)
                        .font(NBFont.dot(600, 9))
                        .tracking(0.06 * 9)
                        .foregroundStyle(NB.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .offset(x: 8, y: y - 6)
                }
            }
        }
        .frame(width: 28)
        .accessibilityHidden(true)
    }
}

/// One cell on the carbon instrument. Same split as the lime slab: Doto number, Doto unit.
private struct BatteryFact: View {
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(NBFont.ui(500, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.text3Prod)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(NBFont.dot(700, 20))
                    .foregroundStyle(NB.text1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let unit {
                    Text(unit)
                        .font(NBFont.dot(500, 10))
                        .foregroundStyle(NB.white.opacity(0.45))
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
