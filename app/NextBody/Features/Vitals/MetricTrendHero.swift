import SwiftUI

/// The week and month hero: one mark a user day, the window's own line under it. It stands
/// where the day page's big number and dial stand, because a rolling window has no single
/// reading — it has a shape. The number is still printed, once, in the summary row under
/// the field, so a week stays comparable with a day; it is no longer the headline. Beside
/// it: the change against the window before, and how many of the days actually recorded.
///
/// ⚠️ A day the band filed nothing for is a dotted slot (bars) or a floor mark (line) —
/// never a zero and never left out. Thirty marks with four silently missing cannot be read,
/// and a missing day is not a zero day (F2 rule 05).
struct MetricTrendHero: View {
    enum Style { case line, bars }

    struct Point: Equatable {
        let start: Date
        let value: Double?
    }

    /// A dashed rule across the field with its name: the window's own median, a baseline.
    struct Rule: Equatable {
        let value: Double
        let label: String
    }

    /// A washed band across the field: this person's own night range.
    struct Band: Equatable {
        let range: ClosedRange<Double>
        let label: String
    }

    struct Summary {
        /// The one number, already formatted: "MEDIAN 58".
        let headline: String
        let unit: String?
        /// "+2 VS PRIOR 7D", or nil when either window is too thin to compare.
        let delta: String?
        /// "6 OF 7 DAYS".
        let worn: String
    }

    /// One slice of the month strip.
    struct Roll: Identifiable {
        let id: Int
        let label: String
        let value: Double?
    }

    let caption: String
    let points: [Point]
    let style: Style
    let scale: ClosedRange<Double>
    let tint: Color
    /// Given a ruler with cuts, a mark wears the colour of the zone its value sits in.
    var zones: VitalsDial.Model? = nil
    var rule: Rule? = nil
    var band: Band? = nil
    let format: (Double) -> String
    var unit: String = ""
    /// What one mark is: "RESTING · PER NIGHT", "TOTAL · PER DAY".
    let seriesLabel: String
    let summary: Summary
    var rolls: [Roll] = []
    /// What the strip averaged: days on most pages, nights on SLEEP and TEMP.
    var rollCaption: String = L("AVERAGE OF RECORDED DAYS")
    let emptyLine: String
    let emptySub: String
    var accessibilityName: String = "vitals.probe.trend"

    private static let height: CGFloat = 150

    private var recorded: Int { points.filter { $0.value != nil }.count }
    private var hasGap: Bool { recorded < points.count }
    private var isMonth: Bool { points.count > 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caption)
                .font(NBFont.ui(400, 10)).tracking(0.12 * 10)
                .foregroundStyle(NB.white.opacity(0.45))
                .lineLimit(1).minimumScaleFactor(0.8)

            if recorded == 0 {
                VitalsChartEmpty(line: emptyLine, sub: emptySub, height: Self.height)
            } else {
                VitalsChartProbe(
                    series: .bins(probeBins),
                    tint: tint,
                    height: Self.height,
                    trailingInset: VitalsScaleRail.gutter,
                    accessibilityTitle: L("BY DAY"),
                    accessibilityName: accessibilityName
                ) { _ in
                    HStack(spacing: VitalsScaleRail.gap) {
                        field
                        VitalsScaleRail(labels: railLabels, tint: tint)
                    }
                }
                axis
                    .padding(.trailing, VitalsScaleRail.gutter)
                legend
            }

