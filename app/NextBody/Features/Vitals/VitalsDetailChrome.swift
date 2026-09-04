import SwiftUI

// 04 · 8 大指标二级页 · the shared anatomy. The board draws one page eight times: a hero
// whose big read-out owns its own line, a chart on a fixed ruler, a distribution, and two
// stat tiles. Everything here is chrome — not one of these views knows a metric's name.
//
// The board's `! ZERO TEXT WRAP GUARANTEE` is the reason every number below carries
// `lineLimit(1)` and a minimum scale factor: 8,420 and 2,140 and +0.2 °C all have to hold
// one line on a 375-wide phone, and a wrapped read-out is the defect the board was drawn
// against.

/// The hero. `value` is the only thing on its line — the unit sits beside it, the range under
/// it, and the two facts that qualify it below a hairline.
struct VitalsHero: View {
    /// What measured it, not what it means.
    let sensor: String
    let badge: VitalsBadge.Model?
    /// nil is ——. F2 rule 05 · a number that is not there is never a zero.
    let value: String?
    let unit: String?
    let tint: Color
    let gauge: VitalsGauge.Model?
    let footLeft: String
    let footRight: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(sensor)
                    .font(NBFont.ui(400, 10)).tracking(0.12 * 10)
                    .foregroundStyle(NB.white.opacity(0.45))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let badge { VitalsBadge(model: badge) }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value ?? Fmt.dash)
                    .font(NBFont.dot(800, 52)).tracking(-0.04 * 52)
                    .foregroundStyle(value == nil ? NB.text3Prod : tint)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(NBFont.ui(600, 14))
                        .foregroundStyle(value == nil ? NB.text3Prod : NB.text1)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if let gauge { VitalsGauge(model: gauge, tint: tint) }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(footLeft)
                    .font(NBFont.ui(400, 10))
                    .foregroundStyle(NB.white.opacity(0.50))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let footRight {
                    Text(footRight)
                        .font(NBFont.ui(400, 10))
                        .foregroundStyle(tint)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(.top, 8)
            .overlay(alignment: .top) {
                Rectangle().fill(NB.white.opacity(0.06)).frame(height: 1)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sensor)
        .accessibilityValue(value.map { "\($0) \(unit ?? "")" } ?? "no reading")
    }
}

/// The hero's state pill. Never a colour of its own: it borrows the metric's, so the page
/// reads as one instrument rather than a traffic light.
struct VitalsBadge: View {
    struct Model {
        let text: String
        let tint: Color
    }
    let model: Model

    var body: some View {
        Text(model.text)
            .font(NBFont.ui(600, 10))
            .foregroundStyle(model.tint)
            .lineLimit(1)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(model.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: NB.R.key - 3, style: .continuous))
    }
}

/// The range the read-out sits inside: a 4 pt rail with the day's low at one end and its
/// peak at the other. The marker is where `now` fell between them — never a target, never a
/// score. With no low or peak on record the rail is empty rather than full.
struct VitalsGauge: View {
    struct Model {
        let lowLabel: String
        let nowLabel: String
        let highLabel: String
        /// 0…1, or nil when the day has no span to place the reading in.
        let fraction: Double?
    }
    let model: Model
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(NB.white.opacity(0.08))
                    if let f = model.fraction {
                        Capsule()
                            .fill(LinearGradient(colors: [tint.opacity(0.55), tint],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(3, g.size.width * min(1, max(0, f))))
                    }
                }
            }
            .frame(height: 4)

            HStack(spacing: 6) {
                Text(model.lowLabel)
                    .font(NBFont.ui(400, 9))
                    .foregroundStyle(NB.white.opacity(0.40))
                Spacer(minLength: 0)
                Text(model.nowLabel)
                    .font(NBFont.ui(500, 9))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(model.highLabel)
                    .font(NBFont.ui(400, 9))
                    .foregroundStyle(NB.white.opacity(0.40))
            }
            .lineLimit(1)
        }
        .accessibilityHidden(true)
    }
}

