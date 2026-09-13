import Foundation

/// Clock-parameterized pose of one idle plate. Separate from SwiftUI so two
/// timestamps can be compared without a simulator. `clock` is on-screen seconds;
/// the catalog loop is 3s, matching `output/fx/render_loops.py`.
public struct IdlePlatePose: Equatable, Sendable {
    /// Loop phase 0..<1 when moving; the hold pose when not.
    public var phase: Double
    public var breathe: Double
    public var ringDeg: Double
    public var dash: Double
    public var bodyX: Double
    public var bodyY: Double
    public var lightX: Double
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

public enum IdlePlateMotion: Sendable {
    public static let loopSeconds: Double = 3

    /// Pose of `plate` at `clock` on-screen seconds. Periods match OrbitField
    /// (halo 26s, precession 37s) — not a 3s GIF wobble. `moving: false`
    /// (Reduce Motion) freezes the hold pose so two clocks compare equal.
    public static func pose(plate: Int, clock: Double, moving: Bool) -> IdlePlatePose {
        let t = moving ? clock : 0
        return look(plate, t)
    }

    public static func samples(plate: Int, clock: Double, moving: Bool) -> [Double] {
        pose(plate: plate, clock: clock, moving: moving).samples
    }

    public static func phase(_ clock: Double) -> Double {
        let p = clock / loopSeconds
        return p - p.rounded(.down)
    }

    private static func look(_ plate: Int, _ t: Double) -> IdlePlatePose {
        let tau = Double.pi * 2
        func wave(_ period: Double, _ ph: Double = 0) -> Double {
            sin(tau * t / period + ph)
        }
        func br(_ amp: Double, _ period: Double = 26, _ ph: Double = 0) -> Double {
            1 + amp * wave(period, ph)
        }
        var p = IdlePlatePose(
            phase: t, breathe: 1, ringDeg: 0, dash: 0,
            bodyX: 179, bodyY: 188, lightX: 0, satellite: 0,
            moonYaw: 0, moonPitch: 0, comet: 0, glow: 1, twinkle: 0)
        p.twinkle = 0.5 + 0.5 * wave(11)
        p.phase = (t / 90).truncatingRemainder(dividingBy: 1)
        if p.phase < 0 { p.phase += 1 }
        switch plate {
        case 1:
            p.breathe = br(0.12, 26)
            p.ringDeg = -14 + 4 * wave(37)
            p.glow = p.breathe
            p.bodyX = 179
            p.bodyY = 188
        case 2:
            p.bodyX = 179
            p.lightX = 10 * wave(26, 0.7)
            p.breathe = br(0.10, 26)
            p.glow = p.breathe
        case 3:
            p.breathe = br(0.12, 26)
            p.ringDeg = -3 + 3 * wave(37)
            p.glow = p.breathe
            p.bodyY = 168
        case 4:
            p.ringDeg = -18 + 6 * wave(37)
            p.breathe = br(0.12, 26)
            p.glow = p.breathe
        case 5:
            p.breathe = br(0.12, 26)
            p.ringDeg = -22 + 3 * wave(37)
            p.glow = p.breathe
        case 6:
            p.dash = t / 26
            p.breathe = br(0.12, 26)
            p.glow = p.breathe
        case 7:
            p.breathe = br(0.12, 26)
            p.ringDeg = -24 + 3 * wave(37)
            p.glow = p.breathe
        case 8:
            p.breathe = br(0.12, 26)
            p.ringDeg = -21 + 3 * wave(37)
            p.glow = p.breathe
        case 9:
            p.dash = t / 26
            p.breathe = br(0.12, 26)
            p.glow = p.breathe
        case 10:
            p.breathe = br(0.12, 26)
            p.glow = br(0.12, 17, 2.1)
        case 11:
            p.breathe = br(0.12, 26)
            p.ringDeg = -8 + 3 * wave(37)
            p.glow = p.breathe
            p.bodyX = 289
            p.bodyY = 96
        case 12:
            p.breathe = br(0.10, 26)
            p.ringDeg = -2 + 3 * wave(37)
            p.glow = p.breathe
        case 14:
            p.breathe = br(0.10, 26)
            p.glow = p.breathe
        case 15:
            p.breathe = br(0.12, 26)
            p.glow = p.breathe
        case 16:
            p.dash = t / 26
            p.breathe = br(0.12, 26)
            p.glow = br(0.12, 26)
        case 20:
            p.breathe = br(0.12, 26)
            p.glow = p.breathe
            p.bodyX = 275
            p.bodyY = 188
        case 21:
            p.breathe = br(0.10, 26)
            p.satellite = -32 + 8 * wave(90)
            p.glow = p.breathe
            p.bodyX = 49
        case 22:
            p.breathe = br(0.12, 26)
            p.ringDeg = -2 + 3 * wave(37)
            p.glow = p.breathe
        case 23:
            p.moonYaw = 2.4 * wave(26)
            p.moonPitch = 1.1 * wave(26, 1.0)
            p.breathe = br(0.25)
            p.glow = p.breathe
            p.bodyX = 179
            p.bodyY = 196
        case 25:
            p.breathe = br(0.35)
            p.glow = br(0.3)
            p.ringDeg = br(0.25)
        case 26:
            p.breathe = br(0.25)
            p.glow = p.breathe
            p.bodyX = 250
            p.bodyY = 200
        case 27:
            p.dash = t
            p.breathe = br(0.4)
            p.glow = p.breathe
        case 28:
            p.breathe = br(0.22)
            p.glow = br(0.2)
            p.ringDeg = 0
        default:
            p.breathe = br(0.22)
            p.glow = p.breathe
        }
        return p
    }
}
