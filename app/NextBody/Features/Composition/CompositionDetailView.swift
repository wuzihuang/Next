import SwiftUI

/// 10 · 成分详情 Composition. Entered from a panel widget (recomp / delta / dual) or from a
/// heat-map cell in Profile, which is why it carries a date and a pager. Back returns to
/// wherever it came from — one layer, never two.
struct CompositionDetailView: View {
    let focus: Date?

    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @State private var range = "DAY"
    @State private var day: UserDay = UserDay.containing(Date())

    private var m: DailyMetrics {
        // ⚠️ Today's row has to come from `today`, not from `history`. Both exist — history
        // holds the raw server rows and `today` is the merged one — and only the merged one
        // carries the composition figures the fetch fills in afterwards.
        if day == UserDay.containing(Date()) { return data.today }
        return data.history.first { $0.day == day } ?? data.today
    }
    /// The Call needs 7-day EMA and at least five weigh-ins. Below that it is PENDING and
    /// the quadrant is not drawn at all.
    private var hasCall: Bool { m.fatEmaDelta7d != nil && m.leanEmaDelta7d != nil && m.scans7d >= 5 }

    private var call: TheCall? {
        guard hasCall else { return nil }
        if let settled = m.serverCall { return settled }
        guard let f = m.fatEmaDelta7d, let l = m.leanEmaDelta7d else { return nil }
        return TheCall.from(fatDelta7d: f, leanDelta7d: l)
    }

    var body: some View {
        DetailScroll(glow: NB.lime1) {
            VStack(alignment: .leading, spacing: 14) {
                header
                callCard
                thatWeekCard
                if hasCall { whyCard } else { needsCard }
                SectionLabel("EVIDENCE")
                scaleCard
                if hasCall {
                    energyCard
                    macrosCard
                    foodCard
                    trainingCard
                    editButton
                } else {
                    gates
                    LimePillButton(title: "Add a weigh-in") { router.sheet = .weighIn }
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            router.backToRoot()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Path { p in
                    p.move(to: CGPoint(x: 7, y: 1))
                    p.addLine(to: CGPoint(x: 1.5, y: 6.5))
                    p.addLine(to: CGPoint(x: 7, y: 12))
                }
                .stroke(NB.macroLabel, style: StrokeStyle(lineWidth: 1.6, lineCap: .square))
                .frame(width: 8, height: 13)
                Text("COMPOSITION")
                    .font(NBFont.ui(500, 11)).tracking(0.24 * 11)
                    .foregroundStyle(NB.macroLabel)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(titleText)
                    .font(NBFont.brand(700, 28)).tracking(-0.02 * 28)
                    .foregroundStyle(NB.text1)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    PagerButton(forward: false, enabled: true) { day = day.adding(days: -1) }
                    PagerButton(forward: true, enabled: day < UserDay.containing(Date())) {
                        day = day.adding(days: 1)
                    }
                }
            }
            SegmentedPills(options: ["DAY", "WEEK", "MONTH"], selection: $range)
        }
        .padding(.top, 14)
    }

    private var titleText: String {
        let f = DateFormatter(); f.dateFormat = "EEE · MMM d"
        return f.string(from: day.start).uppercased()
    }