/// The clock under a chart. `04 · 10 · 16 · 22` on a day page, the night's own two ends on a
/// night page — and NOW in the metric's colour when the last mark is the live one.
struct VitalsAxis: View {
    let labels: [String]
    /// True when the final label is "now" rather than a clock reading.
    var highlightsLast = true
    let tint: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                let last = highlightsLast && i == labels.count - 1
                Text(label)
                    .font(NBFont.ui(last ? 500 : 400, 9))
                    .foregroundStyle(last ? tint : NB.white.opacity(0.45))
                    .lineLimit(1)
                if i < labels.count - 1 { Spacer(minLength: 0) }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Where the day went, as one bar of shares plus its legend. The shares are minutes or
/// kcal, not percentages of a target: the bar is always full because the day always
/// happened, and a band with no minutes in it is simply absent from both bar and legend.
struct VitalsSplit: View {
    struct Band: Identifiable {
        var id: String { name }
        let name: String
        let tint: Color
        let share: Double
        /// What the legend prints after the name — "52%" or "3H 10M".
        let detail: String
    }
    let bands: [Band]

    private var present: [Band] { bands.filter { $0.share > 0 } }
    private var total: Double { present.reduce(0) { $0 + $1.share } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if present.isEmpty || total <= 0 {
                Text(L("NO TICKS YET"))
                    .font(NBFont.dot(500, 10)).tracking(0.05 * 10)
                    .foregroundStyle(NB.macroValue)
            } else {
                GeometryReader { g in
                    HStack(spacing: 3) {
                        ForEach(present) { b in
                            Capsule()
                                .fill(b.tint)
                                .frame(width: max(2, (g.size.width - 3 * CGFloat(present.count - 1)) * b.share / total))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 8)

                // 04B · the legend is a fixed-width lane per band so four of them line up
                // across the card whatever their numbers read.
                HStack(spacing: 6) {
                    ForEach(present) { b in
                        HStack(spacing: 4) {
                            Circle().fill(b.tint).frame(width: 5, height: 5)
                            Text("\(b.name) \(b.detail)")
                                .font(NBFont.ui(400, 9))
                                .foregroundStyle(NB.text2)
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// The board's two closing tiles. Always exactly two, always the same height — they are the
/// page's footnotes, and a single wide one would read as a third conclusion.
struct VitalsStatPair: View {
    struct Model: Identifiable {
        var id: String { label }
        let label: String
        let value: String?
        let unit: String?
        let foot: String
        /// nil keeps the value white — the tint is spent on the one figure that earns it.
        let tint: Color?
    }
    let left: Model
    let right: Model

    var body: some View {
        HStack(spacing: 10) {
            tile(left)
            tile(right)
        }
        .frame(width: NB.Layout.contentWidth)
    }

    private func tile(_ m: Model) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(m.label)
                .font(NBFont.ui(400, 9)).tracking(0.1 * 9)
                .foregroundStyle(NB.white.opacity(0.45))
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(m.value ?? Fmt.dash)
                    .font(NBFont.dot(700, 18))
                    .foregroundStyle(m.value == nil ? NB.text3Prod : (m.tint ?? NB.text1))
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let unit = m.unit, m.value != nil {
                    Text(unit)
                        .font(NBFont.ui(500, 9))
                        .foregroundStyle(NB.white.opacity(0.40))
                }
            }
            Text(m.foot)
                .font(NBFont.ui(400, 9))
                .foregroundStyle(m.value == nil ? NB.text3Prod : (m.tint ?? NB.text2))
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSkin()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.label)
        .accessibilityValue(m.value.map { "\($0) \(m.unit ?? ""), \(m.foot)" } ?? "no reading, \(m.foot)")
    }
}

/// What a chart card says instead of drawing, when the day has no ticks to draw. It keeps
/// the card's frame — 04B F1/F5 · an empty page, not a zeroed one.
struct VitalsChartEmpty: View {
    let line: String
    let sub: String
    var height: CGFloat = 124

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(line)
                .font(NBFont.dot(600, 11)).tracking(0.14 * 11)
                .foregroundStyle(NB.white.opacity(0.55))
            Text(sub)
                .font(NBFont.dot(500, 10)).tracking(0.05 * 10)
                .foregroundStyle(NB.macroValue)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
    }
}
