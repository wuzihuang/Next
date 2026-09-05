import CoreHaptics
import UIKit

/// Two short taps: a soft, low-sharpness pulse at the hold threshold and a crisp pulse
/// on release. Keeping the finger down does not sustain or repeat the vibration.
/// Core Haptics falls back to UIKit on hardware without a haptic engine.
@MainActor
final class HoldHaptics {
    static let shared = HoldHaptics()

    private var engine: CHHapticEngine?
    private var hold: CHHapticPatternPlayer?
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    /// The lift tap must land on the very next frame after the finger goes; a generator that
    /// is already prepared answers in time, a cold one does not.
    private let liftFallback = UIImpactFeedbackGenerator(style: .rigid)
    private let armFallback = UIImpactFeedbackGenerator(style: .soft)

    private init() {}

    /// Warm the engine before the threshold so its pulse lands immediately.
    func prepare() {
        armFallback.prepare()
        liftFallback.prepare()
        guard supported else { return }
        if engine == nil { makeEngine() }
        try? engine?.start()
    }

    /// One low-sharpness transient at the threshold; never a continuous event.
    func beginHold() {
        stopHold()
        guard supported, let engine else { armFallback.impactOccurred(intensity: 0.7); return }
        do {
            try engine.start()
            let tap = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.75),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15),
            ], relativeTime: 0)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [tap], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            hold = player
        } catch {
            armFallback.impactOccurred(intensity: 0.7)
        }
    }

    /// The finger lifted from an armed hold: one crisp tap.
    func release() {
        stopHold()
        guard supported, let engine else { liftFallback.impactOccurred(intensity: 1.0); return }
        do {
            try engine.start()
            let tap = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.75),
            ], relativeTime: 0)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [tap], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            liftFallback.impactOccurred(intensity: 1.0)
        }
    }

    /// A cancelled or interrupted hold has no release tap.
    func cancel() { stopHold() }

    private func stopHold() {
        try? hold?.stop(atTime: CHHapticTimeImmediate)
        hold = nil
    }

    private func makeEngine() {
        guard let engine = try? CHHapticEngine() else { return }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        engine.resetHandler = { [weak self] in
            Task { @MainActor in
                self?.hold = nil
                try? self?.engine?.start()
            }
        }
        engine.stoppedHandler = { [weak self] _ in
            Task { @MainActor in self?.hold = nil }
        }
        self.engine = engine
    }
}
