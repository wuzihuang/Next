import SwiftUI
import UIKit
import os

/// ADR-0001 · 手势所有权 · the other half of the rule, for the key that cannot wait.
///
/// `HotZoneTap` settles a tap on lift-off, which is all a card ever needs. The dock's middle
/// key needs the opposite: it has to know the finger is down and still 200 ms into the touch,
/// while the touch is happening. Under the home page's `highPriorityGesture` a child SwiftUI
/// gesture is told nothing until the page drag has failed — and a drag with a minimum distance
/// only fails when the finger lifts. So the key went dead the moment the page drag took
/// precedence: the arming timer only ever started after the take was already over, `armed`
/// was still false at `onEnded`, and a press — long or short — did exactly nothing.
///
/// The press is therefore a UIKit recognizer, outside SwiftUI's gesture graph, and UIKit's own
/// arbitration is precisely what the ADR asks for:
///   · finger still for 200 ms → the long press recognizes first and prevents the page drag,
///     which is still waiting for its 12 pt. The key owns the touch.
///   · finger past the slop first → the page drag recognizes and prevents the long press. The
///     swipe turns the page and nothing was recorded.
struct PressHold: UIViewRepresentable {
    /// 05M · B·02 · the arming threshold: below it nothing began.
    var minimumDuration: TimeInterval = 0.20
    /// Finger down / finger gone. For the press dim only — no state depends on it, and a
    /// touch the page drag steals arrives here as gone.
    var onTouch: (Bool) -> Void = { _ in }
    /// The threshold was crossed: this is where the mic goes up.
    var onArm: () -> Void = {}
    /// Travel since the finger went down, in window points, while armed. Slide-up-to-cancel.
    var onMove: (CGSize) -> Void = { _ in }
    /// The armed press ended. `interrupted` is UIKit taking the touch away rather than the
    /// finger lifting — half a sentence is worse than none, so the caller cancels on it.
    var onLift: (_ interrupted: Bool) -> Void = { _ in }
    /// Lift before the arming threshold, in place, not cancelled. A drag past `HotZoneTap.slop`
    /// retires this for the rest of the touch — ADR-0001, the same dead zone the cards use —
    /// so a page swipe that started on the key cannot settle as a tap on lift-off.
    var onTap: () -> Void = {}
    /// Opt-in touch timing for diagnosing gesture arbitration. No coordinates or values.
    var diagnosticName: String? = nil
    /// STOP may settle a completed, stationary hold on lift if activation interrupted
    /// recognition. Recording controls must remain false: starting on lift is too late.
    var allowsQualifiedRelease: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = TouchView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        view.diagnosticName = diagnosticName
        let coordinator = context.coordinator
        view.report = { down in coordinator.owner.onTouch(down) }
        view.reportTap = { coordinator.owner.onTap() }
        view.isArmed = { coordinator.armed }
        view.qualifiedRelease = { elapsed in coordinator.completeQualifiedRelease(elapsed) }
        let press = TracedLongPress(target: coordinator,
                                                 action: #selector(Coordinator.handle(_:)))
        press.diagnosticName = diagnosticName
        press.onTouchBegan = { coordinator.recognizedThisTouch = false; coordinator.touchCancelled = false }
        press.onTouchCancelled = { coordinator.touchCancelled = true }
        press.minimumPressDuration = minimumDuration
        // The same dead zone the hot zones use: a finger that travelled is not a press.
        press.allowableMovement = HotZoneTap.slop
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.owner = self
        if let press = view.gestureRecognizers?.first as? UILongPressGestureRecognizer,
           press.minimumPressDuration != minimumDuration {
            // Live readouts refresh this view frequently. Do not reconfigure an
            // in-flight recognizer when its threshold has not actually changed.
            press.minimumPressDuration = minimumDuration
        }
    }

    final class Coordinator: NSObject {
        var owner: PressHold
        /// True from `.began` until the recognizer settles. The orb's tap must not fire
        /// on the lift that ends a hold.
        var armed = false
        var recognizedThisTouch = false
        var touchCancelled = false
        /// Window coordinates: the capsule grows into the chamber under the finger, so the
        /// view's own space moves while the press is live and cannot measure the travel.
        private var origin: CGPoint = .zero

        init(_ owner: PressHold) { self.owner = owner }

