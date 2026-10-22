import SwiftUI
import simd

/// A planet as a fine grain screen, drawn per grain on the GPU (`GrainPlanet.metal`).
/// Surfaces are procedural and turn about their own pole; every grain is a soft lamp, and a
/// smooth neon halo blooms past the limb. Everything draws additively (`.plusLighter`), so the
/// night side and the sky simply vanish into the page. `lit` sets how much of the face the sun
/// reaches.
extension EnvironmentValues {
    /// False while a home art layer cannot be seen: its page is off to the side, the timeline
    /// covers it, or a detail page / takeover sits on top. Animated art pauses on it.
    var homeArtActive: Bool {
        get { self[HomeArtActiveKey.self] }
        set { self[HomeArtActiveKey.self] = newValue }
    }
}

private struct HomeArtActiveKey: EnvironmentKey {
    static let defaultValue = true
}

struct ParticlePlanet: View {
    enum Kind: Sendable { case terra, luna, mars }

    var kind: Kind
    /// Planet centre as a fraction of the view's size.
    var center: UnitPoint
    /// Radius as a fraction of the view's height.
    var radius: CGFloat
    /// Edge length of one grain in points.
    var pitch: CGFloat
    /// Lit fraction of the visible disc, 0...1.
    var lit: Double
    /// Which side the light comes from: -1 left, +1 right.
    var sunSide: Float = -1
    /// Seconds for one full turn.
    var day: Double
    /// Density of the twinkling star field around the planet.
    var stars: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.homeArtActive) private var artActive
    @State private var onScreen = false

    /// ⚠️ Performance. Three of these share the planet page and every grain runs several fbm
    /// octaves. Unthrottled, `.animation` ran them at 120 Hz on ProMotion — for a body that
    /// turns once a minute — and kept going while the page sat off screen behind an offset
    /// or under a pushed detail page (`onDisappear` fires for neither). 30 Hz reads the same.
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30,
                                    paused: reduceMotion || !onScreen || !artActive)) { timeline in
                layer(size: geometry.size,
                      time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .blendMode(.plusLighter)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func layer(size: CGSize, time: Double) -> some View {
        let r = radius * size.height
        let c = CGPoint(x: size.width * center.x, y: size.height * center.y)
        let sun = self.sun
        // Turns are wrapped in Double so the shader's Float never sees a huge clock.
        let turns = time / day
        let spin = turns.truncatingRemainder(dividingBy: 1) * 2 * .pi + phase
        let cloudSpin = (turns * 1.18).truncatingRemainder(dividingBy: 1) * 2 * .pi + phase * 1.7
        let seconds = time.truncatingRemainder(dividingBy: 3600)
        return Rectangle()
            .fill(.black)
            .colorEffect(ShaderLibrary.nbGrainPlanet(
                .float2(size),
                .float4(Float(c.x), Float(c.y), Float(r), Float(pitch)),
                .float4(sun.x, sun.y, sun.z, Float(kindIndex)),
                .float4(Float(spin), Float(cloudSpin), Float(seconds), Float(stars))
            ))
    }

    private var kindIndex: Int {
        switch kind {
        case .terra: return 0
        case .luna: return 1
        case .mars: return 2
        }
    }

    /// Each body starts on a composed face rather than the noise origin.
    private var phase: Double {
        switch kind {
        case .terra: return 2.4
        case .luna: return 0.6
        case .mars: return 4.1
        }
    }

    /// Unit vector toward the sun: +x right, +y up, +z toward the viewer.
    private var sun: SIMD3<Float> {
        let k = Float(max(0.04, min(1, lit)))
        let a = acos(2 * k - 1)
        return simd_normalize(SIMD3<Float>(sunSide * sin(a), 0.24, cos(a)))
    }
}
