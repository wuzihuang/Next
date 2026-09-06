import SwiftUI

/// RESPONSE's three rolling windows. Day is the last 24 hours; week and month are the
/// last 7 and 30 user days. Not a calendar week or month — the same reason sleep's
/// windows roll (ADR 0008), reopened here for food-response points (ADR 0012).
///
/// ⚠️ Sleep still medians a night. This board means a week: the hero is the arithmetic
/// mean of the daily means. The own daytime median stays the comparison, not the hero.
extension RollingPills {
    var responseHeroSensor: String {
        switch self {
        case .day:   L("RESPONSE · LAST 24H")
        case .week:  L("RESPONSE · LAST 7D")
        case .month: L("RESPONSE · LAST 30D")
        }
    }

    var responseChartTitle: String {
        switch self {
        case .day:          L("FOOD RESPONSE")
        case .week, .month: L("DAILY VS OWN")
        }
    }

    var responseAverageLabel: String {
        switch self {
        case .day:   L("24H MEDIAN POINT")
        case .week:  L("7-DAY AVERAGE")
        case .month: L("30-DAY AVERAGE")
        }
    }
}

// MARK: - week / month bars

/// One bar a user day, height by that day's mean optical point, colour by Below / Near /
/// Above versus the own daytime median. A day with no point is a dotted slot at full
/// height — seven bars with one silently missing cannot be read.
struct ResponseDayBars: View {
    let slots: [MealResponseIndex.DaySlot]
    let ownMedian: Double?
    var tint: Color = NB.compareAmber
    var height: CGFloat = 160

    var body: some View {
        VitalsChartProbe(
            series: .bins(probeBins),
            tint: tint,
            height: height,
            trailingInset: VitalsScaleRail.gutter,
            accessibilityTitle: L("DAILY VS OWN"),
            accessibilityName: "vitals.probe.response.days"
        ) { _ in
            HStack(spacing: VitalsScaleRail.gap) {
                GeometryReader { geo in
                    let count = max(slots.count, 1)
                    let spacing: CGFloat = slots.count > 10 ? 2 : 6
                    let width = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
                    let radius = min(width / 2, 6)
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: radius, style: .continuous)
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                                    .foregroundStyle(NB.hairline)
                                    .opacity(slot.mean == nil ? 1 : 0)
                                if let mean = slot.mean {
                                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                                        .fill(Self.tint(mean: mean, ownMedian: ownMedian, fallback: tint))
                                        .frame(height: max(radius * 2,
                                                           height * CGFloat(Self.fraction(mean, axis: axis))))
                                }
                            }
                            .frame(width: width, height: height)
                        }
                    }
                }

                VitalsScaleRail(labels: railLabels, tint: tint)
            }
        }
    }

    static var legend: VitalsChartLegend {
        VitalsChartLegend(
            items: [
                .init(text: L("BELOW"), tint: NB.ember1),
                .init(text: L("NEAR"), tint: NB.compareAmber),
                .init(text: L("ABOVE"), tint: NB.optimal2),
            ],
            trailing: L("DOTTED · NO RECORD"),
            trailingTint: NB.white.opacity(0.45)
        )
    }

    static func tint(mean: Double, ownMedian: Double?, fallback: Color) -> Color {
        switch MealResponseIndex.Band.of(optical: mean, ownMedian: ownMedian ?? 0) {
        case .below: return NB.ember1
        case .near:  return NB.compareAmber
        case .above: return NB.optimal2
        case nil:    return fallback
        }
    }

    private var axis: ClosedRange<Double> {
        MealResponseIndex.axis(values: slots.compactMap(\.mean), ownMedian: ownMedian)
            ?? 80...120
    }

    private var railLabels: [String] {
        let high = axis.upperBound
        let mid = ownMedian ?? (high + axis.lowerBound) / 2
        return [high, mid, axis.lowerBound].map(MealResponseIndex.pointValue)
    }

    private static func fraction(_ value: Double, axis: ClosedRange<Double>) -> Double {
        let span = axis.upperBound - axis.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0.08, (value - axis.lowerBound) / span))
    }

    private var probeBins: [VitalsProbeMath.Bin] {
        let ranges = VitalsProbeMath.equalSlots(count: slots.count)
        return zip(slots, ranges).map { slot, range in
            let clock = slots.count > 10
                ? "\(Calendar.current.component(.day, from: slot.start))"
                : Fmt.weekday(slot.start)
            if let mean = slot.mean {
                return .init(
                    start: range.start,
                    end: range.end,
                    yFraction: 1 - Self.fraction(mean, axis: axis),
                    text: VitalsProbeCopy.line(clock, MealResponseIndex.pointValue(mean))
                )
            }
            return .init(
                start: range.start,
                end: range.end,
                yFraction: nil,
                text: VitalsProbeCopy.gap(clock),
                vacant: true
            )
        }
    }
}

