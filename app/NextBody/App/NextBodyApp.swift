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
    @StateObject private var billing = BillingStore.shared
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
                .environmentObject(billing)
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
                    billing.configure()
                    if await session.ensureSession() {
                        if let userId = await SupabaseClient.shared.currentUserId {
                            await billing.identify(userId: userId)
                        }
                        requestForegroundRefresh(reason: "launch")
                    }
                    await session.resolveLaunch()
                    WidgetGlancePublisher.publish(from: data)
                    BandLiveLifecycle.shared.refreshEligibility()
                    #if DEBUG
                    if session.stage == .root { await DebugBandValidation.run(into: data) }
                    #endif
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
                    if previous == .consent, takeover == nil {
                        requestForegroundRefresh(reason: "consent")
                    }
                    if takeover == nil { router.flushQueuedLink() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    BandLiveLifecycle.shared.setPhase(.background)
                    WidgetGlancePublisher.publish(from: data)
                    // ADR 0026 · a widget on the home screen keeps the reserve moving while
                    // the app is away: the next pull is asked for the moment we leave.
                    BackgroundRefresh.shared.scheduleIfWidgetPlaced()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    BandLiveLifecycle.shared.setPhase(.active)
                    // Issue #20 · someone reading this screen is awake, whatever the wrist
                    // says. The mark is what SleepWakeClamp cuts the recorded night at.
                    AwakeEvidence.record()
                    Task { await billing.refresh() }
                    requestForegroundRefresh(reason: "foreground")
                    // ADR 0018 · idle sessions fold into memory the next time the app is in front.
                    AISession.shared.settleIfDue()
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
            let owner = SupabaseClient.currentUserIdSnapshot()
            if reason == "consent", await OriginDataSync.refreshAfterConsent(into: data) != nil {
                // A manual request resumes here, after the takeover gate was released.
            } else {
                // ADR 0026 · every return to the app asks the wrist, whatever the device page's
                // cadence says; `.foreground` (the home screen's own timer) still honours it.
                // Home and didBecomeActive may already have completed the launch pull.
                // Routine work still repairs missing history; launch is not a force button.
                await OriginDataSync.refreshNow(into: data, request: reason == "launch" ? .automatic : .resume)
            }
            guard owner == SupabaseClient.currentUserIdSnapshot() else { return }
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
