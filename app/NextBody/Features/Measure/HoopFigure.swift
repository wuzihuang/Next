import SwiftUI

struct HoopFigure: View {
    enum Mode: Equatable {
        case waiting, nudge, contact, lit
    }

    var mode: Mode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var changedAt = Date()

    private static let centre = CGPoint(x: 191, y: 234)
    private static let frameWidth: CGFloat = 150
    private static let frameHeight: CGFloat = 268
    private static let keyCentre = CGPoint(x: 269, y: 234)
    private static let keyEdge: CGFloat = 272
    private static let fingerImageSide: CGFloat = 285
    private static let fingerAnchor = CGPoint(x: 0.204, y: 0.363)
    private static let fingerAxis = CGVector(dx: 0.908, dy: 0.417)
    private static let outer = Self.makeOuter()
    private static let inner = Path(roundedRect: CGRect(x: 132, y: 120, width: 118, height: 228),
                                    cornerRadius: 8)
    private static let particles = ParticleSet()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let scale = min(size.width * 0.38 / Self.frameWidth,
                                size.height * 0.9 / Self.frameHeight)
                context.translateBy(x: size.width * 0.46 - Self.centre.x * scale,
                                    y: size.height * 0.5 - Self.centre.y * scale)
                context.scaleBy(x: scale, y: scale)
                let now = reduceMotion ? changedAt : timeline.date
                let elapsed = reduceMotion
                    ? (mode == .contact ? 1.2 : 0)
                    : now.timeIntervalSince(changedAt)
                draw(&context, elapsed: max(0, elapsed), time: now.timeIntervalSinceReferenceDate,
                     scale: scale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
        .onChange(of: mode) { _, _ in changedAt = .now }
    }

    private func draw(_ context: inout GraphicsContext, elapsed: Double,
                      time: Double, scale: CGFloat) {
        let contact = mode == .contact
        let waiting = mode == .waiting || mode == .nudge
        context.blendMode = .plusLighter
        drawBackdrop(&context, time: time, contact: contact, scale: scale)
        drawInterior(&context, elapsed: elapsed, time: time, contact: contact, scale: scale)
        drawShell(&context, elapsed: elapsed, contact: contact, scale: scale)
        drawKey(&context, time: time, elapsed: elapsed, waiting: waiting,
                nudge: mode == .nudge, contact: contact, scale: scale)
        if mode != .lit {
            drawFinger(&context, elapsed: elapsed, time: time, contact: contact,
                       nudge: mode == .nudge, scale: scale)
        }
        if contact { drawContactBloom(&context, elapsed: elapsed, scale: scale) }
        context.blendMode = .normal
    }

    private func drawBackdrop(_ context: inout GraphicsContext, time: Double,
                              contact: Bool, scale: CGFloat) {
        let haloAlpha: Double = contact ? 0.2 : mode == .lit ? 0.025 : 0.055
        context.fill(Path(ellipseIn: CGRect(x: 35, y: 42, width: 320, height: 386)),
                     with: .radialGradient(
                        Gradient(colors: [NB.lime1.opacity(haloAlpha), NB.lime1.opacity(0)]),
                        center: Self.centre, startRadius: 0, endRadius: 214))

        var dust = [Path](repeating: Path(), count: 2)
        for mote in Self.particles.dust {
            let speed = contact ? 17.0 : mode == .nudge ? 7.5 : 3.2
            let rise = CGFloat((time * speed + mote.phase).truncatingRemainder(dividingBy: 400))
            let y = 35 + (mote.y - 35 - rise + 400).truncatingRemainder(dividingBy: 400)
            let x = mote.x + CGFloat(1.8 * sin(time * 0.15 + mote.phase))
            let dx = Double((x - Self.centre.x) / 150)
            let dy = Double((y - Self.centre.y) / 200)
            let radius = dx * dx + dy * dy
            guard radius < 1.22 else { continue }
            let twinkle = 0.58 + 0.42 * sin(time * 1.6 + mote.phase)
            let boost = contact ? 1.7 : mode == .nudge ? 1.15 : 1
            let alpha = min(0.34, mote.alpha * (1 - min(0.85, radius * 0.55)) * twinkle * boost)
            addSquare(x: x, y: y, screenSide: mote.size, scale: scale,
                      alpha: min(1, alpha * 3), to: &dust)
        }
        for (index, path) in dust.enumerated() where !path.isEmpty {
            context.fill(path, with: .color(NB.lime1.opacity(index == 0 ? 0.08 : 0.28)))
        }
    }

