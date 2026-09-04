import SwiftUI

/// 09 · 燃料详情 Fuel. Six cards, one scroll. This page never grows an input field:
/// logging always goes back to the dock.
struct FuelDetailView: View {
    init(focus: UserDay? = nil) { _day = State(initialValue: focus ?? UserDay.containing(Date())) }
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @State private var editing: MealEntry?
    /// 09 edge 5 · PAST DAY. The page pages back like 10 does; a closed day shows what was
    /// measured and nothing that is still an estimate. Range-limited to 7 user days (F2 §08).
    @State private var day: UserDay = UserDay.containing(Date())
    private var today: UserDay { UserDay.containing(Date()) }
    private var isPast: Bool { day < today }

    private var m: DailyMetrics {
        guard isPast else { return data.today }
        var row = data.history.first { $0.day == day } ?? DailyMetrics(day: day)
        // History rows carry what went in as totals; the macro slots are filled from them so
        // the same card reads the same way on a past day.
        row.protein = row.protein.map { MacroSlot(target: $0.target, eaten: row.proteinIn ?? dayMeals.reduce(0) { $0 + $1.protein }) }
        row.carb    = row.carb.map    { MacroSlot(target: $0.target, eaten: row.carbIn    ?? dayMeals.reduce(0) { $0 + $1.carb }) }
        row.fat     = row.fat.map     { MacroSlot(target: $0.target, eaten: row.fatIn     ?? dayMeals.reduce(0) { $0 + $1.fat }) }
        if row.eIn == nil, !dayMeals.isEmpty { row.eIn = dayMeals.reduce(0) { $0 + $1.kcal } }
        return row
    }
    /// The day's own rows: today's from `meals`, a past day's from the week window, plus
    /// anything back-logged in this session.
    private var dayMeals: [MealEntry] {
        let own = data.meals.filter { $0.day == day && $0.status == .confirmed }
        let window = data.recentMeals.filter { r in r.day == day && !own.contains { $0.id == r.id } }
        return (own + window).sorted { $0.at < $1.at }
    }
    private var logged: Bool { m.eIn != nil }
    private var pastTitle: String {
        Fmt.displayDate(day.start, format: "EEE d MMM").uppercased()
    }
    /// 09 edge 1 · PARTIAL: logged but not closed — a slot is still open.
    private var closed: Bool { openSlots.isEmpty }
    private var partialSummary: String {
        let n = data.meals.filter { $0.status == .confirmed }.count
        return n == 1 ? L("%d MEAL · NOT CLOSED", n) : L("%d MEALS · NOT CLOSED", n)
    }
    /// 09 edge 3 / rule 02 · over target is capped, not punished.
    private var overBy: Double? {
        guard let e = m.eIn, let t = m.targetIn, e > t else { return nil }
        return e - t
    }
    /// 09 edge 2 · OUT is trusted only when the day's activity data covers the day so far.
    /// ⚠️ The board leaves the threshold open (「门槛定几小时要拍板」); half of the elapsed day is
    /// the working value until it is ruled.
    private var coverageHours: Double {
        let curve = data.history.first(where: { $0.day == m.day && !$0.loadCurve.isEmpty })?.loadCurve ?? m.loadCurve
        return Double(curve.count) * 5 / 60
    }
    private var outUnknown: Bool {
        if DebugEdge.on("outunknown") { return true }
        // A closed day is judged on the whole day it had, not on the clock.
        let elapsed = isPast ? 24 : Date().timeIntervalSince(m.day.start) / 3600
        return logged && elapsed > 6 && coverageHours < elapsed * 0.5
    }
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
        // 09 edge 5 · a closed day is the headline — `‹ SAT 30 AUG` — under a FUEL eyebrow.
        //
        // ⚠️ DAY / WEEK / MONTH is absent on purpose — see 08. VAF · "留一个点了没反应的分段
        // 控件比没有更糟", and 1EIH rules delete for both pages. THIS WEEK at the foot of
        // this page is what WEEK was for.
        DetailScroll(glow: NB.ember1, title: L("FUEL"), headline: isPast ? pastTitle : nil, trailing: {
            if isPast {
                Text(overBy.map { L("+%@ OVER", Fmt.kcal($0)) } ?? L("CLOSED"))
                    .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
                    .foregroundStyle(NB.emberPale)
                // The board's today header has no pager; a closed day gets one to walk the week.
                HStack(spacing: 6) {
                    PagerButton(forward: false, enabled: day > today.adding(days: -6)) { withAnimation { day = day.adding(days: -1) } }
                    PagerButton(forward: true, enabled: isPast) { withAnimation { day = day.adding(days: 1) } }
                }
                .padding(.leading, 10)
            } else {
                // Deliberately the same number as the one on the home card: you tap it
                // in the upper half and it is still there when you have scrolled down.
                Text(logged ? (overBy.map { L("+%@ OVER", Fmt.kcal($0)) } ?? L("%@ LEFT", Fmt.kcal(m.nextMeal)))
                            : L("%@ TARGET", Fmt.kcal(m.targetIn)))
                    .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
                    .foregroundStyle(NB.emberPale)
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                eatenCard
                macrosCard
                SectionLabel(logged ? L("WHAT WENT IN") : L("WHAT GOES IN"))
                foodCard
                balanceCard
                // 09 edge 5 · EST is gone on a closed day: the burn card is a forecast.
                if isPast {
                    EmptyView()
                } else if logged {
                    burnCard
                    weekCard
                } else {
                    VStack(spacing: 0) {
                        GateRow(title: L("WHERE THE BURN GOES"), when: L("AFTER 1 FULL DAY"))
                        Hairline()
                        GateRow(title: L("THIS WEEK"), when: L("AFTER 7 DAYS"))
                    }
                    .padding(.horizontal, 14)
                    .frame(width: NB.Layout.contentWidth)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            // 09 edge 5 · on a closed day the chevron is the way back to today; from today
            // it is the way home.
            if isPast { withAnimation { day = today } } else { router.backToRoot() }
        }
        .sheet(item: $editing) { entry in
            EditMealSheet(entry: entry)
                .presentationDetents([.fraction(0.55)])
                .presentationBackground(NB.carbon2)
                .presentationCornerRadius(NB.R.panel)
        }
    }

    /// A2 · the big number is what has been eaten, not what is left. Subtraction needs both
    /// of its operands on screen before the result means anything.
    private var eatenCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(isPast ? L("EATEN THAT DAY") : L("EATEN TODAY"))
                    .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
                Text(isPast ? (logged ? mealSummary : L("NOTHING LOGGED"))
                     : logged ? (closed ? mealSummary : partialSummary) : L("NOTHING LOGGED YET"))
                    .font(logged && !closed ? NBFont.dot(700, 12) : NBFont.ui(500, 11))
                    .tracking(logged && !closed ? 0.04 * 12 : 0.06 * 11)
                    .foregroundStyle(logged && !closed ? NB.ember1.opacity(0.85) : NB.text3Prod)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.kcal(m.eIn))
                    .font(NBFont.dot(700, 54)).tracking(-0.02 * 54)
                    .foregroundStyle(logged ? NB.ember1 : NB.text3Prod)
                Text(L("/%@ KCAL", Fmt.kcal(m.targetIn)))
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
                    Text(isPast ? (logged ? (overBy.map { L("+%@ OVER — STILL A FINE DAY", Fmt.kcal($0)) } ?? L("CLOSED — NOTHING LEFT TO PLACE"))
                                          : L("NOTHING COUNTED — A BLANK, NOT A ZERO"))
                         : logged ? (overBy.map { L("+%@ OVER — STILL A FINE DAY", Fmt.kcal($0)) }
                                   ?? L("%@ LEFT — %@", Fmt.kcal(m.nextMeal), leftInWords))
                                : L("NOTHING COUNTED YET — A BLANK, NOT A ZERO"))
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
        guard let last = today.map(\.at).max() else { return L("NOTHING LOGGED YET") }
        return today.count == 1
            ? L("%d MEAL · LAST %@", today.count, Fmt.clock(last))
            : L("%d MEALS · LAST %@", today.count, Fmt.clock(last))
    }

