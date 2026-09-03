import SwiftUI

/// 14 · LIVE SESSION · the globe. One rectangle, one fragment shader (`BayerGlobe.metal`),
/// redrawn by the display clock. The whole picture is computed per cell on the GPU, so
/// full-screen at 120 Hz costs nothing the CPU can feel — which is the point: this screen
/// stays up for an hour.
///
/// It is drawn in the takeover's own coordinates: `center` and `radius` are points in the
/// view this fills, so the halo bleeds across the whole screen and fades on its own rather
/// than stopping at a stage's edge.
struct BayerGlobe: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the disc sits, in this view's points.
    var center: CGPoint
    var radius: CGFloat
    /// Beats per minute for the pulse on the halo; nil holds the halo still.
    var bpm: Int?
    /// 0…1 · where the heart sits in its range. Colours the world and sharpens its pulse.
    var effort: Double = 0
    /// Turns per second. Rises with effort — see `LiveSessionTakeover`.
    var turnRate: Double = 0.14
    var cell: CGFloat = 5
    var levels: Double = 5
    var landLevel: Double = 0.50
    var glowReach: Double = 1.95

    /// Starts part-turned so the first frame is a composed one rather than the seam.
    @State private var spin: Double = 2.1
    @State private var clock: Double = 0
    @State private var lastTick: Date?

    var body: some View {
        if reduceMotion {
            // F5 C11 · decorative motion holds its pose; the readouts still update.
            layer(spin: spin, clock: clock, beat: 0)
        } else {
            TimelineView(.animation) { tl in
                layer(spin: spin, clock: clock, beat: beat(at: clock))
                    .onChange(of: tl.date) { _, now in
                        let previous = lastTick ?? now
                        lastTick = now
                        // On-screen seconds, capped so a stall does not jump the world.
                        let dt = min(now.timeIntervalSince(previous), 1.0 / 20)
                        clock += dt
                        spin += dt * turnRate * 2 * .pi
                    }
            }
        }
    }

    /// 0…1 · a sharp rise and an exponential fall once per beat, phased off the on-screen
    /// clock so it never drifts against the number it is telling again.
    private func beat(at t: Double) -> Double {
        guard let bpm, bpm > 0 else { return 0 }
        let period = 60.0 / Double(bpm)
        let phase = t.truncatingRemainder(dividingBy: period) / period
        return exp(-phase * 7)
    }

    private func layer(spin: Double, clock: Double, beat: Double) -> some View {
        Rectangle()
            .fill(NB.panelInk)
            .colorEffect(ShaderLibrary.nbBayerGlobe(
                .float2(center),
                .float(radius),
                .float(cell),
                .float(clock),
                .float(spin),
                .float(beat),
                .float(landLevel),
                .float(levels),
                .float(glowReach),
                .float(effort),
                .color(NB.panelInk),
                .color(NB.lime1),
                .color(NB.limePale),
                .color(NB.ember1)
            ))
            .allowsHitTesting(false)
    }
}
