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

    @EnvironmentObject private var data: DataStore

    enum Phase: Hashable {
        case opening, waiting, nudge, contact, counting, halfway, lost, computing, result
    }

    @State private var phase: Phase = .opening
    @State private var remaining: Int = 60
    @State private var lostGrace: Double = 3
    @State private var sweep = 0
    @State private var grown = false

    private var isBodyScan: Bool { kind == .bodyComposition }
    private var total: Int { isBodyScan ? 30 : 60 }
    private var title: String { isBodyScan ? "BODY SCAN" : "BATTERY CHECK" }

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            NB.panelInk.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                headline
                Spacer(minLength: 0)
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
        .onReceive(tick) { _ in advance() }
        .statusBarHidden(false)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(NBFont.dot(600, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.white.opacity(0.55))
            Spacer(minLength: 0)
            // The only exit. There is no back key here, and that is the point.
            Button(action: done) { CloseMark() }
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
        case .waiting:   isBodyScan ? "Both hands on the frame." : "Index finger on the side key."
        case .nudge:     "Still nothing on the key."
        case .contact:   "Got it. Hold still."
        case .counting:  "Reading you."
        case .halfway:   "Halfway."
        case .lost:      "Put it back."
        case .computing: "Working it out."
        case .result:    isBodyScan ? "Fourteen fields." : "Done."
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
        case .contact:   "CONTACT · SIGNAL GOOD"
        case .counting:  "MEASURING · KEEP THE FINGER THERE"
        case .halfway:   isBodyScan ? "SECOND CONTACT · KEEP GOING" : "HRV NEEDS THE FULL MINUTE"
        case .lost:      "SIGNAL LOST · HOLDING \(Int(lostGrace.rounded()))S"
        case .computing: isBodyScan ? "COMPUTING 14 FIELDS" : "COMPUTING HRV · STRESS"
        case .result:    "SAVED"
        }
    }
    private var statusTint: Color {
        switch phase {
        case .nudge, .lost: NB.ember2
        case .contact, .counting, .halfway: NB.lime1
        default: NB.white.opacity(0.40)
        }
    }
    private var helpLine: String {
        switch phase {
        case .opening:   ""
        case .waiting:   "Rest your hand on the table. Nothing to press."
        case .nudge:     "Skin, not a nail or a sleeve. Let it rest, don't press."
        case .contact:   "Breathe normally. Talking is fine."
        // ⚠️ Body composition has no resume: lifting off restarts the whole 30 seconds.
        case .counting:  isBodyScan ? "Lift off and the scan starts again."
                                    : "Lift early and it picks up where it stopped."
        case .halfway:   isBodyScan ? "Two contacts make one reading."
                                    : "Stress comes out of the same reading."
        case .lost:      isBodyScan ? "This one has to start over."
                                    : "Come back within three seconds and nothing is lost."
        case .computing: "You can lift your finger now."
        case .result:    "Folding it back onto the panel."
        }
    }

    // MARK: choreography

    private func open() {
        remaining = total
        withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) { grown = true }
        Task {
            try? await Task.sleep(for: .milliseconds(460))
            phase = .waiting
            // The nudge lands at 5s and never times out on its own; the only exit is close.
            try? await Task.sleep(for: .seconds(5))
            if phase == .waiting { phase = .nudge }
            // mock: contact arrives ~1.2s later
            try? await Task.sleep(for: .milliseconds(1200))
            if phase == .nudge || phase == .waiting { makeContact() }
        }
    }

    private func makeContact() {
        // The only haptic in the flow, fired on the first `testing` state — never on `start`.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.3)) { phase = .contact }
        Task {
            try? await Task.sleep(for: .seconds(1))
            withAnimation { phase = .counting }
        }
    }

    private func advance() {
        switch phase {
        case .counting:
            remaining -= 1
            sweep = (total - remaining) / 5
            // The first real number lands at T+30 for the battery check.
            if remaining <= total / 2 { withAnimation { phase = .halfway } }
        case .halfway:
            remaining -= 1
            if remaining <= 0 { withAnimation { phase = .computing }; finish() }
        case .lost:
            lostGrace -= 1
            if lostGrace <= 0 { withAnimation { phase = .counting }; lostGrace = 3 }
        default:
            break
        }
    }

    private func finish() {
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            if isBodyScan {
                data.addWeighIn(WeighIn(id: UUID(), date: Date(),
                                        weightKg: data.today.weightKg ?? 68.4,
                                        bodyFatPercent: 24.1, source: .measured, origin: .band))
            } else {
                data.today.bodyBattery = 72
                data.today.bbWake = 72
            }
            withAnimation { phase = .result }
            try? await Task.sleep(for: .milliseconds(500))
            done()
        }
    }
}

/// The band seen through a ring of ripples that never stop and never time out.
private struct ContactTarget: View {
    let tint: Color
    let pulse: Bool

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
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
    var tint: Color = NB.lime1
    var amplitude: Double = 1

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let mid = size.height / 2
                var dots = Path()
                let n = 200
                for i in 0..<n {
                    let x = size.width * CGFloat(i) / CGFloat(n - 1)
                    let phase = Double(i) / Double(n) * 3.4 - t * 0.85
                    let beat = phase.truncatingRemainder(dividingBy: 1)
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
