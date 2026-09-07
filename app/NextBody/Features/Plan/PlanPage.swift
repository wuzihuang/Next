import CoreHaptics
import SwiftUI
import UIKit

/// Paper 04E · 14 BRIEF. Lime strip, then the tasks the server wrote.
///
/// ADR 0018 · the plan is a server row: one title, one summary, three to five tasks the
/// model chose. While the first one of the day is being written, the thinking stream runs
/// here; a tick is the user's own claim and never calls the model.
struct PlanPage: View {
    let plan: DailyPlan?
    var checked: Set<String> = []
    var flatten: CGFloat
    var reduceMotion: Bool
    var closeEnabled = true
    var loading = false
    var generating = false
    var errorLine: String?
    var thinkingReading: String?
    var thoughts: [AIService.Thought] = []
    var thinkingStartedAt: Date = Date()
    var onTick: (String) -> Void = { _ in }
    var onRegenerate: () -> Void = {}
    var onCloseDragChanged: (CGFloat) -> Void
    var onCloseDragEnded: (CGFloat, CGFloat) -> Void

    @State private var completing: Set<String> = []

    var body: some View {
        ZStack(alignment: .top) {
            NB.carbon.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    chrome
                    if generating {
                        thinking
                    } else if let plan {
                        summary(plan)
                        if let errorLine { failed(errorLine) }
                        tasks(plan)
                    } else {
                        empty
                    }
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
            Text(plan.map { L("TODAY · %d TASKS", $0.tasks.count) } ?? L("TODAY"))
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

    /// The same stream the home panel prints while a turn runs.
    private var thinking: some View {
        ThinkingStage(question: L("TODAY'S PLAN"), reading: thinkingReading,
                      thoughts: thoughts, startedAt: thinkingStartedAt)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 360)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("plan.thinking")
    }

    private func summary(_ plan: DailyPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.title)
                .font(NBFont.brand(700, 22))
                .tracking(em: -0.03, size: 22)
                .foregroundStyle(NB.panelInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("plan.eyebrow")
            Text(plan.summary)
                .font(NBFont.ui(400, 14))
                .foregroundStyle(NB.panelInk)
                .fixedSize(horizontal: false, vertical: true)
            if !plan.readFrom.isEmpty {
                Text(L("AI READ %@ → %@", monthDay(plan.readFrom), monthDay(plan.readTo)))
                    .font(NBFont.dot(500, 10))
                    .tracking(em: 0.16, size: 10)
                    .foregroundStyle(NB.panelInk.opacity(0.7))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .padding(.horizontal, 24)
        .background(NB.lime1)
    }

    /// A regenerate that did not land keeps the plan on screen and says so under it.
    private func failed(_ line: String) -> some View {
        Text(line)
            .font(NBFont.dot(500, 11))
            .tracking(em: 0.12, size: 11)
            .foregroundStyle(NB.alert2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .accessibilityIdentifier("plan.error")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loading ? L("READING…") : L("NO PLAN YET"))
                .font(NBFont.brand(700, 22))
                .tracking(em: -0.03, size: 22)
                .foregroundStyle(NB.panelInk)
            Text(errorLine ?? (loading ? L("Looking for today's plan.") : L("Pull one from the last three days.")))
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
    private func orderedTasks(_ plan: DailyPlan) -> [DailyPlan.Task] {
        let open = plan.tasks.filter { !settled($0.id) }
        let sunk = plan.tasks.filter { settled($0.id) }
        return open + sunk
    }

    private func settled(_ id: String) -> Bool {
        checked.contains(id) && !completing.contains(id)
    }

    private func tasks(_ plan: DailyPlan) -> some View {
        let ordered = orderedTasks(plan)
        return VStack(spacing: 8) {
            ForEach(ordered) { task in
                taskSlab(task)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 16)
        .animation(reduceMotion ? .easeOut(duration: 0.08) : .spring(duration: 0.42, bounce: 0.12),
                   value: ordered.map(\.id))
    }

    private func taskSlab(_ task: DailyPlan.Task) -> some View {
        let on = completing.contains(task.id) || checked.contains(task.id)
        return Button {
            complete(task.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                checkmark(on: on)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(NBFont.brand(600, 16))
                        .tracking(em: -0.02, size: 16)
                        .foregroundStyle(on ? NB.text3Prod : NB.text1)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .overlay(alignment: .leading) { strike(on: on) }
                    Text(task.sub)
                        .font(NBFont.ui(400, 13))
                        .foregroundStyle(on ? NB.text3Prod.opacity(0.6) : NB.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let basis = task.basis {
                        Text(basis)
                            .font(NBFont.dot(500, 10))
                            .tracking(em: 0.12, size: 10)
                            .foregroundStyle(NB.text3Prod)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
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
        .accessibilityLabel(on ? L("%@, done", task.title) : task.title)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("plan.check.\(task.id)")
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
    private func complete(_ id: String) {
        guard !checked.contains(id), !completing.contains(id) else { return }
        completing.insert(id)
        PlanCompleteCue.play()
        onTick(id)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 40 : 520))
            completing.remove(id)
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
            Text(generating ? L("GENERATING…") : (plan == nil ? L("GENERATE") : L("REGENERATE")))
                .font(NBFont.dot(700, 13))
                .tracking(em: 0.16, size: 13)
                .foregroundStyle(NB.text3Prod.opacity(generating ? 0.70 : 1))
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 10)
        }
        .buttonStyle(HotZoneTap())
        .disabled(generating || loading)
        .accessibilityIdentifier("plan.regenerate")
        .frame(maxWidth: .infinity)
        .background(NB.carbon)
    }

    private static let dayIn: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let dayOut: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MM-dd"; return f
    }()
    private func monthDay(_ key: String) -> String {
        Self.dayIn.date(from: key).map { Self.dayOut.string(from: $0) } ?? key
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
