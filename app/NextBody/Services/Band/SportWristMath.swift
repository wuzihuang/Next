import Foundation

/// What a sport-mode report is allowed to say about the wrist.
///
/// HOOP's sport packet is `heartRate = 0` until the optical lock lands — often
/// about twenty seconds after the mode opens. That zero is "not yet", not a
/// loose strap. The same path already learned this on the heart *test*
/// (`VPTestHeartStateStart`); the live report used to treat every empty beat
/// as `noContact` and paint TIGHTEN THE BAND for the whole lock.
enum SportWristMath: Sendable {
    /// First optical lock after the mode is running. Longer than the ~20 s HOOP
    /// typically needs, short enough that a band on the table still gets said.
    static let acquireGrace: TimeInterval = 30
    /// After a lock, a brief zero is a dropout. Same window as a live beat.
    static let dropoutGrace: TimeInterval = SportMetricAccumulator.liveWindow

    enum Face: Equatable, Sendable {
        case reaching, live, noContact, paused
    }

    static func face(runState: Int?, heartRate: Int?,
                     hadHeart: Bool, seekingFor: TimeInterval,
                     silentFor: TimeInterval) -> Face {
        if runState == 2 { return .paused }
        if let heartRate, (1...255).contains(heartRate) { return .live }
        if !hadHeart {
            return seekingFor < acquireGrace ? .reaching : .noContact
        }
        return silentFor < dropoutGrace ? .reaching : .noContact
    }
}
