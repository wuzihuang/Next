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

    private var isBodyScan: Bool { kind == .bodyComposition }
    private var total: Int { isBodyScan ? 30 : 60 }

    private let secondHand = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            NB.panelInk.ignoresSafeArea()

            // 06 · E/F · the board's column, centred: the eyebrow and the close mark, one
            // sentence, the band, the count, and the two lines at the foot. Nothing here is
            // left-aligned — the instruction is about the band, and the band is the middle.
            VStack(spacing: 0) {
                Color.clear.frame(height: Chrome.gateTopInset)
                header
                instruction
                    .padding(.top, 32)
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
                // Grey, in front — what to do if it breaks, said before it breaks.
                Text(helpLine)
                    .font(NBFont.ui(300, 12.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NB.white.opacity(0.42))
                    .frame(width: 318)
                    .padding(.top, 18)
                Color.clear.frame(height: 26)
            }
            .animation(.easeInOut(duration: 0.24), value: phase)
            .opacity(grown ? 1 : 0)
        }
        .scaleEffect(grown ? 1 : 0.92)
        .clipShape(RoundedRectangle(cornerRadius: grown ? 0 : NB.R.hero, style: .continuous))
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
                .foregroundStyle(NB.lime1)
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
                    Text(isBodyScan ? "%" : "BPM")
                        .font(NBFont.dot(500, 12))
                        .foregroundStyle(NB.white.opacity(phase == .lost ? 0.20 : 0.42))
                }
                Text(isBodyScan ? "BODY FAT · SETTLED" : "HEART RATE · SETTLED")
                    .font(NBFont.dot(500, 10)).tracking(0.2 * 10)
                    .foregroundStyle(NB.white.opacity(phase == .lost ? 0.20 : 0.34))
            }
            .padding(.top, 22)
            .transition(.opacity)
        }
    }

    /// The eyebrow: what is being measured and how long it takes, in 03's own words.
    private var eyebrow: String { isBodyScan ? "BODY SCAN · 30S" : "BATTERY CHECK · 60S" }

    private var headlineText: String {
        switch phase {
        // Opening borrows waiting's words: a sentence under an empty line reads as a screen
        // that failed to draw, and this phase is 460 ms of exactly that.
        // The board's own words: which finger, and which key. 「Finger on the key」 with a ring
        // around the display was an instruction to press the screen.
        case .opening, .waiting: "Index finger on the side key."
        case .nudge:     "Still nothing on the key."
        case .contact:   "Got it. Hold still."
        case .counting:  isBodyScan ? "Mapping you." : "Reading you."
        case .halfway:   "Halfway."
        case .lost:      "Put it back."
        case .computing: "Working it out."
        case .result:    isBodyScan ? "Fourteen fields." : "Done."
        case .failed:    "That didn't take."
        case .notWearing: "The band isn't on your wrist."
        case .busy:       "She's already measuring something."
        case .dropped:    "Lost the band."
        case .noReading:  "Couldn't get a clean read."
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
            BandFigure(tint: NB.lime1, mode: .contact)
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
            } else {
                ZStack {
                    // E05 · the band stays for the recovery check — the reading is happening
                    // at the wrist, and the trace is written over it at 14 %.
                    BandFigure(tint: NB.lime1, mode: .lit).opacity(0.14)
                    // The trace beats at the rate the band is reporting right now; before the
                    // first value it sweeps flat. Computing flattens it: the reading is over.
                    LiveECG(bpm: reading?.heartRate,
                            tint: phase == .lost ? NB.ember2 : NB.lime1,
                            amplitude: phase == .computing ? 0 : 1)
                        .frame(height: 96)
                }
            }
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
        case .waiting:   "WAITING FOR YOUR FINGER"
        case .nudge:     "NO CONTACT · \(6)S"
        case .contact:   isBodyScan ? "CONTACT · CIRCUIT CLOSED" : "CONTACT · SIGNAL GOOD"
        case .counting:  isBodyScan ? "\(fields) / 14 FIELDS" : "MEASURING · KEEP THE FINGER THERE"
        case .halfway:   isBodyScan ? "HALFWAY · KEEP THE FINGER THERE" : "HRV NEEDS THE FULL MINUTE"
        case .lost:      "PAUSED · \(Int(lostGrace.rounded()))S TO RESUME"
        case .computing: isBodyScan ? "COMPUTING 14 FIELDS" : "COMPUTING HRV · STRESS"
        case .result:    "SAVED"
        case .failed:    failure ?? "NOT MEASURED"
        case .notWearing: "NOT WEARING · PUT IT BACK ON"
        case .busy:       "MEASURING NOW · TRY IN A MOMENT"
        case .dropped:    "DISCONNECTED · RECONNECTING"
        case .noReading:  "NO READING · NOTHING KEPT"
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
        case .waiting:   "Rest your hand on the table. Nothing to press."
        case .nudge:     "Skin, not a nail or a sleeve. Let it rest, don't press."
        case .contact:   isBodyScan ? "A tiny current crosses your body. You won't feel it." : "Breathe normally. Talking is fine."
        // ⚠️ Body composition has no resume: lifting off restarts the whole 30 seconds.
        case .counting:  isBodyScan ? "Lift a finger and the scan starts over."
                                    : "Lift early and it picks up where it stopped."
        case .halfway:   isBodyScan ? "One steady contact makes one reading."
                                    : "Stress comes out of the same reading."
        // 06 edge 2 · the board's sentence for a lifted finger.
        case .lost:      isBodyScan ? "Your finger came off the key. This one has to start over."
                                    : "Your finger came off the key."
        case .computing: "You can lift your finger now."
        case .result:    "Folding it back onto the panel."
        case .notWearing: "Not a failure — it slipped or came off. Put it back on and the count continues."
        case .busy:       "One measurement at a time. It frees itself when the other one ends."
        case .dropped:    "Nothing half-done is kept. Reconnecting — then put your finger back on."
        case .noReading:  "This one didn't read cleanly. Nothing invented, nothing stored."
        case .failed:    "Close this and try again when you are ready."
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
            await LiveReadout.shared.standDown {
                try? await Task.sleep(for: .seconds(LiveReadout.Cadence.settle))
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

                // F2 §05 · the band's BIA multiplies by the weight we push down, so the
                // weight goes first and a scan without it is refused rather than stored.
                if isBodyScan {
                    try await Band.live.syncPersonalInfo(PersonalInfo(
                        heightCm: Int(data.profile.heightCm),
                        weightKg: Int((data.today.weightKg ?? 70).rounded()),
                        birthYear: Calendar.current.component(.year, from: data.profile.birthdate),
                        sexIsMale: data.profile.sexIsMale,
                        targetStep: 8000))
                }

                let stream = isBodyScan
                    ? Band.live.measureBodyComposition()
                    : Band.live.measureHeartRate()

                for try await step in stream {
                    // 06 · nudge at 5s if contact never arrives. `.waitingForContact` is the
                    // stream opening, not the finger — cancelling here used to trip the amber
                    // line the instant the command went out. Disarm only once the band answers.
                    switch step {
                    case .waitingForContact:
                        apply(step)
                    default:
                        nudge.cancel()
                        apply(step)
                    }
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
            // The only haptic in the flow, fired on the first `testing` state that comes
            // back — never on the fact that we sent `start`.
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeInOut(duration: 0.3)) { phase = .contact }
            lostGrace = 3

        case .measuring(let fraction, let partial, let secondsLeft):
            reading = partial
            if let secondsLeft { bandClock = true; remaining = secondsLeft }
            else { remaining = max(0, total - Int((Double(total) * fraction).rounded())) }
            fields = min(14, Int((14 * fraction).rounded(.down)))
            // Halfway is the clock's, not the value's: a heart-rate read reports a rate from
            // its first callback, and calling that 「Halfway」 at second one was a lie. The body
            // scan's clock is the band's; the heart-rate read is timed here.
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
            withAnimation { phase = .computing }
            Task {
                try? await Task.sleep(for: .milliseconds(1400))
                withAnimation { phase = .result }
                try? await Task.sleep(for: .milliseconds(500))
                done()
            }

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
                type: .wave, title: "BODY BATTERY", tag: .recover,
                sentence: bb < 60 ? "You're still carrying yesterday. Keep it easy today."
                                  : "Charged and steady. Today can take the session.",
                footer: "HR \(hr) · HRV \(hrv.map { "\($0) MS" } ?? "——") · STRESS \(stress.map { "\($0) / 100" } ?? "——")",
                action: "TAP FOR THE FULL READING",
                data: .trace(samples: Self.ecgTrace(hr: hr), hz: 50))
            w.hero = "\(bb)"
            w.heroLarge = true
            w.heroSub = "BODY BATTERY" + (yesterday.map { " · WAS \($0) YESTERDAY" } ?? "")
            w.accentOverride = NB.lime1     // 06 · 16 · lime, not the ECG warning red
            // 06 · 17 · the tap turns the reading into a question for her.
            w.replyPrompt = AppLanguage.isEnglish
                ? "Just measured: HR \(hr), HRV \(hrv.map(String.init) ?? "——") ms, stress \(stress.map(String.init) ?? "——")"
                : "刚测完：心率 \(hr)，HRV \(hrv.map(String.init) ?? "——") ms，压力 \(stress.map(String.init) ?? "——")"
                + (yesterday.map { AppLanguage.isEnglish ? ", battery \($0) yesterday" : "，昨天电量 \($0)" } ?? "")
                + (AppLanguage.isEnglish ? ". What should today look like?" : "。今天怎么安排？")
            return w
        case .bodyComposition(let r):
            let fatDown = (data.today.fatKg).map { r.fatMassKg < $0 } ?? false
            let leanHeld = (data.today.leanKg).map { abs(r.leanMassKg - $0) < 0.3 } ?? true
            var w = PanelWidget(
                type: .metric, title: "BODY COMPOSITION", tag: nil,
                sentence: fatDown && leanHeld ? "Fat down, muscle held. That is the version you wanted."
                        : "One reading, not a verdict. The trend is what counts.",
                footer: [r.bmi.map { String(format: "BMI %.1f", $0) },
                         String(format: "LEAN %.1f KG", r.leanMassKg),
                         r.boneKg.map { String(format: "BONE %.1f KG", $0) }].compactMap { $0 }.joined(separator: " · "),
                action: "TAP FOR ALL 14 FIELDS", data: .none)
            w.hero = String(format: "%.1f%%", r.bodyFatPercent)
            w.targetOverride = .composition(date: nil)
            w.accentOverride = NB.lime1
            // 06 · 20 · the line under the hero is the last measured fat percent and its month,
            // read before this one is stored; the first scan ever says so instead.
            let prior = data.weighIns.first { $0.bodyFatPercent != nil }
            let month: (Date) -> String = { d in
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMMM"
                return f.string(from: d).uppercased()
            }
            w.composition = CompositionAnswer(
                heroSub: prior.flatMap { p in p.bodyFatPercent.map { String(format: "BODY FAT · %.1f%% IN %@", $0, month(p.date)) } }
                         ?? "BODY FAT · FIRST READING",
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
        let bmr = CompositionAnswer.Field(label: "BMR",
                                          value: r.bmrKcal.map(String.init) ?? Fmt.dash,
                                          tint: ember)
        switch goal {
        case .cut:
            return [
                .init(label: "FAT",    value: n(r.fatMassKg),         tint: lime),
                .init(label: "MUSCLE", value: n(r.muscleKg),          tint: lime),
                .init(label: "WATER",  value: n(r.bodyWaterPercent),  tint: cyan),
                bmr,
            ]
        case .bulk:
            return [
                .init(label: "MUSCLE",  value: n(r.muscleKg),          tint: lime),
                .init(label: "LEAN",    value: n(r.leanMassKg),        tint: lime),
                .init(label: "PROTEIN", value: n(r.proteinPercent),    tint: cyan),
                bmr,
            ]
        case .recomp:
            return [
                .init(label: "MUSCLE",  value: n(r.muscleKg),          tint: lime),
                .init(label: "WATER",   value: n(r.bodyWaterPercent),  tint: cyan),
                .init(label: "PROTEIN", value: n(r.proteinPercent),    tint: cyan),
                bmr,
            ]
        }
    }

    /// A trace shaped by the measured rate: one PQRST every 60/hr seconds at 50 Hz, four
    /// seconds of it. It is drawn from the number, not the ECG channel (see before-ship).
    private static func ecgTrace(hr: Int, seconds: Double = 4, hz: Double = 50) -> [Double] {
        let period = 60 / Double(max(hr, 30))
        return (0..<Int(seconds * hz)).map { i in
            let t = Double(i) / hz
            return LiveECG.Monitor.pqrst(t.truncatingRemainder(dividingBy: period) / period)
        }
    }

    private func store(_ result: MeasurementResult) {
        switch result {
        case .heartRate(let hr, _, _):
            data.today.bodyBattery = data.today.bbWake
            reading = PartialReading(heartRate: hr)
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
            // The row goes up now. The next launch reads body_composition back, and a
            // scan that only ever lived in memory would be replaced by the seed by then.
            Task { await Repository.shared.recordBodyComposition(r) }
        }
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

/// A monitor, not a loop. The trace is written left to right at 200 Hz from a running beat
/// phase that advances at the band's own rate: `bpm` is the value the SDK reported last, so
/// when the rate changes, the rhythm on screen changes with it, and until the first value
/// lands the sweep is flat — a beating wave with nothing being read is a picture of a
/// measurement that is not happening. The complex is drawn from the number (this band has no
/// ECG channel on a heart-rate read); the timing is the measurement's.
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
                        Text("BPM")
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
