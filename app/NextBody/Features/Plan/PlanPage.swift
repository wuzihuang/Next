import CoreHaptics
import SwiftUI
import UIKit

/// Paper 04E · 14 BRIEF. Lime strip, then five title/subtitle slabs.
struct PlanPage: View {
    let face: PlanFaceMath.Face
    var flatten: CGFloat
    var reduceMotion: Bool
    var closeEnabled = true
    var done: (PlanFaceMath.ActionKind) -> Bool = { _ in false }
    var regenerating = false
    var onToggle: (PlanFaceMath.ActionKind) -> Void = { _ in }
    var onRegenerate: () -> Void = {}
    var onCloseDragChanged: (CGFloat) -> Void
    var onCloseDragEnded: (CGFloat, CGFloat) -> Void

    @State private var completing: Set<PlanFaceMath.ActionKind> = []

    var body: some View {
        ZStack(alignment: .top) {
            NB.carbon.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    chrome
                    summary
                    tasks
                }
                .frame(maxWidth: .infinity)
                .background {
                    PlanClosePan(enabled: closeEnabled,
                                 onChanged: onCloseDragChanged,
                                 onEnded: onCloseDragEnded)
                    .frame(width: 0, height: 0)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 28) {
                regenerate
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.page")
    }

    private var chrome: some View {
        VStack(spacing: 7) {
            PlanChevron(up: false, playing: !reduceMotion && flatten < 0.02, flatten: flatten,
                        armed: false, reduceMotion: reduceMotion)
            Text(L("TODAY · FIVE TASKS"))
                .font(NBFont.dot(600, 9))
                .tracking(em: 0.24, size: 9)
                .foregroundStyle(NB.lime1.opacity(0.60))
        }
        // Home ignores the vertical safe area, so this page has to clear
        // the Dynamic Island itself — 8pt of air under the cutout.
        .padding(.top, ScreenMetrics.safeArea.top + 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(L("Swipe down for home"))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline)
                .font(NBFont.brand(700, 22))
                .tracking(em: -0.03, size: 22)
                .foregroundStyle(NB.panelInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("plan.eyebrow")
            Text(briefCopy)
                .font(NBFont.ui(400, 14))
                .foregroundStyle(NB.panelInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .padding(.horizontal, 24)
        .background(NB.lime1)
    }

    /// Open rows first, done rows sink to the bottom. A row that is still
    /// settling (strike drawing, ink greying) holds its place so the eye sees
    /// the tick land before the row moves; it sinks once `completing` clears.
    private var orderedActions: [PlanFaceMath.Action] {
        let open = face.actions.filter { !settled($0.kind) }
        let sunk = face.actions.filter { settled($0.kind) }
        return open + sunk
    }

    private func settled(_ kind: PlanFaceMath.ActionKind) -> Bool {
        done(kind) && !completing.contains(kind)
    }

    private var tasks: some View {
        VStack(spacing: 8) {
            ForEach(orderedActions, id: \.kind) { action in
                taskSlab(action)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 16)
        .animation(reduceMotion ? .easeOut(duration: 0.08) : .spring(duration: 0.42, bounce: 0.12),
                   value: orderedActions.map(\.kind))
    }

    private func taskSlab(_ action: PlanFaceMath.Action) -> some View {
        let on = completing.contains(action.kind) || done(action.kind)
        let title = taskTitle(action)
        return Button {
            complete(action.kind)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                checkmark(on: on)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(NBFont.brand(600, 16))
                        .tracking(em: -0.02, size: 16)
                        .foregroundStyle(on ? NB.text3Prod : NB.text1)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .overlay(alignment: .leading) { strike(on: on) }
                    Text(taskDetail(action))
                        .font(NBFont.ui(400, 13))
                        .foregroundStyle(on ? NB.text3Prod.opacity(0.6) : NB.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(NB.carbon4.opacity(on ? 0.6 : 1))
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.26), value: on)
        }
        .buttonStyle(HotZoneTap())
        .disabled(on)
        .accessibilityLabel(on ? L("%@, done", title) : title)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("plan.check.\(action.kind.rawValue)")
    }

    /// The strike draws left to right over the title as the ink greys. It is a
    /// grow, not a fade: a line appearing all at once reads as a render glitch.
    private func strike(on: Bool) -> some View {
        Capsule()
            .fill(NB.text3Prod)
            .frame(height: 1.5)
            .scaleEffect(x: on ? 1 : 0, y: 1, anchor: .leading)
            .opacity(on ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.28).delay(0.06), value: on)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Tap → two needles → tick fills, strike draws, ink greys → row sinks.
    /// The hold before `completing` clears is the strike's own duration, so the
    /// row only moves once the line has reached the end of the title.
    private func complete(_ kind: PlanFaceMath.ActionKind) {
        guard !done(kind), !completing.contains(kind) else { return }
        completing.insert(kind)
        PlanCompleteCue.play()
        onToggle(kind)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 40 : 520))
            completing.remove(kind)
        }
    }

