import SwiftUI

/// 13 / ADR 0017 · BODY BATTERY. Scheme A is the curve: one page, DAY / WEEK /
/// MONTH. Day answers why today is this number. Week and month speak a typical
/// morning peak, never a sum. Lime is the page colour. Sleep never reaches it.
struct BodyBatteryDetailView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @State private var rangeRaw = RollingPills.day.rawValue
    private var range: RollingPills { .parse(rangeRaw) }
    private var detail: DetailWindow { DetailWindow(.bodyBattery, range) }
    private var today: UserDay { UserDay.containing(Date()) }

    private var m: DailyMetrics { data.todayForDisplay }
    private var hasNight: Bool { m.bbWake != nil }
    private var hasScore: Bool { m.bodyBattery != nil }

    /// ⚠️ 1CUP · the four rows are only ever present when they close within 0.5 of
    /// BB(now) − BB(anchor). The server drops them when they do not, and there is no OTHER
    /// row to absorb a difference — the whole card goes away instead.
    private var drivers: ReserveDrivers? { m.reserveDrivers }

    /// The peak is the highest point on the curve, not a fixed hour. With no curve on hand
    /// the board's 07:12 stands in.
    private var peakTime: String {
        guard let top = m.reserveCurve.max(by: { $0.value < $1.value }) else { return "07:12" }
        return Fmt.clock(top.ts)
    }

    private var weekFacts: [BodyBatteryDayFacts] { facts(count: DetailWindow(.bodyBattery, .week).days) }
    private var monthFacts: [BodyBatteryDayFacts] { facts(count: DetailWindow(.bodyBattery, .month).days) }

    var body: some View {
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
                "ENTRY": router.entry == .profile ? "profile" : "panel",
                "RANGE": range.rawValue,
            ])
            if range != .day { return }
            if let bb = m.bodyBattery {
                await Analytics.shared.track("BB_CONFIDENCE_SHOWN",
                                             ["LEVEL": m.confidence.rawValue, "SCORE": bb])
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
            if data.vitals.freshness == .stale, let at = data.vitals.at {
                await Analytics.shared.track("BB_STALE_SHOWN",
                                             ["MIN": Int(Date().timeIntervalSince(at) / 60)])
            }
        }
    }

    private var headerStatus: String {
        switch range {
        case .day:   return hasNight ? L("TODAY") : L("DAY 01")
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
        if hasScore {
            heroCard
            if drivers != nil { whyCard }
            if hasNight {
                inputsCard
                targetCard
            } else {
                daytimeAnchorCard
            }
            vitalsCard
            confidenceCard
            footer
        } else {
            emptyCard
            needsCard
            LimePillButton(title: L("Wear it tonight")) { leave() }
                .padding(.top, 6)
        }
    }

    /// The curve: lime while charging overnight, white while discharging awake,
    /// with one lime dot at NOW. There is not a single sleep number on it.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(Fmt.int(m.bodyBattery))
                        .font(NBFont.dot(800, 64))
                        .foregroundStyle(NB.text1)
                    Text(L("OF 100"))
                        .font(NBFont.dot(600, 12)).tracking(0.18 * 12)
                        .foregroundStyle(NB.white.opacity(0.42))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(hasNight ? L("PEAK %@", peakTime) : L("LIVE ESTIMATE"))
                        .font(NBFont.dot(600, 10)).tracking(0.18 * 10)
                        .foregroundStyle(NB.white.opacity(0.42))
                    Text(hasNight
                         ? L("%@ LAST NIGHT", Fmt.signed(drivers?.lastNight ?? 0))
                         : L("FROM WRIST DATA"))
                        .font(NBFont.dot(700, 12)).tracking(0.12 * 12)
                        .foregroundStyle(NB.lime1)
                }
            }
            BatteryCurve(samples: m.reserveCurve).frame(width: 318, height: 120)
            HStack {
                ForEach(["04", "10", "NOW", "22"], id: \.self) { t in
                    Text(t == "NOW" ? L("NOW") : t)
                        .font(NBFont.dot(600, 10)).tracking(0.18 * 10)
                        .foregroundStyle(t == "NOW" ? NB.lime1 : NB.white.opacity(0.34))
                    if t != "22" { Spacer(minLength: 0) }
                }
            }
        }
        .padding(20)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .background(Color(hex: 0x0F0F13), in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
            .stroke(NB.hairline, lineWidth: 1))
    }

    /// Four rows that must add up to the number at the top, within ±0.5.
    /// The order cannot change: last night first, then the three ways the day spent it.
    @ViewBuilder private var whyCard: some View {
        let d = drivers ?? ReserveDrivers(lastNight: 0, awake: 0, movement: 0, stress: 0, anchor: 0)
        let scale = max(1, max(abs(d.lastNight), max(abs(d.awake), max(abs(d.movement), abs(d.stress)))))
        CardBlock(title: L("WHY %@", Fmt.int(m.bodyBattery)), trailing: L("FROM %d AT 04:00", d.anchor)) {
            VStack(spacing: 11) {
                ContribRow(label: hasNight ? L("Last night") : L("Recovery"),
                           value: d.lastNight, maxAbs: scale, tint: NB.lime1)
                ContribRow(label: L("Just being awake"), value: d.awake, maxAbs: scale, tint: NB.white.opacity(0.35))
                ContribRow(label: L("Moving around"), value: d.movement, maxAbs: scale, tint: NB.white.opacity(0.35))
                ContribRow(label: L("Stress"), value: d.stress, maxAbs: scale, tint: NB.white.opacity(0.35))
            }
            Hairline()
            HStack {
                Text(L("THESE FOUR ADD UP TO %@", Fmt.signed(d.sum)))
                    .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
                Text("\(d.anchor)  →  \(Fmt.int(m.bodyBattery))")
                    .font(NBFont.dot(700, 11)).tracking(0.08 * 11)
                    .foregroundStyle(NB.text2)
            }
            if d.assumedAnchor {
                Text(hasNight
                     ? L("There was no yesterday to start from, so the first night began at an assumed 20. It stops being an assumption tomorrow.")
                     : L("There was no previous day or recorded night, so this daytime estimate begins at a neutral 50. Live wrist data moves it from there."))
                    .font(NBFont.brand(400, 13))
                    .lineSpacing(6)
                    .foregroundStyle(NB.white.opacity(0.62))
            }
        }
    }

    /// HRV and resting heart rate are allowed on screen because we measure them and they have
    /// a unit. Sleep duration and stages are not, here or anywhere.
    private var inputsCard: some View {
        let n = m.nightInputs ?? NightInputs()
        return CardBlock(title: L("LAST NIGHT'S INPUTS"), trailing: L("%d OF 3", n.present)) {
            VStack(spacing: 12) {
                InputRow(name: "HRV", value: Fmt.kg(n.hrv, decimals: 0), unit: n.hrv == nil ? nil : "MS",
                         base: n.hrvBase.map { L("BASE %d", Int($0)) })
                Hairline()
                InputRow(name: "Resting heart rate", value: Fmt.kg(n.rhr, decimals: 0),
                         unit: n.rhr == nil ? nil : "BPM",
                         base: n.rhrBase.map { L("BASE %d", Int($0)) })
                Hairline()
                InputRow(name: "Charge multiplier",
                         value: n.multiplier.map { String(format: "%.2f", $0) } ?? Fmt.dash,
                         unit: nil, base: nil)
            }
        }
    }

    private var targetCard: some View {
        let band = BodyBattery.band(for: m.bbWake ?? 0)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("TODAY'S TARGET"))
                    .font(NBFont.dot(700, 11)).tracking(0.22 * 11)
                    .foregroundStyle(NB.white)
                Spacer(minLength: 0)
                Text(L("SET AT %@", peakTime))
                    .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                    .foregroundStyle(NB.white.opacity(0.42))
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(format: "%.1f", band.target))
                    .font(NBFont.dot(800, 38))
                    .foregroundStyle(NB.lime1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("RANGE %.1f – %.1f", band.optimal.lowerBound, band.optimal.upperBound))
                        .font(NBFont.dot(600, 10.5)).tracking(0.16 * 10.5)
                        .foregroundStyle(NB.white.opacity(0.42))
                    Text(L("BAND %d – %d", band.range.lowerBound, band.range.upperBound))
                        .font(NBFont.dot(600, 10.5)).tracking(0.16 * 10.5)
                        .foregroundStyle(NB.white.opacity(0.42))
                }
            }
            Text(L("Set once this morning. It does not move as the battery drops through the day."))
                .font(NBFont.brand(400, 14))
                .lineSpacing(8)
                .foregroundStyle(NB.white.opacity(0.70))
            Button { router.path = [.training] } label: {
                HStack(spacing: 8) {
                    Text(L("OPEN TRAINING"))
                        .font(NBFont.dot(600, 10.5)).tracking(0.18 * 10.5)
                        .foregroundStyle(NB.white.opacity(0.55))
                    Text(L("→"))
                        .font(NBFont.dot(700, 11))
                        .foregroundStyle(NB.lime1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .background(Color(hex: 0x0F0F13), in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
            .stroke(NB.lime1.opacity(0.22), lineWidth: 1))
    }

    private var daytimeAnchorCard: some View {
        CardBlock(title: L("DAYTIME ESTIMATE"), trailing: L("NO NIGHT REQUIRED")) {
            Text(L("Heart rate, HRV, stress and movement update this score now. A recorded night improves tomorrow's recovery and freezes its training target."))
                .font(NBFont.brand(400, 14))
                .lineSpacing(8)
                .foregroundStyle(NB.white.opacity(0.70))
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
                    HStack {
                        ForEach(["04", "10", "16", "22"], id: \.self) { t in
                            Text(t)
                                .font(NBFont.dot(600, 9)).tracking(0.18 * 9)
                                .foregroundStyle(NB.white.opacity(0.30))
                            if t != "22" { Spacer(minLength: 0) }
                        }
                    }
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
                ? L("Nothing has come off the band for this day yet.")
                : L("Connect the band to see the ticks it has been recording.")
        }
        if gone { return L("Nothing for over six hours. These are not old numbers, they are no numbers.") }
        if stale { return L("%d ticks today. Nothing new for a while — it may be off your wrist.", ticks) }
        return L("%d ticks today, five minutes apart. Stress is one of the four rows above it.", ticks)
    }

    private var confidenceCard: some View {
        CardBlock(title: L("CONFIDENCE"), trailing: m.confidence.rawValue, trailingIsDot: true) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i < tierIndex ? NB.lime1 : NB.white.opacity(0.10))
                        .frame(height: 5)
                }
            }
            Text(L("BASELINE %d / 14 NIGHTS", m.nightInputs?.rhrNights ?? 0))
                .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                .foregroundStyle(NB.text3Prod)
        }
    }

    private var tierIndex: Int {
        switch m.confidence { case .pending: 1; case .medium: 2; case .high: 3 }
    }

    private var footer: some View {
        HStack {
            Text(data.lastSync.map { "SYNCED \(Fmt.clock($0))" } ?? "NOT SYNCED YET")
                .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                .foregroundStyle(NB.text3Prod)
            Spacer(minLength: 0)
            if let wake = m.bbWake {
                Button {
                    let from = data.today.bodyBattery
                    data.today.bodyBattery = wake
                    Task {
                        await Analytics.shared.track("BB_TARGET_REANCHORED",
                                                     ["FROM": from as Any, "TO": wake,
                                                      "SOURCE": "battery_check"])
                    }
                } label: {
                    Text(L("BATTERY CHECK"))
                        .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                        .foregroundStyle(NB.text2)
                        .padding(.horizontal, 16).frame(height: 34)
                        .overlay(Capsule().stroke(NB.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
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
            Text(L("NOTHING TO CHARGE FROM YET"))
                .font(NBFont.dot(600, 11)).tracking(0.2 * 11)
                .foregroundStyle(NB.ember1)
            Text(L("The first number arrives after your first night with the band on. Nothing to do today."))
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
                NeedRow("One night with the band on your wrist")
                NeedRow("Five nights before the number settles")
                NeedRow("Fourteen nights before it knows your normal")
            }
        }
    }

    // MARK: WEEK

    private var weekBoard: some View {
        let days = weekFacts
        let avg = BodyBatteryWindowMath.averageWake(days)
        let peak = BodyBatteryWindowMath.peakDay(days)
        let night = BodyBatteryWindowMath.typicalNightCharge(days)
        return VStack(alignment: .leading, spacing: 14) {
            heroNumber(avg.map { Int($0.rounded()) }, caption: "OF 100",
                       foot: L("7-day average of morning peaks. Empty days stay out."))
            CardBlock(title: L("SEVEN DAYS"),
                      trailing: L("7D AVG %@", Fmt.int(avg.map { Int($0.rounded()) })),
                      trailingIsDot: true) {
                BodyBatteryWeekBars(values: days.map(\.wake), average: avg,
                                    todayIndex: days.indices.last)
                    .frame(height: 130)
                HStack {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                        Text(Fmt.weekday(day.day.date).prefix(1))
                            .font(NBFont.dot(i == days.count - 1 ? 700 : 500, 10))
                            .foregroundStyle(i == days.count - 1 ? NB.lime1 : Color(hex: 0x8A8A96))
                            .frame(width: 34)
                        if i < days.count - 1 { Spacer(minLength: 0) }
                    }
                }
                Text(L("Rolling 7 days. Lime is today. The average is the hero, not a sum."))
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
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
                weekStat(L("EMPTY"), L("%d DAYS", BodyBatteryWindowMath.emptyCount(days)), NB.text3Prod)
            }
        }
    }

    // MARK: MONTH

    private var monthBoard: some View {
        let days = monthFacts
        let typical = BodyBatteryWindowMath.typicalWake(days)
        let worn = BodyBatteryWindowMath.wornCount(days)
        let empty = BodyBatteryWindowMath.emptyCount(days)
        let rolls = BodyBatteryWindowMath.weekRolls(days)
        let night = BodyBatteryWindowMath.typicalNightCharge(days)
        return VStack(alignment: .leading, spacing: 14) {
            heroNumber(typical.map { Int($0.rounded()) }, caption: "30 DAYS",
                       foot: L("A typical morning peak. Not a 30-day sum."))
            CardBlock(title: L("THIRTY DAYS"),
                      trailing: L("%d WORN · %d EMPTY", worn, empty), trailingIsDot: true) {
                BodyBatteryHeatGrid(days: days, today: today)
                HStack(spacing: 6) {
                    Text(L("LOW")).font(NBFont.dot(700, 10)).foregroundStyle(Color(hex: 0x8A8A96))
                    ForEach([0.22, 0.48, 0.72, 1.0], id: \.self) { o in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(NB.lime1.opacity(o))
                            .frame(width: 20, height: 8)
                    }
                    Text(L("HIGH")).font(NBFont.dot(700, 10)).foregroundStyle(Color(hex: 0x8A8A96))
                    Spacer(minLength: 0)
                    Text(L("DASH · NOT WORN"))
                        .font(NBFont.dot(700, 10))
                        .foregroundStyle(Color(hex: 0x8A8A96))
                }
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
                BodyBatteryWeekBars(values: rolls.map { $0.average.map { Int($0.rounded()) } },
                                    average: typical,
                                    todayIndex: rolls.isEmpty ? nil : rolls.count - 1)
                    .frame(height: 72)
                HStack {
                    ForEach(Array(rolls.enumerated()), id: \.offset) { i, roll in
                        Text(L("W%d %@", i + 1, Fmt.int(roll.average.map { Int($0.rounded()) })))
                            .font(NBFont.dot(500, 9))
                            .foregroundStyle(i == rolls.count - 1 ? NB.lime1 : Color(hex: 0x8A8A96))
                        if i < rolls.count - 1 { Spacer(minLength: 0) }
                    }
                }
                Hairline()
                weekStat(L("TYPICAL MORNING"), Fmt.int(typical.map { Int($0.rounded()) }), NB.lime1)
                Hairline()
                weekStat(L("NIGHT CHARGE"),
                         night.map { L("%@ / DAY", Fmt.signed($0)) } ?? Fmt.dash,
                         NB.macroValue)
                Text(L("Four rolling weeks, each one an average of morning peaks. Empty days stay empty."))
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
        }
    }

    private func heroNumber(_ value: Int?, caption: String, foot: String) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(Fmt.int(value))
                    .font(NBFont.dot(800, 64))
                    .foregroundStyle(value == nil ? NB.text3Prod : NB.text1)
                Text(L(caption))
                    .font(NBFont.dot(600, 12)).tracking(0.18 * 12)
                    .foregroundStyle(NB.white.opacity(0.42))
            }
            Text(foot)
                .font(NBFont.ui(400, 12))
                .foregroundStyle(NB.text3Prod)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .frame(width: NB.Layout.contentWidth)
        .cardSkin()
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
                nightCharge: row.reserveDrivers?.lastNight,
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
            Text(text)
                .font(NBFont.brand(400, 13))
                .foregroundStyle(NB.text2)
        }
    }
}

