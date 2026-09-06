import SwiftUI
import UIKit

/// 06 · 02–04 · the measurement takeover.
/// It is not a new page — it is the panel grown to full screen, so the only way out is the
/// close mark. 358×470 → full bleed in 0.46s, corner radius held.
///
/// Choreography: the finger arrives, the band answers, the number writes itself,
/// then the whole thing folds back into the panel as one widget.
struct MeasureTakeover: View {
    let kind: MeasureKind
    let done: () -> Void

    /// F1 rule 05 · the takeover's only exit is the close mark, and the measurement has to be
    /// stopped before it goes. Cancelling this task terminates the stream, and each
    /// implementation stops the test in its `onTermination`.
    @State private var run: Task<Void, Never>?

    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router
    /// 06 · 19 · body composition has no waveform; progress is the fields themselves.
    @State private var fields = 0

    enum Phase: Hashable {
        case opening, waiting, nudge, contact, counting, halfway, lost, computing, result, failed
        // 06 edges · the four device-side states are 32% + a Doto line, never amber (rule 07).
        case notWearing, busy, dropped, noReading
    }

    @State private var phase: Phase = .opening
    @State private var remaining: Int = 60
    @State private var lostGrace: Double = 3
    @State private var grown = false
    @State private var reading: PartialReading?
    @State private var failure: String?
    /// True once the stream has carried the band's own seconds; the phone's clock then
    /// stops counting, so the number on screen is the scan's and never runs ahead of it.
    @State private var bandClock = false
    /// When `remaining` last moved — the body figure hops from this instant.
    @State private var beatAt = Date()
    /// Beats the band reported during this Battery Check. The number on screen is the
    /// median of a short window of these — never a single spike from a settling sensor.
    @State private var hrSamples: [Int] = []

    /// 06 · how far into the balance check, 0…1. The field's brightness and travel follow it,
    /// so the screen visibly gathers instead of looping at one intensity for forty seconds.
    @State private var studyProgress: Double = 0

    private var isBodyScan: Bool { kind == .bodyComposition }
    /// 06 · the balance check. ⚠️ The kind is still `.ecg` because that is the SDK command
    /// underneath; nothing the user reads ever says so — see `measurePulseStudy`.
    private var isBalance: Bool { kind == .ecg }
    /// Measured on a real HOOP: the balance check runs 40 s, the body scan 30, the heart leg 60.
    private var total: Int { isBodyScan ? 30 : isBalance ? 40 : 60 }

    private let secondHand = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            NB.panelInk.ignoresSafeArea()

            // 06 · the field is the SCREEN, not a panel in the middle of one. A rectangle of
            // animation with the page's ground on either side reads as a component that
            // failed to fill; this is a window onto something the whole surface is part of.
            // ⚠️ Drawn behind everything and never taking a touch — the close mark is still
            // the only way out of this screen (F1 rule 05).
            if isBalance, balanceFieldVisible {
                BreathingDots(bpm: balanceTempo,
                              intensity: 0.25 + 0.75 * studyProgress,
                              held: phase == .lost)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    // The words sit over the field, so the field gives them a ground: darkest
                    // where the type is, open through the middle where the pattern lives.
                    // ⚠️ NO scrim over the field. Two attempts at one — 92 % ink over a
                    // short ramp, then 72 % over a long one — both read as black bars against
                    // the status bar and the home indicator, because any darkening that
                    // reaches the edge IS an edge. The words carry their own ground instead
                    // (`overFieldShadow`), and the field runs to all four sides.
                    .transition(.opacity)
            }

            // 06 · the three alternative layouts, for comparing on the wrist rather than as
            // pictures — `NB_DEBUG_BALANCE_STYLE`. They replace the column below entirely;
            // the field, the close mark and every rule about what may be printed are shared.
            if isBalance, BalanceLayout.current != .original {
                balanceVariant
            } else {
            // 06 · E/F · the board's column, centred: the eyebrow and the close mark, one
            // sentence, the band, the count, and the two lines at the foot. Nothing here is
            // left-aligned — the instruction is about the band, and the band is the middle.
            VStack(spacing: 0) {
                Color.clear.frame(height: ScreenMetrics.safeArea.top + Chrome.gateTopInset)
                header
                instruction
                    .padding(.top, 32)
                    .modifier(OverFieldShadow(on: isBalance && balanceFieldVisible))
                settled
                stage
                    .frame(maxHeight: .infinity)
                count
                Spacer(minLength: 0)
                // The Doto line is the state, not a command.
                Text(statusLine)
                    .font(NBFont.dot(600, 10.5)).tracking(0.16 * 10.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(statusTint)
                    .frame(width: NB.Layout.contentWidth)
                    .modifier(OverFieldShadow(on: isBalance && balanceFieldVisible))
                // Grey, in front — what to do if it breaks, said before it breaks.
                Text(helpLine)
                    .font(NBFont.ui(300, 12.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NB.white.opacity(0.42))
                    .modifier(OverFieldShadow(on: isBalance && balanceFieldVisible))
                    .frame(width: 318)
                    .padding(.top, 18)
                Color.clear.frame(height: 26)
            }
            .animation(.easeInOut(duration: 0.24), value: phase)
            .opacity(grown ? 1 : 0)
            }
        }
        .scaleEffect(grown ? 1 : 0.92)
        // ⚠️ The clip has to ignore the safe area too. It exists for the 460 ms fold, when
        // this screen is still panel-shaped and needs the panel's corner radius — but it
        // clips to THIS view's bounds, and those stop at the safe area. Everything inside
        // that said `ignoresSafeArea` was expanding into a region the clip then cut off,
        // which is the black band under the status bar and over the home indicator. Three
        // attempts went into the scrim before the cut turned out to be here.
        .clipShape(RoundedRectangle(cornerRadius: grown ? 0 : NB.R.hero, style: .continuous))
        // ⚠️ The CLIP is what has to ignore the safe area, so the field can reach the screen's
        // edges — but this modifier applies to the whole subtree, and the first version of it
        // took the type along: the eyebrow slid up under the system clock. Everything that is
        // words puts the inset back for itself (`Chrome.gateTopInset` plus the real one).
        .ignoresSafeArea()
        .onAppear { open() }
        .onReceive(secondHand) { _ in tick() }
        .onChange(of: remaining) { beatAt = Date() }
        .statusBarHidden(false)
    }

    /// The board's header: what is being measured, in lime, on the left; the only way out on
    /// the right. 06 · the close mark is the sole exit — nothing on this screen times out.
    private var header: some View {
        HStack(spacing: 0) {
            Text(eyebrow)
                .font(NBFont.dot(600, 11)).tracking(0.24 * 11)
                // ⚠️ White over the field, not the usual lime. Lime on a lime-heavy point
                // cloud with a red/green/blue fringe was unreadable — the one colour the
                // field never produces on its own is white, so it is the only one that still
                // reads as text rather than as more of the pattern.
                .foregroundStyle(isBalance && balanceFieldVisible ? NB.white.opacity(0.92) : NB.lime1)
            Spacer(minLength: 0)
            Button(action: leave) { CloseMark() }
                .buttonStyle(.plain)
                .frame(width: 44, height: 34)
                .opacity(phase == .opening ? 0 : 1)
        }
        .frame(width: NB.Layout.contentWidth, height: 34)
    }

    /// One sentence, centred, in the panel voice. The board carries no paragraph under it:
    /// a second block of prose under the instruction is a thing to read, and the user is
    /// meant to be looking at their wrist.
    private var instruction: some View {
        Text(headlineText)
            .font(NBFont.brand(500, 20)).tracking(-0.01 * 20)
            .multilineTextAlignment(.center)
            .foregroundStyle(NB.text1)
            .contentTransition(.opacity)
            .frame(width: 318)
    }

