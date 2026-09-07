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
    /// How many user days this window was built from. nil on a clock window.
    var dayCount: Int? = nil
    /// The last user day of a multi-day window, so TODAY is that day and not the wall clock.
    var endingDay: UserDay? = nil

    var range: VitalsTimelineRange {
        VitalsTimelineRange(start: start, end: start.addingTimeInterval(span))
    }

    static func userDay(_ day: UserDay, now: Date) -> VitalsWindow {
        let range = VitalsTimelinePolicy.userDay(start: day.start, end: day.end, now: now)
        return make(range: range, endsNow: now >= day.start && now < day.end)
    }

    /// Last `count` user days ending on `day`, one equal slot a day. The span is the
    /// real calendar width (DST included) so a 23-hour day does not invent an eighth bar.
    static func rollingUserDays(_ count: Int, endingOn day: UserDay, now: Date) -> VitalsWindow {
        let slots = UserDay.last(max(1, count), endingAt: day)
        let days = slots.count
        let first = slots[0]
        let start = first.start
        let end = day.end
        let span = max(0, end.timeIntervalSince(start))
        let labels = (0...4).map { index -> String in
            let slot = HeartWindowMath.slotIndex(fraction: Double(index) / 4, days: days)
            let mark = first.adding(days: slot)
            if mark == day { return L("TODAY") }
            if days <= 7 { return Fmt.weekday(mark.start) }
            return index == 0
                ? Fmt.displayDate(mark.start, format: "d MMM").uppercased()
                : Fmt.displayDate(mark.start, format: "d")
        }
        return VitalsWindow(start: start, span: span, labels: labels,
                            endsNow: true, dayCount: days, endingDay: day)
    }

    /// Only a recorded sleep interval can supply a night clock or admit overnight points.
    static func night(start: Date?, end: Date?, fallback: UserDay) -> VitalsWindow {
        guard let start, let end, end > start else {
            return VitalsWindow(start: fallback.start, span: 0, labels: [], endsNow: false)
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
        span > 0 && ts >= start && ts.timeIntervalSince(start) <= span
    }

    func clock(atFraction fraction: Double) -> String {
        guard span > 0 else { return Fmt.dash }
        if let dayCount {
            let slot = HeartWindowMath.slotIndex(fraction: fraction, days: dayCount)
            let mark = start.addingTimeInterval(Double(slot) * HeartWindowMath.slotSeconds(span: span, days: dayCount))
            if let endingDay, UserDay.containing(mark) == endingDay { return L("TODAY") }
            return dayCount <= 7
                ? Fmt.weekday(mark)
                : Fmt.displayDate(mark, format: "d MMM").uppercased()
        }
        if endsNow, fraction >= 0.999 { return L("NOW") }
        return Fmt.clock(start.addingTimeInterval(span * fraction))
    }
}

