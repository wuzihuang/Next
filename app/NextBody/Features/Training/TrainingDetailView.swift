import SwiftUI

/// 08 · 训练详情 Training Load. Nine sections, from the ring all the way to
/// "so what do I do now". Back always returns to the root; there is no history stack here.
struct TrainingDetailView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router


    private var m: DailyMetrics { data.today }
    private var scaled: Bool { m.targetLoad != nil }

    // 08 edge 1 · STALE is judged by the last successful sync, never by the connection —
    // 「连着但没同步也算陈旧」.
    // No sync yet is the stalest a page can be: the ring is standing on nothing.
    private var staleMinutes: Int { data.lastSync.map { Int(Date().timeIntervalSince($0) / 60) } ?? Int.max }
    private var isStale: Bool { DebugEdge.on("stale") || staleMinutes >= 60 }
    private var staleAgo: String {
        guard data.lastSync != nil else { return L("NEVER") }
        return staleMinutes >= 120 ? L("%dH AGO", staleMinutes / 60) : L("%d MIN AGO", staleMinutes)
    }
    private var lastSyncClock: String { data.lastSync.map(Fmt.clock) ?? Fmt.dash }
    // 08 edge 2 · the whole page stands on auto heart rate (funType 0); off is 「残」, not empty.
    private var autoHROff: Bool { DebugEdge.on("autohr") || data.capabilities.autoMeasure == .close }
    // 08 edge 5 · the ring caps at 21 and turns amber. F2's curve is asymptotic to 21, so the
    // cap is reached at the rounding limit, and there is no raw value to print beside it.
    private var isOver: Bool { DebugEdge.on("over") || (m.trainingLoad ?? 0) >= 20.9 }
    /// 08 rule 07 · a missing five-minute tick is a gap. Gaps are multiples of five minutes.
    private var gaps: [(start: Date, end: Date)] {
        if DebugEdge.on("notworn") {
            let d = Calendar.current.startOfDay(for: m.day.date)
            return [(d.addingTimeInterval(13 * 3600), d.addingTimeInterval(16 * 3600))]
        }
        let pts = data.history.first(where: { $0.day == m.day && !$0.loadCurve.isEmpty })?.loadCurve ?? m.loadCurve
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
        let midnight = Calendar.current.startOfDay(for: m.day.date)
        return gaps.map { ($0.start.timeIntervalSince(midnight) / 3600, $0.end.timeIntervalSince(midnight) / 3600) }
    }

    var body: some View {
        // 01 · header & range. "2.1 TO GO" sits on the title line because it is the one
        // conclusion this page has.
        //
        // ⚠️ The DAY / WEEK / MONTH control is deliberately absent, not forgotten.
        // ZUO · "留一个死控件比没有更糟", and 1EIH settles the disagreement between this
        // board (which said build the screens or disable the control) and 09 (which said
        // delete it) with "以删为准，两页保持一致". WEEK's job is already done by THIS
        // WEEK at the foot of the page, and MONTH has no content on seven days of data.
        // 1EEU lists the segmented control itself as out of V1 for both 08 and 09.
        DetailScroll(glow: NB.cyan1, title: MetricNames.training, trailing: {
            Text(isOver ? L("RING FULL")
                 : scaled ? L("%.1f TO GO", max(0, (m.targetLoad ?? 0) - (m.trainingLoad ?? 0)))
                          : L("NO TARGET YET"))
                .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
                .foregroundStyle(scaled ? NB.cyanPale : NB.text3Prod)
        }) {
            VStack(alignment: .leading, spacing: 14) {
                // 02 · ring & legend
                ringCard

                // 03 · why this number — the trust of the whole page
                whyCard

                SectionLabel(scaled ? L("WHERE IT CAME FROM") : L("WHERE IT WILL COME FROM"))

                // 04 · today's build
                buildCard

                if scaled {
                    // 06 · through the day — cumulative, never a rate
                    throughTheDayCard
                    // 07 · time in zone
                    timeInZoneCard
                    // 08 · this week
                    thisWeekCard
                } else {
                    gatesCard
                }

                // 09 · the one CTA. Opens the same Sport Mode picker as the plus menu —
                // that page is the in-session screen this board was waiting for.
                VStack(spacing: 8) {
                    Button {
                        // F1 · no path between two detail pages — replace the stack.
                        router.path = [.sportMode]
                    } label: {
                        Text(L("START A SESSION"))
                            .font(NBFont.ui(500, 12)).tracking(0.2 * 12)
                            .foregroundStyle(NB.carbon)
                            .frame(width: NB.Layout.contentWidth, height: 48)
                            .background(NB.cyan1, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Text(L("PICK A MODE · THE BAND RUNS IT"))
                        .font(NBFont.dot(500, 9.5)).tracking(0.14 * 9.5)
                        .foregroundStyle(NB.text3Prod)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            router.backToRoot()
        }
    }

    private var ringCard: some View {
        VStack(spacing: 18) {
            BigTrainingRing(load: m.trainingLoad, target: m.targetLoad, zone: m.optimalZone,
                            tint: isOver ? NB.ember1 : isStale ? Color(hex: 0x2E6C7A) : NB.cyan1,
                            heroTint: isStale ? Color(hex: 0x7FA8B0) : nil, over: isOver)
                .frame(width: 200, height: 200)

            // 08 edge cases · every degradation happens here, in place: one status line and its
            // colour, at most a sentence. No modal, no full-page error, no bounce home.
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
                         text: L("Steps alone can't move the ring. Turn continuous heart rate back on and today rebuilds itself."),
                         action: { router.open(.deviceAutoMonitor, from: .home) })
            }
            if gapMinutes >= 60, let g = longestGap {
                let hours = Int((g.end.timeIntervalSince(g.start) / 3600).rounded())
                EdgeNote(line: L("NOT ON THE WRIST %@–%@", Fmt.clock(g.start), Fmt.clock(g.end)),
                         text: hours == 1
                            ? L("The line goes flat, not up. Whatever happened in those sixty minutes isn't in today's number.")
                            : L("The line goes flat, not up. Whatever happened in those %d hours isn't in today's number.", hours))
            }

            VStack(spacing: 11) {
                Hairline()
                LegendRow(swatch: .bar(NB.cyan1, 7), label: L("TRAINING NOW"),
                          labelColor: NB.text1, value: Fmt.load(m.trainingLoad), valueColor: NB.cyan1, bold: true)
                LegendRow(swatch: .bar(NB.cyan2, 5), label: L("OPTIMAL ZONE"),
                          labelColor: NB.text2,
                          value: m.optimalZone.map { String(format: "%.1f – %.1f", $0.lowerBound, $0.upperBound) } ?? Fmt.dash,
                          valueColor: NB.macroValue, bold: false)
                LegendRow(swatch: .dot(NB.cyanPale), label: L("TARGET"),
                          labelColor: NB.text2, value: Fmt.load(m.targetLoad),
                          valueColor: NB.cyanPale, bold: true)
                LegendRow(swatch: .bar(Color(hex: 0x33333D), 5), label: L("FULL RING"),
                          labelColor: NB.text3Prod, value: L("21.0 MAX"),
                          valueColor: Color(hex: 0x8A8A96), bold: false)
            }
            .frame(width: 330)
        }
        .padding(.top, 20)
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .frame(width: NB.Layout.contentWidth)
        .cardSkin()
    }

    /// The night behind this morning's number. HRV is normally absent on iOS, and an absent
    /// input has to read "——" here as much as it does on 13 — this is the line that earns
    /// the number above it.
    private var nightLine: String {
        let n = m.nightInputs
        let hrv = n?.hrv.map { L("HRV %d MS", Int($0)) } ?? L("HRV %@", Fmt.dash)
        let rhr = n?.rhr.map { L("RHR %d BPM", Int($0)) } ?? L("RHR %@", Fmt.dash)
        let word = m.reserveDrivers.map { L(BodyBattery.chargeWord(Int($0.lastNight.rounded()))) }
            ?? L("CHARGED OVERNIGHT")
        return L("%@ · %@ · %@", hrv, rhr, word)
    }

    /// Where the target sits on a ring that runs to 21. The board prints 69% because its
    /// day targets 14.5; the number moves with the target, so it is computed.
    private var ringShare: String {
        guard let t = m.targetLoad else { return Fmt.dash }
        return "\(Int((t / 21 * 100).rounded()))%"
    }

    /// The only line on this card that looks at history rather than at today.
    /// Today is not in the average — only finished days are.
    private var sevenDayAverage: Double? {
        let past = data.history.filter { $0.day < m.day }.suffix(7).compactMap(\.trainingLoad)
        guard !past.isEmpty else { return nil }
        return past.reduce(0, +) / Double(past.count)
    }

    /// A day counts as a session when it spent 20 minutes at Z4 or above — the zone where
    /// the ring actually moves.
    private var daysSinceSession: Int? {
        let past = data.history.filter { $0.day < m.day }.reversed()
        for (i, day) in past.enumerated() {
            let hard = (day.zoneMinutes?.dropFirst(3).reduce(0, +)) ?? 0
            if hard >= 20 { return i + 1 }
        }
        return nil
    }

    private var recentWord: String {
        guard let avg = sevenDayAverage else { return Fmt.dash }
        guard let zone = m.optimalZone else { return Fmt.load(avg) }
        if avg < zone.lowerBound { return L("LIGHT") }
        if avg > zone.upperBound { return L("HEAVY") }
        return L("STEADY")
    }

    private var recentDetail: String {
        let since = daysSinceSession.map {
            $0 == 1 ? L("%d DAY SINCE YOUR LAST SESSION", $0) : L("%d DAYS SINCE YOUR LAST SESSION", $0)
        } ?? L("NO SESSION ON RECORD")
        return L("%@ · 7D AVG %@", since, Fmt.load(sevenDayAverage))
    }

    /// 03 · a four-link causal chain, in order: this morning's charge → the target on the ring
    /// → the acceptable band → the recent load. The last line is the only one worth having:
    /// it looks at history instead of at today.
    private var whyCard: some View {
        CardBlock(title: scaled ? L("WHY %@", Fmt.load(m.targetLoad)) : L("WHAT THE RING NEEDS"),
                  trailing: scaled ? L("%@ DECIDES IT", MetricNames.bodyBattery) : L("0 OF 4 READY")) {
            VStack(alignment: .leading, spacing: 13) {
                ReasonLine(dot: NB.optimal2, title: L("%@ THIS MORNING", MetricNames.bodyBattery),
                           value: m.bbWake.map { "\($0)%" } ?? Fmt.dash, valueColor: NB.optimal2,
                           detail: scaled ? nightLine : L("ONE NIGHT OF SLEEP ON THE BAND"))
                ReasonLine(dot: NB.cyanPale, title: L("TARGET ON THE RING"),
                           value: Fmt.load(m.targetLoad), valueColor: NB.cyanPale,
                           detail: scaled ? L("%@ LANDS AT %@ OF THE FULL RING", Fmt.pct(m.bbWake), ringShare)
                                          : L("%@ DECIDES IT — NOTHING TO DECIDE FROM YET", MetricNames.bodyBattery))
                ReasonLine(dot: NB.cyan2, title: L("OPTIMAL ZONE"),
                           value: m.optimalZone.map { String(format: "%.1f – %.1f", $0.lowerBound, $0.upperBound) } ?? Fmt.dash,
                           valueColor: NB.macroValue,
                           detail: scaled ? L("ANYWHERE IN HERE COUNTS AS HITTING THE DAY")
                                          : L("THE ZONE MOVES WITH THE TARGET"))
                ReasonLine(dot: NB.ember1, title: L("RECENT LOAD"),
                           value: scaled ? recentWord : L("NONE"), valueColor: NB.ember1,
                           detail: scaled ? recentDetail
                                          : L("NO SESSIONS ON RECORD · 7D AVG %@", Fmt.dash))
            }
        }
    }

    private func detail(for seg: TrainingSegment) -> String {
        if seg.allDay {
            let steps = Fmt.kcal(seg.steps.map(Double.init))
            return L("%@ STEPS · NEVER LEFT Z1", steps)
        }
        let mins = seg.minutes.map(Fmt.duration) ?? Fmt.dash
        let hr = seg.avgHR.map { L("AVG %d BPM", $0) } ?? Fmt.dash
        return L("%@ · %@", mins, hr)
    }

    /// 05 · one suggestion, never a list — and it has to be sized to the gap that is
    /// actually left, not to a number printed on the board.
    private var suggestion: (title: String, delta: Double) {
        let gap = max(0, (m.targetLoad ?? 0) - (m.trainingLoad ?? 0))
        if gap >= 8 { return (L("STRENGTH · 45 MIN"), gap) }
        if gap >= 3 { return (L("STRENGTH · 30 MIN"), gap) }
        return (L("EASY WALK · 20 MIN"), gap)
    }

    /// 04 · the number on the ring must be breakable into parts. The time column is a fixed
    /// slot so ALL DAY sits in the same lane as a clock time.
    private var buildCard: some View {
        CardBlock(title: L("TODAY'S BUILD"),
                  trailing: scaled
                    ? (m.segments.count == 1
                       ? L("%d SOURCE · %@ TOTAL", m.segments.count, Fmt.load(m.trainingLoad))
                       : L("%d SOURCES · %@ TOTAL", m.segments.count, Fmt.load(m.trainingLoad)))
                    : L("0 SOURCES · 0.0 TOTAL")) {
            if scaled && !m.segments.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(m.segments.enumerated()), id: \.element.id) { i, seg in
                        if i > 0 { Hairline() }
                        BuildRow(time: seg.allDay ? L("ALL DAY") : Fmt.clock(seg.at),
                                 name: seg.name, detail: detail(for: seg),
                                 delta: "+\(String(format: "%.1f", seg.delta))",
                                 timeIsLabel: seg.allDay)
                    }
                }
                // 05 · one suggestion, never a list. It sits last and is drawn in a dashed
                // box so it can't be mistaken for something already done.
                NextSuggestion(title: suggestion.title,
                               detail: L("PUTS YOU AT %@ — IN ZONE", Fmt.load(m.targetLoad)),
                               delta: "+\(String(format: "%.1f", suggestion.delta))")
            } else {
                VStack(spacing: 8) {
                    Text(L("NOTHING HAS COME IN YET"))
                        .font(NBFont.ui(500, 12)).tracking(0.14 * 12)
                        .foregroundStyle(NB.text2)
                    Text(L("WALKS, RIDES, ELEVATED HR AND STEPS ALL LAND HERE ONCE THE BAND IS ON YOUR WRIST"))
                        .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .foregroundStyle(NB.text3Prod)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .overlay(RoundedRectangle(cornerRadius: NB.R.tile, style: .continuous)
                    .strokeBorder(NB.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            }
        }
    }

    private var throughTheDayCard: some View {
        CardBlock(title: L("THROUGH THE DAY"), trailing: L("CUMULATIVE · 0–21")) {
            CumulativeCurve(target: m.targetLoad ?? 14.5, now: m.trainingLoad ?? 0,
                            points: m.loadCurve, day: m.day, gaps: gapsInHours)
                .frame(height: 120)
            HStack {
                ForEach(["00", "06", "12", "NOW", "24"], id: \.self) { t in
                    Text(t == "NOW" ? L("NOW") : t)
                        .font(NBFont.dot(t == "NOW" ? 700 : 500, 10)).tracking(0.04 * 10)
                        .foregroundStyle(t == "NOW" ? NB.cyan1 : Color(hex: 0x8A8A96))
                    if t != "24" { Spacer(minLength: 0) }
                }
            }
        }
    }

    /// 07 · zone time. ⚠️ Any zone duration is a multiple of 5 — the raw points are 5 minutes apart.
    private var timeInZoneCard: some View {
        let mins = m.zoneMinutes ?? [0, 0, 0, 0, 0]
        let top = max(1, mins.max() ?? 1)
        let tints = [NB.cyanDeep, NB.cyan1, NB.lime2, NB.ember1, NB.alert2]
        let hard = mins.dropFirst(3).reduce(0, +)
        return CardBlock(title: L("TIME IN ZONE"),
                         trailing: L("%@ ELEVATED", Fmt.duration(mins.reduce(0, +))), trailingIsDot: true) {
            VStack(spacing: 9) {
                ForEach(0..<5, id: \.self) { i in
                    ZoneBar(zone: "Z\(i + 1)", fill: Double(mins[i]) / Double(top),
                            tint: tints[i], value: Fmt.duration(mins[i]))
                }
            }
            Hairline()
            Text(L("Z4 AND ABOVE IS WHERE THE RING MOVES FAST — %@ TODAY, AGAINST %@ ON YOUR HARDEST DAY THIS WEEK.", Fmt.duration(hard), Fmt.duration(hardBest)))
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .lineSpacing(5)
                .foregroundStyle(NB.text3Prod)
        }
    }

    /// The comparison the footnote makes has to be a day that actually happened.
    private var hardBest: Int {
        data.history.filter { $0.day < m.day }.suffix(7)
            .map { ($0.zoneMinutes?.dropFirst(3).reduce(0, +)) ?? 0 }.max() ?? 0
    }

    /// 08 · it answers "how have I been lately", so it lives at the very bottom.
    /// Today is not counted into the average; only finished days are.
    private var thisWeekCard: some View {
        // Seven days ending today. The average excludes today, because a day in progress
        // would drag it down every morning and nobody would trust the line.
        let week = Array(data.history.suffix(7))
        let values = week.map { $0.trainingLoad ?? 0 }
        let avg = sevenDayAverage ?? 0
        let labels = week.map { Fmt.weekday($0.day.date) }
        return CardBlock(title: L("THIS WEEK"), trailing: L("7D AVG %@", Fmt.load(sevenDayAverage)),
                         trailingIsDot: true) {
            WeekBars(values: values, average: avg)
                .frame(height: 88)
            HStack {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, d in
                    Text(d)
                        .font(NBFont.dot(i == labels.count - 1 ? 700 : 500, 10))
                        .foregroundStyle(i == labels.count - 1 ? NB.cyan1 : Color(hex: 0x8A8A96))
                        .frame(width: 34)
                    if i < labels.count - 1 { Spacer(minLength: 0) }
                }
            }
        }
    }

    /// 05 (empty state) · the three gates. Curve, zones and week bars do not hold on day one,
    /// so they are not drawn empty — only titled, with the condition that unlocks them.
    private var gatesCard: some View {
        VStack(spacing: 0) {
            GateRow(title: L("THROUGH THE DAY"), when: L("AFTER 1 FULL DAY"))
            Hairline()
            GateRow(title: L("TIME IN ZONE"), when: L("AFTER 1 FULL DAY"))
            Hairline()
            GateRow(title: L("THIS WEEK"), when: L("AFTER 7 DAYS"))
        }
        .padding(.horizontal, 14)
        .frame(width: NB.Layout.contentWidth)
    }
}

