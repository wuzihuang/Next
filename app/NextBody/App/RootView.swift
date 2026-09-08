import SwiftUI
import os

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: Router
    @ObservedObject private var phoneTools = PhoneToolRunner.shared

    var body: some View {
        let confirmation = phoneTools.confirmation
        return ZStack {
            switch session.stage {
            case .gateSignIn:     SignInFlow()
            case .gateConnect:    ConnectFlow()
            case .gateOnboarding: OnboardingFlow()
            case .root:           rootStack
            }

            if session.holdingLaunchStill {
                LaunchMark()
            }
        }
        .statusBarHidden(session.holdingLaunchStill)
        .carbonPage()
        // 05 · A · the keyboard is the dock's business alone; the page never shrinks for it.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // F5 C11 · 「maxFontSizeMultiplier = 1.35，允许到 xLarge；再大冻结在 1.35」. Fixed-pixel layouts
        // are the honest compromise the board names: the largest accessibility sizes are not
        // pretended to, but nothing clips at any size that is honoured.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .fullScreenCover(item: $router.takeover) { t in
            TakeoverHost(takeover: t, generation: router.takeoverGeneration, phoneExecution: phoneTools.measurementExecution)
        }
        .sheet(item: $router.sheet) { s in
            SheetHost(route: s)
        }
        // ADR 0018 · a phone tool with a side effect asks here, wherever the turn started.
        // ⚠️ The legacy `.alert(item:) { Alert(...) }` form re-wrapped the navigation bar and
        // UIKit aborted at launch ("nest wrapped navigation controllers"); this form does not.
        .alert(confirmation?.title ?? "",
               isPresented: Binding(get: { confirmation != nil },
                                    set: { if !$0, let confirmation {
                                        phoneTools.resolveConfirmation(id: confirmation.id, approved: false)
                                    } }),
               presenting: confirmation) { c in
            Button(L("CONFIRM ACTION")) { phoneTools.resolveConfirmation(id: c.id, approved: true) }
            Button(L("CANCEL"), role: .cancel) { phoneTools.resolveConfirmation(id: c.id, approved: false) }
        } message: { c in
            Text(c.detail)
        }
        .onAppear { phoneTools.router = router }
    }

    #if DEBUG
    /// 走查用的落点。`device` / `battery` / `measurements` 不是 envelope target——模型不该
    /// 跳到二级页——但走查需要一个能直接落上去的口子。
    /// ⚠️ 必须留在 body 之外：这几个分支写进 `.onAppear` 的表达式链里，整个 body 的类型
    /// 推断会当场超时。
    private static func debugDestination(_ raw: String) -> Destination? {
        if let target = Destination(envelopeTarget: raw) { return target }
        switch raw {
        case "device":               return .device
        case "deviceAutoMonitor", "autoMonitor": return .deviceAutoMonitor
        case "battery":              return .battery
        case "measurements":         return .measurements
        case "sportMode", "sport":   return .sportMode
        case "aiMemory", "memory":   return .aiMemory
        case "fuelDay":
            return .fuelDay(UserDay.containing(Date()).adding(days: -1))
        default:                     return nil
        }
    }

    /// 走查用：最近那条记录的 sheet 路由。放在 body 之外，见调用处的注释。
    private static func debugMeasurementSheet() -> SheetRoute? {
        guard let first = DataStore.shared.measurements.first else { return nil }
        return .measurement(first.id)
    }
    #endif

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
                    // ADR 0010 · 第二个二级页。返回回「我的」，不回首页。
                    case .measurements:           MeasurementsView()
                    // 04 · one of page two's vitals boards, opened from its own card.
                    case .vitals(let metric):     VitalsDetailView(metric: metric)
                    case .device:                 DeviceView()
                    case .battery:                BatteryTrendView()
                    // F1 · D — automatic measurement is a debug sheet on the device page,
                    // not a third-level page.
                    case .deviceAutoMonitor:      DeviceView()
                    case .sportMode:             SportModeView()
                    case .chat(let sessionID, let initialQuery, let attachmentDataURL):
                        ChatDetailView(sessionID: sessionID, initialQuery: initialQuery, initialAttachmentDataURL: attachmentDataURL)
                    case .planFace:               HomeView()
                    case .aiMemory:               AIMemoryView()
                    }
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Returning accounts skip onboarding. A changed consent version must still
            // show its delta before readiness can resume collecting from the bound band.
            // Seed-only previews have no saved decision to migrate.
            guard !ConsentStore.shared.decided,
                  !Band.allowsSeed || UserDefaults.standard.dictionary(forKey: "nb.consent") != nil,
                  router.takeover == nil, router.sheet == nil else { return }
            router.takeover = .consent
        }
        // Any path clear — chevron, edge swipe, or a binding write — restores the home
        // pager page that was showing when the root was left.
        .onChange(of: router.path) { was, now in
            if !was.isEmpty && now.isEmpty { router.restoreHomePageIfRoot() }
            if !now.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !router.path.isEmpty { router.debugRouteDidLand = true }
                }
            }
        }
        #if DEBUG
        // `SIMCTL_CHILD_NB_DEBUG_ROUTE=composition` opens straight onto a detail page for a walk.
        .onAppear {
            os.Logger(subsystem: "com.nextbody.hoop", category: "debug")
                .notice("root appeared, NB_DEBUG_ROUTE=\(ProcessInfo.processInfo.environment["NB_DEBUG_ROUTE"] ?? "nil", privacy: .public) path=\(router.path.count)")
            if let r = ProcessInfo.processInfo.environment["NB_DEBUG_ROUTE"],
               let d = Self.debugDestination(r), router.path.isEmpty {
                // A push landing while the stack is still settling is dropped on a device,
                // so it is retried until it sticks.
                for delay in [1.5, 3.5, 6.0, 9.0, 12.0, 18.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if router.path.isEmpty && !router.debugRouteDidLand {
                            router.open(d, from: .home)
                        }
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
                case "export":           .export
                case "deleteAccount":    .deleteAccount
                case "privacy":          .privacy
                case "about":            .about
                case "language":         .language
                case "units":            .units
                case "plusMenu":         .plusMenu
                case "weighIn":          .weighIn
                case "profileEdit":      .profileEdit
                case "goal":             .goal
                case "notifications":    .notifications
                case "appleHealth":      .appleHealth
                case "signOut":          .signOut
                case "height":           .height
                case "weightBaseline":   .weightBaseline
                case "birthday":         .birthday
                case "findBand":         .findBand
                case "unbind":           .unbind
                case "disconnect":       .disconnect
                case "firmware":         .firmware
                case "syncCadence":      .syncCadence
                case "bandAutoMonitor":  .bandAutoMonitor
                case "findHoop":         .findHoop
                case "bandAlarms":       .bandAlarms
                default:                 nil
                }
                if let sheet {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { router.sheet = sheet }
                }
                // 一条记录的 sheet 要一个 id，走查时取最近那条。⚠️ id 必须在派发之后再取：
                // 模拟器先摆种子、随后服务器的真数据整个换掉这个数组，4 秒时抓到的那个 id
                // 到了 sheet 里已经不存在了。
                if s == "measurement" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                        if let route = Self.debugMeasurementSheet() { router.sheet = route }
                    }
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
                case "consent":  .consent
                case "notify":   .notificationPrimer
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
    let generation: UInt
    let phoneExecution: PhoneToolExecution.Execution?
    @EnvironmentObject private var router: Router

    var body: some View {
        switch takeover {
        case .wordmark:
            WordmarkAnimation(onFinish: { router.takeover = nil })
        case .measure(let kind):
            MeasureTakeover(kind: kind, phoneExecution: phoneExecution) {
                if router.takeoverGeneration == generation { router.takeover = nil }
            }
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
            case .measurement(let id): MeasurementSheet(id: id)
            case .findHoop:       FindHoopSheet()
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
        // ADR 0010 · 身体扫描要装下 14 个字段，平衡检查只有一个结论词加三个小数。两种记录
        // 高度差得远，所以按内容给，不共用一个数。
        case .measurement:                  return 620
        case .export:                       return 440
        case .goal, .notifications, .units: return 480
        default:                            return maxHeight
        }
    }
}
