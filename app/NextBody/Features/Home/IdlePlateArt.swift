import SwiftUI

/// Clock-driven draw of one idle plate. Geometry and ramps come from Paper
/// `V-1`. Pose comes from `IdlePlateMotion` so the field the tests sample
/// is the field the panel paints. Moons and pips ride closed ellipses
/// (`pose.satellite`); they do not pulse in place.
///
/// On top of the 1:1 recipe: a second atmosphere bloom, a tight specular,
/// hashed surface grain, and a limb rim — still the same body, just more
/// light on it. The planet does not breathe in size.
enum IdlePlateArt {
    static let board = CGSize(width: 358, height: 470)

    static func draw(plate: Int, pose: IdlePlatePose,
                     charge: Double, chargeKnown: Bool,
                     in ctx: inout GraphicsContext, size: CGSize) {
        _ = charge
        _ = chargeKnown
        let sx = size.width / board.width, sy = size.height / board.height
        let s = min(sx, sy)
        wash(&ctx, size: size, plate: plate)
        galaxy(&ctx, plate: plate, pose: pose, size: size, s: s, sx: sx, sy: sy)
        look(plate, pose: pose, ctx: &ctx, size: size, s: s, sx: sx, sy: sy)
        filmGrain(&ctx, size: size, plate: plate)
        vignette(&ctx, size: size)
    }