struct SegmentedPills: View {
    let options: [String]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { o in
                Button { selection = o } label: {
                    Text(L(o))
                        .font(NBFont.ui(500, 11)).tracking(0.14 * 11)
                        .foregroundStyle(selection == o ? NB.text1 : NB.text3Prod)
                        .padding(.vertical, 7).padding(.horizontal, 17)
                        .background(selection == o ? NB.barTrack : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
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
    // 09 / 10 edges · the card head's qualifier turns amber when it names a degradation.
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

enum LegendSwatch { case bar(Color, CGFloat), dot(Color) }

struct LegendRow: View {
    let swatch: LegendSwatch
    let label: String
    let labelColor: Color
    let value: String
    let valueColor: Color
    let bold: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                switch swatch {
                case .bar(let c, let h):
                    Capsule().fill(c).frame(width: 22, height: h)
                case .dot(let c):
                    Circle().fill(c).frame(width: 9, height: 9).padding(.leading, 7)
                }
            }
            .frame(width: 26, alignment: .leading)

            Text(label)
                .font(NBFont.ui(500, 11)).tracking(0.14 * 11)
                .foregroundStyle(labelColor)
            Spacer(minLength: 0)
            Text(value)
                .font(NBFont.dot(bold ? 700 : 500, 13)).tracking(0.02 * 13)
                .foregroundStyle(valueColor)
                .frame(width: 96, alignment: .trailing)
        }
    }
}

struct ReasonLine: View {
    let dot: Color
    let title: String
    let value: String
    let valueColor: Color
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(title)
                    .font(NBFont.ui(500, 12)).tracking(0.06 * 12)
                    .foregroundStyle(NB.text1)
                Spacer(minLength: 0)
                Text(value)
                    .font(NBFont.dot(700, 13)).tracking(0.02 * 13)
                    .foregroundStyle(valueColor)
            }
            Text(detail)
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .foregroundStyle(NB.text3Prod)
                .padding(.leading, 15)
        }
    }
}

