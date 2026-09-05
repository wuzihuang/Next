import Foundation
import SwiftUI
import UIKit

/// One switch for every motor in the product: the typing stream, the orb's hold, the taps
/// that mark an outcome. ME → PREFERENCES → HAPTICS. On by default; the choice survives
/// launches. Reduce Motion and Low Power Mode still silence the texture on their own — this
/// is the person saying so directly, and it wins over both.
@MainActor
final class HapticsSetting: ObservableObject {
    static let shared = HapticsSetting()

    private static let key = "nb.haptics.enabled"

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.key) }
    }

    private init() {
        // Absent means never chosen, which is on — not off.
        enabled = UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true
    }

    func toggle() { enabled.toggle() }
}

/// The one gate every motor in the product goes through. UIKit's generators are cheap to
/// build and were being constructed inline all over the app, which is why turning haptics
/// off still left the voice bar, the scale and the connect film buzzing: each of those call
/// sites owned its own generator and knew nothing about the switch. They call these instead.
@MainActor
enum Haptics {
    static var on: Bool { HapticsSetting.shared.enabled }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat? = nil) {
        guard on else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        if let intensity { generator.impactOccurred(intensity: intensity) }
        else { generator.impactOccurred() }
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard on else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    static func selection() {
        guard on else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
