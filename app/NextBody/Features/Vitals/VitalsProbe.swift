import SwiftUI
import UIKit

/// Copy for the 探点 readout. Time on the left, the sample (or `——`) on the right.
enum VitalsProbeCopy {
    static func line(_ time: String, _ value: String) -> String {
        L("%@ · %@", time, value)
    }

    static func gap(_ time: String) -> String {
        line(time, Fmt.dash)
    }

    /// One envelope's readout. A slot that reduced a single tick has nothing to hyphenate,
    /// so it prints as the one value it is rather than as `62–62`.
    static func range(_ time: String, low: String, high: String, unit: String) -> String {
        let reading = low == high ? low : L("%@–%@", low, high)
        return line(time, unit.isEmpty ? reading : L("%@ %@", reading, unit))
    }
}

/// The shared 探点 shell: readout above the field, 标线 on top of it, and a recognizer
/// that axis-locks against the page scroll. Charts draw the series; this owns the touch.
struct VitalsChartProbe<Content: View>: View {
    let series: VitalsProbeMath.Series
    let tint: Color
    var height: CGFloat = 160
    var gapFraction: Double = 0
    var leadingInset: CGFloat = 0
    /// The scale rail's width plus its gap. The field stops where the rail begins.
    var trailingInset: CGFloat = 0
    var clockAt: (Double) -> String = { _ in Fmt.dash }
    var accessibilityTitle: String = L("CHART")
    var accessibilityName: String = "vitals.probe"
    @ViewBuilder var content: (_ probing: Bool) -> Content

    @State private var pick: VitalsProbeMath.Pick?
    @State private var lastIdentity: String?
    #if DEBUG
    @State private var lastProbedText = ""
    #endif

    private var probing: Bool { pick != nil }

    private var gapCopy: String {
        VitalsProbeCopy.gap(clockAt(pick?.marker ?? 1))
    }

    private var readout: String {
        VitalsProbeMath.readout(pick: pick, idle: series.idleText, gap: gapCopy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(readout)
                    .font(NBFont.dot(600, 11)).tracking(0.06 * 11)
                    .foregroundStyle(probing ? tint : NB.white.opacity(0.72))
                    .lineLimit(1).minimumScaleFactor(0.75)

                ZStack {
                    content(probing)
                    if let pick {
                        marker(pick)
                            .allowsHitTesting(false)
                    }
                    if !series.isEmpty {
                        ProbeDrag(
                            leadingInset: leadingInset,
                            trailingInset: trailingInset,
                            onBegan: { apply($0) },
                            onMove: { apply($0) },
                            onEnd: { clear() }
                        )
                    }
                }
                .frame(height: height)
                .contentShape(Rectangle())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(accessibilityName)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(readout)
            .accessibilityHint(L("SWIPE UP OR DOWN TO READ EACH SAMPLE"))
            .accessibilityAdjustableAction { direction in
                step(direction)
            }

            #if DEBUG
            Text(lastProbedText)
                .accessibilityIdentifier("\(accessibilityName).last")
                .accessibilityLabel(L("LAST PROBE"))
                .accessibilityValue(lastProbedText)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
            #endif
        }
    }

