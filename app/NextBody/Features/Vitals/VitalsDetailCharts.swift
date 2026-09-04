import SwiftUI

// 04 · 8 大指标二级页 · the five chart shapes the eight pages are drawn from. Every one of
// them takes the band's own ticks and nothing else: there is no smoothing pass, no
// interpolation across a gap, and no rescaling of the ruler to flatter a quiet day.
//
// The ruler is fixed and named on the card (「FIXED 40–160 BPM」) for the same reason 08's
// curve names its own: a chart that rescales itself makes every day look identical.

/// A caption on a carbon plate, the way the board draws its `MAX 142` badge. Without the
/// plate a label inside the field is read against whatever the curve happens to be doing
/// underneath it — the resting-band caption sat directly under the line and lost.
private func plate(_ ctx: inout GraphicsContext, _ text: Text, at point: CGPoint,
                   in size: CGSize, anchor: UnitPoint = .topLeading) {
    let resolved = ctx.resolve(text)
    let measured = resolved.measure(in: size)
    let origin = CGPoint(x: anchor == .center ? point.x - measured.width / 2 : point.x,
                         y: anchor == .center ? point.y - measured.height / 2 : point.y)
    ctx.fill(Path(roundedRect: CGRect(x: origin.x - 3, y: origin.y - 1.5,
                                      width: measured.width + 6, height: measured.height + 3),
                  cornerRadius: 3),
             with: .color(NB.carbon4.opacity(0.94)))
    ctx.draw(resolved, at: origin, anchor: .topLeading)
}

/// The exact window a chart is drawn across, plus the clock printed under it.
struct VitalsWindow {
    let start: Date
    let span: TimeInterval
    let labels: [String]
    /// True when the last label is NOW rather than a clock reading.
    let endsNow: Bool

    var range: VitalsTimelineRange {
        VitalsTimelineRange(start: start, end: start.addingTimeInterval(span))
    }

    static func rolling24Hours(endingAt now: Date) -> VitalsWindow {
        let range = VitalsTimelinePolicy.rolling24Hours(endingAt: now)
        return make(range: range, endsNow: true)
    }

    static func userDay(_ day: UserDay, now: Date) -> VitalsWindow {
        let range = VitalsTimelinePolicy.userDay(start: day.start, end: day.end, now: now)
        return make(range: range, endsNow: now >= day.start && now < day.end)
    }

    /// The night the band recorded, clock at both ends. Falls back to the day window when
    /// the row carries no sleep_start / wake_at — a night whose ends nobody measured.
    static func night(start: Date?, end: Date?, fallback: UserDay) -> VitalsWindow {
        guard let start, let end, end > start else {
            let range = VitalsTimelineRange(start: fallback.start, end: fallback.end)
            return make(range: range, endsNow: false)
        }
        let range = VitalsTimelineRange(start: start, end: end)
        return make(range: range, endsNow: false)
    }

    private static func make(range: VitalsTimelineRange, endsNow: Bool) -> VitalsWindow {
        let marks = (0...4).map { index in
            range.start.addingTimeInterval(range.span * Double(index) / 4)
        }
        var labels = marks.map(Fmt.clock)
        if endsNow, !labels.isEmpty {
            labels[labels.count - 1] = L("NOW")
        }
        return VitalsWindow(
            start: range.start,
            span: range.span,
            labels: labels,
            endsNow: endsNow
        )
    }

    func fraction(of ts: Date) -> Double {
        guard span > 0 else { return 0 }
        return min(1, max(0, ts.timeIntervalSince(start) / span))
    }

    func contains(_ ts: Date) -> Bool {
        ts >= start && ts.timeIntervalSince(start) <= span
    }
}

/// The 24-hour trace: heart, autonomic load, skin temperature. A fixed vertical ruler, an
/// optional reference band behind the line, one marked extreme and a dot on the last tick.
///
/// ⚠️ Ticks more than ten minutes apart were not neighbours on the wrist, so the line breaks
/// and the gap is drawn dashed. 08 rule 07 · a gap is never interpolated.
struct VitalsTrace: View {
    let samples: [VitalSample]
    let value: (VitalSample) -> Double?
    let window: VitalsWindow
    let low: Double
    let high: Double
    let tint: Color
    /// The physiological band drawn behind the line — 60–80 resting, ±0.3 °C, and so on.
    var referenceBand: ClosedRange<Double>?
    var referenceLabel: String?
    /// The extreme worth naming, and how to print it. nil marks nothing.
    var extremeLabel: ((Double) -> String)?
    /// True to mark the highest point, false the lowest.
    var marksMaximum = true
    var height: CGFloat = 124

