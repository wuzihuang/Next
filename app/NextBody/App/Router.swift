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
    /// 04 · one of page two's instruments, opened from its own card. One case, not
    /// eight: the board draws them against a single anatomy. `.hrv` is a deep-link alias
    /// for sleep.
    case vitals(VitalsMetric)
    case composition(date: Date?)
    case profile
    case device            // THE ONLY SECOND LEVEL, reached from profile
    case deviceAutoMonitor
    /// Plus menu · Sport Mode. Pick one of the catalogued modes and open it on the band.
    case sportMode
    /// 05B · dedicated full-screen chat exploration interface
    case chat(sessionID: String? = nil, initialQuery: String? = nil, attachmentDataURL: String? = nil)
}

extension Destination {
    /// F0 rule 06 · the five values `TARGETS` allows on the wire. `device` and the two
    /// device sheets are deliberately absent: they are reachable only from profile, and a
    /// model that could name them could jump the one second level this product has.
    init?(envelopeTarget raw: String) {
        switch raw {
        case "training":    self = .training
        case "fuel":        self = .fuel
        case "bodyBattery": self = .bodyBattery
        case "composition": self = .composition(date: nil)
        case "profile":     self = .profile
        case "chat":        self = .chat()
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

/// Bottom sheets · 13 of them. The screen underneath always shows its title and one row of value.
enum SheetRoute: Hashable, Identifiable {
    // 03 · onboarding
    case height, weightBaseline, birthday
    // 10S
    case weighIn
    // 11 · profile
    case profileEdit, goal, units, notifications, appleHealth, language, about, privacy, export, deleteAccount, signOut
    // 12S · device
    case bandAutoMonitor, findBand, unbind, disconnect, firmware, syncCadence
    // dock
    case plusMenu
    var id: String { String(describing: self) }
}

@MainActor
final class Router: ObservableObject {
    @Published var path: [Destination] = []
    @Published var entry: EntryPoint = .home
    @Published var takeover: Takeover?
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
    /// Taken the moment the root is left. Every dismiss path restores this, so a stray
    /// mutation while a detail is up cannot strand the user on the wrong home page.
    private var homePageOnLeave = 0

    /// F0 rule 06: every widget on the panel is tappable and declares its target page.
    func open(_ d: Destination, from: EntryPoint = .home) {
        // Snapshot once when leaving the root; nested pushes (profile → device) keep it.
        if path.isEmpty { homePageOnLeave = homePage }
        entry = from
        var dest = d
        if case .vitals(.hrv) = dest { dest = .vitals(.sleep) }
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
}