            summaryRow
            if !rolls.isEmpty { rollStrip }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vitals.hero")
        .accessibilityLabel(caption)
        .accessibilityValue(accessValue)
    }

    private var accessValue: String {
        var parts = [summary.headline]
        if let unit = summary.unit { parts.append(unit) }
        if let delta = summary.delta { parts.append(delta) }
        parts.append(summary.worn)
        return parts.joined(separator: ", ")
    }

    // MARK: the field

    @ViewBuilder
    private var field: some View {
        switch style {
        case .bars: bars
        case .line: line
        }
    }

    private func fraction(_ value: Double) -> Double {
        MetricTrendMath.fraction(value, in: scale)
    }

    private func markTint(_ value: Double) -> Color {
        zones?.tint(for: value) ?? tint
    }

    private var bars: some View {
        GeometryReader { geo in
            let count = max(points.count, 1)
            let spacing: CGFloat = isMonth ? 2 : 6
            let width = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            let radius = min(width / 2, 6)
            ZStack(alignment: .bottom) {
                bandWash(in: geo.size)
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                                .foregroundStyle(NB.hairline)
                                .opacity(point.value == nil ? 1 : 0)
                            if let value = point.value {
                                RoundedRectangle(cornerRadius: radius, style: .continuous)
                                    .fill(markTint(value))
                                    // A recorded zero is still a day, not a gap.
                                    .frame(height: max(2, geo.size.height * CGFloat(fraction(value))))
                            }
                        }
                        .frame(width: width, height: geo.size.height)
                    }
                }
                ruleLine(in: geo.size)
            }
        }
    }

    private var line: some View {
        Canvas { ctx, size in
            guard !points.isEmpty else { return }
            let pad: CGFloat = 6
            let plot = max(0, size.height - pad * 2)
            let slot = size.width / CGFloat(points.count)
            func y(_ value: Double) -> CGFloat { size.height - pad - CGFloat(fraction(value)) * plot }
            func at(_ index: Int, _ value: Double) -> CGPoint {
                CGPoint(x: (CGFloat(index) + 0.5) * slot, y: y(value))
            }

            if let band {
                let top = y(band.range.upperBound), bottom = y(band.range.lowerBound)
                ctx.fill(Path(CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top))),
                         with: .color(tint.opacity(0.12)))
            }
            ctx.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                     with: .color(NB.white.opacity(0.10)))

            // A night with no reading gets a mark on the floor, never a point at the ruler's
            // foot — and the field with nothing yet is a row of marks waiting, not a box.
            for (i, point) in points.enumerated() where point.value == nil {
                let w = min(14, slot * 0.5)
                ctx.fill(Path(CGRect(x: (CGFloat(i) + 0.5) * slot - w / 2, y: size.height - 3,
                                     width: w, height: 2)),
                         with: .color(NB.white.opacity(0.16)))
            }

            let runs = Self.runs(points.map(\.value)).map { $0.map { at($0.index, $0.value) } }

            // The wash under the line is anchored to the run's own crest and stops at the
            // run's ends, so a missing night stays a hole in the fill too.
            for run in runs where run.count > 1 {
                var area = Path()
                area.move(to: CGPoint(x: run[0].x, y: size.height))
                for p in run { area.addLine(to: p) }
                area.addLine(to: CGPoint(x: run[run.count - 1].x, y: size.height))
                area.closeSubpath()
                let crest = run.map(\.y).min() ?? 0
                ctx.fill(area, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.16), tint.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: crest),
                    endPoint: CGPoint(x: 0, y: size.height)))
            }

            for (i, run) in runs.enumerated() {
                if run.count > 1 {
                    var path = Path()
                    path.move(to: run[0])
                    for p in run.dropFirst() { path.addLine(to: p) }
                    ctx.stroke(path, with: .color(tint),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if i + 1 < runs.count, let tail = run.last, let head = runs[i + 1].first {
                    var gap = Path()
                    gap.move(to: tail)
                    gap.addLine(to: head)
                    ctx.stroke(gap, with: .color(tint.opacity(0.28)),
                               style: StrokeStyle(lineWidth: 1.2, dash: [2, 4]))
                }
            }

            if let rule {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y(rule.value)))
                path.addLine(to: CGPoint(x: size.width, y: y(rule.value)))
                ctx.stroke(path, with: .color(tint.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // A run of one has no line at all, so its dot is the reading.
            let r: CGFloat = isMonth ? 1.8 : 2.8
            for (i, point) in points.enumerated() {
                guard let value = point.value else { continue }
                let p = at(i, value)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(markTint(value)))
            }

            // The last recorded day is ringed: it is the one the reader is standing on.
            if let last = points.indices.last, let value = points[last].value {
                let p = at(last, value)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)),
                           with: .color(tint.opacity(0.45)), lineWidth: 1)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.4, y: p.y - 3.4, width: 6.8, height: 6.8)),
                         with: .color(markTint(value)))
            }
        }
    }

    @ViewBuilder
    private func bandWash(in size: CGSize) -> some View {
        if let band {
            let top = size.height * (1 - CGFloat(fraction(band.range.upperBound)))
            let bottom = size.height * (1 - CGFloat(fraction(band.range.lowerBound)))
            Rectangle()
                .fill(tint.opacity(0.12))
                .frame(height: max(1, bottom - top))
                .offset(y: -(size.height - bottom))
        }
    }

    @ViewBuilder
    private func ruleLine(in size: CGSize) -> some View {
        if let rule {
            Path { path in
                let y = size.height * (1 - CGFloat(fraction(rule.value)))
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(tint.opacity(0.55))
        }
    }

    /// Uninterrupted stretches of days that recorded. An empty slot ends a run.
    static func runs(_ values: [Double?]) -> [[(index: Int, value: Double)]] {
        var out: [[(index: Int, value: Double)]] = []
        var run: [(index: Int, value: Double)] = []
        for (i, value) in values.enumerated() {
            if let value {
                run.append((i, value))
            } else if !run.isEmpty {
                out.append(run)
                run = []
            }
        }
        if !run.isEmpty { out.append(run) }
        return out
    }

    // MARK: the ruler, the clock, the key

    private var railLabels: [String] {
        let mid = (scale.lowerBound + scale.upperBound) / 2
        return [scale.upperBound, mid, scale.lowerBound].map(format)
    }

    /// Seven weekday names under a week; the first date and TODAY under a month. Seven
    /// `12`s in a row tell you nothing, and thirty weekday names do not fit.
    @ViewBuilder
    private var axis: some View {
        if isMonth {
            HStack(spacing: 6) {
                Text(points.first.map { Fmt.displayDate($0.start, format: "d MMM").uppercased() } ?? Fmt.dash)
                    .font(NBFont.ui(400, 9))
                    .foregroundStyle(NB.white.opacity(0.45))
                Spacer(minLength: 0)
                Text(L("TODAY"))
                    .font(NBFont.ui(500, 9))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(points.enumerated()), id: \.offset) { i, point in
                    let last = i == points.count - 1
                    Text(Fmt.weekday(point.start))
                        .font(NBFont.ui(last ? 500 : 400, 9))
                        .foregroundStyle(last ? tint : NB.white.opacity(0.45))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private var legend: some View {
        VitalsChartLegend(
            items: [.init(text: seriesLabel, tint: tint, stops: zones?.legendStops)]
                + (rule.map { [VitalsChartLegend.Item(text: $0.label, tint: tint, isArea: true)] } ?? [])
                + (band.map { [VitalsChartLegend.Item(text: $0.label, tint: tint, isArea: true)] } ?? []),
            trailing: hasGap ? L("DOTTED · NO RECORD") : nil,
            trailingTint: NB.white.opacity(0.45))
    }

    private var probeBins: [VitalsProbeMath.Bin] {
        let ranges = VitalsProbeMath.equalSlots(count: points.count)
        return zip(points, ranges).map { point, range in
            let clock = MetricWindowMath.slotLabel(point.start, count: points.count)
            guard let value = point.value else {
                return .init(start: range.start, end: range.end, yFraction: nil,
                             text: VitalsProbeCopy.gap(clock), vacant: true)
            }
            let printed = unit.isEmpty ? format(value) : L("%@ %@", format(value), unit)
            return .init(start: range.start, end: range.end,
                         yFraction: 1 - fraction(value),
                         text: VitalsProbeCopy.line(clock, printed))
        }
    }

    // MARK: the one number, the change, the count

    private var summaryRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(summary.headline)
                .font(NBFont.dot(700, 14)).tracking(0.02 * 14)
                .foregroundStyle(recorded == 0 ? NB.text3Prod : tint)
                .lineLimit(1).minimumScaleFactor(0.8)
            if let unit = summary.unit, recorded > 0 {
                Text(unit)
                    .font(NBFont.ui(600, 10))
                    .foregroundStyle(NB.text1)
                    .lineLimit(1)
            }
            if let delta = summary.delta {
                Text(L("· %@", delta))
                    .font(NBFont.ui(500, 10))
                    .foregroundStyle(NB.white.opacity(0.62))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Text(summary.worn)
                .font(NBFont.ui(400, 10))
                .foregroundStyle(NB.white.opacity(0.42))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(NB.white.opacity(0.06)).frame(height: 1)
        }
    }

    // MARK: the month, week by week

    /// Two days, then four weeks, oldest first: the mean of each slice as a short column,
    /// so a month's drift reads in five marks after the thirty above have shown its texture.
    private var rollStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("WEEK BY WEEK"))
                    .font(NBFont.ui(500, 10)).tracking(0.12 * 10)
                    .foregroundStyle(NB.white.opacity(0.45))
                Spacer(minLength: 0)
                Text(rollCaption)
                    .font(NBFont.ui(400, 9))
                    .foregroundStyle(NB.white.opacity(0.35))
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(rolls) { roll in
                    let last = roll.id == rolls.count - 1
                    VStack(spacing: 4) {
                        Text(roll.value.map(format) ?? Fmt.dash)
                            .font(NBFont.dot(600, 11))
                            .foregroundStyle(roll.value == nil ? NB.text3Prod : (last ? tint : NB.text1))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                                .foregroundStyle(NB.hairline)
                                .opacity(roll.value == nil ? 1 : 0)
                            if let value = roll.value {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(tint.opacity(last ? 1 : 0.55))
                                    .frame(height: max(2, 36 * CGFloat(fraction(value))))
                            }
                        }
                        .frame(height: 36)
                        Text(roll.label)
                            .font(NBFont.ui(last ? 500 : 400, 9))
                            .foregroundStyle(last ? tint : NB.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.trailing, VitalsScaleRail.gutter)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(NB.white.opacity(0.06)).frame(height: 1)
        }
    }
}