/// The 24-hour trace: heart, autonomic load, skin temperature. A fixed vertical ruler that
/// stands beside the field, an optional reference band behind the marks, and occupancy
/// runs inside each quarter hour — only the value bands that have ticks.
///
/// ⚠️ An envelope is not a min–max fill, not a smoothing pass, and not an average. A
/// hole such as 70–75 with no sample stays empty; a quarter hour the band did not
/// report draws nothing at all. 08 rule 07 · a gap is never interpolated still holds
/// on both axes.
///
/// ⚠️ Nothing is printed inside the field. The ruler lives in `VitalsScaleRail`, the band's
/// name and the extreme in `VitalsChartLegend` under the clock. A caption drawn on top of
/// the data is read against whatever the data is doing beneath it, which is how `MAX 142`
/// came to cover the second half of `RESTING BAND 49–69`.
struct VitalsTrace: View {
    let samples: [VitalSample]
    let value: (VitalSample) -> Double?
    let window: VitalsWindow
    let low: Double
    let high: Double
    let tint: Color
    /// The hero dial's own ruler. Given one, every capsule is coloured by the zone it sits
    /// in instead of by the metric's accent, and a capsule that crossed a cut carries both
    /// colours with a hard edge on the cut. nil keeps the whole field in `tint` — a metric
    /// with no zones has nothing to escalate through.
    var zones: VitalsDial.Model?
    /// The physiological band drawn behind the marks — 60–80 resting, ±0.3 °C, and so on.
    var referenceBand: ClosedRange<Double>?
    /// The stretch of the window the band belongs to. nil spans the whole chart; skin
    /// temperature bands only last night, because the daytime hours are not judged.
    var referenceSpan: ClosedRange<Date>?
    /// True to pick out the highest envelope, false the lowest.
    var marksMaximum = true
    var height: CGFloat = 160
    /// Additional measured series share the same chart without impersonating another vital.
    var measuredPoints: [(ts: Date, value: Double)]? = nil
    /// How wide one envelope is. A quarter hour over a full day is 96
    /// columns. A night window has far fewer slots; width follows the slot so the
    /// last quarter hour sits against the rail instead of leaving a dead strip.
    static let defaultSlotMinutes: Double = 15
    var slotMinutes: Double = VitalsTrace.defaultSlotMinutes
    /// A value without its unit: `72`, `36.4`. Drives the rail and both ends of the readout.
    var valueFormat: (Double) -> String = { String(format: "%.0f", $0) }
    /// What the readout calls the numbers. Empty for a bare score.
    var unit: String = ""

    /// The rail, top mark first. Three is as many as 160 pt of field can name without the
    /// numbers crowding each other.
    var railLabels: [String] {
        [high, (high + low) / 2, low].map(valueFormat)
    }

