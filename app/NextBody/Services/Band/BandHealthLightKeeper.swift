import Foundation
import os

/// Writes the user's health-light choice back to the band on every connect.
///
/// The choice is made once, on the Device page. Firmware may forget it across a reboot or
/// a re-pair, and a light the user turned off has to stay off without them opening the
/// app again — so each `.connected` transition re-sends it. No choice, nothing sent: the
/// firmware's own default stands.
@MainActor
final class BandHealthLightKeeper {
    static let shared = BandHealthLightKeeper()
    private static let log = Logger(subsystem: "com.nextbody.hoop", category: "healthLight")
    /// Readiness reads identity and battery first, and a pairing takeover holds the band
    /// for a while; the write waits its turn and asks again rather than giving up once.
    /// ⚠️ A slot is spent only on a real failure. A band held by a workout or a measurement
    /// is not a refusal — that pass waits and asks again without using one up.
    private static let attemptDelays: [Double] = [3, 8, 15, 30, 60]
    /// Backstop for the passes that do not spend a slot (a held band, a reconcile).
    private static let maxPasses = 24
    private var events: Task<Void, Never>?
    private var apply: Task<Void, Never>?

    func start() {
        guard events == nil else { return }
        events = Task { @MainActor in
            for await event in Band.live.events {
                guard case .state(let state) = event else { continue }
                if state == .connected { schedule() } else { cancelPending() }
            }
        }
    }

    /// Called when the link drops. ⚠️ Not called by the sheet after its own write: a write
    /// already queued behind a day pull cannot be recalled, so cancelling here would only
    /// blind the keeper to the stale value it is about to send. It reconciles instead.
    func cancelPending() {
        apply?.cancel()
        apply = nil
    }

    private func schedule() {
        cancelPending()
        guard BandHealthLightPreference.stored() != nil else { return }
        apply = Task { @MainActor in
            var attempt = 0
            var passes = 0
            /// Set when the last write landed a value the user has since changed. The newer
            /// choice goes out immediately instead of waiting out the ladder.
            var reconciling = false
            while attempt < Self.attemptDelays.count, passes < Self.maxPasses {
                passes += 1
                if !reconciling { try? await Task.sleep(for: .seconds(Self.attemptDelays[attempt])) }
                reconciling = false
                guard !Task.isCancelled, Band.live.state == .connected else { return }
                // Read again each pass: the sheet may have changed the choice meanwhile.
                guard let wanted = BandHealthLightPreference.stored() else { return }
                // A takeover, a workout or a measurement owns the band. Wait for it.
                guard !BandLiveLifecycle.shared.hasExclusiveOperation,
                      let owner = LiveReadout.currentOwner else { continue }
                do {
                    let band = try await BandReadiness.read(account: owner.account, binding: owner.binding) {
                        try await Band.live.writeHealthLight(wanted)
                    }
                    Self.log.notice("health light applied wanted=\(wanted.rawValue, privacy: .public) band=\(band.rawValue, privacy: .public) attempt=\(attempt + 1, privacy: .public)")
                    NightDiagnostics.shared.record("band.health_light_applied",
                        fields: ["wanted": String(wanted.rawValue), "band": String(band.rawValue), "attempt": String(attempt + 1)])
                    // ⚠️ This write may have waited behind a day pull while the user chose
                    // something else on the sheet. The band now holds the older value, and
                    // the queue cannot be recalled — so send the newer one straight away.
                    guard BandHealthLightPreference.stored() != band else { return }
                    reconciling = true
                    continue
                } catch BandError.unsupported {
                    Self.log.notice("health light: this HOOP has no light control")
                    return
                } catch is CancellationError {
                    // The band was taken mid-command. Not a refusal; ask again for free.
                    continue
                } catch {
                    BandLog.shared.record("healthLight.apply", error: error)
                    NightDiagnostics.shared.record("band.health_light_apply_failed",
                        fields: ["attempt": String(attempt + 1)])
                    attempt += 1
                }
            }
        }
    }
}
