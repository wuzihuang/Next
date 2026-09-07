import SwiftUI
import UIKit

/// MOTION SPEC · 05 · FIRST RUN · FULL PAGE.
///
/// It boots as one screen, then folds into a page. On the very first entry to Home the whole
/// display *is* the panel — no status bar, no wordmark, no tiles, no dock — and at 5.20s that
/// one surface folds down to 358 × 470 and the rest of the page takes the space it gave up.
/// So the page is not faded in: it is handed the room the screen stepped out of.
///
///   ◇1  0.00  BLACK     one lime pixel, dead centre
///   ◇2  0.40  CORE      it bursts into a core; the backplate lifts to 20%. Backlight, not motion
///   ◇3  1.20  SWEEP     the orbit draws from the right, 0.8s ease-out. Growth, not a fade-in
///   ◇4  1.90  ALIVE     the planet starts 90s a revolution and never stops again
///   ◇5  2.60  TYPE      hairline opens from the centre, then Doto types at 28ms a character
///   ◇6  3.90  LIME      line one drops to white, line two comes in lime, 0.4s of silence between
///   ◇7  5.20  KEY       390×844 → 358×470, radius 44 → 30, 0.62s spring(0.82 / 0.34)
///   ◇8  5.60  TOP       status bar and wordmark slide in from −8px, 120ms apart
///   ◇9  6.10  STAGGER   the two tiles rise from +16px, left then right, 80ms apart
///   ◇10 6.70  INPUT     the dock's three keys land together — it is one tool, not three
///   ◇11 7.40  IDLE      the home indicator last. Two things still move, and only two.
@MainActor
final class FirstRun: ObservableObject {
    private static let key = LaunchFilmPolicy.firstRunPlayedKey

    enum Beat: Double, Comparable {
        case black = 0.00, core = 0.40, sweep = 1.20, alive = 1.90, type = 2.60
        case lime = 3.90, key = 5.20, top = 5.60, stagger = 6.10, input = 6.70, idle = 7.40

        static func < (a: Beat, b: Beat) -> Bool { a.rawValue < b.rawValue }
    }

    @Published private(set) var playing = false
    @Published private(set) var beat: Beat = .black
    /// How many characters of each subtitle line have been typed.
    @Published private(set) var typed: (first: Int, second: Int) = (0, 0)

    static var lineOne: String { L("I DON'T COACH.") }
    static var lineTwo: String { L("I READ YOU.") }
    static var lineThree: String { L("THE FIRST TARGET LANDS BY MORNING") }
    static var lineThreeUnpaired: String { L("PAIR YOUR BAND TO START") }

    private var task: Task<Void, Never>?

    /// Only after onboarding, only once. Reinstalling is the only way back.
    static var shouldPlay: Bool { !UserDefaults.standard.bool(forKey: key) }
    static func markPlayed() { UserDefaults.standard.set(true, forKey: key) }

    func start(reduceMotion: Bool, lowPower: Bool) {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["NB_DEBUG_FIRSTRUN_BEAT"], !raw.isEmpty {
            let named: [String: Beat] = [
                "black": .black, "core": .core, "sweep": .sweep, "alive": .alive,
                "type": .type, "lime": .lime, "key": .key, "top": .top,
                "stagger": .stagger, "input": .input, "idle": .idle,
            ]
            if let beat = named[raw] {
                playing = true
                self.beat = beat
                if beat >= .type {
                    typed = (Self.lineOne.count, beat >= .lime ? Self.lineTwo.count : 0)
                }
                return
            }
        }
        #endif
        if playing { return }
        guard Self.shouldPlay else { finish(); return }
        playing = true
        Self.markPlayed()

        // Reduce Motion: ◇1–◇7 are skipped and the whole page fades in over 0.3s,
        // with the subtitle shown at once rather than typed.
        if reduceMotion {
            typed = (Self.lineOne.count, Self.lineTwo.count)
            withAnimation(.easeOut(duration: 0.3)) { beat = .idle }
            end(after: 0.3)
            return
        }

        // Low Power Mode: only ◇7's fold survives, because the page still has to arrive
        // from somewhere. 0.4s, and nothing before it.
        if lowPower {
            typed = (Self.lineOne.count, Self.lineTwo.count)
            beat = .key
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { beat = .idle }
            end(after: 0.6)
            return
        }

        task = Task { await run() }
    }

