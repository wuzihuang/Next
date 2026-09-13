import SwiftUI

/// 13 / ADR 0017 · BODY BATTERY. Scheme A is the curve: one page, DAY / WEEK /
/// MONTH. Day answers why today is this number. Week and month speak a typical
/// morning peak, never a sum. Lime is the page colour. Sleep never reaches it.
struct BodyBatteryDetailView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @State private var isRefreshing = false
    @State private var refreshMessage: String?
    @State private var rangeRaw = RollingPills.day.rawValue
    private var range: RollingPills { .parse(rangeRaw) }
    private var detail: DetailWindow { DetailWindow(.bodyBattery, range) }
    private var today: UserDay { UserDay.containing(Date()) }

    private var m: DailyMetrics { data.todayForDisplay }
    private var hasNight: Bool { m.bbWake != nil }
    private var hasScore: Bool { m.bodyBatteryForDisplay(at: Date()) != nil }
    private var hasRecord: Bool { m.bodyBatteryObservedAt != nil }
    #if DEBUG
    private var forceEmpty: Bool { DebugEdge.on("empty") }
    #else
    private var forceEmpty: Bool { false }
    #endif
    private var isDim: Bool { m.bodyBatteryFreshness(at: Date()) != .fresh }
    /// #25 · 0% is a measurement; —— is the absence of one. When the hero is showing ——
    /// this line has to name the wrist, not a sync, or the two read the same.
    private var observationLabel: String {
        guard let at = m.bodyBatteryObservedAt else { return L("NO TICK") }
        if m.bodyBatteryReadout(at: Date()).isPlaceholder {
            return L("NOT WORN SINCE %@ · NO CURRENT READING", Fmt.clock(at))
        }
        return L("SYNCED %@", Fmt.clock(at))
    }

    /// ⚠️ 1CUP · the four rows are only ever present when they close within 0.5 of
    /// BB(now) − BB(anchor). The server drops them when they do not, and there is no OTHER
    /// row to absorb a difference — the whole card goes away instead.
    private var drivers: ReserveDrivers? { m.reserveDrivers }

    /// Wake time comes from the recorded night, never from the day's highest score.
    private var wakeTime: String? { m.bodyBatteryWakeAt.map(Fmt.clock) }

    private var weekFacts: [BodyBatteryDayFacts] { facts(count: DetailWindow(.bodyBattery, .week).days) }
    private var monthFacts: [BodyBatteryDayFacts] { facts(count: DetailWindow(.bodyBattery, .month).days) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in content }
    }

    private var content: some View {
        DetailScroll(glow: NB.lime1, title: MetricNames.bodyBattery, trailing: {
            Text(headerStatus)
                .font(NBFont.dot(600, 11)).tracking(0.24 * 11)
                .foregroundStyle(headerTint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }) {
            VStack(alignment: .leading, spacing: 14) {
                SegmentedPills(options: RollingPills.words, selection: $rangeRaw)
                switch range {
                case .day:   dayBoard
                case .week:  weekBoard
                case .month: monthBoard
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("bodyBattery.page")
        } onBack: {
            leave()
        }
        .onReceive(router.$windowRequest) { request in
            guard let request else { return }
            rangeRaw = request.rawValue
            router.windowRequest = nil
        }
        .task {
            #if DEBUG
            if let override = DetailWindow.debugRange(for: .bodyBattery) {
                rangeRaw = override.rawValue
            }
            #endif
            if !Band.allowsSeed {
                await Repository.shared.hydrate(detail, endingAt: today, into: data)
            }
            await Analytics.shared.track("BB_DETAIL_OPEN", [
                "ENTRY": router.entry == .profile ? "profile" : (router.homePage == 1 ? "page2" : "panel"),
                "RANGE": range.rawValue,
            ])
            if range != .day { return }
            if let bb = m.bodyBattery {
                await Analytics.shared.track("BB_CONFIDENCE_SHOWN",
                                             ["LEVEL": m.bodyBatteryConfidence.rawValue, "SCORE": bb])
            } else {
                await Analytics.shared.track("BB_NO_SCORE",
                                             ["REASON": hasNight ? "NOT_SYNCED" : "SHORT_NIGHT"])
            }
            if hasNight && m.reserveDrivers == nil {
                await Analytics.shared.track("BB_ATTRIBUTION_MISMATCH",
                                             ["TICKS": m.reserveCurve.count])
            }
            if let wake = m.bbWake, let target = m.targetLoad, let zone = m.optimalZone {
                await Analytics.shared.track("BB_TARGET_SET",
                                             ["BB": wake, "TARGET": target,
                                              "LO": zone.lowerBound, "HI": zone.upperBound])
            }
            if m.bodyBatteryFreshness(at: Date()) == .stale, let at = m.bodyBatteryObservedAt {
                await Analytics.shared.track("BB_STALE_SHOWN",
                                             ["MIN": Int(Date().timeIntervalSince(at) / 60)])
            }
        }
    }

    private var headerStatus: String {
        switch range {
        case .day:   return L("TODAY")
        case .week, .month: return L(detail.periodKey)
        }
    }

    private var headerTint: Color { range == .day && !hasScore ? NB.text3Prod : NB.lime1 }

    /// From the panel, back is the root. From ME, back is ME — same one-layer
    /// memory composition already uses.
    private func leave() {
        if router.entry == .profile { router.back() } else { router.backToRoot() }
    }

    // MARK: DAY

    @ViewBuilder private var dayBoard: some View {
        if forceEmpty || !(hasScore || hasRecord) {
            emptyCard
            needsCard
            footer
        } else {
            heroCard
            if drivers != nil && hasScore { ledgerCard }
            if hasNight { inputsCard }
            vitalsCard
            confidenceCard
            footer
        }
    }

    /// The curve colours observed increases and decreases, with its actual last timestamp.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(Fmt.int(m.bodyBatteryForDisplay(at: Date())))
                        .font(NBFont.dot(800, 64))
                        .foregroundStyle(isDim ? NB.text3Prod : NB.text1)
                    Text(L("OF 100"))
                        .font(NBFont.dot(600, 12)).tracking(0.18 * 12)
                        .foregroundStyle(NB.white.opacity(0.42))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(wakeTime.map { L("WAKE %@", $0) } ?? (hasNight ? L("MORNING READING") : L("LIVE ESTIMATE")))
                        .font(NBFont.dot(600, 10)).tracking(0.18 * 10)
                        .foregroundStyle(NB.white.opacity(0.42))
                    Text(drivers?.nightCharge.map { L("%@ LAST NIGHT", Fmt.signed($0)) }
                         ?? (hasNight ? L("NIGHT CHARGE UNAVAILABLE") : L("FROM WRIST DATA")))
                        .font(NBFont.dot(700, 12)).tracking(0.12 * 12)
                        .foregroundStyle(NB.lime1)
                }
            }
            BatteryCurve(samples: m.reserveCurve, day: m.day, dim: isDim).frame(height: 120)
            BodyBatteryTimeAxis(day: m.day)
        }
        .padding(20)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .background(Color(hex: 0x0F0F13), in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
            .stroke(NB.hairline, lineWidth: 1))
    }

    /// 13 · WHY <n> as a ledger. Where the day started, four signed rows with the reason
    /// each one has its sign, the balance after each, and the number at the top as the last
    /// balance. Sleep is the only row that charges; the other three only ever drain, and the
    /// caption under each says what the model charged for. No training target here — the
    /// target is a training-page fact, and it read as a fifth term of the sum.
    @ViewBuilder private var ledgerCard: some View {
        if let d = drivers, let now = m.bodyBattery {
            let rows = BodyBatteryLedgerMath.rows(anchor: d.anchor, recovery: d.chargeForDay,
                                                  awake: d.awake, movement: d.movement,
                                                  stress: d.stress, current: now)
            let scale = max(1, rows.map { abs($0.delta) }.max() ?? 1)
            let startClock = Fmt.clock(m.day.start)
            let nowClock = m.bodyBatteryObservedAt.map(Fmt.clock)
            CardBlock(title: L("WHY %@", Fmt.int(now)),
                      trailing: nowClock.map { L("%@ → %@", startClock, $0) } ?? startClock) {
                LedgerEdge(label: L("START %@", startClock), value: d.anchor,
                           note: d.assumedAnchor ? L("ESTIMATED") : nil, tint: NB.white.opacity(0.55))
                Hairline()
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Text(L("CHANGE"))
                        .frame(width: LedgerRow.barWidth + 10 + LedgerRow.deltaWidth, alignment: .trailing)
                    Text(L("AFTER"))
                        .frame(width: LedgerRow.balanceWidth, alignment: .trailing)
                }
                .font(NBFont.dot(500, 9)).tracking(0.16 * 9)
                .foregroundStyle(NB.white.opacity(0.30))
                VStack(spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        LedgerRow(name: ledgerName(row.term), reason: ledgerReason(row.term, d),
                                  delta: row.delta, balance: row.balance, scale: scale)
                    }
                }
                Hairline()
                LedgerEdge(label: nowClock.map { L("NOW %@", $0) } ?? L("NOW"), value: now,
                           note: nil, tint: NB.lime1)
                Text(L("Only sleep charges it. Being awake drains it on its own; moving and stress cost more on top."))
                    .font(NBFont.brand(400, 13))
                    .lineSpacing(6)
                    .foregroundStyle(NB.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                if d.assumedAnchor {
                    Text(L("Starting battery estimated — earlier readings were missing."))
                        .font(NBFont.brand(400, 13))
                        .lineSpacing(6)
                        .foregroundStyle(NB.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .id("bb-why")
        }
    }

    private func ledgerName(_ term: BodyBatteryLedgerRow.Term) -> String {
        switch term {
        case .recovery: L("Recovery")
        case .awake:    L("Just being awake")
        case .movement: L("Moving around")
        case .stress:   L("Stress")
        }
    }

    /// Why the row has its sign, in the day's own numbers where the page has them.
    private func ledgerReason(_ term: BodyBatteryLedgerRow.Term, _ d: ReserveDrivers) -> String {
        switch term {
        case .recovery:
            if let multiplier = m.nightInputs?.multiplier {
                return L("Charged while asleep · multiplier %.2f", multiplier)
            }
            return L("Charged while asleep")
        case .awake:
            if let minutes = BodyBatteryLedgerMath.awakeMinutes(
                wakeAt: m.bodyBatteryWakeAt, dayStart: m.day.start, observedAt: m.bodyBatteryObservedAt) {
                return L("Base drain for %@ awake · faster after a short night", Fmt.duration(minutes))
            }
            return L("Base drain while awake · faster after a short night")
        case .movement:
            if let steps = m.recordedSteps {
                return L("Heart-rate zones, effort and steps · %d steps", steps)
            }
            return L("Heart-rate zones, effort and steps")
        case .stress:
            if let minutes = BodyBatteryLedgerMath.stressedMinutes(m.vitalsCurve) {
                return minutes > 0
                    ? L("Stress above 40 for %@ · HRV under baseline", Fmt.duration(minutes))
                    : L("Stress stayed under 40 · HRV under baseline")
            }
            return L("Stress above 40 and HRV under baseline")
        }
    }

    /// HRV and resting heart rate are allowed on screen because we measure them and they have
    /// a unit. Sleep duration and stages are not, here or anywhere. Each is printed against
    /// its own 14-night baseline, and the multiplier they produce closes the card — it is the
    /// number the Recovery row above was charged through.
    private var inputsCard: some View {
        let n = m.nightInputs ?? NightInputs()
        let pace = n.multiplier.map(BodyBatteryLedgerMath.pace)
        return CardBlock(title: L("LAST NIGHT'S INPUTS"), trailing: L("%d OF 3", n.present)) {
            VStack(spacing: 12) {
                InputRow(name: "HRV", value: Fmt.kg(n.hrv, decimals: 0), unit: n.hrv == nil ? nil : "MS",
                         base: baselineNote(n.hrv, n.hrvBase))
                Hairline()
                InputRow(name: "Resting heart rate", value: Fmt.kg(n.rhr, decimals: 0),
                         unit: n.rhr == nil ? nil : "BPM",
                         base: baselineNote(n.rhr, n.rhrBase))
                Hairline()
                HStack(spacing: 8) {
                    Text(L("Charge multiplier"))
                        .font(NBFont.brand(400, 13))
                        .foregroundStyle(NB.text2)
                    Spacer(minLength: 0)
                    Text(n.multiplier.map { String(format: "%.2f", $0) } ?? Fmt.dash)
                        .font(NBFont.dot(700, 14)).tracking(0.04 * 14)
                        .foregroundStyle(NB.text1)
                    if let pace {
                        Text(paceWord(pace))
                            .font(NBFont.dot(600, 9)).tracking(0.14 * 9)
                            .foregroundStyle(pace == .usual ? NB.white.opacity(0.42) : NB.lime1)
                    }
                }
            }
            Text(L("Last night's HRV and resting heart rate, against your 14-night baselines, set how fast sleep charged the battery."))
                .font(NBFont.brand(400, 13))
                .lineSpacing(6)
                .foregroundStyle(NB.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "BASE 61 · −7": the baseline and how far last night sat from it.
    private func baselineNote(_ value: Double?, _ base: Double?) -> String? {
        guard let base else { return nil }
        guard let value else { return L("BASE %d", Int(base)) }
        return L("BASE %d · %@", Int(base), Fmt.signed(value - base))
    }

    private func paceWord(_ pace: BodyBatteryLedgerMath.Pace) -> String {
        switch pace {
        case .slower: L("SLOWER THAN USUAL")
        case .usual:  L("USUAL PACE")
        case .faster: L("FASTER THAN USUAL")
        }
    }

    /// Heart and stress sit under the curve. They are measurements, not a second
    /// colour for the battery itself.
    private var vitalsCard: some View {
        let day = m.vitalsCurve
        let hrs = day.compactMap(\.hr)
        let stresses = day.compactMap(\.stress)
        let lastTick = day.last
        let live = data.vitals
        let showsLive = m.day == UserDay.containing(Date())
        let at = showsLive ? live.at : lastTick?.ts
        let gone = showsLive && live.freshness == .gone
        let stale = showsLive && live.freshness == .stale
        let hr = gone ? nil : (showsLive ? (live.hr ?? lastTick?.hr) : lastTick?.hr)
        let stress = gone ? nil : (showsLive ? (live.stress ?? lastTick?.stress) : lastTick?.stress)
        return CardBlock(title: L("HEART & STRESS"),
                         trailing: at.map { L("LAST TICK %@", Fmt.clock($0)) } ?? L("NO TICK"),
                         trailingTint: gone || at == nil ? NB.text3Prod : NB.lime1) {
            HStack(spacing: 0) {
                VitalReading(label: L("HEART"), value: hr.map(String.init), unit: "BPM",
                             tint: NB.lime1, dim: stale)
                VitalReading(label: L("STRESS"), value: stress.map(String.init), unit: L("INDEX"),
                             tint: NB.white.opacity(0.55), dim: stale)
                VitalReading(label: L("RESTING"), value: m.nightInputs?.rhr.map { String(Int($0)) },
                             unit: "BPM", tint: NB.white.opacity(0.42), dim: false)
            }
            if !hrs.isEmpty || !stresses.isEmpty {
                VStack(spacing: 10) {
                    if !hrs.isEmpty {
                        VitalTrace(samples: day, value: \.hr, tint: NB.lime1, name: L("HEART"),
                                   low: hrs.min() ?? 0, high: hrs.max() ?? 0, unit: L("BPM"))
                    }
                    if !stresses.isEmpty {
                        VitalTrace(samples: day, value: \.stress, tint: NB.white.opacity(0.55),
                                   name: L("STRESS"),
                                   low: stresses.min() ?? 0, high: stresses.max() ?? 0, unit: L("INDEX"))
                    }
                    BodyBatteryTimeAxis(day: m.day)
                }
            }
            Hairline()
            Text(vitalsLine(ticks: day.count, gone: gone, stale: stale))
                .font(NBFont.brand(400, 13))
                .lineSpacing(6)
                .foregroundStyle(gone || day.isEmpty ? NB.text3Prod : NB.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func vitalsLine(ticks: Int, gone: Bool, stale: Bool) -> String {
        if ticks == 0 {
            return data.band.connected
                ? L("No ticks for this day yet.")
                : L("Connect the band to see the ticks it has been recording.")
        }
        if gone { return L("Nothing for over six hours.") }
        if stale { return L("%d ticks · nothing new for a while.", ticks) }
        return L("%d ticks today. Gaps stay open.", ticks)
    }

    /// Evidence quality, in the two places evidence comes from. NIGHT is what the
    /// multiplier and the morning reading stood on; DAY is what the three drain rows stood
    /// on. Baseline nights sit with the night they qualify.
    private var confidenceCard: some View {
        let coverage = m.reserveDrivers?.coverage
        let hrvNights = coverage?.hrvNights ?? m.nightInputs?.hrvNights ?? 0
        let rhrNights = coverage?.rhrNights ?? m.nightInputs?.rhrNights ?? 0
        return CardBlock(title: L("CONFIDENCE"), trailing: L(m.bodyBatteryConfidence.rawValue), trailingIsDot: true) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i < tierIndex ? NB.lime1 : NB.white.opacity(0.10))
                        .frame(height: 5)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                groupLabel(L("NIGHT"))
                coverageRow(L("HRV COVERAGE"), pct(coverage?.nightHRV))
                coverageRow(L("HEART COVERAGE"), pct(coverage?.nightRHR))
                coverageRow(L("HRV BASELINE"), L("%d / 14 NIGHTS", hrvNights))
                coverageRow(L("RESTING BASELINE"), L("%d / 14 NIGHTS", rhrNights))
            }
            Hairline()
            VStack(alignment: .leading, spacing: 8) {
                groupLabel(L("DAY"))
                coverageRow(L("HEART COVERAGE"), pct(coverage?.dayHeart))
                coverageRow(L("HRV COVERAGE"), pct(coverage?.dayHRV))
                coverageRow(L("STRESS COVERAGE"), pct(coverage?.dayStress))
            }
            Text(L("Missing HRV or stress readings reduce confidence; they do not mean no stress."))
                .font(NBFont.brand(400, 13))
                .lineSpacing(6)
                .foregroundStyle(NB.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(NBFont.dot(600, 9)).tracking(0.18 * 9)
            .foregroundStyle(NB.lime1.opacity(0.75))
    }

    private func pct(_ fraction: Double?) -> String {
        fraction.map { "\(Int((min(1, max(0, $0)) * 100).rounded()))%" } ?? Fmt.dash
    }

    private func coverageRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(NBFont.ui(500, 10))
                .foregroundStyle(NB.text3Prod)
            Spacer(minLength: 0)
            Text(value)
                .font(NBFont.dot(600, 12))
                .foregroundStyle(value == Fmt.dash ? NB.text3Prod : NB.text2)
        }
    }

    private var tierIndex: Int {
        switch m.bodyBatteryConfidence { case .low: 1; case .medium: 2; case .high: 3 }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(observationLabel)
                    .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
                Button {
                    Task { await refreshBattery() }
                } label: {
                    Text(L(isRefreshing ? "SYNCING…" : "SYNC"))
                        .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                        .foregroundStyle(NB.text2)
                        .padding(.horizontal, 16).frame(height: 34)
                        .overlay(Capsule().stroke(NB.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .accessibilityIdentifier("bodyBattery.sync")
                .accessibilityLabel(L("Sync now"))
            }
            if let refreshMessage {
                Text(refreshMessage)
                    .font(NBFont.brand(400, 13))
                    .foregroundStyle(NB.text3Prod)
            }
        }
        .padding(.top, 6)
    }

    /// Re-read real band evidence through the existing sync lane. A request to refresh
    /// never edits a calculated value or resets the frozen training target.
    private func refreshBattery() async {
        guard !isRefreshing else { return }
        refreshMessage = nil
        guard ConsentStore.shared.granted else { router.takeover = .consent; return }
        guard BoundBand.identifier != nil else {
            refreshMessage = L("Connect the band to see the ticks it has been recording.")
            return
        }
        guard SupabaseClient.currentUserIdSnapshot() != nil else {
            refreshMessage = L("Sign in to sync this HOOP.")
            return
        }
        guard LiveSessionStore.shared.session == nil, !BandLiveLifecycle.shared.hasExclusiveOperation else {
            refreshMessage = L("Finish the current measurement or device operation, then sync again.")
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        await OriginDataSync.refreshNow(into: data, request: .latest)
        if Band.live.state != .connected {
            refreshMessage = L("Could not reach this HOOP. Keep it nearby, check Bluetooth, then tap Sync to try again.")
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(Fmt.dash)
                    .font(NBFont.dot(800, 36))
                    .foregroundStyle(NB.text3Prod)
                Text(L("OF 100"))
                    .font(NBFont.dot(600, 12)).tracking(0.18 * 12)
                    .foregroundStyle(NB.white.opacity(0.30))
            }
            Text(L("NO RECENT BATTERY READING"))
                .font(NBFont.dot(600, 11)).tracking(0.2 * 11)
                .foregroundStyle(NB.ember1)
            Text(L("Sync recent wrist readings to estimate your battery."))
                .font(NBFont.brand(400, 16))
                .lineSpacing(8)
                .foregroundStyle(NB.text1)
        }
        .padding(20)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .background(Color(hex: 0x0F0F13), in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
            .stroke(NB.hairline, lineWidth: 1))
    }

    private var needsCard: some View {
        CardBlock(title: L("WHAT IT NEEDS")) {
            VStack(alignment: .leading, spacing: 14) {
                NeedRow("Recent heart rate and activity readings")
                NeedRow("A recorded night for a morning reading")
                NeedRow("Enough complete nights to build a personal baseline")
            }
        }
    }

    // MARK: WEEK

    private var weekBoard: some View {
        let days = weekFacts
        let avg = BodyBatteryWindowMath.averageWake(days)
        let peak = BodyBatteryWindowMath.peakDay(days)
        let night = BodyBatteryWindowMath.typicalNightCharge(days)
        let prior = Array(facts(count: days.count * 2).prefix(days.count))
        let delta = MetricTrendMath.delta(current: days.map { $0.wake.map(Double.init) },
                                          prior: prior.map { $0.wake.map(Double.init) })
        return VStack(alignment: .leading, spacing: 14) {
            // The week leads with its shape, not a number: the line is the seven mornings
            // and the row under it says the average once, beside how it moved.
            CardBlock(title: L("SEVEN DAYS"),
                      trailing: L("MORNING PEAKS · ROLLING"),
                      trailingIsDot: true) {
                BodyBatteryDayLine(values: days.map(\.wake), average: avg,
                                   todayIndex: days.indices.last)
                    .frame(height: 130)
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                        Text(Fmt.weekday(day.day.date).prefix(1))
                            .font(NBFont.dot(i == days.count - 1 ? 700 : 500, 10))
                            .foregroundStyle(i == days.count - 1 ? NB.lime1 : Color(hex: 0x8A8A96))
                            .frame(maxWidth: .infinity)
                    }
                }
                Text(L("Rolling 7 days · lime is today. A dashed gap is a morning with no reading."))
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
                windowSummary(headline: avg, delta: delta,
                              recorded: days.filter(\.hasWake).count, of: days.count)
            }
            CardBlock(title: L("WAKE PEAKS"), trailing: L("TYPICAL DAY"), trailingIsDot: true) {
                weekStat(L("AVERAGE"), Fmt.int(avg.map { Int($0.rounded()) }), NB.lime1)
                Hairline()
                weekStat(L("HIGHEST"),
                         peak.flatMap { p in p.wake.map { L("%d · %@", $0, Fmt.weekday(p.day.date)) } } ?? Fmt.dash,
                         NB.lime1)
                Hairline()
                weekStat(L("NIGHT CHARGE"),
                         night.map { L("%@ / DAY", Fmt.signed($0)) } ?? Fmt.dash,
                         NB.macroValue)
                Hairline()
                weekStat(L("NO MORNING READING"), L("%d DAYS", BodyBatteryWindowMath.emptyCount(days)), NB.text3Prod)
            }
        }
    }

    // MARK: MONTH

    private var monthBoard: some View {
        let days = monthFacts
        let typical = BodyBatteryWindowMath.typicalWake(days)
        let mornings = days.filter(\.hasWake).count
        let empty = BodyBatteryWindowMath.emptyCount(days)
        let rolls = BodyBatteryWindowMath.weekRolls(days)
        let night = BodyBatteryWindowMath.typicalNightCharge(days)
        return VStack(alignment: .leading, spacing: 14) {
            CardBlock(title: L("THIRTY DAYS"),
                      trailing: L("%d MORNINGS · %d MISSING", mornings, empty), trailingIsDot: true) {
                BodyBatteryDayLine(values: days.map(\.wake), average: typical,
                                   todayIndex: days.indices.last)
                    .frame(height: 140)
                HStack(spacing: 6) {
                    Text(days.first.map { Fmt.displayDate($0.day.date, format: "d MMM").uppercased() } ?? Fmt.dash)
                        .font(NBFont.dot(500, 10))
                        .foregroundStyle(Color(hex: 0x8A8A96))
                    Spacer(minLength: 0)
                    Text(L("TODAY"))
                        .font(NBFont.dot(700, 10))
                        .foregroundStyle(NB.lime1)
                }
                Text(L("One point per morning peak · a dashed gap is a morning with no reading."))
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
                // Thirty mornings have no sixty behind them to compare with, so the row
                // is the typical morning and the count; the week-by-week card below is
                // where the month's drift reads.
                windowSummary(headline: typical, delta: nil, recorded: mornings, of: days.count)
            }
            CardBlock(title: L("WHAT THE MONTH LOOKED LIKE")) {
                HStack {
                    Text(L("WEEK BY WEEK"))
                        .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                        .foregroundStyle(NB.text1)
                    Spacer(minLength: 0)
                    Text(weekTrend(rolls))
                        .font(NBFont.dot(700, 11))
                        .foregroundStyle(NB.lime1)
                }
                BodyBatteryDayLine(values: rolls.map { $0.average.map { Int($0.rounded()) } },
                                   average: typical,
                                   todayIndex: rolls.isEmpty ? nil : rolls.count - 1)
                    .frame(height: 72)
                HStack(spacing: 0) {
                    ForEach(Array(rolls.enumerated()), id: \.offset) { i, roll in
                        Text(L("%dD %@", roll.days, Fmt.int(roll.average.map { Int($0.rounded()) })))
                            .font(NBFont.dot(500, 9))
                            .foregroundStyle(i == rolls.count - 1 ? NB.lime1 : Color(hex: 0x8A8A96))
                            .frame(maxWidth: .infinity)
                    }
                }
                Hairline()
                weekStat(L("TYPICAL MORNING"), Fmt.int(typical.map { Int($0.rounded()) }), NB.lime1)
                Hairline()
                weekStat(L("NIGHT CHARGE"),
                         night.map { L("%@ / DAY", Fmt.signed($0)) } ?? Fmt.dash,
                         NB.macroValue)
                Text(L("Two days, then four weeks."))
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
        }
    }

    /// The window's one number, said once under its line: the average morning, how it
    /// moved against the window before, and how many mornings actually recorded. The
    /// 64 pt figure that used to stand above the chart is gone — a rolling window has no
    /// single reading, and printed like one it read as today's.
    private func windowSummary(headline: Double?, delta: Double?, recorded: Int, of total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L("AVG %@", Fmt.int(headline.map { Int($0.rounded()) })))
                .font(NBFont.dot(700, 14)).tracking(0.02 * 14)
                .foregroundStyle(headline == nil ? NB.text3Prod : NB.lime1)
                .lineLimit(1).minimumScaleFactor(0.8)
            if headline != nil {
                Text(L("OF 100"))
                    .font(NBFont.ui(600, 10))
                    .foregroundStyle(NB.text1)
            }
            if let delta {
                let n = Int(delta.rounded())
                Text(L("· %@", n == 0 ? L("LEVEL WITH %@", L("PRIOR %dD", total))
                                      : L("%@%@ VS %@", n > 0 ? "+" : "−", String(abs(n)), L("PRIOR %dD", total))))
                    .font(NBFont.ui(500, 10))
                    .foregroundStyle(NB.white.opacity(0.62))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Text(L("%d OF %d MORNINGS", recorded, total))
                .font(NBFont.ui(400, 10))
                .foregroundStyle(NB.white.opacity(0.42))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(NB.white.opacity(0.06)).frame(height: 1)
        }
    }

    private func weekStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack {
            Text(label)
                .font(NBFont.ui(500, 12)).tracking(0.06 * 12)
                .foregroundStyle(NB.text2)
            Spacer(minLength: 0)
            Text(value)
                .font(NBFont.dot(700, 14))
                .foregroundStyle(tint)
        }
    }

    private func weekTrend(_ rolls: [BodyBatteryWeekRoll]) -> String {
        let values = rolls.compactMap(\.average)
        guard let first = values.first, let last = values.last, values.count >= 2 else {
            return L("NO TREND YET")
        }
        return last >= first ? L("TRENDING UP") : L("TRENDING DOWN")
    }

    private func facts(count: Int) -> [BodyBatteryDayFacts] {
        today.rollingBack(count).map { day in
            let row = day == today ? m : (data.history.first { $0.day == day } ?? DailyMetrics(day: day))
            return BodyBatteryDayFacts(
                day: day,
                wake: row.bbWake,
                now: day == today ? data.bodyBatteryNow : row.bodyBattery,
                nightCharge: row.reserveDrivers?.nightCharge,
                worn: row.worn,
                isOpen: day == today && !day.isClosed)
        }
    }
}

private struct NeedRow: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        HStack(spacing: 10) {
            Circle().stroke(NB.white.opacity(0.28), lineWidth: 1).frame(width: 9, height: 9)
            Text(L(text))
                .font(NBFont.brand(400, 13))
                .foregroundStyle(NB.text2)
        }
    }
}