    var body: some View {
        VitalsChartProbe(
            series: .bins(probeBins),
            tint: tint,
            height: height,
            trailingInset: VitalsScaleRail.gutter,
            clockAt: window.clock(atFraction:)
        ) { probing in
            HStack(spacing: VitalsScaleRail.gap) {
                Canvas { ctx, size in
                    let span = max(0.001, high - low)
                    func y(_ v: Double) -> CGFloat {
                        let clamped = min(high, max(low, v))
                        return size.height - 1 - (clamped - low) / span * (size.height - 2)
                    }

                    // One gridline, at the value the rail's middle mark names. The old chart
                    // ruled 0.15/0.45/0.75 — three lines standing at no value at all, which
                    // is decoration once a rail is there to be read against.
                    var middle = Path()
                    middle.move(to: CGPoint(x: 0, y: y((high + low) / 2)))
                    middle.addLine(to: CGPoint(x: size.width, y: y((high + low) / 2)))
                    ctx.stroke(middle, with: .color(NB.white.opacity(0.05)), lineWidth: 1)

                    var floor = Path()
                    floor.move(to: CGPoint(x: 0, y: size.height - 0.5))
                    floor.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                    ctx.stroke(floor, with: .color(NB.white.opacity(0.10)), lineWidth: 1)

                    if let referenceBand {
                        let top = y(referenceBand.upperBound)
                        let bottom = y(referenceBand.lowerBound)
                        let edges = referenceSpan.map {
                            (size.width * window.fraction(of: $0.lowerBound),
                             size.width * window.fraction(of: $0.upperBound))
                        } ?? (0, size.width)
                        let left = max(0, min(edges.0, edges.1))
                        let right = min(size.width, max(edges.0, edges.1))
                        // A night that has scrolled out of the window bands nothing at all,
                        // rather than a one-pixel sliver against the left edge.
                        if right > left {
                            // ⚠️ Kept deliberately faint. At 0.10 the band read as a solid
                            // slab and the night's marks — which sit inside it, because a
                            // resting pulse is what the band is for — disappeared into it.
                            // The band is background; the marks are the reading.
                            ctx.fill(Path(CGRect(x: left, y: top, width: right - left,
                                                 height: max(1, bottom - top))),
                                     with: .color(tint.opacity(0.055)))
                        }
                    }

                    let marks = envelopes
                    guard !marks.isEmpty else { return }
                    let peak = extremeMark

                    for mark in marks {
                        let top = y(mark.high)
                        let bottom = y(mark.low)
                        let bar = VitalsProbeMath.slotBar(start: mark.start, end: mark.end,
                                                          field: Double(size.width))
                        let barWidth = CGFloat(bar.width)
                        let radius = CGFloat(VitalsProbeMath.slotBarRadius(width: bar.width))
                        // A slot that reduced one tick has no height of its own; it draws as
                        // a round mark of the capsule's head, centred on its own value,
                        // rather than as a hairline that reads as missing data.
                        let barHeight = max(radius * 2, bottom - top)
                        let centre = (top + bottom) / 2
                        let originY = min(max(0, centre - barHeight / 2), size.height - barHeight)
                        let rect = CGRect(x: CGFloat(bar.x), y: originY,
                                          width: barWidth, height: barHeight)
                        let isPeak = !probing && peak.map { $0 == mark } == true
                        let path = Path(roundedRect: rect, cornerRadius: radius)
                        // ⚠️ The clamped ends, not the raw ones. A capsule pinned to the top
                        // of the ruler must be coloured by the stretch it actually shows, or
                        // a 190 BPM spike on a 40–160 field paints its whole visible height
                        // in the top zone's colour.
                        if let stops = zones?.stops(low: max(low, mark.low),
                                                    high: min(high, mark.high)) {
                            ctx.opacity = isPeak ? 1 : 0.78
                            ctx.fill(path, with: .linearGradient(
                                Gradient(stops: stops),
                                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                            ctx.opacity = 1
                        } else {
                            ctx.fill(path, with: .color(tint.opacity(isPeak ? 1 : 0.72)))
                        }
                    }
                }

                VitalsScaleRail(labels: railLabels, tint: tint)
            }
        }
    }

    // MARK: what the field is drawn from

    private var slotSeconds: TimeInterval { slotMinutes * 60 }

    private var windowPoints: [(fraction: Double, value: Double)] {
        let raw = measuredPoints ?? samples.compactMap { sample in
            value(sample).map { (ts: sample.ts, value: $0) }
        }
        return raw.compactMap { sample in
            guard window.contains(sample.ts), sample.value.isFinite else { return nil }
            return (fraction: window.fraction(of: sample.ts), value: sample.value)
        }
    }

    private var occupancyGap: Double {
        VitalsProbeMath.occupancyGap(low: low, high: high)
    }

    private var envelopes: [VitalsProbeMath.Envelope] {
        VitalsProbeMath.envelopes(points: windowPoints, seconds: slotSeconds,
                                  span: window.span, valueGap: occupancyGap)
    }

    /// Which occupied run holds the window's extreme, so the field can pick it out
    /// without printing a number over it. nil on a chart too short to have an
    /// interesting extreme. Identity is the mark itself — a slot can hold more than
    /// one run, and only the extreme run lights.
    private var extremeMark: VitalsProbeMath.Envelope? {
        let marks = envelopes
        guard marks.count > 2 else { return nil }
        return marksMaximum
            ? marks.max(by: { $0.high < $1.high })
            : marks.min(by: { $0.low < $1.low })
    }

    /// Every slot the window has room for, filled or not. A quarter hour the band
    /// skipped is still a slot the finger can land on — it just reads `——`. A slot
    /// with two occupied runs names both, never the hollow min–max between them.
    private var probeBins: [VitalsProbeMath.Bin] {
        let grouped = Dictionary(grouping: envelopes, by: \.index)
        return VitalsProbeMath.timeSlots(seconds: slotSeconds, span: window.span).map { slot in
            let clock = window.clock(atFraction: (slot.start + slot.end) / 2)
            guard let marks = grouped[slot.index], !marks.isEmpty else {
                return .init(start: slot.start, end: slot.end, yFraction: nil,
                             text: VitalsProbeCopy.gap(clock), vacant: true)
            }
            let ordered = marks.sorted { $0.low < $1.low }
            let top = ordered.map(\.high).max() ?? ordered[0].high
            return .init(
                start: slot.start,
                end: slot.end,
                // The dot lands on the top of the highest occupied run.
                yFraction: VitalsProbeMath.yFraction(value: top, low: low, high: high),
                text: VitalsProbeCopy.ranges(
                    clock,
                    spans: ordered.map { (valueFormat($0.low), valueFormat($0.high)) },
                    unit: unit),
                vacant: false
            )
        }
    }
}

/// Overnight automatic SpO2 on the same night clock as the hypnogram. The ruler is fixed
/// 85–100 so a quiet night cannot look like a crash; a missing reading is a gap, never a 0.
/// ADR-0002 · no 90 % clinical line, no apnea grade.
struct VitalsOxygenTrace: View {
    let points: [OvernightOxygenPoint]
    let window: VitalsWindow
    let tint: Color
    var height: CGFloat = 160

    private let low: Double = 85
    private let high: Double = 100

    var body: some View {
        VitalsChartProbe(
            series: .points(probePoints),
            tint: tint,
            height: height,
            gapFraction: VitalsProbeMath.gapFraction(span: window.span),
            clockAt: window.clock(atFraction:)
        ) { probing in
            Canvas { ctx, size in
                let span = max(0.001, high - low)
                func y(_ v: Double) -> CGFloat {
                    let clamped = min(high, max(low, v))
                    return size.height - 1 - (clamped - low) / span * (size.height - 2)
                }
                func point(_ ts: Date, _ v: Double) -> CGPoint {
                    CGPoint(x: size.width * window.fraction(of: ts), y: y(v))
                }

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

                var runs: [[CGPoint]] = []
                var run: [CGPoint] = []
                var lastTs: Date?
                var extreme: (ts: Date, v: Double)?
                for sample in points {
                    guard window.contains(sample.ts), (50...100).contains(sample.percent) else { continue }
                    let v = Double(sample.percent)
                    if let lastTs, sample.ts.timeIntervalSince(lastTs) > 12 * 60, !run.isEmpty {
                        runs.append(run); run = []
                    }
                    run.append(point(sample.ts, v))
                    lastTs = sample.ts
                    if extreme == nil || v < extreme!.v { extreme = (sample.ts, v) }
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

                if !probing, let extreme, points.count > 2 {
                    let at = point(extreme.ts, extreme.v)
                    ctx.fill(Path(ellipseIn: CGRect(x: at.x - 3, y: at.y - 3, width: 6, height: 6)),
                             with: .color(NB.alert2))
                    let anchorX = min(max(at.x, 26), size.width - 26)
                    plate(&ctx, Text(L("MIN %d%%", Int(extreme.v.rounded()))).font(NBFont.ui(600, 9))
                        .foregroundStyle(NB.alert2),
                          at: CGPoint(x: anchorX, y: max(8, at.y - 12)), in: size, anchor: .center)
                }

                if !probing, let end = runs.last?.last {
                    ctx.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)),
                             with: .color(tint))
                }
            }
        }
    }

