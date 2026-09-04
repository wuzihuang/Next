import SwiftUI
import os

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
                    case .fuelDay(let d):         FuelDetailView(focus: d)
                    case .bodyBattery:            BodyBatteryDetailView()
                    case .composition(let date):  CompositionDetailView(focus: date)
                    case .profile:                ProfileView()
                    // 04 · one of page two's eight instruments, opened from its own card.
                    case .vitals(let metric):     VitalsDetailView(metric: metric)
                    case .device:                 DeviceView()
                    // F1 · D — automatic measurement is a sheet on the device page,
                    // not a third-level page.
                    case .deviceAutoMonitor:      DeviceView()
                    case .sportMode:             SportModeView()
                    case .chat(let sessionID, let initialQuery, let attachmentDataURL):
                        ChatDetailView(sessionID: sessionID, initialQuery: initialQuery, initialAttachmentDataURL: attachmentDataURL)
                    }
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Any path clear — chevron, edge swipe, or a binding write — restores the home
        // pager page that was showing when the root was left.
        .onChange(of: router.path) { was, now in
            if !was.isEmpty && now.isEmpty { router.restoreHomePageIfRoot() }
        }
        #if DEBUG
        // `SIMCTL_CHILD_NB_DEBUG_ROUTE=composition` opens straight onto a detail page for a walk.
        .onAppear {
            os.Logger(subsystem: "com.nextbody.hoop", category: "debug")
                .notice("root appeared, NB_DEBUG_ROUTE=\(ProcessInfo.processInfo.environment["NB_DEBUG_ROUTE"] ?? "nil", privacy: .public) path=\(router.path.count)")
            if let r = ProcessInfo.processInfo.environment["NB_DEBUG_ROUTE"],
               let d = Destination(envelopeTarget: r)
                ?? (r == "device" ? .device : nil)
                ?? (r == "sportMode" || r == "sport" ? .sportMode : nil),
               router.path.isEmpty {
                // A push landing while the stack is still settling is dropped on a device,
                // so it is retried until it sticks.
                for delay in [1.5, 3.5, 6.0, 9.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if router.path.isEmpty { router.open(d, from: .home) }
                    }
                }
            }
            // `SIMCTL_CHILD_NB_DEBUG_MEASURE=ecg` opens a measurement takeover straight
            // away — the plus menu is two taps no harness can make, and the ECG strip is
            // forty seconds of drawing that has to be watched to be checked.
            if let m = ProcessInfo.processInfo.environment["NB_DEBUG_MEASURE"],
               let kind = MeasureKind(rawValue: m) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    if router.takeover == nil { router.takeover = .measure(kind) }
                }
            }
            // `SIMCTL_CHILD_NB_DEBUG_SHEET=export` lifts one of profile's sheets on top of
            // whatever the route landed on, for a walk of a sheet that lives behind a tap.
            if let s = ProcessInfo.processInfo.environment["NB_DEBUG_SHEET"] {
                let sheet: SheetRoute? = switch s {
                case "export":        .export
                case "deleteAccount": .deleteAccount
                case "privacy":       .privacy
                case "about":         .about
                case "language":      .language
                case "units":         .units
                case "plusMenu":      .plusMenu
                case "weighIn":       .weighIn
                default:              nil
                }
                if let sheet {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { router.sheet = sheet }
                }
            }
            // `SIMCTL_CHILD_NB_DEBUG_TAKEOVER=wordmark` plays 02M's film on demand. In the
            // product it only ever runs once, on a first registration, so this is the one
            // way to watch it again without making another account. `bodyscan` and `battery`
            // open the two measurements that otherwise live behind the plus key, which no
            // harness can press.
            if let t = ProcessInfo.processInfo.environment["NB_DEBUG_TAKEOVER"] {
                let takeover: Takeover? = switch t {
                case "wordmark": .wordmark
                case "bodyscan": .measure(.bodyComposition)
                case "battery":  .measure(.heartRate)
                default:         nil
                }
                // The measurements wait for the link the home screen's task restores; the
                // film does not, and starting it late would be judging the presentation.
                if let takeover {
                    DispatchQueue.main.asyncAfter(deadline: .now() + (t == "wordmark" ? 0.5 : 2.5)) {
                        // Without this the cover slides up over ~0.4s and the film's power-on
                        // plays behind a moving sheet — an artifact of the harness that the real
                        // sign-in path does not have. The film has to start on a cut here too,
                        // or what is being judged is the presentation, not the animation.
                        var cut = Transaction()
                        cut.disablesAnimations = true
                        withTransaction(cut) { router.takeover = takeover }
                    }
                }
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
