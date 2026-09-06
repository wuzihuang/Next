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

    static func frame(today m: DailyMetrics, history: [DailyMetrics], now clock: Date? = nil) -> PanelWidget? {
        let now = clock ?? debugNow ?? Date()
        guard ConsentStore.shared.granted else { return suppress("NO_CONSENT") }
        // ⚠️ `today` is the merge of the last server row into the local day, and the merge does
        // not carry the five-minute curve. The history row for the same day does.
        let m = history.first(where: { $0.day == m.day && !$0.reserveCurve.isEmpty }) ?? m
        guard let wake = m.bbWake, let drivers = m.reserveDrivers, m.reserveCurve.count > 1
        else {
            #if DEBUG
            NSLog("MorningWidget inputs: day=%@ bbWake=%@ drivers=%d curve=%d history=%@",
                  m.day.key, "\(String(describing: m.bbWake))", m.reserveDrivers == nil ? 0 : 1, m.reserveCurve.count,
                  history.suffix(3).map { "\($0.day.key):\($0.reserveCurve.count)" }.joined(separator: ","))
            #endif
            return suppress("NO_NIGHT")
        }
        if UserDefaults.standard.string(forKey: shownKey) == m.day.key { return suppress("ALREADY_SHOWN") }

        // Wake is the morning peak of the curve: the battery stops charging when she gets up.
        let noon = m.day.start.addingTimeInterval(8 * 3600)   // 04:00 + 8h
        let morning = m.reserveCurve.enumerated().filter { $0.element.ts < noon }
        guard let peak = morning.max(by: { $0.element.value < $1.element.value }) else { return suppress("NO_NIGHT") }
        guard now <= peak.element.ts.addingTimeInterval(6 * 3600) else { return suppress("PAST_WINDOW") }

        let charge = Int(drivers.lastNight.rounded())
        let nights = history.filter { $0.day != m.day && $0.reserveDrivers != nil }
            .sorted { $0.day > $1.day }.prefix(14).map { $0.reserveDrivers!.lastNight }
        let median: Double? = nights.count >= 3 ? nights.sorted()[nights.count / 2] : nil

        let f = DateFormatter(); f.dateFormat = "HH:mm"
        var title = L("LAST NIGHT · %@", f.string(from: peak.element.ts))
        var sentence: String
        var footer: String
        var tier: String? = nil

        if drivers.assumedAnchor {
            // edge 3 · FIRST MORNING
            title = L("FIRST READING · LOW CONFIDENCE")
            sentence = L("First night on the band — this one has a guess under it.")
            footer = L("%d ASSUMED + %d CHARGED", drivers.anchor, charge)
        } else if m.nightInputs?.hrv == nil {
            // edge 2 · HRV MISSING
            title = L("MULTIPLIER 1.00 · NO HRV YET")
            sentence = L("Reading it plain — no HRV to weigh it with.")
            footer = L("CHARGED +%d · ONE TIER DOWN", charge)
        } else if let med = median, med > 0 {
            // 1CDJ · the four tier words are relative to her own 14-night median. Only two of the
            // four are on the boards (NORMAL CHARGE · BARELY CHARGED); the upper tiers are left
            // without a word rather than given an invented one. ⚠️ 待定 — see STATUS.
            let r = drivers.lastNight / med
            if r < 0.6 {
                tier = L("BARELY CHARGED"); sentence = L("Barely charged. Today is a light one.")
            } else if r <= 1.4 {
                tier = L("NORMAL CHARGE"); sentence = L("About as much as you usually charge. Today can take a normal session.")
            } else {
                sentence = L("More than you usually charge.")
            }
            footer = tier.map { L("CHARGED +%d · %@", charge, $0) } ?? L("CHARGED +%d", charge)
        } else {
            sentence = L("%d charged overnight.", charge)
            footer = L("CHARGED +%d", charge)
        }

        let level = m.bodyBattery ?? wake
        #if DEBUG
        NSLog("MorningWidget frame: %@ · %@ · curve %d · peak %@", title, footer, m.reserveCurve.count, "\(peak.element.ts)")
        #endif
        return PanelWidget(
            type: .line, title: title, tag: .recover, sentence: sentence,
            footer: footer, action: L("TAP TO SEE WHY"), hero: "\(level)",
            accentOverride: NB.lime1, curveSplit: peak.offset, curveSecondary: NB.white.opacity(0.42),
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
