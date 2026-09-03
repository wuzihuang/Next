import SwiftUI

/// A ball of dots for the dock's right key. Two Fibonacci shells: the outer one turns one
/// way and draws in, the inner one turns the other way and swells out to meet it, and both
/// land in a single depth sort so an inner dot can paint over an outer one. That single sort
/// is not a nicety — painting back to front with alpha is the whole reason it reads as a
/// volume rather than as a spray of dots.
///
/// Ported from the Originkit "Particle Interlock" reference; its accent (#EFF65A) is
/// `NB.lime1` to the digit, so the key keeps the dock's own colour.
struct OrbGlyph: View {
    var side: CGFloat = 32
    var dot: Color = NB.iconInk
    var accent: Color = NB.lime1
    /// 1 = the reference's 90 + 60 dots; 2.43 is its own preset, and at 32 pt it is what
    /// makes the two shells read as shells rather than as a scatter.
    var density: Double = 2.43
    /// The reference's preset is 1.5, tuned on a ball an order of magnitude larger. At glyph
    /// size every disc is already at the `orbMinRadius` floor, so 1.5 only welds them shut.
    var dotSize: Double = 1
    /// Signed: negative runs the loop backwards. Half speed — a ten-second loop — because
    /// the key sits under the reading and a five-second one kept pulling the eye down.
    var speed: Double = 0.5
    /// Extra whole turns per loop. Counted per loop rather than per second, so any whole
    /// number of them leaves the loop exactly as seamless as it was.
    var spinTurns: Double = 1
    var spread: Double = 1
    var turn: Double = 0
    var tilt: Double = 0

    private func params(_ phase: Double, _ size: Double) -> OrbParams {
        OrbParams(density: density, spread: spread,
                  dotScale: orbDotScale(size) * dotSize,
                  yaw: turn, pitch: tilt, spinTurns: spinTurns, phase: phase)
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let s = min(size.width, size.height)
                let bx = (size.width - s) / 2
                let by = (size.height - s) / 2
                let half = s / 2
                // Wrapped rather than left to accumulate: an unbounded clock eventually
                // costs float precision inside the loop's trig.
                let t = tl.date.timeIntervalSinceReferenceDate * speed / orbPeriod
                var phase = t.truncatingRemainder(dividingBy: 1)
                if phase < 0 { phase += 1 }

                let P = params(phase, s)
                let fit = OrbFitCache.value(size: s, P)
                var pts: [OrbSpeck] = []
                pts.reserveCapacity(Int(160 * density) + 8)
                orbFrame(phase, density, into: &pts)

                for d in orbProject(pts, size: s, P) {
                    // The fit scales positions about the centre and radii by a gentler
                    // factor, exactly as the reference does.
                    let rr = d.r * (0.55 + 0.45 * fit)
                    if rr <= 0.05 || d.a <= 0.004 { continue }
                    var dr = rr
                    var da = min(1, d.a)
                    // A floor on the disc, with the alpha scaled by the area it would
                    // otherwise have lost. The back of the ball is exactly where the depth
                    // cue lives, and at glyph size those dots are all sub-pixel.
                    if dr < orbMinRadius {
                        da *= (dr / orbMinRadius) * (dr / orbMinRadius)
                        dr = orbMinRadius
                    }
                    let cx = bx + half + (d.x - half) * fit
                    let cy = by + half + (d.y - half) * fit
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - dr, y: cy - dr,
                                                    width: dr * 2, height: dr * 2)),
                             with: .color((d.accent ? accent : dot).opacity(da)))
                }
            }
        }
        .frame(width: side, height: side)
    }
}

// MARK: - The ball

private let orbPeriod: Double = 5          // seconds for one loop at speed 1
private let orbBaseSpread: Double = 0.3    // sphere radius as a fraction of the ball box
private let orbPerspective: Double = 3.5   // camera distance in ball radii
private let orbMinRadius: Double = 0.6
private let tau = Double.pi * 2

struct OrbParams {
    var density: Double
    var spread: Double
    var dotScale: Double
    var yaw: Double
    var pitch: Double
    var spinTurns: Double
    var phase: Double
}

struct OrbSpeck {
    var x, y, z: Double
    var rScale: Double
    var aScale: Double
    var accent: Bool
}

private struct OrbDisc {
    var x, y, r, a, z: Double
    var accent: Bool
}

/// Fibonacci sphere: even coverage with no poles and no seam.
private func orbFib(_ i: Int, _ n: Int) -> (Double, Double, Double) {
    let y = 1 - (Double(i) / Double(max(1, n - 1))) * 2
    let r = (max(0, 1 - y * y)).squareRoot()
    let th = 2.399963 * Double(i)
    return (cos(th) * r, y, sin(th) * r)
}

