import Foundation

/// Clock-parameterized pose of one idle plate. Separate from SwiftUI so two
/// timestamps can be compared without a simulator. `clock` is on-screen seconds;
/// one loop is one full revolution of every moon / pip, seamless at the seam.
public struct IdlePlatePose: Equatable, Sendable {
    /// Loop phase 0..<1 when moving; the hold pose when not.
    public var phase: Double
    public var breathe: Double
    public var ringDeg: Double
    public var dash: Double
    public var bodyX: Double
    public var bodyY: Double
    public var lightX: Double
    /// Orbit progress 0..<1. Zero is the Paper rest seat of that plate's moon / pip.
    public var satellite: Double
    public var moonYaw: Double
    public var moonPitch: Double
    public var comet: Double
    public var glow: Double
    public var twinkle: Double

    /// Flattened samples the XCTest compares. Order is part of the contract.
    public var samples: [Double] {
        [phase, breathe, ringDeg, dash, bodyX, bodyY, lightX,
         satellite, moonYaw, moonPitch, comet, glow, twinkle]
    }
}

/// One body on an inclined ellipse. `front` is the near half of the ring plane.
public struct IdleOrbit: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var front: Bool
}

public enum IdlePlateMotion: Sendable {
    /// One closed revolution. Long enough to read as orbit, short enough to see.
    public static let loopSeconds: Double = 8

    // MARK: - Motion grammar
    //
    // Same three rules the source art obeys (output/fx/render_loops.py, written up in
    // output/fx/PLATES.md):
    //   1. Nothing turns at a constant rate. A constant rate is a clock, and there is no clock
    //      in the sky: anything going round obeys Kepler's second law and visibly crawls at
    //      apoapsis, whips through periapsis.
    //   2. A ring does not rotate. Its tilt is fixed by the planet's spin axis, and its
    //      particles are on independent orbits, so it cannot turn as one rigid hoop. Dashes on
    //      an orbit track are tick marks, not a conveyor belt: they hold still.
    //   3. What changes in eight seconds of sky is light, not position -- and light is never a
    //      single sine.
    // Every term below is zero (or 1, for a multiplier) at t == 0, so the hold pose under
    // Reduce Motion is still exactly the Paper rest seat.

    /// Where a body sits along its orbit, 0..<1, Kepler-paced: apoapsis is the Paper rest seat,
    /// so a moon lingers near where the plate was composed and sweeps quickly round the far
    /// side. Newton on M = E - e sinE. progress(0) == 0, progress(0.5) == 0.5, progress(1) == 1.
    public static func orbitProgress(_ t: Double, ecc: Double = orbitEccentricity) -> Double {
        let tau = Double.pi * 2
        let m = tau * t + .pi
        var e = m + ecc * sin(m)
        for _ in 0..<8 {
            e -= (e - ecc * sin(e) - m) / (1 - ecc * cos(e))
        }
        return (e - .pi) / tau
    }

    /// Eccentricity of the idle orbits. One number for the whole set: the pose carries a single
    /// `satellite` channel, and this is the value where the speed-up is legible at 8 s without
    /// the body looking flung.
    public static let orbitEccentricity: Double = 0.45

    /// Brightness wobble: three harmonics with unrelated phases, so a glow reads as something
    /// seen through air instead of a metronome. Zero at t == 0 and at the seam.
    public static func flicker(_ t: Double, _ seed: Double) -> Double {
        let tau = Double.pi * 2
        var v = 0.0
        for (i, wk) in [(0.58, 1.0), (0.29, 2.0), (0.13, 3.0)].enumerated() {
            let ph = (seed * 1.7 + Double(i) * 2.39).truncatingRemainder(dividingBy: tau)
            v += wk.0 * (sin(tau * wk.1 * t + ph) - sin(ph))
        }
        return v
    }

