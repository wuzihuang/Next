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

    /// Pose of `plate` at `clock` on-screen seconds. `moving: false` (Reduce Motion)
    /// freezes the hold pose so two clocks compare equal.
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

    private static func look(_ plate: Int, _ t: Double) -> IdlePlatePose {
        let tau = Double.pi * 2
        func br(_ amp: Double, _ k: Double = 1, _ ph: Double = 0) -> Double {
            1 + amp * sin(tau * k * t + ph)
        }
        var p = IdlePlatePose(
            phase: t, breathe: 1, ringDeg: 0, dash: 0,
            bodyX: 179, bodyY: 188, lightX: 0, satellite: 0,
            moonYaw: 0, moonPitch: 0, comet: 0, glow: 1, twinkle: 0)
        p.twinkle = 0.5 + 0.5 * sin(tau * t)
        switch plate {
        case 1:
            p.breathe = br(0.25)
            p.ringDeg = -14
            p.glow = p.breathe
            p.bodyX = 179
            p.bodyY = 188
        case 2:
            p.bodyX = 179 + 3 * sin(tau * t)
            p.lightX = 8 * sin(tau * t + 0.7)
            p.breathe = br(0.3)
            p.glow = p.breathe
        case 3:
            p.breathe = br(0.22)
            p.ringDeg = -3
            p.glow = p.breathe
            p.bodyY = 128
        case 4:
            p.ringDeg = -18 + 6 * sin(tau * t)
            p.breathe = br(0.3)
            p.glow = p.breathe
        case 5:
            p.breathe = br(0.25)
            p.ringDeg = -22
            p.glow = p.breathe
        case 6:
            p.dash = t
            p.breathe = br(0.4, 2)
            p.glow = p.breathe
        case 7:
            p.breathe = br(0.22)
            p.ringDeg = -24
            p.glow = p.breathe
        case 8:
            p.breathe = br(0.25)
            p.ringDeg = -21
            p.glow = p.breathe
        case 9:
            p.dash = t
            p.breathe = br(0.22)
            p.glow = p.breathe
        case 10:
            p.breathe = br(0.4)
            p.glow = br(0.4, 1, 2.1)
        case 11:
            p.breathe = br(0.22)
            p.ringDeg = -8
            p.glow = p.breathe
            p.bodyX = 338
            p.bodyY = 40
        case 12:
            p.breathe = br(0.2)
            p.ringDeg = -2
            p.glow = p.breathe
        case 14:
            p.breathe = br(0.15)
            p.glow = p.breathe
        case 15:
            p.breathe = br(0.3)
            p.glow = p.breathe
        case 16:
            p.dash = t
            p.breathe = br(0.3)
            p.glow = br(0.25)
        case 20:
            p.breathe = br(0.25)
            p.glow = p.breathe
            p.bodyX = 298
            p.bodyY = 195
        case 21:
            p.breathe = br(0.2)
            p.satellite = -32 + 15 * sin(tau * t)
            p.glow = p.breathe
            p.bodyX = 40
        case 22:
            p.breathe = br(0.22)
            p.ringDeg = -2
            p.glow = p.breathe
        case 23:
            p.moonYaw = 2.4 * sin(tau * t)
            p.moonPitch = 1.1 * sin(tau * t + 1.0)
            p.breathe = br(0.25)
            p.glow = p.breathe
            p.bodyX = 214
            p.bodyY = 372
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