    /// The quadrant appears here and in one line of text — nowhere else, and never in the
    /// heat map's colours (F0 rule 05).
    private var callCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 15) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hasCall ? NB.lime1 : NB.barTrack)
                    .frame(width: 52, height: 52)
                    .shadow(color: hasCall ? NB.lime1.opacity(0.35) : .clear, radius: 13)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 9) {
                        Text(call?.rawValue ?? "NO CALL")
                            .font(NBFont.brand(700, 26)).tracking(-0.02 * 26)
                            .foregroundStyle(NB.text1)
                        Text(hasCall ? "ESTIMATE" : "PENDING")
                            .font(NBFont.ui(500, 11)).tracking(0.14 * 11)
                            .foregroundStyle(Color(hex: 0x9A9AA6))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .overlay(Capsule().stroke(NB.white.opacity(0.12), lineWidth: 1))
                    }
                    Text(hasCall
                         ? "FAT \(Fmt.signedKg(m.fatEmaDelta7d)) KG · LEAN \(Fmt.signedKg(m.leanEmaDelta7d)) KG · 7D"
                         : "FAT \(Fmt.dash) · LEAN \(Fmt.dash) · NEEDS 5 OF 7 DAYS")
                        .font(NBFont.dot(500, 11)).tracking(0.04 * 11)
                        .foregroundStyle(NB.macroValue)
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(NB.barTrack).frame(height: 1)
            HStack {
                HStack(spacing: 9) {
                    Text("CONFIDENCE")
                        .font(NBFont.ui(500, 11)).tracking(0.12 * 11)
                        .foregroundStyle(NB.text3Prod)
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule()
                                .fill(i < tierIndex ? NB.lime1 : NB.white.opacity(0.10))
                                .frame(width: 16, height: 4)
                        }
                    }
                    Text(m.confidence.rawValue)
                        .font(NBFont.dot(700, 11)).tracking(0.04 * 11)
                        .foregroundStyle(hasCall ? NB.lime1 : NB.text3)
                }
                Spacer(minLength: 0)
                // ⚠️ Never an unqualified fraction: the screen must say what it is counting.
                Text("\(m.scans7d)/7 DAYS MEASURED")
                    .font(NBFont.dot(500, 11)).tracking(0.04 * 11)
                    .foregroundStyle(Color(hex: 0x8A8A96))
            }
        }
        .padding(16)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
    }

    private var tierIndex: Int {
        switch m.confidence { case .pending: 1; case .medium: 2; case .high: 3 }
    }

    /// F0 rule 05 · seven cells coloured by Daily Direction, not by the quadrant.
    private var thatWeekCard: some View {
        CardBlock(title: "THAT WEEK", trailing: weekLabel, trailingIsDot: true) {
            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { d in
                    let metrics = data.history.first { $0.day == d }
                    VStack(spacing: 7) {
                        DirectionCell(direction: metrics?.direction ?? .greyNothing,
                                      today: d == day, height: 34)
                        Text(dayNumber(d))
                            .font(NBFont.dot(d == day ? 700 : 500, 11))
                            .foregroundStyle(d == day ? NB.text1 : Color(hex: 0x8A8A96))
                    }
                }
            }
        }
    }

    private var weekDays: [UserDay] {
        let weekday = Calendar.current.component(.weekday, from: day.start)
        let start = day.adding(days: -(weekday - 1))
        return (0..<7).map { start.adding(days: $0) }
    }
    private var weekLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "\(f.string(from: weekDays.first!.start).uppercased()) — \(dayNumber(weekDays.last!))"
    }
    private func dayNumber(_ d: UserDay) -> String {
        "\(Calendar.current.component(.day, from: d.start))"
    }

    /// Four signals. The card header says how many agree; the dots are lime only when
    /// that signal clears its own threshold.
    private var whyCard: some View {
        let s = signals
        return CardBlock(title: "WHY \(call?.rawValue ?? "")",
                         trailing: "\(s.filter(\.lit).count)/4 SIGNALS AGREE", trailingIsDot: true) {
            VStack(spacing: 12) {
                ForEach(s, id: \.name) { sig in
                    SignalRow(lit: sig.lit, name: sig.name, value: sig.value, note: sig.note)
                }
            }
        }
    }

    /// F2 §05 · the four signals behind THE CALL, each with the threshold it is measured
    /// against. ⚠️ A row is lit only when its own number actually clears — the card used to
    /// light all four and print "CLEARS THE −0.15 KG THRESHOLD" beside a −0.05, which is
    /// the page telling the user their own arithmetic is wrong.
    private var signals: [(name: String, value: String, note: String, lit: Bool)] {
        let fat = m.fatEmaDelta7d
        let lean = m.leanEmaDelta7d
        let fatLit = (fat.map { abs($0) > TheCall.fatBand }) ?? false
        let leanLit = (lean.map { abs($0) > TheCall.leanBand }) ?? false

        // 1.9 g/kg is the daily target; 1.8 is the threshold that scores a vote.
        let week = data.history.filter { $0.day <= m.day }.suffix(7)
        let perKg = week.compactMap { d -> Double? in
            guard let p = d.proteinIn, let kg = d.weightKg, kg > 0 else { return nil }
            return Double(p) / kg
        }
        let hitDays = perKg.filter { $0 >= 1.8 }.count
        let avgPerKg = perKg.isEmpty ? nil : perKg.reduce(0, +) / Double(perKg.count)

        let balances = week.compactMap(\.balance)
        let avgBalance = balances.isEmpty ? nil : balances.reduce(0, +) / Double(balances.count)
        let inWindow = (avgBalance.map { $0 <= -200 && $0 >= -500 }) ?? false

        return [
            ("FAT MASS TREND", "\(Fmt.signedKg(fat)) KG",
             fatLit ? "7D EMA · CLEARS THE ±0.15 KG THRESHOLD"
                    : "7D EMA · INSIDE THE ±0.15 KG THRESHOLD", fatLit),
            ("LEAN MASS TREND", "\(Fmt.signedKg(lean)) KG",
             leanLit ? "7D EMA · CLEARS THE ±0.10 KG THRESHOLD"
                     : "7D EMA · INSIDE THE ±0.10 KG THRESHOLD", leanLit),
            ("PROTEIN INTAKE",
             avgPerKg.map { String(format: "%.1f G/KG", $0) } ?? Fmt.dash,
             "\(hitDays) OF \(perKg.count) DAYS AT OR ABOVE 1.8 G/KG", hitDays >= 4),
            ("ENERGY BALANCE", Fmt.signedKcal(avgBalance) + " KCAL",
             inWindow ? "INSIDE THE −200 TO −500 RECOMP WINDOW"
                      : "OUTSIDE THE −200 TO −500 RECOMP WINDOW", inWindow),
        ]
    }

    private var needsCard: some View {
        CardBlock(title: "WHAT IT NEEDS", trailing: "\(m.scans7d) OF 5 SIGNALS READY") {
            VStack(alignment: .leading, spacing: 14) {
                SignalRow(lit: false, name: "FAT MASS TREND", value: Fmt.dash,
                          note: "NEEDS A WEIGH-IN BEFORE A TREND EXISTS")
                SignalRow(lit: false, name: "LEAN MASS TREND", value: Fmt.dash,
                          note: "NEEDS A WEIGH-IN BEFORE A TREND EXISTS")
                SignalRow(lit: false, name: "PROTEIN INTAKE", value: Fmt.dash,
                          note: "NEEDS FOOD LOGGED ON THE SAME DAY")
                SignalRow(lit: false, name: "ENERGY BALANCE", value: Fmt.dash,
                          note: "NEEDS BOTH INTAKE AND BURN ON THE SAME DAY")
            }
            Hairline()
            VStack(alignment: .leading, spacing: 6) {
                Text("HOW THIS IS DERIVED")
                    .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                    .foregroundStyle(NB.text3Prod)
                Text("One weigh-in swings ±0.8 kg on water alone, so no single morning ever sets a quadrant. The call comes from a 7-day exponential average and needs at least 5 measured days — below that its square stays grey.")
                    .font(NBFont.brand(400, 12.5))
                    .lineSpacing(5)
                    .foregroundStyle(NB.text2)
            }
            // ⚠️ RECOMP is inferred from body metrics: a direction, not a diagnosis.
            Text("RECOMP IS INFERRED FROM YOUR BODY METRICS — A DIRECTION, NOT A DIAGNOSIS.")
                .font(NBFont.ui(400, 10.5)).tracking(0.06 * 10.5)
                .foregroundStyle(NB.text3)
        }
    }

    /// F0 rule 09 · every field is tagged at source. Band BIA and a body-fat scale are both
    /// MEASURED and re-anchor the EMA; weight × body-fat % is DERIVED.
    private var scaleCard: some View {
        CardBlock(title: "SCALE", trailing: sourceLine, trailingIsDot: true) {
            HStack(spacing: 10) {
                EvidenceStat(label: "WEIGHT", value: Fmt.kg(m.weightKg), unit: "KG",
                             delta: "-0.30 VS 7D", deltaTint: NB.macroValue)
                EvidenceStat(label: "FAT MASS", value: Fmt.kg(m.fatKg), unit: "KG",
                             delta: "\(Fmt.signedKg(m.fatEmaDelta7d)) VS 7D", deltaTint: NB.lime1)
            }
            Rectangle().fill(NB.barTrack).frame(height: 1)
            HStack(spacing: 10) {
                EvidenceStat(label: "LEAN MASS", value: Fmt.kg(m.leanKg), unit: "KG",
                             delta: "\(Fmt.signedKg(m.leanEmaDelta7d)) VS 7D", deltaTint: NB.lime1)
                EvidenceStat(label: "BODY FAT", value: bodyFatPercent, unit: "%",
                             delta: "-0.50 VS 7D", deltaTint: NB.lime1)
            }
            Rectangle().fill(NB.barTrack).frame(height: 1)
            VStack(alignment: .leading, spacing: 9) {
                SourceLegend(measured: true, label: "MEASURED", fields: "WEIGHT · BODY FAT %")
                SourceLegend(measured: false, label: "DERIVED", fields: "FAT MASS · LEAN MASS")
            }
        }
    }

    private var sourceLine: String {
        guard let w = data.weighIns.first else { return "NO SOURCE CONNECTED" }
        return "\(w.origin.rawValue)  ·  \(Fmt.clock(w.date))"
    }
    private var bodyFatPercent: String {
        guard let f = m.fatKg, let w = m.weightKg, w > 0 else { return Fmt.dash }
        return String(format: "%.1f", f / w * 100)
    }

    private var energyCard: some View {
        CardBlock(title: "ENERGY", trailing: "LOGGED 4 MEALS", trailingIsDot: true) {
            HStack(spacing: 10) {
                BalanceStat(label: "IN", value: "2,180", tint: NB.ember1)
                BalanceStat(label: "OUT", value: "2,560", tint: NB.cyan1)
                BalanceStat(label: "BALANCE", value: "−380", tint: NB.text1)
            }
            BalanceAxis(now: -380, ifBudget: -380, enabled: true).frame(height: 52)
            HStack(spacing: 7) {
                Rectangle().fill(NB.limeMid.opacity(0.55)).frame(width: 14, height: 8)
                Text("RECOMP WINDOW  −200 TO −500 KCAL")
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
            }
        }
    }

    private var macrosCard: some View {
        CardBlock(title: "MACROS", trailing: "VS TARGET") {
            VStack(spacing: 10) {
                MacroDetailRow(name: "PRO", slot: MacroSlot(target: 165, eaten: 168), tint: NB.violet1, note: "2.3 G/KG")
                MacroDetailRow(name: "CARB", slot: MacroSlot(target: 255, eaten: 245), tint: NB.optimal2, note: "")
                MacroDetailRow(name: "FAT", slot: MacroSlot(target: 60, eaten: 52), tint: NB.run1, note: "")
            }
        }
    }

    private var foodCard: some View {
        CardBlock(title: "FOOD", trailing: "2,180 KCAL · 168 G PRO") {
            VStack(spacing: 10) {
                CompFoodRow(time: "07:20", name: "BREAKFAST", detail: "OATS · WHEY · BLUEBERRIES", kcal: "520", pro: "42 G PRO")
                Hairline()
                CompFoodRow(time: "12:40", name: "LUNCH", detail: "CHICKEN · RICE · GREENS", kcal: "720", pro: "58 G PRO")
                Hairline()
                CompFoodRow(time: "16:10", name: "SNACK", detail: "GREEK YOGURT · ALMONDS", kcal: "260", pro: "22 G PRO")
                Hairline()
                CompFoodRow(time: "19:40", name: "DINNER", detail: "SALMON · POTATO · BROCCOLI", kcal: "680", pro: "46 G PRO")
            }
        }
    }

    /// ⚠️ No sleep numbers here or anywhere (F0 rule 03) — the night only shows up as
    /// the Body Battery it produced.
    private var trainingCard: some View {
        CardBlock(title: "TRAINING", trailing: "STRENGTH · 50 MIN") {
            HStack(spacing: 10) {
                EvidenceStat(label: "TRAINING LOAD", value: "12.4", unit: nil, delta: nil, deltaTint: .clear)
                EvidenceStat(label: "STEPS", value: "8,432", unit: nil, delta: nil, deltaTint: .clear)
            }
            Rectangle().fill(NB.barTrack).frame(height: 1)
            HStack(spacing: 10) {
                EvidenceStat(label: "BODY BATTERY", value: "86", unit: "%", delta: nil, deltaTint: .clear)
                EvidenceStat(label: "ZONE 4+", value: "23", unit: "MIN", delta: nil, deltaTint: .clear)
            }
        }
    }

    private var editButton: some View {
        Button {
            router.open(.fuel, from: .home)
        } label: {
            Text("EDIT THIS DAY")
                .font(NBFont.ui(500, 12)).tracking(0.2 * 12)
                .foregroundStyle(NB.text1)
                .frame(width: NB.Layout.contentWidth, height: 48)
                .background(Color(hex: 0x141418), in: Capsule())
                .overlay(Capsule().stroke(NB.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private var gates: some View {
        VStack(spacing: 0) {
            GateRow(title: "ENERGY", when: "WITH YOU LOG A MEAL")
            Hairline()
            GateRow(title: "MACROS", when: "WITH YOU LOG A MEAL")
            Hairline()
            GateRow(title: "FOOD", when: "WITH YOU LOG A MEAL")
            Hairline()
            GateRow(title: "TRAINING", when: "AFTER 1 FULL DAY")
        }
        .padding(.horizontal, 14)
        .frame(width: NB.Layout.contentWidth)
    }
}

private struct PagerButton: View {
    let forward: Bool
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color(hex: 0x141418))
                Path { p in
                    if forward {
                        p.move(to: CGPoint(x: 1, y: 1)); p.addLine(to: CGPoint(x: 5, y: 5)); p.addLine(to: CGPoint(x: 1, y: 9))
                    } else {
                        p.move(to: CGPoint(x: 5, y: 1)); p.addLine(to: CGPoint(x: 1, y: 5)); p.addLine(to: CGPoint(x: 5, y: 9))
                    }
                }
                .stroke(enabled ? Color(hex: 0x8A8A96) : Color(hex: 0x5A5A66),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                .frame(width: 6, height: 10)
            }
            .frame(width: 30, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// F2 §06 · three colours plus two greys. LEVEL is outline only — it says
/// "we can't tell", not "you hit it exactly".
struct DirectionCell: View {
    let direction: DailyDirection
    var today = false
    var height: CGFloat = 34
    var radius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(stroke, lineWidth: direction == .level ? 1.5 : (today ? 2 : 0)))
            .frame(height: height)
    }

    private var fill: Color {
        switch direction {
        case .deficit:     NB.lime1
        case .level:       .clear
        case .surplus:     NB.alert2
        case .greyNothing: Color(hex: 0x26262E)
        case .greyNoBurn:  Color(hex: 0x3A3A44)
        }
    }
    private var stroke: Color {
        if direction == .level { return NB.white.opacity(0.35) }
        return today ? NB.white.opacity(0.7) : .clear
    }
}

private struct SignalRow: View {
    let lit: Bool
    let name: String
    let value: String
    let note: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(lit ? NB.lime1 : .clear)
                .overlay(lit ? nil : Circle().stroke(NB.white.opacity(0.25), lineWidth: 1))
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(NBFont.ui(500, 12.5)).tracking(0.06 * 12.5)
                        .foregroundStyle(lit ? NB.text1 : NB.text2)
                    Spacer(minLength: 0)
                    Text(value)
                        .font(NBFont.dot(700, 13))
                        .foregroundStyle(lit ? NB.lime1 : NB.text3)
                }
                Text(note)
                    .font(NBFont.dot(500, 11)).tracking(0.02 * 11)
                    .foregroundStyle(Color(hex: 0x8A8A96))
            }
        }
    }
}

