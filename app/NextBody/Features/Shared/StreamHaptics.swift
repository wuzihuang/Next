import CoreHaptics
import UIKit

/// The stream you can feel. While she is thinking, the panel types her reasoning out one
/// character at a time and the chat prints the same lines under the keyboard — both of them
/// silent until now. This is the other half of that: a hair-light transient under the
/// characters as they land, a firmer one when a line is whole, and one crisp tap when the
/// turn is over.
///
/// Three rules keep it from turning into a buzz:
/// * the typing tick is throttled — the panel types at 46 characters a second, and anything
///   over ~12 taps a second stops reading as typing and starts reading as a motor;
/// * intensity is low and sharpness mid — a keyboard tap, not an alert;
/// * Reduce Motion, Low Power Mode and hardware without a haptic engine get nothing rather
///   than a coarse UIKit thud on every character. The line and turn taps still land.
@MainActor
final class StreamHaptics {
    static let shared = StreamHaptics()

    private var engine: CHHapticEngine?
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    /// Devices without Core Haptics only ever get the two coarse events.
    private let lineFallback = UIImpactFeedbackGenerator(style: .soft)
    private let settleFallback = UIImpactFeedbackGenerator(style: .rigid)

    /// Fastest the character tick may repeat. 46 cps typing lands roughly every fourth
    /// character, which is the cadence of a fast typist rather than a vibration.
    private static let typeInterval: TimeInterval = 0.085
    private var lastType: TimeInterval = 0
    private var lastLine: TimeInterval = 0
    private var active = false

    private init() {}

    /// A turn started. Warm the engine so the first character does not arrive ahead of it.
    func activate() {
        guard !active else { return }
        active = true
        lineFallback.prepare()
        settleFallback.prepare()
        guard quiet == false, supported else { return }
        if engine == nil { makeEngine() }
        try? engine?.start()
    }

    /// The turn ended, or the screen went away. The engine idles out on its own; this only
    /// drops the gate so a stale stream cannot keep tapping.
    func deactivate() {
        active = false
    }

    /// One character landed. Cheap, throttled, and skipped entirely when the turn is not live.
    func type() {
        guard active, !quiet, supported else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastType >= Self.typeInterval else { return }
        lastType = now
        play(intensity: 0.26, sharpness: 0.62)
    }

    /// A whole line of her reasoning arrived. Softer and rounder than a character so the two
    /// are distinguishable through a pocket.
    func lineLanded() {
        guard active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLine >= 0.12 else { return }
        lastLine = now
        lastType = now
        guard !quiet else { return }
        guard supported else { lineFallback.impactOccurred(intensity: 0.55); return }
        play(intensity: 0.5, sharpness: 0.35)
    }

    /// The turn is over and the answer is on screen. One needle — a single high-sharpness
    /// transient, no continuous body. Sharpness 1 is the Taptic Engine's top click (~230 Hz);
    /// a mid-band tap plus any sustained body reads as a dirty knock. It fires even under
    /// Reduce Motion: it is an outcome, not decoration.
    func settled() {
        guard HapticsSetting.shared.enabled else { return }
        guard supported else { settleFallback.impactOccurred(intensity: 0.9); return }
        if engine == nil { makeEngine() }
        try? engine?.start()
        guard let engine else { settleFallback.impactOccurred(intensity: 0.9); return }
        do {
            let tap = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
            ], relativeTime: 0)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [tap], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            settleFallback.impactOccurred(intensity: 0.9)
        }
    }

    /// Reduce Motion and Low Power Mode both mean: do not run a motor for texture. The
    /// person's own switch in ME → PREFERENCES silences everything, including the outcomes.
    private var quiet: Bool {
        !HapticsSetting.shared.enabled
            || UIAccessibility.isReduceMotionEnabled
            || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func play(intensity: Float, sharpness: Float) {
        guard let engine else { return }
        do {
            let tap = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: 0)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [tap], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // A dropped tick is not worth a fallback thud; the next character brings another.
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
