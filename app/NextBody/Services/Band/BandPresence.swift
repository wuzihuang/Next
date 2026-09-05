import Foundation
import os
import Combine

/// The band's own facts on the home screen: whether it is linked, what its battery says,
/// what firmware it runs. On a device none of this was ever written after the gate — the
/// header printed the simulator's 82% for as long as the band was worn — because the only
/// writers were the pairing screen (walked once) and the device page (opened rarely).
///
/// One subscriber to `BandService.events` for the life of the process, plus one read after
/// every reconnect. Everything here is a fact the band reported; nothing is carried forward
/// from a value it did not.
@MainActor
final class BandPresence {
    static let shared = BandPresence()
    private var listener: Task<Void, Never>?

    /// Idempotent. `.state` keeps STANDBY / OFFLINE true to the link; `.battery` is what the
    /// SDK pushes on its own, which is the number the pip should show without being asked.
    func start(store: DataStore) {
        guard listener == nil else { return }
        listener = Task { @MainActor in
            for await event in Band.live.events {
                switch event {
                case .state(let s):
                    store.band.connected = (s == .connected)
                    if s != .connected { BandReadiness.shared.invalidateSnapshot() }
                case .battery(let b):
                    guard ConsentStore.shared.granted, SupabaseClient.currentUserIdSnapshot() != nil,
                          BoundBand.identifier != nil else { continue }
                    store.applyBandObservation(battery: b)
                default:
                    break
                }
            }
        }
    }

