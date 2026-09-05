import SwiftUI

/// 10 · 成分详情 Composition. Entered from a panel widget (recomp / delta / dual) or from a
/// heat-map cell in Profile, which is why it carries a date and a pager. Back returns to
/// wherever it came from — one layer, never two.
struct CompositionDetailView: View {
    let focus: Date?

    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router
    @ObservedObject private var queue = WeighInQueue.shared

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
    private var hasCall: Bool { m.fatEmaDelta7d != nil && m.leanEmaDelta7d != nil && m.scans7d >= 5 && staleDays < 7 }

    /// 10 edge 1 · a source that stopped: frozen at its last reading and dated, never
    /// extrapolated. Confidence down a tier after three days, NO CALL on the seventh.
    private var staleDays: Int {
        if DebugEdge.on("frozen") { return 4 }
        guard let last = data.weighIns.first?.date else { return 0 }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
    }
    private var frozen: Bool { staleDays >= 3 }
    private var lastReadLabel: String {
        return Fmt.displayDate(data.weighIns.first?.date ?? Date(), format: "MMM d").uppercased()
    }
    /// 10 edge 3 · a day-over-day jump is shown, stored and marked — deleting it would be
    /// editing the facts for the user.
    private var weightDelta1d: Double? {
        if DebugEdge.on("outlier") { return 1.4 }
        guard let now = m.weightKg,
              let then = data.history.first(where: { $0.day == m.day.adding(days: -1) })?.weightKg
        else { return nil }
        return now - then
    }
    private var spike: Bool { (weightDelta1d.map { abs($0) >= 1.0 }) ?? false }
    /// 10 edge 2 · a real body-composition reading re-anchors the series from that day.
    private var measuredComposition: Bool {
        if DebugEdge.on("measured") { return true }
        guard let w = data.weighIns.first else { return false }
        return w.bodyFatPercent != nil && Calendar.current.isDate(w.date, inSameDayAs: Date())
    }
    private var previousFatKg: Double? {
        data.history.first(where: { $0.day == m.day.adding(days: -1) })?.fatKg
    }
    /// 10 edge 4 · 「2/4 就写 2/4」, and say which two.
    private var splitSentence: String? {
        guard hasCall, !isWeek else { return nil }
        let s = signals
        guard s.filter(\.lit).count < 4 else { return nil }
        func word(_ v: Double?) -> String {
            guard let v else { return L("FLAT") }
            return abs(v) < 0.05 ? L("FLAT") : v < 0 ? L("DOWN") : L("UP")
        }
        let fat = word(m.fatEmaDelta7d), lean = word(m.leanEmaDelta7d)
        let trends = fat == lean
            ? L("FAT IS %@, LEAN IS TOO.", fat)
            : L("FAT IS %@, LEAN IS %@.", fat, lean)
        let off = s.dropFirst(2).filter { !$0.lit }.map { $0.name == "PROTEIN INTAKE" ? L("PROTEIN") : L("BALANCE") }
        guard !off.isEmpty else { return trends }
        return L("%@ %@ %@.", trends, off.joined(separator: L(" AND ")),
                 off.count == 1 ? L("DISAGREES") : L("DISAGREE"))
    }

    private var call: TheCall? {
        guard hasCall else { return nil }
        if let settled = m.serverCall { return settled }
        guard let f = m.fatEmaDelta7d, let l = m.leanEmaDelta7d else { return nil }
        return TheCall.from(fatDelta7d: f, leanDelta7d: l)
    }

