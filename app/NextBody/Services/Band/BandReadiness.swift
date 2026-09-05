import Foundation
import os

/// Connection + fresh battery only. Cloud registration and historical reads belong to
/// the full sync lane and never prevent foreground callers from checking the live link.
@MainActor
final class BandReadiness {
    static let shared = BandReadiness()
    private let flight = BandReadinessFlight()
    private let nativeDrain = BandNativeDrain()
    private let log = Logger(subsystem: "com.nextbody.hoop", category: "readiness")
    private(set) var snapshot: Snapshot?

    struct Snapshot {
        let account: String
        let binding: String
        let identity: BandIdentity?
        let battery: BandBattery
    }

    func ensureReady(into store: DataStore, reason: String, reuseRecentLiveReceipt: Bool = false) async -> Bool {
        guard let account = SupabaseClient.currentUserIdSnapshot(),
              let binding = BoundBand.identifier, allowed(account: account, binding: binding) else { return false }
        if reuseRecentLiveReceipt, Band.live.state == .connected,
           LiveReadout.shared.hasRecentReceipt(maxAge: 3) {
            store.band.connected = true
            log.notice("readiness reuse real-live-receipt")
            return true
        }
        let ready = await flight.run(key: account + ":" + binding) { [self] in
            guard allowed(account: account, binding: binding) else { return false }
            let start = ProcessInfo.processInfo.systemUptime
            // Reasons are code-owned labels. Do not log account, MAC, UUID or raw errors.
            let label = String(reason.filter { $0.isLetter || $0 == "-" }.prefix(40))
            log.notice("readiness start reason=\(label, privacy: .public) reuse=\(Band.live.state == .connected)")
            BandPresence.shared.start(store: store)
            nativeDrain.begin()
            defer { nativeDrain.end() }
            return await LiveReadout.shared.standDown {
                guard allowed(account: account, binding: binding) else { return false }
                if Band.live.state != .connected { await Band.live.reconnectIfBound() }
                guard allowed(account: account, binding: binding), Band.live.state == .connected else { return false }
                log.notice("readiness connected elapsed=\(ProcessInfo.processInfo.systemUptime - start)")
                let identity = try? await Band.live.readIdentity()
                guard allowed(account: account, binding: binding), Band.live.state == .connected else { return false }
                do {
                    let battery = try await Band.live.readBattery()
                    guard allowed(account: account, binding: binding), Band.live.state == .connected else { return false }
                    snapshot = Snapshot(account: account, binding: binding, identity: identity, battery: battery)
                    store.band.connected = true
                    store.applyBandObservation(identity: identity, battery: battery)
                    log.notice("readiness battery elapsed=\(ProcessInfo.processInfo.systemUptime - start)")
                    return true
                } catch {
                    log.error("readiness battery failed elapsed=\(ProcessInfo.processInfo.systemUptime - start)")
                    return false
                }
            }
        }
        return ready && allowed(account: account, binding: binding) && Band.live.state == .connected
    }

    /// Pause the live sensor for native commands only, never for a cloud request.
    static func read<T>(account: String, binding: String,
                        work: () async throws -> T) async throws -> T {
        guard shared.allowed(account: account, binding: binding), Band.live.state == .connected else {
            throw CancellationError()
        }
        shared.nativeDrain.begin()
        defer { shared.nativeDrain.end() }
        let result: Result<T, Error> = await LiveReadout.shared.standDown {
            guard shared.allowed(account: account, binding: binding), Band.live.state == .connected else {
                return .failure(CancellationError())
            }
            do {
                let value = try await work()
                guard shared.allowed(account: account, binding: binding), Band.live.state == .connected else {
                    return .failure(CancellationError())
                }
                return .success(value)
            } catch { return .failure(error) }
        }
        return try result.get()
    }

    /// Call after closing native admission with the exclusive-operation gate.
    func awaitNativeIdle() async { await nativeDrain.waitUntilIdle() }

    func invalidateSnapshot() { snapshot = nil }

    private func allowed(account: String, binding: String) -> Bool {
        !Task.isCancelled && ConsentStore.shared.granted && LiveSessionStore.shared.session == nil
            && !BandLiveLifecycle.shared.hasExclusiveOperation
            && SupabaseClient.currentUserIdSnapshot() == account && BoundBand.identifier == binding
    }
}
