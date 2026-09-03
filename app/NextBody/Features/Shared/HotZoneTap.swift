import SwiftUI

/// ADR-0001 · 手势所有权 · the 点按 rule, enforced at the hot zone itself.
///
/// A hot zone fires on a tap only: a touch that never travelled past the dead zone. The
/// system `Button` decides on lift-off and trusts the gesture arbitration above it to cancel
/// it; under the page drag's `highPriorityGesture` that held in XCUITest but not under a
/// finger — a drag that started on the panel still settled as a tap when it lifted, and
/// opened the detail page instead of turning the page. SpringBoard never has this problem
/// because UIKit retires the tap the moment the touch leaves the slop, whatever recognises
/// afterwards. This style does the same, locally: the first 10 pt of travel in any direction
/// retire the tap for the rest of the touch (even if the finger wanders back), and the page
/// drag — minimum 12 pt — can only ever recognise on a touch whose tap is already retired.
///
/// It is a `PrimitiveButtonStyle`, so the `Button` keeps its label, its accessibility trait
/// and its VoiceOver activation; only the touch handling is ours.
struct HotZoneTap: PrimitiveButtonStyle {
    /// The dead zone, in screen points — UIKit's own: a scroll view starts panning at ~10.
    static let slop: CGFloat = 10
    var pressedOpacity: Double = 0.72
    var pressedScale: CGFloat = 0.985

    func makeBody(configuration: Configuration) -> some View {
        Zone(configuration: configuration, pressedOpacity: pressedOpacity, pressedScale: pressedScale)
    }

    private struct Zone: View {
        let configuration: Configuration
        let pressedOpacity: Double
        let pressedScale: CGFloat
        /// Finger down. A `GestureState` resets on end AND on cancel, so the press never
        /// sticks when the page drag takes the touch away without an `onEnded`.
        @GestureState private var down = false
        /// Sticky for the life of one touch: past the slop once, never a tap again. Reset on
        /// touch-down (the first update, translation zero) and on lift-off.
        @State private var moved = false

        private var pressed: Bool { down && !moved }

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .opacity(pressed ? pressedOpacity : 1)
                .scaleEffect(pressed ? pressedScale : 1)
                .animation(.easeOut(duration: 0.12), value: pressed)
                .gesture(
                    // Global space: the panel's canvas is drawn scaled, and the dead zone is
                    // measured in the points the finger actually travelled.
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .updating($down) { _, state, _ in state = true }
                        .onChanged { v in
                            if v.translation == .zero { moved = false } else if !inside(v) { moved = true }
                        }
                        .onEnded { v in
                            let tap = !moved && inside(v)
                            moved = false
                            if tap { configuration.trigger() }
                        }
                )
        }

        private func inside(_ v: DragGesture.Value) -> Bool {
            abs(v.translation.width) <= HotZoneTap.slop && abs(v.translation.height) <= HotZoneTap.slop
        }
    }
}