    private func run() async {
        for step in [Beat.core, .sweep, .alive, .type, .lime, .key, .top, .stagger, .input, .idle] {
            let wait = step.rawValue - beat.rawValue
            try? await Task.sleep(for: .seconds(wait))
            guard playing else { return }

            switch step {
            case .key:
                // ⚠️ One view, animating frame and cornerRadius. Not a cross-fade between two.
                withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) { beat = step }
            case .top, .stagger, .input:
                // The top bar, the tiles and the dock share one spring and differ only in
                // when it starts: 0 / 0.50 / 1.10s measured from ◇7.
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { beat = step }
            default:
                beat = step
            }

            // The typing runs alongside the beats, not inside them: ◇5 → ◇6 is 1.30s and
            // fourteen characters at 28ms is 0.39s, so the budget is already there.
            // Awaiting it here would push the whole 7.40s out by more than a second.
            if step == .type {
                Task { await type(line: 1, text: Self.lineOne) }
            }
            if step == .lime {
                Task {
                    // 0.4s of silence between the two lines — the whole point of the pause.
                    try? await Task.sleep(for: .milliseconds(400))
                    await type(line: 2, text: Self.lineTwo)
                }
            }
        }
        end(after: 0)
    }

    /// 28ms a character. Not an opacity animation, and not a sequence of images.
    private func type(line: Int, text: String) async {
        for n in 1...text.count {
            guard playing else { return }
            if line == 1 { typed.first = n } else { typed.second = n }
            try? await Task.sleep(for: .milliseconds(28))
        }
    }

    /// Any tap at all lands on ◇11 — no "skip?" prompt, and the planet carries on from
    /// wherever it had turned to rather than starting over.
    func skip() {
        guard playing, beat < .idle else { return }
        task?.cancel()
        typed = (Self.lineOne.count, Self.lineTwo.count)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { beat = .idle }
        end(after: 0.42)
    }

    private func end(after delay: Double) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            finish()
        }
    }

    private func finish() {
        task?.cancel()
        playing = false
        beat = .idle
    }

    // MARK: what the layout asks it

    /// ◇7 · the panel is the whole screen until the fold, then it is 358 × 470.
    var panelIsFullScreen: Bool { playing && beat < .key }
    var panelRadius: CGFloat { panelIsFullScreen ? 44 : NB.R.hero }
    /// The core, the orbit and the crescent each arrive on their own beat.
    var coreLit: Bool { !playing || beat >= .core }
    var orbitFraction: Double { !playing ? 1 : (beat >= .sweep ? 1 : 0) }
    var orbitSpinning: Bool { !playing || beat >= .alive }
    var hairlineOpen: Bool { !playing || beat >= .type }
    /// The dock cannot be pressed before ◇10 — and when it cannot, it is simply not there.
    /// A greyed-out disabled state would be a fourth thing on a screen that has three.
    var chromeVisible: Bool { !playing || beat >= .top }
    var tilesVisible: Bool { !playing || beat >= .stagger }
    var dockVisible: Bool { !playing || beat >= .input }
    var indicatorVisible: Bool { !playing || beat >= .idle }
    /// The status bar is hidden for the ceremony and comes back with the top bar. It causes
    /// no layout shift, because the full-screen content was centred to begin with.
    var statusBarHidden: Bool { playing && beat < .top }
}

/// ◇2–◇4 · the core, the orbit and the planet, as one layer that is never rebuilt.
/// After the fold this same view is what the panel draws — it is not replaced, so the
/// field does not restart and does not blink.
struct FirstRunArt: View {
    var coreLit: Bool
    var orbitFraction: Double
    var spinning: Bool

    /// The clock survives across beats and across the fold; it only advances while the
    /// field is turning, so going to the background pauses it rather than skipping it.
    @State private var clock: Double = 0
    /// ◇3 · 0…1 over 0.8s. The sweep is drawn, not faded, so it needs its own progress —
    /// a Canvas has no implicit animation to inherit from the beat changing under it.
    @State private var sweep: Double = 0
    @State private var lastTick: Date?

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                OrbitField(clock: clock,
                           arrival: 1 - pow(1 - sweep, 2),   // ease-out
                           coreLit: coreLit,
                           moving: spinning)
                    .draw(in: &ctx, size: size)
            }
            .onChange(of: tl.date) { _, now in
                let previous = lastTick ?? now
                lastTick = now
                let dt = min(now.timeIntervalSince(previous), 1.0 / 20)
                if orbitFraction > 0 { sweep = min(1, sweep + dt / 0.8) }
                // ◇4 · from here the field never stops. 90 seconds a revolution.
                if spinning { clock += dt }
            }
        }
    }
}

/// ◇5–◇6 · the subtitle. Line one types, drops to white, then line two comes in lime.
struct FirstRunSubtitle: View {
    let typed: (first: Int, second: Int)
    let bandPaired: Bool
    var showsCursor: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text(String(FirstRun.lineOne.prefix(typed.first)))
                .font(NBFont.dot(700, 20)).tracking(0.14 * 20)
                // Line one steps back to white the moment line two starts.
                .foregroundStyle(typed.second > 0 ? NB.white : NB.lime1)

            HStack(spacing: 4) {
                Text(String(FirstRun.lineTwo.prefix(typed.second)))
                    .font(NBFont.dot(700, 20)).tracking(0.14 * 20)
                    .foregroundStyle(NB.lime1)
                // A lime square, and it does not blink: a dot screen has no need to.
                if showsCursor {
                    Rectangle().fill(NB.lime1).frame(width: 9, height: 9)
                }
            }

            Text(bandPaired ? FirstRun.lineThree : FirstRun.lineThreeUnpaired)
                .font(NBFont.dot(500, 11)).tracking(0.2 * 11)
                .foregroundStyle(NB.white.opacity(0.34))
                .padding(.top, 8)
                .opacity(typed.second == FirstRun.lineTwo.count ? 1 : 0)
        }
    }
}