struct BuildRow: View {
    let time: String
    let name: String
    let detail: String
    let delta: String
    var timeIsLabel = false

    var body: some View {
        HStack(spacing: 10) {
            Text(time)
                .font(timeIsLabel ? NBFont.ui(500, 10) : NBFont.dot(500, 11))
                .tracking((timeIsLabel ? 0.1 : 0.02) * (timeIsLabel ? 10 : 11))
                .foregroundStyle(Color(hex: 0x8A8A96))
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(NBFont.ui(600, 13))
                    .foregroundStyle(NB.text1)
                Text(detail)
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
            Spacer(minLength: 0)
            Text(delta)
                .font(NBFont.dot(700, 14)).tracking(0.02 * 14)
                .foregroundStyle(NB.cyan1)
                .frame(width: 46, alignment: .trailing)
        }
    }
}

struct NextSuggestion: View {
    let title: String
    let detail: String
    let delta: String

    var body: some View {
        HStack(spacing: 10) {
            Text(L("NEXT"))
                .font(NBFont.ui(500, 10)).tracking(0.1 * 10)
                .foregroundStyle(NB.cyan2)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(NBFont.ui(600, 13))
                    .foregroundStyle(NB.cyanPale)
                Text(detail)
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .foregroundStyle(Color(hex: 0x7FCEDD))
            }
            Spacer(minLength: 0)
            Text(delta)
                .font(NBFont.dot(700, 14)).tracking(0.02 * 14)
                .foregroundStyle(NB.cyan1)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(12)
        .background(Color(hex: 0x0C1A1E), in: RoundedRectangle(cornerRadius: NB.R.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.tile, style: .continuous)
            .strokeBorder(NB.cyan1.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
}

struct ZoneBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let zone: String
    let fill: Double
    let tint: Color
    let value: String

    @State private var grown: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            Text(zone)
                .font(NBFont.ui(500, 11)).tracking(0.06 * 11)
                .foregroundStyle(NB.macroLabel)
                .frame(width: 22, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0x1A1A20))
                    Capsule().fill(tint).frame(width: geo.size.width * grown)
                }
            }
            .frame(height: 8)
            Text(value)
                .font(NBFont.dot(500, 11)).tracking(0.02 * 11)
                .foregroundStyle(NB.macroValue)
                .frame(width: 56, alignment: .trailing)
        }
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7)) { grown = fill } }
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