        func completeQualifiedRelease(_ elapsed: TimeInterval) -> Bool {
            guard owner.allowsQualifiedRelease, !recognizedThisTouch, !touchCancelled,
                  elapsed >= owner.minimumDuration else { return false }
            recognizedThisTouch = true
            if let name = owner.diagnosticName {
                PressHold.log.notice("press \(name, privacy: .public) qualified release elapsed=\(elapsed, privacy: .public)")
            }
            owner.onArm()
            owner.onLift(false)
            return true
        }

        @objc func handle(_ g: UILongPressGestureRecognizer) {
            if let name = owner.diagnosticName {
                PressHold.log.notice("press \(name, privacy: .public) recognizer state=\(g.state.rawValue, privacy: .public)")
            }
            switch g.state {
            case .began:
                guard !owner.allowsQualifiedRelease || !recognizedThisTouch else { return }
                recognizedThisTouch = true
                armed = true
                origin = g.location(in: nil)
                owner.onArm()
            case .changed:
                let p = g.location(in: nil)
                owner.onMove(CGSize(width: p.x - origin.x, height: p.y - origin.y))
            case .ended:
                owner.onLift(false)
                armed = false
            case .cancelled:
                touchCancelled = true
                owner.onLift(true)
                armed = false
            case .failed:
                owner.onLift(true)
                armed = false
            default:
                break
            }
        }
    }

    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "press-hold")

    private final class TracedLongPress: UILongPressGestureRecognizer {
        var diagnosticName: String?
        var onTouchBegan: () -> Void = {}
        var onTouchCancelled: () -> Void = {}
        private var startedAt: TimeInterval?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            onTouchBegan()
            startedAt = touches.first?.timestamp
            trace("began", touches: touches)
            super.touchesBegan(touches, with: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            trace("ended", touches: touches)
            super.touchesEnded(touches, with: event)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            onTouchCancelled()
            trace("cancelled", touches: touches)
            super.touchesCancelled(touches, with: event)
        }

        private func trace(_ phase: String, touches: Set<UITouch>) {
            guard let diagnosticName, let timestamp = touches.first?.timestamp else { return }
            let elapsed = timestamp - (startedAt ?? timestamp)
            let delay = ProcessInfo.processInfo.systemUptime - timestamp
            PressHold.log.notice("press \(diagnosticName, privacy: .public) native \(phase, privacy: .public) elapsed=\(elapsed, privacy: .public) deliveryDelay=\(delay, privacy: .public) state=\(self.state.rawValue, privacy: .public)")
        }
    }

    /// The dim at touch-down. The recognizer cannot report it — it has not recognized yet —
    /// and the view is the one thing that hears the touch land.
    private final class TouchView: UIView {
        var diagnosticName: String?
        var report: (Bool) -> Void = { _ in }
        var reportTap: () -> Void = {}
        var isArmed: () -> Bool = { false }
        var qualifiedRelease: (TimeInterval) -> Bool = { _ in false }
        private var origin: CGPoint = .zero
        private var moved = false
        private var beganTimestamp: TimeInterval?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            trace("began", touches: touches)
            origin = touches.first?.location(in: nil) ?? .zero
            beganTimestamp = touches.first?.timestamp
            moved = false
            report(true)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            guard let p = touches.first?.location(in: nil) else { return }
            if hypot(p.x - origin.x, p.y - origin.y) > HotZoneTap.slop { moved = true }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            trace("ended", touches: touches)
            if let p = touches.first?.location(in: nil),
               hypot(p.x - origin.x, p.y - origin.y) > HotZoneTap.slop { moved = true }
            let elapsed = beganTimestamp.flatMap { began in touches.first.map { $0.timestamp - began } }
            beganTimestamp = nil
            let completed = !moved && elapsed.map { qualifiedRelease($0) } == true
            report(false)
            if !completed && !moved && !isArmed() { reportTap() }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            trace("cancelled", touches: touches)
            beganTimestamp = nil
            report(false)
        }

        private func trace(_ phase: String, touches: Set<UITouch>) {
            guard let diagnosticName, let timestamp = touches.first?.timestamp else { return }
            let delay = ProcessInfo.processInfo.systemUptime - timestamp
            PressHold.log.notice("press \(diagnosticName, privacy: .public) view \(phase, privacy: .public) deliveryDelay=\(delay, privacy: .public)")
        }
    }
}
