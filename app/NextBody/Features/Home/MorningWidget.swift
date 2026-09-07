import SwiftUI

/// 13 col 01 · 昨夜 · ONE WIDGET · ONCE A DAY · WAKE + 6H.
///
/// The one thing the night is allowed to say, said once. Rule 09: shown at most once per
/// 04:00 day, stamped `bb_morning_shown_at` on the day row. Not rendered at all without a
/// night on the band (edge 1) — the panel simply stays in standby.
@MainActor
enum MorningWidget {
    static let shownKey = "nb.bb.morningShownDay"

    /// DEBUG only · `SIMCTL_CHILD_NB_DEBUG_NOW=2026-09-01T08:30:00Z` pretends it is that morning,
    /// so the once-a-day window can be walked on a simulator whose clock says evening.
    static var debugNow: Date? {
        #if DEBUG
        guard Band.allowsSeed else { return nil }
        return ProcessInfo.processInfo.environment["NB_DEBUG_NOW"].flatMap { ISO8601DateFormatter().date(from: $0) }
        #else
        return nil
        #endif
    }

    static func frame(today m: DailyMetrics, history: [DailyMetrics], now clock: Date? = nil,
                     ignoreShown: Bool = false) -> PanelWidget? {
        let now = clock ?? debugNow ?? Date()
        #if DEBUG
        let pinMorning = ProcessInfo.processInfo.environment["NB_DEBUG_MORNING"] == "1"
        #else
        let pinMorning = false
        #endif
        if !pinMorning {
            guard ConsentStore.shared.granted else { return suppress("NO_CONSENT") }
        }
        guard let wake = m.bbWake, let wakeAt = m.bodyBatteryWakeAt,
              let drivers = m.reserveDrivers, let nightCharge = drivers.nightCharge
        else { return suppress("NO_NIGHT") }
        if !pinMorning, !ignoreShown, UserDefaults.standard.string(forKey: shownKey) == m.day.key {
            return suppress("ALREADY_SHOWN")
        }
        if !pinMorning {
            guard now >= wakeAt, now <= wakeAt.addingTimeInterval(6 * 3600)
            else { return suppress("PAST_WINDOW") }
        }

        let charge = Int(nightCharge.rounded())
        let tier = L(BodyBattery.chargeWord(charge))
        let title: String
        let sentence: String
        if drivers.assumedAnchor {
            title = L("ESTIMATED START")
            sentence = L("The starting battery was estimated because earlier readings were missing. Later readings still carry that uncertainty.")
        } else {
            title = L("LAST NIGHT · %@", Fmt.clock(wakeAt))
            sentence = L("%d charged overnight.", charge)
        }
        let footer = L("CHARGED +%d · %@", charge, tier)
        return PanelWidget(
            type: .line, title: title, tag: .recover, sentence: sentence,
            footer: footer, action: L("TAP TO SEE WHY"), hero: "\(wake)",
            accentOverride: NB.lime1,
            targetOverride: .bodyBattery,
            data: .series(m.reserveCurve.map { Double($0.value) }),
            ttlMinutes: 60)
    }

    /// Rule 09 · the stamp goes to the phone and to the cloud.
    static func markShown(day: UserDay, widget w: PanelWidget) async {
        UserDefaults.standard.set(day.key, forKey: shownKey)
        let iso = ISO8601DateFormatter().string(from: Date())
        _ = try? await SupabaseClient.shared.patchWhere(
            "daily_results", column: "user_day", equals: day.key, row: ["bb_morning_shown_at": iso])
        await Analytics.shared.track("BB_MORNING_SHOWN", [
            "SCORE": w.hero ?? "", "DELTA": w.footer ?? "",
            "BAND": w.footer?.split(separator: "·").dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "",
        ])
    }

    private static func suppress(_ reason: String) -> PanelWidget? {
        #if DEBUG
        NSLog("MorningWidget suppressed: %@", reason)
        #endif
        Task { await Analytics.shared.track("BB_MORNING_SUPPRESSED", ["REASON": reason]) }
        return nil
    }
}