/// The 200pt version of the ring. Same ruler, same three lanes.
struct BigTrainingRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let load: Double?
    let target: Double?
    let zone: ClosedRange<Double>?
    /// 08 edges · stale desaturates, over the ring turns amber. The shape never changes.
    var tint: Color = NB.cyan1
    var heroTint: Color? = nil
    var over = false
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().strokeBorder(NB.ringTrack, lineWidth: 14)
                .frame(width: 186, height: 186)
            RingArc(from: 0, to: shown / 21)
                .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .frame(width: 172, height: 172)
            if over {
                // 08 edge 5 · capped at 21 with a dotted halo, never a second lap.
                Circle().stroke(NB.ember1.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [2, 6]))
                    .frame(width: 200, height: 200)
            }
            if let zone {
                RingArc(from: zone.lowerBound / 21, to: zone.upperBound / 21)
                    .stroke(NB.cyan2, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 194, height: 194)
            }
            if let target {
                let a = Angle.degrees(360 * target / 21 - 90)
                Circle().fill(NB.cyanPale)
                    .frame(width: 9, height: 9)
                    .offset(x: 97 * cos(a.radians), y: 97 * sin(a.radians))
            }
            VStack(spacing: 6) {
                Text(Fmt.load(load))
                    .font(NBFont.dot(700, 46)).tracking(-0.02 * 46)
                    .foregroundStyle(load == nil ? NB.text3Prod : (heroTint ?? tint))
                Text(L("OF 21"))
                    .font(NBFont.ui(500, 11)).tracking(0.22 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
        }
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { shown = load ?? 0 } }
        // F5 §09 · VoiceOver reads one element — "Training load 14.5 out of 21" — not the arc,
        // not the percentage, not the dot. The paths underneath are hidden as children.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(MetricNames.trainingLoad.capitalized) \(Fmt.load(load)) out of 21")
    }
}

