import Foundation

/// ADR 0026 · the body battery keeps being computed while the app is away, but only when
/// someone is there to read it. The home-screen widget is that someone: it paints the App
/// Group glance and nothing else, and the glance is only ever written by this process.
/// Without a widget there is no reader, and the phone's radio stays quiet in the background.
///
/// Every number here is a rule about *when to ask*, never about the reserve itself — the
/// reserve is settled on the server from the ticks the pull brings up (F2 rule 02).
enum BackgroundRefreshPolicy: Sendable {
    /// The BGTaskScheduler identifier. Must match `BGTaskSchedulerPermittedIdentifiers`.
    static let taskIdentifier = "com.nextbody.hoop.refresh"

    /// Half an hour between background pulls. Eleven of them fit inside the six hours after
    /// which `BodyBatteryReadoutPolicy` withdraws the number, so a wrist in range keeps a
    /// printable score on the widget all day; the pull itself decides nothing about the value.
    static let interval: TimeInterval = 30 * 60

    /// A pull is worth scheduling only when the phone can act on it: someone placed a
    /// widget, an account is signed in on this phone, and a band is bound to read from.
    static func shouldSchedule(widgetCount: Int, signedIn: Bool, bound: Bool) -> Bool {
        widgetCount > 0 && signedIn && bound
    }

    /// The earliest moment the system may launch the next pull. Counted from the last pull
    /// that reached the server, so a background run does not follow a foreground sync by
    /// two minutes — and never earlier than now, so a stale `lastPullAt` cannot ask for the past.
    static func nextBeginDate(now: Date, lastPullAt: Date?) -> Date {
        guard let lastPullAt, lastPullAt <= now else { return now.addingTimeInterval(interval) }
        return max(now, lastPullAt.addingTimeInterval(interval))
    }

    /// Whether a run's outcome counts as the task having done its job. `throttled` is a
    /// success: the coordinator declined because a fresher pull already exists.
    static func completed(_ status: BandRefreshResult.Status) -> Bool {
        switch status {
        case .success, .partial, .throttled: true
        case .failed, .signedOut, .consentRequired, .unbound, .busy, .disconnected, .cancelled: false
        }
    }
}
