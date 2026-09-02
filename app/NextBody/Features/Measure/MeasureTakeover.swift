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

    private var isBodyScan: Bool { kind == .bodyComposition }
    private var total: Int { isBodyScan ? 30 : 60 }
    private var title: String { isBodyScan ? "BODY SCAN" : "BATTERY CHECK" }

    private let secondHand = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            NB.panelInk.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                headline
                stage
                Spacer(minLength: 0)
                footer
            }
            .padding(.vertical, 24)
            .opacity(grown ? 1 : 0)
        }
        .scaleEffect(grown ? 1 : 0.92)
        .clipShape(RoundedRectangle(cornerRadius: grown ? 0 : NB.R.hero, style: .continuous))
        .onAppear { open() }
        .onReceive(secondHand) { _ in tick() }
        .statusBarHidden(false)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(NBFont.dot(600, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.white.opacity(0.55))
            Spacer(minLength: 0)
            // The only exit. There is no back key here, and that is the point.
            Button(action: leave) { CloseMark() }
                .buttonStyle(.plain)
                .opacity(phase == .opening ? 0 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, Chrome.statusBarBlock - 24)
    }

    private var headline: some View {
        Text(headlineText)
            .font(NBFont.brand(500, 22))
            .foregroundStyle(NB.text1)
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.28), value: phase)
    }

    private var headlineText: String {
        switch phase {
        case .opening:   ""
        case .waiting:   isBodyScan ? "Two fingers on the side key." : "Index finger on the side key."
        case .nudge:     "Still nothing on the key."
        case .contact:   "Got it. Hold still."
        case .counting:  isBodyScan ? "Mapping you." : "Reading you."
        case .halfway:   "Halfway."
        case .lost:      "Put it back."
        case .computing: "Working it out."
        case .result:    isBodyScan ? "Fourteen fields." : "Done."
        case .failed:    "That didn't take."
        case .notWearing: "The band isn’t on your wrist."
        case .busy:       "She's already measuring something."
        case .dropped:    "Lost the band."
        case .noReading:  "Couldn't get a clean read."
        }
    }

    @ViewBuilder private var stage: some View {
        switch phase {
        case .opening, .waiting:
            ContactTarget(tint: NB.lime1, pulse: true)
        case .nudge:
            // Amber is the first time this flow uses colour: it means "we need you to move",
            // never "you failed".
            ContactTarget(tint: NB.ember2, pulse: true)
        case .contact:
            ContactGlow()
        case .counting:
            CountdownStage(remaining: remaining, total: total)
        case .halfway:
            FirstNumberStage(value: isBodyScan ? "24.1" : "62",
                             unit: isBodyScan ? "%" : "BPM",
                             caption: isBodyScan ? "BODY FAT  SETTLED" : "HEART RATE  SETTLED",
                             remaining: remaining, total: total, faded: false)
        case .lost:
            FirstNumberStage(value: isBodyScan ? "24.1" : "62",
                             unit: isBodyScan ? "%" : "BPM",
                             caption: isBodyScan ? "BODY FAT  SETTLED" : "HEART RATE  SETTLED",
                             remaining: Int(lostGrace.rounded()), total: total, faded: true)
        case .computing:
            FlatlineStage()
        case .result:
            CountdownStage(remaining: 0, total: total)
        case .failed, .busy, .dropped, .noReading:
            // Nothing is drawn where the reading would have been: an empty frame in that
            // position would read as a number we could not print.
            Color.clear.frame(height: 300)
        case .notWearing:
            // 06 edge 1 · amber, because this one is the wearer's to fix.
            ContactTarget(tint: NB.ember2, pulse: true)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text(statusLine)
                .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                .foregroundStyle(statusTint)
            Text(helpLine)
                .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                .multilineTextAlignment(.center)
                .foregroundStyle(NB.white.opacity(0.45))
                .frame(width: 300)
        }
        .padding(.bottom, 20)
        .animation(.easeInOut(duration: 0.24), value: phase)
    }

    private var statusLine: String {
        switch phase {
        case .opening:   ""
        case .waiting:   "WAITING FOR YOUR FINGER"
        case .nudge:     "NO CONTACT · \(6)S"
        case .contact:   isBodyScan ? "BOTH CONTACTS · CIRCUIT CLOSED" : "CONTACT · SIGNAL GOOD"
        case .counting:  isBodyScan ? "\(fields) / 14 FIELDS" : "MEASURING · KEEP THE FINGER THERE"
        case .halfway:   isBodyScan ? "SECOND CONTACT · KEEP GOING" : "HRV NEEDS THE FULL MINUTE"
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
        case .halfway:   isBodyScan ? "Two contacts make one reading."
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
        withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) { grown = true }
        // DEBUG · 06 edges on the mock band, which never fails on its own.
        if let forced: Phase = ["notwearing": .notWearing, "busy": .busy, "dropped": .dropped, "noreading": .noReading][DebugEdge.name ?? ""] {
            run = Task { try? await Task.sleep(for: .milliseconds(700)); withAnimation { phase = forced } }
            return
        }

        run = Task {
            try? await Task.sleep(for: .milliseconds(460))
            phase = .waiting

            // The nudge lands at 5s and the screen never times out on its own:
            // the only exit is the close mark.
            let nudge = Task {
                try? await Task.sleep(for: .seconds(5))
                if phase == .waiting { withAnimation { phase = .nudge } }
            }

            do {
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
                    nudge.cancel()
                    apply(step)
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

        case .measuring(let fraction, let partial):
            reading = partial
            remaining = max(0, total - Int((Double(total) * fraction).rounded()))
            fields = min(14, Int((14 * fraction).rounded(.down)))
            // The first real number lands halfway; before that there is nothing to show.
            let next: Phase = partial == nil ? .counting : .halfway
            if phase != next { withAnimation { phase = next } }

        case .lostContact:
            withAnimation { phase = .lost }

        case .finished(let result):
            // 06 rule 09 · store, then the result folds back onto the panel as one widget —
            // built before the store so the sentence can say what moved.
            let widget = resultWidget(result)
            store(result)
            router.measuredWidget = widget
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

    /// Every countdown runs on the phone's clock. ⚠️ The SDK's own progress is not a timer
    /// and reading it as one makes the number jump.
    private func tick() {
        switch phase {
        case .counting, .halfway:
            if remaining > 0 { remaining -= 1 }
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
            let bb = data.today.bodyBattery ?? data.today.bbWake ?? 0
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
            w.accentOverride = NB.lime1     // 06 · 16 · lime, not the ECG warning red
            // 06 · 17 · the tap turns the reading into a question for her.
            w.replyPrompt = "刚测完：心率 \(hr)，HRV \(hrv.map(String.init) ?? "——") ms，压力 \(stress.map(String.init) ?? "——")"
                + (yesterday.map { "，昨天电量 \($0)" } ?? "") + "。今天怎么安排？"
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
            return w
        }
    }

    /// A trace shaped by the measured rate: one PQRST every 60/hr seconds at 50 Hz, four
    /// seconds of it. It is drawn from the number, not the ECG channel (see before-ship).
    private static func ecgTrace(hr: Int, seconds: Double = 4, hz: Double = 50) -> [Double] {
        let period = 60 / Double(max(hr, 30))
        return (0..<Int(seconds * hz)).map { i in
            let t = Double(i) / hz
            let ph = t.truncatingRemainder(dividingBy: period) / period
            func bump(_ c: Double, _ w: Double, _ a: Double) -> Double { a * exp(-pow((ph - c) / w, 2)) }
            return bump(0.18, 0.05, 0.12) - bump(0.30, 0.012, 0.18) + bump(0.33, 0.015, 1.0)
                 - bump(0.37, 0.014, 0.28) + bump(0.60, 0.06, 0.22)
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
        }
    }
}

/// The band seen through a ring of ripples that never stop and never time out.
private struct ContactTarget: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tint: Color
    let pulse: Bool

    var body: some View {
        TimelineView(.animation) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    // one 1.6s loop, three phases apart
                    let p = ((t / 1.6) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(tint.opacity((1 - p) * 0.55), lineWidth: 2)
                        .frame(width: 90 + CGFloat(p) * 170, height: 90 + CGFloat(p) * 170)
                }
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(hex: 0x17181C))
                    .frame(width: 96, height: 152)
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(NB.white.opacity(0.07), lineWidth: 1))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint)
                    .frame(width: 7, height: 42)
            }
            .frame(height: 300)
        }
    }
}