private struct ContribRow: View {
    let label: String
    let value: Double
    let maxAbs: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(NBFont.brand(400, 13))
                .foregroundStyle(NB.text2)
                .frame(width: 118, alignment: .leading)
            GeometryReader { geo in
                Capsule().fill(tint)
                    .frame(width: geo.size.width * CGFloat(abs(value) / maxAbs), height: 6)
                    .offset(y: 4)
            }
            .frame(height: 14)
            Text(value > 0 ? "+\(Int(value))" : "\(Int(value))")
                .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
                .foregroundStyle(value > 0 ? NB.lime1 : NB.text2)
                .frame(width: 38, alignment: .trailing)
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

/// Lime up through the night, white down through the day, one lime dot at NOW.
/// With real samples the shape is the day's own; with none it falls back to empty.
struct BatteryCurve: View {
    var samples: [ReserveSample] = []

    /// The 318 × 120 box the board draws in. x is the 24 hours from the 04:00 cut,
    /// y is 0–100 of battery; the two are split at the peak, which is when you woke.
    private func path() -> (charge: [CGPoint], drain: [CGPoint]) {
        guard let first = samples.first else { return ([], []) }
        let day = UserDay.containing(first.ts)
        func point(_ s: ReserveSample) -> CGPoint {
            let t = min(1, max(0, s.ts.timeIntervalSince(day.start) / 86_400))
            return CGPoint(x: 4 + t * 310, y: 112 - Double(s.value) / 100 * 104)
        }
        guard samples.count > 1,
              let peak = samples.enumerated().max(by: { $0.element.value < $1.element.value })
        else {
            let only = point(first)
            return ([only], [only])
        }
        let all = samples.map(point)
        return (Array(all[...peak.offset]), Array(all[peak.offset...]))
    }

