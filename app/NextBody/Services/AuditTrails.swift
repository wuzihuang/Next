import Foundation

/// F3's audit tables, written from the client side.
///
/// Each of these exists to answer a question after the fact — what could this band do, why
/// did she say that, what did the user actually see. An empty audit table answers those
/// questions wrongly rather than not at all, which is worse: it looks like nothing happened.
/// (sync_runs is written by OriginDataSync, next to the sync it describes.)

// MARK: - device_capabilities

extension Repository {
    /// 12 · what this HOOP reports it can do. Stored so the device page and 07's
    /// capabilities() gate work before the band has answered — or when it is out of range.
    func loadCapabilities(into store: DataStore) async {
        let rows = (try? await db.select("device_capabilities", query: [
            .init(name: "select",
                  value: "functions,body_component,ecg,hrv,stress,auto_measure,watch_data_day_number,read_at"),
            .init(name: "limit", value: "1"),
        ])) ?? []
        guard let row = rows.first else { return }

        var caps = BandCapabilities()
        func status(_ any: Any?) -> FunctionStatus {
            FunctionStatus(rawValue: (any as? String) ?? "") ?? .unknown
        }
        caps.bodyComponent = status(row["body_component"])
        caps.ecg = status(row["ecg"])
        caps.hrv = status(row["hrv"])
        caps.stress = status(row["stress"])
        caps.autoMeasure = status(row["auto_measure"])
        if let fns = row["functions"] as? [String: Any] {
            caps.functions = fns.mapValues { status($0) }
        }
        store.capabilities = caps
        store.capabilitiesReadAt = (row["read_at"] as? String).flatMap(Self.timestamp)
    }

    /// ⚠️ Written verbatim, never squashed into booleans. On screen "unknown" and
    /// "unsupported" both mean the row is not drawn; when something is wrong they are two
    /// completely different problems, and only one of them is the band's fault.
    /// `holdsDays` is the band's saveDays — how many days of history it still carries. It
    /// travels with the capability row because the backfill and the ON DEVICE fact both
    /// read it, and a null there made both fall back to a number the app made up.
    func saveCapabilities(_ caps: BandCapabilities, deviceId: String, userId: String,
                          holdsDays: Int? = nil) async {
        var row: [String: Any] = [
            "device_id": deviceId,
            "user_id": userId,
            "read_at": ISO8601DateFormatter().string(from: Date()),
            "functions": caps.functions.mapValues(\.rawValue),
            "body_component": caps.bodyComponent.rawValue,
            "ecg": caps.ecg.rawValue,
            "hrv": caps.hrv.rawValue,
            "stress": caps.stress.rawValue,
            "auto_measure": caps.autoMeasure.rawValue,
        ]
        if let holdsDays, holdsDays > 0 { row["watch_data_day_number"] = holdsDays }
        _ = try? await db.upsert("device_capabilities", row: row, onConflict: "device_id")
    }
}

// MARK: - profiles

extension Repository {
    /// F3 §02.3 · profile edits are client-direct RLS writes, not endpoints.
    ///
    /// ⚠️ The sheets used to assign to `data.profile` and stop there. The row looked right
    /// until the next launch, and in the meantime the server went on computing every target
    /// from the old goal — the one place where a change that silently does not happen is
    /// worse than a change that visibly fails.
    ///
    /// A field the user edits is marked `edit` in field_sources, which every later
    /// HealthKit sync skips. We do not compare timestamps and we never win against them.
    ///
    /// ⚠️ This was a PATCH, and nothing anywhere inserted the row. The demo account had one
    /// from the seed; a real account had none, so every save updated zero rows, and the
    /// server — which reads timezone, birth_date, sex and height_cm off this row before it
    /// computes anything — computed nothing for as long as the account existed. It is an
    /// upsert on user_id now, and it carries every column the computation reads.
    func saveProfile(_ profile: Profile, editedFields: [String]) async {
        guard let userId = await db.currentUserId else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var row: [String: Any] = [
            "user_id": userId,
            "timezone": TimeZone.current.identifier,
            "goal": profile.goal.rawValue,
            "units_metric": profile.usesMetric,
            "height_cm": profile.heightCm,
            "sex": profile.sexIsMale ? "male" : "female",
            "birth_date": f.string(from: profile.birthdate),
        ]
        if !profile.name.isEmpty { row["display_name"] = profile.name }
        if !editedFields.isEmpty {
            var sources: [String: String] = [:]
            for e in editedFields { sources[e] = "edit" }
            row["field_sources"] = sources
        }
        do { _ = try await db.upsert("profiles", row: row, onConflict: "user_id") }
        catch {
            #if DEBUG
            NSLog("Repository.saveProfile failed: %@", "\(error)")
            #endif
        }
        await Analytics.shared.track("PROFILE_EDITED", ["FIELDS": editedFields])
    }