    /// The remaining budget said as a meal rather than a number. It has to match the size
    /// of what is actually left, or the sentence is worse than no sentence.
    private var leftInWords: String {
        guard let left = m.nextMeal else { return L("NOTHING BOOKED") }
        if left >= 700 { return L("ABOUT ONE FULL DINNER") }
        if left >= 400 { return L("ABOUT A LIGHT DINNER") }
        if left >= 200 { return L("ABOUT A SNACK") }
        return L("BARELY A SNACK")
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
        guard let worst, worst.1 > 0 else { return L("EVERY TARGET IS MET — NOTHING LEFT TO CHASE TODAY.") }
        let openSlots = MealEntry.Slot.allCases.count - Set(data.meals.filter { $0.status == .confirmed }.map(\.slot)).count
        let meals = openSlots <= 0 ? L("NOTHING LEFT ON THE PLAN")
                                   : (openSlots == 1 ? L("%d MEAL LEFT", openSlots) : L("%d MEALS LEFT", openSlots))
        let gap = (m.targetLoad ?? 0) - (m.trainingLoad ?? 0)
        let session = gap >= 3 ? L(" AND A SESSION ON THE WAY") : ""
        return L("%@ IS THE ONE THAT MATTERS TONIGHT — %d G SHORT WITH %@%@.", L(worst.0), worst.1, meals, session)
    }

