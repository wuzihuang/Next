import SwiftUI
import UIKit

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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = TouchView()
        view.backgroundColor = .clear
        let coordinator = context.coordinator
        view.report = { down in coordinator.owner.onTouch(down) }
        let press = UILongPressGestureRecognizer(target: coordinator,
                                                 action: #selector(Coordinator.handle(_:)))
        press.minimumPressDuration = minimumDuration
        // The same dead zone the hot zones use: a finger that travelled is not a press.
        press.allowableMovement = HotZoneTap.slop
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.owner = self
        (view.gestureRecognizers?.first as? UILongPressGestureRecognizer)?
            .minimumPressDuration = minimumDuration
    }

    final class Coordinator: NSObject {
        var owner: PressHold
        /// Window coordinates: the capsule grows into the chamber under the finger, so the
        /// view's own space moves while the press is live and cannot measure the travel.
        private var origin: CGPoint = .zero

        init(_ owner: PressHold) { self.owner = owner }

        @objc func handle(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began:
                origin = g.location(in: nil)
                owner.onArm()
            case .changed:
                let p = g.location(in: nil)
                owner.onMove(CGSize(width: p.x - origin.x, height: p.y - origin.y))
            case .ended:
                owner.onLift(false)
            case .cancelled, .failed:
                owner.onLift(true)
            default:
                break
            }
        }
    }

    /// The dim at touch-down. The recognizer cannot report it — it has not recognized yet —
    /// and the view is the one thing that hears the touch land.
    private final class TouchView: UIView {
        var report: (Bool) -> Void = { _ in }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            report(true)
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            report(false)
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            report(false)
        }
    }
}
