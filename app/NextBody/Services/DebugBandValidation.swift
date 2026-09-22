#if DEBUG
import Foundation
import os

/// Explicit physical-device acceptance run. Uses production permission gates and
/// coordinators; never injects samples or changes the account, binding, or clock.
@MainActor
enum DebugBandValidation {
    private static var started = false
    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "band-validation")

    static func run(into data: DataStore) async {
        let requested = ProcessInfo.processInfo.environment["NB_DEBUG_REAL_BAND_VALIDATION"]
        guard let requested, ["1", "sync", "sport", "once"].contains(requested),
              !started, Band.isReal, !Band.allowsSeed,
              !LiveSessionStore.debugFakeWrist,
              let account = SupabaseClient.currentUserIdSnapshot(),
              let binding = BoundBand.identifier, ConsentStore.shared.granted else { return }
        started = true
        let authorized = {
            ConsentStore.shared.granted && SupabaseClient.currentUserIdSnapshot() == account
                && BoundBand.identifier == binding
        }
        event("begin")
        await OriginDataSync.waitForCurrentPull()
        guard authorized(), !Task.isCancelled else { event("cancelled"); return }
        let cycles = requested == "sport" ? 0 : (requested == "once" ? 1 : 3)
        for index in 0..<cycles {
            let cycle = index + 1
            do { try await Task.sleep(for: .seconds(3)) } catch { event("cancelled"); return }
            guard authorized(), !Task.isCancelled else { event("cancelled"); return }
            let began = ProcessInfo.processInfo.systemUptime
            event("sync_begin", fields: ["cycle": String(cycle)])
            let result = await OriginDataSync.refreshNow(into: data, request: .latest)
            event("sync_end", fields: ["cycle": String(cycle), "status": result.status.rawValue,
                "durationSeconds": String(ProcessInfo.processInfo.systemUptime - began)])
        }
        if requested == "sync" || requested == "once" { event("complete"); return }
        guard authorized(), !Task.isCancelled, Band.live.state == .connected else {
            event("sport_skipped"); return
        }
        let live = LiveSessionStore.shared
        guard live.session == nil, !live.cleaningUp,
              let mode = SportModeCatalog.modes.first(where: { $0.rawValue == 0 }) else {
            event("sport_busy"); return
        }
        event("sport_begin")
        live.begin(mode, profile: data.profile,
            weightKg: data.today.weightKg ?? data.weighIns.first?.weightKg, authorized: authorized)
        guard let id = live.session?.id else { event("sport_not_started"); return }
        // Both normal completion and cancellation close only the session this run owns.
        var cleaning = false
        let cleanup: @MainActor () async -> Void = {
            guard live.session?.id == id, !cleaning else { return }
            cleaning = true
            if live.refusal == nil { _ = await live.stop(authorized: authorized) }
            let hadError = live.errorLine != nil || live.refusal != nil
            if live.session?.id == id { live.end() }
            event("sport_stopped", fields: ["stopReportedError": String(hadError)])
        }
        await withTaskCancellationHandler {
            let deadline = ProcessInfo.processInfo.systemUptime + 90
            var firstHeartAt: TimeInterval?
            var lastReceipt: Date?
            var count = 0
            while authorized(), !Task.isCancelled, live.session?.id == id,
                  live.refusal == nil, ProcessInfo.processInfo.systemUptime < deadline {
                if let receipt = live.hrAt, receipt != lastReceipt {
                    firstHeartAt = firstHeartAt ?? ProcessInfo.processInfo.systemUptime
                    count += 1
                    event("heart_observed", fields: ["index": String(count),
                        "receiptAgeMs": String(max(0, Date().timeIntervalSince(receipt) * 1000)),
                        "gapSeconds": lastReceipt.map { String(receipt.timeIntervalSince($0)) } ?? "first"])
                    lastReceipt = receipt
                }
                if let firstHeartAt, ProcessInfo.processInfo.systemUptime - firstHeartAt >= 40 { break }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
            }
            event("sport_observation_end", fields: ["receiptCount": String(count)])
            await cleanup()
        } onCancel: {
            Task { @MainActor in await cleanup() }
        }
        event("complete")
    }

    private static func event(_ name: String, fields: [String: String] = [:]) {
        NightDiagnostics.shared.record("validation.\(name)", fields: fields)
        log.notice("validation \(name, privacy: .public) \(fields.description, privacy: .public)")
    }
}
#endif
