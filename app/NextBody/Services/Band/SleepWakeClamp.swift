import Foundation

/// Issue #20 · 「我都已经醒了、在用 App 的时候，它居然还算我在睡觉。」
///
/// The band decides on its own when a night ended, and on this firmware it is generous:
/// a wrist lying still on a duvet at 07:10 while its owner reads the app in bed is filed
/// as sleep, and the night's recorded wake lands well after the person got up. The phone
/// being in front of a face is the one piece of wake evidence the band cannot see, so it
/// is the one the phone owes it.
///
/// `AwakeEvidence` records the instants this app was in the foreground; `SleepWakeClamp`
/// cuts a recorded night at the first of them that lands inside it. Nothing here invents
/// sleep — it only ever removes minutes the band claimed after the person was demonstrably
/// awake, and it never touches a night the app was not open during.
enum AwakeEvidence {
    private static let key = "nb.awake.foregroundMarks"

    /// Two days is longer than any night plus the sync that reads it, and short enough
    /// that this stays a handful of timestamps rather than a log.
    static let retention: TimeInterval = 48 * 3600

    /// Foreground marks closer together than this are the same waking: coming back from
    /// the app switcher four times in a minute is not four pieces of evidence.
    static let coalesce: TimeInterval = 60

    static func record(at instant: Date = Date(), defaults: UserDefaults = .standard) {
        var kept = marks(defaults: defaults).filter { instant.timeIntervalSince($0) < retention }
        if let last = kept.last, instant.timeIntervalSince(last) < coalesce { return }
        kept.append(instant)
        defaults.set(kept.map(\.timeIntervalSince1970), forKey: key)
    }

    static func marks(defaults: UserDefaults = .standard) -> [Date] {
        (defaults.array(forKey: key) as? [Double] ?? [])
            .map { Date(timeIntervalSince1970: $0) }
            .sorted()
    }

    #if DEBUG
    static func reset(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
    #endif
}

enum SleepWakeClamp {
    /// A night is not cut below this. Opening the app at 00:20 does not mean the night that
    /// began at 00:05 never happened — a glance that early is someone falling asleep with a
    /// phone in their hand, and calling it a wake would erase the whole night.
    static let minimumNight: TimeInterval = 45 * 60

    /// Nor is a mark within this of the band's own wake worth acting on: the band and the
    /// phone agree, and rewriting the night to save four minutes only creates churn.
    static let tolerance: TimeInterval = 5 * 60

    /// The instant this night actually ended, or nil to keep the band's own answer.
    /// The first foreground mark strictly inside the recorded night, at least
    /// `minimumNight` after it began and at least `tolerance` before the band's wake.
    static func wake(sleepStart: Date, recordedWake: Date, marks: [Date]) -> Date? {
        guard recordedWake > sleepStart else { return nil }
        return marks.sorted().first {
            $0 > sleepStart.addingTimeInterval(minimumNight)
                && $0 < recordedWake.addingTimeInterval(-tolerance)
        }
    }
}