/// 06 · a cumulative line, never a rate. It only ever rises. The dashed tail after NOW is
/// the forecast, drawn lighter and recomputed at every sync.
struct CumulativeCurve: View {
    let target: Double
    let now: Double
    /// The day's own cumulative curve, one point per five-minute tick. Empty before a day
    /// has settled, in which case the board's illustrative path stands in.
    var points: [LoadPoint] = []
    var day: UserDay = UserDay.containing(Date())
    /// 08 rule 07 · gaps in hours since midnight. Dashed, amber, and the line inside them is
    /// flat — interpolating would be inventing training.
    var gaps: [(Double, Double)] = []

    private static let boardPath: [(Double, Double)] = [
        (0, 0), (5, 0.1), (6.25, 1.9), (7.5, 2.6), (10.1, 3.3),
        (10.8, 5.3), (12.5, 6.2), (13.75, 8.1), (15, 10.2),
    ]

    /// x is hours since midnight — the axis under the chart reads 00 · 06 · 12 · NOW · 24,
    /// so a tick at 04:00 belongs at 4, not at 0.
    private var path: [(Double, Double)] {
        guard !points.isEmpty else { return Self.boardPath }
        let cal = Calendar.current
        return points.map { p in
            let midnight = cal.startOfDay(for: day.date)
            return (p.ts.timeIntervalSince(midnight) / 3600, p.load)
        }
    }

