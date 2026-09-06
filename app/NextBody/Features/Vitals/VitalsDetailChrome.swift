import SwiftUI

// 04 · 8 大指标二级页 · the shared anatomy. The board draws one page eight times: a hero
// whose big read-out owns its own line, a chart on a fixed ruler, a distribution, and two
// stat tiles. Everything here is chrome — not one of these views knows a metric's name.
//
// The board's `! ZERO TEXT WRAP GUARANTEE` is the reason every number below carries
// `lineLimit(1)` and a minimum scale factor: 8,420 and 2,140 and +0.2 °C all have to hold
// one line on a 375-wide phone, and a wrapped read-out is the defect the board was drawn
// against.

/// The hero. `value` is the only thing on its line — the unit sits beside it, the zone
/// name after that, the dial under it, and the two facts that qualify it below a hairline.
struct VitalsHero: View {
    /// What measured it, not what it means.
    let sensor: String
    /// nil is ——. F2 rule 05 · a number that is not there is never a zero.
    let value: String?
    let unit: String?
    let tint: Color
    let dial: VitalsDial.Model?
    let footLeft: String
    let footRight: String?

    private var figureTint: Color { dial?.zoneTint ?? tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sensor)
                .font(NBFont.ui(400, 10)).tracking(0.12 * 10)
                .foregroundStyle(NB.white.opacity(0.45))
                .lineLimit(1).minimumScaleFactor(0.8)

            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(value ?? Fmt.dash)
                    .font(NBFont.dot(800, 52)).tracking(-0.04 * 52)
                    .foregroundStyle(value == nil ? NB.text3Prod : figureTint)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(NBFont.ui(600, 14))
                        .foregroundStyle(value == nil ? NB.text3Prod : NB.text1)
                        .lineLimit(1)
                }
                if let name = dial?.zoneName, value != nil {
                    Text("· \(name)")
                        .font(NBFont.ui(600, 14))
                        .foregroundStyle(figureTint)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }

            if let dial { VitalsDial(model: dial) }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(footLeft)
                    .font(NBFont.ui(400, 10))
                    .foregroundStyle(NB.white.opacity(0.50))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let footRight {
                    Text(footRight)
                        .font(NBFont.ui(400, 10))
                        .foregroundStyle(NB.white.opacity(0.35))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(.top, 10)
            .overlay(alignment: .top) {
                Rectangle().fill(NB.white.opacity(0.06)).frame(height: 1)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("vitals.hero")
        .accessibilityLabel(sensor)
        .accessibilityValue(accessValue)
    }

    private var accessValue: String {
        guard let value else { return "no reading" }
        let zone = dial?.zoneName.map { ", \($0)" } ?? ""
        return "\(value) \(unit ?? "")\(zone)"
    }
}

/// Named zones on a fixed ruler. The occupied zone lights; a white needle marks the
/// reading. This is not a fill bar and not a target — the scale is the conclusion.
struct VitalsDial: View {
    struct Zone {
        let name: String
        let tint: Color
        let weight: Double
    }

    struct Model {
        let zones: [Zone]
        /// 0…1 on the full scale, or nil when there is no reading to place.
        let fraction: Double?
        let activeIndex: Int?
        /// The interior cuts the zones were built from, kept so the model can place *any*
        /// value and not only the one reading the hero prints. This is what lets a chart
        /// colour its marks off the same ruler the dial is drawn from — a capsule cannot
        /// come out red while the dial above it still lights STEADY.
        var cuts: [Double] = []

        var zoneName: String? {
            guard let activeIndex, zones.indices.contains(activeIndex) else { return nil }
            let name = zones[activeIndex].name
            return name.isEmpty ? nil : name
        }

        var zoneTint: Color? {
            guard let activeIndex, zones.indices.contains(activeIndex) else { return nil }
            return zones[activeIndex].tint
        }

        var showsLabels: Bool { zones.contains { !$0.name.isEmpty } }

        /// The colour this ruler gives `value`, or nil when there are no cuts to read it
        /// against — an unscored metric keeps its own accent.
        func tint(for value: Double) -> Color? {
            guard !cuts.isEmpty, !zones.isEmpty else { return nil }
            let i = min(zones.count - 1, VitalsDialMath.activeIndex(value: value, cuts: cuts))
            return zones[i].tint
        }

        /// The zone colours in equal bands, for a legend swatch. ⚠️ Not `stops(low:high:)`
        /// over the whole ruler: on a 40–160 heart field the resting zone owns two thirds of
        /// the scale, so a swatch drawn to proportion is a blue chip with three slivers on
        /// top. A key shows the colours, not their widths.
        ///
        /// ⚠️ Reversed, because the swatch is drawn top-down like the field it keys: the
        /// top zone belongs at the top, next to the marks that reach it.
        var legendStops: [Gradient.Stop]? {
            guard zones.count > 1 else { return nil }
            let step = 1.0 / Double(zones.count)
            return zones.reversed().enumerated().flatMap { i, zone in
                [Gradient.Stop(color: zone.tint, location: Double(i) * step),
                 Gradient.Stop(color: zone.tint, location: Double(i + 1) * step)]
            }
        }

