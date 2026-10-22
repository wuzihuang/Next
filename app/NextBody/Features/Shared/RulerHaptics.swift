import CoreHaptics
import UIKit

/// The detents of a physical ruler under the thumb. Every 0.1 is a thin, bright click; every
/// 0.5 is a touch heavier; every whole unit is a full notch you could count without looking.
/// A fast flick blurs the minor clicks the way a ratchet does — quieter and spaced out so
/// the motor never smears into a buzz — while the whole-unit notches still land. Hitting
/// either end of the range is one dull bump, not a click, and it does not repeat while the
/// finger keeps pushing. Core Haptics falls back to a prepared UIKit generator.
@MainActor
final class RulerHaptics {
    enum Mark { case minor, half, major }

    private var engine: CHHapticEngine?
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let fallback = UIImpactFeedbackGenerator(style: .rigid)
    private let edgeFallback = UIImpactFeedbackGenerator(style: .heavy)
    private var lastFire: CFTimeInterval = 0
    private var atEdge = false

    /// Below this gap the motor cannot separate two transients; minor clicks inside it drop.
    private static let minGap: CFTimeInterval = 0.018
    /// At or below this gap the drag counts as a flick and the minor clicks soften.
    private static let flickGap: CFTimeInterval = 0.045

    /// Warm the engine on touch-down so the first click lands with the first tick.
    func prepare() {
        fallback.prepare()
        edgeFallback.prepare()
        guard supported else { return }
        if engine == nil { makeEngine() }
        try? engine?.start()
    }

    /// The needle crossed one or more ticks; `mark` is the most significant one it crossed.
    func tick(_ mark: Mark) {
        atEdge = false
        guard HapticsSetting.shared.enabled else { return }
        let now = CACurrentMediaTime()
        let gap = now - lastFire
        if mark == .minor, gap < Self.minGap { return }
        lastFire = now

        // How hard the thumb is moving: 0 at a slow crawl, 1 at a flick.
        let speed = Float(((Self.flickGap * 2 - gap) / Self.flickGap).clamped(0, 1))
        let (intensity, sharpness): (Float, Float)
        switch mark {
        case .minor: (intensity, sharpness) = (0.42 - 0.17 * speed, 0.95)
        case .half: (intensity, sharpness) = (0.62 - 0.12 * speed, 0.85)
        case .major: (intensity, sharpness) = (0.92, 0.6)
        }
        play(intensity: intensity, sharpness: sharpness, fallback: fallback)
    }

    /// The value pinned at either end of the range.
    func edge() {
        guard !atEdge else { return }
        atEdge = true
        guard HapticsSetting.shared.enabled else { return }
        lastFire = CACurrentMediaTime()
        play(intensity: 1.0, sharpness: 0.2, fallback: edgeFallback)
    }

    /// The finger lifted; the next push into an edge bumps again.
    func end() { atEdge = false }

    private func play(intensity: Float, sharpness: Float, fallback: UIImpactFeedbackGenerator) {
        defer { fallback.prepare() }
        guard supported, let engine else {
            fallback.impactOccurred(intensity: CGFloat(intensity))
            return
        }
        do {
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: 0)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback.impactOccurred(intensity: CGFloat(intensity))
        }
    }

    private func makeEngine() {
        guard let engine = try? CHHapticEngine() else { return }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        engine.resetHandler = { [weak self] in
            Task { @MainActor in try? self?.engine?.start() }
        }
        self.engine = engine
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
