import Foundation

/// DEBUG only · `SIMCTL_CHILD_NB_DEBUG_EDGE=stale` (or autohr · notworn · over · outunknown ·
/// frozen · outlier · measured · clamped · busy · otaunverified · levelonly · autoswitch ·
/// autoempty · autonone · autorefuse) forces one board edge state on a simulator whose data
/// would never produce it, so each can be walked 1:1.
enum DebugEdge {
    static var name: String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["NB_DEBUG_EDGE"]
        #else
        return nil
        #endif
    }
    static func on(_ s: String) -> Bool { name == s }
}

/// 08 / 09 / 10 edge fragments share one voice: an optional dim sub-line, one amber status
/// line in Doto, and a centred sentence. Optionally tappable (08 edge 2 links to the switch).
import SwiftUI
struct EdgeNote: View {
    var sub: String? = nil
    let line: String
    let text: String
    var action: (() -> Void)? = nil

    var body: some View {
        let body = VStack(spacing: 8) {
            if let sub {
                Text(sub).font(NBFont.dot(500, 11)).tracking(0.18 * 11).foregroundStyle(NB.white.opacity(0.34))
            }
            Text(line).font(NBFont.dot(600, 12)).tracking(0.22 * 12).foregroundStyle(NB.ember1.opacity(0.85))
            Text(text).font(NBFont.brand(400, 13.5)).lineSpacing(5).multilineTextAlignment(.center)
                .foregroundStyle(NB.white.opacity(0.70)).frame(width: 300)
        }
        if let action {
            Button(action: action) { body }.buttonStyle(.plain)
        } else {
            body
        }
    }
}
