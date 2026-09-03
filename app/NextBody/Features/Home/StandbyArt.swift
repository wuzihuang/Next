import SwiftUI

/// 04 · 01 默认 / 01M ◇4 — the star ring. The one thing on this panel that never stops.
///
/// A planet at the centre with its own turn on it; a lime band on a steep orbit that
/// **passes behind the sphere and comes out the other side**, rather than tracing its
/// edge from a safe distance, and flares as its head clears the limb; and a small body
/// running the blue orbit — hidden by the planet across the far half, in front of it
/// across the near one. Every period here is co-prime with the others, and the band's
/// plane itself precesses, so the field never repeats a pose.
///
/// The whole thing is one Canvas on the board's own 358 × 470 space, so the halftone mask
/// above it has a single layer to eat rather than a stack of shapes.
struct OrbitField {
    /// On-screen seconds. It advances only while the field is visible and turning, so a
    /// trip to the background pauses it instead of skipping it forward.
    var clock: Double
    /// 0…1 — how much of the ring the lime band covers. It is the charge level, not decoration.
    var charge: Double = 0.72
    /// Unknown is not an empty battery: without a score the lime band is absent.
    var chargeKnown = true
    /// 0…1 — ◇3's sweep. The idle panel passes 1 and never looks at it again.
    var arrival: Double = 1
    /// ◇2 — before the core is lit the whole plate sits at 20%: this screen comes up backlit.
    var coreLit: Bool = true
    /// ◇4 — from here the body is on the ring.
    var moving: Bool = true

    // The board's geometry, in the board's own 358 × 470 units.
    static let planetR: CGFloat = 74
    static let orbitRX: CGFloat = 126
    static let orbitRY: CGFloat = 34
    static let haloR: CGFloat = 90
    /// The blue orbit's plane, tilted the same 16° the board draws it at. The lime band
    /// leans the other way, and its own lean walks (see `haloPlane`) — two planes that
    /// never line up.
    static let tilt: Double = -16 * .pi / 180
    static let haloTilt: Double = 26 * .pi / 180
    /// 90 seconds a revolution for the body, and nothing else divides into it.
    static let revolution: Double = 90
    static let haloRevolution: Double = 26
    /// The slow drift of the lime plane's inclination — the ring opens and closes as if
    /// the vantage point were sliding, which is what stops the loop from reading as a loop.
    /// The lime plane's node walks all the way round in 97 seconds. Together with the
    /// inclination breathing on 37, the band comes up from a different angle every time.
    static let nodePeriod: Double = 97
    static let precession: Double = 37

