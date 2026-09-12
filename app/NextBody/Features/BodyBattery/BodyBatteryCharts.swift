import SwiftUI

/// One point per day on a 0–100 ruler, drawn as a line so WEEK and MONTH read the
/// same way DAY's curve does. A day without a morning reading is a hole in the line,
/// bridged by a dashed segment — never a dim zero. Today carries the ringed lime dot.
///
/// ⚠️ Points sit at the centre of an equal-width column, `(i + 0.5) / count`, so a label
/// row of `maxWidth: .infinity` columns lines up under them without any edge arithmetic.
struct BodyBatteryDayLine: View {
    let values: [Int?]
    /// The dashed rule the window's typical morning sits on. nil draws no rule.
    let average: Double?
    var todayIndex: Int? = nil

    private static let pad: CGFloat = 8

    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty else { return }
            let plot = max(0, size.height - Self.pad * 2)
            let slot = size.width / CGFloat(values.count)
            func y(_ value: Double) -> CGFloat {
                size.height - Self.pad - CGFloat(min(100, max(0, value))) / 100 * plot
            }
            func point(_ index: Int, _ value: Int) -> CGPoint {
                CGPoint(x: (CGFloat(index) + 0.5) * slot, y: y(Double(value)))
            }

            for rule in [30.0, 70.0] {
                ctx.fill(Path(CGRect(x: 0, y: y(rule), width: size.width, height: 1)),
                         with: .color(NB.white.opacity(0.06)))
            }
            ctx.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                     with: .color(NB.white.opacity(0.10)))
            // ⚠️ A day with no morning reading gets a mark on the floor, never a point at 0 —
            // and without it a window that has nothing yet is an empty box rather than a
            // field waiting for readings.
            for (i, value) in values.enumerated() where value == nil {
                let w = min(14, slot * 0.5)
                ctx.fill(Path(CGRect(x: (CGFloat(i) + 0.5) * slot - w / 2, y: size.height - 3,
                                     width: w, height: 2)),
                         with: .color(NB.white.opacity(0.16)))
            }

            let runs = Self.runs(values).map { $0.map { point($0.index, $0.value) } }
            guard !runs.isEmpty else { return }

            // The wash under the line gives a flat week a body. It is anchored to the run's
            // own crest, so a line riding high never fills the whole card, and it stops at
            // the run's ends, so a missing morning stays a hole in the fill too.
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

            for (i, run) in runs.enumerated() {
                if run.count > 1 {
                    var line = Path()
                    line.move(to: run[0])
                    for p in run.dropFirst() { line.addLine(to: p) }
                    ctx.stroke(line, with: .color(NB.lime1),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if i + 1 < runs.count, let tail = run.last, let head = runs[i + 1].first {
                    var gap = Path()
                    gap.move(to: tail)
                    gap.addLine(to: head)
                    ctx.stroke(gap, with: .color(NB.lime1.opacity(0.28)),
                               style: StrokeStyle(lineWidth: 1.2, dash: [2, 4]))
                }
            }

            if let average {
                var rule = Path()
                rule.move(to: CGPoint(x: 0, y: y(average)))
                rule.addLine(to: CGPoint(x: size.width, y: y(average)))
                ctx.stroke(rule, with: .color(NB.limePale.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }

            // A run of one has no line at all, so its dot is the reading.
            let r: CGFloat = values.count > 14 ? 1.8 : 2.6
            for p in runs.flatMap({ $0 }) {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(NB.lime1.opacity(0.9)))
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

    /// Uninterrupted stretches of days that published a reading. An empty slot ends a run.
    static func runs(_ values: [Int?]) -> [[(index: Int, value: Int)]] {
        var out: [[(index: Int, value: Int)]] = []
        var run: [(index: Int, value: Int)] = []
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
}