/// Yaw about the vertical axis, then pitch. Used both for a shell's own baked tilt and for
/// the viewer's turn / tilt.
private func orbSpin(_ p: (Double, Double, Double), _ yaw: Double, _ pitch: Double)
    -> (Double, Double, Double) {
    let ca = cos(yaw), sa = sin(yaw)
    let rx = p.0 * ca - p.2 * sa
    var rz = p.0 * sa + p.2 * ca
    let co = cos(pitch), so = sin(pitch)
    let ry = p.1 * co - rz * so
    rz = p.1 * so + rz * co
    return (rx, ry, rz)
}

/// The loop itself — the only part of this file that is "interlock".
private func orbFrame(_ t: Double, _ n: Double, into out: inout [OrbSpeck]) {
    let k = 0.5 - 0.5 * cos(tau * t)
    // Outer shell: turning one way, drawing in.
    let outer = max(1, Int((90 * n).rounded()))
    for i in 0..<outer {
        let q = orbSpin(orbFib(i, outer), tau * t, 0.36)
        let s = 1 - 0.22 * k
        out.append(OrbSpeck(x: q.0 * s, y: q.1 * s, z: q.2 * s,
                            rScale: 0.85, aScale: 0.85, accent: false))
    }
    // Inner shell: the other way, swelling out to meet it.
    let inner = max(1, Int((60 * n).rounded()))
    for i in 0..<inner {
        let q = orbSpin(orbFib(i, inner), -tau * t, 0.36)
        let s = 0.45 + 0.3 * k
        out.append(OrbSpeck(x: q.0 * s, y: q.1 * s, z: q.2 * s,
                            rScale: 0.9, aScale: 1, accent: true))
    }
}

/// Rotate, project, sort back to front.
private func orbProject(_ pts: [OrbSpeck], size: Double, _ P: OrbParams) -> [OrbDisc] {
    let c = size / 2
    let R = size * orbBaseSpread * P.spread
    let pv = orbPerspective
    let yaw = P.yaw + tau * P.spinTurns * P.phase
    var out: [OrbDisc] = []
    out.reserveCapacity(pts.count)
    for p in pts {
        let q = orbSpin((p.x, p.y, p.z), yaw, P.pitch)
        let z = q.2
        let s = pv / (pv - z)
        let f = min(1, max(0, (z + 1.1) / 2.2))
        out.append(OrbDisc(x: c + q.0 * R * s,
                           y: c + q.1 * R * s,
                           r: P.dotScale * (0.4 + 1.6 * f) * s * p.rScale,
                           a: (0.07 + 0.93 * pow(f, 1.55)) * p.aScale,
                           z: z, accent: p.accent))
    }
    out.sort { $0.z < $1.z }
    return out
}

/// Ball size to dot scale, in three segments. Deliberately not linear: a ball twice the size
/// gets dots well under twice the radius, so it reads as denser rather than as a zoom.
private func orbDotScale(_ size: Double) -> Double {
    if size <= 46 { return 0.4 }
    if size <= 190 { return 0.4 + ((size - 46) / 144) * 0.6 }
    if size <= 340 { return 1 + ((size - 190) / 150) * 0.55 }
    return 1.55
}

/// The fit is twenty frames of work and its answer only changes when the ball does, so it is
/// measured once per shape and kept. Read from the Canvas closure, which draws on the main
/// thread; a `@State` settled in `onAppear` would also mean a first frame drawn at the wrong
/// size.
enum OrbFitCache {
    private static var store: [String: Double] = [:]

    static func value(size: Double, _ P: OrbParams) -> Double {
        // Keyed on everything the extent depends on. Phase is not one of them: the fit is
        // the maximum over the whole loop.
        let key = "\(size)/\(P.density)/\(P.spread)/\(P.yaw)/\(P.pitch)/\(P.spinTurns)"
        if let hit = store[key] { return hit }
        let v = orbFit(size: size, P)
        store[key] = v
        return v
    }
}

/// Sample the loop at twenty phases, measure how far out it ever throws a dot, and normalise
/// the ball to its box from that.
func orbFit(size: Double, _ base: OrbParams) -> Double {
    var probe = base
    probe.dotScale = 1
    let half = size / 2
    var ext = 0.0
    for k in 0..<20 {
        probe.phase = Double(k) / 20
        var pts: [OrbSpeck] = []
        orbFrame(probe.phase, probe.density, into: &pts)
        for d in orbProject(pts, size: size, probe) where d.a > 0.05 && d.r > 0.15 {
            ext = max(ext, abs(d.x - half) + 0.5 * d.r, abs(d.y - half) + 0.5 * d.r)
        }
    }
    return ext > 1 ? min(1.7, max(0.55, 0.415 * size / ext)) : 1
}

#Preview {
    ZStack {
        NB.carbon
        HStack(spacing: 20) {
            ZStack {
                Circle().fill(NB.carbon4)
                Circle().stroke(NB.hairline, lineWidth: 1)
                OrbGlyph()
            }
            .frame(width: NB.Layout.dockSideButton, height: NB.Layout.dockSideButton)
            OrbGlyph(side: 120)
        }
    }
    .ignoresSafeArea()
}
