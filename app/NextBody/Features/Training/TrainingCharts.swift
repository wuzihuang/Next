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

/// A cumulative line on the user-day clock, never a rate. It only ever rises.
/// The dashed tail after NOW is the forecast. Gaps stay flat.
struct CumulativeCurve: View {
    let target: Double
    let now: Double
    var points: [LoadPoint] = []
    var day: UserDay = UserDay.containing(Date())
    /// Gaps in hours since the user-day cut. Dashed, ember, never interpolated.
    var gaps: [(Double, Double)] = []

    private static let boardPath: [(Double, Double)] = [
        (0, 0), (1, 0.1), (2.25, 1.9), (3.5, 2.6), (6.1, 3.3),
        (6.8, 5.3), (8.5, 6.2), (9.75, 8.1), (11, 10.2),
    ]

    private var path: [(Double, Double)] {
        guard !points.isEmpty else { return Self.boardPath }
        return points.map { ($0.ts.timeIntervalSince(day.start) / 3600, $0.load) }
    }

    private func pt(_ x: Double, _ y: Double, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * x / 24, y: size.height - 12 - CGFloat(y / 21) * (size.height - 24))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let size = geo.size
            let points = self.path
            let nowX = points.last?.0 ?? UserDay.hours(Date(), in: day)
            let nowPoint = pt(nowX, now, size)
            let targetY = h - 12 - CGFloat(target / 21) * (h - 24)

            ZStack(alignment: .topLeading) {
                Rectangle().fill(NB.lime1.opacity(0.12))
                    .frame(height: 14.3)
                    .offset(y: targetY - 7)
                Path { p in p.move(to: CGPoint(x: 0, y: targetY)); p.addLine(to: CGPoint(x: w, y: targetY)) }
                    .stroke(NB.limePale.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                Path { p in p.move(to: CGPoint(x: 0, y: h - 12)); p.addLine(to: CGPoint(x: w, y: h - 12)) }
                    .stroke(NB.white.opacity(0.10), lineWidth: 1)

                Path { p in
                    p.move(to: pt(0, 0, size))
                    for (x, y) in points.dropFirst() { p.addLine(to: pt(x, y, size)) }
                    p.addLine(to: nowPoint)
                    p.addLine(to: CGPoint(x: nowPoint.x, y: h - 12))
                    p.addLine(to: CGPoint(x: 0, y: h - 12))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [NB.lime1.opacity(0.28), NB.lime1.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))

                Path { p in
                    p.move(to: pt(0, 0, size))
                    for (x, y) in points.dropFirst() { p.addLine(to: pt(x, y, size)) }
                    p.addLine(to: nowPoint)
                }
                .stroke(NB.lime1, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                Path { p in p.move(to: nowPoint); p.addLine(to: pt(min(23.5, nowX + 2.1), target, size)) }
                    .stroke(NB.lime2, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5]))

                ForEach(Array(gaps.enumerated()), id: \.offset) { _, g in
                    let y = points.last(where: { $0.0 <= g.0 })?.1 ?? 0
                    let a = pt(g.0, y, size), b = pt(g.1, y, size)
                    Path { p in p.move(to: a); p.addLine(to: b) }
                        .stroke(NB.ember1, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 7]))
                    Circle().fill(NB.ember1).frame(width: 6.8, height: 6.8).position(a)
                    Circle().fill(NB.ember1).frame(width: 6.8, height: 6.8).position(b)
                    Text(L("%dH GAP", Int((g.1 - g.0).rounded())))
                        .font(NBFont.dot(500, 10)).tracking(0.16 * 10)
                        .foregroundStyle(NB.ember1.opacity(0.85))
                        .position(x: (a.x + b.x) / 2, y: a.y + 16)
                }

                Circle().fill(NB.carbon2).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(NB.lime1, lineWidth: 2.5))
                    .position(nowPoint)
                Circle().fill(NB.limePale).frame(width: 7, height: 7)
                    .position(pt(min(23.5, nowX + 2.1), target, size))

                Text(L("TARGET %@", String(format: "%.1f", target)))
                    .font(NBFont.dot(700, 11)).tracking(0.02 * 11)
                    .foregroundStyle(NB.limePale)
                    .offset(x: 4, y: targetY - 18)
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
                let total = max(1, easy + hard)
                VStack(spacing: 0) {
                    if hard > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 5, bottomLeadingRadius: easy > 0 ? 0 : 5,
                            bottomTrailingRadius: easy > 0 ? 0 : 5, topTrailingRadius: 5,
                            style: .continuous)
                            .fill(NB.ember1)
                            .frame(height: max(5, 104 * hard / total))
                    }
                    if easy > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: hard > 0 ? 0 : 5, bottomLeadingRadius: 5,
                            bottomTrailingRadius: 5, topTrailingRadius: hard > 0 ? 0 : 5,
                            style: .continuous)
                            .fill(NB.lime1.opacity(0.53))
                            .frame(height: max(5, 104 * easy / total))
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
    var zone: ClosedRange<Double>? = nil

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
        switch TrainingWindowMath.band(load: load, zone: day.zone ?? zone) {
        case .light:  return NB.lime1.opacity(0.28)
        case .steady: return NB.lime1.opacity(0.72)
        case .heavy:  return NB.lime1
        case .over:   return NB.ember1
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
        }
    }
}
