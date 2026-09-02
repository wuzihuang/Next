import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: Router

    var body: some View {
        ZStack {
            switch session.stage {
            case .gateSignIn:     SignInFlow()
            case .gateConnect:    ConnectFlow()
            case .gateOnboarding: OnboardingFlow()
            case .root:           rootStack
            }
        }
        .carbonPage()
        // 05 · A · the keyboard is the dock's business alone; the page never shrinks for it.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // F5 C11 · 「maxFontSizeMultiplier = 1.35，允许到 xLarge；再大冻结在 1.35」. Fixed-pixel layouts
        // are the honest compromise the board names: the largest accessibility sizes are not
        // pretended to, but nothing clips at any size that is honoured.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .fullScreenCover(item: $router.takeover) { t in
            TakeoverHost(takeover: t)
        }
        .sheet(item: $router.sheet) { s in
            SheetHost(route: s)
        }
    }

    private var rootStack: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Destination.self) { d in
                    switch d {
                    case .training:               TrainingDetailView()
                    case .fuel:                   FuelDetailView()
                    case .bodyBattery:            BodyBatteryDetailView()
                    case .composition(let date):  CompositionDetailView(focus: date)
                    case .profile:                ProfileView()
                    case .device:                 DeviceView()
                    // F1 · D — the band's alarms and auto-measurement are sheets on the
                    // device page, not third-level pages.
                    case .deviceAlarms:           DeviceView()
                    case .deviceAutoMonitor:      DeviceView()
                    }
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        // `SIMCTL_CHILD_NB_DEBUG_ROUTE=composition` opens straight onto a detail page for a walk.
        .onAppear {
            if let r = ProcessInfo.processInfo.environment["NB_DEBUG_ROUTE"],
               let d = Destination(envelopeTarget: r), router.path.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { router.open(d, from: .home) }
            }
        }
        #endif
        // 05 · A · the keyboard moves the dock and nothing else. Without this the stack itself
        // slid the whole home screen up under the status bar.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

/// D · ON TOP. A takeover is the panel grown to full screen, never a page.
struct TakeoverHost: View {
    let takeover: Takeover
    @EnvironmentObject private var router: Router

    var body: some View {
        switch takeover {
        case .wordmark:
            WordmarkAnimation(onFinish: { router.takeover = nil })
        case .measure(let kind):
            MeasureTakeover(kind: kind) { router.takeover = nil }
        case .consent:
            ConsentScreen(onContinue: { router.takeover = nil }, onBack: { router.takeover = nil })
        case .notificationPrimer:
            NotificationPrimer(onDone: { router.takeover = nil })
        }
    }
}

struct SheetHost: View {
    let route: SheetRoute
    var body: some View {
        Group {
            switch route {
            case .weighIn:        WeighInSheet()
            case .plusMenu:       PlusMenuSheet()
            default:              ProfileSheet(route: route)
            }
        }
        // F1 · D · a sheet never passes 78% of the screen, and the screen underneath always
        // keeps its title and at least one row of value. Each route asks for only the height
        // its own content needs.
        .presentationDetents([.height(SheetChrome.height(for: route))])
        .presentationDragIndicator(.visible)
        .presentationBackground(NB.carbon2)
        .presentationCornerRadius(NB.R.panel)
    }
}

/// F1 · D — a sheet never exceeds 78% of the screen, and the screen behind it always
/// keeps showing its title and at least one row of value.
enum SheetChrome {
    static let maxHeight: CGFloat = 844 * 0.78

    static func height(for route: SheetRoute) -> CGFloat {
        switch route {
        case .plusMenu:                     return 430   // 06 · two groups, five rows
        case .weighIn:                      return 500   // 10S · the keypad, and no more
        case .signOut:                      return 360
        // 11's delete sheet has room for the sentence that counts out what is lost *and*
        // the line that says nothing was deleted when the endpoint cannot be reached.
        // At 360 the two together clipped the sentence to "…14 nights you…".
        case .deleteAccount:                return 400
        case .language, .appleHealth:       return 400
        case .export:                       return 440
        case .goal, .notifications, .units: return 480
        default:                            return maxHeight
        }
    }
}