private struct EvidenceStat: View {
    let label: String
    let value: String
    let unit: String?
    let delta: String?
    let deltaTint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(NBFont.ui(500, 11)).tracking(0.12 * 11)
                .foregroundStyle(NB.text3Prod)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(NBFont.dot(700, 20))
                    .foregroundStyle(NB.text1)
                if let unit {
                    Text(unit)
                        .font(NBFont.dot(500, 11))
                        .foregroundStyle(Color(hex: 0x8A8A96))
                }
            }
            if let delta {
                Text(delta)
                    .font(NBFont.dot(500, 11))
                    .foregroundStyle(deltaTint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SourceLegend: View {
    let measured: Bool
    let label: String
    let fields: String
    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(measured ? NB.lime1 : .clear)
                .overlay(measured ? nil : Circle().stroke(Color(hex: 0x6C6C78), lineWidth: 1))
                .frame(width: 8, height: 8)
            Text(label)
                .font(NBFont.ui(500, 11)).tracking(0.12 * 11)
                .foregroundStyle(NB.macroLabel)
                .frame(width: 74, alignment: .leading)
            Text(fields)
                .font(NBFont.dot(500, 11)).tracking(0.02 * 11)
                .foregroundStyle(Color(hex: 0x8A8A96))
            Spacer(minLength: 0)
        }
    }
}

private struct CompFoodRow: View {
    let time: String
    let name: String
    let detail: String
    let kcal: String
    let pro: String
    var body: some View {
        HStack(spacing: 10) {
            Text(time)
                .font(NBFont.dot(500, 11)).tracking(0.02 * 11)
                .foregroundStyle(Color(hex: 0x8A8A96))
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(NBFont.ui(600, 13)).foregroundStyle(NB.text1)
                Text(detail)
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(kcal).font(NBFont.dot(700, 14)).foregroundStyle(NB.text1)
                Text(pro).font(NBFont.dot(500, 11)).foregroundStyle(Color(hex: 0x8A8A96))
            }
            .frame(width: 64, alignment: .trailing)
        }
    }
}
