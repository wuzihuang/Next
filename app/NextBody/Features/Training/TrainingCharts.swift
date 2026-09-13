import SwiftUI

/// The 200pt version of the ring. Same ruler, same three lanes. Lime is the
/// page colour; over the cap turns ember. The shape never changes.
struct BigTrainingRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let load: Double?
    let target: Double?
    let zone: ClosedRange<Double>?
    var tint: Color = NB.lime1
    var heroTint: Color? = nil
    var over = false
    var caption: String = "OF 21"
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().strokeBorder(NB.ringTrack, lineWidth: 14)
                .frame(width: 186, height: 186)
            RingArc(from: 0, to: shown / TrainingWindowMath.fullRing)
                .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .frame(width: 172, height: 172)
            if over {
                Circle().stroke(NB.ember1.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [2, 6]))
                    .frame(width: 200, height: 200)
            }
            if let zone {
                RingArc(from: zone.lowerBound / TrainingWindowMath.fullRing,
                        to: zone.upperBound / TrainingWindowMath.fullRing)
                    .stroke(NB.lime2, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 194, height: 194)
            }
            if let target {
                let a = Angle.degrees(360 * target / TrainingWindowMath.fullRing - 90)
                Circle().fill(NB.limePale)
                    .frame(width: 9, height: 9)
                    .offset(x: 97 * cos(a.radians), y: 97 * sin(a.radians))
            }
            VStack(spacing: 6) {
                Text(Fmt.load(load))
                    .font(NBFont.dot(700, 46)).tracking(-0.02 * 46)
                    .foregroundStyle(load == nil ? NB.text3Prod : (heroTint ?? tint))
                Text(L(caption))
                    .font(NBFont.ui(500, 11)).tracking(0.22 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
        }
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { shown = load ?? 0 } }
        .onChange(of: load) { _, v in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { shown = v ?? 0 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("%@ %@ out of 21", MetricNames.trainingLoad, Fmt.load(load)))
    }
}

/// One day's load on the 0–21 ruler. WEEK and MONTH use this instead of the
/// ring: a missing day is a hole, not a zero and not a dashed callout.
struct TrainingDayLine: View {
    let values: [Double?]
    let average: Double?
    var todayIndex: Int? = nil
    var heavyIndex: Int? = nil

    private static let ceiling = 21.0
    private static let pad: CGFloat = 8

    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty else { return }
            let plot = max(0, size.height - Self.pad * 2)
            let slot = size.width / CGFloat(values.count)
            func y(_ value: Double) -> CGFloat {
                size.height - Self.pad - CGFloat(min(Self.ceiling, max(0, value))) / Self.ceiling * plot
            }
            func point(_ index: Int, _ value: Double) -> CGPoint {
                CGPoint(x: (CGFloat(index) + 0.5) * slot, y: y(value))
            }

            for rule in [7.0, 14.0] {
                ctx.fill(Path(CGRect(x: 0, y: y(rule), width: size.width, height: 1)),
                         with: .color(NB.white.opacity(0.06)))
            }
            ctx.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                     with: .color(NB.white.opacity(0.10)))

            let runs = TrainingWindowMath.lineRuns(values).map { $0.map { point($0.index, $0.value) } }
            guard !runs.isEmpty else { return }

            for run in runs where run.count > 1 {
                var area = Path()
                area.move(to: CGPoint(x: run[0].x, y: size.height))
                for p in run { area.addLine(to: p) }
                area.addLine(to: CGPoint(x: run[run.count - 1].x, y: size.height))
                area.closeSubpath()
                let crest = run.map(\.y).min() ?? 0
                ctx.fill(area, with: .linearGradient(
                    Gradient(colors: [NB.lime1.opacity(0.18), NB.lime1.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: crest),
                    endPoint: CGPoint(x: 0, y: size.height)))
            }

            for run in runs where run.count > 1 {
                var line = Path()
                line.move(to: run[0])
                for p in run.dropFirst() { line.addLine(to: p) }
                ctx.stroke(line, with: .color(NB.lime1),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            if let average {
                var rule = Path()
                rule.move(to: CGPoint(x: 0, y: y(average)))
                rule.addLine(to: CGPoint(x: size.width, y: y(average)))
                ctx.stroke(rule, with: .color(NB.limePale.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }

            let r: CGFloat = values.count > 14 ? 1.8 : 2.6
            for (index, value) in values.enumerated() {
                guard let value else { continue }
                let p = point(index, value)
                let heavy = index == heavyIndex && index != todayIndex
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(heavy ? NB.ember1 : NB.lime1.opacity(0.9)))
            }

            if let todayIndex, values.indices.contains(todayIndex), let value = values[todayIndex] {
                let p = point(todayIndex, value)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)),
                           with: .color(NB.lime1.opacity(0.45)), lineWidth: 1)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.4, y: p.y - 3.4, width: 6.8, height: 6.8)),
                         with: .color(NB.lime1))
            }
        }
    }
}

