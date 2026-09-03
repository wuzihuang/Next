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
            // Coming back is the moment the numbers are most obviously old: the band has been
            // recording the whole time the app was away. Pulling here means the day is
            // already on the screen when the user looks at it, instead of arriving a few
            // seconds after they do.
            if new == .active {
                Task {
                    // A consent decided before the session existed goes up first: the
                    // server refuses every turn until it has one.
                    await ConsentStore.shared.flushPending()
                    await OriginDataSync.refreshNow(into: data)
                }
            }
        }
    }
}
