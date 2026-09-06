import Foundation

/// Phone-find-wrist distance. Same RSSI cuts as the vendor table; the words are
/// how far, never how good.
enum FindDistance: String, Equatable, Sendable, CaseIterable {
    case near, close, away, far

    var label: String {
        switch self {
        case .near: "NEAR"
        case .close: "CLOSE"
        case .away: "AWAY"
        case .far: "FAR"
        }
    }

    /// One step farther on the lamp strip. FAR has nowhere left to fall.
    var farther: FindDistance? {
        switch self {
        case .near: .close
        case .close: .away
        case .away: .far
        case .far: nil
        }
    }

    /// Timeout face's four rising pips. Strength counts from the left.
    var barsLit: Int {
        switch self {
        case .near: 4
        case .close: 3
        case .away: 2
        case .far: 1
        }
    }

    /// Paper KLF-0: current cell is lime, the next farther cell is a 40% falloff,
    /// the rest sit at hairline. Not a single isolated square.
    static func glow(of lamp: FindDistance, current: FindDistance?) -> FindLampGlow {
        guard let current else { return .off }
        if lamp == current { return .hot }
        if lamp == current.farther { return .warm }
        return .off
    }

    /// Unicode minus so −52 matches the instrument face, not a hyphen.
    static func glyph(_ rssi: Int) -> String {
        rssi < 0 ? "−\(abs(rssi))" : "\(rssi)"
    }

    /// NEAR `> −60`. CLOSE `−70 … −60` inclusive. AWAY `−85 … < −70`. FAR `< −85`.
    /// −70 is CLOSE. −85 is AWAY.
    static func from(rssi: Int) -> FindDistance {
        if rssi > -60 { return .near }
        if rssi >= -70 { return .close }
        if rssi >= -85 { return .away }
        return .far
    }
}

/// Stepped lime on the LED strip. Hot is the current distance.
enum FindLampGlow: Equatable, Sendable {
    case hot, warm, off
}

/// Firmware answers from `veepooSDK_searchDeviceFuntionWithState`.
enum FindHoopPhase: Int, Equatable, Sendable {
    case unsupported = 0
    case enter = 1
    case exit = 2
    case timeout = 3

    static func from(rawValue: Int) -> FindHoopPhase {
        FindHoopPhase(rawValue: rawValue) ?? .unsupported
    }
}
