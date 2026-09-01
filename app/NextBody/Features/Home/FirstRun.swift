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
    private static let key = "nb.firstRunPlayed"

    enum Beat: Double, Comparable {
        case black = 0.00, core = 0.40, sweep = 1.20, alive = 1.90, type = 2.60
        case lime = 3.90, key = 5.20, top = 5.60, stagger = 6.10, input = 6.70, idle = 7.40

        static func < (a: Beat, b: Beat) -> Bool { a.rawValue < b.rawValue }
    }

    @Published private(set) var playing = false
    @Published private(set) var beat: Beat = .black
    /// How many characters of each subtitle line have been typed.
    @Published private(set) var typed: (first: Int, second: Int) = (0, 0)

    static let lineOne = "I DON'T COACH."
    static let lineTwo = "I READ YOU."
    static let lineThree = "THE FIRST TARGET LANDS BY MORNING"
    static let lineThreeUnpaired = "PAIR YOUR BAND TO START"

    private var task: Task<Void, Never>?

    /// Only after onboarding, only once. Reinstalling is the only way back.
    static var shouldPlay: Bool { !UserDefaults.standard.bool(forKey: key) }
    static func markPlayed() { UserDefaults.standard.set(true, forKey: key) }

    func start(reduceMotion: Bool, lowPower: Bool) {
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
/// planet does not restart and does not blink.
struct FirstRunArt: View {
    var coreLit: Bool
    var orbitFraction: Double
    var spinning: Bool

    /// Angle survives across beats and across the fold; it only advances while on screen,
    /// so going to the background pauses it and coming back continues from where it stopped.
    @State private var angle: Double = 0
    @State private var lastTick: Date?

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / 358, sy = geo.size.height / 470
            let s = min(sx, sy)
            let c = CGPoint(x: geo.size.width / 2, y: 196 * sy)

            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    // ◇2 · the backplate lifts to 20%. It is lit, not moved.
                    ctx.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .color(NB.panelWash.opacity(coreLit ? 1 : 0.2)))

                    // ◇3 · the orbit draws from the right rather than fading in.
                    if orbitFraction > 0 {
                        var orbit = Path()
                        orbit.addArc(center: c, radius: 126 * s,
                                     startAngle: .degrees(0),
                                     endAngle: .degrees(360 * orbitFraction),
                                     clockwise: false)
                        ctx.scaleBy(x: 1, y: 0.27)
                        ctx.translateBy(x: 0, y: c.y * (1 / 0.27 - 1))
                        ctx.stroke(orbit, with: .color(NB.violet2.opacity(0.5)),
                                   lineWidth: 3 * s / 0.27 * 0.27)
                        ctx.transform = .identity
                    }

                    // ◇1 · one lime pixel, then the core it bursts into.
                    let coreR = coreLit ? 6 * s : 1.5 * s
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - coreR, y: c.y - coreR,
                                                    width: coreR * 2, height: coreR * 2)),
                             with: .color(NB.lime1))

                    // ◇3 · the lime crescent grows alongside the orbit, to half.
                    if orbitFraction > 0 {
                        var crescent = Path()
                        crescent.addArc(center: c, radius: 74 * s,
                                        startAngle: .degrees(-55),
                                        endAngle: .degrees(-55 + 140 * orbitFraction),
                                        clockwise: false)
                        ctx.stroke(crescent, with: .color(NB.lime1),
                                   style: StrokeStyle(lineWidth: 7 * s, lineCap: .round))
                    }

                    // ◇4 · from here the planet never stops. 90 seconds a revolution.
                    if spinning {
                        let a = angle * .pi / 180
                        let planet = CGPoint(x: c.x + 126 * s * cos(a),
                                             y: c.y + 34 * s * sin(a))
                        ctx.fill(Path(ellipseIn: CGRect(x: planet.x - 6 * s, y: planet.y - 6 * s,
                                                        width: 12 * s, height: 12 * s)),
                                 with: .color(NB.lime1))
                    }

                    _ = tl.date
                }
                .onChange(of: tl.date) { _, now in
                    guard spinning else { lastTick = now; return }
                    let previous = lastTick ?? now
                    lastTick = now
                    // 360° in 90s. Driven by elapsed on-screen time, so a trip to the
                    // background pauses it instead of skipping it forward.
                    angle += now.timeIntervalSince(previous) * 4
                }
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