    var body: some View {
        Canvas { ctx, size in
            let span = max(0.001, high - low)
            func y(_ v: Double) -> CGFloat {
                let clamped = min(high, max(low, v))
                return size.height - 1 - (clamped - low) / span * (size.height - 2)
            }
            func point(_ ts: Date, _ v: Double) -> CGPoint {
                CGPoint(x: size.width * window.fraction(of: ts), y: y(v))
            }

            // The ruler: three lines inside the field and one on the floor.
            for f in [0.15, 0.45, 0.75] {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height * f))
                line.addLine(to: CGPoint(x: size.width, y: size.height * f))
                ctx.stroke(line, with: .color(NB.white.opacity(0.05)), lineWidth: 1)
            }
            var floor = Path()
            floor.move(to: CGPoint(x: 0, y: size.height - 0.5))
            floor.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            ctx.stroke(floor, with: .color(NB.white.opacity(0.08)), lineWidth: 1)

            if let referenceBand {
                let top = y(referenceBand.upperBound)
                let bottom = y(referenceBand.lowerBound)
                ctx.fill(Path(CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top))),
                         with: .color(tint.opacity(0.06)))
                if let referenceLabel {
                    plate(&ctx, Text(referenceLabel).font(NBFont.ui(500, 8))
                        .foregroundStyle(tint.opacity(0.8)),
                          at: CGPoint(x: 3, y: top + 2), in: size)
                }
            }

            // The runs, broken wherever the band stopped reporting.
            var runs: [[CGPoint]] = []
            var run: [CGPoint] = []
            var lastTs: Date?
            var extreme: (ts: Date, v: Double)?
            for s in samples {
                guard window.contains(s.ts), let v = value(s) else { continue }
                if let lastTs, s.ts.timeIntervalSince(lastTs) > 10 * 60, !run.isEmpty {
                    runs.append(run); run = []
                }
                run.append(point(s.ts, v))
                lastTs = s.ts
                if extreme == nil || (marksMaximum ? v > extreme!.v : v < extreme!.v) {
                    extreme = (s.ts, v)
                }
            }
            if !run.isEmpty { runs.append(run) }
            guard !runs.isEmpty else { return }

            for (i, r) in runs.enumerated() {
                var p = Path()
                p.move(to: r[0])
                for pt in r.dropFirst() { p.addLine(to: pt) }
                if r.count == 1 { p.addLine(to: CGPoint(x: r[0].x + 0.5, y: r[0].y)) }
                ctx.stroke(p, with: .color(tint),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                if i + 1 < runs.count {
                    var gap = Path()
                    gap.move(to: r[r.count - 1])
                    gap.addLine(to: runs[i + 1][0])
                    ctx.stroke(gap, with: .color(tint.opacity(0.30)),
                               style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                }
            }

            // The extreme, called out where it happened rather than in a caption.
            if let extreme, let extremeLabel, samples.count > 2 {
                let at = point(extreme.ts, extreme.v)
                ctx.fill(Path(ellipseIn: CGRect(x: at.x - 3, y: at.y - 3, width: 6, height: 6)),
                         with: .color(NB.alert2))
                // Kept inside the field: a callout at the right edge would clip.
                let anchorX = min(max(at.x, 26), size.width - 26)
                plate(&ctx, Text(extremeLabel(extreme.v)).font(NBFont.ui(600, 9))
                    .foregroundStyle(NB.alert2),
                      at: CGPoint(x: anchorX, y: max(8, at.y - 12)), in: size, anchor: .center)
            }

            if let end = runs.last?.last {
                ctx.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)),
                         with: .color(tint))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 02 · the night as four lanes — AWAKE · REM · LIGHT · DEEP — stepped in the order the band
/// filed it. The app never re-segments the line (04B rule 04): a run is drawn at its own
/// lane for its own minutes, and the vertical joins are the transitions themselves.
struct VitalsHypnogram: View {
    let runs: [SleepStageRun]
    let tint: Color
    var height: CGFloat = 124

    /// SDK stages: 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake. Four lanes, deepest at the
    /// bottom, because that is how a hypnogram is read.
    private static func lane(_ stage: Int) -> Int {
        switch stage {
        case 0: 3
        case 1: 2
        case 2: 1
        default: 0
        }
    }

