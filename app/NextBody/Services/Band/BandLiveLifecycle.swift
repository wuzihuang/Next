import Combine
import SwiftUI
import os

/// Process-owned live collection. CoreBluetooth background events may wake this work;
/// this does not claim unlimited background execution or restart after force quit.
@MainActor
final class BandLiveLifecycle {
    static let shared = BandLiveLifecycle()
    private var phase: BandLivePolicy.Phase = .active
    private var foregroundWanted = false
    private var exclusive = false
    private let tasks = BandLiveTaskOwner()
    private var observers = Set<AnyCancellable>()
    private var events: Task<Void, Never>?

    func start() {
        guard events == nil else { return }
        ConsentStore.shared.objectWillChange.sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &observers)
        LiveSessionStore.shared.objectWillChange.sink { [weak self] _ in self?.scheduleRefresh() }.store(in: &observers)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.refreshEligibility() } }.store(in: &observers)
        events = Task { @MainActor in
            for await event in Band.live.events {
                if case .state = event { self.refreshEligibility() }
            }
        }
        NotificationCenter.default.publisher(for: SupabaseClient.accountDidChange)
            .sink { [weak self] _ in Task { @MainActor in
                BandReadiness.shared.invalidateSnapshot()
                self?.refreshEligibility()
            } }.store(in: &observers)
        refreshEligibility()
    }

    private func scheduleRefresh() {
        // objectWillChange fires before the new property is written.
        Task { @MainActor in self.refreshEligibility() }
    }

    func setPhase(_ scenePhase: ScenePhase) {
        Logger(subsystem: "com.nextbody.hoop", category: "lifecycle")
            .notice("scene phase=\(String(describing: scenePhase), privacy: .public)")
        switch scenePhase {
        case .active: phase = .active
        case .background: phase = .background
        default: phase = .inactive
        }
        LiveReadout.shared.setBackground(phase != .active)
        refreshEligibility()
    }

    func setForegroundWanted(_ wanted: Bool) {
        foregroundWanted = wanted
        refreshEligibility()
    }

    func setExclusiveOperation(_ value: Bool) {
        exclusive = value
        refreshEligibility()
    }

    var hasExclusiveOperation: Bool {
        exclusive || LiveSessionStore.shared.session != nil || LiveSessionStore.shared.opening
            || LiveSessionStore.shared.cleaningUp || BandMeasurementLifetime.shared.isBusy
    }

    func refreshEligibility() {
        let owner = LiveReadout.currentOwner
        let allowed = BandLivePolicy.shouldRun(phase: phase, foregroundWanted: foregroundWanted,
            hasOwner: owner != nil, consent: ConsentStore.shared.granted,
            connected: Band.live.state == .connected,
            exclusive: hasExclusiveOperation)
        tasks.update(owner: allowed ? owner : nil) {
            await LiveReadout.shared.run()
        }
    }
}

extension BandMeasurementLifetime {
    static let shared = BandMeasurementLifetime(
        acquire: { await BandReadiness.shared.beginMeasurement() },
        release: { await BandReadiness.shared.endMeasurement() },
        changed: { BandLiveLifecycle.shared.refreshEligibility() })
}
