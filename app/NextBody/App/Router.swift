import SwiftUI

/// F1 · The Map. Four kinds of surface and no fifth.
///  A · GATE      — a straight line walked once per account
///  B · THE ROOT  — Home, the only root
///  C · FROM THE ROOT · 5 — full pages, never nested, back always returns to the root
///  D · ON TOP    — takeovers and sheets; closing one restores the same scroll position
enum Destination: Hashable {
    case training
    case fuel
    /// 09 edge 5 · a closed day, reached from THIS WEEK's day labels.
    case fuelDay(UserDay)
    case bodyBattery
    /// 04 · one of page two's vitals boards, opened from its own card. One case, not
    /// seven: the board draws them against a single anatomy. `.hrv` is a deep-link alias
    /// for sleep. Body Battery is `.bodyBattery`, not a vitals metric.
    case vitals(VitalsMetric)
    case composition(date: Date?)
    case profile
    /// ADR 0010 · 主动测量记录的清单。从「我的」那块 MEASUREMENTS 进，返回回「我的」。
    /// 它和 `device` 是仅有的两个二级页——一份按月累积的清单一屏放不下，这是 F1 允许做成
    /// 页面的门槛。深链不落到它。
    case measurements
    case device            // reached from profile or the home battery pip
    case battery           // trend behind the device ring
    case deviceAutoMonitor
    /// Plus menu · Sport Mode. Pick one of the catalogued modes and open it on the band.
    case sportMode
    /// 05B · dedicated full-screen chat exploration interface
    case chat(sessionID: String? = nil, initialQuery: String? = nil, attachmentDataURL: String? = nil)
    /// ADR 0018 · the plan face. Not a page: `open` turns it into a request Home answers by
    /// sliding the face up, so a plan frame anywhere can land on the plan.
    case planFace
    /// ADR 0018 · what the AI remembers about this person. Reached from profile; never on the wire.
    case aiMemory
}

extension Destination {
    /// F0 rule 06 · the five values `TARGETS` allows on the wire. `device`, `measurements`
    /// and the device sheets are deliberately absent: they are reachable only from profile,
    /// and a model that could name them could jump straight to a second level.
    init?(envelopeTarget raw: String) {
        switch raw {
        case "training":    self = .training
        case "fuel":        self = .fuel
        case "bodyBattery": self = .bodyBattery
        case "composition": self = .composition(date: nil)
        case "profile":     self = .profile
        case "chat":        self = .chat()
        case "plan":        self = .planFace
        // 04's eight are addressable by name: `vitals.heart`, `vitals.sleep`. They are
        // pages the model may legitimately point at — unlike `device`, which stays absent.
        default:
            guard raw.hasPrefix("vitals.") else { return nil }
            let name = String(raw.dropFirst("vitals.".count))
            // Night HRV lives on the sleep page. An old envelope that still names
            // `vitals.hrv` must land there rather than on a card that no longer exists.
            if name == "hrv" { self = .vitals(.sleep); return }
            guard let metric = VitalsMetric(rawValue: name) else { return nil }
            self = .vitals(metric)
        }
    }
}

/// Where a detail page was entered from. One layer only — no multi-level history stack.
enum EntryPoint: Hashable { case home, profile }

/// Full-screen takeovers. Not pages: the panel on Home grown to full size.
enum Takeover: Hashable, Identifiable {
    case wordmark                  // 2.6s brand animation, no close mark
    case measure(MeasureKind)
    case consent                   // 补屏 A · from NOT COLLECTING or Settings › Data
    case notificationPrimer        // F5 C4 · before the one system dialog, after the first real morning
    var id: String { String(describing: self) }
}

enum MeasureKind: String, Hashable, CaseIterable {
    case heartRate, bloodOxygen, bloodPressure, ecg, temperature, bodyComposition
}

/// Bottom sheets. The screen underneath always shows its title and one row of value.
enum SheetRoute: Hashable, Identifiable {
    // 03 · onboarding
    case height, weightBaseline, birthday
    // 10S
    case weighIn
    // 11 · profile
    case profileEdit, goal, units, notifications, appleHealth, language, about, privacy, deleteAccount, signOut
    /// Profile › REPORT A PROBLEM · title, words, screenshots → one GitHub issue.
    case feedback
    /// ADR 0010 · 一条测量记录的全部字段。两个详情页之间没有路，所以清单里的行点开是盖在
    /// 清单上的 sheet，不是第三级页面，关掉回到同一滚动位置。
    case measurement(UUID)
    // 12S · device
    case bandAutoMonitor, findBand, unbind, disconnect, firmware, syncCadence
    /// 9-0 A·S1–S6 · give the second HOOP its slot (docs/plans/2026-09-12-dual-device-continuity.md).
    case activateSecond
    /// 9-0 A·S8 · one tap on the other HOOP's card. There are only two, so the tap is the
    /// choice and the sheet only confirms. The payload is the slot being switched to.
    case wearSwitch(String)
    /// The `Counted from …` line: the wearer pins a different start by hand. Not the
    /// switching path — the app works the start out from the band's own evidence.
    case wearCorrect
    /// Choose one HOOP to remove; the other binding and account history stay.
    case releaseSet
    /// 12Y · find the wrist (LED). Not `.findBand`.
    case findHoop
    /// 12Y · new-alarm table (SWITCH).
    case bandAlarms
    /// 12S · the light on the side. DEBUG only — it lives in the Device page's debug card,
    /// not as a page of its own. A choice here is written to the band on every connect.
    case healthLight
    // dock
    case plusMenu
    var id: String { String(describing: self) }
}

