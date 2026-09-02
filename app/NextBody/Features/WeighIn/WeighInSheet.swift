import SwiftUI
import UIKit

/// 10S · 称重录入 Add a weigh-in.
/// D06 struck the old "NOT IN V1": without a manual entry, anyone without a smart scale
/// could never unlock the composition call — the product's headline feature.
/// Reached from the composition detail's ADD A WEIGH-IN and from 11's BODY METRICS row —
/// both are about the same physical fact. Never from the dock.
struct WeighInSheet: View {
    @EnvironmentObject private var data: DataStore
    @Environment(\.dismiss) private var dismiss

    enum Mode: Hashable { case byHand, fromHealth }
    @State private var mode: Mode = .byHand
    @State private var typed = ""
    @State private var unit = "KG"

    /// Health's number may come from another scale, another person, or one mis-step,
    /// and it would flow all the way through to the macros and The Call — so it is confirmed,
    /// never adopted silently.
    ///
    /// ⚠️ Nil by default. It used to default to a literal (78.6, "TODAY 07:12"), so the
    /// sheet always opened claiming Health had a new weigh-in — on a build with no
    /// HealthKit entitlement at all, and over an account whose real last weight was 75.8.
    /// A prompt to confirm a number nobody measured is the worst thing this sheet can do.
    @State private var healthCandidate: (kg: Double, at: String)?

    var body: some View {
        Group {
            switch mode {
            case .byHand:     byHand
            case .fromHealth: fromHealth
            }
        }
        .background(NB.carbon2)
        .task {
            // Only a weigh-in newer than HOOP's own last one is worth confirming.
            if let w = await HealthService.shared.latestWeight(),
               w.at > (data.weighIns.first?.date ?? .distantPast) {
                let f = DateFormatter(); f.dateFormat = "HH:mm"
                let day = Calendar.current.isDateInToday(w.at) ? "TODAY" : Calendar.current.isDateInYesterday(w.at) ? "YESTERDAY" : f.string(from: w.at)
                healthCandidate = (w.kg, "\(day) \(f.string(from: w.at))")
                mode = .fromHealth
            }
        }
        .onAppear {
            // The keypad opens on what they weigh now, not on an empty field: most entries
            // are a small correction to the last one.
            if typed.isEmpty { typed = Fmt.kg(data.today.weightKg) }
        }
    }

    // MARK: 02 · 手填 By hand

