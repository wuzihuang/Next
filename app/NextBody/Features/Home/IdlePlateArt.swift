import SwiftUI

/// Clock-driven draw of one idle plate. Pose comes from `IdlePlateMotion` so
/// the field that the tests sample is the field the panel paints.
enum IdlePlateArt {
    static let board = CGSize(width: 358, height: 470)

    static func draw(plate: Int, pose: IdlePlatePose,
                     charge: Double, chargeKnown: Bool,
                     in ctx: inout GraphicsContext, size: CGSize) {
        let sx = size.width / board.width, sy = size.height / board.height
        let s = min(sx, sy)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(NB.panelInk))
        wash(&ctx, size: size, pose: pose, plate: plate)
        stars(&ctx, sx: sx, sy: sy, s: s, pose: pose, plate: plate)
        look(plate, pose: pose, charge: charge, chargeKnown: chargeKnown,
             ctx: &ctx, size: size, s: s, sx: sx, sy: sy)
    }

    private static func look(_ plate: Int, pose: IdlePlatePose, charge: Double,
                             chargeKnown: Bool, ctx: inout GraphicsContext,
                             size: CGSize, s: CGFloat, sx: CGFloat, sy: CGFloat) {
        switch plate {
        case 1:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 179, cy: 188, r: 82, ringRX: 150, ringRY: 38,
                   ivory: true, charge: charge, chargeKnown: chargeKnown)
        case 2:
            moon(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                 cx: 179, cy: 210, r: 210, close: false)
        case 3:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 179, cy: 128, r: 78, ringRX: 155, ringRY: 19,
                   ivory: false, charge: charge, chargeKnown: chargeKnown)
        case 4:
            swirls(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 5:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 179, cy: 178, r: 68, ringRX: 130, ringRY: 34,
                   ivory: true, dim: true, charge: charge, chargeKnown: chargeKnown)
            crescent(&ctx, at: CGPoint(x: 88 * sx, y: 108 * sy), r: 11 * s, pose: pose)
        case 6:
            dashedOrbits(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 7:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 179, cy: 178, r: 72, ringRX: 138, ringRY: 30,
                   ivory: false, charge: charge, chargeKnown: chargeKnown)
        case 8:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 152, cy: 168, r: 40, ringRX: 175, ringRY: 50,
                   ivory: true, charge: charge, chargeKnown: chargeKnown, wideBand: true)
        case 9:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 179, cy: 188, r: 70, ringRX: 0, ringRY: 0,
                   ivory: true, dim: true, charge: charge, chargeKnown: chargeKnown)
            dashedLine(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                       from: CGPoint(x: 40 * sx, y: 80 * sy),
                       to: CGPoint(x: 320 * sx, y: 300 * sy))
        case 10:
            beam(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                 from: CGPoint(x: 48 * sx, y: 70 * sy),
                 to: CGPoint(x: 310 * sx, y: 340 * sy))
        case 11:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 338, cy: 40, r: 150, ringRX: 262, ringRY: 42,
                   ivory: false, dim: true, charge: charge, chargeKnown: chargeKnown)
        case 12:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 179, cy: 188, r: 85, ringRX: 165, ringRY: 24,
                   ivory: false, dim: true, charge: charge, chargeKnown: chargeKnown)
        case 14:
            thinRing(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 15:
            horizon(&ctx, pose: pose, s: s, sx: sx, sy: sy, ember: true)
        case 16:
            horizon(&ctx, pose: pose, s: s, sx: sx, sy: sy, ember: false)
            dashedArc(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 20:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 298, cy: 195, r: 92, ringRX: 0, ringRY: 0,
                   ivory: false, charge: charge, chargeKnown: chargeKnown)
            arcStroke(&ctx, c: CGPoint(x: 80 * sx, y: 300 * sy),
                      r: 220 * s, from: -0.6, span: 1.1, width: 1.2 * s,
                      color: NB.white.opacity(0.18 * pose.glow))
        case 21:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: -20, cy: 210, r: 200, ringRX: 0, ringRY: 0,
                   ivory: false, charge: charge, chargeKnown: chargeKnown)
            satellite(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                      c: CGPoint(x: 179 * sx, y: 210 * sy), rx: 120 * s, ry: 36 * s)
        case 22:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 179, cy: 188, r: 68, ringRX: 145, ringRY: 16,
                   ivory: true, charge: charge, chargeKnown: chargeKnown)
        case 23:
            moon(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                 cx: 214, cy: 372, r: 224, close: true)
        case 25:
            emberPoint(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 26:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 250, cy: 200, r: 80, ringRX: 0, ringRY: 0,
                   ivory: false, charge: charge, chargeKnown: chargeKnown, violet: true)
        case 27:
            beam(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                 from: CGPoint(x: 210 * sx, y: 40 * sy),
                 to: CGPoint(x: 340 * sx, y: 200 * sy), dashed: true)
        case 28:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 179, cy: 188, r: 80, ringRX: 162, ringRY: 5,
                   ivory: false, charge: charge, chargeKnown: chargeKnown)
        default:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 179, cy: 188, r: 74, ringRX: 126, ringRY: 34,
                   ivory: true, charge: charge, chargeKnown: chargeKnown)
        }
    }

    // MARK: pieces

    private static func wash(_ ctx: inout GraphicsContext, size: CGSize,
                             pose: IdlePlatePose, plate: Int) {
        let tint: Color = {
            switch plate {
            case 15, 25: return NB.ember1
            case 16, 20, 21: return NB.blue2
            case 26: return NB.violet3
            default: return NB.white
            }
        }()
        let r = 180 * pose.glow
        let c = CGPoint(x: size.width * 0.5, y: size.height * 0.38)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(
                    Gradient(colors: [tint.opacity(0.07 * pose.glow), tint.opacity(0)]),
                    center: c, startRadius: 0, endRadius: r))
    }

    private static func stars(_ ctx: inout GraphicsContext, sx: CGFloat, sy: CGFloat,
                              s: CGFloat, pose: IdlePlatePose, plate: Int) {
        let seeds: [(CGFloat, CGFloat, Double)] = [
            (46, 58, 1.2), (78, 88, 1.6), (118, 36, 0.9), (196, 52, 0.7),
            (244, 28, 0.8), (298, 44, 1.0), (312, 118, 1.3), (328, 238, 0.8),
            (28, 268, 0.7), (64, 168, 0.6), (14, 142, 0.7), (292, 318, 0.6),
        ]
        for (i, star) in seeds.enumerated() {
            let tw = 0.45 + 0.55 * sin(pose.phase * .pi * 2 + Double(i) * 0.9)
            let p = CGPoint(x: star.0 * sx, y: star.1 * sy)
            let r = star.2 * s * CGFloat(0.7 + 0.4 * tw)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(NB.white.opacity(0.22 + 0.45 * tw)))
        }
        _ = plate
    }

    private static func saturn(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                               s: CGFloat, sx: CGFloat, sy: CGFloat,
                               cx: Double, cy: Double, r: Double,
                               ringRX: Double, ringRY: Double,
                               ivory: Bool, dim: Bool = false,
                               charge: Double, chargeKnown: Bool,
                               wideBand: Bool = false, violet: Bool = false) {
        let c = CGPoint(x: cx * sx, y: cy * sy)
        let pr = r * s * pose.breathe
        let glow = pr * 1.55
        let body: Color = violet ? NB.violet2 : (ivory ? NB.emberPale : NB.bluePale)
        let ink = dim ? NB.panelInk : NB.discInk
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - glow, y: c.y - glow, width: glow * 2, height: glow * 2)),
                 with: .radialGradient(
                    Gradient(colors: [body.opacity(0.22 * pose.glow), body.opacity(0)]),
                    center: c, startRadius: pr * 0.4, endRadius: glow))
        if ringRX > 4 {
            rings(&ctx, c: c, rx: ringRX * s, ry: ringRY * s,
                  deg: pose.ringDeg, pose: pose, ivory: ivory, wideBand: wideBand, back: true)
        }
        let rect = CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2)
        let disc = Path(ellipseIn: rect)
        let key = CGPoint(x: c.x - pr * 0.38, y: c.y - pr * 0.42)
        ctx.fill(disc, with: .color(ink))
        ctx.fill(disc, with: .radialGradient(
            Gradient(colors: [body.opacity(dim ? 0.35 : 0.85), ink.opacity(0.95)]),
            center: key, startRadius: 0, endRadius: pr * 1.2))
        ctx.fill(disc, with: .radialGradient(
            Gradient(colors: [NB.white.opacity(0.28 * pose.glow), NB.white.opacity(0)]),
            center: key, startRadius: 0, endRadius: pr * 0.45))
        ctx.stroke(disc, with: .color(NB.white.opacity(0.10)), lineWidth: 1)
        if ringRX > 4 {
            rings(&ctx, c: c, rx: ringRX * s, ry: ringRY * s,
                  deg: pose.ringDeg, pose: pose, ivory: ivory, wideBand: wideBand, back: false)
        }
        if ivory, chargeKnown {
            let span = 0.34 + 0.26 * min(1, max(0, charge))
            limeBand(&ctx, c: c, r: pr * 1.18, pose: pose, span: span, s: s)
        }
    }

    private static func rings(_ ctx: inout GraphicsContext, c: CGPoint,
                              rx: CGFloat, ry: CGFloat, deg: Double,
                              pose: IdlePlatePose, ivory: Bool, wideBand: Bool, back: Bool) {
        let color = ivory ? NB.emberPale : NB.bluePale
        let a = deg * .pi / 180
        let gaps: [CGFloat] = wideBand ? [0] : [0, 8, 16]
        for (i, g) in gaps.enumerated() {
            let rxx = rx + g, ryy = ry + g * (ry / max(rx, 1))
            let width: CGFloat = wideBand ? 18 : CGFloat([1.7, 1.25, 1.0][i])
            let alpha = (back ? 0.28 : 0.72) * pose.glow * (wideBand ? 0.22 : 1)
            strokeEllipse(&ctx, c: c, rx: rxx, ry: ryy, rot: a, back: back,
                          width: width, color: color.opacity(alpha))
        }
    }

    private static func strokeEllipse(_ ctx: inout GraphicsContext, c: CGPoint,
                                      rx: CGFloat, ry: CGFloat, rot: Double,
                                      back: Bool, width: CGFloat, color: Color) {
        var path = Path()
        let steps = 48
        var drew = false
        for i in 0...steps {
            let t = Double.pi * 2 * Double(i) / Double(steps)
            let near = sin(t) >= 0
            guard near != back else {
                drew = false
                continue
            }
            let x = Double(rx) * cos(t), y = Double(ry) * sin(t)
            let p = CGPoint(x: c.x + CGFloat(x * cos(rot) - y * sin(rot)),
                            y: c.y + CGFloat(x * sin(rot) + y * cos(rot)))
            if drew { path.addLine(to: p) } else { path.move(to: p); drew = true }
        }
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private static func limeBand(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                                 pose: IdlePlatePose, span: Double, s: CGFloat) {
        let head = -pose.phase * .pi * 2
        let n = 22
        for i in 0..<n {
            let u0 = Double(i) / Double(n), u1 = Double(i + 1) / Double(n)
            let t0 = head + span * .pi * 2 * u0
            let t1 = head + span * .pi * 2 * u1
            guard cos((t0 + t1) / 2) >= 0 else { continue }
            var seg = Path()
            func pt(_ t: Double) -> CGPoint {
                CGPoint(x: c.x + r * CGFloat(cos(t) * 0.42),
                        y: c.y + r * CGFloat(sin(t)))
            }
            seg.move(to: pt(t0)); seg.addLine(to: pt(t1))
            let taper = sin(.pi * (u0 + u1) / 2)
            ctx.stroke(seg, with: .color(NB.lime1.opacity(0.55 * taper * pose.glow)),
                       style: StrokeStyle(lineWidth: 3.2 * s, lineCap: .round))
        }
    }

    private static func moon(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                             s: CGFloat, sx: CGFloat, sy: CGFloat,
                             cx: Double, cy: Double, r: Double, close: Bool) {
        let c = CGPoint(x: (cx + pose.bodyX - cx) * sx, y: cy * sy)
        let pr = r * s
        let rect = CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2)
        let disc = Path(ellipseIn: rect)
        let lx = CGFloat(pose.lightX) * s
        let key = CGPoint(x: c.x - pr * 0.4 + lx, y: c.y - pr * 0.45)
        ctx.fill(disc, with: .color(NB.discInk))
        ctx.fill(disc, with: .radialGradient(
            Gradient(colors: [NB.white.opacity(0.72), NB.panelInk.opacity(0.96)]),
            center: key, startRadius: 0, endRadius: pr * 1.25))
        if close {
            let craters: [(CGFloat, CGFloat, CGFloat)] = [
                (168, 168, 22), (248, 128, 14), (286, 248, 26),
                (118, 268, 16), (198, 220, 10), (64, 210, 11),
            ]
            for cr in craters {
                let p = CGPoint(x: cr.0 * sx + CGFloat(pose.moonYaw) * 2,
                                y: cr.1 * sy + CGFloat(pose.moonPitch) * 2)
                let rr = cr.2 * s
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)),
                         with: .color(NB.panelInk.opacity(0.28)))
            }
        }
        ctx.stroke(disc, with: .color(NB.white.opacity(0.08)), lineWidth: 1)
        _ = pose.breathe
    }

    private static func crescent(_ ctx: inout GraphicsContext, at p: CGPoint,
                                 r: CGFloat, pose: IdlePlatePose) {
        let disc = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.fill(disc, with: .color(NB.emberPale.opacity(0.82 * pose.glow)))
        let hole = Path(ellipseIn: CGRect(x: p.x - r * 0.15, y: p.y - r * 1.05,
                                          width: r * 1.7, height: r * 1.7))
        ctx.fill(hole, with: .color(NB.panelInk))
    }

    private static func swirls(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                               s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 188 * sy)
        let rot = pose.ringDeg * .pi / 180
        for (rx, ry, a) in [(140.0, 60.0, 0.72), (100.0, 42.0, 0.58),
                            (220.0, 70.0, 0.42), (190.0, 95.0, 0.34)] {
            strokeEllipse(&ctx, c: c, rx: rx * s, ry: ry * s, rot: rot,
                          back: false, width: 1.8 * s,
                          color: NB.white.opacity(a * pose.glow))
            strokeEllipse(&ctx, c: c, rx: rx * s, ry: ry * s, rot: rot,
                          back: true, width: 1.4 * s,
                          color: NB.white.opacity(a * 0.45 * pose.glow))
        }
        let g = 18 * s * pose.breathe
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - g, y: c.y - g, width: g * 2, height: g * 2)),
                 with: .radialGradient(
                    Gradient(colors: [NB.white.opacity(0.45 * pose.glow), NB.white.opacity(0)]),
                    center: c, startRadius: 0, endRadius: g))
    }

    private static func dashedOrbits(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                     s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 205 * sy)
        dashEllipse(&ctx, c: c, rx: 72 * s, ry: 72 * s, rot: 0,
                    n: 18, pose: pose, color: NB.white.opacity(0.55))
        dashedLine(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   from: CGPoint(x: 40 * sx, y: 80 * sy),
                   to: CGPoint(x: 320 * sx, y: 310 * sy))
        dashedLine(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   from: CGPoint(x: 40 * sx, y: 310 * sy),
                   to: CGPoint(x: 320 * sx, y: 90 * sy), reverse: true)
        let g = 8 * s * pose.breathe
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - g, y: c.y - 92 * s - g,
                                        width: g * 2, height: g * 2)),
                 with: .color(NB.lime1.opacity(0.7 * pose.glow)))
    }

    private static func dashEllipse(_ ctx: inout GraphicsContext, c: CGPoint,
                                    rx: CGFloat, ry: CGFloat, rot: Double,
                                    n: Int, pose: IdlePlatePose, color: Color) {
        let steps = n * 4
        for i in 0..<steps {
            let u = (Double(i) / Double(steps) + pose.dash).truncatingRemainder(dividingBy: 1)
            let duty = (u * Double(n)).truncatingRemainder(dividingBy: 1)
            guard duty < 0.45 else { continue }
            let t = u * .pi * 2
            let x = Double(rx) * cos(t), y = Double(ry) * sin(t)
            let p = CGPoint(x: c.x + CGFloat(x * cos(rot) - y * sin(rot)),
                            y: c.y + CGFloat(x * sin(rot) + y * cos(rot)))
            let r: CGFloat = 1.6
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(color))
        }
    }

    private static func dashedLine(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                   s: CGFloat, sx: CGFloat, sy: CGFloat,
                                   from: CGPoint, to: CGPoint, reverse: Bool = false) {
        _ = sx; _ = sy
        let n = 22
        let off = reverse ? -pose.dash : pose.dash
        for i in 0..<n {
            let u = (Double(i) / Double(n) + off).truncatingRemainder(dividingBy: 1)
            guard (u * 22).truncatingRemainder(dividingBy: 1) < 0.45 else { continue }
            let p = CGPoint(x: from.x + (to.x - from.x) * CGFloat(u),
                            y: from.y + (to.y - from.y) * CGFloat(u))
            let r = 1.4 * s
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(NB.white.opacity(0.42 * pose.glow)))
        }
    }

    private static func dashedArc(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                  s: CGFloat, sx: CGFloat, sy: CGFloat) {
        dashEllipse(&ctx, c: CGPoint(x: 80 * sx, y: 90 * sy),
                    rx: 90 * s, ry: 40 * s, rot: -0.5, n: 14, pose: pose,
                    color: NB.bluePale.opacity(0.5))
    }

    private static func thinRing(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                 s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 195 * sy)
        let r = 58 * s * pose.breathe
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                   with: .color(NB.white.opacity(0.35 * pose.glow)),
                   style: StrokeStyle(lineWidth: 1.2 * s))
        dashedLine(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   from: CGPoint(x: 40 * sx, y: 300 * sy),
                   to: CGPoint(x: 320 * sx, y: 360 * sy))
    }

    private static func beam(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                             s: CGFloat, sx: CGFloat, sy: CGFloat,
                             from: CGPoint, to: CGPoint, dashed: Bool = false) {
        _ = sx; _ = sy
        if dashed {
            dashedLine(&ctx, pose: pose, s: s, sx: sx, sy: sy, from: from, to: to)
        } else {
            var path = Path()
            path.move(to: from); path.addLine(to: to)
            ctx.stroke(path, with: .color(NB.white.opacity(0.22 * pose.glow)),
                       style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round))
        }
        let a = pose.breathe
        for (p, k) in [(from, a), (to, pose.glow)] {
            let g = 14 * s * k
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - g, y: p.y - g, width: g * 2, height: g * 2)),
                     with: .radialGradient(
                        Gradient(colors: [NB.limePale.opacity(0.55 * k), NB.limePale.opacity(0)]),
                        center: p, startRadius: 0, endRadius: g))
        }
    }

    private static func horizon(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat, ember: Bool) {
        let tint = ember ? NB.ember1 : NB.blue1
        let y = (ember ? 318 : 340) * sy
        let w = 220 * s * pose.breathe
        let h = 48 * s * pose.glow
        ctx.fill(Path(ellipseIn: CGRect(x: 179 * sx - w, y: y - h, width: w * 2, height: h * 2)),
                 with: .radialGradient(
                    Gradient(colors: [tint.opacity(0.45 * pose.glow), tint.opacity(0)]),
                    center: CGPoint(x: 179 * sx, y: y), startRadius: 0, endRadius: w))
        if ember {
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 210, cy: 250, r: 90, ringRX: 0, ringRY: 0,
                   ivory: true, dim: true, charge: 0, chargeKnown: false)
        }
        var arc = Path()
        arc.addArc(center: CGPoint(x: 179 * sx, y: (ember ? 252 : 195) * sy),
                   radius: 140 * s, startAngle: .degrees(ember ? 20 : -30),
                   endAngle: .degrees(ember ? 70 : 20), clockwise: false)
        ctx.stroke(arc, with: .color(tint.opacity(0.35 * pose.glow)),
                   style: StrokeStyle(lineWidth: 1.2 * s, lineCap: .round))
    }

    private static func emberPoint(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                   s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let p = CGPoint(x: 179 * sx, y: 268 * sy)
        let g = 36 * s * pose.breathe
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - g, y: p.y - g, width: g * 2, height: g * 2)),
                 with: .radialGradient(
                    Gradient(colors: [NB.ember1.opacity(0.55 * pose.glow), NB.ember1.opacity(0)]),
                    center: p, startRadius: 0, endRadius: g))
        var arc = Path()
        arc.addArc(center: CGPoint(x: 120 * sx, y: 300 * sy), radius: 90 * s,
                   startAngle: .degrees(-10), endAngle: .degrees(50), clockwise: false)
        ctx.stroke(arc, with: .color(NB.emberPale.opacity(0.4 * pose.glow)),
                   style: StrokeStyle(lineWidth: 1.3 * s, lineCap: .round))
    }

    private static func satellite(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                  s: CGFloat, sx: CGFloat, sy: CGFloat,
                                  c: CGPoint, rx: CGFloat, ry: CGFloat) {
        _ = sx; _ = sy
        let t = pose.satellite * .pi / 180
        let p = CGPoint(x: c.x + rx * CGFloat(cos(t)), y: c.y + ry * CGFloat(sin(t)))
        dashEllipse(&ctx, c: c, rx: rx, ry: ry, rot: -0.4, n: 26, pose: pose,
                    color: NB.white.opacity(0.28))
        let r = 4 * s
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                 with: .color(NB.bluePale.opacity(0.9)))
    }

    private static func arcStroke(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                                  from: Double, span: Double, width: CGFloat, color: Color) {
        var path = Path()
        path.addArc(center: c, radius: r, startAngle: .radians(from),
                    endAngle: .radians(from + span), clockwise: false)
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

enum IdlePlateStore {
    private static let key = "nb.idlePlate.lock.v2"

    static func load() -> IdlePlateLock.Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(IdlePlateLock.Snapshot.self, from: data)
    }

    static func save(_ snap: IdlePlateLock.Snapshot) {
        guard let data = try? JSONEncoder().encode(snap) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// BLE-down clock from `NotificationReach.stampDisconnect`. Missing stamp is nil.
    static func disconnectStamp(defaults: UserDefaults = .standard) -> Date? {
        guard defaults.object(forKey: NotificationReach.disconnectAtKey) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: NotificationReach.disconnectAtKey))
    }
}
