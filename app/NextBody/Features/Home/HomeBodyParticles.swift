import SwiftUI
import UIKit

/// The body-scan figure as a live point cloud. The points are sampled once from the `HomeBody`
/// artwork by brightness; on screen they gather, breathe, shimmer and get swept by a scan line.
struct HomeBodyParticles: View {
    /// One per `HomeV2Model.Zone`, in `allCases` order: head, heart, gut, legs.
    var spots: [BodyCloud.Spot]
    /// Only the page on screen animates.
    var active: Bool
    var lens: BodyLens = .fit
    /// false: the figure is already standing on first show, only the ripple and sweep play.
    var gathers = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.homeArtActive) private var artActive
    /// Set the first time the page is shown. Until then nothing is drawn, so the first visit
    /// watches the figure assemble; later visits get a ripple and a fresh sweep instead.
    @State private var gatheredAt: Date?
    @State private var pulsedAt = Date.distantPast

    var body: some View {
        let cloud = lens.height == nil ? BodyCloud.shared : BodyCloud.dense
        let shown = gatheredAt != nil || reduceMotion
        ZStack {
            BodyCloudHalo(cloud: cloud, lens: lens)
                .opacity(shown ? 1 : 0)
                .animation(.easeOut(duration: 1.4).delay(gathers ? 0.6 : 0), value: shown)
            // ⚠️ Thousands of motes are rebuilt into paths every frame. Drawn on the main thread
            // at 60 Hz this competed with the finger for every page turn and push.
            TimelineView(.animation(minimumInterval: 1.0 / 30,
                                    paused: !active || !artActive || reduceMotion)) { timeline in
                Canvas(rendersAsynchronously: true) { context, size in
                    let frame = BodyCloud.Frame(now: timeline.date,
                                                gatheredAt: reduceMotion ? .distantPast : gatheredAt,
                                                pulsedAt: pulsedAt,
                                                spots: spots,
                                                lens: lens,
                                                still: reduceMotion)
                    cloud.draw(in: &context, size: size, frame: frame)
                }
            }
        }
        .onAppear { if active { arrive() } }
        .onChange(of: active) { _, now in if now { arrive() } }
        .accessibilityHidden(true)
    }

    private func arrive() {
        if gatheredAt == nil { gatheredAt = gathers ? .now : .distantPast }
        pulsedAt = .now
    }
}

/// Where the artwork sits in its canvas: fitted whole, or enlarged around one point.
struct BodyLens: Equatable, Sendable {
    /// Figure height in points. nil fits the whole figure in the canvas.
    var height: CGFloat?
    /// The artwork point (0…1) that lands on `target`.
    var focus = CGPoint(x: 0.5, y: 0.5)
    /// Where `focus` lands, in canvas units.
    var target = CGPoint(x: 0.5, y: 0.5)

    static let fit = BodyLens()

    func box(in size: CGSize, aspect: CGFloat) -> CGRect {
        guard let height else {
            var fitHeight = size.height
            var fitWidth = fitHeight * aspect
            if fitWidth > size.width {
                fitWidth = size.width
                fitHeight = fitWidth / aspect
            }
            return CGRect(x: (size.width - fitWidth) / 2, y: (size.height - fitHeight) / 2,
                          width: fitWidth, height: fitHeight)
        }
        let width = height * aspect
        return CGRect(x: target.x * size.width - focus.x * width,
                      y: target.y * size.height - focus.y * height,
                      width: width, height: height)
    }
}

extension HomeV2Model.Zone {
    /// The middle of the body part, in `HomeBody` artwork units. Leader lines end here,
    /// the tap zooms in around it, and the detail page frames it.
    var anchor: CGPoint {
        switch self {
        case .head: CGPoint(x: 0.5, y: 0.115)
        case .heart: CGPoint(x: 0.56, y: 0.265)
        case .gut: CGPoint(x: 0.5, y: 0.43)
        case .legs: CGPoint(x: 0.45, y: 0.72)
        }
    }