    /// After a reconnect: identity, battery and capabilities off the band, and the devices
    /// row brought up to date so sync_runs and device_capabilities have an id to name.
    /// Quiet on failure — the header keeps showing a dash rather than a guess.
    func refresh(store: DataStore, prepared: BandReadiness.Snapshot? = nil) async {
        guard Band.live.state == .connected, ConsentStore.shared.granted,
              let account = SupabaseClient.currentUserIdSnapshot(), let binding = BoundBand.identifier else { return }
        func isCurrent() -> Bool {
            ConsentStore.shared.granted && !BandLiveLifecycle.shared.hasExclusiveOperation
                && SupabaseClient.currentUserIdSnapshot() == account
                && BoundBand.identifier == binding && Band.live.state == .connected
        }
        store.band.connected = true
        let valid = prepared.flatMap { $0.account == account && $0.binding == binding ? $0 : nil }
        let identity: BandIdentity?
        let battery: BandBattery?
        if let valid {
            identity = valid.identity
            battery = valid.battery
        } else {
            identity = try? await BandReadiness.read(account: account, binding: binding, work: { try await Band.live.readIdentity() })
            guard isCurrent() else { return }
            battery = try? await BandReadiness.read(account: account, binding: binding, work: { try await Band.live.readBattery() })
        }
        guard isCurrent() else { return }
        store.applyBandObservation(identity: identity, battery: battery)
        await Repository.shared.registerDevice(identity: identity, battery: battery)

        guard isCurrent() else { return }

        // 07 · the plus menu is gated on what this HOOP says it can do, read from the band
        // and stored, so the gate is right before the device page has ever been opened.
        if let caps = try? await BandReadiness.read(account: account, binding: binding, work: { try await Band.live.readCapabilities() }) {
            guard isCurrent() else { return }
            store.capabilities = caps
            store.capabilitiesReadAt = Date()
            if let deviceId = Repository.shared.deviceId,
               let userId = await SupabaseClient.shared.currentUserId {
                await Repository.shared.saveCapabilities(caps, deviceId: deviceId, userId: userId,
                                                          holdsDays: identity?.watchDataDayNumber)
            }
        }

        #if DEBUG
        // `DEVICECTL_CHILD_NB_DEBUG_PROBE=healthglance` · run one 微体检 and print everything
        // that came back. ⚠️ A REAL measurement on the wrist, which is why it is behind a
        // launch flag and never runs on its own. `standDown` takes the band off the panel's
        // live readout first — the two cannot share the sensor.
        // `DEVICECTL_CHILD_NB_DEBUG_PROBE=manualdata` · what the watch itself has stored.
        // ⚠️ A read: nothing is measured, nothing lights up. The band hands back what the
        // user already pressed for on the watch.
        if ProcessInfo.processInfo.environment["NB_DEBUG_PROBE"] == "manualdata" {
            let log = Logger(subsystem: "com.nextbody.hoop", category: "probe")
            let since = Date().addingTimeInterval(-30 * 24 * 3600)
            log.notice("manual data probe · reading everything stored since \(since, privacy: .public)")
            await LiveReadout.shared.standDown {
                guard isCurrent() else { return }
                do {
                    let lines = try await Band.live.readManualTestData(since: since)
                    log.notice("manual data · \(lines.count) record(s)")
                    for line in lines { log.notice("manual data · \(line, privacy: .public)") }
                } catch {
                    log.error("manual data · \(String(describing: error), privacy: .public)")
                }
            }
        }

        // `DEVICECTL_CHILD_NB_DEBUG_PROBE=microtest` · 微体检 (定制项目), the other opcode.
        // ⚠️ A REAL measurement on the wrist.
        if ProcessInfo.processInfo.environment["NB_DEBUG_PROBE"] == "microtest" {
            let log = Logger(subsystem: "com.nextbody.hoop", category: "probe")
            log.notice("micro test probe · starting a real measurement")
            await LiveReadout.shared.standDown {
                guard isCurrent() else { return }
                do {
                    let values = try await Band.live.probeMicroTest { p in log.notice("micro test \(p)%") }
                    for (name, value) in values {
                        log.notice("micro test · \(name, privacy: .public) = \(value, privacy: .public)")
                    }
                } catch {
                    log.error("micro test · \(String(describing: error), privacy: .public)")
                }
            }
        }

        if ProcessInfo.processInfo.environment["NB_DEBUG_PROBE"] == "healthglance" {
            let log = Logger(subsystem: "com.nextbody.hoop", category: "probe")
            log.notice("health glance probe · starting a real measurement")
            await LiveReadout.shared.standDown {
                guard isCurrent() else { return }
                do {
                    let glance = try await Band.live.probeHealthGlance { p in
                        log.notice("health glance \(p)%")
                    }
                    log.notice("health glance · this band carries: \(glance.supported.joined(separator: ", "), privacy: .public)")
                    log.notice("health glance · not carried: \(glance.unsupported.joined(separator: ", "), privacy: .public)")
                    // Every field, zeros included: which ones the band left alone is half
                    // the answer, and a filtered list would hide it.
                    for (name, value) in glance.values {
                        log.notice("health glance · \(name, privacy: .public) = \(value, privacy: .public)")
                    }
                } catch {
                    log.error("health glance · \(String(describing: error), privacy: .public)")
                }
            }
        }

        // The band's own answer to "what can this HOOP measure" — one read, no sensor time.
        // Logged, not stored: nothing on screen reads it yet, and a capability that decides
        // what the plus menu offers has to be a deliberate change, not a side effect of a probe.
        // ⚠️ The guessed bits above have twice removed a working feature. When this list is
        // trusted enough to drive a menu, it should replace them — see readHealthFunctions.
        if let functions = try? await BandReadiness.read(account: account, binding: binding, work: { try await Band.live.readHealthFunctions() }), !functions.isEmpty {
            let yes = functions.filter(\.support).map(\.name).joined(separator: ", ")
            let no = functions.filter { !$0.support }.map(\.name).joined(separator: ", ")
            Logger(subsystem: "com.nextbody.hoop", category: "band")
                .notice("this HOOP measures: \(yes, privacy: .public) · not: \(no, privacy: .public)")
        }
        #endif
    }
}

/// Shared progress spans connection, device reads, upload and historical backfill.
@MainActor
final class BandSyncActivity: ObservableObject {
    static let shared = BandSyncActivity()
    @Published var phase = "idle"
}
