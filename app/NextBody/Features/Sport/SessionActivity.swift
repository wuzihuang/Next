import ActivityKit
import Foundation
import os

/// 14 · LIVE SESSION · the app's end of the Dynamic Island.
///
/// One activity per session, started when the band takes the mode and ended when the user
/// stops. Everything it shows is pushed from here; the island renders it (see the
/// `NextBodyLiveActivity` extension) and counts the seconds on its own.
///
/// ⚠️ Updates are rationed. The band reports about once a second and the system budgets how
/// often a backgrounded app may redraw the island, so a push goes out at most every two
/// seconds — except for the ones that change what the thing *says* (the wrist coming and
/// going, the note, the end), which go immediately. The clock is not a reason to push at
/// all: `Text(timerInterval:)` on the island is already counting.
@MainActor
enum SessionActivity {
    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "island")

    private static var current: Activity<SessionAttributes>?
    private static var lastPushAt = Date.distantPast
    private static var lastState: SessionAttributes.ContentState?

    /// The floor between routine pushes.
    private static let cadence: TimeInterval = 2
    /// How long a state stays believable without a new push. Past it the island greys the
    /// numbers itself and says the phone went quiet — which beats a beat frozen from
    /// ten minutes ago, and is the only honest thing to show if the app is killed.
    private static let staleAfter: TimeInterval = 45

    static var isRunning: Bool { current != nil }

    /// Whether the user has left Live Activities on for this app. Not an error when off —
    /// the session simply lives on the screen, as it did before.
    static var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func start(sport: String, modeRawValue: Int, state: SessionAttributes.ContentState) {
        guard current == nil else { return }
        guard enabled else {
            log.notice("live activities are off for this app")
            return
        }
        do {
            current = try Activity.request(
                attributes: SessionAttributes(sport: sport, modeRawValue: modeRawValue),
                content: ActivityContent(state: state,
                                         staleDate: Date().addingTimeInterval(staleAfter)),
                pushType: nil)
            lastState = state
            lastPushAt = Date()
            log.notice("island up · \(sport, privacy: .public)")
        } catch {
            // A refusal is not worth a word on screen: the session is on the phone either
            // way, and the island is the surface that is missing, not the workout.
            log.error("island refused · \(String(describing: error), privacy: .public)")
        }
    }

    /// Push the wrist. `force` skips the cadence for the changes a person would notice a
    /// two-second lie about.
    static func update(_ state: SessionAttributes.ContentState, force: Bool = false) {
        guard let activity = current else { return }
        // Nothing to say: the same numbers again is a redraw the budget pays for.
        if !force, let last = lastState, last == state { return }
        // Contact coming or going, and anything the island prints as words, jump the queue.
        let says = lastState.map { $0.live != state.live || $0.note != state.note } ?? true
        guard force || says || Date().timeIntervalSince(lastPushAt) >= cadence else { return }
        lastState = state
        lastPushAt = Date()
        Task {
            await activity.update(ActivityContent(
                state: state, staleDate: Date().addingTimeInterval(staleAfter)))
        }
    }

    /// The session is over. The final numbers stay on the Lock Screen for a moment — long
    /// enough to be read by someone who put the phone down before pressing stop — and the
    /// island drops it at once, because the island is for what is happening now.
    static func end(_ state: SessionAttributes.ContentState) {
        guard let activity = current else { return }
        current = nil
        lastState = nil
        var final = state
        final.live = false
        final.note = "SESSION ENDED"
        log.notice("island down")
        Task {
            await activity.end(ActivityContent(state: final, staleDate: nil),
                               dismissalPolicy: .after(Date().addingTimeInterval(20)))
        }
    }

    /// Anything this process left behind — a crash mid-session, or a build replaced under a
    /// running activity. Called at launch: an island counting up for a session nobody is in
    /// is worse than no island.
    static func clearOrphans() {
        for activity in Activity<SessionAttributes>.activities where activity.id != current?.id {
            log.notice("clearing an orphaned island")
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