    private var percentText: String {
        guard let eIn = m.eIn, let t = m.targetIn, t > 0 else { return Fmt.dash }
        return "\(Int((eIn / t * 100).rounded()))%"
    }

    /// A3 · three bars, never merged. 84 g of protein and 132 g of carbs do not mean the same
    /// thing tonight; averaging them into one percentage erases the only useful distinction.
    private var macrosCard: some View {
        CardBlock(title: L("MACROS"), trailing: L("VS TARGET")) {
            VStack(spacing: 14) {
                MacroDetailRow(name: L("PRO"), slot: m.protein, tint: NB.violet1,
                               note: proteinNote)
                MacroDetailRow(name: L("CARB"), slot: m.carb, tint: NB.optimal2,
                               note: toGo(m.carb))
                MacroDetailRow(name: L("FAT"), slot: m.fat, tint: NB.run1,
                               note: toGo(m.fat))
            }
            Hairline()
            Text(logged ? macroNote
                 : L("THESE TARGETS COME FROM YOUR WEIGHT AND YOUR GOAL — THEY ARE READY BEFORE YOU LOG ANYTHING."))
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .lineSpacing(5)
                .foregroundStyle(NB.text3Prod)
        }
    }

    private var proteinNote: String {
        guard let p = m.protein else { return L("%@ G/KG", Fmt.dash) }
        guard let w = m.weightKg, p.eaten > 0 else {
            return L("%@ G/KG · %d G TO GO", Fmt.dash, p.target)
        }
        return L("%.1f G/KG · %d G TO GO", Double(p.eaten) / w, max(0, p.target - p.eaten))
    }
    private func toGo(_ slot: MacroSlot?) -> String {
        guard let s = slot else { return Fmt.dash }
        return L("%d G TO GO", max(0, s.target - s.eaten))
    }

    private func toGoValue(_ slot: MacroSlot?) -> String {
        slot.map { "\(max(0, $0.target - $0.eaten))" } ?? Fmt.dash
    }

