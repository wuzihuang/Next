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
    func saveCapabilities(_ caps: BandCapabilities, deviceId: String, userId: String) async {
        _ = try? await db.upsert("device_capabilities", row: [
            "device_id": deviceId,
            "user_id": userId,
            "read_at": ISO8601DateFormatter().string(from: Date()),
            "functions": caps.functions.mapValues(\.rawValue),
            "body_component": caps.bodyComponent.rawValue,
            "ecg": caps.ecg.rawValue,
            "hrv": caps.hrv.rawValue,
            "stress": caps.stress.rawValue,
            "auto_measure": caps.autoMeasure.rawValue,
        ], onConflict: "device_id")
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
