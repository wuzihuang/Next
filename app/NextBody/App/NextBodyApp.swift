import SwiftUI

@main
struct NextBodyApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var router = Router()
    @StateObject private var data = DataStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(router)
                .environmentObject(data)
                .preferredColorScheme(.dark)
                .tint(NB.lime1)
        }
    }
}