    private func drawInterior(_ context: inout GraphicsContext, elapsed: Double,
                              time: Double, contact: Bool, scale: CGFloat) {
        let settled = contact ? min(1, max(0, (elapsed - 0.2) / 1.0)) : 0
        let opening = Self.inner.boundingRect
        let sweep = opening.maxX - CGFloat(settled) * opening.width
        let flow = CGFloat(time * (contact ? 0.75 : 0.18))
        var buckets = [Path](repeating: Path(), count: 4)
        var rim = Path()

        context.fill(Self.inner, with: .radialGradient(
            Gradient(colors: [NB.lime1.opacity(contact ? 0.95 : mode == .lit ? 0.015 : 0.62),
                              NB.lime1.opacity(contact ? 0.07 : 0.025)]),
            center: Self.centre, startRadius: 0, endRadius: 112))

        for point in Self.particles.knit {
            let dx = Double((point.x - Self.centre.x) / (opening.width * 0.52))
            let dy = Double((point.y - Self.centre.y) / (opening.height * 0.52))
            let radial = exp(-(dx * dx + dy * dy))
            let twill = pow(0.55 + 0.45 * sin(Double(point.x + point.y) * 0.075),
                           1.2) * pow(0.55 + 0.45 * sin(Double(point.x - point.y) * 0.071), 1.2)
            let x = Double(point.x)
            let streak = max(exp(-pow((x - 151) / 5.5, 2)),
                             max(exp(-pow((x - 191) / 5, 2)),
                                 exp(-pow((x - 231) / 5.5, 2))))
            let wave = 0.84 + 0.16 * sin(Double(point.y * 0.05) - Double(flow))
            let twinkle = 0.8 + 0.2 * sin(time * 0.8 + point.phase)
            let breath = contact ? 1 : 0.92 + 0.08 * sin(time * 2 * .pi / 4.8)
            var alpha: Double = (contact ? 0.94 + settled * 0.05 : mode == .lit ? 0.14 : 0.56)
                * (0.68 + 0.32 * twill) * wave * twinkle * breath
                * (0.34 + 0.66 * radial + 0.16 * streak)

            if contact {
                let behind = max(0, point.x - sweep)
                alpha *= 0.34 + 0.66 * Double(min(1, behind / 20))
                if abs(point.x - sweep) < 1.4 {
                    buckets[3].addRect(CGRect(x: point.x - 1.2 / scale,
                                              y: point.y - 1.2 / scale,
                                              width: 2.4 / scale, height: 2.4 / scale))
                }
            }
            let level = min(buckets.count - 1, max(0, Int(min(1, alpha) * Double(buckets.count))))
            let side = point.size / scale
            buckets[level].addRect(CGRect(x: point.x - side / 2, y: point.y - side / 2,
                                          width: side, height: side))
            if point.edge < 5 && alpha > 0.18 {
                rim.addRect(CGRect(x: point.x - 0.7 / scale, y: point.y - 0.7 / scale,
                                   width: 1.4 / scale, height: 1.4 / scale))
            }
        }
        for (index, path) in buckets.enumerated() where !path.isEmpty {
            let color = contact && index == 3 ? NB.limePale : NB.lime1
            let opacity = contact ? 0.2 + Double(index) * 0.2
                : mode == .lit ? 0.08 + Double(index) * 0.035 : 0.12 + Double(index) * 0.17
            context.fill(path, with: .color(color.opacity(opacity)))
        }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 7))
            layer.blendMode = .plusLighter
            layer.fill(rim, with: .color(NB.lime1.opacity(contact ? 0.36 : 0.18)))
        }
    }

    private func drawShell(_ context: inout GraphicsContext, elapsed: Double,
                           contact: Bool, scale: CGFloat) {
        var buckets = [Path](repeating: Path(), count: 3)
        var bloom = Path()
        let progress: CGFloat? = contact && elapsed >= 0.1 && elapsed < 1.05
            ? CGFloat(min(1, max(0, (elapsed - 0.1) / 0.9))) : nil
        let topPacket = progress.map { packetPoint($0, top: true) }
        let bottomPacket = progress.map { packetPoint($0, top: false) }
        for point in Self.particles.shell {
            let x = Double(point.x), y = Double(point.y)
            let light = max(0, min(1, 1 - 0.0038 * (x - 116) - 0.0018 * (y - 100)))
            let outerEdge = min(min(point.x - 116, 266 - point.x), min(point.y - 100, 368 - point.y))
            let innerEdge = min(min(point.x - 132, 250 - point.x), min(point.y - 120, 348 - point.y))
            let edge = min(outerEdge, innerEdge)
            let edgeGlow = exp(-Double(max(0, edge)) / 4)
            let shimmer = 0.94 + 0.06 * sin(elapsed * 1.2 + point.phase)
            var alpha = mode == .lit ? 0.08 * light
                : (contact ? 0.68 + 0.24 * light : 0.39 + 0.23 * light) * shimmer
            alpha = min(1, alpha + edgeGlow * (mode == .lit ? 0.08 : 0.27))
            if let topPacket, let bottomPacket {
                let da = hypot(Double(point.x - topPacket.x), Double(point.y - topPacket.y))
                let db = hypot(Double(point.x - bottomPacket.x), Double(point.y - bottomPacket.y))
                alpha = min(1, alpha + exp(-pow(min(da, db) / 4.8, 2)) * 0.8)
            }
            let side = point.size / scale
            let rect = CGRect(x: point.x - side / 2, y: point.y - side / 2,
                              width: side, height: side)
            let level = min(2, max(0, Int(alpha * 3)))
            buckets[level].addRect(rect)
            if edge < 4 || alpha > 0.85 {
                bloom.addRect(rect.insetBy(dx: -0.45 / scale, dy: -0.45 / scale))
            }
        }
        for point in Self.particles.bevel {
            buckets[2].addRect(CGRect(x: point.x - point.size / (2 * scale),
                                      y: point.y - point.size / (2 * scale),
                                      width: point.size / scale, height: point.size / scale))
        }
        for (index, path) in buckets.enumerated() where !path.isEmpty {
            let color = index == 2 ? NB.limePale : NB.lime1
            let opacity = mode == .lit ? 0.08 + Double(index) * 0.04
                : contact ? 0.3 + Double(index) * 0.23
                : 0.15 + Double(index) * 0.19
            context.fill(path, with: .color(color.opacity(opacity)))
        }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.blendMode = .plusLighter
            layer.fill(bloom, with: .color(NB.lime1.opacity(mode == .lit ? 0.06 : contact ? 0.5 : 0.3)))
        }
    }

    private func drawKey(_ context: inout GraphicsContext, time: Double, elapsed: Double,
                         waiting: Bool, nudge: Bool, contact: Bool, scale: CGFloat) {
        let pulse = 0.6 + 0.4 * sin(time * 2 * .pi / 1.6)
        let flash = contact && elapsed < 0.25 ? 1 - elapsed / 0.25 : 0
        var dots = Path()
        for point in Self.particles.key {
            let threshold = contact ? max(0.7, flash) : waiting ? 0.55 + pulse * 0.4 : 0.14
            guard point.phase < threshold else { continue }
            let side = point.size / scale
            dots.addRect(CGRect(x: point.x - side / 2, y: point.y - side / 2,
                                width: side, height: side))
        }
        if !dots.isEmpty {
            let color = nudge ? NB.ember1 : contact && flash > 0.35 ? NB.white : NB.lime1
            let opacity = contact ? 0.95 : waiting ? (nudge ? 0.6 : 0.5 + pulse * 0.25) : 0.18
            context.fill(dots, with: .color(color.opacity(opacity)))
        }

        guard waiting else { return }
        var ripples = Path()
        for index in 0..<3 {
            let phase = (time / 1.6 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let radius = 12 + CGFloat(phase) * 48
            for dot in 0..<70 {
                let angle = Double(dot) / 69 * .pi * 1.35 - .pi * 0.68
                let x = Self.keyCentre.x + CGFloat(cos(angle)) * radius
                let y = Self.keyCentre.y + CGFloat(sin(angle)) * radius
                let side = 0.9 / scale
                ripples.addRect(CGRect(x: x - side / 2, y: y - side / 2,
                                       width: side, height: side))
            }
        }
        let color = nudge ? NB.ember1 : NB.lime1
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            layer.blendMode = .plusLighter
            layer.fill(ripples, with: .color(color.opacity(0.48)))
        }
        context.fill(ripples, with: .color(color.opacity(nudge ? 0.34 : 0.24)))
    }

    private func drawFinger(_ context: inout GraphicsContext, elapsed: Double,
                            time: Double, contact: Bool, nudge: Bool, scale: CGFloat) {
        let gap: CGFloat
        let strength: Double
        if contact {
            gap = reduceMotion ? 0 : 12 * (1 - smooth(elapsed / 0.25))
            strength = reduceMotion ? 1 : min(1, 0.78 + elapsed * 0.65)
        } else {
            let cycle = reduceMotion ? 1.2 : elapsed.truncatingRemainder(dividingBy: 2.4)
            let travel: CGFloat = nudge ? 17 : 9
            let approach: Double
            if cycle < 0.8 {
                approach = smooth(cycle / 0.8)
            } else if cycle < 1.2 {
                approach = 1
            } else if cycle < 2 {
                approach = 1 - smooth((cycle - 1.2) / 0.8)
            } else {
                approach = 0
            }
            gap = (nudge ? 20 : 12) - travel * CGFloat(approach)
            strength = 0.42 + 0.2 * (0.5 + 0.5 * sin(elapsed * 2 * .pi / 2.4))
        }

        let axis = Self.fingerAxis
        let tip = CGPoint(x: Self.keyEdge - 1 + axis.dx * gap,
                          y: Self.keyCentre.y + axis.dy * gap)
        let side = Self.fingerImageSide
        let rect = CGRect(x: tip.x - Self.fingerAnchor.x * side,
                          y: tip.y - Self.fingerAnchor.y * side,
                          width: side, height: side)
        let image = context.resolve(Image("HoopFinger"))
        context.drawLayer { layer in
            layer.opacity = strength
            layer.draw(image, in: rect)
            layer.opacity = 1
            layer.blendMode = .destinationIn
            layer.fill(Path(rect), with: .linearGradient(
                Gradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.49),
                    .init(color: .clear, location: 0.8),
                    .init(color: .clear, location: 1),
                ]),
                startPoint: tip,
                endPoint: CGPoint(x: tip.x + axis.dx * side,
                                  y: tip.y + axis.dy * side)))
        }

        let pad = CGPoint(x: tip.x + axis.dx * 8, y: tip.y + axis.dy * 8)
        let glowAlpha = (contact ? 0.4 : 0.14) * strength
        context.fill(Path(ellipseIn: CGRect(x: pad.x - 24, y: pad.y - 24,
                                            width: 48, height: 48)),
                     with: .radialGradient(
                        Gradient(colors: [NB.limePale.opacity(glowAlpha),
                                          NB.lime1.opacity(glowAlpha * 0.45),
                                          NB.lime1.opacity(0)]),
                        center: pad, startRadius: 0, endRadius: 24))
        var motes = [Path](repeating: Path(), count: 2)
        for mote in Self.particles.tipMotes {
            let twinkle = 0.5 + 0.5 * sin(time * 2.1 + mote.phase)
            let alpha = mote.alpha * twinkle
            guard alpha > 0.15 else { continue }
            let moteSide = mote.size / scale
            motes[alpha > 0.42 ? 1 : 0].addRect(
                CGRect(x: tip.x + mote.x - moteSide / 2,
                       y: tip.y + mote.y - moteSide / 2,
                       width: moteSide, height: moteSide))
        }
        for (index, path) in motes.enumerated() where !path.isEmpty {
            context.fill(path, with: .color(NB.limePale.opacity(
                min(1, (contact ? 0.5 : 0.2) * strength * (index == 0 ? 0.55 : 1)))))
        }
    }

    private func drawContactBloom(_ context: inout GraphicsContext, elapsed: Double, scale: CGFloat) {
        let alpha = elapsed < 0.25 ? 0.86 : 0.3
        let point = CGPoint(x: Self.keyEdge, y: Self.keyCentre.y)
        let radius = 28 / scale
        context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                            width: radius * 2, height: radius * 2)),
                     with: .radialGradient(
                        Gradient(colors: [NB.white.opacity(alpha), NB.lime1.opacity(alpha * 0.7),
                                           NB.lime1.opacity(0)]),
                        center: point, startRadius: 0, endRadius: radius))
    }

    private func addSquare(x: CGFloat, y: CGFloat, screenSide: CGFloat, scale: CGFloat,
                           alpha: Double, to paths: inout [Path]) {
        guard alpha > 0.02 else { return }
        let level = min(paths.count - 1, max(0, Int(alpha * Double(paths.count))))
        let side = screenSide / scale
        paths[level].addRect(CGRect(x: x - side / 2, y: y - side / 2,
                                    width: side, height: side))
    }

    private func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    private func packetPoint(_ progress: CGFloat, top: Bool) -> CGPoint {
        let distance = min(1, max(0, progress)) * 418
        if distance < 134 {
            let start = CGPoint(x: Self.keyEdge, y: Self.keyCentre.y)
            let end = CGPoint(x: 266, y: 100)
            let amount = distance / 134
            return CGPoint(x: start.x + (end.x - start.x) * amount,
                           y: start.y + (end.y - start.y) * amount)
        }
        if distance < 284 {
            let start = CGPoint(x: 266, y: 100)
            let end = CGPoint(x: 116, y: 100)
            let amount = (distance - 134) / 150
            return CGPoint(x: start.x + (end.x - start.x) * amount, y: start.y)
        }
        let start = CGPoint(x: 116, y: 100)
        let end = CGPoint(x: 116, y: Self.keyCentre.y)
        let amount = (distance - 284) / 134
        return CGPoint(x: start.x, y: start.y + (end.y - start.y) * amount)
    }

    private static func makeOuter() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 124, y: 100))
        path.addLine(to: CGPoint(x: 258, y: 100))
        path.addQuadCurve(to: CGPoint(x: 266, y: 108), control: CGPoint(x: 266, y: 100))
        path.addLine(to: CGPoint(x: 266, y: 120))
        path.addCurve(to: CGPoint(x: 266, y: 348),
                      control1: CGPoint(x: 269, y: 190), control2: CGPoint(x: 269, y: 278))
        path.addLine(to: CGPoint(x: 266, y: 360))
        path.addQuadCurve(to: CGPoint(x: 258, y: 368), control: CGPoint(x: 266, y: 368))
        path.addLine(to: CGPoint(x: 124, y: 368))
        path.addQuadCurve(to: CGPoint(x: 116, y: 360), control: CGPoint(x: 116, y: 368))
        path.addLine(to: CGPoint(x: 116, y: 348))
        path.addCurve(to: CGPoint(x: 116, y: 120),
                      control1: CGPoint(x: 113, y: 278), control2: CGPoint(x: 113, y: 190))
        path.addLine(to: CGPoint(x: 116, y: 108))
        path.addQuadCurve(to: CGPoint(x: 124, y: 100), control: CGPoint(x: 116, y: 100))
        path.closeSubpath()
        return path
    }

    private struct Dust {
        var x: CGFloat
        var y: CGFloat
        var alpha: Double
        var phase: Double
        var size: CGFloat
    }

    private struct KnitPoint {
        var x: CGFloat
        var y: CGFloat
        var edge: CGFloat
        var size: CGFloat
        var phase: Double
    }

    private struct ShellPoint {
        var x: CGFloat
        var y: CGFloat
        var phase: Double
        var size: CGFloat
    }

    private struct ParticleSet {
        let dust: [Dust]
        let knit: [KnitPoint]
        let shell: [ShellPoint]
        let bevel: [ShellPoint]
        let key: [ShellPoint]
        let tipMotes: [Dust]

        init() {
            var random = SplitMix64(seed: 0x484F4F5050415254)
            dust = (0..<900).map { _ in
                let angle = random.nextDouble() * .pi * 2
                let radius = sqrt(random.nextDouble())
                return Dust(x: HoopFigure.centre.x + CGFloat(cos(angle) * radius * 150),
                            y: HoopFigure.centre.y + CGFloat(sin(angle) * radius * 200),
                            alpha: 0.05 + 0.3 * (1 - radius),
                            phase: random.nextDouble() * .pi * 2,
                            size: 0.85 + CGFloat(random.nextDouble()) * 0.35)
            }

            var knitPoints: [KnitPoint] = []
            var row = 0
            var y: CGFloat = 120
            while y < 348 {
                var x: CGFloat = 132 + CGFloat(random.nextDouble()) * 1.6
                while x < 250 {
                    let point = CGPoint(x: x + CGFloat(random.nextDouble() - 0.5) * 1.4,
                                        y: y + CGFloat(random.nextDouble() - 0.5) * 1.4)
                    if HoopFigure.inner.contains(point) {
                        let edge = min(min(point.x - 132, 250 - point.x),
                                       min(point.y - 120, 348 - point.y))
                        knitPoints.append(KnitPoint(x: point.x, y: point.y, edge: edge,
                                                    size: 0.8 + CGFloat(random.nextDouble()) * 0.5,
                                                    phase: random.nextDouble() * .pi * 2))
                    }
                    x += 1.6
                }
                y += 1.6
                row += 1
            }
            knit = knitPoints

            var shellPoints: [ShellPoint] = []
            var shellY: CGFloat = 99
            var shellRow = 0
            while shellY <= 369 {
                var shellX: CGFloat = 115 + CGFloat(random.nextDouble()) * 1.8
                while shellX <= 267 {
                    let point = CGPoint(x: shellX + CGFloat(random.nextDouble() - 0.5) * 1.6,
                                        y: shellY + CGFloat(random.nextDouble() - 0.5) * 1.6)
                    if HoopFigure.outer.contains(point) && !HoopFigure.inner.contains(point) {
                        shellPoints.append(ShellPoint(x: point.x, y: point.y,
                                                      phase: random.nextDouble() * .pi * 2,
                                                      size: 0.8 + CGFloat(random.nextDouble()) * 0.5))
                    }
                    shellX += 1.8
                }
                shellY += 1.8
                shellRow += 1
            }
            shell = shellPoints

            var bevelPoints: [ShellPoint] = []
            for x in stride(from: CGFloat(132), through: 250, by: 1.5) {
                for y in [CGFloat(120), CGFloat(348)] {
                    bevelPoints.append(ShellPoint(x: x, y: y + CGFloat(random.nextDouble() - 0.5),
                                                  phase: random.nextDouble(),
                                                  size: 0.9 + CGFloat(random.nextDouble()) * 0.3))
                }
            }
            for y in stride(from: CGFloat(112), through: 128, by: 1.5) {
                for x in [CGFloat(132), CGFloat(250)] {
                    bevelPoints.append(ShellPoint(x: x + CGFloat(random.nextDouble() - 0.5),
                                                  y: y, phase: random.nextDouble(),
                                                  size: 0.9 + CGFloat(random.nextDouble()) * 0.3))
                }
            }
            for y in stride(from: CGFloat(340), through: 356, by: 1.5) {
                for x in [CGFloat(132), CGFloat(250)] {
                    bevelPoints.append(ShellPoint(x: x + CGFloat(random.nextDouble() - 0.5),
                                                  y: y, phase: random.nextDouble(),
                                                  size: 0.9 + CGFloat(random.nextDouble()) * 0.3))
                }
            }
            bevel = bevelPoints

            var keyPoints: [ShellPoint] = []
            var keyY: CGFloat = 210
            while keyY <= 258 {
                var keyX: CGFloat = 266
                while keyX <= 272 {
                    keyPoints.append(ShellPoint(x: keyX, y: keyY,
                                                phase: random.nextDouble(),
                                                size: 0.8 + CGFloat(random.nextDouble()) * 0.5))
                    keyX += 0.85
                }
                keyY += 0.85
            }
            key = keyPoints

            tipMotes = (0..<16).map { _ in
                let angle = random.nextDouble() * .pi * 2
                let radius = sqrt(random.nextDouble())
                return Dust(x: HoopFigure.fingerAxis.dx * 12
                                + CGFloat(cos(angle) * radius * 24),
                            y: HoopFigure.fingerAxis.dy * 12
                                + CGFloat(sin(angle) * radius * 17),
                            alpha: 0.3 + 0.5 * (1 - radius),
                            phase: random.nextDouble() * .pi * 2,
                            size: 0.7 + CGFloat(random.nextDouble()) * 0.5)
            }
        }
    }

    private struct SplitMix64 {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
        mutating func nextDouble() -> Double {
            Double(next() >> 11) / Double(UInt64(1) << 53)
        }
    }
}
