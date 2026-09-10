import SwiftUI
import UIKit

/// Numbered suggestions grounded in the latest available data, without task completion.
/// ADR 0022 · the face reads the day's set. While today's is still being made it shows
/// yesterday's marked stale, or the thinking stream when there is nothing earlier.
struct PlanPage: View {
    let plan: DailyPlan?
    var flatten: CGFloat
    var reduceMotion: Bool
    var closeEnabled = true
    var generating = false
    /// The set on screen is from an earlier day.
    var stale = false
    /// Every automatic attempt today failed; only REFRESH is left.
    var exhausted = false
    var generatedAt: Date?
    var errorLine: String?
    var thinkingReading: String?
    var thoughts: [AIService.Thought] = []
    var thinkingStartedAt: Date = Date()
    var onRegenerate: () -> Void = {}
    var onCloseDragChanged: (CGFloat) -> Void
    var onCloseDragEnded: (CGFloat, CGFloat) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            NB.carbon.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    chrome
                    if generating, let plan {
                        making
                        summary(plan)
                        if !plan.tasks.isEmpty { suggestions(plan) }
                    } else if generating {
                        thinking
                        hint
                    } else if let plan {
                        summary(plan)
                        if let errorLine { failed(errorLine) }
                        if !plan.tasks.isEmpty { suggestions(plan) }
                        if !plan.sources.isEmpty {
                            WebSourcesButton(sources: plan.sources.map { WebReference(title: $0.title, url: $0.url) })
                                .padding(.top, 16)
                        }
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
            .safeAreaInset(edge: .bottom, spacing: 28) { regenerate }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.page")
    }

    private var chrome: some View {
        VStack(spacing: 7) {
            PlanChevron(up: false, playing: !reduceMotion && flatten < 0.02, flatten: flatten,
                        armed: false, reduceMotion: reduceMotion)
            Text(chromeLabel)
                .font(NBFont.dot(600, 9))
                .tracking(em: 0.24, size: 9)
                .foregroundStyle(NB.lime1.opacity(0.60))
        }
        .padding(.top, ScreenMetrics.safeArea.top + 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(L("Swipe down for home"))
    }

    private var chromeLabel: String {
        guard !generating, let plan else { return L("SUGGESTIONS") }
        return stale ? L("YESTERDAY · %d SUGGESTIONS", plan.tasks.count) : L("TODAY · %d SUGGESTIONS", plan.tasks.count)
    }

    /// Live, the model's own lines arrive; after coming back to a run that kept going on the
    /// server there is nothing to replay, so the reading line names the wait itself.
    private var thinking: some View {
        ThinkingStage(question: L("PERSONAL SUGGESTIONS"), reading: thinkingReading ?? "plan.generate",
                      thoughts: thoughts, startedAt: thinkingStartedAt)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 360)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("plan.thinking")
    }

    /// The wait is the server's, not the screen's: leaving does not lose it.
    private var hint: some View {
        Text(L("You can close this and come back in a few minutes."))
            .font(NBFont.ui(400, 13))
            .foregroundStyle(NB.text3Prod)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .accessibilityIdentifier("plan.hint")
    }

    /// Yesterday's set stays readable while today's is made behind it.
    private var making: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("GENERATING TODAY'S SUGGESTIONS"))
                .font(NBFont.dot(600, 10))
                .tracking(em: 0.16, size: 10)
                .foregroundStyle(NB.lime1)
            Text(L("You can close this and come back in a few minutes."))
                .font(NBFont.ui(400, 13))
                .foregroundStyle(NB.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .accessibilityIdentifier("plan.making")
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
                .accessibilityIdentifier(plan.tasks.isEmpty ? "plan.empty" : "plan.summary")
            if stale {
                Text(L("YESTERDAY'S SUGGESTIONS"))
                    .font(NBFont.dot(500, 10))
                    .foregroundStyle(NB.panelInk.opacity(0.7))
                    .padding(.top, 4)
                    .accessibilityIdentifier("plan.stale")
            } else if let generatedAt, errorLine == nil {
                Text(L("UPDATED %@", generatedAt.formatted(date: .omitted, time: .shortened)))
                    .font(NBFont.dot(500, 10))
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

    private func failed(_ line: String) -> some View {
        Text(line)
            .font(NBFont.ui(500, 13))
            .foregroundStyle(NB.alert2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .accessibilityIdentifier("plan.error")
    }

    /// Nothing to show and nothing running: today's could not be made, or there is no
    /// connection to read it. Never a resting state on its own.
    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exhausted ? L("COULD NOT GENERATE TODAY") : L("SUGGESTIONS NOT READY"))
                .font(NBFont.brand(700, 22))
                .tracking(em: -0.03, size: 22)
                .foregroundStyle(NB.panelInk)
                .accessibilityIdentifier("plan.eyebrow")
            Text(errorLine ?? L("Today's suggestions are made when the app opens. Refresh to make them now."))
                .font(NBFont.ui(400, 14))
                .foregroundStyle(NB.panelInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(errorLine == nil ? "plan.empty" : "plan.error")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .padding(.horizontal, 24)
        .background(NB.lime1)
    }

    private func suggestions(_ plan: DailyPlan) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(plan.tasks.enumerated()), id: \.element.id) { index, suggestion in
                suggestionSlab(suggestion, number: index + 1)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 16)
    }

    private func suggestionSlab(_ suggestion: DailyPlan.Task, number: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number).")
                .font(NBFont.brand(600, 20))
                .foregroundStyle(NB.lime1)
                .frame(width: 24, alignment: .leading)
                .accessibilityIdentifier("plan.number.\(number)")
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.title)
                    .font(NBFont.brand(600, 16))
                    .tracking(em: -0.02, size: 16)
                    .foregroundStyle(NB.text1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(suggestion.sub)
                    .font(NBFont.ui(400, 14))
                    .foregroundStyle(NB.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if let basis = suggestion.basis {
                    Text(basis)
                        .font(NBFont.ui(400, 12))
                        .foregroundStyle(NB.text3Prod)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NB.carbon4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan.suggestion.\(number)")
    }

    private var regenerate: some View {
        Button(action: onRegenerate) {
            Text(generating ? L("UPDATING SUGGESTIONS…") : L("REFRESH SUGGESTIONS"))
                .font(NBFont.dot(700, 13))
                .tracking(em: 0.16, size: 13)
                .foregroundStyle(NB.text3Prod.opacity(generating ? 0.70 : 1))
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 10)
        }
        .buttonStyle(HotZoneTap())
        .disabled(generating)
        .accessibilityIdentifier("plan.regenerate")
        .frame(maxWidth: .infinity)
        .background(NB.carbon)
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