/// One ledger line: the term, why it has its sign, a bar that leaves the centre to the
/// right for a charge and to the left for a drain, the signed change, and the balance after.
private struct LedgerRow: View {
    static let barWidth: CGFloat = 76
    static let deltaWidth: CGFloat = 34
    static let balanceWidth: CGFloat = 30

    let name: String
    let reason: String
    let delta: Int
    let balance: Int
    let scale: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Text(name)
                    .font(NBFont.brand(400, 13))
                    .foregroundStyle(NB.text1)
                    .lineLimit(1)
                Spacer(minLength: 0)
                ZStack(alignment: .center) {
                    Rectangle().fill(NB.white.opacity(0.14)).frame(width: 1, height: 10)
                    let half = Self.barWidth / 2
                    let length = half * CGFloat(abs(delta)) / CGFloat(max(1, scale))
                    Capsule()
                        .fill(delta > 0 ? NB.lime1 : NB.white.opacity(0.38))
                        .frame(width: max(delta == 0 ? 0 : 3, length), height: 6)
                        .offset(x: delta > 0 ? length / 2 : -length / 2)
                }
                .frame(width: Self.barWidth, height: 14)
                Text(delta > 0 ? "+\(delta)" : "\(delta)")
                    .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
                    .foregroundStyle(delta > 0 ? NB.lime1 : (delta == 0 ? NB.text3Prod : NB.white.opacity(0.62)))
                    .frame(width: Self.deltaWidth, alignment: .trailing)
                Text("\(balance)")
                    .font(NBFont.dot(600, 12)).tracking(0.04 * 12)
                    .foregroundStyle(NB.text3Prod)
                    .frame(width: Self.balanceWidth, alignment: .trailing)
            }
            Text(reason)
                .font(NBFont.ui(400, 11))
                .foregroundStyle(NB.text3Prod)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The two edges of the ledger: where the day started and where it stands now.
