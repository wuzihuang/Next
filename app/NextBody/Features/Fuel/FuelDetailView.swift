import SwiftUI

/// 09 · 燃料详情 Fuel. Six cards, one scroll. This page never grows an input field:
/// logging always goes back to the dock.
struct FuelDetailView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @State private var editing: MealEntry?

    private var m: DailyMetrics { data.today }
    private var logged: Bool { m.eIn != nil }
    /// 补屏 B rule 07 · NO TARGET is for an account that has never had a weight — not one
    /// whose weight is old (edge 4: a 62-day-old weight is still a denominator).
    private var noTarget: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NB_DEBUG_NO_TARGET"] == "1" { return true }
        #endif
        return data.weighIns.isEmpty && m.weightKg == nil && m.targetIn == nil
    }

    var body: some View {
        if noTarget { NoTargetFuel() } else { fuelPage }
    }

    private var fuelPage: some View {
        DetailScroll(glow: NB.ember1) {
            VStack(alignment: .leading, spacing: 14) {
                header
                eatenCard
                macrosCard
                SectionLabel(logged ? "WHAT WENT IN" : "WHAT GOES IN")
                foodCard
                balanceCard
                if logged {
                    burnCard
                    weekCard
                } else {
                    VStack(spacing: 0) {
                        GateRow(title: "WHERE THE BURN GOES", when: "AFTER 1 FULL DAY")
                        Hairline()
                        GateRow(title: "THIS WEEK", when: "AFTER 7 DAYS")
                    }
                    .padding(.horizontal, 14)
                    .frame(width: NB.Layout.contentWidth)
                }
                logButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            router.backToRoot()
        }
        .sheet(item: $editing) { entry in
            EditMealSheet(entry: entry)
                .presentationDetents([.fraction(0.55)])
                .presentationBackground(NB.carbon2)
                .presentationCornerRadius(NB.R.panel)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("FUEL")
                    .font(NBFont.brand(700, 28)).tracking(-0.02 * 28)
                    .foregroundStyle(NB.text1)
                Spacer(minLength: 0)
                // Deliberately the same number as the one on the home card: you tap it
                // in the upper half and it is still there when you have scrolled down.
                Text(logged ? "\(Fmt.kcal(m.nextMeal)) LEFT" : "\(Fmt.kcal(m.targetIn)) TARGET")
                    .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
                    .foregroundStyle(NB.emberPale)
            }
            // ⚠️ Absent on purpose — see 08. VAF · "留一个点了没反应的分段控件比没有更糟",
            // and 1EIH rules delete for both pages. THIS WEEK at the foot of this page is
            // what WEEK was for.
        }
        .padding(.top, 14)
    }

    /// A2 · the big number is what has been eaten, not what is left. Subtraction needs both
    /// of its operands on screen before the result means anything.
    private var eatenCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("EATEN TODAY")
                    .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
                Text(logged ? mealSummary : "NOTHING LOGGED YET")
                    .font(NBFont.ui(500, 11)).tracking(0.06 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.kcal(m.eIn))
                    .font(NBFont.dot(700, 54)).tracking(-0.02 * 54)
                    .foregroundStyle(logged ? NB.ember1 : NB.text3Prod)
                Text("/\(Fmt.kcal(m.targetIn)) KCAL")
                    .font(NBFont.dot(500, 14)).tracking(0.02 * 14)
                    .foregroundStyle(NB.macroValue)
            }
            VStack(alignment: .leading, spacing: 9) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x1A1A20))
                        if logged, let eIn = m.eIn, let t = m.targetIn, t > 0 {
                            Capsule().fill(NB.ember1).frame(width: geo.size.width * min(1, eIn / t))
                        }
                    }
                }
                .frame(height: 12)
                HStack(alignment: .firstTextBaseline) {
                    // "an empty page" and "a broken page" must not look the same:
                    // NOTHING COUNTED YET — A BLANK, NOT A ZERO.
                    Text(logged ? "\(Fmt.kcal(m.nextMeal)) LEFT — \(leftInWords)"
                                : "NOTHING COUNTED YET — A BLANK, NOT A ZERO")
                        .font(NBFont.ui(500, 12)).tracking(0.04 * 12)
                        .foregroundStyle(NB.emberPale)
                    Spacer(minLength: 0)
                    Text(logged ? percentText : Fmt.dash)
                        .font(NBFont.dot(500, 11)).tracking(0.02 * 11)
                        .foregroundStyle(Color(hex: 0x8A8A96))
                }
            }
        }
        .padding(.top, 18).padding(.horizontal, 14).padding(.bottom, 16)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
    }

    /// How many meals went in and when the last one did. Both come from the rows the user
    /// can scroll down and read — a count that disagrees with the list below it is the
    /// fastest way to lose the page.
    private var mealSummary: String {
        let today = data.meals.filter { $0.status == .confirmed }
        guard let last = today.map(\.at).max() else { return "NOTHING LOGGED YET" }
        return "\(today.count) MEAL\(today.count == 1 ? "" : "S") · LAST \(Fmt.clock(last))"
    }

    /// The remaining budget said as a meal rather than a number. It has to match the size
    /// of what is actually left, or the sentence is worse than no sentence.
    private var leftInWords: String {
        guard let left = m.nextMeal else { return "NOTHING BOOKED" }
        if left >= 700 { return "ABOUT ONE FULL DINNER" }
        if left >= 400 { return "ABOUT A LIGHT DINNER" }
        if left >= 200 { return "ABOUT A SNACK" }
        return "BARELY A SNACK"
    }

    /// ⚠️ Protein comes first whenever it is short, and only then does the biggest
    /// remaining gap get named. Ranking the three by relative shortfall picks fat about
    /// half the time, and "FAT IS THE ONE THAT MATTERS TONIGHT" is advice this product
    /// does not give: F2 §04 anchors the whole split on protein and takes carbs out of
    /// what is left. The sentence has to agree with the arithmetic above it.
    private var macroNote: String {
        let slots: [(String, MacroSlot?)] = [("PROTEIN", m.protein), ("CARBS", m.carb), ("FAT", m.fat)]
        let gaps = slots.compactMap { name, slot -> (String, Int, Double)? in
            guard let slot, slot.target > 0 else { return nil }
            let short = max(0, slot.target - slot.eaten)
            return (name, short, Double(short) / Double(slot.target))
        }
        let protein = gaps.first { $0.0 == "PROTEIN" }
        let worst = (protein.map { $0.1 > 0 } == true) ? protein : gaps.max { $0.2 < $1.2 }
        guard let worst, worst.1 > 0 else { return "EVERY TARGET IS MET — NOTHING LEFT TO CHASE TODAY." }
        let openSlots = MealEntry.Slot.allCases.count - Set(data.meals.filter { $0.status == .confirmed }.map(\.slot)).count
        let meals = openSlots <= 0 ? "NOTHING LEFT ON THE PLAN"
                                   : "\(openSlots) MEAL\(openSlots == 1 ? "" : "S") LEFT"
        let gap = (m.targetLoad ?? 0) - (m.trainingLoad ?? 0)
        let session = gap >= 3 ? " AND A SESSION ON THE WAY" : ""
        return "\(worst.0) IS THE ONE THAT MATTERS TONIGHT — \(worst.1) G SHORT WITH \(meals)\(session)."
    }

    private var percentText: String {
        guard let eIn = m.eIn, let t = m.targetIn, t > 0 else { return Fmt.dash }
        return "\(Int((eIn / t * 100).rounded()))%"
    }

    /// A3 · three bars, never merged. 84 g of protein and 132 g of carbs do not mean the same
    /// thing tonight; averaging them into one percentage erases the only useful distinction.
    private var macrosCard: some View {
        CardBlock(title: "MACROS", trailing: "VS TARGET") {
            VStack(spacing: 14) {
                MacroDetailRow(name: "PRO", slot: m.protein, tint: NB.violet1,
                               note: proteinNote)
                MacroDetailRow(name: "CARB", slot: m.carb, tint: NB.optimal2,
                               note: toGo(m.carb, "G TO GO"))
                MacroDetailRow(name: "FAT", slot: m.fat, tint: NB.run1,
                               note: toGo(m.fat, "G TO GO"))
            }
            Hairline()
            Text(logged ? macroNote
                 : "THESE TARGETS COME FROM YOUR WEIGHT AND YOUR GOAL — THEY ARE READY BEFORE YOU LOG ANYTHING.")
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .lineSpacing(5)
                .foregroundStyle(NB.text3Prod)
        }
    }

    private var proteinNote: String {
        guard let p = m.protein else { return "\(Fmt.dash) G/KG" }
        guard let w = m.weightKg, p.eaten > 0 else {
            return "\(Fmt.dash) G/KG · \(p.target) G TO GO"
        }
        return String(format: "%.1f G/KG · %d G TO GO", Double(p.eaten) / w, max(0, p.target - p.eaten))
    }
    private func toGo(_ slot: MacroSlot?, _ suffix: String) -> String {
        guard let s = slot else { return Fmt.dash }
        return "\(max(0, s.target - s.eaten)) \(suffix)"
    }

    private func toGoValue(_ slot: MacroSlot?) -> String {
        slot.map { "\(max(0, $0.target - $0.eaten))" } ?? Fmt.dash
    }

    /// A4 · timestamps on the left so the card reads like a day, not like a list.
    /// The last row is the single amber OPEN slot — the only highlight the page allows.
    private var foodCard: some View {
        CardBlock(title: "FOOD",
                  trailing: logged ? "\(Fmt.kcal(m.eIn)) KCAL · \(m.protein?.eaten ?? 0) G PRO" : "NOTHING IN YET") {
            let confirmed = data.meals.filter { $0.status == .confirmed }.sorted { $0.at < $1.at }
            VStack(spacing: 10) {
                ForEach(Array(confirmed.enumerated()), id: \.element.id) { i, meal in
                    // F0 right column · the edit / delete entry point this page was missing.
                    Button { if data.canEdit(meal) { editing = meal } } label: {
                        MealRow(meal: meal)
                    }
                    .buttonStyle(.plain)
                    if i < confirmed.count - 1 { Hairline() }
                }
            }
            ForEach(openSlots, id: \.self) { slot in
                OpenSlotRow(slot: slot,
                            hint: slot == nextSlot ? (logged ? "AIM FOR 60 G PROTEIN IN IT" : "START WITH 40 G PROTEIN") : "NOT LOGGED",
                            kcal: slot == nextSlot ? (logged ? Fmt.kcal(m.nextMeal) : "~500") : Fmt.dash,
                            lit: slot == nextSlot)
            }
            if !logged {
                // B4 · one of the four ways to let a user say "I didn't eat".
                // ⚠️ It appears only in the empty state.
                HStack {
                    Text("Fasting, or nothing so far?")
                        .font(NBFont.ui(300, 12)).tracking(0.02 * 12)
                        .foregroundStyle(NB.text3Prod)
                    Spacer(minLength: 0)
                    Button {
                        data.today.fuelState = .fasted
                        data.today.eIn = 0
                    } label: {
                        Text("MARK AS FASTED")
                            .font(NBFont.ui(500, 11)).tracking(0.12 * 11)
                            .foregroundStyle(NB.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var openSlots: [MealEntry.Slot] {
        let taken = Set(data.meals.filter { $0.status == .confirmed }.map(\.slot))
        return MealEntry.Slot.allCases.filter { !taken.contains($0) }
    }

    /// B3 · exactly one slot is lit, chosen by the clock. Grey OPEN is not a failure state.
    private var nextSlot: MealEntry.Slot? {
        let h = Calendar.current.component(.hour, from: Date())
        let byClock: MealEntry.Slot = h < 11 ? .breakfast : (h < 15 ? .lunch : (h < 21 ? .dinner : .snack))
        return openSlots.contains(byClock) ? byClock : openSlots.first
    }

    /// A6 · two different bases on one axis, so both rows say which base they use.
    /// NOW = E_IN − E_OUT_NOW, both measured. The second row is a conditional, not an estimate.
    private var balanceCard: some View {
        CardBlock(title: "ENERGY BALANCE",
                  trailing: logged ? "SO FAR TODAY" : "NEEDS A DAY OF WEAR") {
            HStack(spacing: 10) {
                BalanceStat(label: "IN", value: Fmt.kcal(m.eIn), tint: logged ? NB.ember1 : NB.text3Prod)
                BalanceStat(label: "OUT", value: Fmt.kcal(m.eOutNow), tint: logged ? NB.cyan1 : NB.text3Prod)
                BalanceStat(label: "BALANCE", value: Fmt.signedKcal(m.balance), tint: NB.text1)
            }
            BalanceAxis(now: m.balance,
                        ifBudget: (m.targetIn ?? 0) - (m.eOutFull ?? 0),
                        enabled: logged)
                .frame(height: 52)
            HStack(spacing: 4) {
                ForEach(["−800", "−400", "0", "+400"], id: \.self) { t in
                    Text(t)
                        .font(NBFont.dot(500, 10))
                        .foregroundStyle(Color(hex: 0x8A8A96))
                    if t != "+400" { Spacer(minLength: 0) }
                }
            }
            HStack(spacing: 16) {
                HStack(spacing: 7) {
                    Rectangle().fill(NB.limeMid.opacity(0.55)).frame(width: 14, height: 8)
                    Text("RECOMP WINDOW")
                        .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                        .foregroundStyle(NB.text3Prod)
                }
                if logged {
                    HStack(spacing: 7) {
                        Circle().stroke(NB.ember1, lineWidth: 2).frame(width: 9, height: 9)
                            .accessibilityLabel("Needs you")   // F5 §09 · colour is not the only carrier
                        Text("IF YOU EAT THE \(Fmt.kcal(m.nextMeal))")
                            .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                            .foregroundStyle(NB.text3Prod)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// A7 · 2,280 = BASELINE 1,480 + STEPS 320 + TRAINING 480. The training block is dashed
    /// because it has not happened yet; anything forecast is always dashed, product-wide.
    private var burnCard: some View {
        CardBlock(title: "WHERE THE BURN GOES", trailing: "\(Fmt.kcal(m.eOutFull)) EST", trailingIsDot: true) {
            HStack(spacing: 2) {
                // ⚠️ Every row here is the whole day, because the header says EST. Mixing
                // the elapsed baseline into a card headed by a full-day estimate leaves
                // three numbers that visibly do not add up to the one above them.
                let total = max(m.eOutFull ?? 1, 1)
                Capsule().fill(NB.cyanDeep)
                    .frame(width: 328 * CGFloat((m.bmrFull ?? 0) / total), height: 10)
                Capsule().fill(NB.cyan1)
                    .frame(width: 328 * CGFloat((m.activeForecast ?? 0) / total), height: 10)
                Capsule().fill(NB.cyan3.opacity(0.5))
                    .frame(height: 10)
                    .overlay(Capsule().strokeBorder(NB.cyan1.opacity(0.4),
                                                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
            VStack(spacing: 11) {
                BurnRow(swatch: NB.cyanDeep, dashed: false, name: "BASELINE",
                        detail: nil, value: Fmt.kcal(m.bmrFull), valueTint: NB.macroValue)
                BurnRow(swatch: NB.cyan1, dashed: false, name: "STEPS & MOVEMENT",
                        detail: nil, value: Fmt.kcal(m.activeForecast), valueTint: NB.macroValue)
                BurnRow(swatch: NB.cyan3.opacity(0.5), dashed: true, name: MetricNames.training,
                        detail: "PLANNED · \(plannedSession)",
                        value: Fmt.kcal(m.eTrainPlan), valueTint: NB.cyanPale)
            }
        }
    }

    /// A8 · a week of trend, not tappable. ⚠️ Today is only coloured once the day has closed.
    private var weekCard: some View {
        let week = Array(data.history.suffix(7))
        let values = week.map { $0.balance ?? 0 }
        let labels = week.map { Fmt.weekday($0.day.date) }
        // ⚠️ Today is not in the average: a day in progress is always in deficit, and an
        // average that includes it reads as progress every morning and nothing by evening.
        let closed = week.dropLast().compactMap(\.balance)
        let avg = closed.isEmpty ? nil : closed.reduce(0, +) / Double(closed.count)
        let inWindow = closed.filter { $0 <= -200 && $0 >= -500 }.count
        return CardBlock(title: "THIS WEEK",
                         trailing: "AVG \(Fmt.signedKcal(avg))", trailingIsDot: true) {
            BalanceWeek(values: values, todayClosed: m.day.isClosed)
                .frame(height: 76)
            HStack {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, d in
                    Text(d)
                        .font(NBFont.dot(i == labels.count - 1 ? 700 : 500, 10))
                        .foregroundStyle(i == labels.count - 1 ? NB.lime2 : Color(hex: 0x8A8A96))
                        .frame(width: 34)
                    if i < labels.count - 1 { Spacer(minLength: 0) }
                }
            }
            Hairline()
            Text("\(inWindow) OF \(closed.count) FINISHED DAYS LANDED INSIDE THE RECOMP WINDOW. THE SHADED BAND IS −200 TO −500 KCAL.")
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .lineSpacing(5)
                .foregroundStyle(NB.text3Prod)
        }
    }

    /// The planned session has to be the one board 08 is offering, or the two pages
    /// disagree about the same evening.
    private var plannedSession: String {
        let gap = (m.targetLoad ?? 0) - (m.trainingLoad ?? 0)
        if gap >= 8 { return "STRENGTH 45 MIN" }
        if gap >= 3 { return "STRENGTH 30 MIN" }
        return "EASY WALK 20 MIN"
    }

    /// A9 · not a form entry point: it opens the dock with "log a meal · dinner · 660 left"
    /// prefilled. Lime and solid in the empty state, dark and outlined once there is data.
    private var logButton: some View {
        Button {
            router.backToRoot()
        } label: {
            Text("LOG A MEAL")
                .font(NBFont.ui(500, 12)).tracking(0.2 * 12)
                .foregroundStyle(logged ? NB.text1 : NB.carbon)
                .frame(width: NB.Layout.contentWidth, height: logged ? 48 : 56)
                .background(logged ? Color(hex: 0x141418) : NB.lime1, in: Capsule())
                .overlay(logged ? Capsule().stroke(NB.white.opacity(0.10), lineWidth: 1) : nil)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}

// MARK: rows

struct MacroDetailRow: View {
    let name: String
    let slot: MacroSlot?
    let tint: Color
    let note: String

    private var macroValue: String {
        guard let s = slot else { return Fmt.dash }
        return s.eaten > 0 ? "\(s.eaten)/\(s.target)" : "—/\(s.target)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(name)
                    .font(NBFont.ui(600, 12)).tracking(0.06 * 12)
                    .foregroundStyle(NB.text1)
                    .frame(width: 44, alignment: .leading)
                Text(note)
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
                // 09 · B2 · the numerator is blank until something is logged; the
                // denominator is there from the start. That is the line between
                // "no answer yet" and "broken".
                Text(macroValue)
                    .font(NBFont.dot(700, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.macroValue)
                    .frame(width: 70, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0x1A1A20))
                    if let s = slot, s.target > 0, s.eaten > 0 {
                        Capsule().fill(tint)
                            .frame(width: geo.size.width * min(1, Double(s.eaten) / Double(s.target)))
                    }
                }
            }
            .frame(height: 8)
        }
    }
}

struct MealRow: View {
    let meal: MealEntry

    /// F2 rule 03 · a 01:20 snack belongs to the day that started at yesterday's 04:00.
    /// The "+1" is the visible evidence of the one-calendar ruling.
    private var time: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let clock = f.string(from: meal.at)
        let sameCalendarDay = Calendar.current.isDate(meal.at, inSameDayAs: meal.day.start)
        return sameCalendarDay ? clock : "\(clock) +1"
    }
    var body: some View {
        HStack(spacing: 10) {
            Text(time)
                .font(NBFont.dot(500, 11)).tracking(0.02 * 11)
                .foregroundStyle(Color(hex: 0x8A8A96))
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.slot.rawValue)
                    .font(NBFont.ui(600, 13))
                    .foregroundStyle(NB.text1)
                Text(meal.text.uppercased())
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.kcal(meal.kcal))
                    .font(NBFont.dot(700, 14)).tracking(0.02 * 14)
                    .foregroundStyle(NB.text1)
                Text("\(meal.protein) G PRO")
                    .font(NBFont.dot(500, 11)).tracking(0.02 * 11)
                    .foregroundStyle(Color(hex: 0x8A8A96))
            }
            .frame(width: 64, alignment: .trailing)
        }
    }
}

struct OpenSlotRow: View {
    let slot: MealEntry.Slot
    let hint: String
    let kcal: String
    let lit: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("OPEN")
                .font(NBFont.ui(500, 10)).tracking(0.1 * 10)
                .foregroundStyle(lit ? NB.ember2 : NB.white.opacity(0.28))
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.rawValue)
                    .font(NBFont.ui(600, 13))
                    .foregroundStyle(lit ? NB.emberPale : NB.white.opacity(0.42))
                Text(hint)
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(lit ? Color(hex: 0xC9A365) : NB.white.opacity(0.28))
            }
            Spacer(minLength: 0)
            Text(kcal)
                .font(NBFont.dot(700, 14)).tracking(0.02 * 14)
                .foregroundStyle(lit ? NB.ember1 : NB.white.opacity(0.28))
                .frame(width: 64, alignment: .trailing)
        }
        .padding(12)
        .background(lit ? Color(hex: 0x1C1408) : .clear,
                    in: RoundedRectangle(cornerRadius: NB.R.tile, style: .continuous))
        .overlay(lit ? RoundedRectangle(cornerRadius: NB.R.tile, style: .continuous)
            .strokeBorder(NB.ember1.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) : nil)
    }
}

struct BalanceStat: View {
    let label: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(NBFont.ui(500, 11)).tracking(0.1 * 11)
                .foregroundStyle(NB.text3Prod)
            Text(value)
                .font(NBFont.dot(700, 24)).tracking(-0.01 * 24)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// −800 … +400, absolute. The RECOMP window (−200 … −500) never rescales with the day's data.
struct BalanceAxis: View {
    let now: Double?
    let ifBudget: Double
    let enabled: Bool

    private func x(_ v: Double, _ w: CGFloat) -> CGFloat {
        CGFloat((v + 800) / 1200) * w
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color(hex: 0x1A1A20))
                    .frame(height: 8).offset(y: 24)
                Rectangle().fill(NB.limeMid.opacity(0.55))
                    .frame(width: x(-200, w) - x(-500, w), height: 8)
                    .offset(x: x(-500, w), y: 24)
                Rectangle().fill(NB.white.opacity(0.18))
                    .frame(width: 1, height: 16).offset(x: x(0, w), y: 20)
                if enabled {
                    Circle().fill(NB.carbon2)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(NB.ember1, lineWidth: 2))
                        .offset(x: x(ifBudget, w) - 4.5, y: 23.5)
                    Capsule().fill(NB.white)
                        .frame(width: 2.5, height: 20)
                        .offset(x: x(now ?? 0, w) - 1.25, y: 18)
                    Text("\(Fmt.signedKcal(now)) NOW")
                        .font(NBFont.dot(700, 10)).tracking(0.02 * 10)
                        .foregroundStyle(NB.text1)
                        .offset(x: max(0, x(now ?? 0, w) - 22), y: 0)
                    Text("\(Fmt.signedKcal(ifBudget)) EST")
                        .font(NBFont.dot(700, 10)).tracking(0.02 * 10)
                        .foregroundStyle(NB.ember1)
                        .offset(x: max(0, x(ifBudget, w) - 18), y: 38)
                }
            }
        }
    }
}

