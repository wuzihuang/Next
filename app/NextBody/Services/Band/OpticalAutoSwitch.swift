import Foundation

/// Last known state of the wrist optical auto-measure switch. Page two never asks the
/// band; it only prints SWITCH OFF when a previous Device read already saw the slot off.
enum OpticalAutoSwitch {
    private static let key = "nb.optical.auto.on"

    static var isOff: Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return false }
        return UserDefaults.standard.bool(forKey: key) == false
    }

    static func record(on: Bool) {
        UserDefaults.standard.set(on, forKey: key)
    }
}
