import SwiftUI
import UIKit
import os

/// 14 · LIVE SESSION · the panel grown over the whole home screen for as long as the band
/// is running a sport mode. Not a page and not a cover: it is the panel's own rectangle,
/// animating its frame and corner radius from 358 × 470 to full bleed in 0.46 s, the way
/// the measurement takeover grows — and folding back into the panel, carrying the
/// session's three numbers as one widget, when STOP is held.
///
/// Three regions and nothing else. The eyebrow at the top says LIVE and which sport; the
/// dithered world in the middle carries the clock, and the two wrist numbers sit under it;
/// the lime key at the foot is the only way out. Held, not tapped: a workout screen lives
/// under a sleeve and a sweaty thumb, and a session ended by accident cannot be resumed.
struct LiveSessionTakeover: View {
    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "session-ui")
    /// Where the panel sits on home, in home's own coordinates — the frame this grows from.
    let panelFrame: CGRect
    let screen: CGSize
    /// The screen has folded back into the panel; the widget, if any, is what it carries.
    let onFolded: (PanelWidget?) -> Void

    @ObservedObject private var store = LiveSessionStore.shared
    @EnvironmentObject private var data: DataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var grown = false
    @State private var globeCenter: CGPoint = .zero
    @State private var globeRadius: CGFloat = 110
    /// 0…1 · how far the thumb has held the key.
    @State private var hold: CGFloat = 0
    @State private var holding = false
    @State private var holdStartedAt: TimeInterval?
    @State private var hint = false
    @State private var closing = false

    private var safe: UIEdgeInsets { ScreenMetrics.safeArea }
    private var mode: SportModeOption? { store.session?.mode }
    private var connected: Bool { data.band.connected || LiveSessionStore.debugFakeWrist }

    /// 0…1 · where the heart sits between rest and the profile's maximum — the store's own
    /// number, so the world and the Dynamic Island never disagree about how hard this is.
    /// The world answers it three ways: it turns faster (0.08 turns/s at rest, 0.34 at the
    /// top), its lime warms into amber past the middle, and its halo kicks harder on a beat.
    private var effort: Double { store.effort }
    private var turnRate: Double { 0.08 + 0.26 * effort }

    var body: some View {
        ZStack(alignment: .topLeading) {
            NB.panelInk
            BayerGlobe(center: globeCenter, radius: globeRadius,
                       bpm: store.liveHR, effort: effort, turnRate: turnRate)
                .animation(.easeInOut(duration: 1.2), value: effort)
            chrome
                .frame(width: screen.width, height: screen.height, alignment: .top)
                .opacity(grown ? 1 : 0)
                .animation(.easeOut(duration: 0.22).delay(grown ? 0.08 : 0), value: grown)
        }
        .frame(width: grown ? screen.width : panelFrame.width,
               height: grown ? screen.height : panelFrame.height)
        .clipShape(RoundedRectangle(cornerRadius: grown ? 0 : NB.R.hero, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: grown ? 0 : NB.R.hero, style: .continuous)
            .stroke(NB.white.opacity(grown ? 0 : 0.08), lineWidth: 1))
        .offset(x: grown ? 0 : panelFrame.minX, y: grown ? 0 : panelFrame.minY)
        .coordinateSpace(name: "takeover")
        .onAppear {
            // Now, not after the pop: the page slides away and the panel is already growing
            // under it, so the session is on screen the moment the sport was picked.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { grown = true }
            }
            #if DEBUG
            // `NB_DEBUG_SESSION_STOP=12` holds STOP for you after that many seconds, so the
            // fold and the widget it leaves on the panel can be watched on a simulator.
            if let s = ProcessInfo.processInfo.environment["NB_DEBUG_SESSION_STOP"], let sec = Double(s) {
                DispatchQueue.main.asyncAfter(deadline: .now() + sec) { stopNow() }
            }
            #endif
        }
        // The band said no. The screen folds back the way it came, with the reason.
        .onChange(of: store.refusal) { _, line in
            guard let line, !closing, let s = store.session else { return }
            closing = true
            let widget = store.refusalWidget(s, line: line)
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { grown = false }
                try? await Task.sleep(for: .milliseconds(440))
                onFolded(widget)
            }
        }
        // Modality belongs to the whole session, not an individual readout leaf.
        // Without a container XCTest identifies the heart-rate value as an alert.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: the column

    private var chrome: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: safe.top + Chrome.gateTopInset)
            header
            // Air under the eyebrow, so the world sits low in its room rather than right
            // beneath the header. Proportional to the screen: on a tall phone the disc is
            // capped by the column's width and this only moves it, on a short one the room
            // is what limits it and the disc gives up a few points to come down.
            Color.clear.frame(height: screen.height * 0.055)
            // The world's room. Its centre is where the globe is drawn — measured here, in
            // the takeover's own space, so the halo can bleed across the whole screen.
            GeometryReader { g in
                let f = g.frame(in: .named("takeover"))
                Color.clear
                    .onAppear { place(f) }
                    .onChange(of: f) { _, new in place(new) }
            }
            clock
            stats
                .padding(.top, 22)
            Text(statusLine)
                .font(NBFont.dot(600, 10.5)).tracking(0.16 * 10.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(statusTint)
                .frame(width: NB.Layout.contentWidth)
                .padding(.top, 20)
                .contentTransition(.opacity)
            stopKey
                .padding(.top, 16)
            Text(helpLine)
                .font(NBFont.ui(300, 12.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(NB.white.opacity(0.42))
                .frame(width: 318)
                .padding(.top, 12)
            Color.clear.frame(height: max(22, safe.bottom + 8))
        }
        .animation(.easeInOut(duration: 0.24), value: store.wrist)
        .animation(.easeInOut(duration: 0.24), value: hint)
    }

    /// LIVE, in lime, with a pip that breathes; the sport beside it. The band's link on the
    /// right — the one thing that can change under a session without the user doing anything.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                LivePip(on: !closing)
                Text(closing ? (store.refusal == nil ? "DONE" : "REFUSED") : "LIVE")
                    .font(NBFont.dot(600, 11)).tracking(0.24 * 11)
                    .foregroundStyle(NB.lime1)
                Text(L("·"))
                    .font(NBFont.dot(600, 11))
                    .foregroundStyle(NB.white.opacity(0.28))
                Text((mode?.name ?? "").uppercased())
                    .font(NBFont.dot(600, 11)).tracking(0.18 * 11)
                    .foregroundStyle(NB.white.opacity(0.78))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                Circle().fill(connected ? NB.lime1 : NB.ember1)
                    .frame(width: 5, height: 5)
                Text(connected ? "HOOP" : "OFFLINE")
                    .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                    .foregroundStyle(connected ? NB.white.opacity(0.42) : NB.ember1)
            }
        }
        .frame(width: NB.Layout.contentWidth, height: 34)
    }

    /// The clock, under the world. Doto, big, white — the world is left whole above it.
    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            VStack(spacing: 6) {
                Text(elapsed(to: tl.date))
                    .font(NBFont.dot(700, 56)).tracking(0.02 * 56)
                    .foregroundStyle(NB.text1)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(L("ELAPSED"))
                    .font(NBFont.dot(600, 10)).tracking(0.3 * 10)
                    .foregroundStyle(NB.white.opacity(0.42))
            }
        }
        .accessibilityLabel("Elapsed \(elapsed(to: Date()))")
    }

    /// The two wrist numbers, each in its own fixed column so they stay put as the digits
    /// change width. Lime while the wrist is being read this second; 32 % once it is not —
    /// a number from before the wrist moved is not a number now.
    private var stats: some View {
        HStack(spacing: 0) {
            readout(value: store.liveHR.map(String.init) ?? Fmt.dash, unit: "BPM",
                    label: L("HEART RATE"), lit: store.liveHR != nil)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("session-heart-rate")
                .accessibilityLabel(L("HEART RATE"))
                .accessibilityValue(store.liveHR.map(String.init) ?? Fmt.dash)
            readout(value: burnText, unit: "KCAL",
                    label: store.energyLabel, lit: store.wrist == .live)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("session-calories")
                .accessibilityLabel(store.energyLabel)
                .accessibilityValue(burnText)
        }
        .frame(width: NB.Layout.contentWidth)
        .padding(.top, 8)
    }

    private func readout(value: String, unit: String, label: String, lit: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(NBFont.brand(700, 34)).tracking(-0.045 * 34)
                    .foregroundStyle(lit ? NB.lime1 : NB.white.opacity(0.32))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit)
                    .font(NBFont.dot(500, 12))
                    .foregroundStyle(NB.white.opacity(lit ? 0.42 : 0.20))
            }
            Text(label)
                .font(NBFont.dot(500, 10)).tracking(0.2 * 10)
                .foregroundStyle(NB.white.opacity(lit ? 0.34 : 0.20))
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.24), value: lit)
    }

    /// The only exit. Held for 0.9 s: the ink wipes across the key under the thumb and the
    /// session ends as it reaches the far edge; let go early and it springs back with the
    /// one line that says how.
    private var stopKey: some View {
        ZStack {
            Capsule().fill(NB.lime1)
            GeometryReader { g in
                Capsule().fill(NB.carbon.opacity(0.34))
                    .frame(width: max(0, g.size.width * hold))
            }
            .clipShape(Capsule())
            Text(store.stopping ? "STOPPING…" : closing ? (store.refusal == nil ? "SAVED" : "NOT STARTED")
                 : holding ? "KEEP HOLDING" : "STOP SESSION")
                .font(NBFont.ui(500, 12)).tracking(0.2 * 12)
                .foregroundStyle(NB.carbon)
                .contentTransition(.opacity)
        }
        .frame(width: NB.Layout.contentWidth, height: 52)
        .scaleEffect(holding ? 0.985 : 1)
        .animation(.easeOut(duration: 0.12), value: holding)
        .contentShape(Capsule())
        .overlay {
            // The native recognizer owns the threshold while the finger is down,
            // independently of home's SwiftUI page-gesture arbitration.
            PressHold(minimumDuration: 0.9,
                      onTouch: { down in
                          if down { beginHold() } else { endHold() }
                      },
                      onArm: { stopNow() },
                      onLift: { _ in endHold() },
                      onTap: { showHoldHint() },
                      diagnosticName: "session-stop",
                      allowsQualifiedRelease: true)
                .clipShape(Capsule())
        }
        .disabled(closing || store.stopping || store.opening)
        .opacity(store.opening ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Stop session"))
        .accessibilityIdentifier("session-stop")
        .accessibilityHint(L("Press and hold for one second"))
        .accessibilityAction { stopNow() }
    }

    // MARK: words

    private var burnText: String {
        guard store.hasCalories else { return Fmt.dash }
        guard store.wrist != .off || store.kcal > 0 else { return Fmt.dash }
        return "\(Int(store.kcal.rounded()))"
    }

    private var statusLine: String {
        if let r = store.refusal { return L("REFUSED · %@", r.uppercased()) }
        if closing { return L("SAVED · FOLDING BACK") }
        if store.stopping { return L("CLOSING THE MODE ON THE BAND") }
        if store.opening { return L("OPENING %@ ON THE BAND", (mode?.name ?? "").uppercased()) }
        if store.session?.joined == true, store.wrist == .live { return L("JOINED THE SESSION ALREADY ON THE BAND · LIVE") }
        if let e = store.errorLine { return e.uppercased() }
        if hint { return L("HOLD THE KEY TO STOP") }
        switch store.wrist {
        case .off:       return L("TIMING · THE WRIST IS NOT BEING READ")
        case .reaching:  return L("REACHING THE WRIST")
        case .live:      return L("HEART RATE FROM THE WRIST · LIVE")
        case .noContact: return L("NO CONTACT · TIGHTEN THE BAND")
        case .offline:   return L("BAND OFFLINE · THE CLOCK KEEPS RUNNING")
        case .paused:    return L("PAUSED ON THE BAND")
        }
    }

    private var statusTint: Color {
        if store.refusal != nil { return NB.ember2 }
        if closing || store.stopping || store.opening { return NB.lime1.opacity(0.85) }
        if store.errorLine != nil { return NB.ember2 }
        if hint { return NB.white.opacity(0.55) }
        switch store.wrist {
        case .live:      return NB.lime1
        case .reaching:  return NB.lime1.opacity(0.85)
        case .noContact: return NB.ember2
        // 06 rule 07 · device-side states are 32 % grey, not amber and not red.
        case .off, .offline, .paused: return NB.white.opacity(0.32)
        }
    }

    private var helpLine: String {
        closing ? "The session lands on the panel."
                : "Hold to stop. The band keeps the session open until you do."
    }

    private func elapsed(to now: Date) -> String {
        let sec = max(0, Int(now.timeIntervalSince(store.session?.startedAt ?? now)))
        if sec >= 3600 {
            return String(format: "%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
        }
        return String(format: "%02d:%02d", sec / 60, sec % 60)
    }

    // MARK: geometry

    private func place(_ f: CGRect) {
        guard f.width > 0, f.height > 0 else { return }
        globeCenter = CGPoint(x: f.midX, y: f.midY)
        // The disc: 58 % of the column, and never taller than the room it has. The room is
        // shorter than it was (the air above it), so it takes a little more of what is left.
        globeRadius = min(screen.width * 0.29, f.height * 0.46)
    }

    // MARK: the hold

    private func beginHold() {
        guard !holding, !closing, !store.stopping, !store.opening else { return }
        holdStartedAt = ProcessInfo.processInfo.systemUptime
        Self.log.notice("session stop hold touch began")
        holding = true
        hint = false
        withAnimation(.linear(duration: 0.9)) { hold = 1 }
    }

    private func endHold() {
        guard holding else { return }
        let elapsed = holdStartedAt.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
        Self.log.notice("session stop hold lifted elapsed=\(elapsed, privacy: .public)")
        holdStartedAt = nil
        holding = false
        guard !closing, !store.stopping, !store.opening else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hold = 0 }
    }

    private func showHoldHint() {
        guard !closing, !store.stopping, !store.opening else { return }
        hint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { hint = false }
    }

    private func stopNow() {
        guard !closing, !store.stopping, !store.opening else { return }
        let elapsed = holdStartedAt.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
        Self.log.notice("session stop committed elapsed=\(elapsed, privacy: .public)")
        holdStartedAt = nil
        holding = false
        Haptics.impact(.rigid)
        Task {
            let widget = await store.stop()
            closing = true
            hold = 1
            // A breath on DONE, then the fold: the panel takes the numbers back.
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) { grown = false }
            try? await Task.sleep(for: .milliseconds(480))
            onFolded(widget)
        }
    }
}

/// The LIVE pip: lime, breathing on a slow two-second cycle. Under Reduce Motion it holds.
private struct LivePip: View {
    var on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = true

    var body: some View {
        ZStack {
            Circle().fill(NB.lime1.opacity(lit ? 0.22 : 0.06)).frame(width: 14, height: 14)
            Circle().fill(NB.lime1).frame(width: 6, height: 6)
        }
        .opacity(on ? 1 : 0.5)
        .onAppear {
            guard on, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { lit.toggle() }
        }
    }
}
