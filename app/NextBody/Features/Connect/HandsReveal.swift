import CoreHaptics
import SwiftUI
import UIKit

/// 02 · 05 CONNECTED · the choreography, as a function of seconds since the screen appeared.
///
/// One clock drives everything on the success screen — the print coming in, the hands
/// closing, the ring, the two lines typing, the button — so nothing here is a chain of
/// `asyncAfter`s that can drift apart. Every function is pure in `t`, which is also what
/// lets Reduce Motion show the finished picture by asking for a late `t`.
///
///     0.00  the print comes in, cell by cell, hands apart
///     0.35  the hands start to close
///     1.45  almost there — a held breath, a tremor in the fingertips
///     1.85  touch · haptic · the ring leaves the contact point
///     2.05  YOU'RE CONNECTED types in
///     2.85  「已经连上那个未来的你」 types in
///     3.40  the after-pulse begins, and keeps going
///     3.70  LINK LOCKED and the button
enum LinkChoreo {
    /// Where the fingertips meet, as a fraction of the picture. Measured off the asset.
    static let touchUV = CGPoint(x: 0.498, y: 0.497)
    /// Each hand starts this far from rest, in points, along the diagonal.
    static let gapMax: CGFloat = 150
    static let touchAt = 1.85
    static let titleAt = 2.05
    static let subtitleAt = 2.85
    static let pulseFrom = 3.40
    static let pulsePeriod = 2.6
    static let footerAt = 3.70

    static func printIn(_ t: Double) -> Double { easeOut(clamp01(t / 0.7)) }

    static func approach(_ t: Double) -> Double {
        if t < 0.35 { return 0 }
        if t < 1.45 { return 0.92 * easeInOut((t - 0.35) / 1.1) }
        // The hesitation: held at a hair's breadth, with a tremor.
        if t < 1.75 { return 0.92 + 0.006 * sin((t - 1.45) * 28) }
        return 0.92 + 0.08 * easeIn(clamp01((t - 1.75) / 0.10))
    }

    /// Ring radius in points. `maxR` is what the shader treats as "off the frame".
    static func reveal(_ t: Double, maxR: Double) -> Double {
        t < touchAt ? 0 : 1.02 * maxR * easeOut(clamp01((t - touchAt) / 1.4))
    }

    static func spark(_ t: Double) -> Double { t < touchAt ? 0 : exp(-(t - touchAt) * 2.6) }

    /// Phase 0…1 of the after-pulse, or −1 before it starts.
    static func pulse(_ t: Double) -> Double {
        t < pulseFrom ? -1 : (t - pulseFrom).truncatingRemainder(dividingBy: pulsePeriod) / pulsePeriod
    }

    static func burst(_ t: Double) -> Double { t < touchAt ? 0 : easeOut(clamp01((t - touchAt) / 0.9)) }
    static func burstAlpha(_ t: Double) -> Double {
        t < touchAt ? 0 : 1 - smooth(clamp01((t - touchAt - 1.1) / 1.3))
    }

    static func title(_ t: Double) -> Double { clamp01((t - titleAt) / 0.75) }
    static func subtitle(_ t: Double) -> Double { clamp01((t - subtitleAt) / 1.0) }
    static func footer(_ t: Double) -> Double { easeOut(clamp01((t - footerAt) / 0.5)) }

    /// 0 before the touch, 1 from the touch, 2 from the title. Each step is one haptic.
    static func hapticStage(_ t: Double) -> Int { t < touchAt ? 0 : (t < titleAt ? 1 : 2) }

    /// A `t` past everything, for Reduce Motion and previews.
    static let finished = 10.0

    /// Which replay this is. 0 unless the loop hook is on, and one more each time it wraps —
    /// which is what re-fires the haptic score on a looped run.
    static func cycle(_ elapsed: Double) -> Int {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["NB_DEBUG_LINK_LOOP"] else { return 0 }
        let period = max(footerAt + 1.5, Double(raw) ?? 7.0)
        return Int(elapsed / period)
        #else
        return 0
        #endif
    }