    private func checkmark(on: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(on ? NB.lime1 : .clear)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(NB.lime1, lineWidth: 1.5)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NB.carbon)
                .opacity(on ? 1 : 0)
                .scaleEffect(on ? 1 : 0.55)
        }
        .frame(width: 20, height: 20)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: on)
    }

    private var regenerate: some View {
        Button(action: onRegenerate) {
            Text(regenerating ? L("GENERATING…") : L("REGENERATE"))
                .font(NBFont.dot(700, 13))
                .tracking(em: 0.16, size: 13)
                .foregroundStyle(NB.text3Prod.opacity(regenerating ? 0.70 : 1))
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 10)
        }
        .buttonStyle(HotZoneTap())
        .disabled(regenerating)
        .accessibilityIdentifier("plan.regenerate")
        .frame(maxWidth: .infinity)
        .background(NB.carbon)
    }

    private var headline: String {
        if face.empty { return L("NO NIGHT YET") }
        switch face.weakest {
        case .recovery:     return L("Take the day down")
        case .regularity:   return L("Bring bedtime back")
        case .architecture: return L("Fix last night's structure")
        case .duration:     return L("Sleep long enough")
        case nil:           return L("TODAY'S CONTENTS")
        }
    }

    private var briefCopy: String {
        if face.empty {
            return L("No scored night. The plan stays silent.")
        }
        switch face.weakest {
        case .recovery:
            return L("The night did not finish. Keep today light.")
        case .regularity:
            return L("Bedtime drifted. Move it toward your median.")
        case .architecture:
            return L("Last night's structure was the weak group. Keep the day quiet.")
        case .duration:
            return L("The night was short. Get to bed on time.")
        case nil:
            return L("Keep today light.")
        }
    }

    private func taskTitle(_ action: PlanFaceMath.Action) -> String {
        switch action.kind {
        case .bed:
            if action.trailing == PlanFaceMath.dash { return L("Set a bedtime") }
            return L("Lights out at %@", action.trailing)
        case .load:
            if action.trailing == PlanFaceMath.dash { return L("Cap today's load") }
            return L("Cap load at %@", action.trailing)
        case .strength:
            return action.trailing == "RUN TOMORROW"
                ? L("Run tomorrow")
                : L("Leave strength off")
        case .meal:
            return action.trailing == "LOGGED"
                ? L("Leave the meals as they are")
                : L("Log the three meals")
        case .quiet:
            return L("Keep the afternoon quiet")
        }
    }

    private func taskDetail(_ action: PlanFaceMath.Action) -> String {
        switch action.kind {
        case .bed:
            return action.trailing == PlanFaceMath.dash
                ? L("No night to read a median from.")
                : L("Your median bedtime, not a new rule.")
        case .load:
            return action.trailing == PlanFaceMath.dash
                ? L("No load target yet.")
                : L("Easy work only until the night rebuilds.")
        case .strength:
            return action.trailing == "RUN TOMORROW"
                ? L("Strength waits one more sleep.")
                : L("The night does not ask for it.")
        case .meal:
            return action.trailing == "LOGGED"
                ? L("Three plates already logged.")
                : L("The plate is the only open check.")
        case .quiet:
            return L("No extra session after four.")
        }
    }

}

/// Two short needles, 150ms apart. UIKit's second rigid tap merges into one;
/// Core Haptics transients stay two. No continuous event, no success-notification tail.
@MainActor
private enum PlanCompleteCue {
    private static var engine: CHHapticEngine?
    private static let fallback = UIImpactFeedbackGenerator(style: .rigid)

    static func play() {
        guard Haptics.on else { return }
        fallback.prepare()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            fallback.impactOccurred(intensity: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard Haptics.on else { return }
                fallback.impactOccurred(intensity: 1)
            }
            return
        }
        do {
            if engine == nil {
                let next = try CHHapticEngine()
                next.playsHapticsOnly = true
                next.isAutoShutdownEnabled = true
                engine = next
            }
            try engine?.start()
            let first = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
            ], relativeTime: 0)
            let second = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
            ], relativeTime: 0.15)
            let player = try engine?.makePlayer(with: CHHapticPattern(events: [first, second], parameters: []))
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback.impactOccurred(intensity: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard Haptics.on else { return }
                fallback.impactOccurred(intensity: 1)
            }
        }
    }
}

