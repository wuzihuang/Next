import Foundation

/// Originkit Glitter Wrap — the THINKING field.
///
/// Clock-stepped particle state. The panel paints the stamps this step emits;
/// tests sample the same structs. Live uses a random seed; tests pass a fixed one.
public struct GlitterWrapRGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public static func hex(_ n: UInt32) -> GlitterWrapRGB {
        GlitterWrapRGB(
            r: Double((n >> 16) & 0xFF),
            g: Double((n >> 8) & 0xFF),
            b: Double(n & 0xFF))
    }
}

public struct GlitterWrapConfig: Equatable, Sendable {
    public var particleCount: Int
    public var color1: GlitterWrapRGB
    public var color2: GlitterWrapRGB
    public var color3: GlitterWrapRGB
    public var speed: Double
    public var density: Double
    public var starSize: Double
    public var focalDepth: Double
    public var turbulence: Double
    public var brightness: Double
    public var glitterIntensity: Double
    public var trailAmount: Double
    public var reverse: Bool

    /// Originkit wrap, retimed to the panel: white / cool gray / lime, not the stock red.
    public static let thinking = GlitterWrapConfig(
        particleCount: 773,
        color1: .hex(0xFFFFFF),
        color2: .hex(0xB0B0BA),
        color3: .hex(0xEFF65A),
        speed: 4,
        density: 77,
        starSize: 18,
        focalDepth: 7,
        turbulence: 0,
        brightness: 100,
        glitterIntensity: 3,
        trailAmount: 67,
        reverse: true)

    public var palette: [GlitterWrapRGB] { [color1, color2, color3] }
}

/// Derived quantities the Originkit `cfg()` closure computes each frame.
public struct GlitterWrapDerived: Equatable, Sendable {
    public var reverse: Bool
    public var density: Double
    public var stepZ: Double
    public var focalDepth: Double
    public var starScale: Double
    public var turbulence: Double
    public var glitter: Double
    public var brightness: Double
    public var trail: Double

    public init(_ c: GlitterWrapConfig) {
        reverse = c.reverse
        density = c.density
        stepZ = c.speed * 0.0008
        focalDepth = c.focalDepth / 100
        starScale = c.starSize * 0.15
        turbulence = c.turbulence * 0.2
        glitter = c.glitterIntensity * 0.1
        brightness = min(1, c.brightness / 100)
        trail = c.trailAmount / 100
    }
}

public struct GlitterWrapStar: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var px: Double?
    public var py: Double?
    public var seed: Double
    public var vmul: Double
    public var colorIdx: Int
    public var flashUntil: Double
    public var nextFlash: Double
}

public struct GlitterWrapStamp: Equatable, Sendable {
    public var sx: Double
    public var sy: Double
    public var px: Double?
    public var py: Double?
    public var r: Double
    public var haloR: Double?
    public var alpha: Double
    public var colorIdx: Int
    public var flashMult: Double
}

public struct GlitterWrapFrame: Equatable, Sendable {
    public var stamps: [GlitterWrapStamp]
    public var trailAlpha: Double
}

public struct GlitterWrapProjection: Equatable, Sendable {
    public var sx: Double
    public var sy: Double
    public var radius: Double
}

/// SplitMix64. `unit()` is `[0, 1)`, the same interval as `Math.random()`.
public struct GlitterWrapRNG: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func unit() -> Double {
        Double(next() >> 11) * 0x1p-53
    }
}

public final class GlitterWrapField {
    public let config: GlitterWrapConfig
    public private(set) var stars: [GlitterWrapStar] = []
    public private(set) var elapsed: Double = 0
    public var width: Double
    public var height: Double
    private var rng: GlitterWrapRNG
    private var derived: GlitterWrapDerived

    public init(config: GlitterWrapConfig = .thinking,
                seed: UInt64,
                width: Double = 358,
                height: Double = 470) {
        self.config = config
        self.rng = GlitterWrapRNG(seed: seed)
        self.width = width
        self.height = height
        self.derived = GlitterWrapDerived(config)
        syncCount()
    }

    /// Flattened star state. Two clocks compare equal only when the field did not step.
    public func samples() -> [Double] {
        stars.flatMap { s in
            [s.x, s.y, s.z, s.vmul, Double(s.colorIdx), s.seed, s.flashUntil, s.nextFlash]
        }
    }

