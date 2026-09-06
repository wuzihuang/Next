import SwiftUI

/// 09 / ADR 0014 · calories. DAY is the clock plus one food table; WEEK and MONTH
/// are rolling windows of the same page. LOG A MEAL is an ember state that
/// opens a plate over a pressed-down page.
struct FuelDetailView: View {
    init(focus: UserDay? = nil) { _day = State(initialValue: focus ?? UserDay.containing(Date())) }
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router
    @ObservedObject private var mealQueue = MealQueue.shared

    @State private var plate: FuelPlate?
    /// Paper 09H · DAY / WEEK / MONTH. Default lands on the clock.
    @State private var rangeRaw = RollingPills.day.rawValue
    /// 09 edge 5 · PAST DAY. The page pages back like 10 does; a closed day shows what was
    /// measured and nothing that is still an estimate. Range-limited to 7 user days (F2 §08).
    @State private var day: UserDay = UserDay.containing(Date())
    private var range: RollingPills { .parse(rangeRaw) }
    private var detail: DetailWindow { DetailWindow(.fuel, range) }
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
    /// 09H · a day is closed when its user-day window has ended. Open slots no longer
    /// decide the headline — the list is one flat ledger, not four meal chairs.
    private var closed: Bool { isPast || day.isClosed }
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
        let elapsed = min(Date(), m.day.end).timeIntervalSince(m.day.start) / 3600
        return elapsed > 6 && coverageHours < elapsed * 0.5
    }
    /// 补屏 B rule 07 · NO TARGET is for an account that has never had a weight — not one
    /// whose weight is old (edge 4: a 62-day-old weight is still a denominator).
    private var noTarget: Bool {
        #if DEBUG
        if Band.allowsSeed, ProcessInfo.processInfo.environment["NB_DEBUG_NO_TARGET"] == "1" { return true }
        #endif
        return data.weighIns.isEmpty && m.weightKg == nil && m.targetIn == nil
    }

    var body: some View {
        Group {
            if noTarget { NoTargetFuel() } else { platedPage }
        }
        .safeAreaInset(edge: .bottom) {
            if !mealQueue.rejected.isEmpty { rejectedMeals }
            else if mealQueue.pendingCount > 0, mealQueue.lastError != nil {
                Text(L("Meal changes are saved on this device and waiting to sync."))
                    .font(NBFont.ui(400, 12)).padding(12).background(NB.carbon4)
            }
        }
        .task(id: day) {
            if let owner = SupabaseClient.currentUserIdSnapshot() { mealQueue.refreshStatus(owner: owner) }
            #if DEBUG
            if let override = DetailWindow.debugRange(for: .fuel) {
                rangeRaw = override.rawValue
            }
            #endif
            #if DEBUG
            if ProcessInfo.processInfo.environment["NB_DEBUG_FUEL_PLATE"] == "1" {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { plate = .log }
            }
            #endif
            guard !Band.allowsSeed else { return }
            await Repository.shared.hydrate(detail, endingAt: today, focus: day, into: data)
        }
    }

    private var rejectedMeals: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(mealQueue.rejected) { failure in
                Text(failure.name).font(NBFont.ui(600, 13))
                Text(failure.reason).font(NBFont.ui(400, 12))
                HStack {
                    Button(L("Retry")) { mealQueue.retryRejected(failure.id) }
                    Spacer()
                    Button(L("Remove pending change")) { mealQueue.discardRejected(failure.id, into: data) }
                }
                .font(NBFont.ui(500, 12)).tint(NB.ember1)
            }
        }
        .padding(16).background(NB.carbon4).foregroundStyle(NB.text3Prod)
    }

    private var platedPage: some View {
        ZStack {
            // Black only matters once the card has lifted; at rest the page fills the screen.
            (plate == nil ? NB.carbon : Color.black).ignoresSafeArea()
            fuelPage
                .compositingGroup()
                // ⚠️ The clip is the page's safe-area frame, not the screen. Clipping at rest
                // sheared the bloom off at the status bar and left a black strip above and
                // below the scroll — bars no other detail page has. So at rest the clip shape
                // is pushed far outside the frame and cuts nothing; it tightens to the
                // rounded card only while a plate is up.
                .clipShape(RoundedRectangle(cornerRadius: plate == nil ? 0 : NB.R.panel, style: .continuous)
                    .inset(by: plate == nil ? -400 : 0))
                .overlay {
                    if plate != nil {
                        RoundedRectangle(cornerRadius: NB.R.panel, style: .continuous)
                            .stroke(NB.white.opacity(0.12), lineWidth: 1)
                    }
                }
                .scaleEffect(plate == nil ? 1 : 0.88)
                .shadow(color: Color.black.opacity(plate == nil ? 0 : 0.55), radius: 22, y: 10)
                .allowsHitTesting(plate == nil)
            if let plate {
                FuelPlateLayer(plate: plate, day: day) { self.plate = nil }
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: plate != nil)
    }

    private var fuelPage: some View {
        // ADR 0014 / Paper 09H · DAY is the clock plus one food table. WEEK and MONTH
        // are rolling windows of the same page. LOG A MEAL is an ember state that
        // opens a plate over a pressed-down page — same chrome as Profile sheets.
        DetailScroll(glow: NB.ember1, title: L("CALORIES"), headline: isPast ? pastTitle : nil, trailing: {
            Text(headerPeriod)
                .font(NBFont.dot(600, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.text3Prod)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if isPast, range == .day {
                HStack(spacing: 6) {
                    PagerButton(forward: false, enabled: day > today.adding(days: -6)) { withAnimation { day = day.adding(days: -1) } }
                    PagerButton(forward: true, enabled: isPast) { withAnimation { day = day.adding(days: 1) } }
                }
                .padding(.leading, 10)
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                SegmentedPills(options: RollingPills.words,
                               selection: $rangeRaw)
                switch range {
                case .day:   dayBoard
                case .week:  weekBoard
                case .month: monthBoard
                }
                if !isPast {
                    FastingAction(day: day)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            if isPast { withAnimation { day = today } } else { router.backToRoot() }
        }
    }

    private var headerPeriod: String {
        switch range {
        case .day:   return isPast ? pastTitle : Fmt.clock(Date())
        case .week:  return L(DetailWindow(.fuel, .week).periodKey)
        case .month: return L(DetailWindow(.fuel, .month).periodKey)
        }
    }

    private var dayBoard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("THE DAY SO FAR"))
                        .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                        .foregroundStyle(NB.ember1)
                    Spacer(minLength: 0)
                    Text(dayFoot)
                        .font(NBFont.ui(500, 11)).tracking(0.06 * 11)
                        .foregroundStyle(NB.ember1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("IN"))
                            .font(NBFont.ui(500, 10)).tracking(0.12 * 10)
                            .foregroundStyle(NB.text3Prod)
                        Text(Fmt.kcal(m.eIn))
                            .font(NBFont.dot(700, 36)).tracking(-0.02 * 36)
                            .foregroundStyle(logged ? NB.ember1 : NB.text3Prod)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("OUT"))
                            .font(NBFont.ui(500, 10)).tracking(0.12 * 10)
                            .foregroundStyle(NB.text3Prod)
                        Text(outUnknown ? Fmt.dash : Fmt.kcal(m.eOutNow))
                            .font(NBFont.dot(700, 36)).tracking(-0.02 * 36)
                            .foregroundStyle(logged && !outUnknown ? NB.cyan1 : NB.text3Prod)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(L("DIFF"))
                            .font(NBFont.ui(500, 10)).tracking(0.12 * 10)
                            .foregroundStyle(NB.text3Prod)
                        Text(outUnknown ? Fmt.dash : Fmt.signedKcal(m.balance))
                            .font(NBFont.dot(700, 22)).tracking(-0.01 * 22)
                            .foregroundStyle(gapTint(m.balance))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                FuelDayChart(meals: dayMeals.map { ($0.at, $0.kcal) },
                             burnedNow: outUnknown ? nil : m.eOutNow,
                             restingNow: m.bmr,
                             burnedAt: min(day.end, m.asOf ?? Date()),
                             burnedFull: isPast ? m.eOutNow : m.eOutFull,
                             budget: m.targetIn,
                             now: isPast ? day.end : Date(),
                             dayStart: day.start,
                             happenedIntake: m.eIn ?? 0,
                             burnTicks: dayBurnTicks,
                             outUnknown: outUnknown)
                if let budget = m.targetIn {
                    Text(L("BUDGET %@", Fmt.kcal(budget)))
                        .font(NBFont.dot(500, 10)).tracking(0.08 * 10)
                        .foregroundStyle(NB.white.opacity(0.34))
                }
                Text(L("Solid already happened. Dashed is the usual rhythm."))
                    .font(NBFont.ui(400, 11)).tracking(0.02 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            .padding(16)
            .frame(width: NB.Layout.contentWidth, alignment: .leading)
            .cardSkin()

            FuelFoodTable(meals: dayMeals, trailing: Fmt.kcal(m.eIn)) { meal in
                if data.canEdit(meal) {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { plate = .edit(meal) }
                }
            }
        }
    }

    private var weekBoard: some View {
        let days = weekFacts
        let total = FuelWindowMath.sum(days)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("THIS WEEK"))
                        .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                        .foregroundStyle(NB.text3Prod)
                    Spacer(minLength: 0)
                    Text(weekSpan(days))
                        .font(NBFont.ui(500, 11)).tracking(0.06 * 11)
                        .foregroundStyle(NB.ember1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                FuelStackedHero(intake: Fmt.kcal(total?.intake),
                                burned: Fmt.kcal(total?.burned),
                                gap: Fmt.signedKcal(total?.gap),
                                gapTint: gapTint(total?.gap))
                if let budget = m.targetIn {
                    Text(L("BUDGET %@", Fmt.kcal(budget)))
                        .font(NBFont.dot(500, 10)).tracking(0.08 * 10)
                        .foregroundStyle(NB.white.opacity(0.34))
                }
                FuelWeekBars(days: days, budget: m.targetIn)
                Text(L("Known days: IN %d · OUT %d · DIFF %d", total?.intakeDays ?? 0,
                       total?.burnedDays ?? 0, total?.pairedDays ?? 0))
                    .font(NBFont.ui(400, 11)).tracking(0.02 * 11)
                    .foregroundStyle(NB.text3Prod)
                Text(L("DIFF only includes days with both intake and burn recorded."))
                    .font(NBFont.ui(400, 11)).tracking(0.02 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            .padding(16)
            .frame(width: NB.Layout.contentWidth, alignment: .leading)
            .cardSkin()

            FuelLedgerTable(
                title: L("DAYS"),
                trailing: L("%d DAYS · %d OPEN", days.count, days.filter(\.isOpen).count),
                dayHeader: L("DAY"),
                rows: days.map(weekRow),
                footer: total.map {
                    FuelLedgerRow(id: "week-total", title: L("WEEK"),
                                  intake: Fmt.kcal($0.intake), burned: Fmt.kcal($0.burned),
                                  gap: Fmt.signedKcal($0.gap), gapTint: gapTint($0.gap))
                })
        }
    }

    private var monthBoard: some View {
        let days = monthFacts
        let rolls = FuelWindowMath.weekRolls(days)
        let typical = FuelWindowMath.typicalDay(rolls)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("A TYPICAL DAY"))
                        .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                        .foregroundStyle(NB.text3Prod)
                    Spacer(minLength: 0)
                    Text(L("PER DAY"))
                        .font(NBFont.ui(500, 11)).tracking(0.06 * 11)
                        .foregroundStyle(NB.ember1)
                }
                FuelStackedHero(intake: Fmt.kcal(typical?.intake),
                                burned: Fmt.kcal(typical?.burned),
                                gap: Fmt.signedKcal(typical?.gap),
                                gapTint: gapTint(typical?.gap))
                if let budget = m.targetIn {
                    Text(L("BUDGET %@", Fmt.kcal(budget)))
                        .font(NBFont.dot(500, 10)).tracking(0.08 * 10)
                        .foregroundStyle(NB.white.opacity(0.34))
                }
                FuelMonthBars(days: days, budget: m.targetIn)
                Text(L("Complete days: IN %d · OUT %d · DIFF %d", typical?.intakeDays ?? 0,
                       typical?.burnedDays ?? 0, typical?.pairedDays ?? 0))
                    .font(NBFont.ui(400, 11)).tracking(0.02 * 11)
                    .foregroundStyle(NB.text3Prod)
                Text(L("DIFF only includes days with both intake and burn recorded."))
                    .font(NBFont.ui(400, 11)).tracking(0.02 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            .padding(16)
            .frame(width: NB.Layout.contentWidth, alignment: .leading)
            .cardSkin()

            FuelLedgerTable(
                title: L("WEEKS"),
                trailing: L("PER DAY"),
                dayHeader: L("WEEK"),
                rows: rolls.enumerated().map { monthRow($0.element, newest: $0.offset == 0) },
                footer: typical.map {
                    FuelLedgerRow(id: "typical", title: L("TYPICAL DAY"),
                                  intake: Fmt.kcal($0.intake), burned: Fmt.kcal($0.burned),
                                  gap: Fmt.signedKcal($0.gap), gapTint: gapTint($0.gap))
                })
        }
    }

    private var dayFoot: String {
        if m.fuelState == .fasted { return L("Recorded: nothing eaten today") }
        if isPast { return logged ? L("CLOSED") : L("NOTHING LOGGED") }
        if !logged { return L("NOTHING LOGGED YET") }
        let n = dayMeals.count
        if closed { return n == 1 ? L("%d MEAL", n) : L("%d MEALS", n) }
        return n == 1 ? L("%d MEAL · NOT CLOSED", n) : L("%d MEALS · NOT CLOSED", n)
    }

    /// Five-minute steps on this user day. The cyan line uses them so a walk is
    /// steeper than sitting — not a ruler from 04:00 to now.
    private var dayBurnTicks: [VitalSample] {
        let curve = data.history.first(where: { $0.day == day && !$0.vitalsCurve.isEmpty })?.vitalsCurve
            ?? m.vitalsCurve
        return curve
    }

    private var weekFacts: [FuelDayFacts] {
        facts(endingAt: today, count: DetailWindow(.fuel, .week).days)
    }

    private var monthFacts: [FuelDayFacts] {
        facts(endingAt: today, count: DetailWindow(.fuel, .month).days)
    }

    private func facts(endingAt end: UserDay, count: Int) -> [FuelDayFacts] {
        end.rollingBack(count).map { slot in
            let row = data.history.first { $0.day == slot } ?? (slot == data.today.day ? data.today : nil)
            let meals = (data.meals + data.recentMeals).filter { $0.day == slot && $0.status == .confirmed }
            let unique = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values
            let fasted = row?.fuelState == .fasted
            let intake = row?.eIn ?? (unique.isEmpty ? (fasted ? 0 : nil) : unique.reduce(0) { $0 + $1.kcal })
            return FuelDayFacts(
                day: slot,
                intake: intake,
                burned: row?.eOutNow,
                foodCount: unique.count,
                isFasted: fasted,
                isOpen: slot == today && (row?.fuelState == .unlogged || !slot.isClosed))
        }
    }

    private func weekRow(_ fact: FuelDayFacts) -> FuelLedgerRow {
        let caption: String
        let captionTint: Color
        if fact.day == today {
            caption = L("TODAY"); captionTint = NB.ember1
        } else if fact.isFasted {
            caption = L("FASTED"); captionTint = NB.text3Prod
        } else if fact.foodCount == 0 {
            caption = fact.intake == nil ? Fmt.dash : L("LOGGED")
            captionTint = NB.text3Prod
        } else {
            caption = fact.foodCount == 1 ? L("%d MEAL", fact.foodCount) : L("%d MEALS", fact.foodCount)
            captionTint = NB.text3Prod
        }
        return FuelLedgerRow(
            id: fact.day.key,
            title: Fmt.displayDate(fact.day.date, format: "EEE d").uppercased(),
            caption: caption,
            captionTint: captionTint,
            intake: Fmt.kcal(fact.intake),
            burned: Fmt.kcal(fact.burned),
            gap: Fmt.signedKcal(fact.gap),
            gapTint: gapTint(fact.gap))
    }

    private func monthRow(_ roll: FuelWeekRoll, newest: Bool) -> FuelLedgerRow {
        let span = weekSpan(from: roll.start, to: roll.end)
        return FuelLedgerRow(
            id: roll.start.key,
            title: newest ? L("THIS WEEK") : span,
            caption: L("IN %d days\nOUT %d days\nDIFF %d days", roll.intakeDays,
                       roll.burnedDays, roll.pairedDays),
            captionTint: newest ? NB.ember1 : NB.text3Prod,
            intake: Fmt.kcal(roll.avgIn),
            burned: Fmt.kcal(roll.avgOut),
            gap: Fmt.signedKcal(roll.avgGap),
            gapTint: gapTint(roll.avgGap))
    }

    private func weekSpan(_ days: [FuelDayFacts]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        return weekSpan(from: first.day, to: last.day)
    }

    private func weekSpan(from: UserDay, to: UserDay) -> String {
        let left = Fmt.displayDate(from.date, format: "d MMM").uppercased()
        let right = Fmt.displayDate(to.date, format: "d MMM").uppercased()
        return "\(left) — \(right)"
    }

    private func gapTint(_ gap: Double?) -> Color {
        guard let gap else { return NB.text3Prod }
        return gap > 0 ? NB.lime2 : NB.cyan1
    }
}

