import SwiftUI

/// 06 · THREE WAYS TO LAY OUT THE BALANCE CHECK, so they can be compared on the wrist rather
/// than argued about as pictures. All three carry the same facts and the same field; what
/// differs is where the key numbers sit and how much of the screen the type claims.
///
/// `SIMCTL_CHILD_NB_DEBUG_BALANCE_STYLE=header|dashboard|monolith` (or `DEVICECTL_CHILD_…`
/// on the phone) picks one. Absent, the screen keeps the layout it shipped with.
///
/// ⚠️ Not one of them invents a number. Every value on every variant is either the band's own
/// count, a rate that was measured, or a word describing a state — the same rule the rest of
/// this screen follows, applied three ways.
enum BalanceLayout: String, CaseIterable {
    /// What the screen has now: instruction on top, field through the middle, count low.
    case original
    /// The key data pulled to the top as a masthead — rate large, the run's own clock beside
    /// it, the field taking everything underneath.
    case header
    /// An instrument row: three labelled cells across the top, hairline under them, field
    /// below. The most information, the least drama.
    case dashboard
    /// One enormous rate, the field behind it, and nothing else until the foot. The least
    /// information, the most presence.
    case monolith

    /// `monolith` is the chosen one. The other three stay reachable behind the launch flag
    /// while the layout is still being argued about on the wrist; when it stops being
    /// argued about, they and this enum go.
    static var current: BalanceLayout {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["NB_DEBUG_BALANCE_STYLE"],
           let style = BalanceLayout(rawValue: raw) { return style }
        #endif
        return .monolith
    }
}

/// What the screen is doing, said once, at the foot of the monolith layout.
///
/// ⚠️ No full stop. Every other sentence in this product ends in one — this one sits directly
/// over the help line, and two stacked sentences both ending in a period read as a paragraph
/// that was broken in the wrong place. The strip is done here rather than by adding a second
/// copy of every headline to the string table, so a translator only ever writes the sentence
/// once and the layout decides how it is set.
struct BalanceFootLine: View {
    var headline: String
    var over: Bool

    var body: some View {
        Text(headline.trimmingCharacters(in: CharacterSet(charactersIn: "。.！!")))
            .font(NBFont.brand(500, 19)).tracking(-0.01 * 19)
            .multilineTextAlignment(.center)
            .foregroundStyle(NB.text1)
            .frame(width: 300)
            .modifier(OverFieldShadow(on: over))
    }
}

/// The masthead: the rate at the size of a headline, the clock beside it, one line of state.
struct BalanceHeader: View {
    var bpm: Int?
    var source: String
    var remaining: Int
    var total: Int
    var status: String
    var tint: Color
    var over: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                // ⚠️ A dash until a rate has been measured. The number is the loudest thing
                // on the screen, which is exactly why it may never be a placeholder.
                Text(bpm.map(String.init) ?? Fmt.dash)
                    .font(NBFont.dot(700, 72)).tracking(-0.03 * 72)
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                Text(L("BPM"))
                    .font(NBFont.dot(600, 13)).tracking(0.2 * 13)
                    .foregroundStyle(NB.white.opacity(0.45))
                Spacer(minLength: 0)
                Text(String(format: "00:%02d", max(0, remaining)))
                    .font(NBFont.dot(700, 30)).tracking(0.04 * 30)
                    .foregroundStyle(NB.white.opacity(0.85))
                    .contentTransition(.numericText(countsDown: true))
            }
            Text(source)
                .font(NBFont.dot(500, 9.5)).tracking(0.18 * 9.5)
                .foregroundStyle(NB.white.opacity(0.40))
                .padding(.top, 6)
            // The run drawn as one line rather than a ring: it is a fixed forty seconds, and
            // a line says "this far along" without pretending to be a dial.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(NB.white.opacity(0.12))
                    Rectangle().fill(tint.opacity(0.9))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 2)
            .padding(.top, 14)
            Text(status)
                .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.white.opacity(0.5))
                .padding(.top, 10)
        }
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .modifier(OverFieldShadow(on: over))
    }

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(total - remaining) / Double(total)))
    }
}

/// The instrument row: three cells, one hairline, nothing else.
struct BalanceDashboard: View {
    var bpm: Int?
    var remaining: Int
    var total: Int
    var contact: Bool
    var over: Bool
    var tint: Color

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                cell("RATE", bpm.map(String.init) ?? Fmt.dash, "BPM", tint)
                divider
                cell("LEFT", String(max(0, remaining)), "SEC", NB.white.opacity(0.9))
                divider
                // The wrist's own state, in a word. `contact` is the band's judgement, not
                // the app's guess at one.
                cell("CONTACT", contact ? "ON" : "OFF", contact ? "KEY" : "LIFT",
                     contact ? tint : NB.ember1)
            }
            Hairline().frame(width: NB.Layout.contentWidth)
        }
        .frame(width: NB.Layout.contentWidth)
        .modifier(OverFieldShadow(on: over))
    }

    private var divider: some View {
        Rectangle().fill(NB.white.opacity(0.12)).frame(width: 1, height: 34)
    }

    private func cell(_ label: String, _ value: String, _ unit: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            Text(label)
                .font(NBFont.dot(600, 9)).tracking(0.24 * 9)
                .foregroundStyle(NB.white.opacity(0.38))
            Text(value)
                .font(NBFont.dot(700, 30)).tracking(0.02 * 30)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(unit)
                .font(NBFont.dot(500, 9)).tracking(0.18 * 9)
                .foregroundStyle(NB.white.opacity(0.30))
        }
        .frame(maxWidth: .infinity)
    }
}

/// One number, as big as the column allows, with the field behind it.
///
/// The chosen layout. Everything the wearer needs for forty seconds sits in one centred
/// column — the rate, where it came from, how long is left, and what the screen is doing —
/// and nothing else competes with the field.
struct BalanceMonolith: View {
    var bpm: Int?
    var source: String
    var remaining: Int
    var tint: Color
    var over: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(bpm.map(String.init) ?? Fmt.dash)
                // 132 pt fills the 358 column with three digits and leaves the field
                // readable around it — the whole point of this variant is that the field is
                // not decoration behind a card, it is the ground the number stands on.
                .font(NBFont.dot(700, 132)).tracking(-0.045 * 132)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(source)
                .font(NBFont.dot(500, 10)).tracking(0.2 * 10)
                .foregroundStyle(NB.white.opacity(0.42))
                .padding(.top, 2)
            // ⚠️ 32 pt, not the 15 it started at. The countdown is the second thing anyone
            // looks at on this screen — "how much longer do I have to hold this" — and at
            // fifteen it read as a caption on the line above it.
            Text(String(format: "00:%02d", max(0, remaining)))
                .font(NBFont.dot(700, 32)).tracking(0.04 * 32)
                .foregroundStyle(NB.white.opacity(0.9))
                .contentTransition(.numericText(countsDown: true))
                .padding(.top, 26)
        }
        .frame(width: NB.Layout.contentWidth)
        .modifier(OverFieldShadow(on: over))
    }
}
