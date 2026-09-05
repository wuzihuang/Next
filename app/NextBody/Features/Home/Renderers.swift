import SwiftUI

// 07 · 09 · B — ten renderers cover all 27 types. Each one only eats the chart keys it is given.

/// curve · line · o2night · dual. Line, gradient fill, glow, dot.
struct CurveRenderer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let values: [Double]
    let accent: Color
    var fill = true
    var glow: Double = 0.35
    var dot = true
    /// 13 col 01 · 「the night in violet, the day so far in lime」. Points up to and including
    /// `splitAt` take `accent`; the rest take `accent2`. Nil draws one colour, as before.
    var splitAt: Int? = nil
    var accent2: Color? = nil
    /// 07 · drawn behind the dot screen: the stroke has to be wider than one pitch or the
    /// mask leaves a broken trail; the fill and the glow are the screen's job now.
    var led = false

    @State private var draw: CGFloat = 0
    private var stroke: CGFloat { led ? 6 : 2 }
    private var blur: CGFloat { led ? 0 : 6 }

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if fill, !led, pts.count > 1 {
                    area(pts, in: geo.size)
                        .fill(LinearGradient(colors: [accent.opacity(0.40), accent.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                        .opacity(draw)
                }
                if let k = splitAt, let a2 = accent2, k >= 0, k < pts.count - 1 {
                    line(Array(pts[...k]))
                        .trim(from: 0, to: draw)
                        .stroke(accent, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                        .shadow(color: accent.opacity(glow), radius: blur)
                    line(Array(pts[k...]))
                        .trim(from: 0, to: draw)
                        .stroke(a2, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                        .shadow(color: a2.opacity(glow), radius: blur)
                } else {
                    line(pts)
                        .trim(from: 0, to: draw)
                        .stroke(accent, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                        .shadow(color: accent.opacity(glow), radius: blur)
                }
                if dot, let last = pts.last {
                    Circle().fill(accent2 ?? accent)
                        .frame(width: led ? 10 : 5, height: led ? 10 : 5)
                        .position(last)
                        .opacity(draw == 1 ? 1 : 0)
                }
            }
        }
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { draw = 1 } }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let lo = values.min()!, hi = values.max()!
        let span = max(hi - lo, 0.0001)
        return values.enumerated().map { i, v in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                    y: size.height * (1 - CGFloat((v - lo) / span)) * 0.86 + size.height * 0.07)
        }
    }
    private func line(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard let f = p.first else { return path }
        path.move(to: f); p.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }
    private func area(_ p: [CGPoint], in size: CGSize) -> Path {
        var path = line(p)
        path.addLine(to: CGPoint(x: p.last!.x, y: size.height))
        path.addLine(to: CGPoint(x: p.first!.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

/// pair · band. A hi/lo envelope with the band between them filled.
struct PairRenderer: View {
    let hi: [Double]
    let lo: [Double]
    let accent: Color
    var led = false

    private func map(_ vs: [Double], mn: Double, span: Double, size: CGSize) -> [CGPoint] {
        vs.enumerated().map { i, v in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(max(vs.count - 1, 1)),
                    y: size.height * (1 - CGFloat((v - mn) / span)) * 0.9 + size.height * 0.05)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let all = hi + lo
            let mn = all.min() ?? 0
            let span = max((all.max() ?? 1) - mn, 0.0001)
            let h = map(hi, mn: mn, span: span, size: geo.size)
            let l = map(lo, mn: mn, span: span, size: geo.size)
            ZStack {
                Path { p in
                    guard let f = h.first else { return }
                    p.move(to: f); h.dropFirst().forEach { p.addLine(to: $0) }
                    l.reversed().forEach { p.addLine(to: $0) }
                    p.closeSubpath()
                }
                .fill(accent.opacity(0.18))
                ForEach([h, l].indices, id: \.self) { i in
                    Path { p in
                        let s = i == 0 ? h : l
                        guard let f = s.first else { return }
                        p.move(to: f); s.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(accent.opacity(i == 0 ? 1 : 0.6), lineWidth: led ? 5 : 1.6)
                }
            }
        }
    }
}

/// dual · two series, each normalised to its own range — "two scales, one panel — read the
/// shape, not the gap". No fill, because a fill would say the gap means something.
struct DualRenderer: View {
    let a: [Double]
    let b: [Double]
    let accent: Color
    let secondary: Color
    var led = false

    var body: some View {
        ZStack {
            CurveRenderer(values: b, accent: secondary, fill: false, glow: 0.15, dot: false, led: led)
            CurveRenderer(values: a, accent: accent, fill: false, glow: 0.35, dot: true, led: led)
        }
    }
}

/// column · bars · days · delta. delta uses the zero-axis variant.
struct ColumnRenderer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let bins: [(String, Double)]
    let accent: Color
    var zeroAxis = false
    /// The bars go behind the dot screen and the labels in front of it, so AIPanel draws
    /// this twice; the catalogue draws both at once.
    var showBars = true
    var showLabels = true

    @State private var grown: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let n = max(bins.count, 1)
            let gap: CGFloat = 4
            let w = (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            let mx = max(bins.map { abs($0.1) }.max() ?? 1, 0.0001)
            let axisY = zeroAxis ? geo.size.height / 2 : geo.size.height - 14
            ZStack(alignment: .topLeading) {
                if zeroAxis, showBars {
                    Rectangle().fill(NB.white.opacity(0.10))
                        .frame(height: 1).offset(y: axisY)
                }
                ForEach(showBars ? bins.indices : 0..<0, id: \.self) { i in
                    let v = bins[i].1
                    let h = CGFloat(abs(v) / mx) * (zeroAxis ? geo.size.height / 2 - 8 : geo.size.height - 22) * grown
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(v < 0 && zeroAxis ? NB.alert2 : accent)
                        .frame(width: w, height: max(h, 1))
                        .offset(x: CGFloat(i) * (w + gap),
                                y: v < 0 && zeroAxis ? axisY : axisY - h)
                }
                ForEach(showLabels ? bins.indices : 0..<0, id: \.self) { i in
                    Text(bins[i].0)
                        .font(NBFont.dot(500, 9)).tracking(0.12 * 9)
                        .foregroundStyle(NB.white.opacity(0.32))
                        .frame(width: w)
                        .offset(x: CGFloat(i) * (w + gap), y: geo.size.height - 12)
                }
            }
        }
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7)) { grown = 1 } }
    }
}

