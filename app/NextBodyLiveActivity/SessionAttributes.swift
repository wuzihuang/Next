import ActivityKit
import Foundation

/// 14 · LIVE SESSION · what the Dynamic Island and the Lock Screen are told.
///
/// ⚠️ This file is compiled into BOTH targets — the app (which starts and updates the
/// activity) and the widget extension (which draws it). ActivityKit matches the two by this
/// type, so its shape is a contract: adding a field is safe, renaming one is not.
///
/// The static half is the session's identity, fixed for its whole life. The dynamic half is
/// the wrist, and it is deliberately small — every field here crosses a process boundary on
/// every update, and the island has a budget.
struct SessionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// nil is a dash. ⚠️ Never the last beat kept warm: a rate from before the wrist
        /// moved is not a rate now, and the island has no way to say "this is old".
        var heartRate: Int?
        var kcal: Int
        /// When the session started. The island counts up from this on its own
        /// (`Text(timerInterval:)`), so the clock keeps moving between updates — the phone
        /// does not have to be awake for the seconds to tick.
        var startedAt: Date
        /// The wrist is being read this second. False dims the numbers rather than hiding
        /// them: the clock is still running and the session is still open.
        var live: Bool
        /// 0…1 · where the heart sits between rest and the profile's maximum. The island's
        /// one colour decision: lime at an easy pace, warming to amber near the top.
        var effort: Double
        /// One short line — what the screen's status row would say. nil while it is simply
        /// running, so the island shows the numbers and nothing else.
        var note: String?
    }

    /// The sport, in the catalogue's own words. Fixed for the session.
    var sport: String
    /// VPDeviceRuningMode ordinal, for a caller that needs to know which session this is.
    var modeRawValue: Int
}