// MARK: - month heat

/// Thirty user days as a 5 × 6 grid, oldest at the top-left, filling down a column then
/// across. Colour is the day's band versus the own median; an empty day is a dotted cell.
///
/// 探点 stays a horizontal drag (CONTEXT · 探点), so the finger names a column — the five
/// days that share that x — rather than inventing a second axis on this card.
struct ResponseDayHeat: View {
    let slots: [MealResponseIndex.DaySlot]
    let ownMedian: Double?
    var tint: Color = NB.compareAmber
    var height: CGFloat = 160

    private let columns = 6
    private let rows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VitalsChartProbe(
                series: .bins(probeBins),
                tint: tint,
                height: height,
                accessibilityTitle: L("DAILY VS OWN"),
                accessibilityName: "vitals.probe.response.heat"
            ) { probing in
                GeometryReader { geo in
                    let gap: CGFloat = 4
                    let cellW = max(8, (geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns))
                    let cellH = max(8, (geo.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(0..<columns, id: \.self) { col in
                            VStack(spacing: gap) {
                                ForEach(0..<rows, id: \.self) { row in
                                    cell(at: col * rows + row)
                                        .frame(width: cellW, height: cellH)
                                        .opacity(probing ? 0.85 : 1)
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(columnLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(NBFont.ui(400, 9))
                        .foregroundStyle(NB.white.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    static var legend: VitalsChartLegend { ResponseDayBars.legend }

    @ViewBuilder
    private func cell(at index: Int) -> some View {
        let slot = slots.indices.contains(index) ? slots[index] : nil
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundStyle(NB.hairline)
                .opacity(slot?.mean == nil ? 1 : 0)
            if let mean = slot?.mean {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(ResponseDayBars.tint(mean: mean, ownMedian: ownMedian, fallback: tint))
            }
        }
    }

    private var columnLabels: [String] {
        (0..<columns).map { col in
            let index = col * rows
            guard slots.indices.contains(index) else { return "" }
            return String(Calendar.current.component(.day, from: slots[index].start))
        }
    }

    private var probeBins: [VitalsProbeMath.Bin] {
        let ranges = VitalsProbeMath.equalSlots(count: columns)
        return (0..<columns).map { col in
            let days = (0..<rows).compactMap { row -> MealResponseIndex.DaySlot? in
                let index = col * rows + row
                return slots.indices.contains(index) ? slots[index] : nil
            }
            let filled = days.compactMap(\.mean)
            let clock = days.first.map { String(Calendar.current.component(.day, from: $0.start)) } ?? Fmt.dash
            if let mean = MealResponseIndex.mean(filled) {
                return .init(
                    start: ranges[col].start,
                    end: ranges[col].end,
                    yFraction: 0.5,
                    text: VitalsProbeCopy.line(clock, MealResponseIndex.pointValue(mean))
                )
            }
            return .init(
                start: ranges[col].start,
                end: ranges[col].end,
                yFraction: nil,
                text: VitalsProbeCopy.gap(clock),
                vacant: true
            )
        }
    }
}
