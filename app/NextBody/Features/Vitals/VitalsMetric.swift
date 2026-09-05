import SwiftUI

/// 04 · page-two instruments plus a deep-link alias. Page two shows eight cards; `.hrv`
/// is kept so `vitals.hrv` still parses, and the router sends it to the sleep page.
///
/// ⚠️ The tint is the home card's tint, not the board's swatch. The overview board draws
/// several of the eight in cyan; 04B gives each card its own colour and F0 rule 01 has one
/// concept carrying one name and one accent. A card that turns from lime to cyan as it opens
/// reads as a different object, which is the one thing a tap-through must not do.
enum VitalsMetric: String, Hashable, CaseIterable {
    case heart, sleep, hrv, response, stress, temp, steps, distance, active

    /// What `DetailScroll` prints — the card's own name (`‹ HEART`), never a
    /// `VITALS ·` section prefix. The second level is the instrument, not the page.
    var title: String {
        switch self {
        case .distance: L("DISTANCE")
        case .active:   L("ACTIVE ENERGY")
        default:        L(shortName)
        }
    }

    /// The card's label on page two, which is also the board's nav word.
    var shortName: String {
        switch self {
        case .heart:    "HEART"
        case .sleep:    "SLEEP"
        case .hrv:      "HRV"
        case .response: "RESPONSE"
        case .stress:   "STRESS"
        case .temp:     "TEMP"
        case .steps:    "STEPS"
        case .distance: "DIST"
        case .active:   "CALS"
        }
    }

    /// The key `VitalsPage.cardStates` files this instrument under, so an analytics event
    /// from the page and one from the card are joinable.
    var cardKey: String {
        switch self {
        case .distance: "DISTANCE"
        case .active:   "ACTIVE"
        default:        shortName
        }
    }

    var tint: Color {
        switch self {
        case .heart:    NB.lime1
        case .sleep:    NB.violet1
        case .hrv:      NB.blue1
        case .response: NB.compareAmber
        case .stress:   NB.ember1
        case .temp:     NB.cyan1
        case .steps:    NB.optimal2
        case .distance: NB.violetPink
        case .active:   NB.run1
        }
    }

    /// The board's hero eyebrow: what the number was measured by, not what it means.
    var sensor: String {
        switch self {
        case .heart:    L("OPTICAL PPG SENSOR")
        case .sleep:    L("OVERNIGHT STAGING")
        case .hrv:      L("RMSSD AUTONOMIC TONE")
        case .response: L("WRIST OPTICAL MEAL RESPONSE")
        case .stress:   L("PHYSIOLOGICAL STRAIN")
        case .temp:     L("SKIN BASELINE OFFSET")
        case .steps:    L("DAILY CADENCE ACCUMULATED")
        case .distance: L("SPATIAL DISPLACEMENT")
        case .active:   L("DAILY METABOLIC BURN")
        }
    }

    /// The board's chart-card head, and the note at its right — the fixed ruler the curve is
    /// drawn against, named so a flat line cannot be mistaken for a rescaled one.
    var chartTitle: String {
        switch self {
        case .heart:    L("LAST 24H TELEMETRY")
        case .sleep:    L("STAGES HYPNOGRAM")
        case .hrv:      L("LAST 24H RMSSD SCATTER")
        case .response: L("LAST 24H FOOD RESPONSE POINTS")
        case .stress:   L("LAST 24H AUTONOMIC LOAD")
        case .temp:     L("LAST 24H BASELINE DEVIATION")
        case .steps:    L("TODAY'S CADENCE HISTOGRAM")
        case .distance: L("TODAY'S DISTANCE CLIMB")
        case .active:   L("TODAY'S METABOLIC BURN")
        }
    }

    /// Trace values need enough context to expose gaps and trends. Accumulated values keep
    /// the product's 04:00 user-day boundary so their totals and their charts describe the
    /// same ledger. Sleep alone belongs to one completed night.
    var timeline: VitalsTimelineKind {
        switch self {
        case .sleep:
            .lastNight
        case .heart, .hrv, .response, .stress, .temp:
            .rolling24Hours
        case .steps, .distance, .active:
            .userDayToNow
        }
    }

    var periodLabel: String {
        switch timeline {
        case .lastNight:
            L("LAST NIGHT")
        case .rolling24Hours:
            L("LAST 24H")
        case .userDayToNow:
            L("TODAY · 04→NOW")
        }
    }

    var isNightly: Bool {
        timeline == .lastNight
    }
}

enum VitalsTimelineKind {
    case lastNight
    case rolling24Hours
    case userDayToNow
}