struct BurnRow: View {
    let swatch: Color
    let dashed: Bool
    let name: String
    let detail: String?
    let value: String
    let valueTint: Color

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 2)
                .fill(swatch)
                .frame(width: 12, height: 8)
                .overlay(dashed ? RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(NB.cyan1.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2])) : nil)
                .frame(width: 14, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(NBFont.ui(500, 12)).tracking(0.06 * 12)
                    .foregroundStyle(NB.text1)
                if let detail {
                    Text(detail)
                        .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                        .foregroundStyle(NB.text3Prod)
                }
            }
            Spacer(minLength: 0)
            Text(value)
                .font(NBFont.dot(700, 13)).tracking(0.02 * 13)
                .foregroundStyle(valueTint)
                .frame(width: 64, alignment: .trailing)
        }
    }
}

struct BalanceWeek: View {
    let values: [Double]
    let todayClosed: Bool

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let maxAbs: Double = 800
            ZStack(alignment: .topLeading) {
                // the −200 … −500 band, absolute and never rescaled
                Rectangle().fill(NB.limeMid.opacity(0.18))
                    .frame(height: h * CGFloat(300 / maxAbs))
                    .offset(y: h * CGFloat(200 / maxAbs))
                HStack(spacing: 0) {
                    ForEach(values.indices, id: \.self) { i in
                        let inWindow = values[i] <= -200 && values[i] >= -500
                        let isToday = i == values.count - 1
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isToday && !todayClosed ? NB.lime2
                                  : (inWindow ? NB.limeMid : Color(hex: 0x3A3A44)))
                            .frame(width: 34, height: max(4, h * CGFloat(abs(values[i]) / maxAbs)))
                            .frame(height: h, alignment: .bottom)
                        if i < values.count - 1 { Spacer(minLength: 0) }
                    }
                }
                Path { p in
                    for y in [200.0, 500.0] {
                        let yy = h * CGFloat(y / maxAbs)
                        p.move(to: CGPoint(x: 0, y: yy)); p.addLine(to: CGPoint(x: geo.size.width, y: yy))
                    }
                }
                .stroke(NB.lime2.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
    }
}