/// arc · ring · gauge · battery.
struct ArcRenderer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fraction: Double
    let accent: Color
    let label: String
    var showLabel = true
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().strokeBorder(NB.barTrack, lineWidth: 10)
            RingArc(from: 0, to: shown)
                .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .padding(5)
                .shadow(color: accent.opacity(0.35), radius: 8)
            if showLabel {
                Text(label)
                    .font(NBFont.brand(700, 44)).tracking(-0.045 * 44)
                    .foregroundStyle(NB.white.opacity(0.45))
            }
        }
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { shown = min(fraction, 1) } }
    }
}

struct GaugeRenderer: View {
    let value: Double
    let zones: [(Double, Double, String)]
    let accent: Color
    var showLabel = true

    var body: some View {
        let lo = zones.first?.0 ?? 0
        let hi = zones.last?.1 ?? 1
        let span = max(hi - lo, 0.0001)
        ZStack {
            ForEach(zones.indices, id: \.self) { i in
                RingArc(from: (zones[i].0 - lo) / span * 0.75,
                        to: (zones[i].1 - lo) / span * 0.75)
                    .stroke(zoneColor(i).opacity(0.5), style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                    .rotationEffect(.degrees(225))
            }
            RingArc(from: 0, to: (value - lo) / span * 0.75)
                .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(225))
            if showLabel {
                Text(Fmt.kg(value, decimals: 0))
                    .font(NBFont.brand(700, 44)).tracking(-0.045 * 44)
                    .foregroundStyle(NB.white.opacity(0.45))
            }
        }
    }
    private func zoneColor(_ i: Int) -> Color {
        [NB.barTrack, NB.lime2, NB.lime1, NB.ember1, NB.ember2][min(i, 4)]
    }
}

/// stack · split · fuel · balance. Segments on one track.
struct StackRenderer: View {
    let parts: [(String, Double, Color)]
    /// 10 · split counts minutes, and the board prints them as "1H48 · 24%". fuel and
    /// balance count kcal or grams and print the number. One renderer, two dialects.
    var minutes = false

