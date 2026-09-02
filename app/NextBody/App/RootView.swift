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