/// Recorded cumulative values on the actual user-day clock. Missing intervals
/// interrupt the line; a target is a horizontal reference, never a prediction.
struct CumulativeCurve: View {
    let target: Double?
    var zone: ClosedRange<Double>? = nil
    var points: [LoadPoint] = []
    var day: UserDay = UserDay.containing(Date())
    var through: Date = Date()

    private func pt(_ point: TrainingCurvePoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * TrainingWindowMath.dayFraction(point.ts, day: day),
                y: y(point.load, size))
    }

    private func y(_ load: Double, _ size: CGSize) -> CGFloat {
        size.height - 12 - CGFloat(load / 21) * (size.height - 24)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let data = TrainingWindowMath.curveData(
                points.map { TrainingCurvePoint(ts: $0.ts, load: $0.load) },
                day: day, through: through)
            ZStack(alignment: .topLeading) {
                if let zone {
                    Rectangle().fill(NB.lime1.opacity(0.12))
                        .frame(height: max(0, y(zone.lowerBound, size) - y(zone.upperBound, size)))
                        .offset(y: y(zone.upperBound, size))
                }
                if let target {
                    let targetY = y(target, size)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: targetY))
                        p.addLine(to: CGPoint(x: size.width, y: targetY))
                    }
                    .stroke(NB.limePale.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    Text(L("TARGET %@", String(format: "%.1f", target)))
                        .font(NBFont.dot(700, 11)).tracking(0.02 * 11)
                        .foregroundStyle(NB.limePale)
                        .offset(x: 4, y: max(0, targetY - 18))
                }
                Path { p in
                    p.move(to: CGPoint(x: 0, y: size.height - 12))
                    p.addLine(to: CGPoint(x: size.width, y: size.height - 12))
                }
                .stroke(NB.white.opacity(0.10), lineWidth: 1)

                ForEach(Array(data.segments.enumerated()), id: \.offset) { _, segment in
                    if let first = segment.first, let last = segment.last {
                        Path { p in
                            p.move(to: pt(first, size))
                            for point in segment.dropFirst() { p.addLine(to: pt(point, size)) }
                            p.addLine(to: CGPoint(x: pt(last, size).x, y: size.height - 12))
                            p.addLine(to: CGPoint(x: pt(first, size).x, y: size.height - 12))
                            p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [NB.lime1.opacity(0.28), NB.lime1.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                        Path { p in
                            p.move(to: pt(first, size))
                            for point in segment.dropFirst() { p.addLine(to: pt(point, size)) }
                        }
                        .stroke(NB.lime1, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        if segment.count == 1 {
                            Circle().fill(NB.lime1).frame(width: 4, height: 4)
                                .position(pt(first, size))
                        }
                    }
                }
                if let last = data.segments.last?.last {
                    Circle().fill(NB.carbon2).frame(width: 8, height: 8)
                        .overlay(Circle().stroke(NB.lime1, lineWidth: 2.5))
                        .position(pt(last, size))
                } else {
                    Text(L("NO LOAD SAMPLES"))
                        .font(NBFont.ui(500, 11)).foregroundStyle(NB.text3Prod)
                        .frame(width: size.width, height: size.height)
                }
            }
        }
    }
}

