import SwiftUI

/// 08 / ADR 0015 · training load. One page, DAY / WEEK / MONTH. Style A is the
/// dial: the ring stays the hero, the cards under it are the ingredients that
/// built today's scalar. Back always returns to the root.
struct TrainingDetailView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @State private var rangeRaw = RollingPills.day.rawValue
    private var range: RollingPills { .parse(rangeRaw) }
    private var detail: DetailWindow { DetailWindow(.training, range) }
    private var today: UserDay { UserDay.containing(Date()) }

    private var m: DailyMetrics {
        #if DEBUG && targetEnvironment(simulator)
        return TrainingDebugFixture.metrics(data.today)
        #else
        return data.today
        #endif
    }

    private var staleMinutes: Int { data.lastSync.map { Int(Date().timeIntervalSince($0) / 60) } ?? Int.max }
    private var isStale: Bool { DebugEdge.on("stale") || staleMinutes >= 60 }
    private var staleAgo: String {
        guard data.lastSync != nil else { return L("NEVER") }
        return staleMinutes >= 120 ? L("%dH AGO", staleMinutes / 60) : L("%d MIN AGO", staleMinutes)
    }
    private var lastSyncClock: String { data.lastSync.map(Fmt.clock) ?? Fmt.dash }
    private var autoHROff: Bool { DebugEdge.on("autohr") || data.capabilities.autoMeasure == .close }
    private var rangeStatus: TrainingRangeStatus {
        DebugEdge.on("over") ? .capped
            : TrainingWindowMath.rangeStatus(load: m.trainingLoad, target: m.targetLoad, zone: m.optimalZone)
    }
    private var isOver: Bool {
        switch rangeStatus {
        case .above, .capped: return true
        default: return false
        }
    }
    private var baselineBuilding: Bool {
        (m.nightInputs?.hrvNights ?? 0) < 5 || (m.nightInputs?.rhrNights ?? 0) < 5
    }

    private var curvePoints: [LoadPoint] {
        #if DEBUG && targetEnvironment(simulator)
        if TrainingDebugFixture.name != nil { return m.loadCurve }
        #endif
        let historical = data.history.first(where: { $0.day == m.day && !$0.loadCurve.isEmpty })?.loadCurve ?? []
        return (m.loadCurve.last?.ts ?? .distantPast) >= (historical.last?.ts ?? .distantPast)
            ? m.loadCurve : historical
    }

    private var curveData: TrainingCurveData {
        TrainingWindowMath.curveData(
            curvePoints.map { TrainingCurvePoint(ts: $0.ts, load: $0.load) },
            day: m.day, through: Date())
    }
    private var gapMinutes: Int { Int(curveData.gaps.reduce(0) { $0 + $1.duration } / 60) }
    private var longestGap: DateInterval? { curveData.gaps.max { $0.duration < $1.duration } }

    private var weekFacts: [TrainingDayFacts] { facts(count: DetailWindow(.training, .week).days) }
    private var monthFacts: [TrainingDayFacts] { facts(count: DetailWindow(.training, .month).days) }

    var body: some View {
        DetailScroll(glow: NB.lime1, title: MetricNames.training, trailing: {
            Text(headerStatus)
                .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
                .foregroundStyle(headerTint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }) {
            VStack(alignment: .leading, spacing: 14) {
                SegmentedPills(options: RollingPills.words,
                               selection: $rangeRaw)
                switch range {
                case .day:   dayBoard
                case .week:  weekBoard
                case .month: monthBoard
                }
                sessionButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            router.backToRoot()
        }
        .onReceive(router.$windowRequest) { request in
            guard let request else { return }
            rangeRaw = request.rawValue
            router.windowRequest = nil
        }
        .task {
            #if DEBUG
            if let override = DetailWindow.debugRange(for: .training) {
                rangeRaw = override.rawValue
            }
            #endif
            guard !Band.allowsSeed else { return }
            await Repository.shared.hydrate(detail, endingAt: today, into: data)
        }
    }

    private var headerStatus: String {
        guard range == .day else { return L(detail.periodKey) }
        switch rangeStatus {
        case .noLoad: return L("ACTIVITY DATA NEEDED")
        case .noTarget: return L("NO TARGET YET")
        case .below(let delta): return L("%.1f BELOW RANGE", delta)
        case .inRange: return L("IN RANGE")
        case .above(let delta): return L("%.1f ABOVE RANGE", delta)
        case .capped: return L("SCALE LIMIT")
        }
    }

    private var headerTint: Color {
        if range == .day {
            if isOver { return NB.ember1 }
            if m.targetLoad == nil || m.trainingLoad == nil { return NB.text3Prod }
        }
        return NB.lime1
    }

    // MARK: DAY

    private var dayBoard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ringCard(load: m.trainingLoad, caption: "OF 21", foot: dayRingFoot)
            evidenceCard
            throughTheDayCard
            dayIngredients
            timeInZoneCard
            dayMoveCard
        }
    }

    private var dayRingFoot: String {
        guard let zone = m.optimalZone else {
            return L("No suggested range yet. Recorded activity is still shown below.")
        }
        return L("SUGGESTED RANGE %@", String(format: "%.1f–%.1f", zone.lowerBound, zone.upperBound))
    }

    private var evidenceCard: some View {
        CardBlock(title: L("ESTIMATE BASIS"),
                  trailing: m.nightInputs == nil ? L("BASELINE UNKNOWN")
                    : baselineBuilding ? L("BASELINE BUILDING") : L("RULE ESTIMATE")) {
            HStack {
                moveStat(L("HRV NIGHTS"), m.nightInputs.map { "\($0.hrvNights)" } ?? Fmt.dash, NB.lime1)
                moveStat(L("RHR NIGHTS"), m.nightInputs.map { "\($0.rhrNights)" } ?? Fmt.dash, NB.lime1)
                moveStat(L("LAST SYNC"), lastSyncClock, NB.macroValue)
            }
            Text(m.nightInputs == nil
                 ? L("No night baseline yet. The range is a rule estimate.")
                 : baselineBuilding
                 ? L("Fewer than five baseline nights. The range is an early estimate.")
                 : L("The range is a rule estimate, not a personal training dose."))
                .font(NBFont.ui(400, 11)).foregroundStyle(NB.text3Prod)
                .fixedSize(horizontal: false, vertical: true)
            Hairline()
            if let evidence = m.trainingEvidence {
                HStack {
                    moveStat(L("VALID HR"), coverageLine(evidence.heartRateMinutes, elapsed: evidence.elapsedMinutes), NB.lime1)
                    moveStat(L("RECORDED"), coverageLine(evidence.recordedMinutes, elapsed: evidence.elapsedMinutes), NB.lime1)
                    moveStat(L("ELAPSED"), Fmt.duration(evidence.elapsedMinutes), NB.macroValue)
                }
                Text(L("Coverage is valid recorded minutes against elapsed time, not time worn."))
                    .font(NBFont.ui(400, 11)).foregroundStyle(NB.text3Prod)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("Recording coverage is unavailable. Sync to retrieve it."))
                    .font(NBFont.ui(400, 11)).foregroundStyle(NB.text3Prod)
            }
            Text(L("Guidance, not an exercise quota."))
                .font(NBFont.ui(400, 11)).foregroundStyle(NB.text3Prod)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("training.evidence")
    }

    private var throughTheDayCard: some View {
        CardBlock(title: L("THROUGH THE DAY"), trailing: L("CUMULATIVE 0–21"), trailingIsDot: true) {
            CumulativeCurve(target: m.targetLoad, zone: m.optimalZone,
                            points: curvePoints, day: m.day)
                .frame(height: 120)
                .padding(.horizontal, 14)
            GeometryReader { geo in
                ForEach(0..<5, id: \.self) { index in
                    let fraction = Double(index) / 4
                    let date = m.day.start.addingTimeInterval(m.day.end.timeIntervalSince(m.day.start) * fraction)
                    Text(Fmt.clock(date))
                        .font(NBFont.dot(500, 10))
                        .foregroundStyle(NB.text3Prod)
                        .position(x: 14 + (geo.size.width - 28) * fraction, y: 7)
                }
            }
            .frame(height: 14)
            if let last = curveData.segments.last?.last {
                Text(L("LATEST LOAD SAMPLE %@", Fmt.clock(last.ts)))
                    .font(NBFont.ui(400, 10)).foregroundStyle(NB.text3Prod)
            }
            if gapMinutes > 0 {
                Text(L("Shaded intervals are missing data."))
                    .font(NBFont.ui(400, 11)).foregroundStyle(NB.text3Prod)
            }
        }
    }

    private var dayIngredients: some View {
        TrainingIngredientsCard(trailing: L("FEED THE RING"), rows: [
            .init(label: L("HR ZONES 1–3"), value: durationLine(easyMinutes)),
            .init(label: L("HR ZONES 4–5"), value: durationLine(hardMinutes), tint: NB.ember1),
            .init(label: L("STEPS"), value: Fmt.kcal(m.steps.map(Double.init))),
            .init(label: L("KCAL EST"), value: Fmt.kcal(m.eActive)),
            .init(label: L("ELEVATED HR PERIOD"), value: elevatedHRLine),
        ], note: L("The largest elevated-heart-rate period. No sport is inferred."))
    }

    private var easyMinutes: Int? { m.zoneMinutes.map { $0.prefix(3).reduce(0, +) } }
    private var hardMinutes: Int? { m.zoneMinutes.map { $0.dropFirst(3).reduce(0, +) } }

    private var elevatedHRLine: String {
        guard let seg = m.segments.filter({ !$0.allDay }).max(by: { $0.delta < $1.delta }) else {
            return Fmt.dash
        }
        let mins = seg.minutes.map(Fmt.duration) ?? Fmt.dash
        return L("%@ · %.1f SHARE", mins, seg.delta)
    }

    private var timeInZoneCard: some View {
        let mins = paddedZones(m.zoneMinutes)
        let top = max(1, mins.max() ?? 1)
        let tints = [NB.lime1.opacity(0.33), NB.lime1.opacity(0.47), NB.lime1, NB.ember1, NB.ember1]
        let total = mins.reduce(0, +)
        return CardBlock(title: L("TIME IN EACH ZONE"),
                         trailing: m.zoneMinutes == nil ? Fmt.dash : L("%@ TOTAL", Fmt.duration(total)), trailingIsDot: true) {
            VStack(spacing: 9) {
                ForEach(0..<5, id: \.self) { i in
                    ZoneBar(zone: "Z\(i + 1)", fill: Double(mins[i]) / Double(top),
                            tint: tints[i], value: m.zoneMinutes == nil ? Fmt.dash : L("%dm", mins[i]))
                }
            }
            Text(L("Estimated maximum and resting heart rate. Amber is Z4–5."))
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .lineSpacing(5)
                .foregroundStyle(NB.text3Prod)
        }
    }

    private var dayMoveCard: some View {
        let bins = hourSteps(m)
        return CardBlock(title: L("STEPS AND BURN"),
                         trailing: L("%@ STEPS", Fmt.kcal(m.steps.map(Double.init))),
                         trailingIsDot: true) {
            if let bins {
                TrainingStepBars(bins: bins, sessionIndex: sessionBin(in: bins))
                    .frame(height: 96)
                HStack {
                    Text(Fmt.clock(m.day.start))
                    Spacer()
                    Text(Fmt.clock(m.day.start.addingTimeInterval(m.day.end.timeIntervalSince(m.day.start) / 2)))
                    Spacer()
                    Text(Fmt.clock(m.day.end))
                }
                .font(NBFont.dot(500, 10)).foregroundStyle(NB.text3Prod)
            } else {
                Text(L("STEP TIMELINE UNAVAILABLE"))
                    .font(NBFont.ui(500, 11)).foregroundStyle(NB.text3Prod)
            }
            HStack {
                moveStat(L("ACTIVE BURN"), Fmt.kcal(m.eActive), NB.lime1)
                moveStat(L("RESTING"), Fmt.kcal(restingKcal), NB.macroValue)
                moveStat(L("TOTAL EST"), Fmt.kcal(m.eOutNow), NB.macroValue)
            }
            Text(L("Calories are an estimate, not a measurement."))
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .foregroundStyle(NB.text3Prod)
        }
    }

    private var restingKcal: Double? {
        guard let total = m.eOutNow, let active = m.eActive else { return m.bmr }
        return total - active
    }

    // MARK: WEEK

    private var weekBoard: some View {
        let days = weekFacts
        let avg = TrainingWindowMath.averageLoad(days)
        let heavy = days.enumerated().max(by: { ($0.element.load ?? 0) < ($1.element.load ?? 0) })?.offset
        let zones = TrainingWindowMath.typicalZones(days)
        return VStack(alignment: .leading, spacing: 14) {
            ringCard(load: avg, caption: "OF 21",
                     foot: L("7-day average of finished days. Today is not in this number."))
            CardBlock(title: L("SEVEN DAYS"),
                      trailing: L("7D AVG %@", Fmt.load(avg)), trailingIsDot: true) {
                TrainingWeekBars(values: days.map(\.load), average: avg, heavyIndex: heavy)
                    .frame(height: 130)
                HStack {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                        Text(Fmt.weekday(day.day.date).prefix(1))
                            .font(NBFont.dot(i == heavy ? 700 : 500, 10))
                            .foregroundStyle(i == heavy ? NB.ember1 : Color(hex: 0x8A8A96))
                            .frame(width: 34)
                        if i < days.count - 1 { Spacer(minLength: 0) }
                    }
                }
                Text(L("Rolling 7 days · amber is the heaviest."))
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            weekIngredients(days)
            CardBlock(title: L("HOW THE ZONES STACK"), trailing: L("MINUTES / DAY"), trailingIsDot: true) {
                TrainingZoneStack(days: days)
                Text(days.contains(where: { $0.zoneMinutes != nil })
                     ? L("SHARED SCALE · %@ MAX", Fmt.duration(Int(TrainingWindowMath.zoneScaleMinutes(days))))
                     : L("NO ZONE SAMPLES"))
                    .font(NBFont.ui(400, 10)).foregroundStyle(NB.text3Prod)
                HStack(spacing: 16) {
                    legendDot(NB.lime1.opacity(0.53), L("Z1–3 · %@", Fmt.duration(Int((zones?.prefix(3).reduce(0, +) ?? 0).rounded()))))
                    legendDot(NB.ember1, L("Z4–5 · %@", Fmt.duration(Int((zones?.dropFirst(3).reduce(0, +) ?? 0).rounded()))))
                }
            }
            weekMoveCard(days)
        }
    }

    private func weekIngredients(_ days: [TrainingDayFacts]) -> some View {
        let zones = TrainingWindowMath.typicalZones(days)
        return TrainingIngredientsCard(trailing: L("TYPICAL DAY"), rows: [
            .init(label: L("HR ZONES 1–3"), value: durationLine(zoneMinutes(zones, hard: false))),
            .init(label: L("HR ZONES 4–5"), value: durationLine(zoneMinutes(zones, hard: true)), tint: NB.ember1),
            .init(label: L("STEPS"), value: Fmt.kcal(TrainingWindowMath.typicalSteps(days))),
            .init(label: L("KCAL EST"), value: Fmt.kcal(TrainingWindowMath.typicalActiveKcal(days))),
            .init(label: L("HARD DAYS"), value: "\(TrainingWindowMath.sessionDays(days))"),
        ])
    }

    private func weekMoveCard(_ days: [TrainingDayFacts]) -> some View {
        let steps = days.map { $0.steps.map(Double.init) ?? 0 }
        let typical = TrainingWindowMath.typicalSteps(days)
        let best = steps.max() ?? 0
        return CardBlock(title: L("STEPS AND BURN"),
                         trailing: L("TYPICAL %@", Fmt.kcal(typical)), trailingIsDot: true) {
            TrainingStepBars(bins: steps, sessionIndex: steps.firstIndex(of: best))
                .frame(height: 100)
            HStack {
                moveStat(L("BEST DAY"), Fmt.kcal(best), NB.ember1)
                moveStat(L("ACTIVE BURN"), L("%@ / DAY", Fmt.kcal(TrainingWindowMath.typicalActiveKcal(days))), NB.lime1)
                moveStat(L("TOTAL EST"), L("%@ / DAY", Fmt.kcal(TrainingWindowMath.typicalTotalKcal(days))), NB.macroValue)
            }
            Text(L("Per-day, never a weekly sum."))
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .foregroundStyle(NB.text3Prod)
        }
    }

    // MARK: MONTH

    private var monthBoard: some View {
        let days = monthFacts
        let typical = TrainingWindowMath.typicalLoad(days)
        let recorded = TrainingWindowMath.recordedCount(days)
        let empty = TrainingWindowMath.emptyCount(days)
        let counts = TrainingWindowMath.bandCounts(days)
        let rolls = TrainingWindowMath.weekRolls(days)
        let zones = TrainingWindowMath.typicalZones(days)
        return VStack(alignment: .leading, spacing: 14) {
            ringCard(load: typical, caption: "30 DAYS",
                     foot: L("A typical finished day. Not a 30-day sum."))
            CardBlock(title: L("THIRTY DAYS"),
                      trailing: L("%d RECORDED · %d EMPTY", recorded, empty), trailingIsDot: true) {
                TrainingHeatGrid(days: days)
                HStack(spacing: 6) {
                    Text(L("LIGHT")).font(NBFont.dot(700, 10)).foregroundStyle(Color(hex: 0x8A8A96))
                    ForEach([0.28, 0.47, 0.72, 1.0], id: \.self) { o in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(NB.lime1.opacity(o))
                            .frame(width: 20, height: 8)
                    }
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(NB.ember1)
                        .frame(width: 20, height: 8)
                    Text(L("HEAVY")).font(NBFont.dot(700, 10)).foregroundStyle(Color(hex: 0x8A8A96))
                    Spacer(minLength: 0)
                    Text(L("DASH · NO DATA"))
                        .font(NBFont.dot(700, 10))
                        .foregroundStyle(Color(hex: 0x8A8A96))
                }
            }
            TrainingIngredientsCard(trailing: L("TYPICAL DAY"), rows: [
                .init(label: L("HR ZONES 1–3"),
                      value: durationLine(zoneMinutes(zones, hard: false))),
                .init(label: L("HR ZONES 4–5"),
                      value: durationLine(zoneMinutes(zones, hard: true)),
                      tint: NB.ember1),
                .init(label: L("STEPS"), value: Fmt.kcal(TrainingWindowMath.typicalSteps(days))),
                .init(label: L("KCAL EST"), value: Fmt.kcal(TrainingWindowMath.typicalActiveKcal(days))),
                .init(label: L("HARD DAYS"), value: "\(TrainingWindowMath.sessionDays(days))"),
            ])
            CardBlock(title: L("WHAT THE MONTH LOOKED LIKE")) {
                monthBandRow(L("LIGHT"), counts.light, 30, NB.lime1.opacity(0.33))
                monthBandRow(L("STEADY"), counts.steady, 30, NB.lime1)
                monthBandRow(L("HEAVY"), counts.heavy + counts.over, 30, NB.ember1)
                monthBandRow(L("NO TARGET"), counts.unknown, 30, NB.text3Prod)
                Text(L("Each finished day uses its own range. Today is excluded."))
                    .font(NBFont.ui(400, 11)).foregroundStyle(NB.text3Prod)
                Hairline()
                HStack {
                    Text(L("FIVE GROUPS"))
                        .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                        .foregroundStyle(NB.text1)
                    Spacer(minLength: 0)
                    Text(weekTrend(rolls))
                        .font(NBFont.dot(700, 11))
                        .foregroundStyle(NB.lime1)
                }
                TrainingWeekBars(values: rolls.map(\.average), average: typical)
                    .frame(height: 72)
                HStack {
                    ForEach(Array(rolls.enumerated()), id: \.offset) { i, roll in
                        Text(L("%dD %@", roll.days, Fmt.load(roll.average)))
                            .font(NBFont.dot(500, 9))
                            .foregroundStyle(i == rolls.count - 1 ? NB.ember1 : Color(hex: 0x8A8A96))
                        if i < rolls.count - 1 { Spacer(minLength: 0) }
                    }
                }
                Text(L("2 days, then four groups of 7."))
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            monthMoveCard(days, rolls: rolls)
        }
    }

    private func monthMoveCard(_ days: [TrainingDayFacts], rolls: [TrainingWeekRoll]) -> some View {
        let typical = TrainingWindowMath.typicalSteps(days)
        let weekSteps = rolls.map { roll in
            TrainingWindowMath.typicalSteps(days.filter { $0.day >= roll.start && $0.day <= roll.end })
        }
        let peak = max(typical ?? 0, weekSteps.compactMap { $0 }.max() ?? 0, 1)
        return CardBlock(title: L("STEPS AND BURN"),
                         trailing: L("TYPICAL %@", Fmt.kcal(typical)), trailingIsDot: true) {
            VStack(spacing: 8) {
                ForEach(Array(rolls.enumerated()), id: \.offset) { i, roll in
                    let steps = weekSteps[i]
                    HStack(spacing: 8) {
                        Text(L("%dD", roll.days))
                            .font(NBFont.dot(700, 10))
                            .foregroundStyle(Color(hex: 0x8A8A96))
                            .frame(width: 26, alignment: .leading)
                        Capsule()
                            .fill(i == rolls.count - 1 ? NB.ember1 : NB.lime1.opacity(0.85))
                            .frame(width: max(0, 200 * CGFloat((steps ?? 0) / peak)), height: 12)
                        Text(Fmt.kcal(steps))
                            .font(NBFont.dot(700, 11))
                            .foregroundStyle(i == rolls.count - 1 ? NB.ember1 : NB.macroValue)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            HStack {
                moveStat(L("RECORDED DAYS"), L("%d OF %d", TrainingWindowMath.recordedCount(days), days.count), NB.lime1)
                moveStat(L("ACTIVE BURN"), L("%@ / DAY", Fmt.kcal(TrainingWindowMath.typicalActiveKcal(days))), NB.lime1)
                moveStat(L("TOTAL EST"), L("%@ / DAY", Fmt.kcal(TrainingWindowMath.typicalTotalKcal(days))), NB.macroValue)
            }
            Text(L("Each bar is that group's typical day."))
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .foregroundStyle(NB.text3Prod)
        }
    }

    private func weekTrend(_ rolls: [TrainingWeekRoll]) -> String {
        let values = rolls.compactMap(\.average)
        guard let first = values.first, let last = values.last, values.count >= 2 else {
            return L("NO TREND YET")
        }
        return last >= first ? L("TRENDING UP") : L("TRENDING DOWN")
    }

    private func monthBandRow(_ label: String, _ count: Int, _ total: Int, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(NBFont.dot(700, 10))
                .foregroundStyle(Color(hex: 0x8A8A96))
                .frame(width: 52, alignment: .leading)
            Capsule().fill(tint)
                .frame(width: max(0, 200 * CGFloat(count) / CGFloat(max(1, total))), height: 14)
            Text(L("%d DAYS", count))
                .font(NBFont.dot(700, 11))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: shared chrome

    private func ringCard(load: Double?, caption: String, foot: String) -> some View {
        VStack(spacing: 18) {
            BigTrainingRing(load: load, target: range == .day ? m.targetLoad : nil,
                            zone: range == .day ? m.optimalZone : nil,
                            tint: isOver && range == .day ? NB.ember1 : isStale && range == .day ? Color(hex: 0x6B7039) : NB.lime1,
                            heroTint: isStale && range == .day ? Color(hex: 0xB8B46A) : nil,
                            over: isOver && range == .day,
                            caption: caption)
                .frame(width: 200, height: 200)

            if range == .day { dayEdges }

            Text(foot)
                .font(NBFont.ui(400, 12))
                .foregroundStyle(NB.text3Prod)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 20)
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .frame(width: NB.Layout.contentWidth)
        .cardSkin()
    }

    @ViewBuilder
    private var dayEdges: some View {
        if isStale {
            EdgeNote(sub: L("AS OF %@", lastSyncClock), line: L("LAST SYNC %@", staleAgo),
                     text: data.lastSync == nil
                        ? L("No sync time yet. Records may be incomplete.")
                        : L("Synced %@. Later activity may be missing.", lastSyncClock))
        }
        if isOver {
            EdgeNote(line: headerStatus,
                     text: L("Already above the suggested range. Nothing left to fill."))
        }
        if autoHROff {
            EdgeNote(line: L("AUTO HR IS OFF"),
                     text: L("Steps still count. Turn on continuous heart rate for intensity."),
                     action: { router.open(.deviceAutoMonitor, from: .home) })
        }
        if gapMinutes >= 60, let gap = longestGap {
            EdgeNote(line: L("DATA MISSING %@–%@", Fmt.clock(gap.start), Fmt.clock(gap.end)),
                     text: L("Activity in this interval may not be included."))
        }
    }

    private var sessionButton: some View {
        VStack(spacing: 8) {
            Button {
                router.path = [.sportMode]
            } label: {
                Text(L("START A SESSION"))
                    .font(NBFont.ui(500, 12)).tracking(0.2 * 12)
                    .foregroundStyle(NB.carbon)
                    .frame(width: NB.Layout.contentWidth, height: 48)
                    .background(NB.lime1, in: Capsule())
            }
            .buttonStyle(.plain)
            Text(L("PICK A MODE · THE BAND RUNS IT"))
                .font(NBFont.dot(500, 9.5)).tracking(0.14 * 9.5)
                .foregroundStyle(NB.text3Prod)
        }
        .padding(.top, 6)
    }

    private func moveStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(NBFont.ui(400, 10)).tracking(0.14 * 10)
                .foregroundStyle(Color(hex: 0x8A8A96))
            Text(value)
                .font(NBFont.dot(700, 15))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .font(NBFont.dot(700, 10))
                .foregroundStyle(Color(hex: 0x8A8A96))
        }
    }

    private func facts(count: Int) -> [TrainingDayFacts] {
        today.rollingBack(count).map { day in
            let row = day == today ? m : (data.history.first { $0.day == day } ?? DailyMetrics(day: day))
            return TrainingDayFacts(
                day: day,
                load: row.trainingLoad,
                target: row.targetLoad,
                zone: row.optimalZone,
                zoneMinutes: row.zoneMinutes,
                steps: row.steps,
                activeKcal: row.eActive,
                totalKcal: row.eOutNow,
                worn: row.worn,
                isOpen: day == today && !day.isClosed)
        }
    }

    private func paddedZones(_ zones: [Int]?) -> [Int] {
        var mins = zones ?? []
        while mins.count < 5 { mins.append(0) }
        return Array(mins.prefix(5))
    }

    private func durationLine(_ minutes: Int?) -> String {
        minutes.map(Fmt.duration) ?? Fmt.dash
    }

    private func coverageLine(_ minutes: Int, elapsed: Int) -> String {
        guard elapsed > 0 else { return Fmt.dash }
        let percent = Int((100 * Double(minutes) / Double(elapsed)).rounded())
        return L("%d%% · %@", min(100, max(0, percent)), Fmt.duration(minutes))
    }

    private func zoneMinutes(_ zones: [Double]?, hard: Bool) -> Int? {
        guard let zones, zones.count >= 5 else { return nil }
        let slice = hard ? Array(zones.dropFirst(3)) : Array(zones.prefix(3))
        return Int(slice.reduce(0, +).rounded())
    }

    private func hourSteps(_ row: DailyMetrics) -> [Double]? {
        let ticks = data.history.first(where: { $0.day == row.day && !$0.vitalsCurve.isEmpty })?.vitalsCurve
            ?? row.vitalsCurve
        guard ticks.contains(where: { $0.steps != nil }) else { return nil }
        var bins = Array(repeating: 0.0, count: 12)
        for tick in ticks {
            guard tick.ts >= row.day.start, tick.ts < row.day.end, let steps = tick.steps, steps > 0 else { continue }
            bins[min(11, Int(TrainingWindowMath.dayFraction(tick.ts, day: row.day) * 12))] += Double(steps)
        }
        return bins
    }

    private func sessionBin(in bins: [Double]) -> Int? {
        guard let seg = m.segments.first(where: { !$0.allDay }) else {
            return bins.enumerated().max(by: { $0.element < $1.element })?.offset
        }
        let hour = UserDay.hours(seg.at, in: m.day)
        guard hour >= 0, hour < 24 else { return nil }
        return min(11, Int(hour / 2))
    }
}

struct SegmentedPills: View {
    let options: [String]
    @Binding var selection: String

    static let height: CGFloat = 44
    private static let inset: CGFloat = 3

    var body: some View {
        HStack(spacing: Self.inset) {
            ForEach(options, id: \.self) { o in
                let selected = selection == o
                Button {
                    guard !selected else { return }
                    selection = o
                } label: {
                    Text(L(o))
                        .font(NBFont.ui(selected ? 600 : 500, 12)).tracking(0.14 * 12)
                        .foregroundStyle(selected ? NB.text1 : NB.text3Prod)
                        .frame(maxWidth: .infinity, minHeight: Self.height - Self.inset * 2)
                        .background(selected ? NB.barTrack : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("range.\(o)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Self.inset)
        .frame(width: NB.Layout.contentWidth, height: Self.height)
        .background(NB.carbon4, in: Capsule())
        .overlay(Capsule().stroke(NB.hairline, lineWidth: 1))
    }
}

struct CardSkin: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
                .stroke(NB.hairline, lineWidth: 1))
    }
}
extension View { func cardSkin() -> some View { modifier(CardSkin()) } }

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(NBFont.ui(500, 11)).tracking(0.24 * 11)
            .foregroundStyle(Color(hex: 0x8A8A96))
            .padding(.leading, 2)
            .padding(.top, 8)
    }
}

struct CardBlock<Content: View>: View {
    let title: String
    var trailing: String? = nil
    var trailingIsDot = false
    var trailingTint: Color? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                    .foregroundStyle(NB.text1)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing)
                        .font(trailingIsDot ? NBFont.dot(700, 12) : NBFont.ui(500, 11))
                        .tracking((trailingIsDot ? 0.04 : 0.06) * (trailingIsDot ? 12 : 11))
                        .foregroundStyle(trailingTint ?? (trailingIsDot ? NB.macroValue : NB.text3Prod))
                }
            }
            content
        }
        .padding(14)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
    }
}

struct GateRow: View {
    let title: String
    let when: String
    var body: some View {
        HStack {
            Text(title)
                .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                .foregroundStyle(NB.text2)
            Spacer(minLength: 0)
            Text(when)
                .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                .foregroundStyle(NB.text3Prod)
        }
        .frame(height: 44)
    }
}
