import SwiftUI

@main
struct NextBodyApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var router = Router()
    @StateObject private var data = DataStore.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(router)
                .environmentObject(data)
                .preferredColorScheme(.dark)
                .tint(NB.lime1)
        }
        // Events are queued and posted in batches — one request per tap would show up as
        // jank on exactly the screens they exist to measure. Leaving the app is the one
        // moment a partial batch has to go, or a session's tail is lost.
        .onChange(of: phase) { _, new in
            if new != .active { Task { await Analytics.shared.flush() } }
        }
    }
}