    private var byHand: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add a weigh-in")
                    .font(NBFont.ui(500, 22)).tracking(0.01 * 22)
                    .foregroundStyle(NB.text1)
                // It stays in HOOP: we never write a hand-typed number back into Health.
                Text("Stays in HOOP. It never goes back to Health.")
                    .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                    .foregroundStyle(NB.white.opacity(0.38))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 22)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(typed.isEmpty ? "—" : typed)
                    .font(NBFont.brand(700, 54)).tracking(-0.045 * 54)
                    .foregroundStyle(outOfRange ? NB.ember1 : NB.text1)
                    .contentTransition(.numericText())
                Text(unit.lowercased())
                    .font(NBFont.ui(300, 16))
                    .foregroundStyle(NB.white.opacity(0.38))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            if outOfRange {
                VStack(spacing: 4) {
                    Text("OUT OF RANGE").font(NBFont.dot(600, 12)).tracking(0.22 * 12).foregroundStyle(NB.ember1.opacity(0.85))
                    Text(unit == "KG" ? "20–300 KG" : "44–661 LB").font(NBFont.brand(500, 13.5)).foregroundStyle(NB.white.opacity(0.70))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            } else if let earlier = todaysEarlier, let kg = parsed {
                VStack(spacing: 4) {
                    Text("ALREADY ONE TODAY").font(NBFont.dot(600, 12)).tracking(0.22 * 12).foregroundStyle(NB.ember1.opacity(0.85))
                    Text("\(Fmt.kg(kg)) REPLACES \(Fmt.kg(earlier.weightKg))").font(NBFont.brand(500, 13.5)).foregroundStyle(NB.white.opacity(0.70))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }

            HStack {
                UnitToggle(options: ["KG", "LB"], selection: $unit)
                Spacer(minLength: 0)
                // The date cannot be changed: back-filling goes through the day's own page.
                Text(todayLabel)
                    .font(NBFont.dot(600, 10)).tracking(0.18 * 10)
                    .foregroundStyle(NB.white.opacity(0.34))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Its own keypad, not the system keyboard: this screen takes one decimal number,
            // so letters, emoji and a return key are all noise.
            DecimalPad(text: $typed)
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Spacer(minLength: 0)

            // SAVE is the only lime on this screen, and it stays tappable even when the
            // number has not moved — "yes, today is still 78.6" is a valid record.
            LimePillButton(title: "SAVE", enabled: parsed != nil) { save() }
                .padding(.bottom, 22)
        }
    }

    private var todayLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "TODAY · \(f.string(from: Date()).uppercased())"
    }

    private var parsed: Double? {
        guard let kg = typedKg, (20...300).contains(kg) else { return nil }
        return kg
    }
    private var typedKg: Double? {
        guard let v = Double(typed) else { return nil }
        return unit == "KG" ? v : v / 2.2046226
    }
    /// 10S rule 03 / edge 3 · 20–300 kg (44–661 lb), fixed: SAVE off, the number amber, the
    /// range and nothing else. Never 「与上次相差过大」.
    private var outOfRange: Bool { typedKg.map { !(20...300).contains($0) } ?? false }
    /// 10S edge 2 · a second one today replaces the first in the calculation; the row stays.
    private var todaysEarlier: WeighIn? {
        data.weighIns.first { Calendar.current.isDate($0.date, inSameDayAs: Date()) }
    }

    private func save() {
        guard let kg = parsed else { return }
        data.addWeighIn(WeighIn(id: UUID(), date: Date(), weightKg: kg,
                                bodyFatPercent: nil, source: .measured, origin: .manual))
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        dismiss()
    }

    // MARK: 03 · Health 那一条 From Health — confirm, not auto-adopt

    private var fromHealth: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("FROM HEALTH")
                    .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                    .foregroundStyle(NB.white.opacity(0.34))
                Text("There's a new weigh-in")
                    .font(NBFont.ui(500, 22)).tracking(0.01 * 22)
                    .foregroundStyle(NB.text1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 22)

            if let c = healthCandidate {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(data.profile.usesMetric ? Fmt.kg(c.kg) : String(format: "%.1f", c.kg * 2.2046226))
                        .font(NBFont.brand(700, 54)).tracking(-0.045 * 54)
                        .foregroundStyle(NB.text1)
                    Text(data.profile.usesMetric ? "KG" : "LB")
                        .font(NBFont.dot(500, 14))
                        .foregroundStyle(NB.white.opacity(0.34))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)

                // The number, its source and its time — three facts before one green button.
                Text("APPLE HEALTH  ·  \(c.at)")
                    .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                    .foregroundStyle(NB.white.opacity(0.34))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)

            LimePillButton(title: "USE THIS") {
                if let c = healthCandidate {
                    data.addWeighIn(WeighIn(id: UUID(), date: Date(), weightKg: c.kg,
                                            bodyFatPercent: nil, source: .measured, origin: .health))
                }
                dismiss()
            }

            // Swiping away is a refusal; we do not ask again for the same record.
            Button { mode = .byHand } label: {
                Text("Enter a different number")
                    .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.text3Prod)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }
}

/// One decimal number, one delete key, and nothing else.
struct DecimalPad: View {
    @Binding var text: String

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "DEL"]]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { key in
                        Button { tap(key) } label: {
                            Text(key)
                                .font(key == "DEL" ? NBFont.ui(500, 12) : NBFont.ui(400, 22))
                                .tracking(key == "DEL" ? 0.16 * 12 : 0)
                                .foregroundStyle(key == "DEL" ? NB.text3Prod : NB.text1)
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(NB.smokeKey, in: RoundedRectangle(cornerRadius: NB.R.key, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func tap(_ key: String) {
        switch key {
        case "DEL":
            if !text.isEmpty { text.removeLast() }
        case ".":
            if !text.contains(".") { text.append(".") }
        default:
            // one decimal place, 0.1 kg per notch
            if let dot = text.firstIndex(of: "."), text.distance(from: dot, to: text.endIndex) > 1 { return }
            if text.count < 6 { text.append(key) }
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
