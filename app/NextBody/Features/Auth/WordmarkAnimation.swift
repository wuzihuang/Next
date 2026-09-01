import SwiftUI
import UIKit

/// MOTION SPEC · 01 · 像素坠落 → 字标成形.
/// 2.6s, plays through once, never loops. It exists in exactly two places in the product:
/// first launch, and the moment the band pairs — one animation, not two.
///
///  0.00 → 0.35  ease-out       the whole screen goes lime for 120ms then drops to pure black.
///                              Not a fade-in — a power-on. One short haptic at the peak; the
///                              only haptic in the film.
///  0.35 → 1.10  linear-in      pixels fall from above at three speeds, each dragging a short
///                              blur. Depth comes from the speed difference, not from defocus.
///                              A 1px lime line at the bottom is the floor.
///  1.10 → 1.80  ease-out-back  every pixel drops into its own letter cell, overshooting 4pt
///                              before springing back. Readable, but still dim and half-formed.
///  1.80 → 2.15  ease-in-out    the last pixel lands and the whole word lights lime at once,
///                              a soft glow pushing outward. Strays are flung aside, not cleaned up.
///  2.15 → 2.60  ease-out       the matrix cross-dissolves into the solid Inter Tight wordmark —
///                              the resolution finding focus. The sub-line fades in 200ms later.
struct WordmarkAnimation: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var t: Double = 0
    @State private var start = Date()
    @State private var haptic = false

    private static let total: Double = 2.60

    var body: some View {
        TimelineView(.animation) { tl in
            let t = reduceMotion ? Self.total : tl.date.timeIntervalSince(start)
            ZStack {
                Color.black.ignoresSafeArea()

                // ◇1 · power-on flash
                NB.lime1
                    .ignoresSafeArea()
                    .opacity(flashOpacity(t))

                PixelFall(t: t)
                    .frame(width: 390, height: 844)

                // ◇5 · the solid wordmark takes over
                VStack(spacing: 22) {
                    Wordmark(size: 46)
                        .opacity(solidOpacity(t))
                        .shadow(color: NB.lime1.opacity(0.5 * glow(t)), radius: 24)
                    Text("Build your next body.")
                        .font(NBFont.ui(300, 21)).tracking(0.02 * 21)
                        .foregroundStyle(NB.white.opacity(0.82))
                        .opacity(subOpacity(t))
                }
            }
            .onChange(of: t >= Self.total) { _, done in if done { onFinish() } }
        }
        .statusBarHidden()
        .onAppear {
            start = Date()
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            if reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onFinish() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.20) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.total) { onFinish() }
        }
    }

    private func flashOpacity(_ t: Double) -> Double {
        if t < 0.12 { return 1 }
        if t < 0.35 { return 1 - (t - 0.12) / 0.23 }
        return 0
    }
    private func glow(_ t: Double) -> Double {
        guard t >= 1.80 else { return 0 }
        if t < 2.15 { return (t - 1.80) / 0.35 }
        return max(0, 1 - (t - 2.15) / 0.45)
    }
    private func solidOpacity(_ t: Double) -> Double {
        guard t >= 2.15 else { return 0 }
        return min(1, (t - 2.15) / 0.45)
    }
    private func subOpacity(_ t: Double) -> Double {
        guard t >= 2.35 else { return 0 }
        return min(1, (t - 2.35) / 0.25)
    }
}

/// The falling matrix. Each pixel owns a letter cell; the word is legible before it is lit.
private struct PixelFall: View {
    let t: Double