    private func marker(_ pick: VitalsProbeMath.Pick) -> some View {
        Canvas { ctx, size in
            let field = size.width - leadingInset - trailingInset
            let x = leadingInset + field * pick.marker
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(line, with: .color(tint.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            if pick.snaps, let yFraction = pick.yFraction, pick.text != nil {
                let y = size.height * yFraction
                ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                         with: .color(tint))
            }
        }
    }

    private func apply(_ fraction: CGFloat) {
        let next = series.pick(finger: Double(fraction), gapFraction: gapFraction)
        if next.snaps, next.identity != lastIdentity {
            Haptics.selection()
        }
        lastIdentity = next.identity
        pick = next
        #if DEBUG
        lastProbedText = VitalsProbeMath.readout(
            pick: next, idle: series.idleText, gap: VitalsProbeCopy.gap(clockAt(next.marker)))
        #endif
    }

    private func clear() {
        pick = nil
        lastIdentity = nil
    }

    private func step(_ direction: AccessibilityAdjustmentDirection) {
        let increment: Bool
        switch direction {
        case .increment: increment = true
        case .decrement: increment = false
        @unknown default: return
        }
        guard let next = VitalsProbeMath.voStep(
            items: series.voItems, currentIdentity: pick?.identity, increment: increment
        ) else { return }
        pick = next
        lastIdentity = next.identity
        #if DEBUG
        lastProbedText = next.text ?? VitalsProbeCopy.gap(clockAt(next.marker))
        #endif
    }
}

/// UIKit pan outside SwiftUI's graph, the same reason the dock's press lives in UIKit:
/// a child SwiftUI drag is silent until the page scroll fails. Horizontal travel past the
/// 10pt dead zone owns the touch; vertical travel fails so the page can scroll.
private struct ProbeDrag: UIViewRepresentable {
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0
    var onBegan: (CGFloat) -> Void
    var onMove: (CGFloat) -> Void
    var onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let pan = ProbePan(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        pan.cancelsTouchesInView = false
        pan.leadingInset = leadingInset
        pan.trailingInset = trailingInset
        view.addGestureRecognizer(pan)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onMove = onMove
        context.coordinator.onEnd = onEnd
        context.coordinator.view = view
        if let pan = view.gestureRecognizers?.first as? ProbePan {
            pan.leadingInset = leadingInset
            pan.trailingInset = trailingInset
        }
    }

    final class Coordinator: NSObject {
        var onBegan: (CGFloat) -> Void = { _ in }
        var onMove: (CGFloat) -> Void = { _ in }
        var onEnd: () -> Void = {}
        weak var view: UIView?
        private weak var scroll: UIScrollView?
        /// What the scroll was before the probe borrowed it. A page some other owner had
        /// already locked must not be handed back scrolling when a probe ends.
        private var scrollWasEnabled = true

        @objc func handle(_ pan: ProbePan) {
            switch pan.state {
            case .began:
                lockScroll()
                onBegan(pan.fraction)
            case .changed:
                onMove(pan.fraction)
            case .ended, .cancelled, .failed:
                unlockScroll()
                onEnd()
            default:
                break
            }
        }

        private func lockScroll() {
            var node = view?.superview
            while let current = node {
                if let scroll = current as? UIScrollView {
                    self.scroll = scroll
                    scrollWasEnabled = scroll.isScrollEnabled
                    scroll.isScrollEnabled = false
                    return
                }
                node = current.superview
            }
        }

        private func unlockScroll() {
            scroll?.isScrollEnabled = scrollWasEnabled
            scroll = nil
            scrollWasEnabled = true
        }
    }
}

/// Custom pan that stays `.possible` through the dead zone. Assigning `.possible` is
/// illegal; failed/ended are only written from a state that can legally leave.
private final class ProbePan: UIGestureRecognizer {
    var fraction: CGFloat = 0
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0
    private var origin: CGPoint = .zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard touches.count == 1, let view, let touch = touches.first else {
            state = .failed
            return
        }
        origin = touch.location(in: view)
        fraction = CGFloat(VitalsProbeMath.fingerFraction(
            x: origin.x, width: view.bounds.width,
            leadingInset: leadingInset, trailingInset: trailingInset))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let view, let touch = touches.first else { return }
        let point = touch.location(in: view)
        fraction = CGFloat(VitalsProbeMath.fingerFraction(
            x: point.x, width: view.bounds.width,
            leadingInset: leadingInset, trailingInset: trailingInset))
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        if state == .possible {
            switch VitalsProbeMath.axisLock(dx: dx, dy: dy) {
            case .undecided:
                return
            case .horizontal:
                state = .began
            case .vertical:
                state = .failed
            }
            return
        }
        if state == .began || state == .changed {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        switch state {
        case .began, .changed:
            state = .ended
        case .possible:
            state = .failed
        default:
            break
        }
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        switch state {
        case .began, .changed:
            state = .cancelled
        case .possible:
            state = .failed
        default:
            break
        }
        super.touchesCancelled(touches, with: event)
    }

    override func reset() {
        super.reset()
        fraction = 0
        origin = .zero
    }
}
