import Foundation

/// How the server took a band. A band is held by one account (ADR 0003, `20261024150000`).
enum DeviceRegistration: Equatable, Sendable {
    case saved
    /// Bound to another account; it has to be released there first.
    case ownedElsewhere
    /// Already this account's, in its other slot.
    case alreadyInSet
    case failed

    /// The refusal a failed write carries: the name the trigger raised, read from PostgREST's
    /// error body and from nowhere else the text might happen to appear.
    static func refusal(_ error: Error) -> DeviceRegistration {
        switch (error as? SupabaseFailure)?.serverMessage {
        case "DEVICE_OWNED_ELSEWHERE": .ownedElsewhere
        case "DEVICE_ALREADY_IN_SET": .alreadyInSet
        default: .failed
        }
    }

    /// The `ble_identifier` a registration writes onto the slot's existing row; nil leaves it.
    /// Only pairing, the person choosing this band, may point the row at another band. A
    /// refresh keeps the band the row names and updates only its facts (ADR 0003). The
    /// simulator seed never replaces a binding.
    static func bleIdentifierWrite(pairing: Bool, existing: String?, linked: String?, seed: String) -> String? {
        guard pairing, let linked, linked != seed, linked != existing else { return nil }
        return linked
    }
}