    private static func look(_ plate: Int, pose: IdlePlatePose,
                             ctx: inout GraphicsContext, size: CGSize,
                             s: CGFloat, sx: CGFloat, sy: CGFloat) {
        switch plate {
        case 1:
            plate01(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 2:
            plate02(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 3:
            plate03(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 4:
            plate04(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 5:
            plate05(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 6:
            plate06(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 7:
            plate07(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 8:
            plate08(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 9:
            plate09(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 10:
            plate10(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 11:
            plate11(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 12:
            plate12(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 13:
            plate13(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 14:
            plate14(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 15:
            plate15(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 16:
            plate16(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 17:
            plate17(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 18:
            plate18(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 19:
            plate19(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 20:
            plate20(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 21:
            plate21(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 22:
            plate22(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 23:
            plate23(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 24:
            plate24(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 25:
            plate25(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 26:
            plate26(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 27:
            plate27(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        case 28:
            plate28(&ctx, pose: pose, s: s, sx: sx, sy: sy)
        default:
            saturn(&ctx, pose: pose, s: s, sx: sx, sy: sy,
                   cx: 179, cy: 188, r: 74, hx: 150, hy: 160,
                   stops: [(0, 0xF7EFDD), (0.4, 0xDCCBA6), (0.7, 0x8A7A58), (1, 0x1E1A12)],
                   air: 0x6B5B3A, airA: 0.30,
                   ringRX: 126, ringRY: 34, ringDeg: -14,
                   ring: 0xE8D9B0, dust: 0xC9B68C, gap: 8, wide: 0)
            stars(&ctx, pose: pose, s: s, sx: sx, sy: sy, seed: 100, n: 5)
        }
        _ = size
    }

    // MARK: sky

    private static let tints: [Int: UInt32] = [
        1: 0x3A2E1A, 3: 0x1E2E38, 4: 0x16202A, 5: 0x241F14,
        6: 0x141C26, 7: 0x14202E, 8: 0x262216, 9: 0x1E1C16,
        10: 0x101820, 11: 0x18222A, 12: 0x101014, 13: 0x12202E,
        14: 0x14181E, 15: 0x2A0E06, 16: 0x0B1E3F, 17: 0x1A1030,
        18: 0x260A1E, 19: 0x181422, 20: 0x0A1626, 21: 0x0A1830,
        22: 0x201C10, 24: 0x0A1626, 25: 0x200A04, 26: 0x141233,
        27: 0x12161E, 28: 0x101820,
    ]

    private static let galaxyBand: [Int: (Double, Double, Double)] = [
        1: (-22, 120, 1.0), 2: (-22, 235, 1.0), 3: (-16, 300, 1.0),
        4: (-24, 235, 0.8), 5: (-30, 235, 1.0), 6: (35, 190, 0.9),
        7: (-24, 235, 1.0),         8: (-21, 235, 0.22), 9: (38, 215, 0.9),
        10: (-38, 230, 0.40), 11: (-8, 300, 1.0), 12: (-2, 235, 0.55),
        13: (-36, 215, 0.22), 14: (44, 224, 0.6), 15: (-6, 150, 0.7),
        16: (-28, 235, 0.40), 17: (-12, 235, 0.55), 18: (-30, 205, 0.55),
        19: (-14, 235, 0.9), 20: (-20, 235, 1.0), 21: (-10, 235, 0.45),
        22: (-4, 110, 1.0), 23: (-20, 105, 1.1), 24: (8, 235, 0.35),
        25: (-12, 150, 0.35), 26: (-18, 235, 1.0), 27: (-32, 235, 0.6),
        28: (0, 235, 0.9),
    ]

    private static func wash(_ ctx: inout GraphicsContext, size: CGSize, plate: Int) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(NB.panelInk))
        let mid = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
        ctx.fill(Path(ellipseIn: CGRect(x: mid.x - size.width, y: mid.y - size.height,
                                        width: size.width * 2, height: size.height * 2)),
                 with: .radialGradient(
                    Gradient(colors: [Color(hex: 0x0B0B0D), NB.panelInk]),
                    center: mid, startRadius: 0, endRadius: size.width * 0.85))
        if let tint = tints[plate] {
            let r = size.width * 0.55
            ctx.fill(Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(
                        Gradient(colors: [Color(hex: tint, opacity: 0.16), Color(hex: tint, opacity: 0)]),
                        center: mid, startRadius: 0, endRadius: r))
        }
    }

    private static func galaxy(_ ctx: inout GraphicsContext, plate: Int,
                               pose: IdlePlatePose, size: CGSize,
                               s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let band = galaxyBand[plate] ?? (-18, 235, 0.85)
        let deg = band.0 * .pi / 180
        let ca = cos(deg), sa = sin(deg)
        let cy = band.1
        let alpha = band.2
        for i in 0..<36 {
            let n = Double(i + plate * 17 + 1)
            let u = (hash(n, 12.9898) - 0.5) * 560
            let v = (hash(n, 78.233) - 0.5) * 110
            let x = 179 + u * ca - v * sa
            let y = cy + u * sa + v * ca
            guard x > 6, x < 352, y > 8, y < 300 else { continue }
            let near = exp(-0.5 * (v / 64) * (v / 64))
            let k = 1.0 + Double(i % 2)
            let ph = Double(i / 2 % 3) * (.pi * 2 / 3)
            let tw = 0.55 + 0.45 * sin(pose.phase * .pi * 2 * k + ph)
            let r = (0.85 + 0.7 * hash(n, 39.425)) * s
            let col: UInt32 = hash(n, 57.117) > 0.66 ? 0xCFE4FF
                : (hash(n, 57.117) > 0.33 ? 0xFFE9C9 : 0xE8DDFF)
            let a = (0.06 + 0.14 * near) * tw * alpha
            fillDot(&ctx, at: CGPoint(x: x * sx, y: y * sy), r: r, rgb: col, a: a)
        }
        let dust: [(Double, Double, Double, Double)] = [
            (-130, 150, 30, 0.05), (10, 170, 40, 0.06), (140, 140, 28, 0.04),
        ]
        for d in dust {
            let x = 179 + d.0 * ca
            let y = cy + d.0 * sa
            glow(&ctx, at: CGPoint(x: x * sx, y: y * sy),
                 rx: d.1 * s, ry: d.2 * s, rgb: 0x8A8AA8,
                 a: d.3 * alpha, deg: band.0)
        }
        _ = size
    }

    private static func vignette(_ ctx: inout GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color.black.opacity(0), location: 0.52),
                        .init(color: Color.black.opacity(0.28), location: 0.82),
                        .init(color: Color.black.opacity(0.58), location: 1),
                    ]),
                    center: CGPoint(x: size.width / 2, y: size.height * 0.40),
                    startRadius: 0, endRadius: size.width * 0.82))
    }

    /// Paper plate overlays `1YSM69…` / `1ZRG6HM…` — hashed film, not a texture asset.
    private static func filmGrain(_ ctx: inout GraphicsContext, size: CGSize, plate: Int) {
        var rng = PlateRNG(seed: 1700 + plate * 37)
        let sx = size.width / board.width
        let sy = size.height / board.height
        let s = min(sx, sy)
        for _ in 0..<900 {
            let p = CGPoint(x: rng.uniform(0, Double(board.width)) * sx,
                            y: rng.uniform(0, Double(board.height)) * sy)
            let light = rng.next() > 0.50
            fillDot(&ctx, at: p, r: rng.uniform(0.22, 0.55) * s,
                    rgb: light ? 0xF2EEE4 : 0x000000,
                    a: rng.uniform(0.025, 0.07))
        }
    }

    // MARK: planet

    /// Paper `221Z-1` · ball 164 at 97/106, rings −14°, moon 7×7 at 286/214.
    private static func plate01(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 188 * sy)
        let moon = ride(pose, cx: 179, cy: 188, restX: 289.5, restY: 217.5, flatten: 0.28)
        glow(&ctx, at: c, rx: 130 * s, ry: 130 * s, rgb: 0xC9B68C, a: 0.22 * pose.glow)
        glow(&ctx, at: c, rx: 92 * s, ry: 80 * s, rgb: 0x6B5B3A, a: 0.28 * pose.glow)
        riderMoon(&ctx, o: moon, front: false, cx: 179, cy: 188, occlude: 82,
                  s: s, sx: sx, sy: sy, r: 3.5)
        fineRings(&ctx, c: c, deg: -14, s: s, back: true, bands: [
            (136, 34, 14, 0.16, 0xD9C69A),
            (150, 38, 1.6, 0.34, 0xE8D9B0),
            (158, 40, 1.2, 0.22, 0xD9C69A),
            (167, 42.3, 1.0, 0.12, 0xD9C69A),
        ])
        sphere(&ctx, c: c, r: 82 * s, hx: 146 * sx, hy: 149 * sy,
               stops: [(0, 0xFFF8EC), (0.14, 0xF7EFDD), (0.32, 0xE8D9B0),
                       (0.50, 0xDCCBA6), (0.66, 0x8A7A58), (0.82, 0x3A3224),
                       (1, 0x1E1A12)],
               air: 0xC9B68C, airA: 0.18, speckle: 0.10, specA: 0.10, nightA: 0.28,
               limbA: 0)
        ringShadow(&ctx, c: c, r: 82 * s, rx: 150 * s, ry: 38 * s,
                   deg: -14, rgb: 0x050403, a: 0.18)
        fineRings(&ctx, c: c, deg: -14, s: s, back: false, bands: [
            (136, 34, 12, 0.24, 0xE8D9B0),
            (150, 38, 1.7, 0.90, 0xF5EBCD),
            (158, 40, 1.25, 0.55, 0xF5EBCD),
            (167, 42.3, 1.0, 0.32, 0xF5EBCD),
        ])
        riderMoon(&ctx, o: moon, front: true, cx: 179, cy: 188, occlude: 82,
                  s: s, sx: sx, sy: sy, r: 3.5)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (46, 58, 1.25, 0xFFFAEB, 0.78),
            (298, 44, 0.95, 0xFFE9C9, 0.58),
            (328, 238, 1.05, 0xCFE4FF, 0.42),
            (28, 268, 0.85, 0xFFFAEB, 0.36),
            (244, 28, 0.85, 0xFFFAEB, 0.52),
            (118, 36, 1.05, 0xFFE9C9, 0.34),
            (64, 168, 0.70, 0xFFFAEB, 0.30),
            (292, 318, 0.70, 0xCFE4FF, 0.26),
            (196, 52, 0.60, 0xFFFAEB, 0.28),
            (14, 142, 0.65, 0xFFE9C9, 0.32),
        ], flares: [(78, 88, 5.2, 0xFFFCF0, 0.92), (312, 118, 4.0, 0xCFE4FF, 0.70)])
    }

    /// Paper `222S-1` · 320px moon at 19/40, night ramp to ~0x222220, right limb.
    private static func plate02(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let cx = pose.bodyX, cy = 200.0
        let c = CGPoint(x: cx * sx, y: cy * sy)
        let pr = 160 * s
        haloRing(&ctx, at: c, r: 220 * s, rgb: 0xD6E4FF,
                 stops: [(0.70, 0), (0.77, 0.14),
                         (0.86, 0.05), (1, 0)])
        softBall(&ctx, c: c, r: pr, hx: c.x, hy: c.y - 18 * sy, stops: [
            (0, 0xC8C8C0, 0.24),
            (0.38, 0x8A8A84, 0.16),
            (0.68, 0x4A4A48, 0.07),
            (1, 0x070709, 0),
        ])
        softBall(&ctx, c: c, r: pr * 0.88, hx: 108.6 * sx, hy: 116.8 * sy, stops: [
            (0, 0xE8E8E0, 0.26),
            (0.36, 0xB0B0A8, 0.12),
            (0.70, 0x6A6A68, 0.04),
            (1, 0x070709, 0),
        ])
        paperCraters(&ctx, origin: CGPoint(x: 19 * sx, y: 40 * sy),
                     disc: c, r: pr, s: s, sx: sx, sy: sy,
                     shiftX: 0, shiftY: 0,
                     mares: [(28, 58, 132, 96, 0.05), (118, 172, 112, 82, 0.04)],
                     pits: [(85, 80, 40, 0.05), (180, 105, 30, 0.04),
                            (50, 180, 48, 0.04), (140, 215, 34, 0.03),
                            (222, 50, 24, 0.05), (25, 115, 26, 0.03),
                            (95, 145, 18, 0.03), (205, 170, 16, 0.03)])
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: 210, y1: 47, rx: 160, ry: 160, deg: 0,
               large: false, sweep: true, x2: 330, y2: 260,
               width: 7, rgb: 0xFFFFFF, a: 0.18)
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: 220.4, y1: 45.4, rx: 160, ry: 160, deg: 0,
               large: false, sweep: true, x2: 310.1, y2: 291.8,
               width: 2.2, rgb: 0xFFFFFF, a: 0.40)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (40, 30, 1.3, 0xFFFCF0, 0.75), (320, 24, 1.0, 0xFFFCF0, 0.55),
            (344, 150, 1.2, 0xFFFCF0, 0.60), (14, 180, 1.0, 0xFFFCF0, 0.40),
            (70, 380, 1.0, 0xFFFCF0, 0.35), (330, 420, 1.1, 0xFFFCF0, 0.40),
            (296, 392, 0.8, 0xFFFCF0, 0.30), (24, 90, 0.9, 0xFFFCF0, 0.38),
            (150, 18, 0.8, 0xFFFCF0, 0.45), (250, 430, 0.8, 0xFFFCF0, 0.28),
        ], flares: [(58, 96, 5.0, 0xFFFCF0, 0.90), (328, 84, 4.0, 0xFFFCF0, 0.60)])
    }

    /// Paper `223M-1` · 156px ice ball at 101/50, rings −3°.
    private static func plate03(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 128 * sy)
        let moon = ride(pose, cx: 179, cy: 128, restX: 334, restY: 128, flatten: 0.12)
        glow(&ctx, at: CGPoint(x: 179 * sx, y: 128 * sy),
             rx: 110 * s, ry: 110 * s, rgb: 0xC9D6DC, a: 0.22 * pose.glow)
        glow(&ctx, at: CGPoint(x: 179 * sx, y: 50 * sy),
             rx: 110 * s, ry: 90 * s, rgb: 0xF4F8FA, a: 0.10 * pose.glow)
        riderMoon(&ctx, o: moon, front: false, cx: 179, cy: 128, occlude: 78,
                  s: s, sx: sx, sy: sy, r: 3.2, rgb: 0xE8F0F4)
        fineRings(&ctx, c: c, deg: -3, s: s, back: true, bands: [
            (140, 17, 10, 0.14, 0xC9D6DC),
            (155, 19, 1.5, 0.32, 0xC9D6DC),
            (163, 20, 1.15, 0.20, 0xC9D6DC),
            (171, 21, 1.0, 0.12, 0xC9D6DC),
        ])
        sphere(&ctx, c: c, r: 78 * s, hx: 151 * sx, hy: 91 * sy,
               stops: [(0, 0xF8FBFC), (0.16, 0xF0F4F6), (0.38, 0xCFD8DC),
                       (0.60, 0x85939C), (0.80, 0x3D4A52), (1, 0x101418)],
               air: 0x3E5462, airA: 0.22, speckle: 0.08, specA: 0.28, nightA: 0.58)
        paperHighlight(&ctx, at: CGPoint(x: 150 * sx, y: 82 * sy),
                       rx: 18 * s, ry: 10 * s, deg: -22, a: 0.22)
        ringShadow(&ctx, c: c, r: 78 * s, rx: 155 * s, ry: 19 * s,
                   deg: -3, rgb: 0x05080A, a: 0.16)
        fineRings(&ctx, c: c, deg: -3, s: s, back: false, bands: [
            (140, 17, 9, 0.20, 0xE8F0F4),
            (155, 19, 1.6, 0.88, 0xE8F0F4),
            (163, 20, 1.2, 0.50, 0xE8F0F4),
            (171, 21, 1.0, 0.28, 0xE8F0F4),
        ])
        riderMoon(&ctx, o: moon, front: true, cx: 179, cy: 128, occlude: 78,
                  s: s, sx: sx, sy: sy, r: 3.2, rgb: 0xE8F0F4)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (52, 48, 1.2, 0xFFFAEE, 0.50), (312, 36, 1.0, 0xFFFAEE, 0.40),
            (336, 230, 1.1, 0xFFFAEE, 0.35), (26, 270, 1.0, 0xFFFAEE, 0.40),
            (150, 26, 1.2, 0xFFFAEE, 0.45), (270, 290, 1.0, 0xFFFAEE, 0.30),
        ], flares: [])
    }

    /// Paper `224E-1` · seven independent elliptical arcs, no planet.
    private static func plate04(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        glow(&ctx, at: CGPoint(x: 180 * sx, y: 205 * sy),
             rx: 120 * s, ry: 120 * s, rgb: 0xF0F0F5, a: 0.10 * pose.glow)
        glow(&ctx, at: CGPoint(x: 179 * sx, y: 248 * sy),
             rx: 22 * s, ry: 16 * s, rgb: 0x5E7A92, a: 0.08 * pose.glow)
        let pip = ride(pose, cx: 179, cy: 248, restX: 268.9, restY: 171.4, flatten: 0.42)
        riderPip(&ctx, o: pip, front: false, cx: 179, cy: 248, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 1.7, rgb: 0xF5F5FA)
        ctx.drawLayer { inner in
            let pivot = CGPoint(x: 179 * sx, y: 248 * sy)
            inner.translateBy(x: pivot.x, y: pivot.y)
            inner.rotate(by: .degrees(pose.ringDeg + 18))
            inner.translateBy(x: -pivot.x, y: -pivot.y)
            svgArc(&inner, s: s, sx: sx, sy: sy,
                   x1: -83.5, y1: 289.0, rx: 280, ry: 120, deg: -22,
                   large: true, sweep: true, x2: 348.7, y2: 248.9,
                   width: 1.0, rgb: 0xEBEBF0, a: 0.12)
            svgArc(&inner, s: s, sx: sx, sy: sy,
                   x1: -61.1, y1: 258.2, rx: 250, ry: 110, deg: -8,
                   large: true, sweep: true, x2: 279.1, y2: 295.5,
                   width: 1.2, rgb: 0xEBEBF0, a: 0.16)
            svgArc(&inner, s: s, sx: sx, sy: sy,
                   x1: -46.5, y1: 165.1, rx: 230, ry: 55, deg: 10,
                   large: true, sweep: true, x2: 285.0, y2: 271.9,
                   width: 1.0, rgb: 0xEBEBF0, a: 0.14)
            svgArc(&inner, s: s, sx: sx, sy: sy,
                   x1: 9.6, y1: 297.2, rx: 220, ry: 70, deg: -18,
                   large: true, sweep: true, x2: 363.8, y2: 187.5,
                   width: 1.15, rgb: 0xF0F0F5, a: 0.28)
            svgArc(&inner, s: s, sx: sx, sy: sy,
                   x1: 9.1, y1: 266.1, rx: 190, ry: 95, deg: -30,
                   large: true, sweep: true, x2: 138.9, y2: 323.7,
                   width: 1.0, rgb: 0xF0F0F5, a: 0.22)
            svgArc(&inner, s: s, sx: sx, sy: sy,
                   x1: 152.5, y1: 287.7, rx: 140, ry: 60, deg: -35,
                   large: true, sweep: true, x2: 299.5, y2: 146.4,
                   width: 1.35, rgb: 0xF5F5FA, a: 0.48)
            svgArc(&inner, s: s, sx: sx, sy: sy,
                   x1: 171.6, y1: 249.1, rx: 100, ry: 42, deg: -12,
                   large: true, sweep: true, x2: 268.9, y2: 171.4,
                   width: 1.1, rgb: 0xF5F5FA, a: 0.38)
        }
        riderPip(&ctx, o: pip, front: true, cx: 179, cy: 248, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 1.7, rgb: 0xF5F5FA)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (46, 40, 1.2, 0xFFFFFA, 0.50), (320, 60, 1.0, 0xFFFFFA, 0.40),
            (340, 300, 1.1, 0xFFFFFA, 0.35), (24, 330, 1.0, 0xFFFFFA, 0.40),
            (200, 30, 1.1, 0xFFFFFA, 0.45), (90, 120, 1.0, 0xFFFFFA, 0.35),
            (300, 160, 1.2, 0xFFFFFA, 0.40),
        ], flares: [])
    }

    /// Paper `2256-1` · 136px umber ball at 111/110, rings −22°, moon at 88/108.
    private static func plate05(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 178 * sy)
        let moon = ride(pose, cx: 179, cy: 178, restX: 88, restY: 108, flatten: 0.28)
        glow(&ctx, at: c, rx: 110 * s, ry: 110 * s, rgb: 0x9A927E, a: 0.18 * pose.glow)
        if !moon.front, !occulted(moon, cx: 179, cy: 178, r: 68) {
            glow(&ctx, at: CGPoint(x: moon.x * sx, y: moon.y * sy),
                 rx: 13 * s, ry: 13 * s, rgb: 0xE8E2D0, a: 0.12)
            crescent(&ctx, at: CGPoint(x: moon.x * sx, y: moon.y * sy), r: 13 * s,
                     off: CGSize(width: 4.5 * s, height: -2.2 * s), rgb: 0xE8E2D0, a: 0.45)
        }
        fineRings(&ctx, c: c, deg: -22, s: s, back: true, bands: [
            (118, 31, 12, 0.12, 0xB0A892),
            (130, 34, 1.5, 0.30, 0xB0A892),
            (138, 36.1, 1.15, 0.18, 0xB0A892),
            (146, 38.2, 1.0, 0.10, 0xB0A892),
        ])
        sphere(&ctx, c: c, r: 68 * s, hx: 152 * sx, hy: 148 * sy,
               stops: [(0, 0xD0C8B0), (0.22, 0x9D9686), (0.48, 0x645E50),
                       (0.72, 0x3F3A30), (1, 0x0B0A08)],
               air: 0x3A3423, airA: 0.20, speckle: 0.08, specA: 0.26, nightA: 0.62)
        paperHighlight(&ctx, at: CGPoint(x: 152 * sx, y: 136 * sy),
                       rx: 14 * s, ry: 8 * s, deg: -22, a: 0.20)
        ringShadow(&ctx, c: c, r: 68 * s, rx: 130 * s, ry: 34 * s,
                   deg: -22, rgb: 0x080604, a: 0.20)
        fineRings(&ctx, c: c, deg: -22, s: s, back: false, bands: [
            (118, 31, 10, 0.18, 0xD0C8B0),
            (130, 34, 1.6, 0.78, 0xD0C8B0),
            (138, 36.1, 1.2, 0.46, 0xD0C8B0),
            (146, 38.2, 1.0, 0.26, 0xD0C8B0),
        ])
        if moon.front {
            glow(&ctx, at: CGPoint(x: moon.x * sx, y: moon.y * sy),
                 rx: 13 * s, ry: 13 * s, rgb: 0xE8E2D0, a: 0.22)
            crescent(&ctx, at: CGPoint(x: moon.x * sx, y: moon.y * sy), r: 13 * s,
                     off: CGSize(width: 4.5 * s, height: -2.2 * s), rgb: 0xE8E2D0, a: 0.82)
            glow(&ctx, at: CGPoint(x: (moon.x - 6) * sx, y: (moon.y - 4) * sy),
                 rx: 3 * s, ry: 3 * s, rgb: 0xFFFAEB, a: 0.35)
        }
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (44, 52, 1.2, 0xFFFCFA, 0.50), (316, 40, 1.0, 0xFFFCFA, 0.40),
            (338, 210, 1.1, 0xFFFCFA, 0.35), (22, 150, 1.0, 0xFFFCFA, 0.40),
            (120, 30, 1.1, 0xFFFCFA, 0.45), (290, 400, 1.0, 0xFFFCFA, 0.30),
            (60, 390, 1.2, 0xFFFCFA, 0.35),
        ], flares: [])
    }

    /// Paper `225Y-1` · dark 150px ball at 105/120, two dashed circles + two dashed ellipses.
    private static func plate06(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 180 * sx, y: 195 * sy)
        sphere(&ctx, c: c, r: 75 * s, hx: 168 * sx, hy: 171 * sy,
               stops: [(0, 0x3A4048), (0.45, 0x242830), (0.75, 0x181C22),
                       (1, 0x101418)],
               air: 0xE1E1E8, airA: 0.03, speckle: 0.02, specA: 0.02, nightA: 0.28,
               limbA: 0)
        hazeOrb(&ctx, c: CGPoint(x: 179 * sx, y: 205 * sy), r: 36 * s,
                hx: 166 * sx, hy: 189 * sy,
                core: 0xE4ECF4, mid: 0x6A7A88, a: 0.08)
        let crawl = pose.dash * 8 * s
        paperDashCircle(&ctx, c: c, r: 75 * s, width: 1.6 * s,
                        rgb: 0xE1E1E8, a: 0.55, dash: [2 * s, 6 * s], phase: crawl)
        paperDashCircle(&ctx, c: c, r: 62 * s, width: 1.0 * s,
                        rgb: 0xE1E1E8, a: 0.18, dash: [1.5 * s, 7 * s], phase: crawl)
        paperDashEllipse(&ctx, c: c, rx: 190 * s, ry: 52 * s, deg: -28,
                         width: 1.2 * s, rgb: 0xDCDCE4, a: 0.35,
                         dash: [2 * s, 6 * s], phase: crawl)
        paperDashEllipse(&ctx, c: c, rx: 170 * s, ry: 60 * s, deg: 24,
                         width: 1.1 * s, rgb: 0xDCDCE4, a: 0.25,
                         dash: [2 * s, 6 * s], phase: -crawl)
        let pip = ride(pose, cx: 180, cy: 195, restX: 320, restY: 170, flatten: 0.27)
        riderPip(&ctx, o: pip, front: false, cx: 180, cy: 195, occlude: 75,
                 s: s, sx: sx, sy: sy, r: 2.6, rgb: 0xE1E1E8)
        riderPip(&ctx, o: pip, front: true, cx: 180, cy: 195, occlude: 75,
                 s: s, sx: sx, sy: sy, r: 2.6, rgb: 0xE1E1E8)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (50, 44, 1.1, 0xFFFCF2, 0.45), (310, 34, 1.0, 0xFFFCF2, 0.40),
            (336, 260, 1.1, 0xFFFCF2, 0.35), (26, 300, 1.0, 0xFFFCF2, 0.35),
            (240, 26, 1.0, 0xFFFCF2, 0.40),
        ], flares: [])
    }

    /// Paper `226Q-1` · 144px blue-gray ball at 107/106, rings −24°.
    private static func plate07(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 178 * sy)
        let moon = ride(pose, cx: 179, cy: 178, restX: 317, restY: 178, flatten: 0.22)
        glow(&ctx, at: c, rx: 100 * s, ry: 100 * s, rgb: 0xA9C4DC, a: 0.20 * pose.glow)
        riderMoon(&ctx, o: moon, front: false, cx: 179, cy: 178, occlude: 72,
                  s: s, sx: sx, sy: sy, r: 3.2, rgb: 0xC3D9EC)
        fineRings(&ctx, c: c, deg: -24, s: s, back: true, bands: [
            (126, 27, 12, 0.12, 0xA9C4DC),
            (138, 30, 1.5, 0.32, 0xA9C4DC),
            (146, 31.7, 1.15, 0.18, 0xA9C4DC),
            (154, 33.5, 1.0, 0.10, 0xA9C4DC),
        ])
        sphere(&ctx, c: c, r: 72 * s, hx: 150 * sx, hy: 146 * sy,
               stops: [(0, 0xF2F8FC), (0.16, 0xDBE8F2), (0.40, 0xA7BFD0),
                       (0.64, 0x62809A), (0.88, 0x30485C), (1, 0x0C1420)],
               air: 0x2E465C, airA: 0.22, speckle: 0.08, specA: 0.28, nightA: 0.58)
        paperHighlight(&ctx, at: CGPoint(x: 152 * sx, y: 133 * sy),
                       rx: 16 * s, ry: 9 * s, deg: -24, a: 0.22)
        ringShadow(&ctx, c: c, r: 72 * s, rx: 138 * s, ry: 30 * s,
                   deg: -24, rgb: 0x060C14, a: 0.18)
        fineRings(&ctx, c: c, deg: -24, s: s, back: false, bands: [
            (126, 27, 10, 0.20, 0xC3D9EC),
            (138, 30, 1.6, 0.86, 0xC3D9EC),
            (146, 31.7, 1.2, 0.50, 0xC3D9EC),
            (154, 33.5, 1.0, 0.28, 0xC3D9EC),
        ])
        riderMoon(&ctx, o: moon, front: true, cx: 179, cy: 178, occlude: 72,
                  s: s, sx: sx, sy: sy, r: 3.2, rgb: 0xC3D9EC)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (46, 50, 1.2, 0xE6F8FF, 0.50), (316, 34, 1.0, 0xE6F8FF, 0.40),
            (338, 250, 1.1, 0xE6F8FF, 0.35), (24, 300, 1.0, 0xE6F8FF, 0.40),
            (140, 28, 1.1, 0xE6F8FF, 0.45), (70, 380, 1.0, 0xE6F8FF, 0.30),
        ], flares: [])
    }

    /// Paper `227I-1` · 90px warm ball at 95/145 + wide diagonal band. No rings.
    private static func plate08(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: pose.bodyX * sx, y: pose.bodyY * sy)
        bloom(&ctx, at: c, rx: 85 * s, ry: 85 * s, rgb: 0xE4E8F0, a: 0.08)
        paperBlurLine(&ctx, s: s, sx: sx, sy: sy,
                      from: (-30, 351), to: (388, 99), width: 94, rgb: 0xC8CED8, a: 0.04)
        paperBlurLine(&ctx, s: s, sx: sx, sy: sy,
                      from: (-30, 351), to: (388, 99), width: 58, rgb: 0xCED4DE, a: 0.06)
        paperBlurLine(&ctx, s: s, sx: sx, sy: sy,
                      from: (-30, 351), to: (388, 99), width: 30, rgb: 0xD6DCE6, a: 0.08)
        sphere(&ctx, c: c, r: 45 * s,
               hx: 123.8 * sx, hy: 170.2 * sy,
               stops: [(0, 0xA8A498), (0.30, 0x7A7668), (0.60, 0x4A4638),
                       (0.86, 0x242220), (1, 0x141210)],
               air: 0xC8BE9E, airA: 0.02, speckle: 0.02, specA: 0, nightA: 0,
               limbA: 0)
        discWash(&ctx, c: c, r: 45 * s, deg: 148, stops: [
            (0, Color.white.opacity(0.03)),
            (0.34, Color.white.opacity(0)),
            (0.64, Color(hex: 0x18160E, opacity: 0.44)),
            (1, Color(hex: 0x14120C, opacity: 0.84)),
        ])
        paperHighlight(&ctx, at: CGPoint(x: 163 * sx, y: 165.5 * sy),
                       rx: 13 * s, ry: 7.5 * s, deg: -22, a: 0.03)
        paperLine(&ctx, s: s, sx: sx, sy: sy,
                  from: (-30, 333), to: (388, 81), width: 2.2, rgb: 0xE4E8F0, a: 0.14)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (42, 64, 1.3, 0xF0F2F6, 0.60), (312, 46, 1.0, 0xF0F2F6, 0.45),
            (336, 230, 1.1, 0xF0F2F6, 0.40), (28, 150, 1.0, 0xF0F2F6, 0.38),
            (246, 30, 1.2, 0xF0F2F6, 0.50), (120, 40, 1.0, 0xF0F2F6, 0.35),
            (330, 130, 1.0, 0xF0F2F6, 0.30),
        ], flares: [])
    }

    /// Paper `228A-1` · 150px cool ball at 104/115 + fading diagonal.
    private static func plate09(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 190 * sy)
        bloom(&ctx, at: c, rx: 125 * s, ry: 125 * s, rgb: 0xD6DCE8, a: 0.07)
        sphere(&ctx, c: c, r: 75 * s, hx: 194 * sx, hy: 160 * sy,
               stops: [(0, 0xA0A6B0), (0.32, 0x7A828C), (0.62, 0x4A525C),
                       (0.86, 0x2A3038), (1, 0x14181C)],
               air: 0xD6DCE8, airA: 0.03, speckle: 0.02, specA: 0, nightA: 0.12,
               limbA: 0)
        featherRim(&ctx, c: c, r: 75 * s, rgb: 0x070709, inner: 0.78, pad: 1.0)
        paperCraters(&ctx, origin: CGPoint(x: 104 * sx, y: 115 * sy),
                     disc: c, r: 75 * s, s: s, sx: sx, sy: sy,
                     shiftX: 0, shiftY: 0,
                     mares: [(20, 44, 70, 50, 0.06), (64, 78, 56, 40, 0.05),
                             (46, 22, 44, 32, 0.04)],
                     pits: [])
        let soft: [((CGFloat, CGFloat), (CGFloat, CGFloat), Double)] = [
            ((-20, 295), (51.6, 266.2), 0.04),
            ((123.3, 237.4), (194.9, 208.6), 0.07),
            ((266.6, 179.8), (378, 135), 0.12),
        ]
        for seg in soft {
            paperLine(&ctx, s: s, sx: sx, sy: sy,
                      from: seg.0, to: seg.1, width: 6, rgb: 0xB0B8C4, a: seg.2)
        }
        let core: [((CGFloat, CGFloat), (CGFloat, CGFloat), Double)] = [
            ((-20, 295), (51.6, 266.2), 0.08),
            ((51.6, 266.2), (123.3, 237.4), 0.16),
            ((123.3, 237.4), (194.9, 208.6), 0.26),
            ((194.9, 208.6), (266.6, 179.8), 0.38),
            ((266.6, 179.8), (322.3, 157.4), 0.48),
            ((322.3, 157.4), (378, 135), 0.58),
        ]
        for seg in core {
            paperLine(&ctx, s: s, sx: sx, sy: sy,
                      from: seg.0, to: seg.1, width: 1.5, rgb: 0xC0C8D4, a: seg.2)
        }
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (40, 58, 1.2, 0xF0F2F6, 0.50), (318, 44, 1.0, 0xF0F2F6, 0.40),
            (338, 260, 1.0, 0xF0F2F6, 0.35), (24, 330, 1.0, 0xF0F2F6, 0.30),
            (262, 26, 1.1, 0xF0F2F6, 0.45), (90, 28, 1.0, 0xF0F2F6, 0.32),
        ], flares: [])
    }

    /// Paper `2292-1` · dashed blue diagonal from top-left + star at (14, 94).
    private static func plate10(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let soft: [((CGFloat, CGFloat), (CGFloat, CGFloat), Double)] = [
            ((-10, 82), (46.7, 117.4), 0.05),
            ((46.7, 117.4), (122.3, 164.6), 0.10),
            ((122.3, 164.6), (235.7, 235.4), 0.14),
            ((235.7, 235.4), (311.3, 282.6), 0.09),
            ((311.3, 282.6), (368, 318), 0.04),
        ]
        for seg in soft {
            paperLine(&ctx, s: s, sx: sx, sy: sy,
                      from: seg.0, to: seg.1, width: 7, rgb: 0x6090FF, a: seg.2)
        }
        let core: [((CGFloat, CGFloat), (CGFloat, CGFloat), Double)] = [
            ((-10, 82), (46.7, 117.4), 0.16),
            ((46.7, 117.4), (122.3, 164.6), 0.38),
            ((122.3, 164.6), (235.7, 235.4), 0.55),
            ((235.7, 235.4), (311.3, 282.6), 0.32),
            ((311.3, 282.6), (368, 318), 0.12),
        ]
        for seg in core {
            paperDashLine(&ctx, s: s, sx: sx, sy: sy,
                          from: seg.0, to: seg.1, width: 1.6, rgb: 0x96BAFF, a: seg.2,
                          dash: [2, 5], phase: pose.dash * 7)
        }
        let star = CGPoint(x: 14 * sx, y: 94 * sy)
        bloom(&ctx, at: star, rx: 16 * s, ry: 16 * s, rgb: 0x96BAFF, a: 0.28 * pose.glow)
        glow(&ctx, at: star, rx: 6 * s, ry: 6 * s, rgb: 0xF4F8FF, a: 0.70 * pose.glow)
        flare(&ctx, at: star, r: 7 * s, rgb: 0xEBF2FF, a: 0.92 * pose.glow)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (300, 40, 1.0, 0xE6EEFF, 0.40), (110, 30, 1.0, 0xE6EEFF, 0.32),
            (340, 180, 1.0, 0xE6EEFF, 0.30), (230, 22, 1.1, 0xE6EEFF, 0.36),
        ], flares: [])
    }

    /// Paper `22BE-1` · bright diagonal + dashed ellipse 210×110 at −32°. No moon.
    private static func plate13(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        paperBlurLine(&ctx, s: s, sx: sx, sy: sy,
                      from: (-20, 460), to: (378, 50), width: 42, rgb: 0xEBEEF4,
                      a: 0.16 * pose.glow)
        paperBlurLine(&ctx, s: s, sx: sx, sy: sy,
                      from: (-20, 460), to: (378, 50), width: 14, rgb: 0xF0F3F8,
                      a: 0.28 * pose.glow)
        paperDashEllipse(&ctx, c: CGPoint(x: 180 * sx, y: 235 * sy),
                         rx: 210 * s, ry: 110 * s, deg: -32,
                         width: 1.5 * s, rgb: 0xE4E8EE, a: 0.50,
                         dash: [2 * s, 6 * s], phase: pose.dash * 8 * s)
        let pip = ride(pose, cx: 180, cy: 235, restX: 320, restY: 180, flatten: 0.52)
        riderPip(&ctx, o: pip, front: false, cx: 180, cy: 235, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 2.8, rgb: 0xFAFBFD)
        paperLine(&ctx, s: s, sx: sx, sy: sy,
                  from: (-20, 460), to: (378, 50), width: 2.4, rgb: 0xFAFBFD, a: 0.90)
        riderPip(&ctx, o: pip, front: true, cx: 180, cy: 235, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 2.8, rgb: 0xFAFBFD)
        glow(&ctx, at: CGPoint(x: 35 * sx, y: 425 * sy),
             rx: 45 * s, ry: 45 * s, rgb: 0xF8F8FA, a: 0.40 * pose.glow)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (44, 62, 1.2, 0xF0F2F6, 0.50), (316, 40, 1.0, 0xF0F2F6, 0.40),
            (340, 200, 1.0, 0xF0F2F6, 0.35), (26, 170, 1.0, 0xF0F2F6, 0.38),
            (250, 24, 1.1, 0xF0F2F6, 0.45), (120, 36, 1.0, 0xF0F2F6, 0.32),
            (70, 280, 1.0, 0xF0F2F6, 0.30),
        ], flares: [])
    }

    /// Paper `22C6-1` · 56px dim ball at 151/167, dashed r=62 circle, fade line.
    private static func plate14(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        glow(&ctx, at: CGPoint(x: 200 * sx, y: 320 * sy),
             rx: 120 * s, ry: 100 * s, rgb: 0x5EEAD4, a: 0.055 * pose.glow)
        paperDashCircle(&ctx, c: CGPoint(x: 173 * sx, y: 205 * sy), r: 62 * s,
                        width: 1.0 * s, rgb: 0xFFFFFF, a: 0.11 * pose.glow,
                        dash: [1.6 * s, 5 * s], phase: 0)
        paperGradientLine(&ctx, s: s, sx: sx, sy: sy,
                          from: (-20, 400), to: (378, 218), width: 1.0,
                          stops: [(0, 0), (0.22, 0.12), (0.78, 0.12), (1, 0)])
        let c = CGPoint(x: pose.bodyX * sx, y: pose.bodyY * sy)
        let pip = ride(pose, cx: 173, cy: 205, restX: 235, restY: 205, flatten: 1)
        riderPip(&ctx, o: pip, front: false, cx: 173, cy: 205, occlude: 28,
                 s: s, sx: sx, sy: sy, r: 2.4, rgb: 0xE8F4F6)
        glow(&ctx, at: c, rx: 36 * s, ry: 36 * s, rgb: 0xA8BED0, a: 0.10 * pose.glow)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 28 * s, y: c.y - 28 * s,
                                        width: 56 * s, height: 56 * s)),
                 with: .radialGradient(
                    Gradient(colors: [Color(hex: 0x3A4450, opacity: 0.22),
                                      Color(hex: 0x12161C, opacity: 0.12),
                                      Color(hex: 0x12161C, opacity: 0)]),
                    center: CGPoint(x: 168 * sx, y: 182 * sy),
                    startRadius: 0, endRadius: 28 * s))
        riderPip(&ctx, o: pip, front: true, cx: 173, cy: 205, occlude: 28,
                 s: s, sx: sx, sy: sy, r: 2.4, rgb: 0xE8F4F6)
    }

    /// Paper `22DQ-1` · bottom cyan bloom + far circles + left dashed crescent.
    private static func plate16(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        mist(&ctx, at: CGPoint(x: 180 * sx, y: 450 * sy),
             rx: 260 * s, ry: 150 * s, rgb: 0x67E8F9, a: 0.32)
        mist(&ctx, at: CGPoint(x: 205 * sx, y: 445 * sy),
             rx: 95 * s, ry: 60 * s, rgb: 0xCFFAFE, a: 0.22)
        ctx.fill(Path(CGRect(x: 0, y: 300 * sy, width: 358 * sx, height: 170 * sy)),
                 with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: 0x67E8F9, opacity: 0), location: 0),
                        .init(color: Color(hex: 0x67E8F9, opacity: 0.06), location: 0.55),
                        .init(color: Color(hex: 0xCFFAFE, opacity: 0.14), location: 1),
                    ]),
                    startPoint: CGPoint(x: 179 * sx, y: 300 * sy),
                    endPoint: CGPoint(x: 179 * sx, y: 470 * sy)))
        strokeCircle(&ctx, c: CGPoint(x: 900 * sx, y: -100 * sy), r: 796 * s,
                     width: 1.5 * s, rgb: 0xBAE6FD, a: 0.28)
        strokeCircle(&ctx, c: CGPoint(x: 1050 * sx, y: 300 * sy), r: 720 * s,
                     width: 1.0 * s, rgb: 0xBAE6FD, a: 0.10)
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: 110, y1: 232.3, rx: 20, ry: 20, deg: 0,
               large: true, sweep: true, x2: 110, y2: 197.7,
               width: 2, rgb: 0xBAE6FD, a: 0.55,
               marks: [2, 5], markPhase: pose.dash * 7)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (60, 90, 1.2, 0xE2F4FF, 0.60), (290, 60, 1.0, 0xE2F4FF, 0.45),
            (330, 170, 1.1, 0xE2F4FF, 0.40), (200, 120, 1.0, 0xE2F4FF, 0.50),
            (140, 42, 1.2, 0xE2F4FF, 0.40), (36, 270, 1.0, 0xE2F4FF, 0.35),
        ], flares: [])
    }

    /// Paper `22EI-1` · violet bloom + 128×96 ellipse at 18° + pip (294, 210).
    private static func plate17(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        bloom(&ctx, at: CGPoint(x: 180 * sx, y: 260 * sy),
              rx: 125 * s, ry: 115 * s, rgb: 0x6D28D9, a: 0.28)
        bloom(&ctx, at: CGPoint(x: 250 * sx, y: 320 * sy),
              rx: 75 * s, ry: 65 * s, rgb: 0xD774B4, a: 0.18)
        bloom(&ctx, at: CGPoint(x: 185 * sx, y: 270 * sy),
              rx: 75 * s, ry: 65 * s, rgb: 0xA78BFA, a: 0.22)
        bloom(&ctx, at: CGPoint(x: 185 * sx, y: 280 * sy),
              rx: 45 * s, ry: 35 * s, rgb: 0xFFF4E0, a: 0.16)
        paperDashEllipse(&ctx, c: CGPoint(x: 182 * sx, y: 238 * sy),
                         rx: 128 * s, ry: 96 * s, deg: 18,
                         width: 1.2 * s, rgb: 0xC4B5FD, a: 0.38,
                         dash: [], phase: 0)
        paperLine(&ctx, s: s, sx: sx, sy: sy,
                  from: (200, -20), to: (330, 180), width: 1.0, rgb: 0xFFFFFF, a: 0.07)
        paperLine(&ctx, s: s, sx: sx, sy: sy,
                  from: (245, -20), to: (358, 140), width: 1.0, rgb: 0xFFFFFF, a: 0.05)
        let pip = ride(pose, cx: 182, cy: 238, restX: 294, restY: 210, flatten: 0.75)
        riderPip(&ctx, o: pip, front: false, cx: 182, cy: 238, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 3.2, rgb: 0xA78BFA)
        riderPip(&ctx, o: pip, front: true, cx: 182, cy: 238, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 3.2, rgb: 0xA78BFA)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (48, 72, 1.2, 0xF0EBFF, 0.60), (310, 50, 1.0, 0xF0EBFF, 0.45),
            (334, 300, 1.1, 0xF0EBFF, 0.40), (90, 150, 1.0, 0xF0EBFF, 0.50),
            (160, 60, 1.3, 0xF0EBFF, 0.40), (250, 120, 1.0, 0xF0EBFF, 0.45),
            (36, 330, 1.0, 0xF0EBFF, 0.35), (290, 360, 1.2, 0xF0EBFF, 0.30),
        ], flares: [])
    }

    /// Paper `22FA-1` · two magenta blooms + rings at (200, 210) + pip (106, 264).
    private static func plate18(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        glow(&ctx, at: CGPoint(x: 75 * sx, y: 75 * sy),
              rx: 145 * s, ry: 125 * s, rgb: 0xE84393, a: 0.22)
        glow(&ctx, at: CGPoint(x: 310 * sx, y: 420 * sy),
             rx: 145 * s, ry: 125 * s, rgb: 0xD774B4, a: 0.24)
        let ring = CGPoint(x: 200 * sx, y: 210 * sy)
        strokeCircle(&ctx, c: ring, r: 112 * s, width: 1.0 * s, rgb: 0xFFEBF4, a: 0.14)
        strokeCircle(&ctx, c: ring, r: 107 * s, width: 1.2 * s,
                     rgb: 0xFFEBF4, a: 0.34 * pose.glow)
        let pip = ride(pose, cx: 200, cy: 210, restX: 106, restY: 264, flatten: 1)
        riderPip(&ctx, o: pip, front: false, cx: 200, cy: 210, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 3.2, rgb: 0xE84393)
        riderPip(&ctx, o: pip, front: true, cx: 200, cy: 210, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 3.2, rgb: 0xE84393)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (58, 180, 1.2, 0xFFEBF4, 0.55), (300, 90, 1.0, 0xFFEBF4, 0.45),
            (335, 220, 1.1, 0xFFEBF4, 0.40), (150, 70, 1.0, 0xFFEBF4, 0.40),
            (240, 340, 1.0, 0xFFEBF4, 0.35), (70, 330, 1.3, 0x9AE6F0, 0.50),
            (320, 380, 1.1, 0x9AE6F0, 0.40), (180, 150, 1.0, 0x9AE6F0, 0.35),
        ], flares: [])
    }

    /// Paper `22G2-1` · 150px ivory ball at 105/125, thin ring −13°, three color ticks.
    private static func plate19(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 180 * sx, y: 200 * sy)
        glow(&ctx, at: c, rx: 125 * s, ry: 125 * s, rgb: 0xFFF8E0, a: 0.10 * pose.glow)
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: 343.7, y1: 197.2, rx: 168, ry: 48, deg: pose.ringDeg,
               large: false, sweep: false, x2: 16.3, y2: 272.8,
               width: 2.5, rgb: 0xF0DEAA, a: 0.30)
        sphere(&ctx, c: c, r: 75 * s, hx: 162 * sx, hy: 164 * sy,
               stops: [(0, 0xE8DCC4), (0.18, 0xC4B89A), (0.40, 0x8A8068),
                       (0.66, 0x4A4438), (1, 0x1A1810)],
               air: 0xC9C0AC, airA: 0.10, speckle: 0.06, specA: 0.05, nightA: 0.40,
               limbA: 0)
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: 343.7, y1: 197.2, rx: 168, ry: 48, deg: pose.ringDeg,
               large: false, sweep: true, x2: 16.3, y2: 272.8,
               width: 2.0, rgb: 0xF5E6BE, a: 0.55)
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: 344.0, y1: 200.1, rx: 168, ry: 48, deg: pose.ringDeg,
               large: false, sweep: true, x2: 278.8, y2: 253.4,
               width: 3.0, rgb: 0xF472B6, a: 0.90)
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: 262.5, y1: 260.1, rx: 168, ry: 48, deg: pose.ringDeg,
               large: false, sweep: true, x2: 115.6, y2: 293.8,
               width: 3.0, rgb: 0x22D3EE, a: 0.90)
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: 98.0, y1: 294.9, rx: 168, ry: 48, deg: pose.ringDeg,
               large: false, sweep: true, x2: 17.2, y2: 275.5,
               width: 3.0, rgb: 0xFDE047, a: 0.90)
        for (fx, fy, fr, col) in [
            (72.0, 265.0, 9.0, UInt32(0xFFF6DC)),
            (127.0, 88.0, 7.0, UInt32(0xF472B6)),
            (263.0, 128.0, 8.0, UInt32(0xBAF0FA)),
            (318.0, 300.0, 5.5, UInt32(0xFFF6DC)),
        ] {
            flare(&ctx, at: CGPoint(x: fx * sx, y: fy * sy), r: fr * s,
                  rgb: col, a: 0.72 * pose.breathe)
        }
        let pip = ride(pose, cx: 180, cy: 200, restX: 343.7, restY: 197.2, flatten: 0.29)
        riderPip(&ctx, o: pip, front: false, cx: 180, cy: 200, occlude: 75,
                 s: s, sx: sx, sy: sy, r: 2.8, rgb: 0xFFF6DC)
        riderPip(&ctx, o: pip, front: true, cx: 180, cy: 200, occlude: 75,
                 s: s, sx: sx, sy: sy, r: 2.8, rgb: 0xFFF6DC)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (46, 120, 1.2, 0xFFF6DC, 0.55), (310, 60, 1.0, 0xFFF6DC, 0.50),
            (336, 200, 1.1, 0xFFF6DC, 0.40), (200, 46, 1.0, 0xFFF6DC, 0.45),
            (30, 350, 1.0, 0xFFF6DC, 0.35),
        ], flares: [])
    }

    /// Paper `22JY-1` · cyan trail `M 372 96 C …` + static head (366, 92).
    private static func plate24(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        glow(&ctx, at: CGPoint(x: 330 * sx, y: 180 * sy),
             rx: 120 * s, ry: 120 * s, rgb: 0x22D3EE, a: 0.16 * pose.glow)
        let trail: [(CGFloat, UInt32, Double)] = [
            (6, 0x22D3EE, 0.06), (3, 0x22D3EE, 0.12),
            (1.6, 0x38BDF8, 0.42), (1.0, 0xCFFAFE, 0.82),
        ]
        for t in trail {
            paperCubics(&ctx, s: s, sx: sx, sy: sy,
                        p0: (372, 96), c1: (268, 116), c2: (196, 178), p1: (158, 246),
                        c3: (128, 300), c4: (138, 344), p2: (196, 366),
                        width: t.0, rgb: t.1, a: t.2)
        }
        paperCubics(&ctx, s: s, sx: sx, sy: sy,
                    p0: (378, 170), c1: (300, 190), c2: (240, 240), p1: (214, 300),
                    width: 1.2, rgb: 0x93C5FD, a: 0.22,
                    dash: [2, 6], phase: pose.dash * 8)
        let q = pose.comet
        let p = plate24Point(q)
        glow(&ctx, at: CGPoint(x: p.0 * sx, y: p.1 * sy),
             rx: 10 * s, ry: 10 * s, rgb: 0x38BDF8, a: 0.40)
        glow(&ctx, at: CGPoint(x: p.0 * sx, y: p.1 * sy),
             rx: 3.4 * s, ry: 3.4 * s, rgb: 0xEAF6FF, a: 0.88)
        fillDot(&ctx, at: CGPoint(x: p.0 * sx, y: p.1 * sy), r: 2.6 * s, rgb: 0xE0F7FE, a: 0.95)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (60, 70, 1.2, 0xFFFFFF, 0.50), (130, 40, 1.0, 0xFFFFFF, 0.38),
            (40, 210, 1.1, 0xFFFFFF, 0.40), (90, 330, 1.0, 0xFFFFFF, 0.30),
            (260, 420, 1.1, 0xFFFFFF, 0.32), (320, 380, 1.0, 0xFFFFFF, 0.30),
        ], flares: [])
    }

    /// Paper `229U-1` · 860px limb from the right, diagonal lines, no rings.
    private static func plate11(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        paperLine(&ctx, s: s, sx: sx, sy: sy,
                  from: (-30, 327), to: (368, 48), width: 1.5, rgb: 0xBEC3CD, a: 0.18)
        paperLine(&ctx, s: s, sx: sx, sy: sy,
                  from: (-30, 335), to: (368, 56), width: 1.0, rgb: 0xBEC3CD, a: 0.08)
        let c = CGPoint(x: pose.bodyX * sx, y: pose.bodyY * sy)
        sphere(&ctx, c: c, r: 430 * s, hx: 170 * sx, hy: 133 * sy,
               stops: [(0, 0x6A7078), (0.12, 0x3A4048), (0.28, 0x1C2228),
                       (0.50, 0x101418), (0.74, 0x0A0C10), (1, 0x07080A)],
               air: 0xC8CDD6, airA: 0.03, speckle: 0.02, specA: 0.03, nightA: 0.62,
               limbA: 0)
        paperLine(&ctx, s: s, sx: sx, sy: sy,
                  from: (-30, 345), to: (140, 226), width: 1.2, rgb: 0xC8CDD7, a: 0.02)
        paperLine(&ctx, s: s, sx: sx, sy: sy,
                  from: (-30, 327), to: (135, 211), width: 2.0, rgb: 0xDCE1E9, a: 0.18)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (40, 60, 1.3, 0xF0F2F6, 0.55), (120, 34, 1.0, 0xF0F2F6, 0.40),
            (30, 200, 1.0, 0xF0F2F6, 0.35), (90, 120, 1.1, 0xF0F2F6, 0.42),
            (220, 26, 1.0, 0xF0F2F6, 0.38), (52, 300, 1.0, 0xF0F2F6, 0.30),
        ], flares: [])
    }

    /// Paper `22AM-1` · 170px silhouette at 94/103, rings −2°.
    private static func plate12(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 188 * sy)
        let moon = ride(pose, cx: 179, cy: 188, restX: 344, restY: 188, flatten: 0.145)
        glow(&ctx, at: CGPoint(x: 230 * sx, y: 190 * sy),
             rx: 110 * s, ry: 110 * s, rgb: 0x50505A, a: 0.10 * pose.glow)
        riderMoon(&ctx, o: moon, front: false, cx: 179, cy: 188, occlude: 85,
                  s: s, sx: sx, sy: sy, r: 3.0, rgb: 0x9696A0)
        fineRings(&ctx, c: c, deg: -2, s: s, back: true, bands: [
            (152, 22, 10, 0.10, 0x55555E),
            (165, 24, 1.5, 0.28, 0x55555E),
            (173, 25.2, 1.15, 0.16, 0x55555E),
            (181, 26.3, 1.0, 0.10, 0x55555E),
        ])
        sphere(&ctx, c: c, r: 85 * s, hx: 142 * sx, hy: 154 * sy,
               stops: [(0, 0x7A7A86), (0.24, 0x4A4A54), (0.50, 0x2C2C32),
                       (0.74, 0x18181C), (1, 0x0A0A0C)],
               air: 0x1E1E24, airA: 0.28, speckle: 0.06)
        ringShadow(&ctx, c: c, r: 85 * s, rx: 165 * s, ry: 24 * s,
                   deg: -2, rgb: 0x000000, a: 0.22)
        fineRings(&ctx, c: c, deg: -2, s: s, back: false, bands: [
            (152, 22, 8, 0.16, 0x787882),
            (165, 24, 1.6, 0.72, 0x9696A0),
            (173, 25.2, 1.2, 0.42, 0x9696A0),
            (181, 26.3, 1.0, 0.24, 0x9696A0),
        ])
        riderMoon(&ctx, o: moon, front: true, cx: 179, cy: 188, occlude: 85,
                  s: s, sx: sx, sy: sy, r: 3.0, rgb: 0x9696A0)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (46, 66, 1.1, 0xEBEEF2, 0.40), (312, 48, 1.0, 0xEBEEF2, 0.32),
            (334, 150, 1.0, 0xEBEEF2, 0.28), (28, 290, 1.0, 0xEBEEF2, 0.26),
            (240, 28, 1.0, 0xEBEEF2, 0.35),
        ], flares: [])
    }

    /// Paper `22GU-1` · 184px blue ball at 206/103, two far circular arcs.
    private static func plate20(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        bloom(&ctx, at: CGPoint(x: 290 * sx, y: 190 * sy),
              rx: 150 * s, ry: 150 * s, rgb: 0x38BDF8, a: 0.12)
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: -40, y1: 400, rx: 420, ry: 420, deg: 0,
               large: false, sweep: true, x2: 262, y2: 62,
               width: 1.0, rgb: 0xBAE6FD, a: 0.26)
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: -54, y1: 412, rx: 438, ry: 438, deg: 0,
               large: false, sweep: true, x2: 270, y2: 52,
               width: 0.8, rgb: 0xBAE6FD, a: 0.11)
        let c20 = CGPoint(x: pose.bodyX * sx, y: pose.bodyY * sy)
        softBall(&ctx, c: c20, r: 92 * s, hx: c20.x, hy: c20.y, stops: [
            (0, 0x4A6A98, 0.28),
            (0.42, 0x2A4A78, 0.18),
            (0.74, 0x122040, 0.07),
            (1, 0x080E1C, 0),
        ])
        softBall(&ctx, c: c20, r: 78 * s, hx: 246 * sx, hy: 166 * sy, stops: [
            (0, 0xA8C4E0, 0.22),
            (0.40, 0x5A7EA8, 0.10),
            (1, 0x1A2A58, 0),
        ])
        flare(&ctx, at: CGPoint(x: 104 * sx, y: 132 * sy),
              r: 5.2 * s, rgb: 0xF0F8FF, a: 0.70 * pose.twinkle)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (52, 66, 1.3, 0xFFFFFF, 0.62), (120, 40, 1.0, 0xFFFFFF, 0.40),
            (30, 180, 1.1, 0xFFFFFF, 0.45), (90, 330, 1.2, 0xFFFFFF, 0.35),
            (206, 34, 1.0, 0xFFFFFF, 0.50), (26, 260, 1.0, 0xFFFFFF, 0.30),
        ], flares: [])
    }

    /// Paper `22HM-1` · 404px left giant at −262/38, dashed arc, pip at 223/218.
    private static func plate21(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        bloom(&ctx, at: CGPoint(x: 30 * sx, y: 270 * sy),
              rx: 210 * s, ry: 210 * s, rgb: 0x2563EB, a: 0.22 * pose.glow)
        sphere(&ctx, c: CGPoint(x: pose.bodyX * sx, y: pose.bodyY * sy), r: 202 * s,
               hx: 80 * sx, hy: 200 * sy,
               stops: [(0, 0xE8F4FF), (0.16, 0xA8D4F8), (0.36, 0x5B9EF0),
                       (0.58, 0x2F74E0), (0.80, 0x1A4AA8), (1, 0x0A2050)],
               air: 0x3B82F6, airA: 0.18, speckle: 0.03, specA: 0.10, nightA: 0.32,
               limbA: 0)
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: 169, y1: 128, rx: 300, ry: 110, deg: -12,
               large: false, sweep: true, x2: 140, y2: 286,
               width: 1.3, rgb: 0x93C5FD, a: 0.40,
               marks: [2, 6], markPhase: pose.dash * 8)
        let sat = IdlePlateMotion.alongArc(
            x1: 169, y1: 128, rx: 300, ry: 110, deg: -12,
            large: false, sweep: true, x2: 140, y2: 286,
            restU: 0.63, swing: 0.36, u: pose.satellite)
        riderPip(&ctx, o: sat, front: false, cx: 195, cy: 208, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 4, rgb: 0xBAE6FD)
        riderPip(&ctx, o: sat, front: true, cx: 195, cy: 208, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 4, rgb: 0xBAE6FD)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (300, 60, 1.3, 0xFFFFFF, 0.55), (330, 150, 1.0, 0xFFFFFF, 0.40),
            (250, 30, 1.1, 0xFFFFFF, 0.45), (320, 330, 1.2, 0xFFFFFF, 0.35),
            (210, 380, 1.0, 0xFFFFFF, 0.30),
        ], flares: [])
    }

    /// Paper `22IE-1` · 136px ivory ball at 111/118, rings −2°.
    private static func plate22(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 186 * sy)
        let moon = ride(pose, cx: 179, cy: 186, restX: 324, restY: 186, flatten: 0.11)
        glow(&ctx, at: c, rx: 120 * s, ry: 120 * s, rgb: 0xCFC5A2, a: 0.16 * pose.glow)
        riderMoon(&ctx, o: moon, front: false, cx: 179, cy: 186, occlude: 68,
                  s: s, sx: sx, sy: sy, r: 3.0, rgb: 0xE2D8B4)
        fineRings(&ctx, c: c, deg: -2, s: s, back: true, bands: [
            (132, 14.5, 8, 0.12, 0xCFC5A2),
            (145, 16, 1.5, 0.32, 0xCFC5A2),
            (152, 16.8, 1.15, 0.18, 0xCFC5A2),
            (159, 17.5, 1.0, 0.10, 0xCFC5A2),
        ])
        sphere(&ctx, c: c, r: 68 * s, hx: 152 * sx, hy: 156 * sy,
               stops: [(0, 0xF3EFD6), (0.16, 0xE4DCC0), (0.42, 0xB3A882),
                       (0.66, 0x5F5640), (0.90, 0x2A2418), (1, 0x100E08)],
               air: 0x3E3823, airA: 0.18, speckle: 0.08)
        ringShadow(&ctx, c: c, r: 68 * s, rx: 145 * s, ry: 16 * s,
                   deg: -2, rgb: 0x0A0804, a: 0.16)
        fineRings(&ctx, c: c, deg: -2, s: s, back: false, bands: [
            (132, 14.5, 7, 0.18, 0xE2D8B4),
            (145, 16, 1.6, 0.86, 0xE2D8B4),
            (152, 16.8, 1.2, 0.50, 0xE2D8B4),
            (159, 17.5, 1.0, 0.28, 0xE2D8B4),
        ])
        riderMoon(&ctx, o: moon, front: true, cx: 179, cy: 186, occlude: 68,
                  s: s, sx: sx, sy: sy, r: 3.0, rgb: 0xE2D8B4)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (60, 52, 1.3, 0xFFFCF0, 0.70), (150, 32, 1.0, 0xFFE9C9, 0.48),
            (300, 70, 1.2, 0xCFE4FF, 0.52), (330, 168, 1.0, 0xFFFFFF, 0.36),
            (240, 48, 1.1, 0xFFFCF0, 0.42), (36, 148, 0.9, 0xFFFFFF, 0.30),
        ], flares: [(88, 86, 5.0, 0xFFFCF0, 0.88)])
    }

    /// Paper `22KQ-1` · low amber bloom + tiny ring at y≈414, no sphere.
    private static func plate25(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        mist(&ctx, at: CGPoint(x: 179 * sx, y: 313 * sy),
             rx: 120 * s, ry: 65 * s, rgb: 0xE05E10, a: 0.05)
        mist(&ctx, at: CGPoint(x: 179 * sx, y: 298 * sy),
             rx: 50 * s, ry: 20 * s, rgb: 0xF6A41C, a: 0.06)
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: 244, y1: 410, rx: 64, ry: 15, deg: -4,
               large: false, sweep: false, x2: 116, y2: 419,
               width: 1.8, rgb: 0xFFE9B8, a: 0.90)
        let pip = IdlePlateMotion.alongArc(
            x1: 244, y1: 410, rx: 64, ry: 15, deg: -4,
            large: false, sweep: false, x2: 116, y2: 419,
            restU: 0.48, swing: 0.44, u: pose.satellite)
        riderPip(&ctx, o: pip, front: true, cx: 180, cy: 414.5, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 2.6, rgb: 0xFFE9B8)
        riderPip(&ctx, o: pip, front: false, cx: 180, cy: 414.5, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 2.6, rgb: 0xFFE9B8)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (70, 90, 1.1, 0xFFFAF0, 0.45), (290, 60, 1.2, 0xFFFAF0, 0.50),
            (180, 140, 1.0, 0xFFFAF0, 0.35), (320, 200, 1.0, 0xFFFAF0, 0.30),
            (40, 240, 1.0, 0xFFFAF0, 0.30),
        ], flares: [])
    }

    /// Paper `22LI-1` · 160px violet ball at 170/150, lit from the left limb.
    private static func plate26(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        glow(&ctx, at: CGPoint(x: 250 * sx, y: 230 * sy),
             rx: 160 * s, ry: 160 * s, rgb: 0x6D28D9, a: 0.22 * pose.glow)
        sphere(&ctx, c: CGPoint(x: pose.bodyX * sx, y: pose.bodyY * sy), r: 80 * s,
               hx: 196 * sx, hy: 198 * sy,
               stops: [(0, 0x8A72C8), (0.28, 0x4A3288), (0.58, 0x2A1A58),
                       (0.84, 0x120C28), (1, 0x080610)],
               air: 0x6D28D9, airA: 0.10, speckle: 0.04,
               specA: 0.05, nightA: 0.46, limbA: 0)
        glow(&ctx, at: CGPoint(x: 250 * sx, y: 230 * sy),
             rx: 94 * s, ry: 94 * s, rgb: 0xA78BFA, a: 0.08)
        paperHighlight(&ctx, at: CGPoint(x: 199 * sx, y: 188 * sy),
                       rx: 14 * s, ry: 8 * s, deg: 24, a: 0.10)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (42, 66, 1.3, 0xEBE6FF, 0.65), (96, 34, 1.0, 0xEBE6FF, 0.45),
            (160, 80, 1.2, 0xEBE6FF, 0.50), (236, 40, 1.0, 0xEBE6FF, 0.55),
            (310, 64, 1.4, 0xEBE6FF, 0.70), (330, 130, 1.0, 0xEBE6FF, 0.40),
            (60, 150, 1.1, 0xEBE6FF, 0.40), (200, 120, 1.0, 0xEBE6FF, 0.35),
            (120, 200, 0.9, 0xEBE6FF, 0.30),
        ], flares: [(78, 108, 5.4, 0xF0ECFF, 0.85), (322, 190, 4.0, 0xF0ECFF, 0.55)])
    }

    /// Paper `22MA-1` · two dashed far arcs + pip at 150/138.
    private static func plate27(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: -46.9, y1: 368.5, rx: 289, ry: 289, deg: 0,
               large: false, sweep: true, x2: 399.3, y2: 151.8,
               width: 0.8, rgb: 0xBAE6FD, a: 0.16,
               marks: [1.2, 8], markPhase: pose.dash * 8)
        svgArc(&ctx, s: s, sx: sx, sy: sy,
               x1: -30, y1: 370, rx: 272, ry: 272, deg: 0,
               large: false, sweep: true, x2: 390, y2: 166,
               width: 0.9, rgb: 0xBAE6FD, a: 0.40,
               marks: [1.6, 7], markPhase: pose.dash * 8)
        let pip = ride(pose, cx: 241, cy: 394, restX: 150, restY: 138, flatten: 1)
        riderPip(&ctx, o: pip, front: false, cx: 241, cy: 394, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 2.6, rgb: 0xF0FDFF)
        riderPip(&ctx, o: pip, front: true, cx: 241, cy: 394, occlude: 0,
                 s: s, sx: sx, sy: sy, r: 2.6, rgb: 0xF0FDFF)
        glow(&ctx, at: CGPoint(x: pip.x * sx, y: pip.y * sy),
             rx: 16 * s, ry: 16 * s, rgb: 0x38BDF8, a: 0.40 * pose.glow)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (52, 88, 1.2, 0xDCEBFF, 0.50), (120, 46, 1.0, 0xDCEBFF, 0.40),
            (216, 60, 1.3, 0xDCEBFF, 0.60), (312, 44, 1.0, 0xDCEBFF, 0.45),
            (332, 112, 1.1, 0xDCEBFF, 0.35), (36, 180, 1.0, 0xDCEBFF, 0.35),
        ], flares: [])
    }

    /// Paper `22CY-1` · 270px dark ball at 82/188, amber left glow, huge far arc.
    private static func plate15(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        bloom(&ctx, at: CGPoint(x: 320 * sx, y: 270 * sy),
              rx: 130 * s, ry: 130 * s, rgb: 0x1D4ED8, a: 0.05)
        mist(&ctx, at: CGPoint(x: 100 * sx, y: 280 * sy),
             rx: 170 * s, ry: 115 * s, rgb: 0xE05E10, a: 0.08)
        mist(&ctx, at: CGPoint(x: 135 * sx, y: 253 * sy),
             rx: 55 * s, ry: 43 * s, rgb: 0xF6A41C, a: 0.07)
        let c15 = CGPoint(x: 217 * sx, y: 323 * sy)
        sphere(&ctx, c: c15, r: 135 * s,
               hx: 152 * sx, hy: 231 * sy,
               stops: [(0, 0xA84A14), (0.04, 0x6A2E0C), (0.10, 0x2A1810),
                       (0.22, 0x100C0A), (0.55, 0x0A0806), (1, 0x070709)],
               air: 0xE05E10, airA: 0.02, speckle: 0.02, specA: 0, nightA: 0,
               limbA: 0)
        featherRim(&ctx, c: c15, r: 135 * s, rgb: 0x070709, inner: 0.64, pad: 1.0)
        strokeCircle(&ctx, c: CGPoint(x: 650 * sx, y: 458 * sy), r: 685 * s,
                     width: 1.5 * s, rgb: 0xFFEED6, a: 0.30)
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (52, 66, 1.3, 0xFFF4E0, 0.65), (300, 48, 1.1, 0xFFF4E0, 0.50),
            (332, 180, 1.0, 0xFFF4E0, 0.40), (238, 96, 1.2, 0xFFF4E0, 0.45),
            (150, 40, 1.0, 0xFFF4E0, 0.50), (30, 330, 1.1, 0xFFF4E0, 0.35),
        ], flares: [])
    }

    /// Paper `22J6-1` · 600px disc at −121/−50, painted craters, libration.
    /// Lips are typed `PaperLip` SVG elliptical-arc strokes — not circular bowl rims.
    private static func plate23(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let cx = pose.bodyX, cy = pose.bodyY
        let c = CGPoint(x: cx * sx, y: cy * sy)
        let pr = 300 * s
        let ox = pose.moonYaw * 1.4 * sx
        let oy = -pose.moonPitch * 1.8 * sy
        glow(&ctx, at: CGPoint(x: (cx - 40) * sx, y: (cy - 80) * sy),
             rx: 200 * s, ry: 180 * s, rgb: 0x3A3C48, a: 0.10 * pose.glow)
        sphere(&ctx, c: c, r: pr,
               hx: 47 * sx, hy: 82 * sy,
               stops: [(0, 0xF2F0E6), (0.14, 0xC8C6BE), (0.36, 0x8A8880),
                       (0.62, 0x54524C), (0.88, 0x1A1814), (1, 0x080809)],
               air: 0xC0C4D0, airA: 0.03 * pose.glow, speckle: 0.03, seed: 223,
               specA: 0, nightA: 0, limbA: 0)
        discWash(&ctx, c: c, r: pr, deg: 142, stops: [
            (0, Color.white.opacity(0.08)),
            (0.28, Color.white.opacity(0)),
            (0.60, Color.black.opacity(0.32)),
            (1, Color.black.opacity(0.72)),
        ])
        paperCraters(&ctx, origin: .zero, disc: c, r: pr, s: s, sx: sx, sy: sy,
                     shiftX: ox, shiftY: oy,
                     mares: [(120, 150, 190, 150, 0.28), (-30, 230, 170, 140, 0.22)],
                     pits: [])
        paperOvals(&ctx, disc: c, r: pr, sx: sx, sy: sy, shiftX: ox, shiftY: oy,
                   ovals: [
                    (168, 168, 22, 19, 0.28),
                    (248, 128, 14, 12, 0.24),
                    (286, 248, 26, 22, 0.26),
                    (118, 268, 16, 14, 0.24),
                    (198, 220, 10, 9, 0.22),
                    (64, 210, 11, 10, 0.20),
                    (310, 88, 8, 7, 0.20),
                   ])
        ctx.fill(Path(CGRect(x: 0, y: 0, width: 358 * sx, height: 470 * sy)),
                 with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color.black.opacity(0), location: 0.30),
                        .init(color: Color.black.opacity(0.35), location: 0.55),
                        .init(color: Color.black.opacity(0.72), location: 0.85),
                    ]),
                    startPoint: CGPoint(x: 179 * sx, y: 0),
                    endPoint: CGPoint(x: 179 * sx, y: 470 * sy)))
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (40, 36, 1.1, 0xFFFCF0, 0.40), (300, 28, 0.9, 0xCFE4FF, 0.36),
            (330, 70, 1.0, 0xFFFCF0, 0.32), (18, 90, 0.8, 0xFFE9C9, 0.28),
            (250, 48, 0.85, 0xFFFCF0, 0.30), (88, 22, 0.75, 0xCFE4FF, 0.26),
        ], flares: [(58, 54, 3.6, 0xFFFCF0, 0.55)])
    }

    /// Paper `22N2-1` · 160px ball at 99/108, edge-on rings on y=188.
    private static func plate28(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 188 * sy)
        bloom(&ctx, at: CGPoint(x: 180 * sx, y: 203 * sy),
              rx: 160 * s, ry: 95 * s, rgb: 0x67E8F9, a: 0.14)
        fineRings(&ctx, c: c, deg: 0, s: s, back: true, bands: [
            (162, 5, 1.6, 0.22, 0xC9D8E4),
            (166, 6.5, 1.2, 0.14, 0xC9D8E4),
            (170, 9, 1.0, 0.08, 0xC9D8E4),
        ])
        sphere(&ctx, c: c, r: 80 * s, hx: 150 * sx, hy: 150 * sy,
               stops: [(0, 0xC8D2D8), (0.16, 0xA8B4BC), (0.42, 0x7A8A94),
                       (0.66, 0x3A4A54), (0.90, 0x1A2430), (1, 0x0C1218)],
               air: 0x7FA8C8, airA: 0.08, speckle: 0.03, specA: 0, nightA: 0,
               limbA: 0)
        discWash(&ctx, c: c, r: 80 * s, deg: 148, stops: [
            (0, Color.white.opacity(0.16)),
            (0.36, Color.white.opacity(0)),
            (0.66, Color(hex: 0x0A1016, opacity: 0.18)),
            (1, Color(hex: 0x080C10, opacity: 0.62)),
        ])
        ctx.drawLayer { inner in
            inner.clip(to: Path(ellipseIn: CGRect(x: c.x - 80 * s, y: c.y - 80 * s,
                                                  width: 160 * s, height: 160 * s)))
            glow(&inner, at: CGPoint(x: c.x, y: c.y + 1 * s),
                 rx: 72 * s, ry: 7 * s, rgb: 0xEAF2F8, a: 0.32)
        }
        fineRings(&ctx, c: c, deg: 0, s: s, back: false, bands: [
            (162, 5, 1.7, 0.90, 0xEAF2F8),
            (166, 6.5, 1.25, 0.50, 0xEAF2F8),
            (170, 9, 1.0, 0.28, 0xEAF2F8),
        ])
        paperStars(&ctx, pose: pose, s: s, sx: sx, sy: sy, dots: [
            (44, 62, 1.3, 0xE2F0FF, 0.60), (110, 36, 1.0, 0xE2F0FF, 0.42),
            (180, 74, 1.2, 0xE2F0FF, 0.50), (268, 42, 1.0, 0xE2F0FF, 0.55),
            (326, 86, 1.4, 0xE2F0FF, 0.65), (64, 132, 1.0, 0xE2F0FF, 0.35),
            (332, 160, 1.1, 0xE2F0FF, 0.40),
        ], flares: [])
    }

    private static func ride(_ pose: IdlePlatePose,
                             cx: Double, cy: Double,
                             restX: Double, restY: Double,
                             flatten: Double) -> IdleOrbit {
        IdlePlateMotion.around(cx: cx, cy: cy,
                               restX: restX, restY: restY,
                               flatten: flatten, u: pose.satellite)
    }

    private static func occulted(_ o: IdleOrbit, cx: Double, cy: Double, r: Double) -> Bool {
        guard !o.front else { return false }
        let dx = o.x - cx, dy = o.y - cy
        return dx * dx + dy * dy < r * r
    }

    private static func paintMoon(_ ctx: inout GraphicsContext, o: IdleOrbit,
                                  s: CGFloat, sx: CGFloat, sy: CGFloat,
                                  r: CGFloat = 3.5, rgb: UInt32 = 0xE8D9B0) {
        let p = CGPoint(x: o.x * sx, y: o.y * sy)
        let k = o.front ? 1.0 : 0.55
        glow(&ctx, at: p, rx: r * 2.6 * s, ry: r * 2.6 * s, rgb: rgb, a: 0.30 * k)
        sphere(&ctx, c: p, r: r * s,
               hx: p.x - 0.32 * r * s, hy: p.y - 0.36 * r * s,
               stops: [(0, 0xFFFCF0), (0.55, rgb), (1, 0x8A7A58)],
               air: rgb, airA: 0.12 * k, speckle: 0)
    }

    private static func paintPip(_ ctx: inout GraphicsContext, o: IdleOrbit,
                                 s: CGFloat, sx: CGFloat, sy: CGFloat,
                                 r: CGFloat, rgb: UInt32, a: Double = 0.92) {
        let p = CGPoint(x: o.x * sx, y: o.y * sy)
        let k = o.front ? 1.0 : 0.50
        paperPip(&ctx, at: p, r: r * s, rgb: rgb, a: a * k)
    }

    private static func riderMoon(_ ctx: inout GraphicsContext, o: IdleOrbit,
                                  front: Bool, cx: Double, cy: Double, occlude: Double,
                                  s: CGFloat, sx: CGFloat, sy: CGFloat,
                                  r: CGFloat = 3.5, rgb: UInt32 = 0xE8D9B0) {
        guard o.front == front else { return }
        if !front, occulted(o, cx: cx, cy: cy, r: occlude) { return }
        paintMoon(&ctx, o: o, s: s, sx: sx, sy: sy, r: r, rgb: rgb)
    }

    private static func riderPip(_ ctx: inout GraphicsContext, o: IdleOrbit,
                                 front: Bool, cx: Double, cy: Double, occlude: Double,
                                 s: CGFloat, sx: CGFloat, sy: CGFloat,
                                 r: CGFloat, rgb: UInt32, a: Double = 0.92) {
        guard o.front == front else { return }
        if !front, occulted(o, cx: cx, cy: cy, r: occlude) { return }
        paintPip(&ctx, o: o, s: s, sx: sx, sy: sy, r: r, rgb: rgb, a: a)
    }

    private static func saturn(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                               s: CGFloat, sx: CGFloat, sy: CGFloat,
                               cx: Double, cy: Double, r: Double,
                               hx: Double, hy: Double,
                               stops: [(CGFloat, UInt32)],
                               air: UInt32, airA: Double,
                               ringRX: Double, ringRY: Double, ringDeg: Double,
                               ring: UInt32, dust: UInt32, gap: Double, wide: Double,
                               moon: CGPoint? = nil, dimRing: Bool = false) {
        let c = CGPoint(x: cx * sx, y: cy * sy)
        let pr = r * s
        glow(&ctx, at: c, rx: pr * 2.15, ry: pr * 1.85, rgb: air, a: airA * pose.glow * 1.15)
        glow(&ctx, at: c, rx: pr * 1.45, ry: pr * 1.25, rgb: air, a: airA * 0.55 * pose.glow)
        if ringRX > 4 {
            rings(&ctx, c: c, rx: ringRX * s, ry: ringRY * s, deg: ringDeg,
                  pose: pose, rgb: ring, dust: dust, gap: gap * s, wide: wide * s,
                  dim: dimRing, back: true)
        }
        sphere(&ctx, c: c, r: pr, hx: hx * sx, hy: hy * sy, stops: stops,
               air: air, airA: airA * 0.35)
        if ringRX > 4 {
            ringShadow(&ctx, c: c, r: pr, rx: ringRX * s, ry: ringRY * s,
                       deg: ringDeg, rgb: 0x050403, a: dimRing ? 0.16 : 0.22)
            rings(&ctx, c: c, rx: ringRX * s, ry: ringRY * s, deg: ringDeg,
                  pose: pose, rgb: ring, dust: dust, gap: gap * s, wide: wide * s,
                  dim: dimRing, back: false)
        }
        if let moon {
            glow(&ctx, at: moon, rx: 8 * s, ry: 8 * s, rgb: 0xE8D9B0, a: 0.28 * pose.glow)
            sphere(&ctx, c: moon, r: 3.6 * s, hx: moon.x - 1.2 * s, hy: moon.y - 1.4 * s,
                   stops: [(0, 0xFFF8EC), (0.55, 0xE8D9B0), (1, 0x8A7A58)],
                   air: 0xE8D9B0, airA: 0.10)
        }
    }

    private static func sphere(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                               hx: CGFloat, hy: CGFloat,
                               stops: [(CGFloat, UInt32)],
                               air: UInt32, airA: Double,
                               speckle: Double = 0.12, seed: Int = 0,
                               specA: Double = 0.36,
                               nightA: Double = 0.68,
                               rim: (UInt32, Double)? = nil,
                               limbA: Double = 0.10) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        let disc = Path(ellipseIn: rect)
        ctx.fill(disc, with: .color(Color(hex: stops.last?.1 ?? 0x0A0A0C)))
        let key = CGPoint(x: hx, y: hy)
        ctx.fill(disc, with: .radialGradient(
            Gradient(stops: stops.map { .init(color: Color(hex: $0.1), location: $0.0) }),
            center: key, startRadius: 0, endRadius: r * 1.38))
        let night = CGPoint(x: c.x * 2 - key.x, y: c.y * 2 - key.y)
        ctx.fill(disc, with: .radialGradient(
            Gradient(colors: [Color(hex: 0x050508, opacity: 0),
                              Color(hex: 0x050508, opacity: nightA * 0.28),
                              Color(hex: 0x050508, opacity: nightA)]),
            center: night, startRadius: r * 0.12, endRadius: r * 1.45))
        ctx.fill(disc, with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0), Color.black.opacity(nightA * 0.28)]),
            center: c, startRadius: r * 0.62, endRadius: r * 1.02))
        let spec = CGPoint(x: c.x + (key.x - c.x) * 0.42, y: c.y + (key.y - c.y) * 0.42)
        if specA > 0.02 {
            ctx.fill(Path(ellipseIn: CGRect(x: spec.x - r * 0.22, y: spec.y - r * 0.13,
                                            width: r * 0.44, height: r * 0.26)),
                     with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(specA), Color.white.opacity(0)]),
                        center: spec, startRadius: 0, endRadius: r * 0.24))
        }
        if speckle > 0.02 {
            grain(&ctx, c: c, r: r, amount: speckle, seed: seed)
        }
        if let rim {
            ctx.stroke(disc, with: .color(Color(hex: rim.0, opacity: rim.1 * 0.55)),
                       lineWidth: max(1.2, r * 0.035))
            glow(&ctx, at: CGPoint(x: c.x + r * 0.55, y: c.y - r * 0.15),
                 rx: r * 0.55, ry: r * 0.7, rgb: rim.0, a: rim.1 * 0.18)
        } else if limbA > 0.01 {
            ctx.stroke(disc, with: .color(Color.white.opacity(limbA)), lineWidth: 1)
        }
        glow(&ctx, at: c, rx: r * 1.12, ry: r * 1.12, rgb: air, a: airA * 0.45)
    }

    private static func grain(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                              amount: Double, seed: Int) {
        ctx.drawLayer { inner in
            inner.clip(to: Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                  width: r * 2, height: r * 2)))
            let n = amount > 0.4 ? 48 : 28
            for i in 0..<n {
                let k = Double(seed * 13 + i + 1)
                let ang = hash(k, 12.9898) * .pi * 2
                let rad = (0.18 + 0.72 * hash(k, 78.233)) * r
                let p = CGPoint(x: c.x + cos(ang) * rad, y: c.y + sin(ang) * rad)
                let rr = (0.9 + 2.4 * hash(k, 39.425)) * (r / 82)
                let dark = hash(k, 57.117) > 0.45
                inner.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr,
                                                  width: rr * 2, height: rr * 2)),
                           with: .color(Color.white.opacity(dark ? 0 : 0.07 * amount)
                                        .opacity(dark ? 0 : 1)))
                if dark {
                    inner.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr,
                                                      width: rr * 2, height: rr * 2)),
                               with: .color(Color.black.opacity(0.16 * amount)))
                }
            }
        }
    }

    private static func rings(_ ctx: inout GraphicsContext, c: CGPoint,
                              rx: CGFloat, ry: CGFloat, deg: Double,
                              pose: IdlePlatePose, rgb: UInt32, dust: UInt32,
                              gap: CGFloat, wide: CGFloat, dim: Bool,
                              back: Bool? = nil) {
        _ = pose
        let a = deg * .pi / 180
        let halves: [Bool] = back.map { [$0] } ?? [true, false]
        for isBack in halves {
            if wide > 1 {
                strokeEllipse(&ctx, c: c, rx: rx, ry: ry, rot: a, back: isBack,
                              width: wide, rgb: dust,
                              a: (isBack ? 0.16 : 0.28) * (dim ? 0.45 : 1))
            }
            let lines: [(CGFloat, CGFloat, Double)] = gap > 1
                ? [(0, dim ? 1.4 : 1.7, dim ? (isBack ? 0.30 : 0.70) : (isBack ? 0.34 : 0.90)),
                   (gap, dim ? 1.1 : 1.25, dim ? (isBack ? 0.20 : 0.42) : (isBack ? 0.22 : 0.55)),
                   (gap * 2, 1.0, dim ? (isBack ? 0.12 : 0.25) : (isBack ? 0.12 : 0.32))]
                : [(0, 1.6, isBack ? 0.30 : 0.42)]
            for (g, w, al) in lines {
                let scale = 1 + g / max(rx, 1)
                strokeEllipse(&ctx, c: c, rx: rx + g, ry: ry * scale, rot: a,
                              back: isBack, width: w, rgb: rgb, a: al)
            }
            if !isBack, !dim {
                strokeEllipse(&ctx, c: c, rx: rx + 4, ry: ry + 1, rot: a, back: false,
                              width: 7, rgb: rgb, a: 0.08)
            }
        }
    }

    private static func fineRings(_ ctx: inout GraphicsContext, c: CGPoint,
                                  deg: Double, s: CGFloat, back: Bool,
                                  bands: [(CGFloat, CGFloat, CGFloat, Double, UInt32)]) {
        let rot = deg * .pi / 180
        for b in bands {
            strokeEllipse(&ctx, c: c, rx: b.0 * s, ry: b.1 * s, rot: rot,
                          back: back, width: max(0.7, b.2 * s), rgb: b.4, a: b.3)
        }
    }

    private static func paperStars(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                   s: CGFloat, sx: CGFloat, sy: CGFloat,
                                   dots: [(Double, Double, Double, UInt32, Double)],
                                   flares: [(Double, Double, Double, UInt32, Double)]) {
        for d in dots {
            let tw = 0.72 + 0.28 * sin(pose.phase * .pi * 2 + d.0 * 0.03)
            fillDot(&ctx, at: CGPoint(x: d.0 * sx, y: d.1 * sy),
                    r: d.2 * s, rgb: d.3, a: d.4 * tw)
        }
        for f in flares {
            let tw = 0.70 + 0.30 * sin(pose.phase * .pi * 4 + f.1 * 0.02)
            flare(&ctx, at: CGPoint(x: f.0 * sx, y: f.1 * sy),
                  r: f.2 * s, rgb: f.3, a: f.4 * tw)
        }
    }

    /// Paper crater highlight: an SVG elliptical-arc stroke, not a circular rim.
    private struct PaperLip {
        var x1, y1, rx, ry, x2, y2: Double
        var width: CGFloat
        var a: Double
    }

    /// Dissolve a hard disc edge into ink so a Paper soft moon does not read as a cut-out.
    private static func featherRim(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                                   rgb: UInt32 = 0x070709,
                                   inner: CGFloat = 0.86,
                                   pad: CGFloat = 1.12) {
        let outer = r * pad
        guard outer > 0, inner < 1 else { return }
        let start = min(0.98, (r * inner) / outer)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - outer, y: c.y - outer,
                                        width: outer * 2, height: outer * 2)),
                 with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: rgb, opacity: 0), location: start),
                        .init(color: Color(hex: rgb, opacity: 0.42),
                              location: start + (1 - start) * 0.42),
                        .init(color: Color(hex: rgb, opacity: 0.88),
                              location: start + (1 - start) * 0.80),
                        .init(color: Color(hex: rgb, opacity: 1), location: 1),
                    ]),
                    center: c, startRadius: 0, endRadius: outer))
    }

    private static func discWash(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                                 deg: Double, stops: [(CGFloat, Color)]) {
        ctx.drawLayer { inner in
            let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                              width: r * 2, height: r * 2))
            inner.clip(to: disc)
            let rad = deg * .pi / 180
            let vx = sin(rad), vy = -cos(rad)
            inner.fill(disc, with: .linearGradient(
                Gradient(stops: stops.map { .init(color: $0.1, location: $0.0) }),
                startPoint: CGPoint(x: c.x - vx * r, y: c.y - vy * r),
                endPoint: CGPoint(x: c.x + vx * r, y: c.y + vy * r)))
        }
    }

    private static func paperOvals(_ ctx: inout GraphicsContext,
                                   disc: CGPoint, r: CGFloat,
                                   sx: CGFloat, sy: CGFloat,
                                   shiftX: CGFloat, shiftY: CGFloat,
                                   ovals: [(Double, Double, Double, Double, Double)]) {
        ctx.drawLayer { inner in
            inner.clip(to: Path(ellipseIn: CGRect(x: disc.x - r, y: disc.y - r,
                                                  width: r * 2, height: r * 2)))
            for o in ovals {
                let rect = CGRect(x: (o.0 - o.2) * sx + shiftX,
                                  y: (o.1 - o.3) * sy + shiftY,
                                  width: o.2 * 2 * sx, height: o.3 * 2 * sy)
                inner.fill(Path(ellipseIn: rect),
                           with: .color(Color.black.opacity(o.4)))
            }
        }
    }

    private static func paperLips(_ ctx: inout GraphicsContext,
                                  s: CGFloat, sx: CGFloat, sy: CGFloat,
                                  shiftX: CGFloat, shiftY: CGFloat,
                                  lips: [PaperLip]) {
        for lip in lips {
            svgArc(&ctx, s: s, sx: sx, sy: sy,
                   x1: lip.x1 + Double(shiftX / sx),
                   y1: lip.y1 + Double(shiftY / sy),
                   rx: lip.rx, ry: lip.ry, deg: 0,
                   large: false, sweep: true,
                   x2: lip.x2 + Double(shiftX / sx),
                   y2: lip.y2 + Double(shiftY / sy),
                   width: lip.width, rgb: 0xFFFAF0, a: lip.a)
        }
    }

    private static func paperCraters(_ ctx: inout GraphicsContext,
                                     origin: CGPoint, disc: CGPoint, r: CGFloat,
                                     s: CGFloat, sx: CGFloat, sy: CGFloat,
                                     shiftX: CGFloat, shiftY: CGFloat,
                                     mares: [(Double, Double, Double, Double, Double)],
                                     pits: [(Double, Double, Double, Double)]) {
        _ = s
        ctx.drawLayer { inner in
            inner.clip(to: Path(ellipseIn: CGRect(x: disc.x - r, y: disc.y - r,
                                                  width: r * 2, height: r * 2)))
            for m in mares {
                let rect = CGRect(x: origin.x + m.0 * sx + shiftX,
                                  y: origin.y + m.1 * sy + shiftY,
                                  width: m.2 * sx, height: m.3 * sy)
                let center = CGPoint(x: rect.midX, y: rect.midY)
                inner.fill(Path(ellipseIn: rect),
                           with: .radialGradient(
                            Gradient(colors: [
                                Color.black.opacity(m.4),
                                Color.black.opacity(m.4 * 0.35),
                                Color.black.opacity(0),
                            ]),
                            center: center,
                            startRadius: 0,
                            endRadius: max(rect.width, rect.height) * 0.55))
            }
            for p in pits {
                let rr = p.2 * sx * 0.5
                let c = CGPoint(x: origin.x + p.0 * sx + shiftX,
                                y: origin.y + p.1 * sy + shiftY)
                let bowl = CGRect(x: c.x - rr, y: c.y - rr * 0.86,
                                  width: rr * 2, height: rr * 1.72)
                inner.fill(Path(ellipseIn: bowl),
                           with: .radialGradient(
                            Gradient(colors: [
                                Color.black.opacity(p.3),
                                Color.black.opacity(p.3 * 0.45),
                                Color.black.opacity(0),
                            ]),
                            center: c, startRadius: 0, endRadius: rr * 1.15))
            }
        }
    }

    private static func ringShadow(_ ctx: inout GraphicsContext, c: CGPoint,
                                   r: CGFloat, rx: CGFloat, ry: CGFloat,
                                   deg: Double, rgb: UInt32, a: Double) {
        ctx.drawLayer { inner in
            inner.clip(to: Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                  width: r * 2, height: r * 2)))
            strokeEllipse(&inner, c: c, rx: min(rx, r * 0.98), ry: max(3, ry * 0.55),
                          rot: deg * .pi / 180, back: false, width: 5,
                          rgb: rgb, a: a)
        }
    }

    // MARK: moon

    private struct MoonFeat {
        var lon, lat, size, depth: Double
        var mare: Bool
    }

    private static let moonClose: [MoonFeat] = {
        var rng = PlateRNG(seed: 223)
        var feats: [MoonFeat] = []
        for _ in 0..<3 {
            feats.append(MoonFeat(lon: rng.uniform(-1.1, 1.1), lat: rng.uniform(-0.55, 0.85),
                                  size: rng.uniform(0.22, 0.33), depth: rng.uniform(0.26, 0.36),
                                  mare: true))
        }
        for i in 0..<22 {
            let big = i < 6
            feats.append(MoonFeat(lon: rng.uniform(-1.3, 1.3), lat: rng.uniform(-0.85, 1.1),
                                  size: big ? rng.uniform(0.08, 0.13) : rng.uniform(0.04, 0.075),
                                  depth: big ? rng.uniform(0.45, 0.6) : rng.uniform(0.34, 0.52),
                                  mare: false))
        }
        return feats
    }()

    private static func moon(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                             s: CGFloat, sx: CGFloat, sy: CGFloat,
                             cx: Double, cy: Double, r: Double,
                             hx: Double, hy: Double, close: Bool, seed: Int) {
        let c = CGPoint(x: cx * sx, y: cy * sy)
        let pr = r * s
        glow(&ctx, at: CGPoint(x: (cx - 40) * sx, y: (cy - 60) * sy),
             rx: pr * 1.15, ry: pr * 1.05, rgb: 0x3A3C48, a: 0.12 * pose.glow)
        glow(&ctx, at: c, rx: pr * 1.08, ry: pr * 1.08, rgb: 0x8A8AA8, a: 0.08 * pose.glow)
        let stops: [(CGFloat, UInt32)] = close
            ? [(0, 0x0A0A0A), (0.28, 0x2C2A26), (0.52, 0x6A6860),
               (0.74, 0x9C9A91), (1, 0xD6D4CC)]
            : [(0, 0xEAEAE6), (0.32, 0x9A9A96), (0.62, 0x3C3C3A), (1, 0x0A0A0A)]
        // Close-up is a lit body (dark→bright). Full-bleed plate 02 keeps the
        // rim-lit catalogue ramp so it stays a pale disc, not a second 23.
        let key = close
            ? CGPoint(x: hx * sx, y: hy * sy)
            : CGPoint(x: hx * sx, y: hy * sy)
        sphere(&ctx, c: c, r: pr, hx: key.x, hy: key.y, stops: stops,
               air: 0x555550, airA: 0.10 * pose.glow, speckle: close ? 0.12 : 0.22,
               seed: seed, rim: close ? nil : (0xEAEAE6, 0.08))
        if close {
            relief(&ctx, c: c, r: pr, yaw: pose.moonYaw * .pi / 180,
                   pitch: pose.moonPitch * .pi / 180, s: s)
            glow(&ctx, at: CGPoint(x: c.x - pr * 0.55, y: c.y - pr * 0.35),
                 rx: pr * 0.55, ry: pr * 0.40, rgb: 0xB8C4E8, a: 0.06)
        } else {
            var rng = PlateRNG(seed: seed)
            ctx.drawLayer { inner in
                inner.clip(to: Path(ellipseIn: CGRect(x: c.x - pr, y: c.y - pr,
                                                      width: pr * 2, height: pr * 2)))
                for _ in 0..<18 {
                    let ax = c.x + CGFloat(rng.uniform(-0.62, 0.62)) * pr
                    let ay = c.y + CGFloat(rng.uniform(-0.62, 0.62)) * pr
                    let sr = CGFloat(rng.uniform(0.04, 0.13)) * pr
                    inner.fill(Path(ellipseIn: CGRect(x: ax - sr, y: ay - sr,
                                                      width: sr * 2, height: sr * 2)),
                               with: .color(Color.black.opacity(0.16)))
                }
            }
        }
    }

    private static func relief(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                               yaw: Double, pitch: Double, s: CGFloat) {
        _ = s
        let cyaw = cos(yaw), syaw = sin(yaw)
        let cpi = cos(pitch), spi = sin(pitch)
        ctx.drawLayer { inner in
            inner.clip(to: Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                  width: r * 2, height: r * 2)))
            for feat in moonClose {
                var px = cos(feat.lat) * sin(feat.lon)
                var py = sin(feat.lat)
                var pz = cos(feat.lat) * cos(feat.lon)
                let px2 = px * cyaw + pz * syaw
                pz = -px * syaw + pz * cyaw
                px = px2
                let py2 = py * cpi - pz * spi
                pz = py * spi + pz * cpi
                py = py2
                guard pz > 0.08 else { continue }
                let sx = c.x + CGFloat(px) * r
                let sy = c.y - CGFloat(py) * r
                let fade = min(1, pz / 0.35)
                let rx = CGFloat(feat.size) * r
                let ry = rx * CGFloat(pz)
                let rect = CGRect(x: sx - rx, y: sy - ry, width: rx * 2, height: ry * 2)
                if feat.mare {
                    inner.fill(Path(ellipseIn: rect),
                               with: .color(Color.black.opacity(0.22 * fade * feat.depth)))
                    continue
                }
                inner.fill(Path(ellipseIn: rect),
                           with: .color(Color.black.opacity(0.28 * fade * feat.depth)))
                let rim = Path(ellipseIn: rect.insetBy(dx: -rx * 0.08, dy: -ry * 0.08))
                inner.stroke(rim, with: .color(Color.white.opacity(0.16 * fade)),
                             lineWidth: max(0.8, rx * 0.08))
                let lit = CGPoint(x: sx - rx * 0.28, y: sy - ry * 0.22)
                inner.fill(Path(ellipseIn: CGRect(x: lit.x - rx * 0.18, y: lit.y - ry * 0.10,
                                                  width: rx * 0.36, height: ry * 0.20)),
                           with: .color(Color.white.opacity(0.14 * fade)))
            }
        }
    }

    // MARK: lines / arcs

    private static func swirls(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                               s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 215 * sy)
        glow(&ctx, at: c, rx: 40 * s, ry: 30 * s, rgb: 0x5E7A92, a: 0.40 * pose.glow)
        let arcs: [(Double, CGFloat, UInt32, Double, Double, Double, (Int, Double)?, Double, Double)] = [
            (46, 2.2, 0xAFC6D8, 0.50, 20, 200, nil, 4, 0.0),
            (66, 1.8, 0x7E93A8, 0.42, 150, 340, (10, 0.5), 5, 1.1),
            (86, 2.4, 0xC3D4E2, 0.46, 260, 460, nil, 4, 2.2),
            (106, 1.6, 0x6E8199, 0.38, 40, 210, (14, 0.45), 6, 0.6),
            (126, 2.0, 0x9FB4C8, 0.42, 190, 400, nil, 5, 1.7),
            (146, 1.6, 0x8AA0B4, 0.34, 300, 520, (16, 0.4), 6, 2.8),
            (164, 1.4, 0x5E7185, 0.30, 90, 260, (18, 0.4), 7, 2.0),
        ]
        for (rr, w, col, al, t0, t1, dash, sw, ph) in arcs {
            let deg = -18 + sw * sin(pose.phase * .pi * 2 + ph)
            strokeEllipse(&ctx, c: c, rx: rr * s, ry: rr * 0.42 * s,
                          rot: deg * .pi / 180, back: false, width: w * s,
                          rgb: col, a: al, arc: (t0, t1), dash: dash, dashOff: 0)
            strokeEllipse(&ctx, c: c, rx: rr * s, ry: rr * 0.42 * s,
                          rot: deg * .pi / 180, back: true, width: w * 0.8 * s,
                          rgb: col, a: al * 0.45, arc: (t0, t1), dash: dash, dashOff: 0)
        }
    }

    private static func dashedOrbits(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                     s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 205 * sy)
        glow(&ctx, at: c, rx: 55 * s, ry: 55 * s, rgb: 0x2E3E50, a: 0.38 * pose.glow)
        dashEllipse(&ctx, c: c, rx: 72 * s, ry: 72 * s, rot: 0,
                    n: 18, pose: pose, rgb: 0xB8C4D0, a: 0.60)
        dashedLine(&ctx, pose: pose, s: s,
                   from: CGPoint(x: 10 * sx, y: 70 * sy),
                   to: CGPoint(x: 348 * sx, y: 310 * sy),
                   n: 20, rgb: 0x8AA0B8, a: 0.30)
        dashedLine(&ctx, pose: pose, s: s,
                   from: CGPoint(x: 30 * sx, y: 330 * sy),
                   to: CGPoint(x: 328 * sx, y: 60 * sy),
                   n: 18, rgb: 0x8AA0B8, a: 0.26, reverse: true)
        glow(&ctx, at: CGPoint(x: 179 * sx, y: 133 * sy),
             rx: 6 * s, ry: 6 * s, rgb: 0xD8E4F0, a: 0.55 * pose.breathe)
    }

    private static func beam(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                             s: CGFloat, from: CGPoint, to: CGPoint) {
        var path = Path()
        path.move(to: from); path.addLine(to: to)
        ctx.stroke(path, with: .color(Color(hex: 0xD8DEE6, opacity: 0.50)),
                   style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round))
        glow(&ctx, at: to, rx: 24 * s, ry: 24 * s, rgb: 0x7FB2D8, a: 0.44 * pose.glow)
        glow(&ctx, at: to, rx: 9 * s, ry: 9 * s, rgb: 0xEAF4FF, a: 0.88 * pose.glow)
        glow(&ctx, at: from, rx: 6 * s, ry: 6 * s, rgb: 0xB8C8D8, a: 0.34 * pose.breathe)
    }

    private static func beamCore(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                 s: CGFloat, from: CGPoint, to: CGPoint) {
        var fat = Path(); fat.move(to: from); fat.addLine(to: to)
        ctx.stroke(fat, with: .color(Color(hex: 0x7FA8C8, opacity: 0.10 * pose.glow)),
                   style: StrokeStyle(lineWidth: 26 * s, lineCap: .round))
        var core = Path(); core.move(to: from); core.addLine(to: to)
        ctx.stroke(core, with: .color(Color(hex: 0xA8CCE8, opacity: 0.24 * pose.glow)),
                   style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
    }

    private static func horizon(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        glow(&ctx, at: CGPoint(x: 179 * sx, y: 302 * sy),
             rx: 165 * s, ry: 24 * s, rgb: 0xE05E10, a: 0.55 * pose.glow)
        glow(&ctx, at: CGPoint(x: 179 * sx, y: 296 * sy),
             rx: 130 * s, ry: 9 * s, rgb: 0xF6A41C, a: 0.46 * pose.glow)
        sphere(&ctx, c: CGPoint(x: 179 * sx, y: 218 * sy), r: 88 * s,
               hx: 179 * sx, hy: 60 * sy,
               stops: [(0, 0x2A1410), (0.4, 0x1A0D0A), (0.7, 0x0C0706), (1, 0x050303)],
               air: 0xE05E10, airA: 0.16, rim: (0xE05E10, 1.0))
        glow(&ctx, at: CGPoint(x: 179 * sx, y: 300 * sy),
             rx: 130 * s, ry: 40 * s, rgb: 0x7C2D12, a: 0.34 * pose.glow)
    }

    private static func emberPoint(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                   s: CGFloat, sx: CGFloat, sy: CGFloat) {
        glow(&ctx, at: CGPoint(x: 179 * sx, y: 318 * sy),
             rx: 34 * s, ry: 18 * s, rgb: 0xE05E10, a: 0.48 * pose.glow)
        glow(&ctx, at: CGPoint(x: 179 * sx, y: 316 * sy),
             rx: 12 * s, ry: 8 * s, rgb: 0xF6A41C, a: 0.56 * pose.glow)
        strokeEllipse(&ctx, c: CGPoint(x: 179 * sx, y: 252 * sy),
                      rx: 60 * s, ry: 30 * s, rot: 0, back: false,
                      width: 2 * s, rgb: 0xF6A41C, a: 0.50 * pose.breathe,
                      arc: (200, 340))
        glow(&ctx, at: CGPoint(x: 179 * sx, y: 252 * sy),
             rx: 30 * s, ry: 20 * s, rgb: 0x7C2D12, a: 0.22 * pose.glow)
    }

    private static func equator(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 212 * sy)
        glow(&ctx, at: c, rx: 100 * s, ry: 60 * s, rgb: 0x2E3E4C, a: 0.32 * pose.glow)
        rings(&ctx, c: c, rx: 162 * s, ry: 4 * s, deg: 0, pose: pose,
              rgb: 0xC9D8E4, dust: 0xC9D8E4, gap: 2.5 * s, wide: 0, dim: true, back: true)
        sphere(&ctx, c: c, r: 88 * s, hx: 150 * sx, hy: 170 * sy,
               stops: [(0, 0xE8F0F4), (0.22, 0xC9D4DC), (0.50, 0x7E8E9A),
                       (0.76, 0x2E3A44), (1, 0x0A0E12)],
               air: 0x2E3E4C, airA: 0.22)
        ctx.drawLayer { inner in
            inner.clip(to: Path(ellipseIn: CGRect(x: c.x - 88 * s, y: c.y - 88 * s,
                                                  width: 176 * s, height: 176 * s)))
            glow(&inner, at: CGPoint(x: c.x, y: c.y + 8 * s),
                 rx: 70 * s, ry: 8 * s, rgb: 0xE8F0F4, a: 0.28)
        }
        strokeEllipse(&ctx, c: c, rx: 162 * s, ry: 4 * s, rot: 0, back: false,
                      width: 1.6 * s, rgb: 0xEAF2F8, a: 0.88 * pose.breathe)
        strokeEllipse(&ctx, c: c, rx: 162 * s, ry: 6.5 * s, rot: 0, back: false,
                      width: 1.2 * s, rgb: 0xEAF2F8, a: 0.52 * pose.breathe)
        strokeEllipse(&ctx, c: c, rx: 162 * s, ry: 9 * s, rot: 0, back: false,
                      width: 1.0 * s, rgb: 0xEAF2F8, a: 0.32 * pose.breathe)
        glow(&ctx, at: c, rx: 150 * s, ry: 6 * s, rgb: 0x7FA8C8, a: 0.28 * pose.breathe)
    }

    private static func rainbowSaturn(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                      s: CGFloat, sx: CGFloat, sy: CGFloat) {
        let c = CGPoint(x: 179 * sx, y: 205 * sy)
        glow(&ctx, at: c, rx: 100 * s, ry: 85 * s, rgb: 0x3A3444, a: 0.32 * pose.glow)
        let segs: [UInt32] = [0xEF4444, 0xF6A41C, 0xFDE047, 0x34D399, 0x38BDF8, 0xA78BFA]
        segmentRing(&ctx, c: c, rx: 150 * s, ry: 40 * s, deg: pose.ringDeg,
                    width: 8 * s, colors: segs, a: 0.40, back: true)
        sphere(&ctx, c: c, r: 70 * s, hx: 150 * sx, hy: 170 * sy,
               stops: [(0, 0xF2EEE4), (0.4, 0xC9C0AC), (0.7, 0x5E5748), (1, 0x14120C)],
               air: 0x3A3444, airA: 0.20)
        segmentRing(&ctx, c: c, rx: 150 * s, ry: 40 * s, deg: pose.ringDeg,
                    width: 8 * s, colors: segs, a: 0.60, back: false)
        for (fx, fy, fr) in [(70.0, 90.0, 7.0), (300.0, 130.0, 6.0), (90.0, 330.0, 5.0)] {
            flare(&ctx, at: CGPoint(x: fx * sx, y: fy * sy), r: fr * s,
                  rgb: 0xFFFFFF, a: 0.50 * pose.breathe)
        }
    }

    private enum NebulaKind { case violet, magenta }

    private static func nebula(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                               s: CGFloat, sx: CGFloat, sy: CGFloat, kind: NebulaKind) {
        let blobs: [(Double, Double, Double, Double, Double, UInt32, Double, Double, Double, Double, Double)]
        switch kind {
        case .violet:
            blobs = [
                (90, 140, 90, 60, -20, 0x6D28D9, 0.24, 8, 5, 1, 0.0),
                (260, 240, 100, 70, 15, 0xA78BFA, 0.18, 7, 6, 1, 2.1),
                (150, 330, 90, 55, -10, 0x4F46E5, 0.20, 6, 5, 2, 1.0),
                (300, 90, 70, 50, 0, 0x6D28D9, 0.16, 6, 4, 2, 3.3),
            ]
        case .magenta:
            blobs = [
                (80, 100, 80, 55, -30, 0xE84393, 0.24, 7, 5, 1, 0.0),
                (170, 200, 95, 65, -30, 0xD774B4, 0.22, 8, 6, 1, 1.9),
                (270, 310, 85, 60, -30, 0xE84393, 0.20, 6, 5, 2, 0.8),
                (300, 80, 60, 45, 0, 0xA78BFA, 0.16, 5, 4, 2, 2.6),
            ]
        }
        for b in blobs {
            let ox = b.7 * sin(pose.phase * .pi * 2 * b.9 + b.10)
            let oy = b.8 * sin(pose.phase * .pi * 2 * b.9 + b.10 + 1.3)
            glow(&ctx, at: CGPoint(x: (b.0 + ox) * sx, y: (b.1 + oy) * sy),
                 rx: b.2 * s, ry: b.3 * s, rgb: b.5, a: b.6, deg: b.4)
        }
    }

    private static func comet(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                              s: CGFloat, sx: CGFloat, sy: CGFloat) {
        strokeEllipse(&ctx, c: CGPoint(x: 200 * sx, y: 260 * sy),
                      rx: 235 * s, ry: 135 * s, rot: 8 * .pi / 180, back: false,
                      width: 1 * s, rgb: 0x2E4A66, a: 0.30, arc: (150, 330))
        let t = pose.comet
        let env = pow(sin(.pi * t), 1.3)
        guard env > 0.01 else { return }
        func path(_ q: Double) -> CGPoint {
            let ax = 372.0, ay = 150.0, bx = 330.0, by = 310.0, cx = 96.0, cy = 300.0
            let u = 1 - q
            return CGPoint(x: (u * u * ax + 2 * u * q * bx + q * q * cx) * sx,
                           y: (u * u * ay + 2 * u * q * by + q * q * cy) * sy)
        }
        for j in 0..<26 {
            let q = t - Double(j) * 0.012
            guard q > 0 else { continue }
            let a = env * pow(1 - Double(j) / 26, 2) * 0.32
            let rr = max(6.5 - Double(j) * 0.2, 1.2) * s
            glow(&ctx, at: path(q), rx: rr, ry: rr, rgb: 0x38BDF8, a: a)
        }
        let head = path(t)
        glow(&ctx, at: head, rx: 17 * s, ry: 17 * s, rgb: 0x38BDF8, a: env * 0.50)
        glow(&ctx, at: head, rx: 7 * s, ry: 7 * s, rgb: 0xEAF6FF, a: env * 0.90)
    }

    // MARK: stars

    private static func stars(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                              s: CGFloat, sx: CGFloat, sy: CGFloat,
                              seed: Int, n: Int, ymax: Double = 295,
                              xlo: Double = 16, xhi: Double = 342, flares: Int = 1) {
        var rng = PlateRNG(seed: UInt64(seed))
        let palette: [UInt32] = [0xFFFFFF, 0xFFE9C9, 0xCFE4FF]
        for i in 0..<n {
            let bright = rng.next() < 0.35
            let r = (bright ? rng.uniform(1.1, 1.6) : rng.uniform(0.7, 1.05)) * s
            let a0 = bright ? rng.uniform(0.50, 0.78) : rng.uniform(0.16, 0.32)
            let x = rng.uniform(xlo, xhi)
            let y = rng.uniform(18, ymax)
            let k = 1.0 + Double(Int(rng.next() * 2))
            let ph = rng.uniform(0, .pi * 2)
            let col = palette[Int(rng.next() * 3) % 3]
            let tw = 0.5 + 0.5 * sin(pose.phase * .pi * 2 * k + ph)
            fillDot(&ctx, at: CGPoint(x: x * sx, y: y * sy), r: r, rgb: col, a: a0 * tw)
            if i == 0 || bright {
                flare(&ctx, at: CGPoint(x: x * sx, y: y * sy), r: r * 3.2,
                      rgb: col, a: a0 * tw * 0.35)
            }
        }
        for _ in 0..<flares {
            let x = rng.uniform(xlo + 24, xhi - 24)
            let y = rng.uniform(30, ymax * 0.8)
            let r = rng.uniform(4.5, 7) * s
            let ph = rng.uniform(0, .pi * 2)
            let a = 0.62 * (0.35 + 0.65 * (0.5 + 0.5 * sin(pose.phase * .pi * 4 + ph)))
            flare(&ctx, at: CGPoint(x: x * sx, y: y * sy), r: r, rgb: 0xFFFFFF, a: a)
        }
    }

    // MARK: primitives

    private static func glow(_ ctx: inout GraphicsContext, at p: CGPoint,
                             rx: CGFloat, ry: CGFloat, rgb: UInt32, a: Double,
                             deg: Double = 0) {
        guard a > 0.004, rx > 0, ry > 0 else { return }
        var inner = ctx
        if deg != 0 {
            inner.translateBy(x: p.x, y: p.y)
            inner.rotate(by: .degrees(deg))
            inner.translateBy(x: -p.x, y: -p.y)
        }
        inner.fill(Path(ellipseIn: CGRect(x: p.x - rx, y: p.y - ry, width: rx * 2, height: ry * 2)),
                   with: .radialGradient(
                    Gradient(colors: [Color(hex: rgb, opacity: a), Color(hex: rgb, opacity: 0)]),
                    center: p, startRadius: 0, endRadius: max(rx, ry)))
    }

    /// Horizon mist: gone by ~48% radius so a large ellipse never reads as a disc.
    private static func mist(_ ctx: inout GraphicsContext, at p: CGPoint,
                             rx: CGFloat, ry: CGFloat, rgb: UInt32, a: Double) {
        guard a > 0.004, rx > 0, ry > 0 else { return }
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - rx, y: p.y - ry, width: rx * 2, height: ry * 2)),
                 with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: rgb, opacity: a), location: 0),
                        .init(color: Color(hex: rgb, opacity: a * 0.40), location: 0.22),
                        .init(color: Color(hex: rgb, opacity: a * 0.10), location: 0.48),
                        .init(color: Color(hex: rgb, opacity: 0), location: 0.78),
                    ]),
                    center: p, startRadius: 0, endRadius: max(rx, ry)))
    }

    /// Paper bloom: fades by 70% radius so a large ellipse stays a haze, not a disc.
    private static func bloom(_ ctx: inout GraphicsContext, at p: CGPoint,
                              rx: CGFloat, ry: CGFloat, rgb: UInt32, a: Double,
                              deg: Double = 0) {
        guard a > 0.004, rx > 0, ry > 0 else { return }
        var inner = ctx
        if deg != 0 {
            inner.translateBy(x: p.x, y: p.y)
            inner.rotate(by: .degrees(deg))
            inner.translateBy(x: -p.x, y: -p.y)
        }
        inner.fill(Path(ellipseIn: CGRect(x: p.x - rx, y: p.y - ry, width: rx * 2, height: ry * 2)),
                   with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: rgb, opacity: a), location: 0),
                        .init(color: Color(hex: rgb, opacity: a * 0.45), location: 0.38),
                        .init(color: Color(hex: rgb, opacity: a * 0.10), location: 0.70),
                        .init(color: Color(hex: rgb, opacity: 0), location: 1),
                    ]),
                    center: p, startRadius: 0, endRadius: max(rx, ry)))
    }

    /// Paper fog-edge disc: radial holds color then dissolves. Unlike `sphere()`,
    /// there is no opaque last-stop fill and no night / spec — the screenshot
    /// of plates 02 / 20 is a glow moon, not a hard 3D cut-out.
    private static func softBall(_ ctx: inout GraphicsContext,
                                 c: CGPoint, r: CGFloat, hx: CGFloat, hy: CGFloat,
                                 stops: [(CGFloat, UInt32, Double)]) {
        guard r > 0, !stops.isEmpty else { return }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(
                    Gradient(stops: stops.map {
                        .init(color: Color(hex: $0.1, opacity: $0.2), location: $0.0)
                    }),
                    center: CGPoint(x: hx, y: hy),
                    startRadius: 0, endRadius: r))
    }

    /// Soft orb whose rim fades to clear — used as a highlight wash, not a body.
    private static func hazeOrb(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                                hx: CGFloat, hy: CGFloat,
                                core: UInt32, mid: UInt32, a: Double) {
        guard a > 0.004, r > 0 else { return }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: core, opacity: a), location: 0),
                        .init(color: Color(hex: mid, opacity: a * 0.50), location: 0.40),
                        .init(color: Color(hex: mid, opacity: a * 0.14), location: 0.72),
                        .init(color: Color(hex: mid, opacity: 0), location: 1),
                    ]),
                    center: CGPoint(x: hx, y: hy), startRadius: 0, endRadius: r * 1.05))
    }

    /// Paper 02 halo: a ring glow that starts after 70% of the radius.
    private static func haloRing(_ ctx: inout GraphicsContext, at p: CGPoint,
                                 r: CGFloat, rgb: UInt32,
                                 stops: [(CGFloat, Double)]) {
        guard r > 0 else { return }
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(
                    Gradient(stops: stops.map {
                        .init(color: Color(hex: rgb, opacity: $0.1), location: $0.0)
                    }),
                    center: p, startRadius: 0, endRadius: r))
    }

    private static func fillDot(_ ctx: inout GraphicsContext, at p: CGPoint,
                                r: CGFloat, rgb: UInt32, a: Double) {
        guard a > 0.01 else { return }
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                 with: .color(Color(hex: rgb, opacity: a)))
    }

    private static func flare(_ ctx: inout GraphicsContext, at p: CGPoint,
                              r: CGFloat, rgb: UInt32, a: Double) {
        guard a > 0.02 else { return }
        fillDot(&ctx, at: p, r: r * 0.35, rgb: rgb, a: a)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.7, y: p.y - r * 0.16,
                                        width: r * 3.4, height: r * 0.32)),
                 with: .color(Color(hex: rgb, opacity: a * 0.55)))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.16, y: p.y - r * 1.7,
                                        width: r * 0.32, height: r * 3.4)),
                 with: .color(Color(hex: rgb, opacity: a * 0.55)))
    }

    private static func crescent(_ ctx: inout GraphicsContext, at p: CGPoint,
                                 r: CGFloat, off: CGSize, rgb: UInt32, a: Double) {
        ctx.drawLayer { inner in
            var disc = Path()
            disc.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            var hole = Path()
            hole.addEllipse(in: CGRect(x: p.x + off.width - r * 0.92,
                                       y: p.y + off.height - r * 0.92,
                                       width: r * 1.84, height: r * 1.84))
            disc.addPath(hole)
            inner.fill(disc, with: .color(Color(hex: rgb, opacity: a)),
                       style: FillStyle(eoFill: true))
        }
        glow(&ctx, at: p, rx: r * 1.5, ry: r * 1.5, rgb: rgb, a: a * 0.14)
    }

    private static func paperHighlight(_ ctx: inout GraphicsContext, at p: CGPoint,
                                       rx: CGFloat, ry: CGFloat, deg: Double, a: Double) {
        ctx.drawLayer { inner in
            inner.translateBy(x: p.x, y: p.y)
            inner.rotate(by: .degrees(deg))
            inner.translateBy(x: -p.x, y: -p.y)
            inner.fill(Path(ellipseIn: CGRect(x: p.x - rx, y: p.y - ry,
                                              width: rx * 2, height: ry * 2)),
                       with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(a), Color.white.opacity(0)]),
                        center: p, startRadius: 0, endRadius: max(rx, ry)))
        }
    }

    private static func paperLine(_ ctx: inout GraphicsContext,
                                  s: CGFloat, sx: CGFloat, sy: CGFloat,
                                  from: (CGFloat, CGFloat), to: (CGFloat, CGFloat),
                                  width: CGFloat, rgb: UInt32, a: Double) {
        var path = Path()
        path.move(to: CGPoint(x: from.0 * sx, y: from.1 * sy))
        path.addLine(to: CGPoint(x: to.0 * sx, y: to.1 * sy))
        ctx.stroke(path, with: .color(Color(hex: rgb, opacity: a)),
                   style: StrokeStyle(lineWidth: width * s, lineCap: .round))
    }

    private static func paperDashStroke(_ ctx: inout GraphicsContext,
                                        path: Path, width: CGFloat, rgb: UInt32, a: Double,
                                        dash: [CGFloat], phase: CGFloat = 0) {
        let style: StrokeStyle
        if dash.isEmpty {
            style = StrokeStyle(lineWidth: width, lineCap: .round)
        } else {
            style = StrokeStyle(lineWidth: width, lineCap: .round,
                                dash: dash, dashPhase: phase)
        }
        ctx.stroke(path, with: .color(Color(hex: rgb, opacity: a)), style: style)
    }

    private static func paperDashCircle(_ ctx: inout GraphicsContext,
                                        c: CGPoint, r: CGFloat, width: CGFloat,
                                        rgb: UInt32, a: Double,
                                        dash: [CGFloat], phase: CGFloat = 0) {
        paperDashStroke(&ctx,
                        path: Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                     width: r * 2, height: r * 2)),
                        width: width, rgb: rgb, a: a, dash: dash, phase: phase)
    }

    private static func paperDashEllipse(_ ctx: inout GraphicsContext,
                                         c: CGPoint, rx: CGFloat, ry: CGFloat, deg: Double,
                                         width: CGFloat, rgb: UInt32, a: Double,
                                         dash: [CGFloat], phase: CGFloat = 0) {
        ctx.drawLayer { inner in
            inner.translateBy(x: c.x, y: c.y)
            inner.rotate(by: .degrees(deg))
            paperDashStroke(&inner,
                            path: Path(ellipseIn: CGRect(x: -rx, y: -ry,
                                                         width: rx * 2, height: ry * 2)),
                            width: width, rgb: rgb, a: a, dash: dash, phase: phase)
        }
    }

    private static func paperDashLine(_ ctx: inout GraphicsContext,
                                      s: CGFloat, sx: CGFloat, sy: CGFloat,
                                      from: (CGFloat, CGFloat), to: (CGFloat, CGFloat),
                                      width: CGFloat, rgb: UInt32, a: Double,
                                      dash: [CGFloat], phase: Double) {
        var path = Path()
        path.move(to: CGPoint(x: from.0 * sx, y: from.1 * sy))
        path.addLine(to: CGPoint(x: to.0 * sx, y: to.1 * sy))
        paperDashStroke(&ctx, path: path, width: width * s, rgb: rgb, a: a,
                        dash: dash.map { $0 * s }, phase: phase * s)
    }

    private static func paperGradientLine(_ ctx: inout GraphicsContext,
                                          s: CGFloat, sx: CGFloat, sy: CGFloat,
                                          from: (CGFloat, CGFloat), to: (CGFloat, CGFloat),
                                          width: CGFloat,
                                          stops: [(CGFloat, Double)]) {
        var path = Path()
        let a = CGPoint(x: from.0 * sx, y: from.1 * sy)
        let b = CGPoint(x: to.0 * sx, y: to.1 * sy)
        path.move(to: a)
        path.addLine(to: b)
        ctx.stroke(path, with: .linearGradient(
            Gradient(stops: stops.map {
                .init(color: Color.white.opacity($0.1), location: $0.0)
            }),
            startPoint: a, endPoint: b),
                   style: StrokeStyle(lineWidth: width * s, lineCap: .round))
    }

    private static func paperSoftBand(_ ctx: inout GraphicsContext,
                                      s: CGFloat, sx: CGFloat, sy: CGFloat,
                                      from: (CGFloat, CGFloat), to: (CGFloat, CGFloat),
                                      rx: CGFloat, rgb: UInt32, a: Double) {
        paperBlurLine(&ctx, s: s, sx: sx, sy: sy,
                      from: from, to: to, width: rx * 2, rgb: rgb, a: a)
    }

    /// Paper blurred stroke: a capsule whose alpha falls off across the width.
    private static func paperBlurLine(_ ctx: inout GraphicsContext,
                                      s: CGFloat, sx: CGFloat, sy: CGFloat,
                                      from: (CGFloat, CGFloat), to: (CGFloat, CGFloat),
                                      width: CGFloat, rgb: UInt32, a: Double) {
        let a0 = CGPoint(x: from.0 * sx, y: from.1 * sy)
        let b0 = CGPoint(x: to.0 * sx, y: to.1 * sy)
        let dx = b0.x - a0.x, dy = b0.y - a0.y
        let len = hypot(dx, dy)
        guard len > 0.5, a > 0.002, width > 0 else { return }
        let nx = -dy / len, ny = dx / len
        let hw = width * s * 0.5
        var quad = Path()
        quad.move(to: CGPoint(x: a0.x + nx * hw, y: a0.y + ny * hw))
        quad.addLine(to: CGPoint(x: b0.x + nx * hw, y: b0.y + ny * hw))
        quad.addLine(to: CGPoint(x: b0.x - nx * hw, y: b0.y - ny * hw))
        quad.addLine(to: CGPoint(x: a0.x - nx * hw, y: a0.y - ny * hw))
        quad.closeSubpath()
        let mid = CGPoint(x: (a0.x + b0.x) / 2, y: (a0.y + b0.y) / 2)
        ctx.fill(quad, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(hex: rgb, opacity: 0), location: 0),
                .init(color: Color(hex: rgb, opacity: a * 0.35), location: 0.28),
                .init(color: Color(hex: rgb, opacity: a), location: 0.5),
                .init(color: Color(hex: rgb, opacity: a * 0.35), location: 0.72),
                .init(color: Color(hex: rgb, opacity: 0), location: 1),
            ]),
            startPoint: CGPoint(x: mid.x + nx * hw, y: mid.y + ny * hw),
            endPoint: CGPoint(x: mid.x - nx * hw, y: mid.y - ny * hw)))
        bloom(&ctx, at: a0, rx: hw, ry: hw, rgb: rgb, a: a * 0.55)
        bloom(&ctx, at: b0, rx: hw, ry: hw, rgb: rgb, a: a * 0.55)
    }

    private static func paperPip(_ ctx: inout GraphicsContext, at p: CGPoint,
                                 r: CGFloat, rgb: UInt32, a: Double) {
        glow(&ctx, at: p, rx: r * 2.2, ry: r * 2.2, rgb: rgb, a: a * 0.28)
        fillDot(&ctx, at: p, r: r, rgb: rgb, a: a)
    }

    private static func paperCubics(_ ctx: inout GraphicsContext,
                                    s: CGFloat, sx: CGFloat, sy: CGFloat,
                                    p0: (CGFloat, CGFloat),
                                    c1: (CGFloat, CGFloat),
                                    c2: (CGFloat, CGFloat),
                                    p1: (CGFloat, CGFloat),
                                    c3: (CGFloat, CGFloat)? = nil,
                                    c4: (CGFloat, CGFloat)? = nil,
                                    p2: (CGFloat, CGFloat)? = nil,
                                    width: CGFloat, rgb: UInt32, a: Double,
                                    dash: [CGFloat] = [], phase: Double = 0) {
        var path = Path()
        path.move(to: CGPoint(x: p0.0 * sx, y: p0.1 * sy))
        path.addCurve(to: CGPoint(x: p1.0 * sx, y: p1.1 * sy),
                      control1: CGPoint(x: c1.0 * sx, y: c1.1 * sy),
                      control2: CGPoint(x: c2.0 * sx, y: c2.1 * sy))
        if let c3, let c4, let p2 {
            path.addCurve(to: CGPoint(x: p2.0 * sx, y: p2.1 * sy),
                          control1: CGPoint(x: c3.0 * sx, y: c3.1 * sy),
                          control2: CGPoint(x: c4.0 * sx, y: c4.1 * sy))
        }
        paperDashStroke(&ctx, path: path, width: width * s, rgb: rgb, a: a,
                        dash: dash.map { $0 * s }, phase: phase * s)
    }

    private static func plate24Point(_ q: Double) -> (Double, Double) {
        func cubic(_ t: Double,
                   _ a: (Double, Double), _ b: (Double, Double),
                   _ c: (Double, Double), _ d: (Double, Double)) -> (Double, Double) {
            let u = 1 - t, uu = u * u, uuu = uu * u, tt = t * t, ttt = tt * t
            return (uuu * a.0 + 3 * uu * t * b.0 + 3 * u * tt * c.0 + ttt * d.0,
                    uuu * a.1 + 3 * uu * t * b.1 + 3 * u * tt * c.1 + ttt * d.1)
        }
        if q <= 0.5 {
            return cubic(q * 2, (372, 96), (268, 116), (196, 178), (158, 246))
        }
        return cubic((q - 0.5) * 2, (158, 246), (128, 300), (138, 344), (196, 366))
    }

    /// SVG elliptical-arc center parameterization (Paper path `M … A rx ry deg …`).
    private static func svgArc(_ ctx: inout GraphicsContext,
                               s: CGFloat, sx: CGFloat, sy: CGFloat,
                               x1: Double, y1: Double, rx: Double, ry: Double,
                               deg: Double, large: Bool, sweep: Bool,
                               x2: Double, y2: Double,
                               width: CGFloat, rgb: UInt32, a: Double,
                               dash: (Int, Double)? = nil, dashOff: Double = 0,
                               marks: [CGFloat]? = nil, markPhase: CGFloat = 0) {
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
        var path = Path()
        let steps = 56
        var drew = false
        for i in 0...steps {
            let u = Double(i) / Double(steps)
            if marks == nil, let dash {
                let duty = ((u + dashOff) * Double(dash.0)).truncatingRemainder(dividingBy: 1)
                guard duty < dash.1 else { drew = false; continue }
            }
            let θ = θ1 + Δθ * u
            let x = rxv * cos(θ), y = ryv * sin(θ)
            let p = CGPoint(x: (cx + x * cosφ - y * sinφ) * sx,
                            y: (cy + x * sinφ + y * cosφ) * sy)
            if drew { path.addLine(to: p) } else { path.move(to: p); drew = true }
        }
        if let marks {
            paperDashStroke(&ctx, path: path, width: width * s, rgb: rgb, a: a,
                            dash: marks.map { $0 * s }, phase: markPhase * s)
        } else {
            ctx.stroke(path, with: .color(Color(hex: rgb, opacity: a)),
                       style: StrokeStyle(lineWidth: width * s, lineCap: .round))
        }
    }

    private static func strokeCircle(_ ctx: inout GraphicsContext, c: CGPoint,
                                     r: CGFloat, width: CGFloat, rgb: UInt32, a: Double) {
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                   with: .color(Color(hex: rgb, opacity: a)),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private static func strokeEllipse(_ ctx: inout GraphicsContext, c: CGPoint,
                                      rx: CGFloat, ry: CGFloat, rot: Double,
                                      back: Bool, width: CGFloat, rgb: UInt32, a: Double,
                                      arc: (Double, Double)? = nil,
                                      dash: (Int, Double)? = nil, dashOff: Double = 0) {
        var path = Path()
        let steps = 64
        var drew = false
        for i in 0...steps {
            let u = Double(i) / Double(steps)
            let t = u * .pi * 2
            if let arc {
                let deg = (u * 360).truncatingRemainder(dividingBy: 360)
                let t0 = arc.0.truncatingRemainder(dividingBy: 360)
                let t1 = arc.1.truncatingRemainder(dividingBy: 360)
                let inside = t0 <= t1 ? (deg >= t0 && deg <= t1) : (deg >= t0 || deg <= t1)
                guard inside else { drew = false; continue }
            }
            if let dash {
                let duty = ((u + dashOff) * Double(dash.0)).truncatingRemainder(dividingBy: 1)
                guard duty < dash.1 else { drew = false; continue }
            }
            let x = Double(rx) * cos(t), y = Double(ry) * sin(t)
            let yr = x * sin(rot) + y * cos(rot)
            let isFront = yr > 0
            guard isFront != back else { drew = false; continue }
            let p = CGPoint(x: c.x + CGFloat(x * cos(rot) - y * sin(rot)),
                            y: c.y + CGFloat(x * sin(rot) + y * cos(rot)))
            if drew { path.addLine(to: p) } else { path.move(to: p); drew = true }
        }
        ctx.stroke(path, with: .color(Color(hex: rgb, opacity: a)),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private static func dashEllipse(_ ctx: inout GraphicsContext, c: CGPoint,
                                    rx: CGFloat, ry: CGFloat, rot: Double,
                                    n: Int, pose: IdlePlatePose, rgb: UInt32, a: Double) {
        let steps = n * 4
        for i in 0..<steps {
            let u = (Double(i) / Double(steps) + pose.dash).truncatingRemainder(dividingBy: 1)
            let duty = (u * Double(n)).truncatingRemainder(dividingBy: 1)
            guard duty < 0.45 else { continue }
            let t = u * .pi * 2
            let x = Double(rx) * cos(t), y = Double(ry) * sin(t)
            let p = CGPoint(x: c.x + CGFloat(x * cos(rot) - y * sin(rot)),
                            y: c.y + CGFloat(x * sin(rot) + y * cos(rot)))
            fillDot(&ctx, at: p, r: 1.55, rgb: rgb, a: a)
        }
    }

    private static func dashArc(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat,
                                from: Double, to: Double, n: Int,
                                pose: IdlePlatePose, rgb: UInt32, a: Double) {
        strokeEllipse(&ctx, c: c, rx: r, ry: r, rot: 0, back: false,
                      width: 2 * (r / 68), rgb: rgb, a: a,
                      arc: (from, to), dash: (n, 0.42), dashOff: pose.dash)
    }

    private static func dashedLine(_ ctx: inout GraphicsContext, pose: IdlePlatePose,
                                   s: CGFloat, from: CGPoint, to: CGPoint,
                                   n: Int, rgb: UInt32, a: Double,
                                   reverse: Bool = false, crawl: Bool = true) {
        if n <= 1 || !crawl {
            var path = Path()
            path.move(to: from); path.addLine(to: to)
            ctx.stroke(path, with: .color(Color(hex: rgb, opacity: a)),
                       style: StrokeStyle(lineWidth: 1.1 * s, lineCap: .round))
            return
        }
        let off = reverse ? -pose.dash : pose.dash
        for i in 0..<n {
            let u = (Double(i) / Double(n) + off).truncatingRemainder(dividingBy: 1)
            guard (u * Double(n)).truncatingRemainder(dividingBy: 1) < 0.42 else { continue }
            let p = CGPoint(x: from.x + (to.x - from.x) * CGFloat(u),
                            y: from.y + (to.y - from.y) * CGFloat(u))
            fillDot(&ctx, at: p, r: 1.35 * s, rgb: rgb, a: a)
        }
    }

    private static func ringDots(_ ctx: inout GraphicsContext, c: CGPoint,
                                 rx: CGFloat, ry: CGFloat, deg: Double,
                                 n: Int, phase: Double, r: CGFloat, rgb: UInt32) {
        let rot = deg * .pi / 180
        for i in 0..<n {
            let t = .pi * 2 * (Double(i) + phase) / Double(n)
            let x = Double(rx) * cos(t), y = Double(ry) * sin(t)
            let p = CGPoint(x: c.x + CGFloat(x * cos(rot) - y * sin(rot)),
                            y: c.y + CGFloat(x * sin(rot) + y * cos(rot)))
            glow(&ctx, at: p, rx: r * 1.8, ry: r * 1.8, rgb: rgb, a: 0.35)
            fillDot(&ctx, at: p, r: r, rgb: rgb, a: 0.88)
        }
    }

    private static func segmentRing(_ ctx: inout GraphicsContext, c: CGPoint,
                                    rx: CGFloat, ry: CGFloat, deg: Double,
                                    width: CGFloat, colors: [UInt32], a: Double,
                                    back: Bool) {
        let n = colors.count
        let span = 360.0 / Double(n)
        for (i, col) in colors.enumerated() {
            let t0 = Double(i) * span
            strokeEllipse(&ctx, c: c, rx: rx, ry: ry, rot: deg * .pi / 180,
                          back: back, width: width, rgb: col, a: a,
                          arc: (t0, t0 + span))
        }
    }

    private static func hash(_ n: Double, _ salt: Double) -> Double {
        let v = sin(n * salt) * 43758.5453
        return v - v.rounded(.down)
    }
}

private struct PlateRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }
    init(seed: Int) { self.init(seed: UInt64(truncatingIfNeeded: seed)) }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFFFF_FFFF) / 4_294_967_296
    }

    mutating func uniform(_ a: Double, _ b: Double) -> Double {
        a + (b - a) * next()
    }
}