// MARK: rows

struct MacroDetailRow: View {
    let name: String
    let slot: MacroSlot?
    let tint: Color
    let note: String
    var intake: Int? = nil
    var logged: Bool = false

    private var macroValue: String {
        guard let s = slot else { return intake.map { "\($0) g" } ?? Fmt.dash }
        return logged || s.eaten > 0 ? "\(s.eaten)/\(s.target)" : "—/\(s.target)"
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



/// F0 right column · "改一笔／删一笔". Same plate chrome as Profile / Log a meal.
struct EditMealSheet: View {
    let entry: MealEntry
    var onClose: () -> Void
    @EnvironmentObject private var data: DataStore

    @State private var text = ""
    @State private var kcal = ""

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (Double(kcal) ?? 0) > 0
    }

    var body: some View {
        SheetFrame(title: L("Edit this meal"), fillsHeight: false) {
            VStack(spacing: 10) {
                HStack {
                    Text(L(entry.slot.rawValue))
                        .font(NBFont.ui(500, 13))
                        .foregroundStyle(NB.text3Prod)
                    Spacer(minLength: 0)
                    Text(Fmt.clock(entry.at))
                        .font(NBFont.dot(600, 11)).tracking(0.12 * 11)
                        .foregroundStyle(NB.ember1)
                }
                FieldBox(label: L("What you ate"), text: $text)
                FieldBox(label: L("KCAL"), text: $kcal, keyboard: .numberPad)
            }
            Text(L("This recomputes the user day. Range is the last 7 days."))
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(NB.white.opacity(0.38))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } footer: {
            VStack(spacing: 14) {
                LimePillButton(title: L("Save"), enabled: canSave) {
                    data.amendMeal(entry.id, kcal: Double(kcal) ?? entry.kcal, text: text)
                    onClose()
                }
                Button {
                    data.deleteMeal(entry.id)
                    onClose()
                } label: {
                    Text(L("Delete this entry"))
                        .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                        .foregroundStyle(NB.alert2)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, max(8, Chrome.homeIndicatorBlock - 8))
        .onAppear { text = entry.text; kcal = String(Int(entry.kcal)) }
    }
}