    /// A 5 × 7 face for the eight letters of the wordmark.
    private static let font: [Character: [String]] = [
        "N": ["X...X", "XX..X", "XX..X", "X.X.X", "X..XX", "X..XX", "X...X"],
        "E": ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"],
        "X": ["X...X", "X...X", ".X.X.", "..X..", ".X.X.", "X...X", "X...X"],
        "T": ["XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "..X.."],
        "B": ["XXXX.", "X...X", "X...X", "XXXX.", "X...X", "X...X", "XXXX."],
        "O": [".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
        "D": ["XXXX.", "X...X", "X...X", "X...X", "X...X", "X...X", "XXXX."],
        "Y": ["X...X", "X...X", ".X.X.", "..X..", "..X..", "..X..", "..X.."],
    ]

    private struct Pixel {
        let target: CGPoint
        let speed: Int          // 0 fast · 1 mid · 2 slow — depth is speed, not blur
        let startX: CGFloat
        let stray: Bool
        let strayDrift: CGFloat
    }

    private static let pixels: [Pixel] = {
        let word = Array("NEXTBODY")
        let cell: CGFloat = 4.4
        let letterW = cell * 6
        let totalW = letterW * CGFloat(word.count) - cell
        let originX = (390 - totalW) / 2
        let originY: CGFloat = 400
        var out: [Pixel] = []
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 1000) / 1000
        }
        for (li, ch) in word.enumerated() {
            guard let rows = font[ch] else { continue }
            for (r, row) in rows.enumerated() {
                for (c, ck) in row.enumerated() where ck == "X" {
                    out.append(Pixel(
                        target: CGPoint(x: originX + CGFloat(li) * letterW + CGFloat(c) * cell,
                                        y: originY + CGFloat(r) * cell),
                        speed: Int(rnd() * 3),
                        startX: originX + CGFloat(li) * letterW + CGFloat(c) * cell + (rnd() - 0.5) * 44,
                        stray: false, strayDrift: 0))
                }
            }
        }
        // strays — they never had a cell, and nobody tidies them away
        for _ in 0..<26 {
            out.append(Pixel(target: CGPoint(x: rnd() * 390, y: 430),
                             speed: Int(rnd() * 3),
                             startX: rnd() * 390,
                             stray: true, strayDrift: (rnd() - 0.5) * 320))
        }
        return out
    }()

    var body: some View {
        Canvas { ctx, size in
            guard t >= 0.30 else { return }
            for (i, px) in Self.pixels.enumerated() {
                let lead = Double(px.speed) * 0.14 + Double(i % 7) * 0.012
                let fallStart = 0.35 + lead
                let fallEnd = 1.10 + lead
                guard t >= fallStart else { continue }

                var y: CGFloat
                var x = px.startX
                var alpha: Double = 1
                var trail: CGFloat = 0

                if t < fallEnd {
                    let p = (t - fallStart) / (fallEnd - fallStart)
                    y = -10 + (px.target.y + 10) * CGFloat(p)
                    trail = CGFloat(10 - px.speed * 3) * CGFloat(1 - p * 0.4)
                    alpha = 0.28 + 0.32 * Double(2 - px.speed) / 2
                } else if t < 1.80 {
                    // ◇3 · land with a 4pt overshoot, then spring back
                    let p = min(1, (t - fallEnd) / (1.80 - fallEnd))
                    let over = sin(p * .pi) * 4
                    y = px.target.y + CGFloat(over) * (1 - CGFloat(p))
                    x = px.startX + (px.target.x - px.startX) * CGFloat(p)
                    alpha = 0.45
                } else {
                    y = px.target.y
                    x = px.target.x
                    alpha = t < 2.15 ? 0.45 + 0.55 * (t - 1.80) / 0.35 : max(0, 1 - (t - 2.15) / 0.45)
                }

                if px.stray && t >= 1.80 {
                    let p = min(1, (t - 1.80) / 0.6)
                    x = px.startX + px.strayDrift * CGFloat(p)
                    alpha *= 1 - Double(p)
                }

                let colour: Color = t >= 1.80 ? NB.lime1 : NB.white.opacity(0.9)
                if trail > 0 {
                    ctx.fill(Path(CGRect(x: x, y: y - trail, width: 3, height: trail + 3)),
                             with: .color(colour.opacity(alpha * 0.35)))
                }
                ctx.fill(Path(CGRect(x: x, y: y, width: 3, height: 3)),
                         with: .color(colour.opacity(alpha)))
            }

            // the floor
            if t >= 0.35 && t < 1.95 {
                let a = t < 1.80 ? 0.55 : 0.55 * (1 - (t - 1.80) / 0.15)
                ctx.fill(Path(CGRect(x: 0, y: 470, width: size.width, height: 1)),
                         with: .color(NB.lime1.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
}