    private static let laneNames = ["AWAKE", "REM", "LIGHT", "DEEP"]
    /// The lane-label gutter plus its gap. The clock under the chart is inset by exactly
    /// this, or its first mark sits under "AWAKE" instead of under the night's first minute.
    static let labelGutter: CGFloat = 40

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Self.laneNames, id: \.self) { name in
                    Text(L(name))
                        .font(NBFont.ui(400, 8)).tracking(0.08 * 8)
                        .foregroundStyle(NB.white.opacity(0.40))
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(width: 34, height: height)

            Canvas { ctx, size in
                let total = runs.reduce(0) { $0 + $1.minutes }
                guard total > 0 else { return }
                let laneHeight = size.height / 4

                for i in 0..<4 {
                    var line = Path()
                    let y = laneHeight * (CGFloat(i) + 0.5)
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(line, with: .color(NB.white.opacity(0.05)), lineWidth: 1)
                }

                var x: CGFloat = 0
                var path = Path()
                var previousY: CGFloat?
                for run in runs {
                    let w = size.width * CGFloat(run.minutes) / CGFloat(total)
                    let y = laneHeight * (CGFloat(Self.lane(run.stage)) + 0.5)
                    if let previousY {
                        path.addLine(to: CGPoint(x: x, y: y))
                        _ = previousY
                    } else {
                        path.move(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: x + w, y: y))
                    previousY = y
                    x += w

                    // Deep sleep is the night's payload, so its runs carry a block behind
                    // the line; the lighter lanes stay a line so the shape reads at a glance.
                    if run.stage == 0 {
                        let rect = CGRect(x: x - w, y: y, width: max(1, w), height: laneHeight * 0.5)
                        ctx.fill(Path(rect), with: .color(tint.opacity(0.22)))
                    }
                }
                ctx.stroke(path, with: .color(tint),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            .frame(height: height)
        }
        .accessibilityHidden(true)
    }
}

/// 03 · the night's RMSSD ticks as a scatter, inside the envelope the last fortnight of
/// nights drew. The envelope is the baseline's own spread — not a target band — so a night
/// that sits under it is low for *this* wrist rather than low in the abstract.
struct VitalsScatter: View {
    let samples: [VitalSample]
    let window: VitalsWindow
    /// The 14-night envelope, when there are enough nights to have one (04B rule 06).
    var envelope: ClosedRange<Double>?
    var baseline: Double?
    let tint: Color
    var height: CGFloat = 124

