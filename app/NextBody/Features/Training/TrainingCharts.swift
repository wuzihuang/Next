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

                ForEach(Array(data.gaps.enumerated()), id: \.offset) { _, gap in
                    let start = size.width * TrainingWindowMath.dayFraction(gap.start, day: day)
                    let end = size.width * TrainingWindowMath.dayFraction(gap.end, day: day)
                    Rectangle().fill(NB.ember1.opacity(0.09))
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(NB.ember1.opacity(0.5)).frame(height: 2)
                        }
                        .frame(width: max(0, end - start), height: size.height - 24)
                        .offset(x: start, y: 12)
                }

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

/// Seven (or N) daily loads. A nil slot is an empty track, never a zero bar.
struct TrainingWeekBars: View {
    let values: [Double?]
    let average: Double?
    var heavyIndex: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(values.indices, id: \.self) { i in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: 0x16161B))
                            if let v = values[i] {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(i == heavyIndex ? NB.ember1
                                          : i == values.count - 1 ? NB.lime1 : NB.lime1.opacity(0.55))
                                    .frame(height: h * CGFloat(min(1, v / 21)))
                            }
                        }
                        .frame(width: 34, height: h)
                        if i < values.count - 1 { Spacer(minLength: 0) }
                    }
                }
                if let average {
                    Path { p in
                        let y = h - h * CGFloat(min(1, average / 21))
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(NB.limePale.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
            }
            .clipped()
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

/// Thirty heat cells. A missing day is a dashed empty slot, never a dim zero.
struct TrainingHeatGrid: View {
    let days: [TrainingDayFacts]
    private let cell: CGFloat = 26
    private let gap: CGFloat = 4

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(cell), spacing: gap), count: 10)
        LazyVGrid(columns: columns, spacing: gap) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill(for: day))
                    .overlay {
                        if day.load == nil {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(NB.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .frame(width: cell, height: cell)
            }
        }
        .frame(width: 10 * cell + 9 * gap)
    }

    private func fill(for day: TrainingDayFacts) -> Color {
        guard let load = day.load else { return NB.white.opacity(0.04) }
        switch TrainingWindowMath.band(load: load, zone: day.zone) {
        case .light:  return NB.lime1.opacity(0.28)
        case .steady: return NB.lime1.opacity(0.72)
        case .heavy:  return NB.lime1
        case .over:   return NB.ember1
        case .unknown: return NB.text3Prod.opacity(0.4)
        }
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