private struct LedgerEdge: View {
    let label: String
    let value: Int
    let note: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.white.opacity(0.55))
            if let note {
                Text(note)
                    .font(NBFont.dot(500, 9)).tracking(0.14 * 9)
                    .foregroundStyle(NB.ember1)
            }
            Spacer(minLength: 0)
            Text("\(value)")
                .font(NBFont.dot(700, 16)).tracking(0.02 * 16)
                .foregroundStyle(tint)
        }
    }
}

private struct InputRow: View {
    let name: String
    let value: String
    let unit: String?
    let base: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(L(name))
                .font(NBFont.brand(400, 13))
                .foregroundStyle(NB.text2)
            Spacer(minLength: 0)
            Text(value)
                .font(NBFont.dot(700, 14)).tracking(0.04 * 14)
                .foregroundStyle(NB.text1)
            if let unit {
                Text(unit)
                    .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                    .foregroundStyle(NB.white.opacity(0.42))
            }
            if let base {
                Text(base)
                    .font(NBFont.dot(500, 9)).tracking(0.14 * 9)
                    .foregroundStyle(NB.white.opacity(0.28))
            }
        }
    }
}

/// Each observed rise is lime; flat or falling segments are white. Missing ticks
/// stay open. The last point marks the last observation, not an extrapolated NOW.
struct BatteryCurve: View {
    var samples: [ReserveSample] = []
    var day: UserDay? = nil
    var dim = false
    var compact = false

