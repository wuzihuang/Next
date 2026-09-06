import GoogleSignIn
import SwiftUI
import UIKit
import os

@main
struct NextBodyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = SessionStore()
    @StateObject private var router = Router()
    @StateObject private var data = DataStore.shared
    @StateObject private var language = AppLanguage.shared
    @Environment(\.scenePhase) private var phase

    init() {
        _ = LaunchFilmPolicy.processStart
        Logger(subsystem: "com.nextbody.hoop", category: "lifecycle").notice("app initialized")
        NightDiagnostics.shared.record("app.launch", fields: NightDiagnostics.shared.status)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(router)
                .environmentObject(data)
                .environmentObject(language)
                .environment(\.locale, language.swiftLocale)
                .id(language.locale.rawValue)
                .preferredColorScheme(.dark)
                .tint(NB.lime1)
                // 01 · the Google account picker comes back through our reversed-client-ID
                // scheme; the SDK's continuation is waiting on this hand-off.
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    openIncoming(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: NotificationReach.deepLinkDidArrive)) { note in
                    if let url = note.object as? URL { openIncoming(url) }
                }
                // 14 · an island left counting for a session this process is not in — the app
                // was killed mid-workout, or replaced under a running one. The store is empty
                // at launch by definition, so anything still up is an orphan.
                .onReceive(Reachability.shared.$isOnline.removeDuplicates()) { online in
                    if online { Task { await Repository.shared.flushPendingEvidence() } }
                }
                .task {
                    BandLiveLifecycle.shared.start()
                    BandLiveLifecycle.shared.setPhase(phase)
                    SessionActivity.clearOrphans()
                    // Restoring the local account gates BLE, not cloud homepage hydration.
                    if await session.ensureSession() { requestForegroundRefresh(reason: "launch") }
                    await session.resolveLaunch()
                    WidgetGlancePublisher.publish(from: data)
                    BandLiveLifecycle.shared.refreshEligibility()
                }
                .onChange(of: phase) { _, new in
                    NightDiagnostics.shared.record("app.scene", fields: ["phase": String(describing: new)])
                    BandLiveLifecycle.shared.setPhase(new)
                    if new != .active {
                        WidgetGlancePublisher.publish(from: data)
                        Task { await Analytics.shared.flush() }
                    }
                }
                .onChange(of: router.takeover) { previous, takeover in
                    BandLiveLifecycle.shared.setExclusiveOperation(takeover != nil)
                    // The consent screen owns the exclusive gate until it closes. Resume
                    // only after releasing it, so a grant cannot be swallowed by readiness.
                    if previous == .consent, takeover == nil, ConsentStore.shared.granted {
                        requestForegroundRefresh(reason: "consent")
                    }
                    if takeover == nil { router.flushQueuedLink() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    BandLiveLifecycle.shared.setPhase(.background)
                    WidgetGlancePublisher.publish(from: data)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    BandLiveLifecycle.shared.setPhase(.active)
                    requestForegroundRefresh(reason: "foreground")
                }
        }
    }

    private func requestForegroundRefresh(reason: String) {
        NightDiagnostics.shared.record("app.refresh_requested", fields: ["reason": reason])
        Logger(subsystem: "com.nextbody.hoop", category: "lifecycle")
            .notice("foreground refresh reason=\(reason, privacy: .public)")
        // Publication still happens, but is not a dependency of local BLE readiness.
        Task {
            await ConsentStore.shared.flushPending()
            await Repository.shared.flushPendingEvidence()
        }
        Task {
            guard await session.ensureSession() else { return }
            BandLiveLifecycle.shared.refreshEligibility()
            guard !BandLiveLifecycle.shared.hasExclusiveOperation else { return }
            let coldLaunch = reason == "launch"
            await OriginDataSync.refreshNow(into: data,
                minimumInterval: coldLaunch ? 0 : SyncCadence.interval,
                fullHistory: coldLaunch, reuseRecentLiveReceipt: !coldLaunch)
            await NotificationReach.refresh(today: data.today, history: data.history,
                                            store: data, page: router.notifyPage, appIsActive: true)
        }
    }

    private func openIncoming(_ url: URL) {
        if WidgetBridge.isPhotoLog(url) {
            WidgetBridge.rememberPhoto()
            NotificationCenter.default.post(name: WidgetBridge.photoDidArrive, object: nil)
            return
        }
        guard session.stage == .root else { return }
        guard let link = NotificationDeepLink.parse(url) else { return }
        router.receive(link)
    }
}
