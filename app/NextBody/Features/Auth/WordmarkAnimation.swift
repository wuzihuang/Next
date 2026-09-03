import CoreHaptics
import SwiftUI
import UIKit

/// MOTION SPEC · 01 · 像素坠落 → 字标成形.
/// 2.6s, plays through once, never loops. It exists in exactly two places in the product:
/// first launch, and the moment the band pairs — one animation, not two.
///
///  0.00 → 0.35  ease-out       the whole screen goes lime for 120ms then drops to pure black.
///                              Not a fade-in — a power-on. Nothing is felt here: a hit on the
///                              flash reads as a button being pressed and dirties the opening.
///  0.35 → 1.10  linear-in      pixels fall from above at three speeds, each dragging a short
///                              blur. Depth comes from the speed difference, not from defocus.
///                              A 1px lime line at the bottom is the floor. This is where the
///                              hand is used: rain, 哒哒哒哒哒, thickening and passing.
///  1.10 → 1.80  ease-out-back  every pixel drops into its own letter cell, overshooting 4pt
///                              before springing back. Readable, but still dim and half-formed.
///  1.80 → 2.15  ease-in-out    the last pixel lands and the whole word lights lime at once,
///                              a soft glow pushing outward. Strays are flung aside, not cleaned up.
///  2.15 → 2.60  ease-out       the matrix cross-dissolves into the solid Inter Tight wordmark —
///                              the resolution finding focus. The sub-line fades in 200ms later.
///                              The dot lands on two taps — the 「噔噔」. See WordmarkHaptics.
struct WordmarkAnimation: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var t: Double = 0
    @State private var start = Date()
    @State private var haptics = WordmarkHaptics()

    private static let total: Double = 2.60
    /// Reduce Motion holds the last frame instead of playing the fall. 0.3s was the same as
    /// never showing the wordmark at all — the word still has to be read.
    private static let still: Double = 1.40

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
                    .frame(width: ScreenMetrics.size.width, height: ScreenMetrics.size.height)

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
        .onDisappear { haptics.stop() }
        .onAppear {
            // Creating and starting the haptic engine blocks the main thread for tens of
            // milliseconds. That cost is paid before the clock is stamped, so it lands ahead
            // of t = 0 instead of inside it — otherwise the first frame is already late by
            // the time it is drawn, and the score runs ahead of the picture for all 2.6 s.
            haptics.prepare()
            start = Date()
            haptics.play(still: reduceMotion)
            if reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.still) { onFinish() }
                return
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
        // ◇5 dissolves the matrix into the solid wordmark, so the two have to occupy the same
        // band: the solid one is the top half of a centred stack and sits 23pt above the
        // canvas centre, and this is that same centre line, 15pt up for the 7 rows below it.
        let originY: CGFloat = 384
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
            out.append(Pixel(target: CGPoint(x: rnd() * 390, y: 414),
                             speed: Int(rnd() * 3),
                             startX: rnd() * 390,
                             stray: true, strayDrift: (rnd() - 0.5) * 320))
        }
        return out
    }()

    var body: some View {
        Canvas { ctx, size in
            guard t >= 0.30 else { return }
            // The matrix is laid out on the 390 × 844 canvas the board draws. On a wider
            // phone it is scaled and centred, not left sitting in the top-left corner —
            // otherwise the cross-dissolve in ◇5 jumps from one word to another somewhere else.
            let k = size.width / 390
            ctx.scaleBy(x: k, y: k)
            ctx.translateBy(x: 0, y: (size.height / k - 844) / 2)
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
                ctx.fill(Path(CGRect(x: 0, y: 454, width: 390, height: 1)),
                         with: .color(NB.lime1.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// 02M · the film's haptic score. Two gestures and a silence between them: the rain of the
/// fall, then the 「噔噔」 as the dot lands. The power-on flash is deliberately untouched —
/// a hit there reads as a button being pressed, which is the wrong verb for the opening
/// frame and dirties everything after it.
///
/// Core Haptics rather than the canned generators, because this is a score and not a
/// notification: `.success` is somebody else's three-beat pattern and has nothing to do with
/// these pictures, and two dozen `asyncAfter`ed `UIImpactFeedbackGenerator` calls cannot hold
/// 45 ms spacing steadily enough to read as rain rather than as stutter.
@MainActor
final class WordmarkHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?

    /// Warm the engine up. Split out of `play` because starting it is the expensive part and
    /// it has to happen before the film's clock is stamped, not after.
    func prepare() {
        guard engine == nil, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            // The pattern is scheduled two and a half seconds ahead; an engine allowed to
            // shut itself down when idle would take the 「噔噔」 with it.
            engine.isAutoShutdownEnabled = false
            try engine.start()
            self.engine = engine
        } catch {
            #if DEBUG
            print("NB_HAPTIC engine failed to start (\(error))")
            #endif
        }
    }

    func play(still: Bool) {
        // Reduce Motion holds the last frame instead of playing the fall, so there is no rain
        // to track — only the landing, moved onto that shorter beat.
        let dun1 = still ? 0.50 : 2.30
        let dun2 = still ? 0.62 : 2.42
        prepare()
        guard let engine else {
            #if DEBUG
            print("NB_HAPTIC no engine — falling back")
            #endif
            fallback(dun1: dun1, dun2: dun2); return
        }
        do {
            var events: [CHHapticEvent] = still ? [] : Self.rain()
            // ◇5 · 「点要一个"噔噔"的震动」. Two transients 120 ms apart — the window in which
            // they read as one gesture — the second harder and sharper: the first is the dot
            // arriving, the second is the resolution snapping onto it.
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: 0.70),
                .init(parameterID: .hapticSharpness, value: 0.55),
            ], relativeTime: dun1))
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: 1.0),
                .init(parameterID: .hapticSharpness, value: 0.95),
            ], relativeTime: dun2))

            let player = try engine.makePlayer(with: try CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            self.player = player
            #if DEBUG
            print("NB_HAPTIC score started · \(events.count) events · 噔噔 at \(dun1)/\(dun2)")
            #endif
        } catch {
            #if DEBUG
            print("NB_HAPTIC engine failed (\(error)) — falling back")
            #endif
            fallback(dun1: dun1, dun2: dun2)
        }
    }

    /// ◇2 · the rain. Not one tap per pixel — there are 240 of them inside 1.2 s and the hand
    /// cannot separate hits closer than about 45 ms, so that is a buzz, not weather. Two dozen
    /// drops instead, scattered on an irregular grid: sparse as the first pixels arrive, thick
    /// through the middle where the fast and mid bands land together, thinning out before the
    /// word lights. Each one is small and dry — high sharpness, low intensity. A soft drop is
    /// a thud, and rain has no thud in it.
    private static func rain() -> [CHHapticEvent] {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 1000) / 1000
        }
        var events: [CHHapticEvent] = []
        var t = 0.42
        while t < 1.62 {
            let peak = max(0, 1 - abs(t - 1.02) / 0.62)
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: Float(0.12 + 0.24 * peak + rnd() * 0.10)),
                .init(parameterID: .hapticSharpness, value: Float(0.72 + rnd() * 0.25)),
            ], relativeTime: t))
            // 44 ms at the height of it, 86 ms at the edges, and never twice the same —
            // an even spacing turns rain into a machine.
            t += 0.058 - 0.028 * peak + rnd() * 0.028
        }
        return events
    }

    /// Hardware with no Taptic Engine, or an engine that will not start. The rain cannot be
    /// carried by the canned generators, so only the landing survives — blunt, but not silent.
    private func fallback(dun1: Double, dun2: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + dun1) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dun2) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }

    /// The film hands the screen over the moment it ends; the engine goes with it.
    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        engine?.stop()
        player = nil
        engine = nil
    }
}