    var body: some View {
        Canvas { ctx, size in
            guard let last = samples.max(by: { $0.ts < $1.ts }) else { return }
            let window = day ?? UserDay.containing(last.ts)
            let pad = compact ? 3.0 : 8.0
            let inset = compact ? 2.0 : 4.0
            func point(_ sample: ReserveSample) -> CGPoint {
                CGPoint(x: inset + BodyBatteryCurveMath.fraction(sample.ts, in: window) * max(0, size.width - inset * 2),
                        y: size.height - pad - Double(min(100, max(0, sample.value))) / 100 * max(0, size.height - pad * 2))
            }
            if !compact {
                for value in [30.0, 70.0] {
                    let y = size.height - pad - value / 100 * max(0, size.height - pad * 2)
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(NB.white.opacity(0.06)))
                }
            }
            let lineWidth: CGFloat = compact ? 1.5 : 2.2
            for segment in BodyBatteryCurveMath.segments(samples) {
                var line = Path()
                line.move(to: point(segment.start))
                line.addLine(to: point(segment.end))
                ctx.stroke(line, with: .color(segment.charging ? NB.lime1 : NB.white.opacity(0.42)),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
            let tail = point(last)
            let r: CGFloat = compact ? 2.5 : 4.5
            ctx.fill(Path(ellipseIn: CGRect(x: tail.x - r, y: tail.y - r, width: r * 2, height: r * 2)),
                     with: .color(NB.lime1))
        }
        .opacity(dim ? 0.45 : 1)
    }
}

/// Local clock labels share the same second-based coordinates as both charts.
/// No fixed-position NOW label implies that an old observation is current.
private struct BodyBatteryTimeAxis: View {
    let day: UserDay