    private var probePoints: [VitalsProbeMath.Point] {
        points.compactMap { sample in
            guard window.contains(sample.ts), (50...100).contains(sample.percent) else { return nil }
            let value = Double(sample.percent)
            return .init(
                fraction: window.fraction(of: sample.ts),
                yFraction: VitalsProbeMath.yFraction(value: value, low: low, high: high),
                text: VitalsProbeCopy.line(Fmt.clock(sample.ts), "\(sample.percent)%")
            )
        }
    }
}

/// 02 · the night as four lanes — AWAKE · REM · LIGHT · DEEP — stepped in the order the band
/// filed it. The app never re-segments the line (04B rule 04): a run is drawn at its own
/// lane for its own minutes, and the vertical joins are the transitions themselves.
struct VitalsHypnogram: View {
    let runs: [SleepStageRun]
    let tint: Color
    var windowMinutes: Double? = nil
    var height: CGFloat = 160
    var probeClock: (Double) -> String = { _ in Fmt.dash }

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
        VitalsChartProbe(
            series: .runs(probeRuns),
            tint: tint,
            height: height,
            leadingInset: Self.labelGutter,
            clockAt: probeClock
        ) { _ in
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.laneNames, id: \.self) { name in
                        Text(L(name))
                            .font(NBFont.ui(400, 8)).tracking(0.08 * 8)
                            .foregroundStyle(NB.white.opacity(0.40))
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(width: 34)

                Canvas { ctx, size in
                    let hasOffsets = runs.allSatisfy { $0.offsetMinutes != nil }
                    let total = layoutTotal
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
                        let runX = hasOffsets ? size.width * CGFloat(run.offsetMinutes ?? 0) / CGFloat(total) : x
                        let w = size.width * CGFloat(run.minutes) / CGFloat(total)
                        let followsPrevious = abs(runX - x) < 0.1
                        x = runX
                        let y = laneHeight * (CGFloat(Self.lane(run.stage)) + 0.5)
                        if let previousY, followsPrevious {
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
            }
        }
    }

