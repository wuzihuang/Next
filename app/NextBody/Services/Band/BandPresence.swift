import Foundation
import os
import os

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
                case .battery(let b):
                    if let p = b.percent { store.band.batteryPercent = p }
                default:
                    break
                }
            }
        }
    }

    /// After a reconnect: identity, battery and capabilities off the band, and the devices
    /// row brought up to date so sync_runs and device_capabilities have an id to name.
    /// Quiet on failure — the header keeps showing a dash rather than a guess.
    func refresh(store: DataStore) async {
        guard Band.live.state == .connected else { return }
        store.band.connected = true
        let identity = try? await Band.live.readIdentity()
        let battery = try? await Band.live.readBattery()
        if let identity {
            store.band.name = identity.name
            store.band.mac = identity.bleIdentifier
            store.band.firmware = identity.firmware
        }
        if let battery, let p = battery.percent { store.band.batteryPercent = p }
        await Repository.shared.registerDevice(identity: identity, battery: battery)

        // 07 · the plus menu is gated on what this HOOP says it can do, read from the band
        // and stored, so the gate is right before the device page has ever been opened.
        if let caps = try? await Band.live.readCapabilities() {
            store.capabilities = caps
            store.capabilitiesReadAt = Date()
            if let deviceId = Repository.shared.deviceId,
               let userId = await SupabaseClient.shared.currentUserId {
                await Repository.shared.saveCapabilities(caps, deviceId: deviceId, userId: userId,
                                                          holdsDays: identity?.watchDataDayNumber)
            }
        }

        #if DEBUG
        // The band's own answer to "what can this HOOP measure" — one read, no sensor time.
        // Logged, not stored: nothing on screen reads it yet, and a capability that decides
        // what the plus menu offers has to be a deliberate change, not a side effect of a probe.
        // ⚠️ The guessed bits above have twice removed a working feature. When this list is
        // trusted enough to drive a menu, it should replace them — see readHealthFunctions.
        if let functions = try? await Band.live.readHealthFunctions(), !functions.isEmpty {
            let yes = functions.filter(\.support).map(\.name).joined(separator: ", ")
            let no = functions.filter { !$0.support }.map(\.name).joined(separator: ", ")
            Logger(subsystem: "com.nextbody.hoop", category: "band")
                .notice("this HOOP measures: \(yes, privacy: .public) · not: \(no, privacy: .public)")
        }
        #endif
    }
}
