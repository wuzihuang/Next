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

    private var m: DailyMetrics { data.today }
    private var scaled: Bool { m.targetLoad != nil }

    private var staleMinutes: Int { data.lastSync.map { Int(Date().timeIntervalSince($0) / 60) } ?? Int.max }
    private var isStale: Bool { DebugEdge.on("stale") || staleMinutes >= 60 }
    private var staleAgo: String {
        guard data.lastSync != nil else { return L("NEVER") }
        return staleMinutes >= 120 ? L("%dH AGO", staleMinutes / 60) : L("%d MIN AGO", staleMinutes)
    }
    private var lastSyncClock: String { data.lastSync.map(Fmt.clock) ?? Fmt.dash }
    private var autoHROff: Bool { DebugEdge.on("autohr") || data.capabilities.autoMeasure == .close }
    private var isOver: Bool { DebugEdge.on("over") || (m.trainingLoad ?? 0) >= 20.9 }

    private var curvePoints: [LoadPoint] {
        data.history.first(where: { $0.day == m.day && !$0.loadCurve.isEmpty })?.loadCurve ?? m.loadCurve
    }

    private var gaps: [(start: Date, end: Date)] {
        if DebugEdge.on("notworn") {
            let start = m.day.start.addingTimeInterval(9 * 3600)
            return [(start, start.addingTimeInterval(3 * 3600))]
        }
        let pts = curvePoints
        guard pts.count > 1 else { return [] }
        return zip(pts, pts.dropFirst()).compactMap { a, b in
            b.ts.timeIntervalSince(a.ts) > 7.5 * 60 ? (a.ts, b.ts) : nil
        }
    }
    private var gapMinutes: Int { Int(gaps.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60) / 5 * 5 }
    private var longestGap: (start: Date, end: Date)? {
        gaps.max { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }
    }
    private var gapsInHours: [(Double, Double)] {
        gaps.map {
            (UserDay.hours($0.start, in: m.day),
             UserDay.hours($0.end, in: m.day))
        }
    }

    private var weekFacts: [TrainingDayFacts] { facts(count: DetailWindow(.training, .week).days) }
    private var monthFacts: [TrainingDayFacts] { facts(count: DetailWindow(.training, .month).days) }
    private var latestZone: ClosedRange<Double>? { m.optimalZone }

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
        switch range {
        case .day:
            if isOver { return L("RING FULL") }
            if scaled {
                return inZone ? L("IN ZONE") : L("%.1f TO GO", max(0, (m.targetLoad ?? 0) - (m.trainingLoad ?? 0)))
            }
            return L("NO TARGET YET")
        case .week, .month:
            return L(detail.periodKey)
        }
    }

    private var headerTint: Color {
        if range == .day && !scaled { return NB.text3Prod }
        return NB.lime1
    }

    private var inZone: Bool {
        guard let load = m.trainingLoad, let zone = m.optimalZone else { return false }
        return zone.contains(load)
    }

    // MARK: DAY

    private var dayBoard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ringCard(load: m.trainingLoad, caption: "OF 21", foot: dayRingFoot)
            if scaled {
                throughTheDayCard
                dayIngredients
                timeInZoneCard
                dayMoveCard
            } else {
                gatesCard
            }
        }
    }

    private var dayRingFoot: String {
        let target = Fmt.load(m.targetLoad)
        let left = m.targetLoad.map { max(0, $0 - (m.trainingLoad ?? 0)) }
        let zone = m.optimalZone.map { String(format: "%.1f–%.1f", $0.lowerBound, $0.upperBound) } ?? Fmt.dash
        if let left {
            return L("TARGET %@ · %.1f TO GO · ZONE %@", target, left, zone)
        }
        return L("TARGET %@ · ZONE %@", target, zone)
    }

    private var throughTheDayCard: some View {
        CardBlock(title: L("THROUGH THE DAY"), trailing: L("CUMULATIVE 0–21"), trailingIsDot: true) {
            CumulativeCurve(target: m.targetLoad ?? 14.5, now: m.trainingLoad ?? 0,
                            points: curvePoints, day: m.day, gaps: gapsInHours)
                .frame(height: 120)
            HStack {
                ForEach(Array(["04", "09", "13", "NOW", "04"].enumerated()), id: \.offset) { i, t in
                    Text(t == "NOW" ? L("NOW") : t)
                        .font(NBFont.dot(t == "NOW" ? 700 : 500, 10)).tracking(0.04 * 10)
                        .foregroundStyle(t == "NOW" ? NB.lime1 : Color(hex: 0x8A8A96))
                    if i < 4 { Spacer(minLength: 0) }
                }
            }
        }
    }

    private var dayIngredients: some View {
        TrainingIngredientsCard(trailing: L("FEED THE RING"), rows: [
            .init(label: L("HR ZONES 1–3"), value: durationLine(easyMinutes)),
            .init(label: L("HR ZONES 4–5"), value: durationLine(hardMinutes), tint: NB.ember1),
            .init(label: L("STEPS"), value: Fmt.kcal(m.steps.map(Double.init))),
            .init(label: L("KCAL EST"), value: Fmt.kcal(m.eActive)),
            .init(label: L("STRENGTH"), value: strengthLine),
        ])
    }

    private var easyMinutes: Int { (m.zoneMinutes ?? []).prefix(3).reduce(0, +) }
    private var hardMinutes: Int { (m.zoneMinutes ?? []).dropFirst(3).reduce(0, +) }

    private var strengthLine: String {
        guard let seg = m.segments.filter({ !$0.allDay }).max(by: { $0.delta < $1.delta }) else {
            return Fmt.dash
        }
        let mins = seg.minutes.map(Fmt.duration) ?? Fmt.dash
        return L("%@ · +%.1f", mins, seg.delta)
    }

    private var timeInZoneCard: some View {
        let mins = paddedZones(m.zoneMinutes)
        let top = max(1, mins.max() ?? 1)
        let tints = [NB.lime1.opacity(0.33), NB.lime1.opacity(0.47), NB.lime1, NB.ember1, NB.ember1]
        let total = mins.reduce(0, +)
        return CardBlock(title: L("TIME IN EACH ZONE"),
                         trailing: L("%@ TOTAL", Fmt.duration(total)), trailingIsDot: true) {
            VStack(spacing: 9) {
                ForEach(0..<5, id: \.self) { i in
                    ZoneBar(zone: "Z\(i + 1)", fill: Double(mins[i]) / Double(top),
                            tint: tints[i], value: L("%dm", mins[i]))
                }
            }
            Text(L("Z4 and Z5 do most of the lifting. Amber marks them."))
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .lineSpacing(5)
                .foregroundStyle(NB.text3Prod)
        }
    }

    private var dayMoveCard: some View {
        let bins = hourSteps(m)
        let sessionHour = sessionBin(in: bins)
        return CardBlock(title: L("STEPS AND BURN"),
                         trailing: L("%@ STEPS", Fmt.kcal(m.steps.map(Double.init))),
                         trailingIsDot: true) {
            TrainingStepBars(bins: bins, sessionIndex: sessionHour)
                .frame(height: 96)
            HStack {
                moveStat(L("ACTIVE BURN"), Fmt.kcal(m.eActive), NB.lime1)
                moveStat(L("RESTING"), Fmt.kcal(restingKcal), NB.macroValue)
                moveStat(L("TOTAL EST"), Fmt.kcal(m.eOutNow), NB.macroValue)
            }
            Text(L("Calories are an estimate from MET and body weight, not a measurement."))
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
                Text(L("Rolling 7 days. Amber is the heaviest one. The average is the hero, not a sum."))
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            weekIngredients(days)
            CardBlock(title: L("HOW THE ZONES STACK"), trailing: L("MINUTES / DAY"), trailingIsDot: true) {
                TrainingZoneStack(days: days)
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
            Text(L("Per-day numbers, never a weekly sum. Calories are an estimate."))
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .foregroundStyle(NB.text3Prod)
        }
    }

    // MARK: MONTH

    private var monthBoard: some View {
        let days = monthFacts
        let typical = TrainingWindowMath.typicalLoad(days)
        let worn = TrainingWindowMath.wornCount(days)
        let empty = TrainingWindowMath.emptyCount(days)
        let counts = TrainingWindowMath.bandCounts(days, zone: latestZone)
        let rolls = TrainingWindowMath.weekRolls(days)
        let zones = TrainingWindowMath.typicalZones(days)
        return VStack(alignment: .leading, spacing: 14) {
            ringCard(load: typical, caption: "30 DAYS",
                     foot: L("A typical finished day. Not a 30-day sum."))
            CardBlock(title: L("THIRTY DAYS"),
                      trailing: L("%d WORN · %d EMPTY", worn, empty), trailingIsDot: true) {
                TrainingHeatGrid(days: days, zone: latestZone)
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
                    Text(L("DASH · NOT WORN"))
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
                .init(label: L("SESSION DAYS"), value: "\(TrainingWindowMath.sessionDays(days))"),
            ])
            CardBlock(title: L("WHAT THE MONTH LOOKED LIKE")) {
                monthBandRow(L("LIGHT"), counts.light, 30, NB.lime1.opacity(0.33))
                monthBandRow(L("STEADY"), counts.steady, 30, NB.lime1)
                monthBandRow(L("HEAVY"), counts.heavy + counts.over, 30, NB.ember1)
                Hairline()
                HStack {
                    Text(L("WEEK BY WEEK"))
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
                        Text(L("W%d %@", i + 1, Fmt.load(roll.average)))
                            .font(NBFont.dot(500, 9))
                            .foregroundStyle(i == rolls.count - 1 ? NB.ember1 : Color(hex: 0x8A8A96))
                        if i < rolls.count - 1 { Spacer(minLength: 0) }
                    }
                }
                Text(L("Four rolling weeks, each one an average of finished days. Empty days stay empty."))
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            monthMoveCard(days, rolls: rolls)
        }
    }

    private func monthMoveCard(_ days: [TrainingDayFacts], rolls: [TrainingWeekRoll]) -> some View {
        let typical = TrainingWindowMath.typicalSteps(days)
        let weekSteps = rolls.map { roll in
            TrainingWindowMath.typicalSteps(days.filter { $0.day >= roll.start && $0.day <= roll.end }) ?? 0
        }
        let peak = max(typical ?? 0, weekSteps.max() ?? 0, 1)
        return CardBlock(title: L("STEPS AND BURN"),
                         trailing: L("TYPICAL %@", Fmt.kcal(typical)), trailingIsDot: true) {
            VStack(spacing: 8) {
                ForEach(Array(rolls.enumerated()), id: \.offset) { i, _ in
                    let steps = weekSteps[i]
                    HStack(spacing: 8) {
                        Text(L("W%d", i + 1))
                            .font(NBFont.dot(700, 10))
                            .foregroundStyle(Color(hex: 0x8A8A96))
                            .frame(width: 26, alignment: .leading)
                        Capsule()
                            .fill(i == rolls.count - 1 ? NB.ember1 : NB.lime1.opacity(steps > 0 ? 0.85 : 0.2))
                            .frame(width: max(8, 200 * CGFloat(steps / peak)), height: 12)
                        Text(Fmt.kcal(steps > 0 ? steps : nil))
                            .font(NBFont.dot(700, 11))
                            .foregroundStyle(i == rolls.count - 1 ? NB.ember1 : NB.macroValue)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            HStack {
                moveStat(L("WORN DAYS"), L("%d OF %d", TrainingWindowMath.wornCount(days), days.count), NB.lime1)
                moveStat(L("ACTIVE BURN"), L("%@ / DAY", Fmt.kcal(TrainingWindowMath.typicalActiveKcal(days))), NB.lime1)
                moveStat(L("TOTAL EST"), L("%@ / DAY", Fmt.kcal(TrainingWindowMath.typicalTotalKcal(days))), NB.macroValue)
            }
            Text(L("Each bar is that week's typical day. Calories stay an estimate, never a measurement."))
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
                .frame(width: max(8, 200 * CGFloat(count) / CGFloat(max(1, total))), height: 14)
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
                        ? L("The band has not synced yet. Nothing here is measured.")
                        : L("The band has been out of range since %@. This is where you were, not where you are.", lastSyncClock))
        } else if isOver {
            EdgeNote(line: L("RING FULL · %.1f OVER TARGET", 21 - (m.targetLoad ?? 21)),
                     text: L("Way past %@. Tomorrow's target will already know about this.", Fmt.load(m.targetLoad)))
        }
        if autoHROff {
            EdgeNote(line: L("AUTO HR IS OFF"),
                     text: L("Steps still contribute to daily load. Enable continuous heart rate to capture exercise intensity."),
                     action: { router.open(.deviceAutoMonitor, from: .home) })
        }
        if gapMinutes >= 60, let g = longestGap {
            let hours = Int((g.end.timeIntervalSince(g.start) / 3600).rounded())
            EdgeNote(line: L("NOT ON THE WRIST %@–%@", Fmt.clock(g.start), Fmt.clock(g.end)),
                     text: hours == 1
                        ? L("The line goes flat, not up. Whatever happened in those sixty minutes isn't in today's number.")
                        : L("The line goes flat, not up. Whatever happened in those %d hours isn't in today's number.", hours))
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

    private var gatesCard: some View {
        VStack(spacing: 0) {
            GateRow(title: L("THROUGH THE DAY"), when: L("AFTER 1 FULL DAY"))
            Hairline()
            GateRow(title: L("TIME IN EACH ZONE"), when: L("AFTER 1 FULL DAY"))
            Hairline()
            GateRow(title: L("SEVEN DAYS"), when: L("AFTER 7 DAYS"))
        }
        .padding(.horizontal, 14)
        .frame(width: NB.Layout.contentWidth)
        .cardSkin()
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

    private func zoneMinutes(_ zones: [Double]?, hard: Bool) -> Int? {
        guard let zones, zones.count >= 5 else { return nil }
        let slice = hard ? Array(zones.dropFirst(3)) : Array(zones.prefix(3))
        return Int(slice.reduce(0, +).rounded())
    }

    private func hourSteps(_ row: DailyMetrics) -> [Double] {
        let ticks = data.history.first(where: { $0.day == row.day && !$0.vitalsCurve.isEmpty })?.vitalsCurve
            ?? row.vitalsCurve
        var bins = Array(repeating: 0.0, count: 12)
        for tick in ticks {
            let hour = UserDay.hours(tick.ts, in: row.day)
            guard hour >= 0, hour < 24, let steps = tick.steps, steps > 0 else { continue }
            bins[min(11, Int(hour / 2))] += Double(steps)
        }
        if bins.allSatisfy({ $0 == 0 }), let steps = row.steps {
            bins[6] = Double(steps)
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