    /// x, y on the board, base brightness, twinkle phase.
    private static let specks: [(CGFloat, CGFloat, Double, Double)] = [
        (52, 84, 0.50, 0.0), (300, 112, 0.35, 1.7), (84, 300, 0.30, 3.1),
        (286, 286, 0.50, 0.8), (212, 70, 0.25, 2.4), (40, 208, 0.35, 4.2),
        (150, 372, 0.22, 5.3), (332, 214, 0.28, 2.0), (118, 152, 0.20, 3.9),
        (248, 396, 0.26, 1.1),
    ]

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let sx = size.width / 358, sy = size.height / 470
        let s = min(sx, sy)
        let c = CGPoint(x: size.width / 2, y: 196 * sy)

        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(NB.panelWash.opacity(coreLit ? 1 : 0.2)))

        // ◇1 · one lime pixel, dead centre — and then the core it bursts into.
        guard coreLit else {
            dot(&ctx, at: c, r: 1.5 * s, NB.lime1)
            return
        }
        guard arrival > 0.001 else {
            dot(&ctx, at: c, r: 6 * s, NB.lime1)
            return
        }

        let a = min(1, arrival)
        let bodyA = clock * 2 * .pi / Self.revolution
        let haloA = -clock * 2 * .pi / Self.haloRevolution
        // The lime plane's inclination breathes: 0.20 nearly edge-on, 0.58 wide open.
        let incl = 0.26 + 0.36 * (0.5 + 0.5 * sin(clock * 2 * .pi / Self.precession))
        // The sphere is lit from wherever the band is nearest the eye, by that much.
        let light = haloLight(angle: haloA, incl: incl, c: c, s: s)
        // The sweep starts at the right and closes anticlockwise, as the board draws it.
        let swept = 2 * Double.pi * a

        nebula(&ctx, size: size, s: s, alpha: a)
        dust(&ctx, sx: sx, sy: sy, s: s, alpha: a)
        for lane in 0..<3 { meteor(&ctx, lane: lane, sx: sx, sy: sy, s: s, alpha: a) }
        visitor(&ctx, c: c, s: s, alpha: a)

        // Everything upstage of the planet, in order of depth. The far half of the blue
        // orbit reads dimmer and the body crosses it *behind* the sphere: that occlusion
        // is the whole trick, and without it the ellipse is a flat drawing on glass.
        ring(&ctx, c: c, s: s, from: Double.pi, to: 2 * .pi, swept: swept,
             alpha: 0.11, width: 2.2 * s)
        if moving, sin(bodyA) < 0 { body(&ctx, c: c, s: s, angle: bodyA) }
        halo(&ctx, c: c, s: s, angle: haloA, incl: incl, growth: a, back: true)

        planet(&ctx, c: c, s: s, alpha: a, light: light)

        // …and everything downstage of it.
        halo(&ctx, c: c, s: s, angle: haloA, incl: incl, growth: a, back: false)
        ring(&ctx, c: c, s: s, from: 0, to: Double.pi, swept: swept,
             alpha: 0.27, width: 2.8 * s)
        // The orbit lights up just ahead of the body, so you can see where it is going.
        if moving {
            ring(&ctx, c: c, s: s, from: bodyA + 0.26, to: bodyA + 1.30, swept: .infinity,
                 alpha: 0.26, width: 3 * s, color: NB.violet2)
        }
        if moving, sin(bodyA) >= 0 { body(&ctx, c: c, s: s, angle: bodyA) }
    }

    // MARK: geometry

    /// A point on a tilted ellipse. Angle 0 is the right-hand extreme; the lower half is
    /// the near side, which is what every `sin(angle) >= 0` test in here is asking.
    private func point(_ angle: Double, c: CGPoint, rx: CGFloat, ry: CGFloat,
                       tilt: Double) -> CGPoint {
        let x = Double(rx) * cos(angle), y = Double(ry) * sin(angle)
        let ct = cos(tilt), st = sin(tilt)
        return CGPoint(x: c.x + CGFloat(x * ct - y * st), y: c.y + CGFloat(x * st + y * ct))
    }

    private func orbitPoint(_ angle: Double, c: CGPoint, s: CGFloat) -> CGPoint {
        point(angle, c: c, rx: Self.orbitRX * s, ry: Self.orbitRY * s, tilt: Self.tilt)
    }

    // MARK: the pieces

    private func ring(_ ctx: inout GraphicsContext, c: CGPoint, s: CGFloat,
                      from: Double, to: Double, swept: Double,
                      alpha: Double, width: CGFloat, color: Color = NB.violet2) {
        var path = Path()
        var drew = false
        let steps = 48
        for i in 0...steps {
            let t = from + (to - from) * Double(i) / Double(steps)
            // While ◇3 is still drawing, the ring exists only as far as the sweep has got.
            guard swept.isInfinite || t.truncatingRemainder(dividingBy: 2 * .pi) <= swept
            else { continue }
            let p = orbitPoint(t, c: c, s: s)
            if drew { path.addLine(to: p) } else { path.move(to: p); drew = true }
        }
        guard drew else { return }
        ctx.stroke(path, with: .color(color.opacity(alpha)),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    /// The band's length. It is the charge level, not decoration.
    private var haloSpan: Double {
        guard chargeKnown else { return 0 }
        return 2 * .pi * (0.34 + 0.26 * min(1, max(0, charge)))
    }

    /// A point on the lime band's ring. The ring is *polar*: it stands up through the
    /// planet's poles rather than lying in the blue orbit's plane, so its narrow axis is
    /// the one pointing at the eye — which is why depth here reads off `cos`, not `sin`.
    private func haloPoint(_ t: Double, c: CGPoint, s: CGFloat, incl: Double) -> CGPoint {
        point(t, c: c, rx: Self.haloR * s * CGFloat(incl), ry: Self.haloR * s,
              tilt: haloPlane)
    }

    /// The lean of the band's plane. It is not a constant: the node walks, so the ring
    /// stands up through a different pair of poles every minute and a half.
    private var haloPlane: Double { Self.haloTilt + clock * 2 * .pi / Self.nodePeriod }

    /// 0…1 — how recently the head of the band came out from behind the planet. The band
    /// travels towards falling angles, so its head is the leading end, and it clears the
    /// limb at exactly π/2 once every 26 seconds. It brings the light out with it.
    private var emergence: Double {
        let head = -clock * 2 * .pi / Self.haloRevolution
        var since = (.pi / 2 - head).truncatingRemainder(dividingBy: 2 * .pi)
        if since < 0 { since += 2 * .pi }
        let seconds = since * Self.haloRevolution / (2 * .pi)
        // A bump centred 0.4s after the crossing, ±0.5s wide: it rises as well as falls,
        // so there is no step on the way in.
        let d = (seconds - 0.4) / 0.5
        return exp(-d * d)
    }

    /// Where the band's light falls on the planet, and how much of it. A weighted sum of
    /// the band's near-side samples — every sample pulls the light its way in proportion
    /// to how close it is to the eye — so the direction slides continuously as the band
    /// moves, and the strength fades to nothing while the band is round the back. An
    /// argmax here would step from sample to sample and the light would visibly stutter.
    private func haloLight(angle: Double, incl: Double, c: CGPoint, s: CGFloat)
        -> (angle: Double, strength: Double) {
        guard chargeKnown else { return (0, 0) }
        let span = haloSpan
        let n = 24
        var vx = 0.0, vy = 0.0
        for i in 0...n {
            let t = angle + span * Double(i) / Double(n)
            let w = max(0, cos(t))
            guard w > 0 else { continue }
            let p = haloPoint(t, c: c, s: s, incl: incl)
            let dx = Double(p.x - c.x), dy = Double(p.y - c.y)
            let len = max(1e-6, (dx * dx + dy * dy).squareRoot())
            vx += w * w * dx / len
            vy += w * w * dy / len
        }
        let mag = (vx * vx + vy * vy).squareRoot() / Double(n + 1)
        return (atan2(vy, vx), min(1, mag * 3))
    }

    /// The lime band. Drawn in two passes with the planet between them: the segments on the
    /// far side of the ring go down first, thinner and dimmer, so the band narrows as it
    /// rounds the back of the sphere, vanishes behind it, and swells as it comes forward
    /// again. That — not the rotation on its own — is what makes it a ring and not a rim.
    private func halo(_ ctx: inout GraphicsContext, c: CGPoint, s: CGFloat,
                      angle: Double, incl: Double, growth: Double, back: Bool) {
        let span = haloSpan * growth
        guard span > 0.03 else { return }
        let n = 26
        // The swell as the head clears the limb — a second, and only on the way out.
        let flash = emergence

        for i in 0..<n {
            let u0 = Double(i) / Double(n), u1 = Double(i + 1) / Double(n)
            let t0 = angle + span * u0, t1 = angle + span * u1
            let mid = (t0 + t1) / 2
            guard (cos(mid) >= 0) != back else { continue }
            // 0 at the far side of the ring, 1 at the near side.
            let depth = (cos(mid) + 1) / 2
            // Tapered at both ends, so it is a band passing through, not a pie slice.
            let taper = pow(sin(.pi * (u0 + u1) / 2), 0.45)
            var seg = Path()
            seg.move(to: haloPoint(t0, c: c, s: s, incl: incl))
            seg.addLine(to: haloPoint(t1, c: c, s: s, incl: incl))

            let width = (3.2 + 4.2 * depth) * s * CGFloat(0.55 + 0.45 * taper)
            // The bloom the dot screen turns into a soft edge.
            ctx.stroke(seg, with: .color(NB.lime1.opacity(0.05 * taper * depth * growth)),
                       style: StrokeStyle(lineWidth: width * 2.6, lineCap: .round))
            ctx.stroke(seg, with: .color(NB.lime1
                .opacity(min(1, (0.20 + 0.70 * taper) * (0.30 + 0.70 * depth)
                                * (1 + 0.8 * flash * depth) * growth))),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
        }

        // The head of the band, bright and glowing — the band reads as being drawn by it.
        // It is the leading end, and the band runs towards falling angles.
        let head = angle
        if (cos(head) >= 0) != back {
            let depth = (cos(head) + 1) / 2
            let p = haloPoint(head, c: c, s: s, incl: incl)
            dot(&ctx, at: p, r: 7 * s * CGFloat(0.5 + 0.5 * depth),
                NB.lime1.opacity(0.07 * depth * growth))
            dot(&ctx, at: p, r: 2.2 * s * CGFloat(0.6 + 0.4 * depth),
                NB.limePale.opacity(min(1, (0.35 + 0.55 * depth) * (1 + flash) * growth)))
            if flash > 0.02 {
                dot(&ctx, at: p, r: 30 * s * CGFloat(0.4 + 0.6 * flash),
                    NB.lime1.opacity(0.12 * flash * growth))
                dot(&ctx, at: p, r: 11 * s * CGFloat(0.4 + 0.6 * flash),
                    NB.lime1.opacity(0.30 * flash * growth))
            }
        }
    }

    /// The planet: a body, not a hole. A fixed key light from the upper left gives it its
    /// form so it always reads as a sphere; the lime and ember on its limb come from the
    /// band and follow it, and fade out entirely while the band is round the back.
    private func planet(_ ctx: inout GraphicsContext, c: CGPoint, s: CGFloat,
                        alpha: Double, light: (angle: Double, strength: Double)) {
        let r = Self.planetR * s * CGFloat(0.35 + 0.65 * alpha)
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        let disc = Path(ellipseIn: rect)
        let key = CGPoint(x: c.x - r * 0.42, y: c.y - r * 0.48)

        ctx.fill(disc, with: .color(NB.discInk))
        ctx.fill(disc, with: .radialGradient(
            Gradient(colors: [NB.white.opacity(0.15 * alpha), NB.white.opacity(0)]),
            center: key, startRadius: 0, endRadius: r * 1.15))
        ctx.fill(disc, with: .radialGradient(
            Gradient(colors: [NB.panelInk.opacity(0), NB.panelInk.opacity(0.80 * alpha)]),
            center: CGPoint(x: c.x * 2 - key.x, y: c.y * 2 - key.y),
            startRadius: r * 0.15, endRadius: r * 1.5))
        ctx.stroke(disc, with: .color(NB.white.opacity(0.10 * alpha)), lineWidth: 1)

        // The band's light on the near limb, and a cold ember answer on the far one.
        let k = light.strength * alpha
        guard k > 0.01 else { return }
        let la = light.angle
        arc(&ctx, c: c, r: r, from: la - 0.8, span: 1.6,
            width: 2.4 * s, color: NB.lime1.opacity(0.28 * k))
        arc(&ctx, c: c, r: r + 3 * s, from: la - 0.55, span: 1.1,
            width: 8 * s, color: NB.lime1.opacity(0.06 * k))
        arc(&ctx, c: c, r: r - 0.5 * s, from: la + .pi - 0.9, span: 1.8,
            width: 2.6 * s, color: NB.ember2.opacity(0.30 * k))
        arc(&ctx, c: c, r: r + 2 * s, from: la + .pi - 0.6, span: 1.2,
            width: 9 * s, color: NB.run2.opacity(0.06 * k))
    }

    /// The small body, with the tail it drags. It swells and brightens on the near side of
    /// the orbit and shrinks away on the far side — the depth cue that makes the ellipse
    /// read as a circle seen edge-on.
    private func body(_ ctx: inout GraphicsContext, c: CGPoint, s: CGFloat, angle: Double) {
        let near = (sin(angle) + 1) / 2
        for k in stride(from: 14, through: 1, by: -1) {
            let t = angle - Double(k) * 0.045
            let fade = 1 - Double(k) / 15
            dot(&ctx, at: orbitPoint(t, c: c, s: s),
                r: 5 * s * CGFloat(fade * (0.55 + 0.45 * near)),
                NB.lime1.opacity(0.18 * fade * fade * (0.4 + 0.6 * near)))
        }
        let p = orbitPoint(angle, c: c, s: s)
        let r = 6 * s * CGFloat(0.70 + 0.45 * near)
        dot(&ctx, at: p, r: r * 3.2, NB.lime1.opacity(0.07 * (0.3 + 0.7 * near)))
        dot(&ctx, at: p, r: r * 1.8, NB.lime1.opacity(0.12 * (0.3 + 0.7 * near)))
        dot(&ctx, at: p, r: r, NB.lime1.opacity(0.55 + 0.45 * near))
        dot(&ctx, at: p, r: r * 0.42, NB.limePale.opacity(0.5 + 0.5 * near))
    }

    /// Every so often something else comes round the back — a moon, a dust giant, a cold
    /// one — in from one side, behind the planet, out the other. Which one, which way, how
    /// steep, how deep and when in the cycle are all drawn from the cycle index, so no two
    /// visits are alike and none of them is on a beat you could count.
    private func visitor(_ ctx: inout GraphicsContext, c: CGPoint, s: CGFloat, alpha: Double) {
        let period = 44.0, pass = 16.0
        let cycle = (clock / period).rounded(.down)
        let h1 = hash(cycle + 3, 12.9898), h2 = hash(cycle + 3, 78.233)
        let h3 = hash(cycle + 3, 39.425), h4 = hash(cycle + 3, 57.117)
        let u = (clock - cycle * period - h1 * (period - pass)) / pass
        guard u > 0, u < 1 else { return }

        // Quicker across the middle than at the edges: it sweeps past rather than drifting,
        // but not so fast that you only ever catch the tail of it.
        let e = 0.45 * u + 0.55 * u * u * (3 - 2 * u)
        let t = Double.pi + Double.pi * (h3 < 0.5 ? e : 1 - e)      // the far half only
        let tilt = (-28 + 56 * h4) * Double.pi / 180
        let ry = (34 + 60 * h2) * s                                  // how deep behind it dips
        let p = point(t, c: c, rx: 246 * s, ry: ry, tilt: tilt)
        let depth = 1 + sin(t)                                       // 1 at the sides, 0 deepest
        let fade = min(1, min(u, 1 - u) / 0.10) * alpha

        let kind = Int(h2 * 97) % 3
        let base: CGFloat = [30, 50, 38][kind]
        let tint: Color = [NB.white, NB.ember2, NB.violet2][kind]
        let tintA: Double = [0.34, 0.32, 0.34][kind]
        let r = base * s * CGFloat(0.62 + 0.38 * depth)
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        let disc = Path(ellipseIn: rect)
        let key = CGPoint(x: p.x - r * 0.42, y: p.y - r * 0.48)

        // The giants carry a little atmosphere; the moon does not.
        if kind > 0 {
            let g = r * 1.7
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - g, y: p.y - g, width: g * 2, height: g * 2)),
                     with: .radialGradient(
                        Gradient(colors: [tint.opacity(0.10 * fade), tint.opacity(0)]),
                        center: p, startRadius: r * 0.8, endRadius: g))
        }
        ctx.fill(disc, with: .color(NB.discInk.opacity(fade)))
        ctx.fill(disc, with: .color(tint.opacity(tintA * fade)))
        // Lit the same way the planet is — one sky, one sun.
        ctx.fill(disc, with: .radialGradient(
            Gradient(colors: [NB.white.opacity(0.22 * fade), NB.white.opacity(0)]),
            center: key, startRadius: 0, endRadius: r * 1.15))
        ctx.fill(disc, with: .radialGradient(
            Gradient(colors: [NB.panelInk.opacity(0), NB.panelInk.opacity(0.85 * fade)]),
            center: CGPoint(x: p.x * 2 - key.x, y: p.y * 2 - key.y),
            startRadius: r * 0.15, endRadius: r * 1.5))
        ctx.stroke(disc, with: .color(NB.white.opacity(0.11 * fade)), lineWidth: 1)
    }

    /// Deterministic 0…1 from an index, so the sky is the same sky on every launch.
    private func hash(_ n: Double, _ salt: Double) -> Double {
        let v = sin(n * salt) * 43758.5453
        return v - v.rounded(.down)
    }

    /// The starfield. Thirty specks, each with its own size, brightness and rate, so the
    /// sky shimmers unevenly the way one does rather than pulsing as a block.
    private func dust(_ ctx: inout GraphicsContext, sx: CGFloat, sy: CGFloat,
                      s: CGFloat, alpha: Double) {
        for i in 0..<30 {
            let n = Double(i) + 1
            let hx = hash(n, 12.9898), hy = hash(n, 78.233), hz = hash(n, 39.425)
            let side: CGFloat = hz < 0.62 ? 2 : (hz < 0.92 ? 3 : 4)
            let rate = 0.4 + 1.7 * hz
            let twinkle = max(0, 0.30 + 0.70 * sin(clock * rate + hy * 6.283))
            // The brightest few take a colour — a dot screen can hold that much.
            let tint: Color = hz > 0.94 ? NB.ember1 : (hz > 0.88 ? NB.cyan1 : NB.white)
            var square = Path()
            square.addRect(CGRect(x: CGFloat(hx) * 358 * sx, y: CGFloat(hy) * 470 * sy,
                                  width: side * s, height: side * s))
            ctx.fill(square, with: .color(tint
                .opacity((0.13 + 0.36 * hz) * twinkle * alpha)))
        }
    }

    /// Three slow washes of colour drifting behind everything, on periods that do not
    /// divide into each other. They never resolve into a shape — they are only there so
    /// the black is not flat black.
    private func nebula(_ ctx: inout GraphicsContext, size: CGSize, s: CGFloat, alpha: Double) {
        let blobs: [(Color, Double, Double, Double)] = [
            (NB.run2, 0.0, 61, 0.070),
            (NB.ember1, 2.1, 83, 0.052),
            (NB.violet3, 4.2, 71, 0.066),
        ]
        for (tint, phase, period, peak) in blobs {
            let t = clock * 2 * .pi / period + phase
            let cx = CGFloat(0.5 + 0.44 * sin(t)) * size.width
            let cy = CGFloat(0.44 + 0.38 * cos(t * 0.7 + 1.3)) * size.height
            let r = 172 * s
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(
                        Gradient(colors: [tint.opacity(peak * alpha), tint.opacity(0)]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
        }
    }

    /// Three lanes of shooting stars, on 7.3 / 11.9 / 17.1 seconds. They are the only
    /// things here not on a fixed rail, and they are what keeps the panel from settling
    /// into a screensaver.
    private func meteor(_ ctx: inout GraphicsContext, lane: Int, sx: CGFloat, sy: CGFloat,
                        s: CGFloat, alpha: Double) {
        let spec: [(Double, Double, Color, CGFloat)] = [
            (7.3, 0.9, NB.limePale, 1.4),
            (11.9, 1.4, NB.white, 1.8),
            (17.1, 1.1, NB.ember1, 1.5),
        ]
        let (period, flight, tint, weight) = spec[lane]
        let cycle = (clock / period).rounded(.down)
        let u = (clock - cycle * period) / flight
        guard u > 0, u < 1 else { return }
        // A cheap hash of the cycle index, so no two passes share a path.
        let seed = hash(cycle + Double(lane) * 7 + 1, 12.9898)
        let drop = hash(cycle + Double(lane) * 7 + 1, 78.233)
        let y0 = CGFloat(-20 + 420 * seed)
        let from = CGPoint(x: -40 * sx, y: y0 * sy)
        let to = CGPoint(x: 420 * sx, y: (y0 + CGFloat(60 + 220 * drop)) * sy)
        func at(_ p: Double) -> CGPoint {
            CGPoint(x: from.x + (to.x - from.x) * CGFloat(p),
                    y: from.y + (to.y - from.y) * CGFloat(p))
        }
        let fade = sin(.pi * u) * alpha
        // The tail is drawn in falling steps rather than as one flat line, so it actually
        // thins out and dims behind the head instead of ending in a hard stop.
        for (i, step) in [(0.38, 0.05), (0.22, 0.11), (0.10, 0.24), (0.0, 0.55)].enumerated() {
            var seg = Path()
            seg.move(to: at(max(0, u - step.0)))
            seg.addLine(to: at(max(0, u - (i == 0 ? 0.22 : [0.11, 0.05, 0.0][i - 1]))))
            ctx.stroke(seg, with: .color(tint.opacity(step.1 * fade)),
                       style: StrokeStyle(lineWidth: weight * s * CGFloat(0.5 + 0.2 * Double(3 - i)),
                                          lineCap: .round))
        }
        dot(&ctx, at: at(u), r: 2 * s, tint.opacity(0.85 * fade))
    }

    private func arc(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                     from: Double, span: Double, width: CGFloat, color: Color) {
        var path = Path()
        path.addArc(center: c, radius: r,
                    startAngle: .radians(from), endAngle: .radians(from + span),
                    clockwise: false)
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func dot(_ ctx: inout GraphicsContext, at p: CGPoint, r: CGFloat, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                 with: .color(color))
    }
}

/// 04 · 01 默认 — the standby illustration inside the panel. It is the same field the boot
/// ceremony ends on, still turning: the panel is not handed a fresh drawing at ◇11.
struct StandbyArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0…1 — drives the lime band's length so it reads as a charge level, not a decoration.
    var charge: Double = 0.72
    var chargeKnown = true
    var animate = true

    /// Starts part-turned so the held pose is a composed one rather than the zero frame.
    @State private var clock: Double = 6
    @State private var lastTick: Date?

    var body: some View {
        // F5 C11 · decorative. Under Reduce Motion it holds its pose, and nothing ticks.
        if animate && !reduceMotion {
            TimelineView(.animation) { tl in
                canvas
                    .onChange(of: tl.date) { _, now in
                        let previous = lastTick ?? now
                        lastTick = now
                        // Elapsed on-screen time, capped so a stall does not jump the field.
                        clock += min(now.timeIntervalSince(previous), 1.0 / 20)
                    }
            }
        } else {
            canvas
        }
    }

    private var canvas: some View {
        Canvas { ctx, size in
            OrbitField(clock: clock, charge: charge, chargeKnown: chargeKnown)
                .draw(in: &ctx, size: size)
        }
    }
}
