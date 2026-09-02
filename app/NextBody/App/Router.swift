import SwiftUI

/// F1 · The Map. Four kinds of surface and no fifth.
///  A · GATE      — a straight line walked once per account
///  B · THE ROOT  — Home, the only root
///  C · FROM THE ROOT · 5 — full pages, never nested, back always returns to the root
///  D · ON TOP    — takeovers and sheets; closing one restores the same scroll position
enum Destination: Hashable {
    case training
    case fuel
    /// 09 edge 5 · a closed day, reached from THIS WEEK or from 10's EDIT THIS DAY.
    case fuelDay(UserDay)
    case bodyBattery
    case composition(date: Date?)
    case profile
    case device            // THE ONLY SECOND LEVEL, reached from profile
    case deviceAlarms      // second-level-of-second-level, see F6 dead-control ruling
    case deviceAutoMonitor
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
        default:            return nil
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
    case bandAlarm, bandAutoMonitor, findBand, unbind, firmware
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

    /// F0 rule 06: every widget on the panel is tappable and declares its target page.
    func open(_ d: Destination, from: EntryPoint = .home) {
        entry = from
        path.append(d)
    }

    /// All detail pages return to the root — not to the previous screen, not to a scroll position.
    func backToRoot() { path.removeAll() }

    func back() { if !path.isEmpty { path.removeLast() } }
}