    /// The close-up on the detail page: figure height, and where the anchor lands.
    var closeUp: BodyLens {
        switch self {
        case .head: BodyLens(height: 980, focus: anchor, target: CGPoint(x: 0.74, y: 0.34))
        case .heart: BodyLens(height: 760, focus: anchor, target: CGPoint(x: 0.68, y: 0.34))
        case .gut: BodyLens(height: 800, focus: anchor, target: CGPoint(x: 0.70, y: 0.30))
        case .legs: BodyLens(height: 900, focus: anchor, target: CGPoint(x: 0.72, y: 0.42))
        }
    }
}

/// Soft aura under the points. Drawn once per size, blurred on the GPU.
private struct BodyCloudHalo: View {
    let cloud: BodyCloud
    let lens: BodyLens

    var body: some View {
        Canvas { context, size in
            cloud.drawHalo(in: &context, size: size, lens: lens)
        }
        .blur(radius: 7)
        .blendMode(.plusLighter)
    }
}

struct BodyCloud: Sendable {
    struct Mote: Sendable {
        /// 0…1 of the artwork.
        var x: CGFloat
        var y: CGFloat
        /// 0…1 brightness of the source pixel.
        var light: CGFloat
        var seed: CGFloat
        var phase: CGFloat
        /// Where the point waits before it gathers, in figure heights from home.
        var scatterX: CGFloat
        var scatterY: CGFloat
    }

    /// One zone's light: how hot it burns and in which colour. Intensity 0 leaves the motes white.
    struct Spot: Sendable {
        var intensity: Double
        var tint: Color
    }

    struct Frame {
        var now: Date
        /// nil: the page has not been shown yet.
        var gatheredAt: Date?
        var pulsedAt: Date
        /// In `HomeV2Model.Zone.allCases` order. A spot with intensity 0 tints nothing.
        var spots: [Spot]
        var lens: BodyLens
        var still: Bool
    }

    let aspect: CGFloat
    /// Sampling rows; sets the point size so the cloud reads as solid at any zoom.
    let rows: Int
    let motes: [Mote]
    /// Bright points that shed rising dust.
    let emitters: [Int]

    static let shared = BodyCloud.sample(named: "HomeBody", cols: 150)
    /// For close-ups. About three times the points; only those on screen are drawn.
    static let dense = BodyCloud.sample(named: "HomeBody", cols: 260)

    private static let levels = 6
    /// Tone zero: the untinted mote colour, and the scan line.
    private static let base = Color(hex: 0xBDF5F0)
    /// Zones in artwork units, in `HomeV2Model.Zone.allCases` order: head, heart, gut, legs.
    /// Narrow enough that the arms and hands beside the torso stay untinted.
    private static let zones: [CGRect] = [CGRect(x: 0.36, y: 0.00, width: 0.28, height: 0.19),
                                          CGRect(x: 0.48, y: 0.20, width: 0.20, height: 0.14),
                                          CGRect(x: 0.33, y: 0.37, width: 0.34, height: 0.15),
                                          CGRect(x: 0.34, y: 0.52, width: 0.32, height: 0.46)]