    /// The count is the board's own: Doto, big, white while it runs, amber the moment a
    /// finger comes off — and it holds where it stopped rather than falling to zero.
    @ViewBuilder private var count: some View {
        switch phase {
        case .opening, .waiting, .nudge, .contact, .failed, .busy, .dropped, .noReading, .notWearing:
            Color.clear.frame(height: 0)
        default:
            Text(String(format: "00:%02d", max(0, remaining)))
                .font(NBFont.dot(700, 52)).tracking(0.04 * 52)
                .foregroundStyle(phase == .lost ? NB.ember1 : NB.text1)
                .modifier(OverFieldShadow(on: isBalance && balanceFieldVisible))
                .frame(height: 56)
                .contentTransition(.numericText(countsDown: true))
        }
    }

    /// The one thing 03 has no room for: the number the band has already settled. It lands in
    /// the empty half of the screen, so nothing above it moves when it arrives.
    @ViewBuilder private var settled: some View {
        if phase == .halfway || phase == .lost, reading != nil {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(firstNumber)
                        .font(NBFont.brand(700, 34)).tracking(-0.045 * 34)
                        .foregroundStyle(phase == .lost ? NB.white.opacity(0.32) : NB.text1)
                    Text(isBodyScan ? "%" : L("BPM"))
                        .font(NBFont.dot(500, 12))
                        .foregroundStyle(NB.white.opacity(phase == .lost ? 0.20 : 0.42))
                }
                Text(isBodyScan ? L("BODY FAT · SETTLED")
                     : isBalance ? L("HEART RATE · MEASURING") : L("HEART RATE · SETTLED"))
                    .font(NBFont.dot(500, 10)).tracking(0.2 * 10)
                    .foregroundStyle(NB.white.opacity(phase == .lost ? 0.20 : 0.34))
            }
            .padding(.top, 22)
            .transition(.opacity)
        }
    }

    /// The eyebrow: what is being measured and how long it takes, in 03's own words.
    private var eyebrow: String {
        isBodyScan ? L("BODY SCAN · 30S") : isBalance ? L("BALANCE CHECK · 40S") : L("BATTERY CHECK · 60S")
    }

    private var headlineText: String {
        switch phase {
        // Opening borrows waiting's words: a sentence under an empty line reads as a screen
        // that failed to draw, and this phase is 460 ms of exactly that.
        // The board's own words: which finger, and which key. 「Finger on the key」 with a ring
        // around the display was an instruction to press the screen.
        case .opening, .waiting: L("Index finger on the side key.")
        case .nudge:     L("Still nothing on the key.")
        case .contact:   L("Got it. Hold still.")
        case .counting:  isBodyScan ? L("Mapping you.") : isBalance ? L("Listening to your rhythm.") : L("Reading you.")
        case .halfway:   L("Halfway.")
        case .lost:      L("Put it back.")
        case .computing: L("Working it out.")
        case .result:    isBodyScan ? L("Fourteen fields.") : isBalance ? L("Rest and drive.") : L("Done.")
        case .failed:    L("That didn't take.")
        case .notWearing: L("The band isn't on your wrist.")
        case .busy:       L("She's already measuring something.")
        case .dropped:    L("Lost the band.")
        case .noReading:  L("Couldn't get a clean read.")
        }
    }

    /// The figure is the band itself, at the board's size. A body scan has no waveform, so
    /// the current walks the body; a battery check really does read the heart, so it keeps
    /// the trace — over the band, dimmed to 14 %, the way E05 draws it.
    @ViewBuilder private var stage: some View {
        switch phase {
        case .opening, .waiting:
            BandFigure(tint: NB.lime1, mode: .ripple)
        case .nudge, .notWearing:
            // Amber is the first time this flow uses colour: it means "we need you to move",
            // never "you failed". Only the key and its ripples change — the layout does not.
            BandFigure(tint: NB.ember1, mode: .ripple)
        case .contact:
            if isBodyScan {
                BandFigure(tint: NB.lime1, mode: .contact)
            } else if isBalance {
                balanceStage
            } else {
                // Pulse monitor from the moment contact lands — flat until the first rate,
                // so the wait is not a second screen that only appears once a number exists.
                ZStack {
                    BandFigure(tint: NB.lime1, mode: .lit).opacity(0.14)
                    LiveECG(bpm: reading?.heartRate,
                            tint: NB.lime1,
                            amplitude: 1)
                        .frame(height: 96)
                }
            }
        case .failed, .busy, .dropped, .noReading:
            // Nothing is drawn where the reading would have been: an empty frame in that
            // position would read as a number we could not print.
            Color.clear
        default:
            if isBodyScan {
                // ⚠️ No band behind the body. Once the current is running it is inside the
                // user, not on the wrist — and a band still lit in the background is a second
                // subject on a screen that has one. G·02 draws the scan and nothing else.
                //
                // 06 edge 2 · a lifted finger freezes the figure where it was and turns it
                // amber. Computing and the result hold the whole body lit: it has been read,
                // and draining it at the end would say the reading went away.
                BodyFill(beat: phase == .computing || phase == .result ? total : total - remaining,
                         total: total, beatAt: beatAt, held: phase == .lost)
                    // The figure is drawn to the height it is given, so the height is the size:
                    // 03 · Scanning's own 280, not whatever room the page happens to have left.
                    .frame(height: 280)
            } else if isBalance {
                balanceStage
            } else {
                ZStack {
                    // E05 · the band stays for the recovery check — the reading is happening
                    // at the wrist, and the pulse trace is written over it at 14 %.
                    // ⚠️ Not an ECG channel: this HOOP's Battery Check is PPG heart rate
                    // (F5), shaped into a monitor sweep from the measured BPM.
                    BandFigure(tint: NB.lime1, mode: .lit).opacity(0.14)
                    LiveECG(bpm: reading?.heartRate,
                            tint: phase == .lost ? NB.ember2 : NB.lime1,
                            amplitude: phase == .computing ? 0 : 1)
                        .frame(height: 96)
                }
            }
        }
    }

    /// 06 · what is left in the stage slot once the field became the whole screen: the one
    /// line that says where the tempo is coming from. The field itself is drawn behind
    /// everything — see `body`.
    ///
    /// ⚠️ The field is deliberately NOT a heart trace. Drawing one would make this a
    /// different kind of product in the United States, so the measurement's own signal drives
    /// an abstract field instead: the dots breathe once per measured beat. When the band
    /// stops reporting a rate the field holds a resting tempo and dims — it never invents a
    /// pulse to keep the motion going.
    private var balanceStage: some View {
        VStack {
            Spacer(minLength: 0)
            Text(balanceSourceLine)
                .font(NBFont.dot(500, 9.5)).tracking(0.18 * 9.5)
                .foregroundStyle(NB.white.opacity(0.42))
                .modifier(OverFieldShadow(on: isBalance && balanceFieldVisible))
        }
    }

    /// One of the three alternatives, each keeping the eyebrow and the close mark at the top
    /// and the help line at the foot — those are the way out and the way to fix it, and no
    /// layout experiment gets to move them.
    @ViewBuilder private var balanceVariant: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: ScreenMetrics.safeArea.top + Chrome.gateTopInset)
            header
                // The eyebrow sits on the field like everything else, so it gets the same halo.
                .modifier(OverFieldShadow(on: balanceFieldVisible))
            switch BalanceLayout.current {
            case .header:
                BalanceHeader(bpm: balanceTempo, source: balanceSourceLine,
                              remaining: remaining, total: total, status: statusLine,
                              tint: phase == .lost ? NB.ember1 : NB.lime1,
                              over: balanceFieldVisible)
                    .padding(.top, 24)
                Spacer(minLength: 0)
            case .dashboard:
                BalanceDashboard(bpm: balanceTempo, remaining: remaining, total: total,
                                 contact: phase != .lost && phase != .notWearing,
                                 over: balanceFieldVisible,
                                 tint: NB.lime1)
                    .padding(.top, 22)
                Spacer(minLength: 0)
                Text(headlineText)
                    .font(NBFont.brand(500, 18)).tracking(-0.01 * 18)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NB.text1)
                    .frame(width: 318)
                    .modifier(OverFieldShadow(on: balanceFieldVisible))
            case .monolith:
                Spacer(minLength: 0)
                BalanceMonolith(bpm: balanceTempo, source: balanceSourceLine,
                                remaining: remaining,
                                tint: phase == .lost ? NB.ember1 : NB.lime1,
                                over: balanceFieldVisible)
                Spacer(minLength: 0)
                // The sentence lives at the foot, directly over the help line — the two read
                // as one block there, where under the number it was a third centred thing
                // competing with the count.
                BalanceFootLine(headline: headlineText, over: balanceFieldVisible)
                    .padding(.bottom, 10)
            case .original:
                EmptyView()
            }
            Text(helpLine)
                .font(NBFont.ui(300, 12.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(NB.white.opacity(0.42))
                .modifier(OverFieldShadow(on: balanceFieldVisible))
                .frame(width: 318)
                .padding(.top, 18)
            Color.clear.frame(height: ScreenMetrics.safeArea.bottom + 18)
        }
        .animation(.easeInOut(duration: 0.24), value: phase)
        .opacity(grown ? 1 : 0)
    }

    /// What the field breathes at.
    ///
    /// ⚠️ This firmware reports NOTHING during the run: `muHearts` stays empty and `aveHeart`
    /// is a dash for all forty seconds, and then the rate and forty-one intervals arrive
    /// together in the final callback. Gating the field on "a rate from this measurement"
    /// therefore left the screen empty until second thirty-five.
    /// So the tempo is the most recent rate this wrist actually produced — the panel's own
    /// live readout, measuring seconds before the plus key was pressed — until this run has
    /// one of its own. Both are measured; neither is invented; the line under it says which.
    private var balanceTempo: Int? { reading?.heartRate ?? LiveReadout.shared.hr }

    private var balanceSourceLine: String {
        if let hr = reading?.heartRate { return "\(hr) BPM · FROM THIS READING" }
        if let hr = LiveReadout.shared.hr { return "\(hr) BPM · YOUR LAST READING" }
        return balanceFieldVisible ? "FINDING YOUR PULSE" : "WAITING FOR THE KEY"
    }

    /// The field runs while the band is being read, and only then. It is not a background
    /// the screen wears — it is the measurement, so it arrives with contact and goes when the
    /// reading is over.
    private var balanceFieldVisible: Bool {
        switch phase {
        case .contact, .counting, .halfway, .lost, .computing: true
        default: false
        }
    }

    /// The number the band has settled so far, and a dash until it has one. ⚠️ Never a
    /// placeholder: a printed 24.1 that no band produced is a reading the user will believe.
    private var firstNumber: String {
        if isBodyScan { return reading?.bodyFatPercent.map { String(format: "%.1f", $0) } ?? Fmt.dash }
        return reading?.heartRate.map(String.init) ?? Fmt.dash
    }

    private var statusLine: String {
        switch phase {
        case .opening:   ""
        case .waiting:   L("WAITING FOR YOUR FINGER")
        case .nudge:     L("NO CONTACT · %dS", 6)
        case .contact:   isBodyScan ? L("CONTACT · CIRCUIT CLOSED") : L("CONTACT · PULSE LOCK")
        case .counting:  isBodyScan ? L("%d / 14 FIELDS", fields) : L("MEASURING · KEEP STILL")
        case .halfway:   isBodyScan ? L("HALFWAY · KEEP THE FINGER THERE")
                         : isBalance ? L("HALFWAY · KEEP THE FINGER THERE") : L("KEEP STILL · STRESS NEXT")
        case .lost:      L("PAUSED · %dS TO RESUME", Int(lostGrace.rounded()))
        case .computing: isBodyScan ? L("COMPUTING 14 FIELDS")
                         : isBalance ? L("WORKING OUT THE BALANCE") : L("MEASURING STRESS · HRV")
        // ⚠️ The ECG is not written to any table — 20 000 points have nowhere to go — so
        // this one says what actually happened instead of borrowing "SAVED".
        case .result:    isBalance ? L("ON THE PANEL") : L("SAVED")
        case .failed:    failure ?? L("NOT MEASURED")
        case .notWearing: L("NOT WEARING · PUT IT BACK ON")
        case .busy:       L("MEASURING NOW · TRY IN A MOMENT")
        case .dropped:    L("DISCONNECTED · RECONNECTING")
        case .noReading:  L("NO READING · NOTHING KEPT")
        }
    }
    private var statusTint: Color {
        switch phase {
        // E02 · the waiting line is lime: it is the screen saying it is ready, not a warning.
        case .waiting: NB.lime1.opacity(0.85)
        case .nudge, .lost, .notWearing: NB.ember2
        case .failed: NB.ember2
        case .contact, .counting, .halfway: NB.lime1
        // 06 rule 07 · device-side states are 32% grey, not amber and not red.
        case .busy, .dropped, .noReading: NB.white.opacity(0.32)
        default: NB.white.opacity(0.40)
        }
    }
    private var helpLine: String {
        switch phase {
        case .opening:   ""
        case .waiting:   L("Rest your hand on the table. Nothing to press.")
        case .nudge:     L("Skin, not a nail or a sleeve. Let it rest, don't press.")
        case .contact:   isBodyScan ? L("A tiny current crosses your body. You won't feel it.")
                                    : isBalance ? L("Keep the finger on the key. The field breathes with your pulse.")
                                    : L("Breathe normally. Talking is fine.")
        // ⚠️ Body composition has no resume: lifting off restarts the whole 30 seconds.
        case .counting:  isBodyScan ? L("Lift a finger and the scan starts over.")
                                    // ⚠️ Not the battery check's sentence, and not a trace:
                                    // the field's tempo IS the rate the band is reporting.
                                    : isBalance ? L("One breath of the field for every beat it reads.")
                                    : L("Heart rate from the band — the sweep follows that beat.")
        case .halfway:   isBodyScan ? L("One steady contact makes one reading.")
                                    : isBalance ? L("Halfway. Keep the finger where it is.")
                                    : L("Almost there. Stress and HRV come after the minute.")
        // 06 edge 2 · the board's sentence for a lifted finger.
        case .lost:      isBodyScan ? L("Your finger came off the key. This one has to start over.")
                                    : L("Your finger came off the key.")
        case .computing: isBodyScan ? L("You can lift your finger now.")
                                    : isBalance ? L("You can lift your finger now.")
                                    : L("Stress on the band now. HRV if this firmware has it.")
        case .result:    L("Folding it back onto the panel.")
        case .notWearing: L("Not a failure — it slipped or came off. Put it back on and the count continues.")
        case .busy:       L("One measurement at a time. It frees itself when the other one ends.")
        case .dropped:    L("Nothing half-done is kept. Reconnecting — then put your finger back on.")
        case .noReading:  L("This one didn't read cleanly. Nothing invented, nothing stored.")
        case .failed:    L("Close this and try again when you are ready.")
        }
    }

    // MARK: choreography

    /// The panel grows to full screen, then waits for a finger. Everything after that is
    /// driven by what the band actually reports — not by a timer pretending to be one.
    /// ⚠️ Closing used to call `done()` and nothing else. The task reading the measurement was
    /// never held onto, so it was never cancelled — on a real HOOP the test kept running after
    /// the screen was gone, and F3 §06's queue allows one native command in flight, so the next
    /// one came back DEVICE_BUSY against a measurement nobody was watching.
    private func leave() {
        run?.cancel()
        run = nil
        done()
    }

    private func open() {
        remaining = total
        bandClock = false
        reading = nil
        hrSamples = []
        withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) { grown = true }
        // DEBUG · 06 edges on the mock band, which never fails on its own.
        if let forced: Phase = ["notwearing": .notWearing, "busy": .busy, "dropped": .dropped, "noreading": .noReading,
                                    // E01–E04 · the two frames a mock band passes through too fast to look at.
                                    "waiting": .waiting, "contact": .contact][DebugEdge.name ?? ""] {
            run = Task { try? await Task.sleep(for: .milliseconds(700)); withAnimation { phase = forced } }
            return
        }

        run = Task {
            try? await Task.sleep(for: .milliseconds(460))
            phase = .waiting

            // The nudge lands at 5s and the screen never times out on its own:
            // the only exit is the close mark.
            // ⚠️ `try?` swallows CancellationError — without the isCancelled guard, cancelling
            // this task on the stream's first `.waitingForContact` immediately painted
            // 「Still nothing on the key」 while the band had not even been asked yet.
            // Onboarding's scan arm does the same guard; keep them the same shape.
            let nudge = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                if phase == .waiting { withAnimation { phase = .nudge } }
            }

            // ⚠️ THE BAND HAS ONE COMMAND CHANNEL AND THE SDK KEEPS ONE RESULT BLOCK PER TEST.
            // The panel's live readout is holding an open heart-rate test when the plus key is
            // pressed, and its stop — `veepooSDKTestHeartStart(false)` — is a command going out
            // on the main queue, not an instant. Started over the top of that, this screen's own
            // test was the one the stale stop ended: the band went quiet, no callback ever came,
            // and 「Index finger on the side key」 stood there for the whole minute on a band that
            // was perfectly willing to measure. So the readout is stood down and awaited first,
            // and the band gets the same settling second the inserted stress test gets.
            // Close admission synchronously: router observation may not have fired yet.
            // Let an already admitted native read finish before replacing SDK callbacks.
            guard !Task.isCancelled else { nudge.cancel(); return }
            BandLiveLifecycle.shared.setExclusiveOperation(true)
            await BandReadiness.shared.awaitNativeIdle()
            guard !Task.isCancelled else { nudge.cancel(); return }
            await LiveReadout.shared.standDown {
                try? await Task.sleep(for: .seconds(LiveReadout.Cadence.settle))
                guard !Task.isCancelled else { nudge.cancel(); return }
                await measure(nudge: nudge)
            }
        }
    }

    /// One measurement, from the first command to the stream ending. Runs inside the readout's
    /// `standDown`, so nothing else is talking to the band for as long as it lasts.
    private func measure(nudge: Task<Void, Never>) async {
            do {
                // ⚠️ The plus key can be pressed a second after a launch or a transient drop,
                // while the link is still coming back. Sending the first command into that gap
                // threw notConnected and the screen opened on 「Lost the band」 — a measurement
                // that never failed, reported as a failure. 03 restores the link first; so does this.
                if Band.live.state != .connected { await Band.live.reconnectIfBound() }

                if isBodyScan {
                    // F2 §05 · the band's BIA multiplies by the weight we push down, so the
                    // weight goes first and a scan without it is refused rather than stored.
                    try await Band.live.syncPersonalInfo(PersonalInfo(
                        heightCm: Int(data.profile.heightCm),
                        weightKg: Int((data.today.weightKg ?? 70).rounded()),
                        birthYear: Calendar.current.component(.year, from: data.profile.birthdate),
                        sexIsMale: data.profile.sexIsMale,
                        targetStep: 8000))
                    let stream = Band.live.measureBodyComposition()
                    for try await step in stream {
                        switch step {
                        case .waitingForContact: apply(step)
                        default: nudge.cancel(); apply(step)
                        }
                    }
                } else if isBalance {
                    try await measureBalanceCheck(nudge: nudge)
                } else {
                    await measureBatteryCheck(nudge: nudge)
                }
            } catch BandError.busy {
                // 06 edge 3 · DEVICE BUSY: one start*Test at a time. Not amber — not the wearer's doing.
                nudge.cancel()
                withAnimation { phase = .busy }
            } catch BandError.notConnected {
                nudge.cancel()
                await dropped()
            } catch {
                nudge.cancel()
                failure = (error as? BandError)?.errorDescription ?? "BAND OFFLINE"
                withAnimation { phase = .failed }
            }
    }

    /// 06 · Balance Check: the band's own forty seconds.
    ///
    /// ⚠️ The count comes from the BAND's percentage, not the phone's clock. The heart leg
    /// owns its minute on the phone because the SDK ends that test early; this one does not —
    /// it reports 0…100 as it goes, and a countdown that kept ticking after the band had
    /// stopped would be the screen lying about a measurement that had already ended.
    private func measureBalanceCheck(nudge: Task<Void, Never>) async throws {
        for try await step in Band.live.measurePulseStudy() {
            try Task.checkCancellation()
            switch step {
            case .waitingForContact:
                apply(.waitingForContact)
            case .contact:
                nudge.cancel()
                apply(.contact)
            case .measuring(let percent, let heartRate):
                nudge.cancel()
                // ⚠️ The band's percentage is the only clock here. Without this the phone's
                // own second hand kept decrementing `remaining` underneath it and the count
                // bounced between 38, 39 and 40 — two clocks writing one number.
                bandClock = true
                // ⚠️ Only a rate the band actually reported. Without one the field keeps its
                // resting tempo — it never fills the gap with the last number it saw.
                if let heartRate { reading = PartialReading(heartRate: heartRate) }
                studyProgress = min(1, Double(percent) / 100)
                remaining = max(0, total - Int((Double(total) * Double(percent) / 100).rounded()))
                let next: Phase = percent >= 50 ? .halfway : .counting
                if phase != next { withAnimation { phase = next } }
            case .lostContact:
                apply(.lostContact)
            case .finished(let study):
                apply(.finished(.pulseStudy(study)))
            case .failed(let reason):
                apply(.failed(reason: reason))
            }
        }
    }

    /// 06 · Battery Check: 60 s of PPG heart rate on the phone's clock, then stress (and
    /// HRV when the firmware answers) during computing. The menu promises all three; the
    /// heart stream alone used to invent a half-done fraction, never stop itself, and leave
    /// HRV / stress as nil forever.
    private func measureBatteryCheck(nudge: Task<Void, Never>) async {
        let box = HeartAccumulator()

        // Collect until the phone clock hits 0. The SDK may end early (or on lift-off); the
        // minute is still ours, and a lift past grace restarts the heart test in place.
        while !Task.isCancelled {
            let outcome = await collectHeartLeg(into: box, nudge: nudge)
            switch outcome {
            case .clockDone:
                break
            case .restartAfterLift:
                continue
            case .aborted:
                return
            }
            break
        }
        guard !Task.isCancelled else { return }

        if phase == .failed || phase == .busy || phase == .dropped
            || phase == .noReading || phase == .notWearing { return }

        nudge.cancel()
        // One settling spike is not a reading — need a short run of plausible beats.
        guard box.snapshot().count >= 3, let hr = Self.stableHeartRate(box.snapshot()) else {
            failure = "NO READING"
            withAnimation { phase = .noReading }
            return
        }

        reading = PartialReading(heartRate: hr)
        withAnimation { phase = .computing }

        try? await Task.sleep(for: .seconds(LiveReadout.Cadence.settle))
        guard !Task.isCancelled else { return }

        var stress: Int?
        var hrv: Int?
        do {
            stress = try await Band.live.measureStress { _ in }
        } catch is CancellationError {
            return
        } catch BandError.unsupported {
            stress = nil
        } catch {
            BandLog.shared.record("batteryCheck.stress", error: error)
        }
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .seconds(LiveReadout.Cadence.settle))
        guard !Task.isCancelled else { return }

        do {
            // Firmware often needs a long hold; twenty seconds is a try, not a promise.
            // A miss stays —— (rule 04) rather than a number we did not measure.
            hrv = try await Band.live.measureHRV(timeout: 20)
        } catch is CancellationError {
            return
        } catch BandError.unsupported {
            hrv = nil
        } catch {
            BandLog.shared.record("batteryCheck.hrv", error: error)
        }
        guard !Task.isCancelled else { return }

        apply(.finished(.heartRate(hr: hr, hrv: hrv, stress: stress)))
    }

    private enum HeartLegOutcome {
        /// Phone clock hit 0 — move on to stress / HRV.
        case clockDone
        /// Lift past the 3 s grace; SDK test is dead — open a new heart stream.
        case restartAfterLift
        /// Terminal UI state or the takeover was closed.
        case aborted
    }

    /// One heart-rate stream, until the minute ends, the user lifts past grace, or the
    /// screen fails. The phone clock is the authority: an early SDK `.over` does not
    /// shorten the minute.
    private func collectHeartLeg(into box: HeartAccumulator, nudge: Task<Void, Never>) async -> HeartLegOutcome {
        let lift = LiftFlag()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                do {
                    let stream = Band.live.measureHeartRate()
                    for try await step in stream {
                        try Task.checkCancellation()
                        switch step {
                        case .waitingForContact:
                            apply(step)
                        case .contact:
                            nudge.cancel()
                            apply(step)
                        case .measuring(_, let partial, _):
                            nudge.cancel()
                            if let hr = partial?.heartRate, Self.isPlausibleHeartRate(hr) {
                                box.add(hr)
                                hrSamples = box.snapshot()
                                reading = PartialReading(heartRate: Self.stableHeartRate(hrSamples))
                            }
                            // Phone clock owns `remaining` — never rewrite it from a fraction.
                            let next: Phase = remaining <= total / 2 ? .halfway : .counting
                            if phase != next { withAnimation { phase = next } }
                        case .lostContact:
                            lift.mark()
                            nudge.cancel()
                            apply(step)
                            // Do not return here — winning the task group would cancel the
                            // grace watcher while phase is still `.lost` and remaining is
                            // frozen, hanging the minute. Wait for the stream to finish
                            // (notWear ends it) or for tick to resume counting.
                        case .finished(let result):
                            if case .heartRate(let h, _, _) = result, Self.isPlausibleHeartRate(h) {
                                box.add(h)
                            }
                            // Stream over early — stay alive until the phone clock says so.
                            while !Task.isCancelled, remaining > 0,
                                  phase == .counting || phase == .halfway || phase == .lost {
                                try? await Task.sleep(for: .milliseconds(100))
                            }
                            return
                        case .failed(let reason):
                            nudge.cancel()
                            apply(.failed(reason: reason))
                            return
                        }
                        if remaining == 0, phase == .counting || phase == .halfway { return }
                    }
                    // Stream ended without `.finished` (cancel, or notWear → finish).
                    // If we are in lift-off grace, wait it out so tick can resume counting.
                    while !Task.isCancelled, phase == .lost {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                } catch is CancellationError {
                    // Countdown or leave() ended the heart stream on purpose.
                } catch BandError.busy {
                    nudge.cancel()
                    withAnimation { phase = .busy }
                } catch BandError.notConnected {
                    nudge.cancel()
                    await dropped()
                } catch {
                    nudge.cancel()
                    failure = (error as? BandError)?.errorDescription ?? "BAND OFFLINE"
                    withAnimation { phase = .failed }
                }
            }
            group.addTask { @MainActor in
                while !Task.isCancelled {
                    if remaining == 0, phase == .counting || phase == .halfway { return }
                    if phase == .failed || phase == .busy || phase == .dropped
                        || phase == .noReading || phase == .notWearing { return }
                    // After grace, tick puts us back on counting with a dead SDK test —
                    // the outer loop must open a fresh stream.
                    if lift.raised, phase == .counting || phase == .halfway, remaining > 0 {
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            _ = await group.next()
            group.cancelAll()
            await group.waitForAll()
        }

        if Task.isCancelled { return .aborted }
        if phase == .failed || phase == .busy || phase == .dropped
            || phase == .noReading || phase == .notWearing { return .aborted }
        if remaining == 0 { return .clockDone }
        // Grace may still be running if the deadline lost the race; wait it out.
        while !Task.isCancelled, phase == .lost {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if Task.isCancelled { return .aborted }
        if lift.raised, phase == .counting || phase == .halfway, remaining > 0 {
            return .restartAfterLift
        }
        // Stream died early but clock still running and no lift — wait out the minute.
        while !Task.isCancelled, remaining > 0 {
            if phase == .failed || phase == .busy || phase == .dropped
                || phase == .noReading || phase == .notWearing { return .aborted }
            if phase == .lost {
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return Task.isCancelled ? .aborted : .clockDone
    }

    /// Physiological gate for a live PPG sample. Settling spikes and zeros never reach the
    /// number or the sweep.
    private static func isPlausibleHeartRate(_ hr: Int) -> Bool { (40...180).contains(hr) }

    /// Median of the recent window so one 120 from a settling sensor cannot own the screen.
    private static func stableHeartRate(_ samples: [Int]) -> Int? {
        let window = Array(samples.suffix(7))
        guard window.count >= 1 else { return nil }
        // Prefer a settled window; a lone beat is allowed only when the minute produced
        // nothing else (caller still requires ≥3 samples before accepting a finish).
        let sorted = window.sorted()
        return sorted[sorted.count / 2]
    }

    /// 06 edge 4 · LINK DROPPED. Nothing half-done is kept; the screen stays, reconnects on its
    /// own, and goes back to "put your finger on". ⚠️ The measurement is stopped explicitly
    /// (the stream ends) so the band's slot is released before reconnecting.
    private func dropped() async {
        withAnimation { phase = .dropped }
        await Band.live.reconnectIfBound()
        if Band.live.state == .connected { open() }
    }

    private func apply(_ step: MeasurementProgress) {
        switch step {
        case .waitingForContact:
            if phase == .opening { withAnimation { phase = .waiting } }

        case .contact:
            // The only haptic in the flow, fired on the first `testing`/`start` state that
            // comes back — never on the fact that we sent `start`.
            Haptics.impact(.medium)
            // After a lift-off restart the stream yields contact again; do not wipe the
            // minute back to the pre-count contact frame (that hides 00:XX and feels broken).
            if phase != .counting && phase != .halfway {
                withAnimation(.easeInOut(duration: 0.3)) { phase = .contact }
            }
            lostGrace = 3

        case .measuring(let fraction, let partial, let secondsLeft):
            reading = partial
            // Body scan: the band's own seconds (or its fraction). Battery Check never
            // enters here — its path owns remaining on the phone clock so a fake 0.5
            // fraction cannot pin the count at 30.
            if isBodyScan {
                if let secondsLeft { bandClock = true; remaining = secondsLeft }
                else { remaining = max(0, total - Int((Double(total) * fraction).rounded())) }
                fields = min(14, Int((14 * fraction).rounded(.down)))
            }
            let half = isBodyScan ? fraction >= 0.5 : remaining <= total / 2
            let next: Phase = half ? .halfway : .counting
            if phase != next { withAnimation { phase = next } }

        case .lostContact:
            withAnimation { phase = .lost }

        case .finished(let result):
            // 06 rule 09 · store, then the result folds back onto the panel as one widget —
            // built before the store so the sentence can say what moved.
            let widget = resultWidget(result)
            store(result)
            router.measuredWidget = widget
            if isBodyScan {
                // 06 · 20 / G·03 · the result is the home panel (one hero, four fields,
                // one sentence), not a takeover page that says "Fourteen fields." The
                // cover is not the panel, so the fold is a cut: home is already holding
                // the widget, and a slide-down would be a different motion than the board.
                var cut = Transaction()
                cut.disablesAnimations = true
                withTransaction(cut) { done() }
                return
            }
            // Battery Check already spent computing on the real stress/HRV legs.
            if phase != .computing { withAnimation { phase = .computing } }
            // Stay on `run` so leave() cancels the fold-back; an unstructured Task used to
            // call done() after the user had already closed the screen.
            let fold = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                withAnimation { phase = .result }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                done()
            }
            run = fold

        case .failed(let reason):
            // 06 edges 1 / 5 · the SDK's own words decide: notWear is the wearer's, anything
            // else that ran and produced nothing is NO READING, never an invented number.
            if reason.lowercased().contains("wear") || reason.lowercased().contains("worn") {
                withAnimation { phase = .notWearing }
            } else if reason == "BAND OFFLINE" {
                Task { await dropped() }
            } else {
                failure = reason
                withAnimation { phase = .noReading }
            }
        }
    }

    /// The phone's clock counts only when the band has no clock of its own to report.
    /// A body scan's seconds come from the SDK's progress (see `bandClock`); a heart-rate
    /// read gives values and no progress, so its minute is timed here.
    private func tick() {
        switch phase {
        case .counting, .halfway:
            if !bandClock, remaining > 0 { remaining -= 1 }
        case .lost:
            lostGrace -= 1
            // Three seconds of grace on a battery check; a body scan has no resume at all.
            if lostGrace <= 0 {
                if isBodyScan {
                    remaining = total
                    withAnimation { phase = .waiting }
                } else {
                    withAnimation { phase = .counting }
                }
                lostGrace = 3
            }
        default:
            break
        }
    }

    /// 06 · 16 / 20 · the result is not a report page: it is the panel's own widget, with the
    /// number, the trace or the tiles, one sentence, the measured line, and one tap.
    private func resultWidget(_ result: MeasurementResult) -> PanelWidget {
        switch result {
        case .heartRate(let hr, let hrv, let stress):
            let bb = data.bodyBatteryNow ?? data.today.bbWake ?? 0
            let yesterday = data.history.last(where: { $0.day < data.today.day })?.bbWake
            var w = PanelWidget(
                type: .wave, title: L("BODY BATTERY"), tag: .recover,
                sentence: bb < 60 ? L("You're still carrying yesterday. Keep it easy today.")
                                  : L("Charged and steady. Today can take the session."),
                footer: L("HR %d · HRV %@ · STRESS %@",
                          hr,
                          hrv.map { "\($0) MS" } ?? "——",
                          stress.map { "\($0) / 100" } ?? "——"),
                action: L("TAP FOR THE FULL READING"),
                data: .trace(samples: Self.ecgTrace(hr: hr), hz: 50))
            w.hero = "\(bb)"
            w.heroLarge = true
            w.heroSub = yesterday.map { L("BODY BATTERY · WAS %d YESTERDAY", $0) } ?? L("BODY BATTERY")
            w.accentOverride = NB.lime1     // 06 · 16 · lime, not the ECG warning red
            // 06 · 17 · the tap turns the reading into a question for her.
            w.replyPrompt = L("Just measured: HR %d, HRV %@ ms, stress %@", hr, hrv.map(String.init) ?? "——", stress.map(String.init) ?? "——")
                + (yesterday.map { L(", battery %d yesterday", $0) } ?? "")
                + L(". What should today look like?")
            return w
        case .pulseStudy(let study):
            // ⚠️ Nothing here is drawn unless the band actually reported enough beats.
            // `AutonomicBalance` returns nil below twelve intervals, and a split computed
            // from six of them would swing on one swallow — so the frame says it could not
            // read rather than printing a confident percentage.
            guard let balance = AutonomicBalance(intervals: study.intervals) else {
                var w = PanelWidget(
                    type: .metric, title: L("BALANCE"), tag: nil,
                    sentence: L("The band didn't send enough beats to read the balance. Nothing was made up to fill it."),
                    footer: study.heartRate.map { L("HEART RATE %d BPM · %d INTERVALS", $0, study.intervals.count) }
                        ?? L("NO READING · %d INTERVALS", study.intervals.count),
                    action: L("TRY IT AGAIN WHEN YOU'RE STILL"), data: .none)
                w.hero = Fmt.dash
                w.accentOverride = NB.lime1
                return w
            }
            var w = PanelWidget(
                type: .metric, title: L("BALANCE"), tag: nil,
                sentence: balance.note,
                footer: "",
                action: L("TAP TO ASK ABOUT IT"), data: .none)
            w.accentOverride = NB.lime1
            w.balance = BalanceAnswer(
                headline: balance.headline,
                note: balance.note,
                restShare: balance.parasympatheticShare,
                // The band's own average rate when it has one — it saw every beat, and this
                // series is a sample of them.
                footer: [(study.heartRate ?? balance.beatsPerMinute).description + " BPM",
                         "SD1 \(Int(balance.sd1.rounded())) MS",
                         "SD2 \(Int(balance.sd2.rounded())) MS",
                         // ⚠️ Says which series it read. Per-second rates blunt the fast half
                         // of the cloud, and a footer that hid that would make two different
                         // measurements look like the same one.
                         study.source == .intervals ? L("%d BEATS", balance.points.count)
                                                    : L("%d SAMPLES · PER SECOND", balance.points.count)]
                    .joined(separator: " · "),
                points: balance.points.map { CGPoint(x: $0.x, y: $0.y) })
            w.replyPrompt = L("Just did a balance check: rest %d%%, drive %d%%, SD1 %d ms, SD2 %d ms. What does that suggest for today?",
                              balance.split.rest, balance.split.drive, Int(balance.sd1.rounded()), Int(balance.sd2.rounded()))
            return w
        case .bodyComposition(let r):
            let fatDown = (data.today.fatKg).map { r.fatMassKg < $0 } ?? false
            let leanHeld = (data.today.leanKg).map { abs(r.leanMassKg - $0) < 0.3 } ?? true
            var w = PanelWidget(
                type: .metric, title: L("BODY COMPOSITION"), tag: nil,
                sentence: fatDown && leanHeld ? L("Fat down, muscle held. That is the version you wanted.")
                        : L("One reading, not a verdict. The trend is what counts."),
                footer: [r.bmi.map { String(format: "BMI %.1f", $0) },
                         L("LEAN %.1f KG", r.leanMassKg),
                         r.boneKg.map { L("BONE %.1f KG", $0) }].compactMap { $0 }.joined(separator: " · "),
                action: L("TAP FOR ALL 14 FIELDS"), data: .none)
            w.hero = String(format: "%.1f%%", r.bodyFatPercent)
            w.targetOverride = .composition(date: nil)
            w.accentOverride = NB.lime1
            // 06 · 20 · the line under the hero is the last measured fat percent and its month,
            // read before this one is stored; the first scan ever says so instead.
            let prior = data.weighIns.first { $0.bodyFatPercent != nil }
            let month: (Date) -> String = { d in
                let f = DateFormatter()
                f.locale = AppLanguage.shared.swiftLocale
                f.dateFormat = AppLanguage.shared.isEnglish ? "MMMM" : "M月"
                return f.string(from: d).uppercased()
            }
            w.composition = CompositionAnswer(
                heroSub: prior.flatMap { p in p.bodyFatPercent.map { L("BODY FAT · %.1f%% IN %@", $0, month(p.date)) } }
                         ?? L("BODY FAT · FIRST READING"),
                fields: Self.goalFields(r, goal: data.profile.goal))
            return w
        }
    }

    /// 06 · 20 · four tiles, picked by the goal, not a fixed set. Colour follows the domain:
    /// lime for composition, cyan for water and protein, amber for BMR.
    private static func goalFields(_ r: BodyCompositionReading, goal: Goal) -> [CompositionAnswer.Field] {
        func n(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? Fmt.dash }
        let lime = NB.lime1.opacity(0.68)
        let cyan = NB.cyan1.opacity(0.78)
        let ember = NB.ember1.opacity(0.78)
        let bmr = CompositionAnswer.Field(label: L("BMR"),
                                          value: r.bmrKcal.map(String.init) ?? Fmt.dash,
                                          tint: ember)
        switch goal {
        case .cut:
            return [
                .init(label: L("FAT"),    value: n(r.fatMassKg),         tint: lime),
                .init(label: L("MUSCLE"), value: n(r.muscleKg),          tint: lime),
                .init(label: L("WATER"),  value: n(r.bodyWaterPercent),  tint: cyan),
                bmr,
            ]
        case .bulk:
            return [
                .init(label: L("MUSCLE"),  value: n(r.muscleKg),          tint: lime),
                .init(label: L("LEAN"),    value: n(r.leanMassKg),        tint: lime),
                .init(label: L("PROTEIN"), value: n(r.proteinPercent),    tint: cyan),
                bmr,
            ]
        case .recomp:
            return [
                .init(label: L("MUSCLE"),  value: n(r.muscleKg),          tint: lime),
                .init(label: L("WATER"),   value: n(r.bodyWaterPercent),  tint: cyan),
                .init(label: L("PROTEIN"), value: n(r.proteinPercent),    tint: cyan),
                bmr,
            ]
        }
    }

    /// A trace shaped by the measured rate: one PQRST every 60/hr seconds at 50 Hz, four
    /// seconds of it. It is drawn from the number, not the ECG channel (see before-ship).
    private static func ecgTrace(hr: Int, seconds: Double = 4, hz: Double = 50) -> [Double] {
        guard Band.allowsSeed else { return [] }
        let period = 60 / Double(max(hr, 30))
        return (0..<Int(seconds * hz)).map { i in
            let t = Double(i) / hz
            return LiveECG.Monitor.pqrst(t.truncatingRemainder(dividingBy: period) / period)
        }
    }

    private func store(_ result: MeasurementResult) {
        switch result {
        case .heartRate(let hr, _, _):
            // ⚠️ Do not copy bbWake into bodyBattery — that pretended the check rewrote
            // the day's reserve. The reading on screen is HR / HRV / stress; Body Battery
            // settlement still owns the score (06 before-ship).
            reading = PartialReading(heartRate: hr)
        case .pulseStudy(let study):
            if let hr = study.heartRate { reading = PartialReading(heartRate: hr) }
            // ADR 0010 · 摘要行落库。逐拍序列仍然一个字都不写——那是心律波形，产品不呈现也不
            // 解读；`balance_checks` 里只有结论词、心率、节拍数和三个离散度。
            // 算不出结论的一次（区间太少）没有摘要可存，和面板上那个 NO READING 一致。
            guard let balance = AutonomicBalance(intervals: study.intervals) else { return }
            let at = Date()
            let lead: MeasurementRecord.BalanceCheck.Lead = switch balance.lead {
            case .parasympathetic: .rest
            case .sympathetic:     .drive
            case .even:            .even
            }
            // 先进内存再上传：测完退回「我的」，那块 MEASUREMENTS 第一行立刻就是它，不用等
            // 下次启动重读（06 · 20 的验收线）。
            data.measurements.insert(
                MeasurementRecord(id: UUID(), at: at, detail: .balanceCheck(.init(
                    lead: lead,
                    restShare: balance.split.rest,
                    sd1Ms: balance.sd1, sd2Ms: balance.sd2, sdnnMs: balance.sdnn,
                    heartRate: study.heartRate ?? balance.beatsPerMinute,
                    beatCount: balance.points.count + 1))),
                at: 0)
            Task {
                await Repository.shared.recordBalanceCheck(balance, heartRate: study.heartRate,
                                                           at: at)
            }
        case .bodyComposition(let r):
            // F0 rule 09 · a band BIA reading is MEASURED and re-anchors the EMA.
            data.addWeighIn(WeighIn(id: UUID(), date: Date(), weightKg: r.inputWeightKg,
                                    bodyFatPercent: r.bodyFatPercent,
                                    source: .measured, origin: .band))
            data.today.fatKg = r.fatMassKg
            data.today.leanKg = r.leanMassKg
            data.today.fatSource = .measured
            data.bodyFatPercent = r.bodyFatPercent
            data.today.scans7d += 1
            // ADR 0010 · 同一次扫描也立刻进测量记录，理由和上面那条一样。
            data.rememberBodyScan(
                MeasurementRecord(id: UUID(), at: Date(), detail: .bodyScan(.init(
                    bodyFatPercent: r.bodyFatPercent,
                    fatMassKg: r.fatMassKg,
                    leanMassKg: r.leanMassKg,
                    bmrKcal: r.bmrKcal,
                    inputWeightKg: r.inputWeightKg))))
            // The row goes up now. The next launch reads body_composition back, and a
            // scan that only ever lived in memory would be replaced by the seed by then.
            Task { await Repository.shared.recordBodyComposition(r) }
        }
    }
}

/// Samples collected off the heart stream during Battery Check.
private final class HeartAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []
    func add(_ hr: Int) {
        lock.lock(); values.append(hr); lock.unlock()
    }
    func snapshot() -> [Int] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}

/// Lift-off flag shared by the heart-stream consumer and the deadline watcher.
private final class LiftFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var raised: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func mark() {
        lock.lock(); value = true; lock.unlock()
    }
}

/// 06 · E · the band, drawn as the board draws it: the strap fading into the ground at both
/// ends, the case, the dot-matrix screen, and the side key on the right edge.
///
/// ⚠️ The ripples come out of the KEY, not out of the middle of the face. Rings centred on
/// the screen are an instruction to press the display — which is not where the sensor is, and
/// not what the user is being asked to do. The one action this screen asks for is a fingertip
/// resting on the side key, so that is the only place anything moves.
private struct BandFigure: View {
    enum Mode {
        /// Waiting for a finger: rings walk out of the key on one 1.6 s loop.
        case ripple
        /// Skin has closed the circuit: the rings stop, the surface lights, the fingertip is drawn.
        case contact
        /// Lit but quiet — the ghost the trace is written over while the count runs.
        case lit
    }
    var tint: Color = NB.lime1
    var mode: Mode = .ripple
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The board's own geometry, in its 390 × 470 space.
    private static let W: CGFloat = 390, H: CGFloat = 470
    private static let keyCentre = CGPoint(x: 255, y: 210)
    private static let bandCentre = CGPoint(x: 195, y: 210)

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let s = min(size.width / Self.W, size.height / Self.H)
                ctx.translateBy(x: (size.width - Self.W * s) / 2, y: (size.height - Self.H * s) / 2)
                ctx.scaleBy(x: s, y: s)
                draw(&ctx, t)
            }
        }
        .frame(maxWidth: Self.W)
        .aspectRatio(Self.W / Self.H, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private func draw(_ ctx: inout GraphicsContext, _ t: Double) {
        let lit = mode != .ripple

        // The halo the contact frame puts behind the whole band: one ring at 152, and the
        // glow it sits in. This is the only burst of colour in the flow.
        if mode == .contact {
            ctx.fill(Path(ellipseIn: CGRect(x: 10, y: 35, width: 370, height: 350)),
                     with: .radialGradient(Gradient(colors: [tint.opacity(0.20), tint.opacity(0)]),
                                           center: Self.bandCentre, startRadius: 0, endRadius: 185))
            ctx.stroke(circle(Self.bandCentre, 152), with: .color(tint.opacity(0.30)), lineWidth: 3)
        }

        // The strap, fading out top and bottom so the band is a band and not a phone.
        let strapInk = Color(hex: lit ? 0x191A1F : 0x15161A)
        ctx.fill(Path(roundedRect: CGRect(x: 161, y: 0, width: 68, height: 118), cornerRadius: 14),
                 with: .linearGradient(Gradient(stops: [.init(color: strapInk.opacity(0), location: 0),
                                                        .init(color: strapInk, location: 0.6)]),
                                       startPoint: CGPoint(x: 195, y: 0), endPoint: CGPoint(x: 195, y: 118)))
        ctx.fill(Path(roundedRect: CGRect(x: 161, y: 302, width: 68, height: 168), cornerRadius: 14),
                 with: .linearGradient(Gradient(stops: [.init(color: strapInk, location: 0.4),
                                                        .init(color: strapInk.opacity(0), location: 1)]),
                                       startPoint: CGPoint(x: 195, y: 302), endPoint: CGPoint(x: 195, y: 470)))

        // The case, and the screen printed in the house dot matrix at a 4 pt pitch.
        let shell = Path(roundedRect: CGRect(x: 139, y: 112, width: 112, height: 196), cornerRadius: 36)
        ctx.fill(shell, with: .color(Color(hex: lit ? 0x1B1C21 : 0x17181C)))
        ctx.stroke(shell, with: .color(lit ? tint.opacity(0.35) : NB.white.opacity(0.07)),
                   lineWidth: lit ? 1.5 : 1)

        let face = Path(roundedRect: CGRect(x: 153, y: 126, width: 84, height: 168), cornerRadius: 26)
        ctx.fill(face, with: .color(Color(hex: lit ? 0x0C0D08 : 0x0A0A0D)))
        ctx.drawLayer { layer in
            layer.clip(to: face)
            var dots = Path()
            var y: CGFloat = 127
            while y < 294 {
                var x: CGFloat = 154
                while x < 237 {
                    dots.addRoundedRect(in: CGRect(x: x, y: y, width: 3.2, height: 3.2),
                                        cornerSize: CGSize(width: 0.8, height: 0.8))
                    x += 4
                }
                y += 4
            }
            layer.fill(dots, with: .color(Color(hex: lit ? 0x9BA23C : 0x24252C)))
        }

        // Eight cells alight while the circuit is closed — the band answering, not a spinner.
        if lit {
            let cells = [(169.0, 158.0), (197, 146), (213, 182), (181, 206),
                         (205, 234), (173, 258), (217, 270), (189, 278)]
            for (i, c) in cells.enumerated() {
                let p = (t * 0.6 + Double(i) / Double(cells.count)).truncatingRemainder(dividingBy: 1)
                let a = 0.45 + 0.55 * (0.5 + 0.5 * cos(p * 2 * .pi))
                ctx.fill(Path(roundedRect: CGRect(x: c.0, y: c.1, width: 3.2, height: 3.2), cornerRadius: 0.8),
                         with: .color(tint.opacity(a)))
            }
        }

        // The side key: the one place on the hardware this screen is talking about.
        ctx.fill(Path(roundedRect: CGRect(x: 251, y: 186, width: 8, height: 48), cornerRadius: 4),
                 with: .color(tint))

        // Three rings out of the key on one 1.6 s loop, a third of a turn apart. They never
        // stop and they never time out: the way out of this screen is the close mark.
        if mode == .ripple {
            for i in 0..<3 {
                let p = reduceMotion
                    ? Double(i) / 3
                    : ((t / 1.6) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                ctx.stroke(circle(Self.keyCentre, 34 + CGFloat(p) * 72),
                           with: .color(tint.opacity((1 - p) * 0.42)), lineWidth: 3)
            }
        }

        // The fingertip, resting on the key — drawn only once contact is real.
        if mode == .contact {
            let c = CGPoint(x: 272, y: 210)
            ctx.stroke(circle(c, 18), with: .color(NB.limePale.opacity(0.16)), lineWidth: 1)
            ctx.fill(circle(c, 11), with: .color(NB.carbon))
            ctx.stroke(circle(c, 11), with: .color(NB.limePale.opacity(0.95)), lineWidth: 1.4)
            ctx.fill(circle(c, 3.6), with: .color(tint))
        }
    }
}

/// A monitor, not a medical ECG. The sweep is written left to right at 200 Hz from a running
/// beat phase that advances at the band's own PPG rate: `bpm` is the value the SDK reported
/// last, so when the rate changes, the rhythm on screen changes with it, and until the first
/// value lands the sweep is flat — a beating wave with nothing being read is a picture of a
/// measurement that is not happening. The complex is drawn from the number (Battery Check
/// does not open the ECG channel; F5); the timing is the measurement's.
/// 06 · what lets type sit on the field without a bar behind it. A tight dark halo travels
/// with the glyphs, so the ground is only ever under the words — a scrim big enough to darken
/// a whole edge is indistinguishable from a black bar, which is what two of them turned into.
struct OverFieldShadow: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        content
            .shadow(color: NB.panelInk.opacity(on ? 0.95 : 0), radius: 5)
            .shadow(color: NB.panelInk.opacity(on ? 0.75 : 0), radius: 14)
    }
}

