import SwiftUI

/// 04 · 05 这条带 The Strip. 358 × 136, two 174-wide cards, gap 10, order written in stone:
/// TRAINING left, CALORIES right — the causal order of a day, burn before refuel.
/// The whole card is the tap target; there is no second-level button inside it.
struct BottomStrip: View {
    let m: DailyMetrics
    var width: CGFloat = NB.Layout.contentWidth
    let onTraining: () -> Void
    let onFuel: () -> Void

    var body: some View {
        HStack(spacing: NB.Layout.cardGap) {
            // ADR-0001 · the card is a hot zone: it fires on a tap and never on a touch
            // that travelled (HotZoneTap), so a page drag that starts here turns the page.
            Button(action: onTraining) { TrainingCard(m: m) }
                .buttonStyle(HotZoneTap())
            Button(action: onFuel) { FuelCard(m: m) }
                .buttonStyle(HotZoneTap())
        }
        .frame(width: width, height: NB.Layout.stripHeight)
    }
}

struct TrainingCard: View {
    let m: DailyMetrics

    private var toGo: String {
        guard let t = m.targetLoad, let l = m.trainingLoad else { return L("NO TARGET") }
        return L("%.1f TO GO", max(0, t - l))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(MetricNames.training)
                    .font(NBFont.ui(500, 11)).tracking(0.14 * 11)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
                Text(toGo)
                    .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
                    .foregroundStyle(m.targetLoad == nil ? NB.text3Prod : NB.cyanPale)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                TrainingRing(load: m.trainingLoad, target: m.targetLoad, zone: m.optimalZone)
                VStack(alignment: .leading, spacing: 9) {
                    if m.targetLoad == nil {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("TARGET")).font(NBFont.ui(500, 11)).tracking(0.06 * 11)
                                .foregroundStyle(NB.text3Prod)
                            Text(L("NOT SET")).font(NBFont.ui(600, 12)).foregroundStyle(NB.text1)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("FULL RING")).font(NBFont.ui(500, 11)).tracking(0.06 * 11)
                                .foregroundStyle(NB.text3Prod)
                            Text(L("21.0")).font(NBFont.dot(700, 14)).tracking(0.02 * 14)
                                .foregroundStyle(NB.text3Prod)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("SUGGESTED")).font(NBFont.ui(500, 11)).tracking(0.06 * 11)
                                .foregroundStyle(NB.text3Prod)
                            Text(L("STRENGTH")).font(NBFont.ui(600, 12)).foregroundStyle(NB.text1)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("TARGET")).font(NBFont.ui(500, 11)).tracking(0.06 * 11)
                                .foregroundStyle(NB.text3Prod)
                            Text(Fmt.load(m.targetLoad)).font(NBFont.dot(700, 14)).tracking(0.02 * 14)
                                .foregroundStyle(NB.cyanPale)
                        }
                    }
                }
                .fixedSize()
            }
        }
        .padding(12)
        .frame(width: NB.Layout.cardWidth, height: NB.Layout.stripHeight, alignment: .topLeading)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous).stroke(NB.hairline, lineWidth: 1))
    }
}

struct FuelCard: View {
    let m: DailyMetrics

    private var headline: String {
        guard let next = m.nextMeal else { return unloggedHead }
        return L("%@ LEFT", Fmt.kcal(next))
    }
    private var unloggedHead: String {
        if case .unlogged = m.fuelState { return L("UNLOGGED") }
        return Fmt.dash
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(MetricNames.calories)
                        .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                        .foregroundStyle(NB.text3Prod)
                    Spacer(minLength: 0)
                    Text(headline)
                        .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
                        .foregroundStyle(m.nextMeal == nil ? NB.text3Prod : NB.emberPale)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Fmt.kcal(m.eIn))
                        .font(NBFont.dot(700, 26)).tracking(-0.02 * 26)
                        .foregroundStyle(m.eIn == nil ? NB.text3Prod : NB.ember1)
                    Text("/\(Fmt.kcal(m.targetIn))")
                        .font(NBFont.dot(500, 11))
                        .foregroundStyle(NB.macroValue)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                MacroBar(label: L("PRO"),  eaten: m.protein?.eaten, target: m.protein?.target, tint: NB.violet1)
                MacroBar(label: L("CARB"), eaten: m.carb?.eaten,    target: m.carb?.target,    tint: NB.optimal2)
                MacroBar(label: L("FAT"),  eaten: m.fat?.eaten,     target: m.fat?.target,     tint: NB.run1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: NB.Layout.stripHeight)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous).stroke(NB.hairline, lineWidth: 1))
    }
}

/// Three independent bars, 4px tall, each capped at its own target.
/// They are never merged into one total progress bar — that would answer a different question.
struct MacroBar: View {
    let label: String
    let eaten: Int?
    let target: Int?
    let tint: Color

    private var fraction: Double {
        guard let e = eaten, let t = target, t > 0, e > 0 else { return 0 }
        return min(1, Double(e) / Double(t))
    }
    /// 09 · B2 · in the empty state the three bars are complete: —/145, —/195, —/60.
    /// The numerator is blank and the denominator is already there — that is the line
    /// between "no answer yet" and "broken".
    private var value: String {
        guard let t = target else { return Fmt.dash }
        guard let e = eaten, e > 0 else { return "—/\(t)" }
        return "\(e)/\(t)"
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(NBFont.ui(500, 11)).tracking(0.02 * 11)
                .foregroundStyle(NB.macroLabel)
                .frame(width: 32, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(NB.barTrack)
                    Capsule().fill(tint).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.78)   // F5 C11 · the card is a fixed 174; at xLarge the number gives a little rather than clip
                .font(NBFont.dot(500, 11))
                .foregroundStyle(NB.macroValue)
                .frame(width: 48, alignment: .trailing)
        }
    }
}