/// F0 right column · "改一笔／删一笔". Without it the first mis-logged meal is wrong forever,
/// and the heat map, the energy gap and The Call are all built on those numbers.
struct EditMealSheet: View {
    let entry: MealEntry
    @EnvironmentObject private var data: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var kcal = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(entry.slot.rawValue)
                    .font(NBFont.ui(500, 20)).tracking(0.01 * 20)
                    .foregroundStyle(NB.text1)
                Spacer(minLength: 0)
                Text(Fmt.clock(entry.at))
                    .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                    .foregroundStyle(NB.text3Prod)
            }

            TextField("", text: $text, axis: .vertical)
                .font(NBFont.ui(400, 15))
                .foregroundStyle(NB.text1)
                .tint(NB.lime1)
                .padding(14)
                .frame(height: 88, alignment: .topLeading)
                .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous)
                    .stroke(NB.hairline, lineWidth: 1))

            HStack(spacing: 10) {
                TextField("", text: $kcal)
                    .keyboardType(.numberPad)
                    .font(NBFont.dot(700, 20))
                    .foregroundStyle(NB.ember1)
                    .tint(NB.lime1)
                    .padding(.horizontal, 14)
                    .frame(width: 120, height: 52)
                    .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous)
                        .stroke(NB.hairline, lineWidth: 1))
                Text("KCAL")
                    .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
            }

            Text("EDITING RECOMPUTES THIS USER DAY. RANGE IS THE LAST 7 DAYS.")
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .foregroundStyle(NB.text3Prod)

            Spacer(minLength: 0)

            LimePillButton(title: "Save") {
                data.updateMeal(entry.id, kcal: Double(kcal) ?? entry.kcal, text: text)
                dismiss()
            }

            Button {
                data.deleteMeal(entry.id)
                dismiss()
            } label: {
                Text("Delete this entry")
                    .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                    .foregroundStyle(NB.alert2)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon2)
        .onAppear { text = entry.text; kcal = String(Int(entry.kcal)) }
    }
}