struct LiveECG: View {
    /// The band's latest rate. nil: nothing read yet, flat sweep, no invented beats.
    var bpm: Int?
    var tint: Color = NB.lime1
    var amplitude: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var monitor = Monitor()

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas(rendersAsynchronously: false) { ctx, size in
                let m = monitor
                m.advance(to: tl.date, bpm: bpm, amplitude: amplitude, still: reduceMotion)
                let W = size.width, H = size.height, mid = H / 2, N = m.samples.count
                let gain = mid * 0.78

                // ECG paper, in the house dot-matrix: a 1 mm grid at 6 % white.
                var grid = Path()
                var gy: CGFloat = 4
                while gy < H {
                    var gx: CGFloat = 4
                    while gx < W { grid.addEllipse(in: CGRect(x: gx - 0.6, y: gy - 0.6, width: 1.2, height: 1.2)); gx += 8 }
                    gy += 8
                }
                ctx.fill(grid, with: .color(NB.white.opacity(0.06)))

                // The sweep: every column holds the sample the head wrote there last. The gap
                // ahead of the head is what a monitor erases before it writes.
                let gap = Int(Double(N) * 0.07)
                var trace = Path()
                var pen = false
                var x: CGFloat = 0
                while x <= W {
                    let idx = min(N - 1, Int(x / W * CGFloat(N)))
                    let ahead = (idx - m.head + N) % N
                    if ahead > 0 && ahead <= gap { pen = false; x += 1; continue }
                    let pt = CGPoint(x: x, y: mid - CGFloat(m.samples[idx]) * gain)
                    if pen { trace.addLine(to: pt) } else { trace.move(to: pt); pen = true }
                    x += 1
                }
                ctx.stroke(trace, with: .color(tint), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                // The head: the same white core and lime glow that leads the body scan.
                if !reduceMotion {
                    let hx = CGFloat(m.head) / CGFloat(N) * W
                    let hy = mid - CGFloat(m.samples[(m.head - 1 + N) % N]) * gain
                    let R: CGFloat = 9 + 5 * CGFloat(m.flash)
                    ctx.fill(Path(ellipseIn: CGRect(x: hx - R, y: hy - R, width: R * 2, height: R * 2)),
                             with: .radialGradient(Gradient(colors: [tint.opacity(0.55), tint.opacity(0)]),
                                                   center: CGPoint(x: hx, y: hy), startRadius: 0, endRadius: R))
                    ctx.fill(Path(ellipseIn: CGRect(x: hx - 1.6, y: hy - 1.6, width: 3.2, height: 3.2)), with: .color(NB.white))
                }
            }
            .overlay(alignment: .topTrailing) {
                // The readout: the number the rhythm is drawn from.
                if let bpm {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(bpm)")
                            .font(NBFont.dot(700, 16)).tracking(0.08 * 16)
                            .foregroundStyle(tint)
                            .contentTransition(.numericText())
                        Text(L("BPM"))
                            .font(NBFont.dot(500, 9)).tracking(0.2 * 9)
                            .foregroundStyle(NB.white.opacity(0.42))
                    }
                    .padding(.trailing, 4)
                    .padding(.top, 2)
                    .animation(.easeOut(duration: 0.2), value: bpm)
                }
            }
        }
    }

    /// The paper the trace is written on: a ring of samples, one per column of the sweep.
    final class Monitor {
        static let hz = 200.0, seconds = 4.0
        var samples = [Double](repeating: 0, count: Int(hz * seconds))
        var head = 0
        private var phase = 0.0
        private var last: Date?
        /// 1 at the R spike, fading over ~120 ms: the head swells on every beat.
        private(set) var flash = 0.0

        func advance(to now: Date, bpm: Int?, amplitude: Double, still: Bool) {
            // This PQRST shape is synthetic, not samples from the ECG channel.
            guard Band.allowsSeed else { return }
            guard let last else {
                self.last = now
                if still, let bpm { prefill(bpm: bpm, amplitude: amplitude) }
                return
            }
            if still { return }
            let n = min(Int(Self.hz), Int(now.timeIntervalSince(last) * Self.hz))
            guard n > 0 else { return }
            self.last = last.addingTimeInterval(Double(n) / Self.hz)
            let step = (bpm.map { Double($0) / 60 } ?? 0) / Self.hz
            for _ in 0..<n {
                if bpm != nil {
                    phase += step
                    if phase >= 1 { phase -= 1; flash = 1 }
                }
                let v = bpm == nil ? 0 : Self.pqrst(phase) * amplitude
                samples[head] = v + Double.random(in: -0.012...0.012)
                head = (head + 1) % samples.count
                flash *= 0.96
            }
        }

        /// Reduce Motion: the whole paper written once, at the measured rate, and left still.
        private func prefill(bpm: Int, amplitude: Double) {
            let step = Double(bpm) / 60 / Self.hz
            for i in samples.indices {
                phase += step
                if phase >= 1 { phase -= 1 }
                samples[i] = Self.pqrst(phase) * amplitude
            }
            head = 0
        }

        /// One PQRST complex over a beat phase in [0, 1): the shape the panel widget draws too.
        static func pqrst(_ ph: Double) -> Double {
            func bump(_ c: Double, _ w: Double, _ a: Double) -> Double { a * exp(-pow((ph - c) / w, 2)) }
            return bump(0.18, 0.05, 0.12) - bump(0.30, 0.012, 0.18) + bump(0.33, 0.015, 1.0)
                 - bump(0.37, 0.014, 0.28) + bump(0.60, 0.06, 0.22)
        }
    }
}
