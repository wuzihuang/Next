import BackgroundTasks
import Foundation
import WidgetKit
import os

/// ADR 0026 · the half-hourly pull the widget lives on while the app is away.
///
/// One `BGAppRefreshTask`. The system launches this process in the background, we ask the
/// wrist for today, the server settles the day from what came up, the App Group glance is
/// rewritten and the widget redraws. Then the next run is asked for. iOS owns the actual
/// moment — `earliestBeginDate` is a floor, not a schedule — so the cadence is "every
/// thirty minutes when the phone allows it", never a promise of eleven runs a day.
///
/// Nothing here computes a reserve. The phone still only carries ticks up and reads a row
/// back (F2 rule 02); `BackgroundRefreshPolicy` decides when asking is worth a radio wake.
@MainActor
final class BackgroundRefresh {
    static let shared = BackgroundRefresh()
    private let log = Logger(subsystem: "com.nextbody.hoop", category: "background")
    private var running: Task<Void, Never>?

    /// Registration has to happen before the app finishes launching, so the delegate calls it.
    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundRefreshPolicy.taskIdentifier, using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in BackgroundRefresh.shared.handle(refresh) }
        }
    }

    /// Called on every trip to the background and after every run. The widget question is
    /// asked of WidgetKit each time: a widget removed since the last trip cancels the run.
    func scheduleIfWidgetPlaced(now: Date = Date()) {
        WidgetCenter.shared.getCurrentConfigurations { result in
            let placed = (try? result.get())?.count ?? 0
            Task { @MainActor in BackgroundRefresh.shared.schedule(widgetCount: placed, now: now) }
        }
    }

    private func schedule(widgetCount: Int, now: Date) {
        let signedIn = SupabaseClient.currentUserIdSnapshot() != nil || SessionKeychain.userId != nil
        guard BackgroundRefreshPolicy.shouldSchedule(
            widgetCount: widgetCount, signedIn: signedIn, bound: BoundBand.identifier != nil)
        else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundRefreshPolicy.taskIdentifier)
            log.notice("background refresh not scheduled widgets=\(widgetCount) signedIn=\(signedIn)")
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: BackgroundRefreshPolicy.taskIdentifier)
        let begin = BackgroundRefreshPolicy.nextBeginDate(now: now, lastPullAt: DataStore.shared.lastSync)
        request.earliestBeginDate = begin
        do {
            try BGTaskScheduler.shared.submit(request)
            log.notice("background refresh scheduled notBefore=\(begin, privacy: .public) widgets=\(widgetCount)")
            NightDiagnostics.shared.record("background.scheduled", fields: [
                "notBefore": ISO8601DateFormatter().string(from: begin), "widgets": String(widgetCount),
            ])
        } catch {
            // Denied on the simulator and when the user turned Background App Refresh off.
            log.error("background refresh submit failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        running?.cancel()
        let completion = BackgroundTaskCompletion(task)
        let work = Task { @MainActor in
            NightDiagnostics.shared.record("background.started")
            let done = await refresh()
            NightDiagnostics.shared.record("background.finished", fields: ["done": String(done)])
            scheduleIfWidgetPlaced()
            completion.finish(success: done)
        }
        running = work
        // The system gives a few seconds' notice. Cancel the pull so the BLE and upload
        // awaits unwind, and close the task ourselves rather than wait for them to.
        task.expirationHandler = {
            work.cancel()
            completion.finish(success: false)
        }
    }

    /// Today off the wrist, settled on the server, read back, written to the widget. The
    /// settle-and-reload runs even when the band was out of reach, so a number the hourly
    /// cron produced still reaches the home screen.
    private func refresh() async -> Bool {
        let store = DataStore.shared
        try? await Repository.shared.openSession()
        guard SupabaseClient.currentUserIdSnapshot() != nil else {
            log.notice("background refresh · no session")
            return false
        }
        let result = await OriginDataSync.refreshNow(into: store, request: .background)
        log.notice("background pull status=\(result.status.rawValue, privacy: .public) points=\(result.points)")
        guard !Task.isCancelled else { return false }
        await Repository.shared.flushPendingEvidence()
        guard !Task.isCancelled else { return false }
        WidgetGlancePublisher.publish(from: store)
        HomeSnapshot.save(from: store)
        return BackgroundRefreshPolicy.completed(result.status)
    }
}

/// `setTaskCompleted` may be reached from the run and from the expiration handler, on
/// different queues, and must be called exactly once.
private final class BackgroundTaskCompletion: @unchecked Sendable {
    private let task: BGAppRefreshTask
    private let finished = OSAllocatedUnfairLock(initialState: false)

    init(_ task: BGAppRefreshTask) { self.task = task }

    func finish(success: Bool) {
        let first = finished.withLock { done -> Bool in
            if done { return false }
            done = true
            return true
        }
        guard first else { return }
        task.setTaskCompleted(success: success)
    }
}