    var body: some View {
        // 10 · the board drew `‹ COMPOSITION` as the page's back mark; the day is the headline.
        DetailScroll(glow: NB.lime1, title: L("COMPOSITION"), headline: titleText, trailing: {
            HStack(spacing: 6) {
                PagerButton(forward: false, enabled: true) { day = day.adding(days: -1) }
                PagerButton(forward: true, enabled: day < UserDay.containing(Date())) {
                    day = day.adding(days: 1)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                // ⚠️ 18FW · "DAY 与 WEEK 都有真屏，MONTH 没有，别把它当已设计." Two segments,
                // not three — this is the one page whose week view the boards actually drew.
                SegmentedPills(options: ["DAY", "WEEK"], selection: $range)
                callCard
                thatWeekCard
                if hasCall { whyCard } else { needsCard }
                SectionLabel(L("EVIDENCE"))
                weighInCard
                if hasCall {
                    energyCard
                    macrosCard
                    foodCard
                    trainingCard
                } else {
                    gates
                    LimePillButton(title: L("Add a weigh-in")) { router.sheet = .weighIn }
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            router.backToRoot()
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["NB_DEBUG_COMP_RANGE"] == "WEEK" {
                range = "WEEK"
            }
            #endif
            await Analytics.shared.track("COMP_DETAIL_OPEN", [
                "CALL": call?.rawValue ?? "NO_CALL",
                "CONFIDENCE": m.confidence.rawValue,
                "SCANS_7D": m.scans7d,
            ])
        }
    }

    private var titleText: String {
        Fmt.displayDate(day.start, format: "EEE · MMM d").uppercased()
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
                        Text(L(call?.rawValue ?? "NO CALL"))
                            .font(NBFont.brand(700, 26)).tracking(-0.02 * 26)
                            .foregroundStyle(NB.text1)
                        Text(hasCall ? L("ESTIMATE") : L("PENDING"))
                            .font(NBFont.ui(500, 11)).tracking(0.14 * 11)
                            .foregroundStyle(Color(hex: 0x9A9AA6))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .overlay(Capsule().stroke(NB.white.opacity(0.12), lineWidth: 1))
                    }
                    Text(hasCall
                         ? L("FAT %@ KG · LEAN %@ KG · 7D", Fmt.signedKg(m.fatEmaDelta7d), Fmt.signedKg(m.leanEmaDelta7d))
                         : L("FAT %@ · LEAN %@ · NEEDS 5 OF 7 DAYS", Fmt.dash, Fmt.dash))
                        .font(NBFont.dot(500, 11)).tracking(0.04 * 11)
                        .foregroundStyle(NB.macroValue)
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(NB.barTrack).frame(height: 1)
            HStack {
                HStack(spacing: 9) {
                    Text(L("CONFIDENCE"))
                        .font(NBFont.ui(500, 11)).tracking(0.12 * 11)
                        .foregroundStyle(NB.text3Prod)
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule()
                                .fill(i < tierIndex ? NB.lime1 : NB.white.opacity(0.10))
                                .frame(width: 16, height: 4)
                        }
                    }
                    Text(L(m.confidence.rawValue))
                        .font(NBFont.dot(700, 11)).tracking(0.04 * 11)
                        .foregroundStyle(hasCall ? NB.lime1 : NB.text3Prod)
                }
                Spacer(minLength: 0)
                // ⚠️ Never an unqualified fraction: the screen must say what it is counting.
                Text(L("%d/7 DAYS MEASURED", m.scans7d))
                    .font(NBFont.dot(500, 11)).tracking(0.04 * 11)
                    .foregroundStyle(Color(hex: 0x8A8A96))
            }
            if let s = splitSentence {
                Text(s)
                    .font(NBFont.ui(300, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
    }

    // MARK: 19VV · the week window
    //
    // ⚠️ 19YC · "WEEK 不是另一个页面：卡片顺序、卡片标题、CTA 的位置全不变，只换数据窗口和
    // 每张卡右上角那行限定词." The qualifier is a required field, not decoration: 2,240 as a
    // daily average and 2,240 as a weekly total differ by seven, and a card that forgets to
    // say which one it is, is simply wrong.

    private var isWeek: Bool { range == "WEEK" }

    /// The seven days ending on the shown day, or just that day.
    private var window: [DailyMetrics] {
        guard isWeek else { return [m] }
        return weekDays.compactMap { d in
            d == UserDay.containing(Date()) ? data.today : data.history.first { $0.day == d }
        }
    }

    /// Days in the window with any food logged. 19YI · this coverage has to be visible:
    /// a 6/7 week and a 7/7 week are not the same confidence.
    private var loggedDays: Int {
        window.filter { if case .unlogged = $0.fuelState { return false } else { return true } }.count
    }

    private func avg(_ pick: (DailyMetrics) -> Double?) -> Double? {
        let xs = window.compactMap(pick)
        return xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    private var tierIndex: Int { max(0, baseTierIndex - (frozen ? 1 : 0)) }
    private var baseTierIndex: Int {
        switch m.confidence { case .pending: 1; case .medium: 2; case .high: 3 }
    }

    /// F0 rule 05 · seven cells coloured by Daily Direction, not by the quadrant.
    private var thatWeekCard: some View {
        // 19YI · the same seven cells, renamed, with coverage in place of the date range.
        let late = backfilled
        return CardBlock(title: isWeek ? L("DAILY BREAKDOWN") : L("THAT WEEK"),
                  trailing: !late.isEmpty && !isWeek
                          ? (late.count == 1 ? L("%d DAY RECALCULATED", late.count) : L("%d DAYS RECALCULATED", late.count))
                          : isWeek ? L("%d OF 7 LOGGED", loggedDays) : weekLabel,
                  trailingIsDot: true,
                  trailingTint: !late.isEmpty && !isWeek ? NB.ember1.opacity(0.85) : nil) {
            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { d in
                    let metrics = data.metrics(for: d)
                    VStack(spacing: 7) {
                        DirectionCell(direction: metrics?.direction ?? .greyNothing,
                                      today: d == day, height: 34)
                            // 10 edge 5 · a recoloured cell is marked, so the receipt names it.
                            .overlay(late.contains(d) ? RoundedRectangle(cornerRadius: 6).stroke(NB.ember1.opacity(0.85), lineWidth: 1) : nil)
                        Text(dayNumber(d))
                            .font(NBFont.dot(d == day ? 700 : 500, 11))
                            .foregroundStyle(d == day ? NB.text1 : late.contains(d) ? NB.ember1.opacity(0.85) : Color(hex: 0x8A8A96))
                    }
                }
            }
            if !late.isEmpty, !isWeek {
                EvidenceNote(L("YOU LOGGED %@ LATE. %@ CHANGED.", rangeLabel(late), countWord(late.count)))
            }
        }
    }

    /// 10 edge 5 · BACKFILL. A day whose row was recomputed well after the day closed — more
    /// than two days later — and recently, is a day that changed because something was
    /// logged late. 10 rule 09: any call change needs a visible receipt naming the signal.
    private var backfilled: [UserDay] {
        let week = weekDays
        if DebugEdge.on("backfill") {
            return Array(week.filter { $0 < UserDay.containing(Date()).adding(days: -1) }.prefix(3))
        }
        // The signal is a meal logged after the day had closed, and a row recomputed after
        // that log. `computed_at` alone is not enough: the nightly recompute touches every row.
        let now = Date()
        return week.filter { d in
            let closedAt = d.adding(days: 1).start
            let late = data.recentMeals.filter { $0.day == d && $0.at > closedAt.addingTimeInterval(4 * 3600) }
            guard let lastLate = late.map(\.at).max(),
                  let row = data.history.first(where: { $0.day == d }), let at = row.asOf else { return false }
            return at >= lastLate && now.timeIntervalSince(lastLate) < 48 * 3600
        }
    }
    private func rangeLabel(_ days: [UserDay]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        if days.count == 1 { return Fmt.displayDate(first.start, format: "MMM d").uppercased() }
        let contiguous = zip(days, days.dropFirst()).allSatisfy { $1 == $0.adding(days: 1) }
        let sameMonth = Calendar.current.isDate(first.start, equalTo: last.start, toGranularity: .month)
        if contiguous && sameMonth { return "\(Fmt.displayDate(first.start, format: "MMM d").uppercased())–\(dayNumber(last))" }
        return days.map { Fmt.displayDate($0.start, format: "MMM d").uppercased() }.joined(separator: ", ")
    }
    private func countWord(_ n: Int) -> String {
        let words = ["", "THAT DAY", "THOSE TWO DAYS", "THOSE THREE DAYS", "THOSE FOUR DAYS", "THOSE FIVE DAYS", "THOSE SIX DAYS", "THOSE SEVEN DAYS"]
        return n < words.count ? L(words[n]) : L("THOSE %d DAYS", n)
    }

    private var weekDays: [UserDay] {
        let weekday = Calendar.current.component(.weekday, from: day.start)
        let start = day.adding(days: -(weekday - 1))
        return (0..<7).map { start.adding(days: $0) }
    }
    private var weekLabel: String {
        "\(Fmt.displayDate(weekDays.first!.start, format: "MMM d").uppercased()) — \(dayNumber(weekDays.last!))"
    }
    private func dayNumber(_ d: UserDay) -> String {
        "\(Calendar.current.component(.day, from: d.start))"
    }

    /// Four signals. The card header says how many agree; the dots are lime only when
    /// that signal clears its own threshold.
    private var whyCard: some View {
        let s = signals
        return CardBlock(title: L("WHY %@", L(call?.rawValue ?? "")),
                         trailing: L("%d/4 SIGNALS AGREE", s.filter(\.lit).count), trailingIsDot: true) {
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
    /// ⚠️ 19YF · DAY's four signals are measured against fixed thresholds; WEEK's are
    /// measured against the week before. So the same "4/4 SIGNALS AGREE" says two different
    /// things — DAY means "today's four all point at RECOMP", WEEK means "this week is more
    /// RECOMP than last week" — and the qualifier on each row is what tells them apart.
    private var previousWeek: [DailyMetrics] {
        weekDays.compactMap { d in data.history.first { $0.day == d.adding(days: -7) } }
    }

    private func weekAvg(_ days: [DailyMetrics], _ pick: (DailyMetrics) -> Double?) -> Double? {
        let xs = days.compactMap(pick)
        return xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    private var signals: [(name: String, value: String, note: String, lit: Bool)] {
        if isWeek { return weekSignals }
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
            ("FAT MASS TREND", L("%@ KG", Fmt.signedKg(fat)),
             fatLit ? L("7D EMA · CLEARS THE ±0.15 KG THRESHOLD")
                    : L("7D EMA · INSIDE THE ±0.15 KG THRESHOLD"), fatLit),
            ("LEAN MASS TREND", L("%@ KG", Fmt.signedKg(lean)),
             leanLit ? L("7D EMA · CLEARS THE ±0.10 KG THRESHOLD")
                     : L("7D EMA · INSIDE THE ±0.10 KG THRESHOLD"), leanLit),
            ("PROTEIN INTAKE",
             avgPerKg.map { L("%.1f G/KG", $0) } ?? Fmt.dash,
             L("%d OF %d DAYS AT OR ABOVE 1.8 G/KG", hitDays, perKg.count), hitDays >= 4),
            ("ENERGY BALANCE", L("%@ KCAL", Fmt.signedKcal(avgBalance)),
             inWindow ? L("INSIDE THE −200 TO −500 RECOMP WINDOW")
                      : L("OUTSIDE THE −200 TO −500 RECOMP WINDOW"), inWindow),
        ]
    }

    private var weekSignals: [(name: String, value: String, note: String, lit: Bool)] {
        let prev = previousWeek
        // ⚠️ The value on a week row is the *change*, not the level. Printing the level
        // beside "VS LAST WEEK" gave "+64.56 KG" for lean mass, which reads as a week's gain
        // and is actually the body. 19QO/19QW keep the delta on the left and the bar it has
        // or has not cleared on the right.
        func compare(_ label: String, _ pick: (DailyMetrics) -> Double?, bar: Double?,
                     lowerIsBetter: Bool, format: (Double?) -> String)
            -> (name: String, value: String, note: String, lit: Bool) {
            let now = weekAvg(window, pick)
            let then = weekAvg(prev, pick)
            guard let now, let then else {
                return (label, Fmt.dash, L("NO PREVIOUS WEEK TO COMPARE"), false)
            }
            let delta = now - then
            let moved = lowerIsBetter ? delta < 0 : delta > 0
            guard let bar else {
                return (label, format(delta),
                        moved ? L("VS LAST WEEK · MOVING THE RIGHT WAY")
                              : L("VS LAST WEEK · MOVING THE OTHER WAY"),
                        moved)
            }
            let cleared = moved && abs(delta) > bar
            return (label, format(delta),
                    cleared
                        ? L("VS LAST WEEK · CLEARS THE ±%@ BAR", String(format: "%.2f", bar))
                        : L("VS LAST WEEK · INSIDE THE ±%@ BAR", String(format: "%.2f", bar)),
                    cleared)
        }
        return [
            compare("FAT MASS TREND", { $0.fatKg }, bar: TheCall.fatBand,
                    lowerIsBetter: true) { "\(Fmt.signedKg($0)) KG" },
            compare("LEAN MASS TREND", { $0.leanKg }, bar: TheCall.leanBand,
                    lowerIsBetter: false) { "\(Fmt.signedKg($0)) KG" },
            compare("PROTEIN INTAKE", { d in
                guard let p = d.proteinIn, let kg = d.weightKg, kg > 0 else { return nil }
                return Double(p) / kg
            }, bar: nil, lowerIsBetter: false) { $0.map { String(format: "%+.1f G/KG", $0) } ?? Fmt.dash },
            compare("ENERGY BALANCE", { $0.balance }, bar: nil,
                    lowerIsBetter: true) { Fmt.signedKcal($0) + " KCAL" },
        ]
    }

    private var needsCard: some View {
        CardBlock(title: L("WHAT IT NEEDS"), trailing: L("%d OF 5 SIGNALS READY", m.scans7d)) {
            VStack(alignment: .leading, spacing: 14) {
                SignalRow(lit: false, name: "FAT MASS TREND", value: Fmt.dash,
                          note: L("NEEDS A WEIGH-IN BEFORE A TREND EXISTS"))
                SignalRow(lit: false, name: "LEAN MASS TREND", value: Fmt.dash,
                          note: L("NEEDS A WEIGH-IN BEFORE A TREND EXISTS"))
                SignalRow(lit: false, name: "PROTEIN INTAKE", value: Fmt.dash,
                          note: L("NEEDS FOOD LOGGED ON THE SAME DAY"))
                SignalRow(lit: false, name: "ENERGY BALANCE", value: Fmt.dash,
                          note: L("NEEDS BOTH INTAKE AND BURN ON THE SAME DAY"))
            }
            Hairline()
            VStack(alignment: .leading, spacing: 6) {
                Text(L("HOW THIS IS DERIVED"))
                    .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                    .foregroundStyle(NB.text3Prod)
                Text(L("One weigh-in swings ±0.8 kg on water alone, so no single morning ever sets a quadrant. The call comes from a 7-day exponential average and needs at least 5 measured days — below that its square stays grey."))
                    .font(NBFont.brand(400, 12.5))
                    .lineSpacing(5)
                    .foregroundStyle(NB.text2)
            }
            // ⚠️ RECOMP is inferred from body metrics: a direction, not a diagnosis.
            Text(L("RECOMP IS INFERRED FROM YOUR BODY METRICS — A DIRECTION, NOT A DIAGNOSIS."))
                .font(NBFont.ui(400, 10.5)).tracking(0.06 * 10.5)
                .foregroundStyle(NB.text3Prod)
        }
    }

    /// F0 rule 09 · every field is tagged at source. Band BIA is MEASURED and re-anchors the
    /// EMA; weight × body-fat % is DERIVED.
    ///
    /// ⚠️ This card was titled SCALE. F6 §05 settles D06 the other way: weight comes from Apple
    /// Health or from a weigh-in the user types, and 「V1 里没有秤这个设备，任何屏上不许出现它」.
    /// The trailing line already read APPLE HEALTH while the title said SCALE, which named a
    /// device this product does not have — on the one page whose whole job is saying where each
    /// number came from.
    private var weighInCard: some View {
        CardBlock(title: L("WEIGH-IN"),
                  trailing: notSynced ? L("SAVED · NOT SYNCED") : frozen ? L("LAST READ %@", lastReadLabel) : spike ? L("OUTLIER · KEPT") : sourceLine,
                  trailingIsDot: true,
                  trailingTint: (notSynced || frozen || spike) ? NB.ember1.opacity(0.85) : nil) {
            // 10S rule 07 · the composition page's top row is one of the two ways in.
            Button { router.sheet = .weighIn } label: {
                HStack(spacing: 10) {
                    EvidenceStat(label: L("WEIGHT"), value: Fmt.kg(m.weightKg), unit: frozen ? L("KG · FROZEN") : "KG",
                                 delta: spike ? L("%@ IN A DAY", Fmt.signedKg(weightDelta1d)) : L("%@ VS 7D", Fmt.signedKg(weightDelta7d)),
                                 deltaTint: spike ? NB.ember1.opacity(0.85) : NB.macroValue)
                    EvidenceStat(label: L("FAT MASS"), value: Fmt.kg(m.fatKg), unit: "KG",
                                 delta: L("%@ VS 7D", Fmt.signedKg(m.fatEmaDelta7d)), deltaTint: NB.lime1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Add a weigh-in"))
            Rectangle().fill(NB.barTrack).frame(height: 1)
            HStack(spacing: 10) {
                EvidenceStat(label: L("LEAN MASS"), value: Fmt.kg(m.leanKg), unit: "KG",
                             delta: L("%@ VS 7D", Fmt.signedKg(m.leanEmaDelta7d)), deltaTint: NB.lime1)
                EvidenceStat(label: L("BODY FAT"), value: bodyFatPercent, unit: "%",
                             delta: L("%@ VS 7D", Fmt.signedKg(bodyFatDelta7d)), deltaTint: NB.lime1)
            }
            Rectangle().fill(NB.barTrack).frame(height: 1)
            VStack(alignment: .leading, spacing: 9) {
                SourceLegend(measured: true, label: L("MEASURED"),
                             fields: measuredComposition ? L("WEIGHT · BODY FAT % · FAT MASS · LEAN MASS") : L("WEIGHT · BODY FAT %"))
                SourceLegend(measured: false, label: L("DERIVED"),
                             fields: measuredComposition ? L("NOTHING TODAY") : L("FAT MASS · LEAN MASS"))
                // 10 edges · the note under the legend is the receipt: what changed, and why.
                // 10S edge 4 · the row is here and counted; the server has not seen it yet.
                if notSynced {
                    EvidenceNote(L("IT'LL GO UP LATER"))
                }
                if frozen {
                    EvidenceNote(L("NOTHING NEW SINCE %@.", lastReadLabel))
                }
                if spike {
                    EvidenceNote((weightDelta7d.map { abs($0) < 0.5 }) ?? true
                                 ? L("THE 7-DAY AVERAGE BARELY MOVED.")
                                 : L("THE 7-DAY AVERAGE MOVED %@ KG.", Fmt.signedKg(weightDelta7d)))
                }
                if measuredComposition {
                    EvidenceNote(previousFatKg.map { L("ESTIMATE WAS %@ · THE SERIES RE-ANCHORS FROM HERE", Fmt.kg($0)) }
                                 ?? L("MEASURED TODAY · THE SERIES RE-ANCHORS FROM HERE"))
                }
            }
        }
    }

    /// 10S edge 4 · OFFLINE: the latest weigh-in is still in the queue.
    private var notSynced: Bool {
        guard let w = data.weighIns.first else { return false }
        return queue.isPending(w.id)
    }
    private var sourceLine: String {
        guard let w = data.weighIns.first else { return L("NO SOURCE CONNECTED") }
        return "\(w.origin.rawValue)  ·  \(Fmt.clock(w.date))"
    }
    /// Both deltas are against the same seven-day window the two mass trends use, so the
    /// four rows on this card are the same comparison read four ways.
    private var weightDelta7d: Double? {
        guard let now = m.weightKg,
              let then = data.history.first(where: { $0.day == m.day.adding(days: -7) })?.weightKg
        else { return nil }
        return now - then
    }
    private var bodyFatDelta7d: Double? {
        guard let f = m.fatEmaDelta7d, let w = m.weightKg, w > 0 else { return nil }
        return f / w * 100
    }

    private var bodyFatPercent: String {
        guard let f = m.fatKg, let w = m.weightKg, w > 0 else { return Fmt.dash }
        return String(format: "%.1f", f / w * 100)
    }

    private var energyCard: some View {
        let kIn = avg(\.eIn), kOut = avg(\.eOutNow), bal = avg(\.balance)
        return CardBlock(title: L("ENERGY"),
                         trailing: isWeek ? L("DAILY AVERAGE · %d OF 7 LOGGED", loggedDays)
                                          : L("LOGGED %d MEALS", windowMeals.count),
                         trailingIsDot: true) {
            HStack(spacing: 10) {
                BalanceStat(label: L("IN"), value: Fmt.kcal(kIn), tint: NB.ember1)
                BalanceStat(label: L("OUT"), value: Fmt.kcal(kOut), tint: NB.cyan1)
                BalanceStat(label: L("BALANCE"), value: Fmt.signedKcal(bal), tint: NB.text1)
            }
            BalanceAxis(now: bal ?? 0, ifBudget: bal ?? 0, enabled: bal != nil).frame(height: 52)
            HStack(spacing: 7) {
                Rectangle().fill(NB.limeMid.opacity(0.55)).frame(width: 14, height: 8)
                Text(L("RECOMP WINDOW  −200 TO −500 KCAL"))
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
            }
        }
    }

    private var macrosCard: some View {
        func slot(_ eaten: (DailyMetrics) -> Int?, _ target: (DailyMetrics) -> MacroSlot?) -> MacroSlot? {
            guard let t = target(m)?.target else { return nil }
            let xs = window.compactMap(eaten)
            guard !xs.isEmpty else { return MacroSlot(target: t, eaten: 0) }
            return MacroSlot(target: t, eaten: xs.reduce(0, +) / xs.count)
        }
        let pro = slot({ $0.proteinIn }, { $0.protein })
        let perKg = (pro.map(\.eaten)).flatMap { p in m.weightKg.map { Double(p) / $0 } }
        return CardBlock(title: L("MACROS"),
                         trailing: isWeek ? L("DAILY AVERAGE · VS TARGET") : L("VS TARGET")) {
            VStack(spacing: 10) {
                MacroDetailRow(name: "PRO", slot: pro, tint: NB.violet1,
                               note: perKg.map { String(format: "%.1f G/KG", $0) } ?? "")
                MacroDetailRow(name: "CARB", slot: slot({ $0.carbIn }, { $0.carb }),
                               tint: NB.optimal2, note: "")
                MacroDetailRow(name: "FAT", slot: slot({ $0.fatIn }, { $0.fat }),
                               tint: NB.run1, note: "")
            }
        }
    }

    /// The meals inside the window — one day's, or the week's.
    private var windowMeals: [MealEntry] {
        let days = Set(window.map(\.day))
        let source = isWeek ? data.recentMeals : (data.recentMeals.isEmpty ? data.meals : data.recentMeals)
        return source.filter { days.contains($0.day) }.sorted { $0.at < $1.at }
    }

    /// ⚠️ 19YL · in the week view FOOD becomes TOP FOODS, the left column is the number of
    /// days it appeared on, and the sort is by that count — not by kcal. A week's most
    /// useful fact is the habit, and sorting by kcal puts Saturday's one big dinner at the
    /// top, which has nothing to do with the call.
    private var foodCard: some View {
        let meals = windowMeals
        let kcal = meals.reduce(0) { $0 + $1.kcal }
        let pro = meals.reduce(0) { $0 + $1.protein }

        var byName: [String: (days: Set<UserDay>, kcal: Double, pro: Int)] = [:]
        for meal in meals {
            let key = meal.text.isEmpty ? meal.slot.rawValue : meal.text
            var e = byName[key] ?? (Set<UserDay>(), 0, 0)
            e.days.insert(meal.day); e.kcal += meal.kcal; e.pro += meal.protein
            byName[key] = e
        }
        let top = byName.map { (name: $0.key, days: $0.value.days.count,
                                kcal: $0.value.kcal, pro: $0.value.pro) }
            .sorted { ($0.days, $0.kcal) > ($1.days, $1.kcal) }
            .prefix(5)

        return CardBlock(title: isWeek ? L("TOP FOODS") : L("FOOD"),
                         trailing: L("%@ KCAL · %d G PRO", Fmt.kcal(kcal), pro)) {
            if meals.isEmpty {
                Text(L("NOTHING LOGGED IN THIS WINDOW"))
                    .font(NBFont.dot(500, 11)).tracking(0.14 * 11)
                    .foregroundStyle(NB.text3Prod)
            } else if isWeek {
                VStack(spacing: 10) {
                    ForEach(Array(top.enumerated()), id: \.offset) { i, f in
                        if i > 0 { Hairline() }
                        CompFoodRow(time: "\(f.days)D", name: String(f.name.prefix(28)),
                                    detail: "\(Fmt.kcal(f.kcal / Double(max(1, f.days)))) KCAL A DAY",
                                    kcal: Fmt.kcal(f.kcal), pro: "\(f.pro) G PRO")
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(meals.enumerated()), id: \.offset) { i, meal in
                        if i > 0 { Hairline() }
                        CompFoodRow(time: Fmt.clock(meal.at), name: meal.slot.rawValue,
                                    detail: String(meal.text.prefix(34)),
                                    kcal: Fmt.kcal(meal.kcal), pro: "\(meal.protein) G PRO")
                    }
                }
            }
        }
    }

    /// ⚠️ No sleep numbers here or anywhere (F0 rule 03) — the night only shows up as
    /// the Body Battery it produced.
    /// 18SZ · four numbers only — load, steps, battery, hard minutes. No ring and no curve:
    /// this page asks what state the body was in that day, not for a smaller training page.
    private var trainingCard: some View {
        let load = avg { $0.trainingLoad }
        let steps = avg { $0.steps.map(Double.init) }
        let battery = avg { $0.bodyBattery.map(Double.init) }
        let hard = avg { d in d.zoneMinutes.map { Double($0.dropFirst(3).reduce(0, +)) } }
        let session = window.compactMap { $0.segments.first { !$0.allDay && $0.name == "HARD SESSION" } }.first
        return CardBlock(title: MetricNames.training,
                         trailing: isWeek ? L("DAILY AVERAGE")
                                          : session.map { L("HARD · %@", Fmt.duration($0.minutes ?? 0)) }
                                            ?? L("NO SESSION")) {
            HStack(spacing: 10) {
                EvidenceStat(label: MetricNames.trainingLoad, value: Fmt.load(load), unit: nil,
                             delta: nil, deltaTint: .clear)
                EvidenceStat(label: L("STEPS"), value: Fmt.kcal(steps), unit: nil,
                             delta: nil, deltaTint: .clear)
            }
            Rectangle().fill(NB.barTrack).frame(height: 1)
            HStack(spacing: 10) {
                EvidenceStat(label: MetricNames.bodyBattery, value: Fmt.kg(battery, decimals: 0), unit: "%",
                             delta: nil, deltaTint: .clear)
                EvidenceStat(label: L("ZONE 4+"), value: Fmt.kg(hard, decimals: 0), unit: "MIN",
                             delta: nil, deltaTint: .clear)
            }
        }
    }

    private var gates: some View {
        VStack(spacing: 0) {
            GateRow(title: L("ENERGY"), when: L("WITH YOU LOG A MEAL"))
            Hairline()
            GateRow(title: L("MACROS"), when: L("WITH YOU LOG A MEAL"))
            Hairline()
            GateRow(title: L("FOOD"), when: L("WITH YOU LOG A MEAL"))
            Hairline()
            GateRow(title: MetricNames.training, when: L("AFTER 1 FULL DAY"))
        }
        .padding(.horizontal, 14)
        .frame(width: NB.Layout.contentWidth)
    }
}

struct PagerButton: View {
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
                    Text(L(name))
                        .font(NBFont.ui(500, 12.5)).tracking(0.06 * 12.5)
                        .foregroundStyle(lit ? NB.text1 : NB.text2)
                    Spacer(minLength: 0)
                    Text(value)
                        .font(NBFont.dot(700, 13))
                        .foregroundStyle(lit ? NB.lime1 : NB.text3Prod)
                }
                Text(L(note))
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


/// 10 edges · one line under the legend, the board's 11 px Jost 300.
private struct EvidenceNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(NBFont.ui(300, 11)).tracking(0.04 * 11)
            .foregroundStyle(NB.text3Prod)
    }
}