    /// Pose of `plate` at `clock` on-screen seconds. `t` is the loop phase
    /// (0..<1). `moving: false` (Reduce Motion) freezes the hold pose so two
    /// clocks compare equal.
    public static func pose(plate: Int, clock: Double, moving: Bool) -> IdlePlatePose {
        let t = moving ? phase(clock) : 0
        return look(plate, t)
    }

    public static func samples(plate: Int, clock: Double, moving: Bool) -> [Double] {
        pose(plate: plate, clock: clock, moving: moving).samples
    }

    public static func phase(_ clock: Double) -> Double {
        let p = clock / loopSeconds
        return p - p.rounded(.down)
    }

    /// Ellipse through the Paper rest seat `(restX, restY)` around `(cx, cy)`.
    /// `flatten` is the minor-axis ratio (saturn rings ~0.25). `u` is 0..<1;
    /// `u == 0` is the rest seat and the near ansa.
    public static func around(
        cx: Double, cy: Double,
        restX: Double, restY: Double,
        flatten: Double,
        u: Double
    ) -> IdleOrbit {
        let tau = Double.pi * 2
        let wrap = u - u.rounded(.down)
        let ox = restX - cx
        let oy = restY - cy
        let bx = -oy * flatten
        let by = ox * flatten
        let c = cos(tau * wrap)
        let s = sin(tau * wrap)
        return IdleOrbit(
            x: cx + ox * c + bx * s,
            y: cy + oy * c + by * s,
            front: s >= 0)
    }

    /// Point at parameter `u` (0...1) on a Paper SVG elliptical arc.
    public static func svgArcPoint(
        x1: Double, y1: Double, rx: Double, ry: Double,
        deg: Double, large: Bool, sweep: Bool,
        x2: Double, y2: Double, u: Double
    ) -> (Double, Double) {
        let phi = deg * .pi / 180
        let cosφ = cos(phi), sinφ = sin(phi)
        let dx = (x1 - x2) / 2, dy = (y1 - y2) / 2
        let x1p = cosφ * dx + sinφ * dy
        let y1p = -sinφ * dx + cosφ * dy
        var rxv = abs(rx), ryv = abs(ry)
        let λ = (x1p * x1p) / (rxv * rxv) + (y1p * y1p) / (ryv * ryv)
        if λ > 1 {
            let r = sqrt(λ)
            rxv *= r
            ryv *= r
        }
        let num = max(0, rxv * rxv * ryv * ryv - rxv * rxv * y1p * y1p - ryv * ryv * x1p * x1p)
        let den = rxv * rxv * y1p * y1p + ryv * ryv * x1p * x1p
        var coef = sqrt(num / max(den, 1e-12))
        if large == sweep { coef = -coef }
        let cxp = coef * rxv * y1p / ryv
        let cyp = coef * -ryv * x1p / rxv
        let cx = cosφ * cxp - sinφ * cyp + (x1 + x2) / 2
        let cy = sinφ * cxp + cosφ * cyp + (y1 + y2) / 2
        func ang(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let sign = ux * vy - uy * vx < 0 ? -1.0 : 1.0
            let n = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            let c = max(-1, min(1, (ux * vx + uy * vy) / max(n, 1e-12)))
            return sign * acos(c)
        }
        let θ1 = ang(1, 0, (x1p - cxp) / rxv, (y1p - cyp) / ryv)
        var Δθ = ang((x1p - cxp) / rxv, (y1p - cyp) / ryv,
                     (-x1p - cxp) / rxv, (-y1p - cyp) / ryv)
        if !sweep && Δθ > 0 { Δθ -= .pi * 2 }
        if sweep && Δθ < 0 { Δθ += .pi * 2 }
        let θ = θ1 + Δθ * u
        let x = rxv * cos(θ), y = ryv * sin(θ)
        return (cx + x * cosφ - y * sinφ, cy + x * sinφ + y * cosφ)
    }