    private func pt(_ x: Double, _ y: Double, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * x / 24, y: size.height - 12 - CGFloat(y / 21) * (size.height - 24))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let size = geo.size
            let points = self.path
            let nowX = points.last?.0 ?? 15
            let nowPoint = pt(nowX, now, size)
            let targetY = h - 12 - CGFloat(target / 21) * (h - 24)

            ZStack(alignment: .topLeading) {
                // the optimal band and the target line
                Rectangle().fill(NB.cyan2.opacity(0.12))
                    .frame(height: 14.3)
                    .offset(y: targetY - 7)
                Path { p in p.move(to: CGPoint(x: 0, y: targetY)); p.addLine(to: CGPoint(x: w, y: targetY)) }
                    .stroke(NB.cyanPale.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                Path { p in p.move(to: CGPoint(x: 0, y: h - 12)); p.addLine(to: CGPoint(x: w, y: h - 12)) }
                    .stroke(NB.white.opacity(0.10), lineWidth: 1)

                Path { p in
                    p.move(to: pt(0, 0, size))
                    for (x, y) in points.dropFirst() { p.addLine(to: pt(x, y, size)) }
                    p.addLine(to: nowPoint)
                    p.addLine(to: CGPoint(x: nowPoint.x, y: h - 12))
                    p.addLine(to: CGPoint(x: 0, y: h - 12))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [NB.cyan1.opacity(0.28), NB.cyan1.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))

                Path { p in
                    p.move(to: pt(0, 0, size))
                    for (x, y) in points.dropFirst() { p.addLine(to: pt(x, y, size)) }
                    p.addLine(to: nowPoint)
                }
                .stroke(NB.cyan1, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // forecast — always lighter than the measured line
                Path { p in p.move(to: nowPoint); p.addLine(to: pt(min(23.5, nowX + 2.1), target, size)) }
                    .stroke(NB.cyan2, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5]))

                ForEach(Array(gaps.enumerated()), id: \.offset) { _, g in
                    let y = points.last(where: { $0.0 <= g.0 })?.1 ?? 0
                    let a = pt(g.0, y, size), b = pt(g.1, y, size)
                    Path { p in p.move(to: a); p.addLine(to: b) }
                        .stroke(NB.ember1, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 7]))
                    Circle().fill(NB.ember1).frame(width: 6.8, height: 6.8).position(a)
                    Circle().fill(NB.ember1).frame(width: 6.8, height: 6.8).position(b)
                    Text(L("%dH GAP", Int((g.1 - g.0).rounded())))
                        .font(NBFont.dot(500, 10)).tracking(0.16 * 10)
                        .foregroundStyle(NB.ember1.opacity(0.85))
                        .position(x: (a.x + b.x) / 2, y: a.y + 16)
                }

                Circle().fill(NB.carbon2).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(NB.cyan1, lineWidth: 2.5))
                    .position(nowPoint)
                Circle().fill(NB.cyanPale).frame(width: 7, height: 7)
                    .position(pt(min(23.5, nowX + 2.1), target, size))

                Text(L("TARGET %@", String(format: "%.1f", target)))
                    .font(NBFont.dot(700, 11)).tracking(0.02 * 11)
                    .foregroundStyle(Color(hex: 0x7FCEDD))
                    .offset(x: 4, y: targetY - 18)
            }
        }
    }
}

struct WeekBars: View {
    let values: [Double]
    let average: Double

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(values.indices, id: \.self) { i in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: 0x16161B))
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(i == values.count - 1 ? NB.cyan1 : NB.cyan3)
                                .frame(height: h * CGFloat(min(1, values[i] / 21)))
                        }
                        .frame(width: 34, height: h)
                        if i < values.count - 1 { Spacer(minLength: 0) }
                    }
                }
                Path { p in
                    let y = h - h * CGFloat(min(1, average / 21))
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(NB.cyanPale.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            .clipped()
        }
    }
}