    var body: some View {
        let total = max(parts.reduce(0) { $0 + $1.1 }, 0.0001)
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(parts[i].2)
                            .frame(width: max(2, geo.size.width * CGFloat(parts[i].1 / total) - 2))
                    }
                }
            }
            .frame(height: 10)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(parts.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(parts[i].2).frame(width: 8, height: 8)
                        Text(parts[i].0.uppercased())
                            .font(NBFont.ui(500, 11)).tracking(0.12 * 11)
                            .foregroundStyle(NB.white.opacity(0.55))
                        Spacer(minLength: 0)
                        Text(minutes ? clock(parts[i].1, of: total) : Fmt.kcal(parts[i].1))
                            .font(NBFont.dot(600, 11))
                            .foregroundStyle(NB.white.opacity(0.80))
                    }
                }
            }
        }
    }
}

extension StackRenderer {
    /// "1H48 · 24%" — the board's own legend for a night.
    fileprivate func clock(_ value: Double, of total: Double) -> String {
        let m = Int(value.rounded())
        let pct = Int((value / total * 100).rounded())
        return m >= 60 ? "\(m / 60)H\(String(format: "%02d", m % 60)) · \(pct)%"
                       : "\(m)M · \(pct)%"
    }
}

/// grid · cells · heat · recomp.
struct GridRenderer: View {
    let rows: Int
    let cols: Int
    let values: [Int]
    let levels: Int
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 3
            let cw = (geo.size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let ch = min(cw, (geo.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(0..<cols, id: \.self) { c in
                            let idx = r * cols + c
                            let v = idx < values.count ? values[idx] : 0
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(v == 0 ? NB.barTrack
                                             : accent.opacity(0.25 + 0.75 * Double(v) / Double(max(levels, 1))))
                                .frame(width: cw, height: ch)
                        }
                    }
                }
            }
        }
    }
}