struct ZoneBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let zone: String
    let fill: Double
    let tint: Color
    let value: String

    @State private var grown: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            Text(zone)
                .font(NBFont.dot(700, 11))
                .foregroundStyle(NB.macroLabel)
                .frame(width: 24, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0x1A1A20))
                    Capsule().fill(tint).frame(width: geo.size.width * grown)
                }
            }
            .frame(height: 12)
            Text(value)
                .font(NBFont.dot(700, 11)).tracking(0.02 * 11)
                .foregroundStyle(tint)
                .frame(width: 44, alignment: .trailing)
        }
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7)) { grown = fill } }
        .onChange(of: fill) { _, value in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { grown = value }
        }
    }
}

/// One stacked column a day: Z1–3 lime under Z4–5 ember.
struct TrainingZoneStack: View {
    let days: [TrainingDayFacts]

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                let easy = Double(day.easyMinutes ?? 0)
                let hard = Double(day.hardMinutes ?? 0)
                let scale = TrainingWindowMath.zoneScaleMinutes(days)
                VStack(spacing: 0) {
                    if hard > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 5, bottomLeadingRadius: easy > 0 ? 0 : 5,
                            bottomTrailingRadius: easy > 0 ? 0 : 5, topTrailingRadius: 5,
                            style: .continuous)
                            .fill(NB.ember1)
                            .frame(height: 104 * hard / scale)
                    }
                    if easy > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: hard > 0 ? 0 : 5, bottomLeadingRadius: 5,
                            bottomTrailingRadius: 5, topTrailingRadius: hard > 0 ? 0 : 5,
                            style: .continuous)
                            .fill(NB.lime1.opacity(0.53))
                            .frame(height: 104 * easy / scale)
                    }
                    if easy == 0 && hard == 0 {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(NB.white.opacity(0.06))
                            .frame(height: 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
        .frame(height: 104, alignment: .bottom)
    }
}