    /// `SIMCTL_CHILD_NB_DEBUG_LINK_LOOP=1` replays the whole thing on a loop so it can be
    /// watched over and over on a simulator; `=<seconds>` sets the period. Release builds
    /// and every unset run play it once.
    static func looped(_ elapsed: Double) -> Double {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["NB_DEBUG_LINK_LOOP"] else { return elapsed }
        let period = max(footerAt + 1.5, Double(raw) ?? 7.0)
        return elapsed.truncatingRemainder(dividingBy: period)
        #else
        return elapsed
        #endif
    }

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    private static func easeIn(_ x: Double) -> Double { x * x * x }
    private static func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    private static func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}

/// The two hands. One photograph, one fragment shader (`HandsReveal.metal`), driven by
/// `LinkChoreo` off the clock the screen hands it. The picture is drawn in its own frame;
/// `size` must be that frame, because the shader needs it in points.
struct HandsLink: View {
    let clock: Double
    let size: CGSize
    var cell: CGFloat = 4

    var body: some View {
        // The picture fills the width; a shorter frame (an SE) crops it top and bottom
        // equally, so the meeting point is measured off the scaled picture, not the frame.
        let pictureHeight = size.width * 4 / 3
        let touch = CGPoint(x: size.width * LinkChoreo.touchUV.x,
                            y: pictureHeight * LinkChoreo.touchUV.y - (pictureHeight - size.height) / 2)
        let maxR = Double(hypot(size.width, size.height)) * 0.62
        let reach = LinkChoreo.gapMax + 24
        Image("HandsReach")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .clipped()
            .layerEffect(ShaderLibrary.nbHandsReveal(
                .float2(size),
                .float(cell),
                .float(clock),
                .float(LinkChoreo.printIn(clock)),
                .float(LinkChoreo.approach(clock)),
                .float(LinkChoreo.reveal(clock, maxR: maxR)),
                .float(LinkChoreo.gapMax),
                .float2(touch),
                .float(LinkChoreo.spark(clock)),
                .float(LinkChoreo.pulse(clock)),
                .color(NB.panelInk),
                .color(NB.lime1),
                .color(NB.limePale),
                .color(NB.white)
            ), maxSampleOffset: CGSize(width: reach, height: reach))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 02 · 05 CONNECTED · the link, felt. One Core Haptics score, scheduled against the same
/// clock the picture runs on, rather than a generator fired when a stage flips.
///
/// The moment is a contact, and a contact has a shape: a rumble that grows for a second and
/// a half while the hands close, a stall and three small tremors at the hesitation, one hard
/// strike at the fingertips, then a decay that empties out as the ring leaves the frame.
/// `.success` is somebody else's three-beat notification and says "your form was submitted";
/// it has nothing to do with this picture. The two later taps ride the lines typing in, so
/// the words land in the hand as well as on the screen.
@MainActor
final class LinkHaptics {
    static let shared = LinkHaptics()

    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?

    /// False on a simulator and on hardware with no Taptic Engine, which is what the screen
    /// checks before it keeps its own fallback taps.
    var isSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    /// Warm the engine before the clock is stamped: starting it is the expensive part, and
    /// the first event is only 450 ms in.
    func prepare() {
        guard engine == nil, isSupported else { return }
        do {
            let engine = try CHHapticEngine()
            // The score runs almost four seconds; an engine that shuts itself down when idle
            // would take the strike with it.
            engine.isAutoShutdownEnabled = false
            engine.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            engine.stoppedHandler = { _ in }
            try engine.start()
            self.engine = engine
        } catch {
            #if DEBUG
            print("NB_HAPTIC link engine failed to start (\(error))")
            #endif
        }
    }

    /// `still` is Reduce Motion: the screen shows the finished picture at once, so there is
    /// no approach to track and only the contact is played.
    func play(still: Bool) {
        prepare()
        guard let engine else { return }
        do {
            let player = try engine.makePlayer(with: try CHHapticPattern(events: still ? Self.contactOnly()
                                                                                       : Self.score(),
                                                                         parameterCurves: still ? []
                                                                                                : Self.curves()))
            try player.start(atTime: CHHapticTimeImmediate)
            self.player = player
        } catch {
            #if DEBUG
            print("NB_HAPTIC link score failed (\(error))")
            #endif
        }
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        engine?.stop()
        engine = nil
    }

    // MARK: the score

    private static let rumbleFrom = 0.45
    private static var rumbleTo: Double { LinkChoreo.touchAt - 0.06 }

    private static func score() -> [CHHapticEvent] {
        var events: [CHHapticEvent] = []

        // The closing. One continuous event, low and blunt, whose intensity is driven by the
        // curve below — a rumble that grows is the hands having further to go.
        events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
            .init(parameterID: .hapticIntensity, value: 0.62),
            .init(parameterID: .hapticSharpness, value: 0.10),
        ], relativeTime: rumbleFrom, duration: rumbleTo - rumbleFrom))

