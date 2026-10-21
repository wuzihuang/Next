import SwiftUI

struct ScanBody: View {
    var beat: Int
    var total: Int = 30
    var beatAt: Date
    var active: Bool = true
    var held: Bool = false
    var complete: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearedAt = Date()

    private static let cloud = BodyCloud.shared
    private static let base = Color(hex: 0xBDF5F0)
    private static let contentBounds = cloudBounds()
    private static let sternumArtwork = CGPoint(x: 0.5, y: 0.28)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: held || reduceMotion)) { timeline in
            Canvas(rendersAsynchronously: false) { context, size in
                draw(&context, size: size, now: timeline.date)
            }
        }
        .accessibilityLabel(active
            ? L("Body scan, %d of %d seconds", beat, total)
            : L("Waiting for contact"))
        .onAppear { appearedAt = .now }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, now: Date) {
        let cloud = Self.cloud
        guard !cloud.motes.isEmpty else { return }
        let artwork = Self.contentBounds
        let aspect = cloud.aspect * artwork.width / artwork.height
        let boxHeight = min(size.height * 0.96, size.width * 0.85 / aspect)
        let boxWidth = boxHeight * aspect
        let box = CGRect(x: (size.width - boxWidth) / 2,
                         y: (size.height - boxHeight) / 2,
                         width: boxWidth, height: boxHeight)
        guard box.height > 4 else { return }

        let scale = min(1.6, max(0.55, box.height / CGFloat(cloud.rows) / 1.8))
        let clock = reduceMotion ? 0 : now.timeIntervalSinceReferenceDate
        let gatherAge = reduceMotion ? 2 : now.timeIntervalSince(appearedAt)
        let beatAge = reduceMotion ? 1 : now.timeIntervalSince(beatAt)
        let beatBlend = reduceMotion ? 1 : smooth(beatAge / 0.9)
        let progress = complete ? 1 : min(1, max(0,
            (Double(max(0, beat - 1)) + Double(beatBlend)) / Double(max(1, total))))
        let scanY = 0.98 - progress * 0.96
        let lineY = box.minY + CGFloat(scanY) * box.height
        let tint = held ? NB.ember1 : NB.lime1
        let flareColor = held ? NB.ember2 : NB.limePale
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -24, dy: -24)

        var ghost = [Path](repeating: Path(), count: 2)
        var lit = [Path](repeating: Path(), count: 4)
        var haloGhost = Path()
        var haloLit = Path()
        var flarePath = Path()
        var sparkPath = Path()

        for mote in cloud.motes {
            let delay = Double(mote.y) * 0.15 + Double(mote.seed) * 0.08
            let gather = reduceMotion ? 1 : easeOut((gatherAge - delay) / 0.9)
            guard gather > 0.01 else { continue }
            let away = CGFloat(1 - gather)
            let torso = bump(mote.y, 0.16, 0.56)
            let breath = CGFloat(sin(clock * 2 * .pi / 4.8))
            let artworkX = 0.5 + (mote.x - 0.5) * (1 + 0.014 * breath * torso)
            let artworkY = mote.y - 0.003 * breath * torso
            let x = (artworkX - artwork.minX) / artwork.width
            let y = (artworkY - artwork.minY) / artwork.height
            let px = box.minX + x * box.width + mote.scatterX * away * box.height
                + CGFloat(sin(clock * 0.8 + Double(mote.phase))) * 0.7 * scale
            let py = box.minY + y * box.height + mote.scatterY * away * box.height
                + CGFloat(cos(clock * 0.6 + Double(mote.phase) * 1.7)) * 0.7 * scale
            guard bounds.contains(CGPoint(x: px, y: py)) else { continue }

            let flare = active && !complete
                ? max(0, 1 - abs(Double(y) - scanY) / max(0.006, 6 / Double(box.height)))
                : 0
            let sheen: Double
            if complete && !reduceMotion {
                let sweep = clock.truncatingRemainder(dividingBy: 2.4) / 2.4
                sheen = exp(-pow((Double(y) - sweep) / 0.035, 2))
            } else {
                sheen = 0
            }
            let isLit = active && (complete || Double(y) >= scanY)
            let twinkle = 0.6 + 0.4 * sin(clock * (1.2 + Double(mote.seed) * 3) + Double(mote.phase))
            let side = (0.9 + mote.light * 1.1) * scale
            let rect = CGRect(x: px - side / 2, y: py - side / 2, width: side, height: side)
            let haloSide = 2.6 * scale

            if isLit {
                let intensity = min(1, (Double(mote.light) * twinkle * 1.2)
                    + flare * 0.45 + sheen * 0.35)
                let level = min(lit.count - 1, max(0, Int(intensity * Double(lit.count))))
                let grow = 1 + CGFloat(flare * 0.7 + sheen * 0.25)
                lit[level].addRect(CGRect(x: px - side * grow / 2, y: py - side * grow / 2,
                                          width: side * grow, height: side * grow))
                if mote.light > 0.35 {
                    haloLit.addRect(CGRect(x: px - haloSide / 2, y: py - haloSide / 2,
                                           width: haloSide, height: haloSide))
                }
                if flare > 0.72 || sheen > 0.72 {
                    flarePath.addRect(rect.insetBy(dx: -0.45 * scale, dy: -0.45 * scale))
                }
            } else {
                let intensity = 0.36 + Double(mote.light) * twinkle * 0.12
                ghost[min(1, Int(intensity * 4))].addRect(rect)
                if mote.light > 0.35 {
                    haloGhost.addRect(CGRect(x: px - haloSide / 2, y: py - haloSide / 2,
                                             width: haloSide, height: haloSide))
                }
            }
        }

        context.blendMode = .plusLighter
        for (index, path) in ghost.enumerated() where !path.isEmpty {
            context.fill(path, with: .color(Self.base.opacity(0.34 + Double(index) * 0.1)))
        }
        for (index, path) in lit.enumerated() where !path.isEmpty {
            context.fill(path, with: .color(tint.opacity(0.54 + Double(index) * 0.14)))
        }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.blendMode = .plusLighter
            layer.fill(haloGhost, with: .color(Self.base.opacity(0.16)))
            layer.fill(haloLit, with: .color(tint.opacity(held ? 0.26 : 0.32)))
        }
        if !flarePath.isEmpty {
            context.fill(flarePath, with: .color(flareColor.opacity(held ? 0.8 : 0.95)))
        }

        if active && !complete {
            drawSparks(cloud: cloud, box: box, scale: scale,
                       bounds: artwork, scanY: scanY, clock: clock, path: &sparkPath)
            if !sparkPath.isEmpty {
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 4))
                    layer.blendMode = .plusLighter
                    layer.fill(sparkPath, with: .color(tint.opacity(0.52)))
                }
                context.fill(sparkPath, with: .color(flareColor.opacity(0.82)))
            }
            drawScanLine(&context, size: size, y: lineY, tint: tint)
        }

        if !active {
            drawSternum(&context, box: box, scale: scale, clock: clock)
        }
        if active && (progress > 0.02 || complete) {
            let foot = CGPoint(x: box.midX, y: box.maxY - 3 * scale)
            let pool = Path(ellipseIn: CGRect(x: foot.x - box.width * 0.24,
                                              y: foot.y - 12 * scale,
                                              width: box.width * 0.48,
                                              height: 22 * scale))
            context.fill(pool, with: .radialGradient(
                Gradient(colors: [tint.opacity(0.2 * progress), tint.opacity(0)]),
                center: foot, startRadius: 0, endRadius: box.width * 0.24))
        }
        context.blendMode = .normal
    }

    private func drawSparks(cloud: BodyCloud, box: CGRect, scale: CGFloat, bounds: CGRect,
                            scanY: Double, clock: Double, path: inout Path) {
        guard !cloud.emitters.isEmpty else { return }
        for index in 0..<min(60, cloud.emitters.count) {
            let mote = cloud.motes[cloud.emitters[(index * 131) % cloud.emitters.count]]
            let y = (mote.y - bounds.minY) / bounds.height
            guard Double(y) >= scanY else { continue }
            let rate = 0.08 + 0.1 * Double((mote.seed * 13.3).truncatingRemainder(dividingBy: 1))
            let phase = (clock * rate + Double(mote.phase) / (2 * .pi)).truncatingRemainder(dividingBy: 1)
            let x = box.minX + (mote.x - bounds.minX) / bounds.width * box.width
                + CGFloat(sin(clock * 0.9 + Double(mote.phase))) * 4 * scale
            let py = box.minY + (y - CGFloat(phase) * 0.12) * box.height
            let side = 1.8 * scale
            path.addRect(CGRect(x: x - side / 2, y: py - side / 2,
                                width: side, height: side))
        }
    }

    private func drawScanLine(_ context: inout GraphicsContext, size: CGSize,
                              y: CGFloat, tint: Color) {
        let width = size.width * 0.85
        let band = CGRect(x: (size.width - width) / 2, y: y, width: width, height: 28)
        let glow = Path(ellipseIn: band)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.blendMode = .plusLighter
            layer.fill(glow, with: .linearGradient(
                Gradient(stops: [
                    .init(color: tint.opacity(0), location: 0),
                    .init(color: tint.opacity(0.22), location: 0.5),
                    .init(color: tint.opacity(0), location: 1),
                ]),
                startPoint: CGPoint(x: band.minX, y: band.midY),
                endPoint: CGPoint(x: band.maxX, y: band.midY)))
        }
        var line = Path()
        line.move(to: CGPoint(x: band.minX, y: y))
        line.addLine(to: CGPoint(x: band.maxX, y: y))
        context.stroke(line, with: .linearGradient(
            Gradient(stops: [
                .init(color: tint.opacity(0), location: 0),
                .init(color: tint.opacity(0.88), location: 0.2),
                .init(color: NB.limePale.opacity(0.95), location: 0.5),
                .init(color: tint.opacity(0.88), location: 0.8),
                .init(color: tint.opacity(0), location: 1),
            ]),
            startPoint: CGPoint(x: band.minX, y: y),
            endPoint: CGPoint(x: band.maxX, y: y)),
            lineWidth: 1)
    }

    private func drawSternum(_ context: inout GraphicsContext, box: CGRect,
                             scale: CGFloat, clock: Double) {
        let alpha = reduceMotion ? 0.58 : 0.42 + 0.3 * (0.5 + 0.5 * sin(clock / 0.6))
        let bounds = Self.contentBounds
        let sternumX = (Self.sternumArtwork.x - bounds.minX) / bounds.width
        let sternumY = (Self.sternumArtwork.y - bounds.minY) / bounds.height
        let point = CGPoint(x: box.minX + sternumX * box.width,
                            y: box.minY + sternumY * box.height)
        context.fill(Path(ellipseIn: CGRect(x: point.x - 14 * scale, y: point.y - 14 * scale,
                                            width: 28 * scale, height: 28 * scale)),
                     with: .radialGradient(
                        Gradient(colors: [NB.lime1.opacity(alpha * 0.55), NB.lime1.opacity(0)]),
                        center: point, startRadius: 0, endRadius: 14 * scale))
        context.fill(Path(ellipseIn: CGRect(x: point.x - 1.6 * scale, y: point.y - 1.6 * scale,
                                            width: 3.2 * scale, height: 3.2 * scale)),
                     with: .color(NB.lime1.opacity(alpha)))
    }

    private func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    private func easeOut(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return 1 - pow(1 - t, 3)
    }

    private func bump(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        let t = (value - low) / (high - low)
        guard t > 0, t < 1 else { return 0 }
        return sin(t * .pi)
    }

    private static func cloudBounds() -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for mote in cloud.motes where mote.light > 0.14 {
            minX = min(minX, mote.x)
            minY = min(minY, mote.y)
            maxX = max(maxX, mote.x)
            maxY = max(maxY, mote.y)
        }
        guard maxX > minX, maxY > minY else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