/// Hourly step columns on the user-day clock. The tallest hour that also has
/// a named session is marked amber.
struct TrainingStepBars: View {
    let bins: [Double]
    var sessionIndex: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let peak = max(1, bins.max() ?? 1)
            let gap: CGFloat = 4
            let w = max(4, (geo.size.width - gap * CGFloat(max(0, bins.count - 1))) / CGFloat(max(1, bins.count)))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(bins.enumerated()), id: \.offset) { i, value in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(i == sessionIndex ? NB.ember1
                              : value > 0 ? NB.lime1.opacity(0.35 + 0.65 * (value / peak))
                              : NB.white.opacity(0.08))
                        .frame(width: w, height: max(2, geo.size.height * value / peak))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct TrainingIngredient: Identifiable {
    var id: String { label }
    let label: String
    let value: String
    var tint: Color = NB.lime1
}

struct TrainingIngredientsCard: View {
    let trailing: String
    let rows: [TrainingIngredient]
    var note: String? = nil

    var body: some View {
        CardBlock(title: L("INGREDIENTS"), trailing: trailing, trailingIsDot: true) {
            VStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { Hairline() }
                    HStack {
                        Text(row.label)
                            .font(NBFont.ui(500, 12)).tracking(0.06 * 12)
                            .foregroundStyle(NB.text1)
                        Spacer(minLength: 0)
                        Text(row.value)
                            .font(NBFont.dot(700, 14)).tracking(0.02 * 14)
                            .foregroundStyle(row.tint)
                    }
                }
            }
            if let note {
                Text(note)
                    .font(NBFont.ui(400, 11)).foregroundStyle(NB.text3Prod)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// WEEK and MONTH lead with this instead of a number: one column a user day for the load
/// that day reached, against the target that day was set. The target is a tick across the
/// column and the optimal zone a faint band behind it, so "did I hit it" is read column by
/// column rather than from one average. A finished day's column wears its band's colour —
/// light, steady, heavy — and today's is drawn hollow, because it is still counting.
///
/// ⚠️ A day with no load is a dotted slot, never a zero column (F2 rule 05).
struct TrainingTargetBars: View {
    let days: [TrainingDayFacts]
    var height: CGFloat = 150

    private static let ceiling = 21.0

    var body: some View {
        VitalsChartProbe(
            series: .bins(probeBins),
            tint: NB.lime1,
            height: height,
            trailingInset: VitalsScaleRail.gutter,
            accessibilityTitle: L("LOAD VS TARGET BY DAY"),
            accessibilityName: "training.probe.targetBars"
        ) { _ in
            HStack(spacing: VitalsScaleRail.gap) {
                GeometryReader { geo in
                    let count = max(days.count, 1)
                    let spacing: CGFloat = days.count > 10 ? 2 : 6
                    let width = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
                    let radius = min(width / 2, 6)
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                            column(day, width: width, radius: radius, height: geo.size.height)
                        }
                    }
                }
                VitalsScaleRail(labels: ["21", "14", "7", "0"], tint: NB.lime1)
            }
        }
    }

    private func fraction(_ value: Double) -> CGFloat {
        CGFloat(min(Self.ceiling, max(0, value)) / Self.ceiling)
    }

    private func tint(_ day: TrainingDayFacts, load: Double) -> Color {
        switch TrainingWindowMath.band(load: load, zone: day.zone) {
        case .light:        NB.lime1.opacity(0.45)
        case .steady:       NB.lime1
        case .heavy, .over: NB.ember1
        case .unknown:      NB.lime1.opacity(0.7)
        }
    }

    @ViewBuilder
    private func column(_ day: TrainingDayFacts, width: CGFloat, radius: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if let zone = day.zone {
                // The zone behind the column: the stretch the day was meant to land in.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(NB.lime2.opacity(0.16))
                    .frame(height: max(2, height * (fraction(zone.upperBound) - fraction(zone.lowerBound))))
                    .offset(y: -height * fraction(zone.lowerBound))
            }
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundStyle(NB.hairline)
                .opacity(day.load == nil ? 1 : 0)
            if let load = day.load {
                let bar = RoundedRectangle(cornerRadius: radius, style: .continuous)
                if day.isOpen {
                    // Today is still counting: hollow, so it is not read as a finished day.
                    bar.fill(NB.lime1.opacity(0.18))
                        .overlay(bar.stroke(NB.lime1, lineWidth: 1.5))
                        .frame(height: max(radius * 2, height * fraction(load)))
                } else {
                    bar.fill(tint(day, load: load))
                        .frame(height: max(2, height * fraction(load)))
                }
            }
            if let target = day.target {
                // The target as a tick across the whole slot, so a column that stopped
                // short of it and one that overshot it are both read against the same line.
                Rectangle()
                    .fill(NB.limePale)
                    .frame(height: 2)
                    .offset(y: -height * fraction(target))
            }
        }
        .frame(width: width, height: height)
    }

    static var legend: VitalsChartLegend {
        VitalsChartLegend(
            items: [
                .init(text: L("LOAD · PER DAY"), tint: NB.lime1),
                .init(text: L("TARGET"), tint: NB.limePale),
                .init(text: L("ZONE"), tint: NB.lime2, isArea: true),
            ],
            trailing: L("DOTTED · NO RECORD"),
            trailingTint: NB.white.opacity(0.45))
    }

    private var probeBins: [VitalsProbeMath.Bin] {
        let ranges = VitalsProbeMath.equalSlots(count: days.count)
        return zip(days, ranges).map { day, range in
            let clock = MetricWindowMath.slotLabel(day.day.start, count: days.count)
            guard let load = day.load else {
                return .init(start: range.start, end: range.end, yFraction: nil,
                             text: VitalsProbeCopy.gap(clock), vacant: true)
            }
            let target = day.target.map { L("TARGET %@", Fmt.load($0)) } ?? L("NO TARGET")
            return .init(start: range.start, end: range.end,
                         yFraction: 1 - fraction(load),
                         text: VitalsProbeCopy.line(clock, L("%@ · %@", Fmt.load(load), target)))
        }
    }
}
