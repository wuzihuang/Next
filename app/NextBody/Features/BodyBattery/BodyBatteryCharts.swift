import SwiftUI

/// Seven wake-peak bars on a 0–100 ruler. Today is lime. An empty day is an
/// empty slot, never a dim zero.
struct BodyBatteryWeekBars: View {
    let values: [Int?]
    let average: Double?
    var todayIndex: Int? = nil

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
                                    .fill(i == todayIndex ? NB.lime1 : NB.lime1.opacity(0.55))
                                    .frame(height: h * CGFloat(min(1, Double(v) / 100)))
                            }
                        }
                        .frame(width: 34, height: h)
                        if i < values.count - 1 { Spacer(minLength: 0) }
                    }
                }
                if let average {
                    Path { p in
                        let y = h - h * CGFloat(min(1, average / 100))
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(NB.limePale.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
            }
            .clipped()
        }
    }
}

/// Thirty heat cells. A missing morning is a dashed empty slot, never a dim zero.
/// Today is lime; the rest scale with the wake peak.
struct BodyBatteryHeatGrid: View {
    let days: [BodyBatteryDayFacts]
    var today: UserDay = UserDay.containing(Date())

    private let cell: CGFloat = 26
    private let gap: CGFloat = 4

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(cell), spacing: gap), count: 10)
        LazyVGrid(columns: columns, spacing: gap) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill(for: day))
                    .overlay {
                        if !day.hasWake {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(NB.white.opacity(0.12),
                                              style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        } else if day.day == today {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(NB.lime1, lineWidth: 1.5)
                        }
                    }
                    .frame(width: cell, height: cell)
            }
        }
        .frame(width: 10 * cell + 9 * gap)
    }

    private func fill(for day: BodyBatteryDayFacts) -> Color {
        guard let wake = day.wake else { return NB.white.opacity(0.04) }
        if day.day == today { return NB.lime1 }
        return NB.lime1.opacity(0.22 + 0.78 * (Double(wake) / 100))
    }
}
