import SwiftUI

/// 04 · page-two instruments plus a deep-link alias. Page two shows seven vitals cards
/// plus Body Battery; `.hrv` is kept so `vitals.hrv` still parses, and the router sends
/// it to the sleep page. `.response` still opens the meal-response board via deep link.
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
        // 偏红 · RMSSD is the pulse's own variability, so it wears a heart colour rather
        // than the blue it shared with REM and the skin-temp lows. ⚠️ The pale rose, not
        // `alert2`: a full alert red on a field of dots reads as a warning about the night
        // rather than as the instrument's own colour.
        case .hrv:      NB.alert1
        case .response: NB.compareAmber
        case .stress:   NB.ember1
        case .temp:     NB.cyan1
        case .steps:    NB.optimal2
        case .distance: NB.violetPink
        case .active:   NB.lime1
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
        case .temp:     L("WRIST SKIN TEMPERATURE")
        case .steps:    L("DAILY CADENCE ACCUMULATED")
        case .distance: L("SPATIAL DISPLACEMENT")
        case .active:   L("DAILY METABOLIC BURN")
        }
    }

    /// The board's chart-card head, and the note at its right — the fixed ruler the curve is
    /// drawn against, named so a flat line cannot be mistaken for a rescaled one.
    var chartTitle: String {
        switch self {
        case .heart:    L("TODAY'S TELEMETRY")
        case .sleep:    L("STAGES HYPNOGRAM")
        case .hrv:      L("TODAY'S RMSSD SCATTER")
        case .response: L("TODAY'S FOOD RESPONSE POINTS")
        case .stress:   L("TODAY'S AUTONOMIC LOAD")
        case .temp:     L("TODAY'S SKIN TEMPERATURE")
        case .steps:    L("TODAY'S CADENCE HISTOGRAM")
        case .distance: L("TODAY'S DISTANCE CLIMB")
        case .active:   L("TODAY'S METABOLIC BURN")
        }
    }

    /// True for the charts whose vertical ruler stands in a rail beside the field rather
    /// than being left unnamed inside it. The clock under those charts is inset by the
    /// rail's gutter; the scatters and the hypnogram still span the full card width.
    var chartHasScaleRail: Bool {
        switch self {
        case .heart, .stress, .temp, .steps, .distance:
            true
        case .sleep, .hrv, .response, .active:
            false
        }
    }

    /// Issue #19 · one day on every card. Traces used to draw a rolling 24 hours while
    /// accumulated values drew the user day, so two cards on the same screen answered
    /// "today" with two different windows and the trace cards carried yesterday's evening
    /// into this morning. They all draw local midnight → now. Sleep alone belongs to one
    /// completed night and keeps its own clock.
    var timeline: VitalsTimelineKind {
        switch self {
        case .sleep:
            .lastNight
        case .heart, .hrv, .response, .stress, .temp, .steps, .distance, .active:
            .userDayToNow
        }
    }

    var periodLabel: String {
        switch timeline {
        case .lastNight:
            L("LAST NIGHT")
        case .userDayToNow:
            L("TODAY")
        }
    }

    var isNightly: Bool {
        timeline == .lastNight
    }
}

enum VitalsTimelineKind {
    case lastNight
    /// Local midnight → now. The only day a card draws (issue #19).
    case userDayToNow
}

/// ADR 0008 · the score's four bands. Only the numeral is tinted — the SLEEP card keeps
/// `NB.violet1` for its label, its tag and its strip, because a card that changes colour
/// with last night's number reads as a different instrument each morning.
extension SleepScore {
    var tint: Color {
        switch score {
        case 80...:   NB.optimal2
        case 60..<80: NB.violet1
        case 40..<60: NB.compareAmber
        default:      NB.ember1
        }
    }
}