enum PlanSnapshot {
    private static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd"
        return formatter
    }()

    static func make(today: DailyMetrics, history: [DailyMetrics],
                     scores: [String: SleepScore], now: Date = Date()) -> PlanFaceMath.Face {
        let past = history.filter { $0.day < today.day }.sorted { $0.day < $1.day }
        let yesterday = past.last
        let dayBefore = past.dropLast().last
        let load = PlanFaceMath.Load(
            yesterday: yesterday?.trainingLoad,
            dayBefore: dayBefore?.trainingLoad,
            target: today.targetLoad ?? yesterday?.targetLoad,
            activeMinutes: today.activeMinutes)
        let mealsLogged = today.fuelState != .unlogged
        let scored = (0..<7).compactMap { back -> (UserDay, SleepScore)? in
            let day = today.day.adding(days: -back)
            guard let score = scores[day.key] else { return nil }
            return (day, score)
        }
        let readyFrom = scored.last.map { monthDay.string(from: $0.0.date) }
        let readyTo = scored.first.map { monthDay.string(from: $0.0.date) }
        let nightScore = scores[today.day.key] ?? today.sleepScore
        let night = nightScore.map { score in
            PlanFaceMath.Night(
                score: score.score,
                duration: score.duration,
                architecture: score.architecture,
                recovery: score.recovery,
                regularity: score.regularity,
                personalWeight: score.personalWeight,
                hrvMs: score.inputs["hrv_ms"],
                bedOffset: score.inputs["bed_offset"],
                nightIndex: scores.count)
        }
        return PlanFaceMath.face(
            night: night,
            load: load,
            mealsLogged: mealsLogged,
            scoredNightCount: scores.count,
            readyFrom: readyFrom,
            readyTo: readyTo,
            now: now)
    }
}

/// ADR-0001 · the catalog's own pan is the close pull. A second recognizer
/// that only began at offset 0 lost the race with the list, so the face
/// felt glued on unless the user first parked at the exact top. Downward
/// travel freezes the list and moves the page; upward stays a scroll.
private struct PlanClosePan: UIViewRepresentable {
    var enabled: Bool
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onWindow = { [weak view] _ in
            guard let view else { return }
            context.coordinator.attach(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.attach(from: uiView)
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ProbeView: UIView {
        var onWindow: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindow?(window)
        }
    }

    final class Coordinator: NSObject {
        var enabled = true
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
        private weak var scroll: UIScrollView?
        private var pulling = false
        private var pinned = CGPoint.zero
        private var savedBounces = true

        func attach(from probe: UIView) {
            if let scroll = Self.nearestScrollView(from: probe) {
                hook(scroll)
                return
            }
            DispatchQueue.main.async { [weak self, weak probe] in
                guard let self, let probe, self.scroll == nil else { return }
                if let scroll = Self.nearestScrollView(from: probe) {
                    self.hook(scroll)
                }
            }
        }

        func detach() {
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(handle(_:)))
            restore()
            scroll = nil
        }

        private func hook(_ scroll: UIScrollView) {
            if self.scroll === scroll { return }
            detach()
            self.scroll = scroll
            scroll.panGestureRecognizer.addTarget(self, action: #selector(handle(_:)))
        }

        static func nearestScrollView(from view: UIView) -> UIScrollView? {
            var current: UIView? = view
            while let node = current {
                if let scroll = node as? UIScrollView { return scroll }
                current = node.superview
            }
            return nil
        }

        @objc func handle(_ gesture: UIPanGestureRecognizer) {
            guard enabled, let scroll else { return }
            let t = gesture.translation(in: scroll)
            let v = gesture.velocity(in: scroll)
            switch gesture.state {
            case .began:
                pulling = false
            case .changed:
                if !pulling {
                    guard t.y > 0, t.y >= abs(t.x) else { return }
                    pulling = true
                    pinned = scroll.contentOffset
                    savedBounces = scroll.bounces
                    scroll.bounces = false
                }
                guard pulling else { return }
                scroll.setContentOffset(pinned, animated: false)
                onChanged(max(0, t.y))
            case .ended:
                if pulling { onEnded(max(0, t.y), v.y) }
                restore()
            case .cancelled, .failed:
                if pulling { onEnded(0, 0) }
                restore()
            default:
                break
            }
        }

        private func restore() {
            pulling = false
            scroll?.bounces = savedBounces
        }
    }
}