        /// Hard-edged gradient stops for a mark spanning `low…high`, top-down. A mark inside
        /// one zone degenerates to two stops of the same colour, which is a solid fill.
        func stops(low: Double, high: Double) -> [Gradient.Stop]? {
            guard !cuts.isEmpty, !zones.isEmpty else { return nil }
            let runs = VitalsDialMath.zoneRuns(low: low, high: high, cuts: cuts)
            guard !runs.isEmpty else { return nil }
            return runs.flatMap { run -> [Gradient.Stop] in
                let tint = zones[min(zones.count - 1, run.zone)].tint
                // Both ends of the run carry its own colour, so the next run starts at the
                // same location with a different one: the crossing is a line, not a blend.
                return [.init(color: tint, location: run.from),
                        .init(color: tint, location: run.to)]
            }
        }
    }

    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                let layout = row(in: g.size.width)
                ZStack(alignment: .topLeading) {
                    HStack(spacing: layout.gap) {
                        ForEach(Array(model.zones.enumerated()), id: \.offset) { i, zone in
                            let on = model.activeIndex == i
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(on ? zone.tint : zone.tint.opacity(0.14))
                                .frame(width: layout.widths[i], height: 9)
                        }
                    }
                    .padding(.top, 9)

                    if let fraction = model.fraction {
                        let x = min(g.size.width - 4, max(4, g.size.width * CGFloat(fraction)))
                        VStack(spacing: 0) {
                            Capsule().fill(NB.white).frame(width: 8, height: 4)
                            Capsule().fill(NB.white).frame(width: 2, height: 22)
                        }
                        .frame(width: 8)
                        .offset(x: x - 4)
                    }
                }
            }
            .frame(height: 26)

            if model.showsLabels {
                GeometryReader { g in
                    let layout = row(in: g.size.width)
                    HStack(alignment: .top, spacing: layout.gap) {
                        ForEach(Array(model.zones.enumerated()), id: \.offset) { i, zone in
                            let on = model.activeIndex == i
                            Text(zone.name)
                                .font(NBFont.ui(on ? 500 : 400, 9))
                                .foregroundStyle(on ? zone.tint : NB.white.opacity(0.32))
                                .lineLimit(1).minimumScaleFactor(0.65)
                                .frame(width: layout.widths[i], alignment: .leading)
                        }
                    }
                }
                .frame(height: 12)
            }
        }
        .accessibilityHidden(true)
    }

    private func row(in width: CGFloat) -> (gap: CGFloat, widths: [CGFloat]) {
        let gap: CGFloat = 3
        let count = model.zones.count
        let usable = width - gap * CGFloat(max(0, count - 1))
        let total = CGFloat(model.zones.reduce(0) { $0 + max(0.001, $1.weight) })
        let widths: [CGFloat] = model.zones.map { max(2, usable * CGFloat($0.weight) / total) }
        return (gap, widths)
    }
}

/// The vertical ruler, standing beside the field instead of inside it.
///
/// ⚠️ The whole point of the rail is that nothing is printed over the data. A number in the
/// field is read against whatever the curve happens to be doing underneath it, which is how
/// `MAX 142` came to sit on top of the resting-band caption. Charts that adopt the rail
/// shrink their own canvas by `gutter`, and the clock under them is inset by the same — or
/// its last mark lands under the rail rather than under the window's last minute.
struct VitalsScaleRail: View {
    /// Top of the ruler first, the way it is read. Three marks: high, middle, low.
    let labels: [String]
    let tint: Color

    static let width: CGFloat = 34
    static let gap: CGFloat = 8
    static var gutter: CGFloat { width + gap }
    /// How far the tick pokes back into the gap, towards the field it measures.
    private static let tick: CGFloat = 8

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                    let fraction = labels.count > 1
                        ? Double(i) / Double(labels.count - 1)
                        : 0
                    let y = g.size.height * fraction

                    Rectangle()
                        .fill(NB.white.opacity(0.28))
                        .frame(width: Self.tick, height: 1)
                        .offset(x: -Self.gap - 3, y: y)

                    Text(label)
                        .font(NBFont.ui(500, 9))
                        .foregroundStyle(NB.white.opacity(0.52))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        // Half the cap height, so the label reads level with its own tick
                        // rather than hanging below it.
                        .offset(x: 0, y: y - 6)
                }
            }
        }
        .frame(width: Self.width)
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

/// What the marks in the field mean, said under the field. This row is where the captions
/// that used to be plates on top of the trace went: the resting band's name, the capsule's
/// own width in minutes, and the one extreme worth printing.
struct VitalsChartLegend: View {
    struct Item: Identifiable {
        var id: String { text }
        let text: String
        let tint: Color
        /// A block swatch reads as an area — the reference band. A bar reads as one mark.
        var isArea = false
        /// Given the zone colours, the swatch wears them instead of a flat tint, so it looks
        /// like the marks it is naming. The zones' *names* are not repeated here — the hero
        /// dial directly above the chart is already that key.
        var stops: [Gradient.Stop]?
    }
    let items: [Item]
    /// The extreme, printed once at the end of the row instead of over the point it names.
    var trailing: String?
    var trailingTint: Color = NB.white

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.stops.map {
                            AnyShapeStyle(LinearGradient(stops: $0, startPoint: .top,
                                                         endPoint: .bottom))
                        } ?? AnyShapeStyle(item.tint.opacity(item.isArea ? 0.14 : 0.85)))
                        .frame(width: item.isArea ? 12 : 3, height: 11)
                    Text(item.text)
                        .font(NBFont.ui(400, 9))
                        .foregroundStyle(NB.white.opacity(0.50))
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(NBFont.ui(500, 9))
                    .foregroundStyle(trailingTint)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(.top, 9)
        .overlay(alignment: .top) {
            Rectangle().fill(NB.white.opacity(0.06)).frame(height: 1)
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
    var height: CGFloat = 160
    var subLineLimit: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(line)
                .font(NBFont.dot(600, 11)).tracking(0.14 * 11)
                .foregroundStyle(NB.white.opacity(0.55))
            Text(sub)
                .font(NBFont.dot(500, 10)).tracking(0.05 * 10)
                .foregroundStyle(NB.macroValue)
                .lineLimit(subLineLimit).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
    }
}