    private var ticks: [Date] {
        let calendar = Calendar.current
        // ⚠️ The end label is pinned to the right edge, so an hour mark that lands close to
        // it collides with it — 22:00 and 00:00 printed as one word once the user day moved
        // to midnight and the axis face grew wider. An hour inside the last tenth of the day
        // is dropped rather than drawn on top of the edge.
        let hours = [4, 10, 16, 22].compactMap {
            calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day.start)
        }.filter { BodyBatteryCurveMath.fraction($0, in: day) < 0.9 }
        return hours + [day.end]
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(ticks, id: \.self) { timestamp in
                Text(Fmt.clock(timestamp))
                    .font(NBFont.dot(500, 9))
                    .foregroundStyle(NB.white.opacity(0.34))
                    .position(x: min(max(16, 4 + BodyBatteryCurveMath.fraction(timestamp, in: day) * max(0, geo.size.width - 8)),
                                     max(16, geo.size.width - 16)), y: 6)
            }
        }
        .frame(height: 12)
    }
}

private struct VitalReading: View {
    let label: String
    let value: String?
    let unit: String
    let tint: Color
    var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(NBFont.ui(500, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.text3Prod)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? Fmt.dash)
                    .font(NBFont.dot(700, 24)).tracking(0.02 * 24)
                    .foregroundStyle(value == nil ? NB.text3Prod : (dim ? NB.text2 : tint))
                Text(unit)
                    .font(NBFont.dot(500, 8)).tracking(0.16 * 8)
                    .foregroundStyle(NB.white.opacity(0.34))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A day of one tick series, drawn across the same 04:00 → 04:00 width as the battery curve.
/// ⚠️ A gap in the series is a gap in the line, not a straight segment across it.
private struct VitalTrace: View {
    let samples: [VitalSample]
    let value: KeyPath<VitalSample, Int?>
    let tint: Color
    let name: String
    let low: Int
    let high: Int
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(name)
                    .font(NBFont.dot(600, 9)).tracking(0.18 * 9)
                    .foregroundStyle(tint.opacity(0.75))
                Spacer(minLength: 0)
                Text("\(low) – \(high) \(unit)")
                    .font(NBFont.dot(500, 9)).tracking(0.12 * 9)
                    .foregroundStyle(NB.white.opacity(0.30))
            }
            Canvas { ctx, size in
                guard let first = samples.first else { return }
                let day = UserDay.containing(first.ts)
                let span = max(1, high - low)
                var run = Path()
                var open = false
                var previous: Date?
                for s in samples.sorted(by: { $0.ts < $1.ts }) {
                    defer { previous = s.ts }
                    guard let v = s[keyPath: value] else { open = false; continue }
                    if let previous, s.ts.timeIntervalSince(previous) > 10 * 60 { open = false }
                    let t = BodyBatteryCurveMath.fraction(s.ts, in: day)
                    let x = size.width * t
                    let y = size.height - (Double(v - low) / Double(span)) * (size.height - 4) - 2
                    let pt = CGPoint(x: x, y: y)
                    if open { run.addLine(to: pt) } else { run.move(to: pt); open = true }
                }
                ctx.stroke(run, with: .color(tint.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 34)
        }
    }
}