    /// A4 · timestamps on the left so the card reads like a day, not like a list.
    /// The last row is the single amber OPEN slot — the only highlight the page allows.
    private var foodCard: some View {
        CardBlock(title: L("FOOD"),
                  trailing: logged ? L("%@ KCAL · %d G PRO", Fmt.kcal(m.eIn), m.protein?.eaten ?? m.proteinIn ?? dayMeals.reduce(0) { $0 + $1.protein }) : isPast ? L("NOTHING IN") : L("NOTHING IN YET")) {
            let confirmed = dayMeals
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
            // 09 edge 5 · OPEN slots and suggestions are for a day that is still running.
            ForEach(isPast ? [] : openSlots, id: \.self) { slot in
                OpenSlotRow(slot: slot,
                            hint: slot == nextSlot ? (logged ? L("AIM FOR 60 G PROTEIN IN IT") : L("START WITH 40 G PROTEIN")) : L("NOT LOGGED"),
                            kcal: slot == nextSlot ? (logged ? Fmt.kcal(m.nextMeal) : "~500") : Fmt.dash,
                            lit: slot == nextSlot)
            }
            if !logged, !isPast {
                // B4 · one of the four ways to let a user say "I didn't eat".
                // ⚠️ It appears only in the empty state.
                HStack {
                    Text(L("Fasting, or nothing so far?"))
                        .font(NBFont.ui(300, 12)).tracking(0.02 * 12)
                        .foregroundStyle(NB.text3Prod)
                    Spacer(minLength: 0)
                    Button {
                        data.today.fuelState = .fasted
                        data.today.eIn = 0
                    } label: {
                        Text(L("MARK AS FASTED"))
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
        CardBlock(title: L("ENERGY BALANCE"),
                  trailing: isPast ? L("CLOSED") : outUnknown ? L("%dH OF DATA ONLY", Int(coverageHours))
                          : logged ? L("SO FAR TODAY") : L("NEEDS A DAY OF WEAR"),
                  trailingIsDot: outUnknown || isPast,
                  trailingTint: outUnknown ? NB.ember1.opacity(0.85) : nil) {
            HStack(spacing: 10) {
                BalanceStat(label: L("IN"), value: Fmt.kcal(m.eIn), tint: logged ? NB.ember1 : NB.text3Prod)
                // 09 edge 2 · half the equation missing: OUT and BALANCE go grey, IN stays.
                // Never a BMR estimate dressed as a measurement.
                BalanceStat(label: L("OUT"), value: outUnknown ? Fmt.dash : Fmt.kcal(m.eOutNow),
                            tint: logged && !outUnknown ? NB.cyan1 : NB.text3Prod)
                BalanceStat(label: L("BALANCE"), value: outUnknown ? Fmt.dash : Fmt.signedKcal(m.balance),
                            tint: outUnknown ? NB.text3Prod : NB.text1)
            }
            if outUnknown {
                Text(isPast ? "THAT DAY'S BURN NEEDED A FULL DAY OF WEAR. THE MEALS STILL COUNT."
                            : "TODAY'S BURN NEEDS A FULL DAY OF WEAR. THE MEALS STILL COUNT.")
                    .font(NBFont.ui(300, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            if isPast {
                // 09 edge 5 · a closed day has one number, and it was measured.
                Text(L("MEASURED · NO ESTIMATE"))
                    .font(NBFont.dot(500, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.macroValue)
            }
            BalanceAxis(now: m.balance,
                        ifBudget: isPast ? (m.balance ?? 0) : (m.targetIn ?? 0) - (m.eOutFull ?? 0),
                        enabled: logged && !outUnknown)
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
                    Text(L("RECOMP WINDOW"))
                        .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                        .foregroundStyle(NB.text3Prod)
                }
                if logged, !isPast {
                    HStack(spacing: 7) {
                        Circle().stroke(NB.ember1, lineWidth: 2).frame(width: 9, height: 9)
                            .accessibilityLabel(L("Needs you"))   // F5 §09 · colour is not the only carrier
                        Text(L("IF YOU EAT THE %@", Fmt.kcal(m.nextMeal)))
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
        CardBlock(title: L("WHERE THE BURN GOES"), trailing: L("%@ EST", Fmt.kcal(m.eOutFull)), trailingIsDot: true) {
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
                BurnRow(swatch: NB.cyanDeep, dashed: false, name: L("BASELINE"),
                        detail: nil, value: Fmt.kcal(m.bmrFull), valueTint: NB.macroValue)
                BurnRow(swatch: NB.cyan1, dashed: false, name: L("STEPS & MOVEMENT"),
                        detail: nil, value: Fmt.kcal(m.activeForecast), valueTint: NB.macroValue)
                BurnRow(swatch: NB.cyan3.opacity(0.5), dashed: true, name: MetricNames.training,
                        detail: L("PLANNED · %@", plannedSession),
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
        return CardBlock(title: L("THIS WEEK"),
                         trailing: L("AVG %@", Fmt.signedKcal(avg)), trailingIsDot: true) {
            BalanceWeek(values: values, todayClosed: m.day.isClosed)
                .frame(height: 76)
            HStack {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, d in
                    // 09 edge 5 · a finished day opens as a closed page.
                    Button {
                        let target = week[i].day
                        if target < today { withAnimation { day = target } }
                    } label: {
                        Text(d)
                            .font(NBFont.dot(i == labels.count - 1 ? 700 : 500, 10))
                            .foregroundStyle(i == labels.count - 1 ? NB.lime2 : Color(hex: 0x8A8A96))
                            .frame(width: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(d)")
                    if i < labels.count - 1 { Spacer(minLength: 0) }
                }
            }
            Hairline()
            Text(L("%d OF %d FINISHED DAYS LANDED INSIDE THE RECOMP WINDOW. THE SHADED BAND IS −200 TO −500 KCAL.", inWindow, closed.count))
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .lineSpacing(5)
                .foregroundStyle(NB.text3Prod)
        }
    }

    /// The planned session has to be the one board 08 is offering, or the two pages
    /// disagree about the same evening.
    private var plannedSession: String {
        let gap = (m.targetLoad ?? 0) - (m.trainingLoad ?? 0)
        if gap >= 8 { return L("STRENGTH 45 MIN") }
        if gap >= 3 { return L("STRENGTH 30 MIN") }
        return L("EASY WALK 20 MIN")
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
                Text(L(name))
                    .font(NBFont.ui(600, 12)).tracking(0.06 * 12)
                    .foregroundStyle(NB.text1)
                    .frame(width: 44, alignment: .leading)
                Text(note.isEmpty ? "" : L(note))
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
                Text(L(meal.slot.rawValue))
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
                Text(L("%d G PRO", meal.protein))
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
            Text(L("OPEN"))
                .font(NBFont.ui(500, 10)).tracking(0.1 * 10)
                .foregroundStyle(lit ? NB.ember2 : NB.white.opacity(0.28))
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(slot.rawValue))
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
                    Text(L("%@ NOW", Fmt.signedKcal(now)))
                        .font(NBFont.dot(700, 10)).tracking(0.02 * 10)
                        .foregroundStyle(NB.text1)
                        .offset(x: max(0, x(now ?? 0, w) - 22), y: 0)
                    Text(L("%@ EST", Fmt.signedKcal(ifBudget)))
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
                // 0 sits at the bottom, same as the bars. −200 / −500 are absolute and
                // never rescaled; a day past ±800 fills the chart instead of leaving it.
                Rectangle().fill(NB.limeMid.opacity(0.18))
                    .frame(height: h * CGFloat(300 / maxAbs))
                    .offset(y: h * CGFloat((maxAbs - 500) / maxAbs))
                HStack(spacing: 0) {
                    ForEach(values.indices, id: \.self) { i in
                        let inWindow = values[i] <= -200 && values[i] >= -500
                        let isToday = i == values.count - 1
                        let fraction = min(1, abs(values[i]) / maxAbs)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isToday && !todayClosed ? NB.lime2
                                  : (inWindow ? NB.limeMid : Color(hex: 0x3A3A44)))
                            .frame(width: 34, height: max(4, h * CGFloat(fraction)))
                            .frame(height: h, alignment: .bottom)
                        if i < values.count - 1 { Spacer(minLength: 0) }
                    }
                }
                Path { p in
                    for kcal in [200.0, 500.0] {
                        let yy = h * CGFloat(1 - kcal / maxAbs)
                        p.move(to: CGPoint(x: 0, y: yy)); p.addLine(to: CGPoint(x: geo.size.width, y: yy))
                    }
                }
                .stroke(NB.lime2.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            .clipped()
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
                Text(L("KCAL"))
                    .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
            }

            Text(L("EDITING RECOMPUTES THIS USER DAY. RANGE IS THE LAST 7 DAYS."))
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .foregroundStyle(NB.text3Prod)

            Spacer(minLength: 0)

            LimePillButton(title: L("Save")) {
                data.updateMeal(entry.id, kcal: Double(kcal) ?? entry.kcal, text: text)
                dismiss()
            }

            Button {
                data.deleteMeal(entry.id)
                dismiss()
            } label: {
                Text(L("Delete this entry"))
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
