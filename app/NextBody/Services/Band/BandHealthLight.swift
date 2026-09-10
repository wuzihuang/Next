import Foundation

/// Raw values follow the SDK's VPHealthLightStatusType wire contract.
enum BandHealthLightState: Int, CaseIterable, Identifiable, Sendable {
    case off = 0
    case slowFlash = 1
    case continuousFlashing = 2
    case stayOn = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .slowFlash: "Slow flash"
        case .continuousFlashing: "Continuous flashing"
        case .stayOn: "Stay on"
        }
    }

    /// The returned device state is authoritative, even if it differs from the request.
    static func confirmedState(success: Bool, rawValue: Int) throws -> Self {
        guard success else { throw BandHealthLightError.rejected }
        guard let state = Self(rawValue: rawValue) else { throw BandHealthLightError.unknownState }
        return state
    }
}

enum BandHealthLightError: LocalizedError, Equatable {
    case rejected
    case unknownState

    var errorDescription: String? {
        switch self {
        case .rejected: "The device rejected the health light setting."
        case .unknownState: "The device returned an unknown health light state."
        }
    }
}

/// The state chosen on the Device page, kept on the phone and written to the band again
/// on every connect (`BandHealthLightKeeper`). `nil` is "never chosen": the firmware's own
/// default stands and the app sends nothing.
enum BandHealthLightPreference {
    static let key = "nb.band.healthLight"

    static func stored(in defaults: UserDefaults = .standard) -> BandHealthLightState? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return BandHealthLightState(rawValue: defaults.integer(forKey: key))
    }

    static func store(_ state: BandHealthLightState?, in defaults: UserDefaults = .standard) {
        if let state {
            defaults.set(state.rawValue, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