    static func sample(named name: String, cols: Int) -> BodyCloud {
        guard let image = UIImage(named: name)?.cgImage else {
            return BodyCloud(aspect: 0.56, rows: 1, motes: [], emitters: [])
        }
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        let rows = Int((CGFloat(cols) / aspect).rounded())
        var pixels = [UInt8](repeating: 0, count: cols * rows)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let bitmap = CGContext(data: raw.baseAddress, width: cols, height: rows,
                                         bitsPerComponent: 8, bytesPerRow: cols,
                                         space: CGColorSpaceCreateDeviceGray(),
                                         bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            bitmap.interpolationQuality = .medium
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: cols, height: rows))
            return true
        }
        guard drawn else { return BodyCloud(aspect: aspect, rows: rows, motes: [], emitters: []) }

        var rng = SplitMix(state: 0x5EED_B0D1)
        var motes: [Mote] = []
        var emitters: [Int] = []
        motes.reserveCapacity(cols * rows / 8)
        for row in 0..<rows {
            for col in 0..<cols {
                let light = CGFloat(pixels[row * cols + col]) / 255
                guard light > 0.14, rng.unit() < min(1, (light - 0.1) * 1.7) else { continue }
                let x = (CGFloat(col) + rng.unit()) / CGFloat(cols)
                let y = (CGFloat(row) + rng.unit()) / CGFloat(rows)
                let angle = atan2(y - 0.45, (x - 0.5) * aspect) + (rng.unit() - 0.5) * 1.4
                let reach = 0.2 + rng.unit() * 0.5
                if light > 0.55 && rng.unit() < 0.3 { emitters.append(motes.count) }
                motes.append(Mote(x: x, y: y, light: min(1, light * 1.15),
                                  seed: rng.unit(), phase: rng.unit() * 2 * .pi,
                                  scatterX: cos(angle) * reach, scatterY: sin(angle) * reach))
            }
        }
        return BodyCloud(aspect: aspect, rows: rows, motes: motes, emitters: emitters)
    }

    func draw(in context: inout GraphicsContext, size: CGSize, frame: Frame) {
        guard !motes.isEmpty, let gatheredAt = frame.gatheredAt else { return }
        let box = frame.lens.box(in: size, aspect: aspect)
        guard box.height > 4 else { return }
        let scale = min(1.6, max(0.55, box.height / CGFloat(rows) / 1.8))
        let levels = Self.levels
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -24, dy: -24)
        /// The sweep crosses the visible part of the figure, whole or close-up.
        let top = max(0, -box.minY / box.height)
        let span = max(0.05, min(1, (size.height - box.minY) / box.height) - top)

        let clock = frame.still ? 0 : frame.now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
        let gatherAge = frame.now.timeIntervalSince(gatheredAt)
        let pulseAge = frame.still ? .infinity : frame.now.timeIntervalSince(frame.pulsedAt)
        let breath = CGFloat(sin(clock * 2 * .pi / 4.8))
        let ripple = pulseAge < 0.9 ? CGFloat(sin(pulseAge / 0.9 * .pi)) : 0
        let settle = CGFloat(min(1, max(0, (gatherAge - 1.6) / 0.8)))
        let scanClock = pulseAge < 1e6 ? pulseAge : clock
        let scanY: CGFloat? = frame.still
            ? nil
            : top + (CGFloat((scanClock / 5.2).truncatingRemainder(dividingBy: 1)) * 1.3 - 0.15) * span

        var paths = [Path](repeating: Path(), count: (1 + frame.spots.count) * levels)
        var flares = Path()

        func put(_ x: CGFloat, _ y: CGFloat, side: CGFloat, alpha: CGFloat, tone: Int) {
            guard alpha > 0.04 else { return }
            let level = min(levels - 1, Int(alpha * CGFloat(levels)))
            paths[tone * levels + level].addRect(CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side))
        }

        for mote in motes {
            guard bounds.contains(CGPoint(x: box.minX + mote.x * box.width,
                                          y: box.minY + mote.y * box.height)) else { continue }
            let delay = Double(mote.y) * 0.55 + Double(mote.seed) * 0.45
            let progress = min(1, max(0, (gatherAge - delay) / 1.2))
            let ease = CGFloat(1 - pow(1 - progress, 3))
            guard ease > 0.01 else { continue }
            let away = 1 - ease

            let torso = Self.bump(mote.y, 0.16, 0.56)
            var x = 0.5 + (mote.x - 0.5) * (1 + 0.014 * breath * torso)
            var y = mote.y - 0.003 * breath * torso
            var bright = mote.light
            var grow: CGFloat = 1
            if let scanY {
                let d = (y - scanY) / (0.022 * span)
                let band = exp(-d * d) * settle
                x += (x - 0.5) * band * 0.035
                bright += band * 0.8
                grow += band * 0.7
            }
            if ripple > 0 {
                let push = ripple * (0.012 + 0.02 * mote.seed)
                x += (mote.x - 0.5) * push * 2
                y += (mote.y - 0.45) * push
                bright += ripple * 0.3
            }

            let px = box.minX + x * box.width + mote.scatterX * away * box.height
                + CGFloat(sin(clock * 0.8 + Double(mote.phase))) * 0.7 * scale
            let py = box.minY + y * box.height + mote.scatterY * away * box.height
                + CGFloat(cos(clock * 0.6 + Double(mote.phase) * 1.7)) * 0.7 * scale
            let twinkle = 0.6 + 0.4 * CGFloat(sin(clock * (1.2 + Double(mote.seed) * 3) + Double(mote.phase)))
            let alpha = min(1, bright * twinkle) * ease
            let side = (0.9 + mote.light * 1.1) * scale * grow

            var tone = 0
            if let zone = Self.zones.firstIndex(where: { $0.contains(CGPoint(x: mote.x, y: mote.y)) }),
               zone < frame.spots.count,
               (mote.seed * 37.7).truncatingRemainder(dividingBy: 1) < CGFloat(frame.spots[zone].intensity) * 0.8 {
                tone = zone + 1
            }
            put(px, py, side: side, alpha: alpha, tone: tone)

            if mote.seed > 0.992 && sin(clock * 0.7 + Double(mote.phase) * 3) > 0.94 {
                let arm = 4 * scale
                flares.addRect(CGRect(x: px - arm, y: py - 0.4, width: arm * 2, height: 0.8))
                flares.addRect(CGRect(x: px - 0.4, y: py - arm, width: 0.8, height: arm * 2))
            }
        }

        if !frame.still && settle > 0 && !emitters.isEmpty {
            for index in 0..<min(70, emitters.count) {
                let mote = motes[emitters[(index * 131) % emitters.count]]
                let rate = 0.08 + 0.1 * Double((mote.seed * 13.3).truncatingRemainder(dividingBy: 1))
                let life = CGFloat((clock * rate + Double(mote.phase) / (2 * .pi)).truncatingRemainder(dividingBy: 1))
                let px = box.minX + mote.x * box.width + CGFloat(sin(clock * 0.9 + Double(mote.phase))) * 4 * scale
                let py = box.minY + (mote.y - life * 0.12) * box.height
                put(px, py, side: 1.2 * scale, alpha: sin(life * .pi) * 0.55 * settle, tone: 0)
            }
        }

        context.blendMode = .plusLighter
        if let scanY, settle > 0, (0...1).contains(scanY) {
            let lineY = box.minY + scanY * box.height
            let left = max(0, box.minX)
            let right = min(size.width, box.maxX)
            context.fill(Path(CGRect(x: left, y: lineY - 0.5, width: right - left, height: 1)),
                         with: .linearGradient(Gradient(colors: [Self.base.opacity(0),
                                                                 Self.base.opacity(0.5 * settle),
                                                                 Self.base.opacity(0)]),
                                               startPoint: CGPoint(x: left, y: lineY),
                                               endPoint: CGPoint(x: right, y: lineY)))
        }
        context.blendMode = .normal
        for tone in 0...frame.spots.count {
            let tint = tone == 0 ? Self.base : frame.spots[tone - 1].tint
            for level in 0..<levels {
                let path = paths[tone * levels + level]
                guard !path.isEmpty else { continue }
                let opacity = (Double(level) + 0.5) / Double(levels)
                context.fill(path, with: .color(tint.opacity(opacity)))
            }
        }
        context.fill(flares, with: .color(NB.white.opacity(0.85)))
    }

    func drawHalo(in context: inout GraphicsContext, size: CGSize, lens: BodyLens) {
        let box = lens.box(in: size, aspect: aspect)
        guard box.height > 4 else { return }
        let side = 2.6 * min(1.6, max(0.55, box.height / CGFloat(rows) / 1.8))
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -16, dy: -16)
        var halo = Path()
        for mote in motes where mote.light > 0.35 {
            let point = CGPoint(x: box.minX + mote.x * box.width, y: box.minY + mote.y * box.height)
            guard bounds.contains(point) else { continue }
            halo.addRect(CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side))
        }
        context.fill(halo, with: .color(Self.base.opacity(0.32)))
    }

    private static func bump(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        let t = (value - low) / (high - low)
        guard t > 0, t < 1 else { return 0 }
        return sin(t * .pi)
    }
}

/// Deterministic, so the figure is the same constellation on every launch.
private struct SplitMix {
    var state: UInt64

    mutating func unit() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(UInt64(1) << 53)
    }
}