    /// Just the name, for the one caller that has a name and nothing else to say: the first
    /// Apple authorization. It cannot go through `saveProfile`, which would write a whole
    /// profile of defaults over whatever onboarding is about to establish.
    func saveDisplayName(_ name: String) async {
        guard let userId = await db.currentUserId, !name.isEmpty else { return }
        do { _ = try await db.upsert("profiles", row: ["user_id": userId, "display_name": name],
                                     onConflict: "user_id") }
        catch {
            #if DEBUG
            NSLog("Repository.saveDisplayName failed: %@", "\(error)")
            #endif
        }
    }

    /// The row the computation hangs off, with at least the timezone on it. Called on every
    /// launch: a missing row is created, and a phone that has moved zones tells the server —
    /// the user day is cut at local 04:00, and the server can only know "local" from here.
    func ensureProfileRow(existingTimezone: String?) async {
        guard let userId = await db.currentUserId else { return }
        let tz = TimeZone.current.identifier
        if existingTimezone == tz { return }
        _ = try? await db.upsert("profiles", row: ["user_id": userId, "timezone": tz], onConflict: "user_id")
    }
}

// MARK: - analytics_events

/// The boards name their events exactly — BB_MORNING_SHOWN{SCORE,DELTA,BAND},
/// BB_DETAIL_OPEN{ENTRY}, COMP_CALL_CHANGED{REASON} — because each acceptance line is
/// written against a specific one. A different name is a line nobody can check.
///
/// Queued and posted in batches: an event that costs a request at the moment of a tap
/// would show up as jank on the very screens these events are meant to measure.
actor Analytics {
    static let shared = Analytics()
    private let db = SupabaseClient.shared
    private var pending: [[String: Any]] = []
    private var flushing = false

    func track(_ name: String, _ props: [String: Any] = [:]) async {
        pending.append([
            "name": name,
            "props": props,
            "client_ts": ISO8601DateFormatter().string(from: Date()),
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            "device_model": "iPhone",
        ])
        if pending.count >= 4 { await flush() }
    }

    /// 11 · DELETE EVERYTHING. ⚠️ flush() stamps user_id at flush time, not at track time,
    /// so a buffer left over from the deleted account would be posted under whoever signs in
    /// next on this phone. The batch is unsendable anyway — its own account is gone and the
    /// insert would 401 — so this drops it rather than misattributing it.
    func purge() { pending.removeAll() }

    func flush() async {
        guard !flushing, !pending.isEmpty, let userId = await db.currentUserId else { return }
        flushing = true
        let batch = pending.map { row -> [String: Any] in
            var r = row; r["user_id"] = userId; return r
        }
        pending.removeAll()
        // A dropped analytics batch is never worth surfacing to the user; it is also never
        // worth retrying forever, because the next flush carries the newer events anyway.
        // Write-only by design: no select policy, so nothing may be asked for in return.
        if (try? await db.insert("analytics_events", rows: batch, returning: false)) == nil {
            // put them back, once — a flat network blip should not lose a session
            pending.insert(contentsOf: batch.map { r in
                var c = r; c.removeValue(forKey: "user_id"); return c
            }, at: 0)
        }
        flushing = false
    }
}