    var body: some View {
        Canvas { ctx, size in
            let values = samples.compactMap(\.hrv)
            guard !values.isEmpty else { return }
            // The axis comes from the night and its envelope together, so the points and the
            // band are always both on screen.
            let lo = min(values.min()!, envelope?.lowerBound ?? .infinity, baseline ?? .infinity) - 6
            let hi = max(values.max()!, envelope?.upperBound ?? -.infinity, baseline ?? -.infinity) + 6
            let span = max(1, hi - lo)
            func y(_ v: Double) -> CGFloat {
                size.height - 2 - CGFloat((min(hi, max(lo, v)) - lo) / span) * (size.height - 4)
            }

            if let envelope {
                let top = y(envelope.upperBound)
                let bottom = y(envelope.lowerBound)
                ctx.fill(Path(CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top))),
                         with: .color(tint.opacity(0.08)))
            }
            if let baseline {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(baseline)))
                line.addLine(to: CGPoint(x: size.width, y: y(baseline)))
                ctx.stroke(line, with: .color(NB.white.opacity(0.28)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }

            // A faint line joining the ticks in order, and the ticks themselves on top: the
            // trend is the shape, the dots are the measurements.
            var trend = Path()
            var started = false
            for s in samples {
                guard window.contains(s.ts), let v = s.hrv else { continue }
                let p = CGPoint(x: size.width * window.fraction(of: s.ts), y: y(v))
                if started { trend.addLine(to: p) } else { trend.move(to: p); started = true }
            }
            if started {
                ctx.stroke(trend, with: .color(tint.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
            for s in samples {
                guard window.contains(s.ts), let v = s.hrv else { continue }
                let p = CGPoint(x: size.width * window.fraction(of: s.ts), y: y(v))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)),
                         with: .color(tint))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 06 · 08 · the day as 24 hourly columns, graded in three tiers against the busiest hour.
/// An hour with no ticks is left empty rather than drawn as a zero — 04B rule 04 · a missing
/// hour and a still hour are two different facts, and only one of them is a bar.
struct VitalsHistogram: View {
    /// Hourly bins, nil where the band reported nothing.
    let bins: [Double?]
    let window: VitalsWindow
    let tint: Color
    /// What the peak column is labelled with, e.g. "PEAK 1,420/H".
    var peakLabel: ((Double) -> String)?
    var height: CGFloat = 124

    var body: some View {
        Canvas { ctx, size in
            let present = bins.compactMap { $0 }.filter { $0 > 0 }
            guard let top = present.max(), top > 0, window.span > 0 else { return }
            let gap: CGFloat = 3
            let field = size.height - 16   // the peak callout's lane

            var floor = Path()
            floor.move(to: CGPoint(x: 0, y: size.height - 0.5))
            floor.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            ctx.stroke(floor, with: .color(NB.white.opacity(0.08)), lineWidth: 1)

            var peakX: CGFloat?
            for (i, value) in bins.enumerated() {
                guard let value, value > 0 else { continue }
                let ratio = value / top
                let h = max(1.5, field * ratio)
                let start = min(window.span, TimeInterval(i) * 3600)
                let end = min(window.span, TimeInterval(i + 1) * 3600)
                let x = size.width * CGFloat(start / window.span)
                let endX = size.width * CGFloat(end / window.span)
                let width = max(1.5, endX - x - gap)
                let rect = CGRect(x: x, y: size.height - h, width: width, height: h)
                // Three tiers, one colour: intensity is brightness, never a second hue.
                let alpha: Double = ratio >= 0.72 ? 1 : (ratio >= 0.34 ? 0.60 : 0.30)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(tint.opacity(alpha)))
                if value == top { peakX = x + width / 2 }
            }

            if let peakX, let peakLabel {
                let text = Text(peakLabel(top)).font(NBFont.ui(600, 9)).foregroundStyle(tint)
                ctx.draw(text, at: CGPoint(x: min(max(peakX, 30), size.width - 30), y: 6), anchor: .center)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 07 · the day's displacement as a climb: each hour's metres added to the last, so the
/// curve only ever rises and its steepness is the hour that moved. A flat stretch is an hour
/// that happened and went nowhere — which is why this is a climb and not a histogram.
struct VitalsClimb: View {
    /// Hourly increments, nil where the band reported nothing.
    let bins: [Double?]
    let window: VitalsWindow
    let tint: Color
    /// What the last point is labelled with, e.g. "6.42 KM NOW".
    var endLabel: String?
    var height: CGFloat = 124

    var body: some View {
        Canvas { ctx, size in
            var cumulative: [(fraction: CGFloat, value: CGFloat)] = []
            var running: Double = 0
            var any = false
            guard window.span > 0 else { return }
            for (index, bin) in bins.enumerated() {
                if let bin, bin > 0 { running += bin; any = true }
                let elapsed = min(window.span, TimeInterval(index + 1) * 3600)
                cumulative.append((
                    fraction: CGFloat(elapsed / window.span),
                    value: CGFloat(running)
                ))
            }
            guard any, running > 0 else { return }

            for f in [0.25, 0.5, 0.75] {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height * f))
                line.addLine(to: CGPoint(x: size.width, y: size.height * f))
                ctx.stroke(line, with: .color(NB.white.opacity(0.05)), lineWidth: 1)
            }

            let field = size.height - 14
            func point(_ i: Int) -> CGPoint {
                CGPoint(x: size.width * cumulative[i].fraction,
                        y: size.height - 1 - cumulative[i].value / CGFloat(running) * field)
            }

            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height - 1))
            for i in cumulative.indices { area.addLine(to: point(i)) }
            area.addLine(to: CGPoint(x: size.width, y: size.height - 1))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.22), tint.opacity(0.01)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

            var line = Path()
            line.move(to: CGPoint(x: 0, y: size.height - 1))
            for i in cumulative.indices { line.addLine(to: point(i)) }
            ctx.stroke(line, with: .color(tint),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

            let end = point(cumulative.count - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)),
                     with: .color(tint))
            if let endLabel {
                let text = Text(endLabel).font(NBFont.ui(600, 9)).foregroundStyle(tint)
                ctx.draw(text, at: CGPoint(x: size.width - 4, y: max(7, end.y - 12)), anchor: .trailing)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