    var body: some View {
        let (charge, drain) = path()
        Canvas { ctx, size in
            let sx = size.width / 318, sy = size.height / 120
            func p(_ pt: CGPoint) -> CGPoint { CGPoint(x: pt.x * sx, y: pt.y * sy) }

            for y in [30.0, 70.0] {
                ctx.fill(Path(CGRect(x: 0, y: y * sy, width: size.width, height: 1)),
                         with: .color(NB.white.opacity(0.06)))
            }

            guard let head = charge.first, let tail = drain.last else { return }

            var area = Path()
            area.move(to: p(head))
            (charge.dropFirst() + drain.dropFirst()).forEach { area.addLine(to: p($0)) }
            area.addLine(to: p(.init(x: tail.x, y: 112)))
            area.addLine(to: p(.init(x: head.x, y: 112)))
            area.closeSubpath()
            ctx.fill(area, with: .color(NB.lime1.opacity(0.10)))

            var up = Path()
            up.move(to: p(head))
            charge.dropFirst().forEach { up.addLine(to: p($0)) }
            ctx.stroke(up, with: .color(NB.lime1),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

            if let dhead = drain.first {
                var down = Path()
                down.move(to: p(dhead))
                drain.dropFirst().forEach { down.addLine(to: p($0)) }
                ctx.stroke(down, with: .color(NB.white.opacity(0.42)),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }

            let now = p(tail)
            ctx.fill(Path(ellipseIn: CGRect(x: now.x - 4.5, y: now.y - 4.5, width: 9, height: 9)),
                     with: .color(NB.lime1))
        }
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
                for s in samples {
                    guard let v = s[keyPath: value] else { open = false; continue }
                    let t = min(1, max(0, s.ts.timeIntervalSince(day.start) / 86_400))
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