    /// Originkit `dt = clamp(deltaSec, 0.001, 0.1) * 60`.
    public static func frameDt(deltaSec: Double) -> Double {
        max(0.001, min(0.1, deltaSec)) * 60
    }

    /// `keep = pow(min(0.98, max(0, trail)), dt)` with `trail = trailAmount / 100`.
    public static func trailKeep(trailAmount: Double, deltaSec: Double) -> Double {
        let trail = trailAmount / 100
        let dt = frameDt(deltaSec: deltaSec)
        return pow(min(0.98, max(0, trail)), dt)
    }

    public static func trailAlpha(trailAmount: Double, deltaSec: Double) -> Double {
        max(0.02, 1 - trailKeep(trailAmount: trailAmount, deltaSec: deltaSec))
    }

    /// Elliptical falloff so the field dissolves before this slot's rect clip.
    public static func edgeGain(x: Double, y: Double, width: Double, height: Double) -> Double {
        let w = max(1, width), h = max(1, height)
        let nx = (x - w / 2) / (w * 0.54)
        let ny = (y - h / 2) / (h * 0.46)
        return 1 - smoothstep(0.62, 1.08, hypot(nx, ny))
    }

    public static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - edge0) / max(1e-9, edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// Perspective `focalDepth / z`. Reverse motion increases `z`, so radius shrinks.
    public static func project(x: Double, y: Double, z: Double,
                              width: Double, height: Double,
                              focalDepth: Double) -> GlitterWrapProjection {
        let w = max(1, width), h = max(1, height)
        let cx = w / 2, cy = h / 2
        let projScale = min(w, h) * 0.9
        let persp = focalDepth / max(z, 0.0001)
        let sx = cx + x * persp * projScale
        let sy = cy + y * persp * projScale
        return GlitterWrapProjection(sx: sx, sy: sy, radius: hypot(sx - cx, sy - cy))
    }

    /// One Originkit `drawFrame`. `moving: false` freezes the pose (Reduce Motion).
    @discardableResult
    public func step(deltaSec: Double, moving: Bool = true) -> GlitterWrapFrame {
        if !moving {
            return GlitterWrapFrame(stamps: snapshot(scheduleFlash: false), trailAlpha: 0)
        }
        syncCount()
        let d = derived
        let dt = Self.frameDt(deltaSec: deltaSec)
        let w = max(1, width), h = max(1, height)
        let cx = w / 2, cy = h / 2
        let projScale = min(w, h) * 0.9
        var stamps: [GlitterWrapStamp] = []
        stamps.reserveCapacity(stars.count)

        for i in 0..<stars.count {
            var s = stars[i]
            let vz = d.stepZ * s.vmul * dt
            if d.reverse {
                s.z += vz
                if s.z >= 1.0 {
                    resetStar(&s, initial: false)
                    stars[i] = s
                    continue
                }
            } else {
                s.z -= vz
                if s.z <= d.focalDepth {
                    resetStar(&s, initial: false)
                    stars[i] = s
                    continue
                }
            }

            var tx = s.x
            var ty = s.y
            if d.turbulence > 0 {
                let t = elapsed * 1.2 + s.seed
                let amp = d.turbulence * (1 - s.z) * 0.25
                tx += sin(t + s.seed) * amp
                ty += cos(t * 1.13 + s.seed * 0.7) * amp
            }

            let persp = d.focalDepth / max(s.z, 0.0001)
            let sx = cx + tx * persp * projScale
            let sy = cy + ty * persp * projScale

            if !d.reverse, (sx < -20 || sx > w + 20 || sy < -20 || sy > h + 20) {
                resetStar(&s, initial: false)
                stars[i] = s
                continue
            }

            let flashMult = flash(for: &s, schedule: true)
            let stamp = stamp(s, sx: sx, sy: sy, flashMult: flashMult, d: d)
            stamps.append(stamp)
            s.px = sx
            s.py = sy
            stars[i] = s
        }

        elapsed += min(0.1, max(0, deltaSec))
        return GlitterWrapFrame(
            stamps: stamps,
            trailAlpha: Self.trailAlpha(trailAmount: config.trailAmount, deltaSec: deltaSec))
    }

    private func snapshot(scheduleFlash: Bool) -> [GlitterWrapStamp] {
        let d = derived
        let w = max(1, width), h = max(1, height)
        let cx = w / 2, cy = h / 2
        let projScale = min(w, h) * 0.9
        var stamps: [GlitterWrapStamp] = []
        stamps.reserveCapacity(stars.count)
        for i in 0..<stars.count {
            var s = stars[i]
            var tx = s.x
            var ty = s.y
            if d.turbulence > 0 {
                let t = elapsed * 1.2 + s.seed
                let amp = d.turbulence * (1 - s.z) * 0.25
                tx += sin(t + s.seed) * amp
                ty += cos(t * 1.13 + s.seed * 0.7) * amp
            }
            let persp = d.focalDepth / max(s.z, 0.0001)
            let sx = cx + tx * persp * projScale
            let sy = cy + ty * persp * projScale
            let flashMult = flash(for: &s, schedule: scheduleFlash)
            stamps.append(stamp(s, sx: sx, sy: sy, flashMult: flashMult, d: d))
            if scheduleFlash { stars[i] = s }
        }
        return stamps
    }

    private func flash(for s: inout GlitterWrapStar, schedule: Bool) -> Double {
        let glitter = derived.glitter
        guard glitter > 0 else { return 1 }
        if schedule, elapsed >= s.nextFlash, s.flashUntil < elapsed {
            s.flashUntil = elapsed + 0.04 + rng.unit() * 0.07
            s.nextFlash = elapsed + 1 + rng.unit() * 4 * (1 / max(0.0001, glitter))
        }
        return elapsed <= s.flashUntil ? 1 + 2.5 * glitter : 1
    }

    private func stamp(_ s: GlitterWrapStar, sx: Double, sy: Double,
                       flashMult: Double, d: GlitterWrapDerived) -> GlitterWrapStamp {
        let sizePersp = min(2.5, (d.focalDepth / max(s.z, 0.0001)) * 0.6)
        let baseR = max(0.25, d.starScale * (0.4 + sizePersp))
        let maxR = 1 + d.starScale * 2.5
        let gain = Self.edgeGain(x: sx, y: sy, width: width, height: height)
        let bloom = 1 + (1 - gain) * 1.6
        let r = min(baseR * flashMult * bloom, maxR * 2.2)
        let lifeT = d.reverse ? s.z : 1 - s.z
        let fadeIn = d.reverse
            ? min(1, (s.z - d.focalDepth) / (1 - d.focalDepth) / 0.12)
            : 1
        let a = min(1, d.reverse ? 0.85 - lifeT * 0.6 : lifeT * 0.9 + 0.05)
            * fadeIn
            * d.brightness
            * (flashMult > 1 ? 1 : 0.85)
            * gain
        let halo: Double? = flashMult > 1 || gain < 0.85
            ? min(r * 1.4, maxR * 2.4)
            : nil
        return GlitterWrapStamp(
            sx: sx, sy: sy, px: s.px, py: s.py,
            r: r, haloR: halo, alpha: a,
            colorIdx: s.colorIdx, flashMult: flashMult)
    }

    private func syncCount() {
        let count = max(1, Int(config.particleCount))
        if stars.count == count { return }
        if stars.count > count {
            stars.removeLast(stars.count - count)
            return
        }
        while stars.count < count {
            var s = GlitterWrapStar(
                x: 0, y: 0, z: 0, px: nil, py: nil,
                seed: 0, vmul: 1, colorIdx: 0,
                flashUntil: 0, nextFlash: 0)
            resetStar(&s, initial: true)
            stars.append(s)
        }
    }

    private func resetStar(_ s: inout GlitterWrapStar, initial: Bool) {
        let d = derived
        let angle = rng.unit() * Double.pi * 2
        let radius = (0.2 + rng.unit() * 0.8) * (d.density / 15)
        s.x = cos(angle) * radius
        s.y = sin(angle) * radius
        if d.reverse {
            s.z = initial ? d.focalDepth + rng.unit() * (1 - d.focalDepth) : d.focalDepth
        } else {
            s.z = initial ? rng.unit() : 1.0
        }
        s.px = nil
        s.py = nil
        s.seed = rng.unit() * 1000
        s.vmul = 0.6 + rng.unit() * 0.8
        s.colorIdx = Int(rng.unit() * 3)
        s.flashUntil = 0
        s.nextFlash = elapsed + 1 + rng.unit() * 4 * (1 / max(0.0001, d.glitter))
    }
}