/// The band's own face lights up. The judgement comes from the first `testing` state
/// coming back, not from having sent `start` — showing it early is a lie the user can feel.
private struct ContactGlow: View {
    @State private var lit = false
    var body: some View {
        ZStack {
            Circle()
                .stroke(NB.lime1.opacity(0.6), lineWidth: 2)
                .frame(width: 250, height: 250)
                .shadow(color: NB.lime1.opacity(0.35), radius: 30)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(NB.lime1.opacity(lit ? 0.85 : 0.2))
                .frame(width: 84, height: 150)
                .overlay(
                    Canvas { ctx, size in
                        var dots = Path()
                        var y: CGFloat = 4
                        while y < size.height {
                            var x: CGFloat = 4
                            while x < size.width {
                                dots.addEllipse(in: CGRect(x: x, y: y, width: 1.6, height: 1.6))
                                x += 5
                            }
                            y += 5
                        }
                        ctx.fill(dots, with: .color(NB.limeMid.opacity(0.5)))
                    })
            Circle().fill(NB.lime1).frame(width: 12, height: 12).offset(x: 62)
        }
        .frame(height: 300)
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { lit = true } }
    }
}

/// The countdown uses the phone's clock, never the SDK's progress callback.
private struct CountdownStage: View {
    let remaining: Int
    let total: Int