        // The hesitation, 1.45 to 1.75 on the screen: three small dry taps, the tremor in the
        // fingertips. Small and sharp, because a soft one at this size is a thud.
        for (i, at) in [1.47, 1.585, 1.70].enumerated() {
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: Float(0.16 + 0.04 * Double(i))),
                .init(parameterID: .hapticSharpness, value: 0.80),
            ], relativeTime: at))
        }

        // Contact. The hardest thing on the screen, and the only event at full intensity.
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticIntensity, value: 1.0),
            .init(parameterID: .hapticSharpness, value: 0.92),
        ], relativeTime: LinkChoreo.touchAt))

        // What the strike leaves behind: a body that empties out while the ring crosses the
        // frame. Blunt, so it reads as a resonance and not as a second hit.
        events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
            .init(parameterID: .hapticIntensity, value: 0.80),
            .init(parameterID: .hapticSharpness, value: 0.28),
        ], relativeTime: LinkChoreo.touchAt + 0.02, duration: 0.90))

        // The two lines landing, and the button arriving under them.
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticIntensity, value: 0.42),
            .init(parameterID: .hapticSharpness, value: 0.62),
        ], relativeTime: LinkChoreo.titleAt))
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticIntensity, value: 0.22),
            .init(parameterID: .hapticSharpness, value: 0.45),
        ], relativeTime: LinkChoreo.subtitleAt))
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
            .init(parameterID: .hapticIntensity, value: 0.30),
            .init(parameterID: .hapticSharpness, value: 0.50),
        ], relativeTime: LinkChoreo.footerAt))

        return events
    }

    private static func curves() -> [CHHapticParameterCurve] {
        let span = rumbleTo - rumbleFrom
        return [
            // Barely there for the first half, then steep — the same ease the hands close on.
            CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: 0.05),
                .init(relativeTime: span * 0.55, value: 0.28),
                .init(relativeTime: span * 0.85, value: 0.62),
                .init(relativeTime: span, value: 1.0),
            ], relativeTime: rumbleFrom),
            // The resonance after the strike, gone before the title types in.
            CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: 1.0),
                .init(relativeTime: 0.30, value: 0.34),
                .init(relativeTime: 0.90, value: 0.0),
            ], relativeTime: LinkChoreo.touchAt + 0.02),
        ]
    }

    /// Reduce Motion · the contact alone, on the first beat.
    private static func contactOnly() -> [CHHapticEvent] {
        [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: 1.0),
                .init(parameterID: .hapticSharpness, value: 0.92),
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                .init(parameterID: .hapticIntensity, value: 0.45),
                .init(parameterID: .hapticSharpness, value: 0.28),
            ], relativeTime: 0.02, duration: 0.45),
        ]
    }
}

/// A line typing itself in: the finished line lays out invisibly so nothing shifts while
/// the letters arrive, and a block cursor sits at the end until the last one lands.
struct TypeIn: View {
    let text: String
    /// 0…1 · fraction of the characters shown.
    let progress: Double
    let font: Font
    let tracking: CGFloat
    let size: CGFloat
    let color: Color

    var body: some View {
        let chars = Array(text)
        let n = Int((Double(chars.count) * progress).rounded(.down))
        let shown = String(chars.prefix(n))
        ZStack(alignment: .leading) {
            Text(text).font(font).tracking(tracking).opacity(0)
            HStack(alignment: .center, spacing: 0) {
                Text(shown).font(font).tracking(tracking).foregroundStyle(color)
                if progress > 0 && progress < 1 {
                    Rectangle().fill(color)
                        .frame(width: size * 0.55, height: size * 1.0)
                        .offset(x: n == 0 ? 0 : -tracking * 0.5)
                }
            }
        }
        .fixedSize()
        .opacity(progress > 0 ? 1 : 0)
        .accessibilityLabel(text)
    }
}

#if DEBUG
#Preview("Connected · finished") {
    ZStack {
        NB.panelInk
        HandsLink(clock: LinkChoreo.finished, size: CGSize(width: 390, height: 520))
            .frame(width: 390, height: 520)
    }
}
#endif