    private var layoutTotal: Double {
        let hasOffsets = runs.allSatisfy { $0.offsetMinutes != nil }
        return hasOffsets
            ? max(windowMinutes ?? 0, Double(runs.map { ($0.offsetMinutes ?? 0) + $0.minutes }.max() ?? 0))
            : Double(runs.reduce(0) { $0 + $1.minutes })
    }

    private var probeRuns: [VitalsProbeMath.Run] {
        let offsets = runs.allSatisfy { $0.offsetMinutes != nil }
            ? runs.map { $0.offsetMinutes ?? 0 } : nil
        let spans = VitalsProbeMath.stageSpans(
            minutes: runs.map(\.minutes), offsets: offsets, windowMinutes: windowMinutes)
        guard spans.count == runs.count else { return [] }
        return zip(runs, spans).map { run, span in
            let stage = L(Self.laneNames[Self.lane(run.stage)])
            let mid = (span.start + span.end) / 2
            return .init(
                start: span.start,
                end: span.end,
                yFraction: (Double(Self.lane(run.stage)) + 0.5) / 4,
                text: VitalsProbeCopy.line(probeClock(mid), stage)
            )
        }
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
    var height: CGFloat = 160

    var body: some View {
        VitalsChartProbe(
            series: .points(probePoints),
            tint: tint,
            height: height,
            gapFraction: VitalsProbeMath.gapFraction(span: window.span),
            clockAt: window.clock(atFraction:)
        ) { _ in
            Canvas { ctx, size in
                let values = samples.compactMap(\.hrv)
                guard !values.isEmpty else { return }
                let (lo, hi) = scatterRange
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

                var trend = Path()
                var started = false
                var previousTimestamp: Date?
                for s in samples {
                    guard window.contains(s.ts), let v = s.hrv else { continue }
                    let p = CGPoint(x: size.width * window.fraction(of: s.ts), y: y(v))
                    if let previousTimestamp, s.ts.timeIntervalSince(previousTimestamp) <= 10 * 60 {
                        trend.addLine(to: p)
                    } else {
                        trend.move(to: p)
                    }
                    previousTimestamp = s.ts
                    started = true
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
        }
    }

    private var scatterRange: (Double, Double) {
        let values = samples.compactMap(\.hrv)
        guard !values.isEmpty else { return (0, 1) }
        let lo = min(values.min()!, envelope?.lowerBound ?? .infinity, baseline ?? .infinity) - 6
        let hi = max(values.max()!, envelope?.upperBound ?? -.infinity, baseline ?? -.infinity) + 6
        return (lo, hi)
    }

    private var probePoints: [VitalsProbeMath.Point] {
        let (lo, hi) = scatterRange
        return samples.compactMap { sample in
            guard window.contains(sample.ts), let value = sample.hrv else { return nil }
            return .init(
                fraction: window.fraction(of: sample.ts),
                yFraction: VitalsProbeMath.yFraction(value: value, low: lo, high: hi),
                text: VitalsProbeCopy.line(Fmt.clock(sample.ts), "\(Int(value.rounded())) MS")
            )
        }
    }
}

/// Rolling-24h meal-response index. Points only, compare-amber, a dashed own-median at 0.
/// No polyline, no meal marks, no envelope, no MAX callout.
struct VitalsIndexScatter: View {
    let points: [MealResponseIndex.ScatterPoint]
    let window: VitalsWindow
    let tint: Color
    var height: CGFloat = 160

    var body: some View {
        Canvas { ctx, size in
            let visible = points.filter { window.contains($0.ts) }
            guard !visible.isEmpty else { return }
            let values = visible.map(\.percent)
            let lo = min(Double(values.min()!), -8) - 6
            let hi = max(Double(values.max()!), 8) + 6
            let span = max(1, hi - lo)
            func y(_ v: Int) -> CGFloat {
                size.height - 2 - CGFloat((min(hi, max(lo, Double(v))) - lo) / span) * (size.height - 4)
            }
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: y(0)))
            zero.addLine(to: CGPoint(x: size.width, y: y(0)))
            ctx.stroke(zero, with: .color(NB.white.opacity(0.28)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            for point in visible {
                let p = CGPoint(x: size.width * window.fraction(of: point.ts), y: y(point.percent))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)),
                         with: .color(tint))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Rolling-24h wrist meal-response points. The vendor scale is opaque, so the chart names
/// these as points and scales only to the observed range. Gaps stay dashed instead of being
/// presented as continuous measurement.
struct VitalsResponseTrace: View {
    let points: [MealResponseIndex.Point]
    let window: VitalsWindow
    let tint: Color
    var height: CGFloat = 160

    var body: some View {
        VitalsChartProbe(
            series: .points(probePoints),
            tint: tint,
            height: height,
            gapFraction: VitalsProbeMath.gapFraction(span: window.span),
            clockAt: window.clock(atFraction:)
        ) { probing in
            Canvas { ctx, size in
                let visible = points.filter { window.contains($0.ts) && $0.optical.isFinite && $0.optical > 0 }
                guard let minimum = visible.map(\.optical).min(),
                      let maximum = visible.map(\.optical).max() else { return }
                let padding = max(1, (maximum - minimum) * 0.12)
                let low = minimum - padding
                let high = maximum + padding
                let span = max(1, high - low)
                func position(_ point: MealResponseIndex.Point) -> CGPoint {
                    let y = size.height - 2 - CGFloat((point.optical - low) / span) * (size.height - 4)
                    return CGPoint(x: size.width * window.fraction(of: point.ts), y: y)
                }

                for fraction in [0.15, 0.45, 0.75] {
                    var guide = Path()
                    guide.move(to: CGPoint(x: 0, y: size.height * fraction))
                    guide.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                    ctx.stroke(guide, with: .color(NB.white.opacity(0.05)), lineWidth: 1)
                }

                var runs: [[MealResponseIndex.Point]] = []
                var run: [MealResponseIndex.Point] = []
                for point in visible {
                    if let previous = run.last, point.ts.timeIntervalSince(previous.ts) > 10 * 60 {
                        runs.append(run)
                        run = []
                    }
                    run.append(point)
                }
                if !run.isEmpty { runs.append(run) }

                for (index, samples) in runs.enumerated() {
                    var line = Path()
                    line.move(to: position(samples[0]))
                    for sample in samples.dropFirst() { line.addLine(to: position(sample)) }
                    if samples.count == 1 {
                        let point = position(samples[0])
                        line.addLine(to: CGPoint(x: point.x + 0.5, y: point.y))
                    }
                    ctx.stroke(line, with: .color(tint),
                               style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    if index + 1 < runs.count {
                        var gap = Path()
                        gap.move(to: position(samples[samples.count - 1]))
                        gap.addLine(to: position(runs[index + 1][0]))
                        ctx.stroke(gap, with: .color(tint.opacity(0.28)),
                                   style: StrokeStyle(lineWidth: 1.1, dash: [2, 3]))
                    }
                }

                for sample in visible {
                    let point = position(sample)
                    ctx.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                             with: .color(tint))
                }
                if !probing, let latest = visible.last {
                    let point = position(latest)
                    ctx.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                             with: .color(tint))
                }
            }
        }
    }

    private var probePoints: [VitalsProbeMath.Point] {
        let visible = points.filter { window.contains($0.ts) && $0.optical.isFinite && $0.optical > 0 }
        guard let minimum = visible.map(\.optical).min(),
              let maximum = visible.map(\.optical).max() else { return [] }
        let padding = max(1, (maximum - minimum) * 0.12)
        let low = minimum - padding
        let high = maximum + padding
        return visible.map { point in
            .init(
                fraction: window.fraction(of: point.ts),
                yFraction: VitalsProbeMath.yFraction(value: point.optical, low: low, high: high),
                text: VitalsProbeCopy.line(Fmt.clock(point.ts), MealResponseIndex.pointValue(point.optical))
            )
        }
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
    /// The hero dial's ruler, as on `VitalsTrace`: a column climbs through the zones its
    /// total reaches instead of standing in the metric's accent. nil for the hourly metrics
    /// that have no per-hour zones — a busy hour and a still hour differ in height, and
    /// steps-per-hour has no threshold anybody reads it against.
    var zones: VitalsDial.Model?
    /// How a column's total prints on the rail — `1,420`, `620`.
    var valueFormat: (Double) -> String = { Fmt.kcal($0) }
    var height: CGFloat = 160

    /// The rail is scaled to the busiest hour, so its top mark is that hour and its floor is
    /// a real zero. Naming the peak here is what let the column give back the 16 pt of field
    /// it used to reserve for a caption printed over itself.
    var railLabels: [String] {
        let top = peak ?? 0
        return [top, top / 2, 0].map(valueFormat)
    }

    var body: some View {
        VitalsChartProbe(
            series: .bins(probeBins),
            tint: tint,
            height: height,
            trailingInset: VitalsScaleRail.gutter,
            clockAt: window.clock(atFraction:)
        ) { probing in
            HStack(spacing: VitalsScaleRail.gap) {
                Canvas { ctx, size in
                    guard let top = peak, top > 0, window.span > 0 else { return }
                    let gap: CGFloat = 3
                    let field = size.height - 2

                    var middle = Path()
                    middle.move(to: CGPoint(x: 0, y: size.height - field / 2))
                    middle.addLine(to: CGPoint(x: size.width, y: size.height - field / 2))
                    ctx.stroke(middle, with: .color(NB.white.opacity(0.05)), lineWidth: 1)

                    var floor = Path()
                    floor.move(to: CGPoint(x: 0, y: size.height - 0.5))
                    floor.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                    ctx.stroke(floor, with: .color(NB.white.opacity(0.10)), lineWidth: 1)

                    for (i, value) in bins.enumerated() {
                        guard let value, value > 0 else { continue }
                        let ratio = value / top
                        let start = min(window.span, TimeInterval(i) * 3600)
                        let end = min(window.span, TimeInterval(i + 1) * 3600)
                        let x = size.width * CGFloat(start / window.span)
                        let endX = size.width * CGFloat(end / window.span)
                        // ⚠️ The hour that just started has no room of its own. At 12:01 the
                        // window leaves it a 2.5 pt sliver pinned against the rail, which
                        // reads as an artefact and not as an hour, and there is nowhere to
                        // widen it to without overlapping 11:00. It stays out of the field
                        // until it owns enough width to be a column; the probe reports it
                        // either way, so the ticks are not lost.
                        let hour = size.width * CGFloat(3600 / window.span)
                        guard endX - x >= hour * 0.4 else { continue }
                        let width = max(2.5, endX - x - gap)
                        // A full day of hours is ~11 pt per column, so `width / 2` wins and
                        // the head is a true capsule. ⚠️ The cap is for a user day only a
                        // few hours old, where each hour gets a 39 pt column and a 19 pt
                        // radius would turn it into a pill rather than a column standing
                        // on the floor.
                        let radius = min(width / 2, 6)
                        // The quietest hour on record still reads as a mark rather than as
                        // a scratch, but it is not inflated to the column's own width.
                        let h = max(radius * 2, field * ratio)
                        let rect = CGRect(x: x, y: size.height - h, width: width, height: h)
                        let isPeak = !probing && value == top
                        let path = Path(roundedRect: rect, cornerRadius: radius)
                        // A column stands on the floor, so the run it covers is 0…its total.
                        if let stops = zones?.stops(low: 0, high: value) {
                            ctx.opacity = isPeak ? 1 : 0.78
                            ctx.fill(path, with: .linearGradient(
                                Gradient(stops: stops),
                                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                            ctx.opacity = 1
                        } else {
                            ctx.fill(path, with: .color(tint.opacity(isPeak ? 1 : 0.72)))
                        }
                    }
                }

                VitalsScaleRail(labels: railLabels, tint: tint)
            }
        }
    }

    private var peak: Double? {
        bins.compactMap { $0 }.filter { $0 > 0 }.max()
    }

    private var probeBins: [VitalsProbeMath.Bin] {
        let top = bins.compactMap { $0 }.filter { $0 > 0 }.max() ?? 0
        return VitalsProbeMath.hourSlots(count: bins.count, span: window.span).map { slot in
            let value = bins[slot.index]
            let clock = Fmt.clock(window.start.addingTimeInterval(TimeInterval(slot.index) * 3600))
            if let value, !VitalsProbeMath.isVacantHour(value), top > 0 {
                return .init(
                    start: slot.start,
                    end: slot.end,
                    yFraction: 1 - value / top,
                    text: VitalsProbeCopy.line(clock, valueFormat(value)),
                    vacant: false
                )
            }
            return .init(
                start: slot.start,
                end: slot.end,
                yFraction: nil,
                text: VitalsProbeCopy.gap(clock),
                vacant: true
            )
        }
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
    /// How a running total prints on the rail — `6.42 KM`.
    var valueFormat: (Double) -> String = { VitalsReadout.distanceLabel($0) }
    var height: CGFloat = 160

    /// The climb is scaled to where it finished, so the rail's top mark is the day's total.
    /// That is the number the curve's end used to print over itself.
    var railLabels: [String] {
        let total = VitalsProbeMath.cumulativeTotals(bins).max() ?? 0
        return [total, total / 2, 0].map(valueFormat)
    }

    var body: some View {
        VitalsChartProbe(
            series: .bins(probeBins),
            tint: tint,
            height: height,
            trailingInset: VitalsScaleRail.gutter,
            clockAt: window.clock(atFraction:)
        ) { probing in
            HStack(spacing: VitalsScaleRail.gap) {
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

                    let field = size.height - 2
                    func point(_ i: Int) -> CGPoint {
                        CGPoint(x: size.width * cumulative[i].fraction,
                                y: size.height - 1 - cumulative[i].value / CGFloat(running) * field)
                    }

                    var middle = Path()
                    middle.move(to: CGPoint(x: 0, y: size.height - 1 - field / 2))
                    middle.addLine(to: CGPoint(x: size.width, y: size.height - 1 - field / 2))
                    ctx.stroke(middle, with: .color(NB.white.opacity(0.05)), lineWidth: 1)

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

                    if !probing {
                        let end = point(cumulative.count - 1)
                        ctx.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)),
                                 with: .color(tint))
                    }
                }

                VitalsScaleRail(labels: railLabels, tint: tint)
            }
        }
    }

    private var probeBins: [VitalsProbeMath.Bin] {
        let totals = VitalsProbeMath.cumulativeTotals(bins)
        let peak = totals.max() ?? 0
        return VitalsProbeMath.hourSlots(count: bins.count, span: window.span).map { slot in
            let running = totals[slot.index]
            let elapsed = min(window.span, TimeInterval(slot.index + 1) * 3600)
            let clock = Fmt.clock(window.start.addingTimeInterval(elapsed))
            return .init(
                start: slot.start,
                end: slot.end,
                yFraction: peak > 0 ? 1 - running / peak : nil,
                text: VitalsProbeCopy.line(clock, valueFormat(running))
            )
        }
    }
}