    var body: some View {
        VStack(spacing: 26) {
            Text(String(format: "00:%02d", max(0, remaining)))
                .font(NBFont.dot(700, 44)).tracking(0.1 * 44)
                .foregroundStyle(NB.text1)
                .contentTransition(.numericText(countsDown: true))
            LiveECG(tint: NB.lime1)
                .frame(height: 90)
        }
        .frame(height: 300)
    }
}

private struct FirstNumberStage: View {
    let value: String
    let unit: String
    let caption: String
    let remaining: Int
    let total: Int
    let faded: Bool

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(NBFont.brand(700, 46)).tracking(-0.045 * 46)
                    .foregroundStyle(faded ? NB.white.opacity(0.32) : NB.text1)
                Text(unit)
                    .font(NBFont.dot(500, 13))
                    .foregroundStyle(NB.white.opacity(faded ? 0.20 : 0.42))
            }
            Text(caption)
                .font(NBFont.dot(500, 10)).tracking(0.2 * 10)
                .foregroundStyle(NB.white.opacity(faded ? 0.20 : 0.34))
            LiveECG(tint: faded ? NB.ember2 : NB.lime1)
                .frame(height: 80)
            Text(String(format: "00:%02d", max(0, remaining)))
                .font(NBFont.dot(700, 30)).tracking(0.1 * 30)
                .foregroundStyle(faded ? NB.ember2 : NB.text1)
                .contentTransition(.numericText(countsDown: true))
        }
        .frame(height: 300)
    }
}

/// No spinner anywhere: the wait is filled by the data the user just produced,
/// collapsing into a single line.
private struct FlatlineStage: View {
    @State private var flat = false
    var body: some View {
        VStack {
            LiveECG(tint: NB.lime1, amplitude: flat ? 0.06 : 1)
                .frame(height: 90)
        }
        .frame(height: 300)
        .onAppear { withAnimation(.easeInOut(duration: 1.1)) { flat = true } }
    }
}

/// A real waveform, drawn as dots — one sweep is never the same as the last,
/// and that is the whole proof that it is really reading you.
struct LiveECG: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tint: Color = NB.lime1
    var amplitude: Double = 1

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let mid = size.height / 2
                var dots = Path()
                let n = 200
                for i in 0..<n {
                    let x = size.width * CGFloat(i) / CGFloat(n - 1)
                    let phase = Double(i) / Double(n) * 3.4 - t * 0.85
                    let beat = phase - phase.rounded(.down)   // wrap to [0,1); a negative phase must not skip the beat
                    var v: Double = 0
                    if beat > 0.30 && beat < 0.35 { v = -0.16 }
                    else if beat > 0.35 && beat < 0.41 { v = 1.0 }
                    else if beat > 0.41 && beat < 0.47 { v = -0.5 }
                    else if beat > 0.55 && beat < 0.68 { v = 0.2 }
                    else { v = sin(phase * 11) * 0.03 }
                    let y = mid - CGFloat(v * amplitude) * mid * 0.85
                    dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                }
                ctx.fill(dots, with: .color(tint))
            }
        }
    }
}
