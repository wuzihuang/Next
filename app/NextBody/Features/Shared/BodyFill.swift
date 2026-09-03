import SwiftUI

/// 03 · Scanning and 06 · body scan. Bio-impedance has no waveform to show — the old ECG
/// trace was a picture of a measurement that is not happening. What the current actually does
/// is walk the body, so that is what is drawn: a dot-matrix figure, dark, lit from the sternum
/// outward. One beat per band second: the torso grows a ring, and a spark on each limb hops one
/// bead further out. Legs finish on the last second. Nothing here is timed by the phone — the
/// beat is the band's `remaining`, and the only phone-side motion is the 0.28 s hop after it.
struct BodyFill: View {
    /// Whole beats the band has reported: `total - remaining`.
    var beat: Int
    var total: Int = 30
    /// When `beat` last changed; the hop animates from this instant.
    var beatAt: Date
    /// False before contact: a dark body with one breathing dot where the current will enter.
    var active: Bool = true
    /// A lifted finger: the picture freezes where it was and goes amber.
    var held: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: held)) { tl in
            Canvas(rendersAsynchronously: true) { ctx, size in
                draw(&ctx, size: size, now: tl.date)
            }
        }
        .accessibilityLabel(active ? "Body scan, \(beat) of \(total) seconds" : "Waiting for contact")
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, now: Date) {
        let map = BodyMap.shared
        let scale = (size.height - 6) / BodyMap.unitHeight
        let ox = size.width / 2 - BodyMap.unitWidth / 2 * scale, oy: CGFloat = 3
        let base = 1.05 * scale
        let lit: RGB = held ? .ember : .lime
        let hot: RGB = held ? .emberPale : .white
        let u = now.timeIntervalSince(beatAt)

        func threshold(_ b: BodyMap.Branch) -> CGFloat {
            guard active else { return -1 }
            let hop = reduceMotion ? 1 : smooth((u - b.offset) / 0.28)
            let beats = beat == 0 ? 0 : CGFloat(beat - 1) + hop
            return map.maxD * min(1, beats / CGFloat(total)) + 4
        }
        var thresholds: [BodyMap.Branch: CGFloat] = [:]
        for b in BodyMap.Branch.allCases { thresholds[b] = threshold(b) }

        // Dots · unlit in one path, lit ones bucketed by how recently they lit (hot → settled).
        var unlit = Path()
        var buckets = [Path](repeating: Path(), count: 8)
        for p in map.dots {
            let age = thresholds[p.branch]! - p.d
            let x = ox + p.x * scale, y = oy + p.y * scale
            if age < 0 {
                unlit.addEllipse(in: CGRect(x: x - base * 0.8, y: y - base * 0.8, width: base * 1.6, height: base * 1.6))
            } else {
                let h = held ? 0 : max(0, 1 - age / 14)
                let r = base * (1 + 1.1 * h * h)
                buckets[min(7, Int(h * 7.99))].addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        ctx.fill(unlit, with: .color(NB.white.opacity(0.10)))
        for (i, path) in buckets.enumerated() where !path.isEmpty {
            ctx.fill(path, with: .color(lit.mix(hot, CGFloat(i) / 7 * 0.9).color))
        }

        // Sparks · the front of each limb chain, while the front is on it.
        if active && !held {
            for chain in map.chains {
                let T = thresholds[chain.branch]!
                guard T >= chain.start - 6, T <= chain.end + 4, let pt = chain.point(at: T) else { continue }
                let x = ox + pt.x * scale, y = oy + pt.y * scale, R = 9 * scale
                ctx.fill(Path(ellipseIn: CGRect(x: x - R, y: y - R, width: R * 2, height: R * 2)),
                         with: .radialGradient(Gradient(colors: [NB.lime1.opacity(0.55), NB.lime1.opacity(0)]),
                                               center: CGPoint(x: x, y: y), startRadius: 0, endRadius: R))
                let c = 1.6 * scale
                ctx.fill(Path(ellipseIn: CGRect(x: x - c, y: y - c, width: c * 2, height: c * 2)), with: .color(NB.white))
            }
        }

        // No contact yet · one breathing dot where the current will enter.
        if !active {
            let a = reduceMotion ? 0.6 : 0.35 + 0.35 * (0.5 + 0.5 * sin(now.timeIntervalSinceReferenceDate / 0.6))
            let x = ox + BodyMap.centre.x * scale, y = oy + BodyMap.centre.y * scale, R = 14 * scale
            ctx.fill(Path(ellipseIn: CGRect(x: x - R, y: y - R, width: R * 2, height: R * 2)),
                     with: .radialGradient(Gradient(colors: [NB.lime1.opacity(a * 0.5), NB.lime1.opacity(0)]),
                                           center: CGPoint(x: x, y: y), startRadius: 0, endRadius: R))
            let c = base * 1.4
            ctx.fill(Path(ellipseIn: CGRect(x: x - c, y: y - c, width: c * 2, height: c * 2)), with: .color(NB.lime1.opacity(a)))
        }
    }

    private func smooth(_ v: Double) -> CGFloat {
        let u = CGFloat(max(0, min(1, v)))
        return u * u * (3 - 2 * u)
    }

    private struct RGB {
        var r: CGFloat, g: CGFloat, b: CGFloat
        static let lime      = RGB(r: 0xEF / 255, g: 0xF6 / 255, b: 0x5A / 255)   // --lime-1
        static let white     = RGB(r: 1, g: 1, b: 1)
        static let ember     = RGB(r: 0xE0 / 255, g: 0x5E / 255, b: 0x10 / 255)   // --ember-2
        static let emberPale = RGB(r: 0xFF / 255, g: 0xE9 / 255, b: 0xB8 / 255)   // --ember-pale
        func mix(_ o: RGB, _ t: CGFloat) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
        var color: Color { Color(red: r, green: g, blue: b) }
    }
}

/// The figure, in a 200 × 372 unit space, traced from the reference render: the silhouette is
/// a table of lit columns per row (pitch 3.3 units, the same dot density as the reference),
/// so the body is exactly the one in the design and never a drawing of it. A dot's fill order is
/// its distance from the sternum — straight line for the torso, along the skeleton for a limb —
/// so the torso grows as a ring and the limbs light from the shoulder and the hip outward.
struct BodyMap {
    static let shared = BodyMap()
    static let unitWidth: CGFloat = 200, unitHeight: CGFloat = 372
    static let centre = CGPoint(x: 100, y: 104)
    static let pitch: CGFloat = 3.3
    static let x0: CGFloat = -98.0, y0: CGFloat = 4.0

    enum Branch: CaseIterable, Hashable {
        case torso, head, armL, armR, legL, legR
        /// Seconds into the beat before this branch hops — the limbs answer one after another.
        var offset: Double {
            switch self {
            case .torso: 0; case .head: 0.08; case .armL: 0.14; case .armR: 0.22; case .legL: 0.44; case .legR: 0.52
            }
        }
    }
    struct Dot { let x: CGFloat, y: CGFloat, d: CGFloat; let branch: Branch }
    struct Segment {
        let a: CGPoint, b: CGPoint, branch: Branch, radial: Bool
        /// Torso segments win ties against a limb, so the chest sides light with the ring.
        let priority: CGFloat
        var d0: CGFloat = 0
        var len: CGFloat { hypot(b.x - a.x, b.y - a.y) }
    }
    struct Chain {
        let branch: Branch, segments: [Segment], start: CGFloat, end: CGFloat
        func point(at T: CGFloat) -> CGPoint? {
            for s in segments where T >= s.d0 && T <= s.d0 + s.len {
                let t = (T - s.d0) / s.len
                return CGPoint(x: s.a.x + (s.b.x - s.a.x) * t, y: s.a.y + (s.b.y - s.a.y) * t)
            }
            if T < segments.first!.d0 { return segments.first!.a }
            return segments.last!.b
        }
    }

    /// One entry per grid row, top of the head first: pairs of first/last lit column, where
    /// column i sits at `x0 + i · pitch`. Skull is a small round superellipse — wide enough
    /// that the crown is not a spike, narrow enough that it sits on the neck, not the shoulders.
    private static let rows: [[Int]] = [
        [57, 63],
        [56, 64],
        [55, 65],
        [55, 65],
        [54, 66],
        [54, 66],
        [54, 66],
        [54, 66],
        [54, 66],
        [55, 65],
        [55, 65],
        [56, 64],
        [57, 63],
        [57, 63],
        [57, 63],
        [57, 63],
        [57, 63],
        [56, 64],
        [54, 66],
        [52, 68],
        [50, 70],
        [49, 71],
        [49, 71],
        [48, 72],
        [48, 72],
        [48, 72],
        [48, 72],
        [48, 72],
        [48, 72],
        [48, 72],
        [47, 73],
        [47, 73],
        [47, 51, 53, 67, 69, 73],
        [47, 50, 53, 67, 70, 73],
        [46, 50, 53, 67, 70, 74],
        [46, 50, 53, 67, 70, 74],
        [46, 49, 54, 66, 71, 74],
        [45, 49, 54, 66, 71, 75],
        [45, 48, 54, 66, 72, 75],
        [45, 48, 54, 66, 72, 75],
        [44, 48, 54, 66, 72, 76],
        [44, 47, 54, 66, 73, 76],
        [44, 47, 53, 67, 73, 76],
        [43, 47, 53, 67, 73, 77],
        [43, 46, 53, 67, 74, 77],
        [43, 46, 53, 67, 74, 77],
        [43, 46, 52, 68, 74, 77],
        [43, 45, 52, 68, 75, 77],
        [42, 45, 52, 68, 75, 78],
        [42, 44, 51, 69, 76, 78],
        [42, 44, 51, 69, 76, 78],
        [41, 43, 51, 69, 77, 79],
        [41, 43, 51, 69, 77, 79],
        [40, 43, 51, 69, 77, 80],
        [39, 43, 50, 70, 77, 81],
        [39, 43, 50, 70, 77, 81],
        [39, 43, 50, 70, 77, 81],
        [38, 43, 50, 70, 77, 82],
        [38, 42, 50, 59, 61, 70, 78, 82],
        [39, 42, 50, 59, 61, 70, 78, 81],
        [39, 42, 50, 59, 61, 70, 78, 81],
        [39, 41, 51, 58, 62, 69, 79, 81],
        [40, 40, 51, 58, 62, 69, 80, 80],
        [51, 58, 62, 69],
        [51, 58, 62, 69],
        [51, 58, 62, 69],
        [51, 58, 62, 69],
        [51, 58, 62, 69],
        [51, 58, 62, 69],
        [51, 57, 63, 69],
        [51, 57, 63, 69],
        [52, 57, 63, 68],
        [52, 57, 63, 68],
        [52, 57, 63, 68],
        [52, 57, 63, 68],
        [52, 56, 64, 68],
        [52, 56, 64, 68],
        [52, 56, 64, 68],
        [51, 56, 64, 69],
        [51, 56, 64, 69],
        [51, 56, 64, 69],
        [51, 56, 64, 69],
        [51, 56, 64, 69],
        [51, 56, 64, 69],
        [51, 56, 64, 69],
        [51, 56, 64, 69],
        [51, 56, 64, 69],
        [51, 56, 64, 69],
        [51, 56, 64, 69],
        [51, 56, 64, 69],
        [51, 56, 64, 69],
        [51, 55, 65, 69],
        [51, 55, 65, 69],
        [52, 55, 65, 68],
        [52, 55, 65, 68],
        [52, 55, 65, 68],
        [52, 55, 65, 68],
        [52, 55, 65, 68],
        [52, 55, 65, 68],
        [52, 55, 65, 68],
        [52, 55, 65, 68],
        [52, 55, 65, 68],
        [52, 55, 65, 68],
        [52, 55, 65, 68],
        [51, 55, 65, 69],
        [51, 55, 65, 69],
        [50, 55, 65, 70],
        [50, 55, 65, 70],
        [49, 54, 66, 71],
        [49, 54, 66, 71],
        [50, 54, 66, 70],
        [51, 52, 68, 69]
    ]

    let dots: [Dot]
    let chains: [Chain]
    let maxD: CGFloat

    private init() {
        var S: [Segment] = []
        func seg(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ b: Branch, radial: Bool = false, priority: CGFloat = 0) {
            S.append(Segment(a: CGPoint(x: x1, y: y1), b: CGPoint(x: x2, y: y2), branch: b, radial: radial, priority: priority))
        }
        // torso · radial from the sternum
        seg(100,  66, 100, 196, .torso, radial: true, priority: 10)   // spine
        seg( 64,  84, 136,  84, .torso, radial: true, priority: 10)   // shoulder line
        seg( 80, 110,  78, 170, .torso, radial: true, priority: 10)   // flanks
        seg(120, 110, 122, 170, .torso, radial: true, priority: 10)
        seg( 72, 186, 128, 186, .torso, radial: true, priority: 10)   // pelvis
        // head chain · a smaller round skull, spark travels to the crown.
        seg(100,  62, 100,  40, .head)
        seg(100,  40, 100,  14, .head)
        for s: CGFloat in [-1, 1] {
            let a: Branch = s < 0 ? .armL : .armR, l: Branch = s < 0 ? .legL : .legR
            seg(100 + 36 * s,  90, 100 + 48 * s, 145, a)   // arms hang open, hands clear of the thighs
            seg(100 + 48 * s, 145, 100 + 59 * s, 185, a)
            seg(100 + 59 * s, 185, 100 + 64 * s, 210, a)
            seg(100 + 18 * s, 196, 100 + 21 * s, 280, l)
            seg(100 + 21 * s, 280, 100 + 20 * s, 336, l)
            seg(100 + 20 * s, 336, 100 + 27 * s, 368, l)
        }
        // A limb segment starts at its chain root's straight-line distance plus the arc so far.
        var chains: [Chain] = []
        for b in Branch.allCases where b != .torso {
            var segs = S.filter { $0.branch == b }
            var d = hypot(segs[0].a.x - Self.centre.x, segs[0].a.y - Self.centre.y)
            let start = d
            var prev = segs[0].a
            for i in segs.indices {
                d += hypot(segs[i].a.x - prev.x, segs[i].a.y - prev.y)
                segs[i].d0 = d
                d += segs[i].len
                prev = segs[i].b
            }
            chains.append(Chain(branch: b, segments: segs, start: start, end: d))
            for i in S.indices where S[i].branch == b { S[i].d0 = segs.first { $0.a == S[i].a && $0.b == S[i].b }!.d0 }
        }

        var dots: [Dot] = []
        var maxD: CGFloat = 0
        for (j, row) in Self.rows.enumerated() {
            let y = Self.y0 + CGFloat(j) * Self.pitch
            for k in stride(from: 0, to: row.count, by: 2) {
                for i in row[k]...row[k + 1] {
                    let x = Self.x0 + CGFloat(i) * Self.pitch
                    var best: (score: CGFloat, d: CGFloat, b: Branch)?
                    for s in S {
                        let vx = s.b.x - s.a.x, vy = s.b.y - s.a.y, L2 = vx * vx + vy * vy
                        let t = L2 > 0 ? max(0, min(1, ((x - s.a.x) * vx + (y - s.a.y) * vy) / L2)) : 0
                        let perp = hypot(x - (s.a.x + vx * t), y - (s.a.y + vy * t))
                        let score = perp - s.priority
                        if best == nil || score < best!.score {
                            let d = s.radial ? hypot(x - Self.centre.x, y - Self.centre.y) : s.d0 + t * s.len + perp * 0.5
                            best = (score, d, s.branch)
                        }
                    }
                    if let best {
                        dots.append(Dot(x: x, y: y, d: best.d, branch: best.b))
                        maxD = max(maxD, best.d)
                    }
                }
            }
        }
        self.dots = dots
        self.chains = chains
        self.maxD = maxD
    }
}
