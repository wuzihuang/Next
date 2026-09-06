import Foundation

/// Cold-start cover is a still: PingFang `NextBody` + the launch line.
/// No film. Harness launches skip the cover so UI tests keep the 1.2s door.
public enum LaunchFilmPolicy: Sendable {
    /// Same key `FirstRun` writes after the 7.40s page fold.
    public static let firstRunPlayedKey = "nb.firstRunPlayed"
    public static let lastDurationKey = "nb.launch.lastMs"

    /// Stamped on first access. `NextBodyApp.init` must touch it so the clock
    /// starts at process entry, not at the first SwiftUI frame.
    public static let processStart = CFAbsoluteTimeGetCurrent()

    public static var elapsed: TimeInterval {
        CFAbsoluteTimeGetCurrent() - processStart
    }

    public static func shouldHoldStill(environment: [String: String]) -> Bool {
        !isHarness(environment)
    }

    public static func isHarness(_ environment: [String: String]) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if environment["NB_DEBUG_STAGE"] != nil { return true }
        if environment["NB_DEBUG_ROUTE"] != nil { return true }
        if environment["NB_DEBUG_TAKEOVER"] != nil { return true }
        return false
    }
}