    /// Ride a visible SVG arc. `u == 0` is the Paper rest seat at `restU`.
    public static func alongArc(
        x1: Double, y1: Double, rx: Double, ry: Double,
        deg: Double, large: Bool, sweep: Bool,
        x2: Double, y2: Double,
        restU: Double, swing: Double, u: Double
    ) -> IdleOrbit {
        let wrap = u - u.rounded(.down)
        let q = restU + swing * sin(.pi * 2 * wrap)
        let p = svgArcPoint(x1: x1, y1: y1, rx: rx, ry: ry, deg: deg,
                            large: large, sweep: sweep, x2: x2, y2: y2, u: q)
        return IdleOrbit(x: p.0, y: p.1, front: sin(.pi * 2 * wrap) >= 0)
    }

    private static func look(_ plate: Int, _ t: Double) -> IdlePlatePose {
        // dash 0: the ticks on an orbit track never move. satellite/comet are Kepler-paced,
        // not linear ramps. glow/breathe were hard 1 -- every ring plate's only animation used
        // to be the ring turning -- and now carry the plate's light.
        var p = IdlePlatePose(
            phase: t, breathe: 1 + 0.12 * flicker(t, Double(plate) + 40), ringDeg: 0, dash: 0,
            bodyX: 179, bodyY: 188, lightX: 0, satellite: orbitProgress(t),
            moonYaw: 0, moonPitch: 0, comet: orbitProgress(t, ecc: 0.8),
            glow: 1 + 0.16 * flicker(t, Double(plate)), twinkle: 0)
        p.twinkle = min(max(0.5 + 0.5 * flicker(t, Double(plate) + 80), 0), 1)
        switch plate {
        case 1:
            p.ringDeg = -14
            p.bodyY = 188
        case 2:
            p.bodyX = 179
            p.bodyY = 196
            p.ringDeg = -18
            // lightX used to swing the highlight across the disc once a loop. A light source an
            // astronomical unit away does not swing in eight seconds; the libration carries it.
            p.moonYaw = sin(.pi * 2 * t)
            p.moonPitch = sin(.pi * 4 * t)
        case 3:
            p.ringDeg = -3
            p.bodyY = 128
        case 4:
            p.ringDeg = -18
        case 5:
            p.ringDeg = -22
            p.bodyY = 178
        case 6:
            p.ringDeg = -28
        case 7:
            p.ringDeg = -24
            p.bodyY = 178
        case 8:
            p.bodyX = 140
            p.bodyY = 190
            p.ringDeg = -22
        case 9:
            p.bodyY = 190
            p.ringDeg = 18
        case 10:
            break
        case 11:
            p.bodyX = 560
            p.bodyY = 150
        case 12:
            p.ringDeg = -2
            p.bodyY = 188
        case 13:
            p.ringDeg = -32
        case 14:
            p.bodyX = 179
            p.bodyY = 195
        case 15:
            p.ringDeg = -6
        case 16:
            p.ringDeg = -8
        case 17:
            p.ringDeg = -12
        case 18:
            break
        case 19:
            p.ringDeg = -13
        case 20:
            p.bodyX = 298
            p.bodyY = 195
            p.ringDeg = -12
        case 21:
            p.bodyX = -60
            p.bodyY = 240
        case 22:
            p.ringDeg = -2
            p.bodyY = 188
        case 23:
            p.bodyX = 179
            p.bodyY = 250
            p.ringDeg = -16
            // libration: yaw once a loop, pitch twice, both zero at the rest seat. The pair
            // traces a figure eight, which is the path a real libration draws -- not a rock
            // along one line, and not the old 0...2 pitch that only ever nodded one way.
            p.moonYaw = sin(.pi * 2 * t)
            p.moonPitch = sin(.pi * 4 * t)
        case 24:
            break
        case 25:
            p.ringDeg = -4
        case 26:
            p.bodyX = 250
            p.bodyY = 230
            p.ringDeg = -18
        case 27:
            break
        case 28:
            p.ringDeg = 0
        default:
            break
        }
        return p
    }

}