/// strip · hypnogram · zones. Stacked lanes, never numbers.
struct StripRenderer: View {
    let segments: [(Int, Double)]     // (level, share)
    private let palette: [Color] = [NB.barTrack, NB.lime2, NB.lime1, NB.ember1, NB.ember2]

    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.1 }, 0.0001)
        VStack(spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segments.indices, id: \.self) { i in
                        Rectangle()
                            .fill(palette[min(segments[i].0, palette.count - 1)])
                            .frame(width: max(1, geo.size.width * CGFloat(segments[i].1 / total) - 1))
                    }
                }
            }
            .frame(height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

/// lanes · hypnogram. 07 · 12 · three lanes — AWAKE on top, then LIGHT, then DEEP — with
/// one block per run. The night reads as a shape rather than a bar: where the deep blocks
/// sit is the whole point, and a stacked bar throws that away.
struct LaneRenderer: View {
    /// (lane, minutes) in order. Lane 0 = awake, 1 = light, 2 = deep, 3 = REM.
    let runs: [(Int, Double)]
    let from: String
    let to: String
    var showBlocks = true
    var showLabels = true

    private let names = ["AWAKE", "LIGHT", "DEEP", "REM"]
    private var tint: [Color] { [NB.white.opacity(0.75), NB.violet1.opacity(0.65), NB.violet1, NB.violet1.opacity(0.85)] }

    var body: some View {
        GeometryReader { geo in
            let total = max(runs.reduce(0) { $0 + $1.1 }, 1)
            // 12 · the strip starts under the hero and ends over the clock labels; three
            // lanes share what is left, label tight above its own blocks.
            let top: CGFloat = 34
            let laneH = (geo.size.height - top - 22) / CGFloat(names.count)
            let blockH: CGFloat = 14
            ZStack(alignment: .topLeading) {
                if showLabels {
                    ForEach(0..<names.count, id: \.self) { l in
                        Text(names[l])
                            .font(NBFont.dot(600, 9)).tracking(0.12 * 9)
                            .foregroundStyle(NB.white.opacity(0.34))
                            .offset(y: top + laneH * CGFloat(l))
                    }
                }
                if showBlocks {
                    // One pass over the runs, carrying the x cursor forward.
                    let laid = layout(in: geo.size.width, total: total)
                    ForEach(laid.indices, id: \.self) { i in
                        let b = laid[i]
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(tint[max(0, min(b.lane, names.count - 1))])
                            .frame(width: max(b.width, 2), height: blockH)
                            .offset(x: b.x, y: top + laneH * CGFloat(b.lane) + 15)
                    }
                }
                if showLabels {
                    HStack(spacing: 0) {
                        Text(from); Spacer(minLength: 0); Text(to)
                    }
                    .font(NBFont.dot(500, 9)).tracking(0.12 * 9)
                    .foregroundStyle(NB.white.opacity(0.32))
                    .offset(y: geo.size.height - 12)
                }
            }
        }
    }

    private struct Block { let lane: Int; let x: CGFloat; let width: CGFloat }
    private func layout(in width: CGFloat, total: Double) -> [Block] {
        var x: CGFloat = 0
        return runs.map { run in
            let w = width * CGFloat(run.1 / total)
            defer { x += w }
            return Block(lane: max(0, min(run.0, names.count - 1)), x: x, width: w - 1)
        }
    }
}

/// columns · zones. 07 · 13 · five columns, Z1…Z5, each in its own zone colour, minutes
/// under them. The board's own scale: Z1 track grey, then lime, yellow, amber, red.
struct ZoneColumnsRenderer: View {
    let minutes: [Double]
    var showBars = true
    var showLabels = true

    private var palette: [Color] { [NB.barTrack, NB.lime2, NB.lime1, NB.ember1, NB.alert2] }

    var body: some View {
        GeometryReader { geo in
            let n = max(minutes.count, 1)
            let gap: CGFloat = 10
            let w = (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            let mx = max(minutes.max() ?? 1, 1)
            let plot = geo.size.height - 18
            ZStack(alignment: .topLeading) {
                ForEach(showBars ? minutes.indices : 0..<0, id: \.self) { i in
                    let h = CGFloat(minutes[i] / mx) * plot
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(minutes[i] > 0 ? palette[min(i, 4)] : NB.barTrack.opacity(0.5))
                        .frame(width: w, height: max(h, 3))
                        .offset(x: CGFloat(i) * (w + gap), y: plot - max(h, 3))
                }
                ForEach(showLabels ? minutes.indices : 0..<0, id: \.self) { i in
                    Text("Z\(i + 1)")
                        .font(NBFont.dot(600, 9)).tracking(0.12 * 9)
                        .foregroundStyle(NB.white.opacity(minutes[i] > 0 ? 0.55 : 0.28))
                        .frame(width: w)
                        .offset(x: CGFloat(i) * (w + gap), y: geo.size.height - 12)
                }
            }
        }
    }
}

/// trace · wave. ECG paper: a grid in millimetres, then one line.
struct TraceRenderer: View {
    let samples: [Double]
    let hz: Double
    let accent: Color
    var led = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { ctx, size in
                    var g = Path()
                    var x: CGFloat = 0
                    while x < size.width { g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: size.height)); x += 10 }
                    var y: CGFloat = 0
                    while y < size.height { g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y)); y += 10 }
                    ctx.stroke(g, with: .color(NB.white.opacity(0.06)), lineWidth: 0.5)
                }
                Path { p in
                    guard samples.count > 1 else { return }
                    let mn = samples.min()!, mx = samples.max()!
                    let span = max(mx - mn, 0.0001)
                    for (i, v) in samples.enumerated() {
                        let pt = CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(samples.count - 1),
                                         y: geo.size.height * (1 - CGFloat((v - mn) / span)) * 0.8 + geo.size.height * 0.1)
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: led ? 5 : 1.6, lineJoin: .round))
            }
        }
    }
}

/// rows · sparks · table · events · workout · meal.
struct RowsRenderer: View {
    let items: [PanelData.RowItem]
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Circle().fill(items[i].tint ?? accent).frame(width: 5, height: 5)
                    Text(items[i].label.uppercased())
                        .font(NBFont.ui(500, 11)).tracking(0.10 * 11)
                        .foregroundStyle(NB.white.opacity(0.62))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let spark = items[i].spark, spark.count > 1 {
                        Sparkline(values: spark, tint: items[i].tint ?? accent)
                            .frame(width: 64, height: 16)
                    }
                    Text(items[i].value)
                        .font(NBFont.dot(600, 12))
                        .foregroundStyle(NB.white.opacity(0.88))
                        .frame(minWidth: 48, alignment: .trailing)
                }
                .frame(height: 34)
                if i < items.count - 1 { Hairline() }
            }
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            Path { p in
                guard values.count > 1 else { return }
                let mn = values.min()!, mx = values.max()!
                let span = max(mx - mn, 0.0001)
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(values.count - 1),
                                     y: geo.size.height * (1 - CGFloat((v - mn) / span)))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}