@MainActor
final class Router: ObservableObject {
    @Published var path: [Destination] = [] {
        didSet {
            if returnBackdrops.count > path.count {
                returnBackdrops.removeSubrange(path.count...)
            }
            NotificationReach.currentPage = notifyPage
        }
    }

    /// ADR 0019 · which deep-link page is already open, for swallow.
    var notifyPage: NotifyPage {
        switch path.last {
        case .fuel, .fuelDay: return .fuel
        case .training: return .training
        case .device: return .device
        case .bodyBattery: return .bodyBattery
        default: return .other
        }
    }
    /// In-memory only: capture the exact parent before a push, including its scroll
    /// position. A popped route immediately releases its stack-owned image.
    private var returnBackdrops: [UIImage?] = []
    var returnBackdrop: UIImage? { returnBackdrops.last ?? nil }

    private func captureReturnBackdrop() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        format.opaque = true
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return drawn ? image : nil
    }
    @Published var entry: EntryPoint = .home
    private(set) var takeoverGeneration: UInt = 0
    @Published var takeover: Takeover? { didSet { takeoverGeneration &+= 1 } }
    @Published var sheet: SheetRoute?
    /// 09 edge 5 · ADD TO THAT DAY: back-logging goes through the dock, prefilled with the
    /// day, and the meal lands on that day rather than today.
    struct DockPrefill: Equatable { let text: String; let day: UserDay }
    @Published var dockPrefill: DockPrefill?
    /// 06 rule 09 · the measuring screen folds its result back onto the panel as one widget.
    @Published var measuredWidget: PanelWidget?
    /// 04B · which home pager page is showing. 0 = panel + strip, 1 = vitals. Lives on the
    /// router (not on `HomeView` `@State`) so a NavigationStack push/pop cannot wipe it —
    /// pager page the user left. Page two's cards must return to those cards, not bounce
    @Published var homePage = 0
    /// docs/plans/2026-09-09-ai-tool-surface.md · `do app.open {window}`: the detail page
    /// that is showing switches its DAY / WEEK / MONTH pills and clears the request.
    @Published var windowRequest: RollingPills?
    /// The device page owns its own sheets (alarms, auto-measure, cadence…); a voice
    /// `app.open {sheet}` asks it to lift one once it is on screen.
    @Published var deviceSheetRequest: SheetRoute?
    /// ADR 0018 · bumped when something asks for the plan face; Home observes it.
    @Published private(set) var planRequest = 0
    func requestPlan() {
        if !path.isEmpty { backToRoot() }
        planRequest += 1
    }
    /// Taken the moment the root is left. Every dismiss path restores this, so a stray
    /// mutation while a detail is up cannot strand the user on the wrong home page.
    private var homePageOnLeave = 0
    /// DEBUG `NB_DEBUG_ROUTE` retries until a destination actually sits on the stack.
    /// Once it has, later empties are real pops — do not push the page back.
    var debugRouteDidLand = false
    /// F1 · a notification tap while measuring waits here until the takeover folds.
    private var queuedLink: NotificationDeepLink?
    /// F1 · `nextbody://home?panel=body_battery` — Home puts 昨夜 on the panel.
    @Published var pendingHomePanel: String?
    /// ADR 0019 · `nextbody://fuel?slot=` lands on Fuel; the slot is for the page to read.
    @Published var pendingFuelSlot: String?

    /// F0 rule 06: every widget on the panel is tappable and declares its target page.
    func open(_ d: Destination, from: EntryPoint = .home) {
        if case .planFace = d { requestPlan(); return }
        // Snapshot once when leaving the root; nested pushes (profile → device) keep it.
        if path.isEmpty { homePageOnLeave = homePage }
        entry = from
        var dest = d
        if case .vitals(.hrv) = dest { dest = .vitals(.sleep) }
        returnBackdrops.append(captureReturnBackdrop())
        path.append(dest)
    }

    /// All detail pages return to the root — not to a nested previous screen. The home
    /// pager page is restored so leaving a vitals board lands back on page two.
    func backToRoot() {
        path.removeAll()
        homePage = homePageOnLeave
    }

    func back() {
        guard !path.isEmpty else { return }
        path.removeLast()
        if path.isEmpty { homePage = homePageOnLeave }
    }

    /// Safety net for any path clear that did not go through `backToRoot` / `back`.
    func restoreHomePageIfRoot() {
        guard path.isEmpty else { return }
        homePage = homePageOnLeave
    }

    /// F1 Sec 03 · a tap on a notification. Measuring queues it; anything else lands now.
    func receive(_ link: NotificationDeepLink) {
        if case .measure = takeover {
            queuedLink = link
            return
        }
        apply(link)
    }

    func flushQueuedLink() {
        guard takeover == nil, let link = queuedLink else { return }
        queuedLink = nil
        apply(link)
    }

    func apply(_ link: NotificationDeepLink) {
        switch link {
        case .homePanel:
            if !path.isEmpty { backToRoot() }
            homePage = 0
            pendingHomePanel = "body_battery"
        case .home:
            if !path.isEmpty { backToRoot() }
            homePage = 0
            pendingHomePanel = nil
        case .fuel(let slot):
            pendingFuelSlot = slot
            open(.fuel)
        case .training:
            open(.training)
        case .device:
            if path.isEmpty { homePageOnLeave = homePage }
            entry = .profile
            returnBackdrops.append(captureReturnBackdrop())
            path = [.profile, .device]
        case .composition(let raw):
            let day = raw.flatMap { s -> Date? in
                let f = DateFormatter()
                f.calendar = Calendar(identifier: .gregorian)
                f.dateFormat = "yyyy-MM-dd"
                return f.date(from: s)
            }
            open(.composition(date: day))
        case .logPhoto:
            break
        }
    }
}
