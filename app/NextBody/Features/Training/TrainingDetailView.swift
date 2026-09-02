import SwiftUI

/// 08 · 训练详情 Training Load. Nine sections, from the ring all the way to
/// "so what do I do now". Back always returns to the root; there is no history stack here.
struct TrainingDetailView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router


    private var m: DailyMetrics { data.today }
    private var scaled: Bool { m.targetLoad != nil }

    var body: some View {
        DetailScroll(glow: NB.cyan1) {
            VStack(alignment: .leading, spacing: 14) {
                // 01 · header & range. "2.1 TO GO" sits on the title line because it is
                // the one conclusion this page has.
                header

                // 02 · ring & legend
                ringCard

                // 03 · why this number — the trust of the whole page
                whyCard

                SectionLabel(scaled ? "WHERE IT CAME FROM" : "WHERE IT WILL COME FROM")

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

                // 09 · the one CTA.
                //
                // ⚠️ 10PV names three entry points on this board that "指向空气", and rules:
                // "V1 要么补屏，要么把入口显式禁用——点了没反应比没有这个按钮更糟." The
                // in-session screen is on 1EEU's not-in-V1 list, so this is the second
                // branch: visibly disabled, with the reason on it. It was an empty closure —
                // a button that looks live and does nothing, which is the exact thing that
                // line forbids.
                VStack(spacing: 8) {
                    Text("START A SESSION")
                        .font(NBFont.ui(500, 12)).tracking(0.2 * 12)
                        .foregroundStyle(NB.text3)
                        .frame(width: NB.Layout.contentWidth, height: 48)
                        .background(Color(hex: 0x101014), in: Capsule())
                        .overlay(Capsule().stroke(NB.white.opacity(0.06), lineWidth: 1))
                    Text("START IT ON THE BAND — THE IN-SESSION SCREEN IS NOT IN THIS BUILD")
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRAINING")
                    .font(NBFont.brand(700, 28)).tracking(-0.02 * 28)
                    .foregroundStyle(NB.text1)
                Spacer(minLength: 0)
                Text(scaled ? String(format: "%.1f TO GO", max(0, (m.targetLoad ?? 0) - (m.trainingLoad ?? 0)))
                            : "NO TARGET YET")
                    .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
                    .foregroundStyle(scaled ? NB.cyanPale : NB.text3Prod)
            }
            // ⚠️ The DAY / WEEK / MONTH control is deliberately absent, not forgotten.
            // ZUO · "留一个死控件比没有更糟", and 1EIH settles the disagreement between this
            // board (which said build the screens or disable the control) and 09 (which said
            // delete it) with "以删为准，两页保持一致". WEEK's job is already done by THIS
            // WEEK at the foot of the page, and MONTH has no content on seven days of data.
            // 1EEU lists the segmented control itself as out of V1 for both 08 and 09.
        }
        .padding(.top, 14)
    }

    private var ringCard: some View {
        VStack(spacing: 18) {
            BigTrainingRing(load: m.trainingLoad, target: m.targetLoad, zone: m.optimalZone)
                .frame(width: 200, height: 200)

            VStack(spacing: 11) {
                Hairline()
                LegendRow(swatch: .bar(NB.cyan1, 7), label: "TRAINING NOW",
                          labelColor: NB.text1, value: Fmt.load(m.trainingLoad), valueColor: NB.cyan1, bold: true)
                LegendRow(swatch: .bar(NB.cyan2, 5), label: "OPTIMAL ZONE",
                          labelColor: NB.text2,
                          value: m.optimalZone.map { String(format: "%.1f – %.1f", $0.lowerBound, $0.upperBound) } ?? Fmt.dash,
                          valueColor: NB.macroValue, bold: false)
                LegendRow(swatch: .dot(NB.cyanPale), label: "TARGET",
                          labelColor: NB.text2, value: Fmt.load(m.targetLoad),
                          valueColor: NB.cyanPale, bold: true)
                LegendRow(swatch: .bar(Color(hex: 0x33333D), 5), label: "FULL RING",
                          labelColor: NB.text3Prod, value: "21.0 MAX",
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
        let hrv = n?.hrv.map { "HRV \(Int($0)) MS" } ?? "HRV \(Fmt.dash)"
        let rhr = n?.rhr.map { "RHR \(Int($0)) BPM" } ?? "RHR \(Fmt.dash)"
        let word = m.reserveDrivers.map { BodyBattery.chargeWord(Int($0.lastNight.rounded())) }
            ?? "CHARGED OVERNIGHT"
        return "\(hrv) · \(rhr) · \(word)"
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
        if avg < zone.lowerBound { return "LIGHT" }
        if avg > zone.upperBound { return "HEAVY" }
        return "STEADY"
    }

    private var recentDetail: String {
        let since = daysSinceSession.map { "\($0) DAY\($0 == 1 ? "" : "S") SINCE YOUR LAST SESSION" }
            ?? "NO SESSION ON RECORD"
        return "\(since) · 7D AVG \(Fmt.load(sevenDayAverage))"
    }

    /// 03 · a four-link causal chain, in order: this morning's charge → the target on the ring
    /// → the acceptable band → the recent load. The last line is the only one worth having:
    /// it looks at history instead of at today.
    private var whyCard: some View {
        CardBlock(title: scaled ? "WHY \(Fmt.load(m.targetLoad))" : "WHAT THE RING NEEDS",
                  trailing: scaled ? "BODY BATTERY DECIDES IT" : "0 OF 4 READY") {
            VStack(alignment: .leading, spacing: 13) {
                ReasonLine(dot: NB.optimal2, title: "BODY BATTERY THIS MORNING",
                           value: m.bbWake.map { "\($0)%" } ?? Fmt.dash, valueColor: NB.optimal2,
                           detail: scaled ? nightLine : "ONE NIGHT OF SLEEP ON THE BAND")
                ReasonLine(dot: NB.cyanPale, title: "TARGET ON THE RING",
                           value: Fmt.load(m.targetLoad), valueColor: NB.cyanPale,
                           detail: scaled ? "\(Fmt.pct(m.bbWake)) LANDS AT \(ringShare) OF THE FULL RING"
                                          : "BODY BATTERY DECIDES IT — NOTHING TO DECIDE FROM YET")
                ReasonLine(dot: NB.cyan2, title: "OPTIMAL ZONE",
                           value: m.optimalZone.map { String(format: "%.1f – %.1f", $0.lowerBound, $0.upperBound) } ?? Fmt.dash,
                           valueColor: NB.macroValue,
                           detail: scaled ? "ANYWHERE IN HERE COUNTS AS HITTING THE DAY"
                                          : "THE ZONE MOVES WITH THE TARGET")
                ReasonLine(dot: NB.ember1, title: "RECENT LOAD",
                           value: scaled ? recentWord : "NONE", valueColor: NB.ember1,
                           detail: scaled ? recentDetail
                                          : "NO SESSIONS ON RECORD · 7D AVG \(Fmt.dash)")
            }
        }
    }

    private func detail(for seg: TrainingSegment) -> String {
        if seg.allDay {
            let steps = Fmt.kcal(seg.steps.map(Double.init))
            return "\(steps) STEPS · NEVER LEFT Z1"
        }
        let mins = seg.minutes.map(Fmt.duration) ?? Fmt.dash
        let hr = seg.avgHR.map { "AVG \($0) BPM" } ?? Fmt.dash
        return "\(mins) · \(hr)"
    }

    /// 05 · one suggestion, never a list — and it has to be sized to the gap that is
    /// actually left, not to a number printed on the board.
    private var suggestion: (title: String, delta: Double) {
        let gap = max(0, (m.targetLoad ?? 0) - (m.trainingLoad ?? 0))
        if gap >= 8 { return ("STRENGTH · 45 MIN", gap) }
        if gap >= 3 { return ("STRENGTH · 30 MIN", gap) }
        return ("EASY WALK · 20 MIN", gap)
    }

    /// 04 · the number on the ring must be breakable into parts. The time column is a fixed
    /// slot so ALL DAY sits in the same lane as a clock time.
    private var buildCard: some View {
        CardBlock(title: "TODAY'S BUILD",
                  trailing: scaled ? "\(m.segments.count) SOURCE\(m.segments.count == 1 ? "" : "S") · \(Fmt.load(m.trainingLoad)) TOTAL"
                                   : "0 SOURCES · 0.0 TOTAL") {
            if scaled && !m.segments.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(m.segments.enumerated()), id: \.element.id) { i, seg in
                        if i > 0 { Hairline() }
                        BuildRow(time: seg.allDay ? "ALL DAY" : Fmt.clock(seg.at),
                                 name: seg.name, detail: detail(for: seg),
                                 delta: "+\(String(format: "%.1f", seg.delta))",
                                 timeIsLabel: seg.allDay)
                    }
                }
                // 05 · one suggestion, never a list. It sits last and is drawn in a dashed
                // box so it can't be mistaken for something already done.
                NextSuggestion(title: suggestion.title,
                               detail: "PUTS YOU AT \(Fmt.load(m.targetLoad)) — IN ZONE",
                               delta: "+\(String(format: "%.1f", suggestion.delta))")
            } else {
                VStack(spacing: 8) {
                    Text("NOTHING HAS COME IN YET")
                        .font(NBFont.ui(500, 12)).tracking(0.14 * 12)
                        .foregroundStyle(NB.text2)
                    Text("WALKS, RIDES, ELEVATED HR AND STEPS ALL LAND HERE ONCE THE BAND IS ON YOUR WRIST")
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
        CardBlock(title: "THROUGH THE DAY", trailing: "CUMULATIVE · 0–21") {
            CumulativeCurve(target: m.targetLoad ?? 14.5, now: m.trainingLoad ?? 0,
                            points: m.loadCurve, day: m.day)
                .frame(height: 120)
            HStack {
                ForEach(["00", "06", "12", "NOW", "24"], id: \.self) { t in
                    Text(t)
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
        return CardBlock(title: "TIME IN ZONE",
                         trailing: "\(Fmt.duration(mins.reduce(0, +))) ELEVATED", trailingIsDot: true) {
            VStack(spacing: 9) {
                ForEach(0..<5, id: \.self) { i in
                    ZoneBar(zone: "Z\(i + 1)", fill: Double(mins[i]) / Double(top),
                            tint: tints[i], value: Fmt.duration(mins[i]))
                }
            }
            Hairline()
            Text("Z4 AND ABOVE IS WHERE THE RING MOVES FAST — \(Fmt.duration(hard)) TODAY, AGAINST \(Fmt.duration(hardBest)) ON YOUR HARDEST DAY THIS WEEK.")
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
        return CardBlock(title: "THIS WEEK", trailing: "7D AVG \(Fmt.load(sevenDayAverage))",
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
            GateRow(title: "THROUGH THE DAY", when: "AFTER 1 FULL DAY")
            Hairline()
            GateRow(title: "TIME IN ZONE", when: "AFTER 1 FULL DAY")
            Hairline()
            GateRow(title: "THIS WEEK", when: "AFTER 7 DAYS")
        }
        .padding(.horizontal, 14)
        .frame(width: NB.Layout.contentWidth)
    }
}

// MARK: page chrome shared by 08 · 09 · 10 · 13

/// Every detail page is one scroll with a coloured bloom behind the top,
/// a back mark that says where it returns to, and nothing else pinned.
struct DetailScroll<Content: View>: View {
    let glow: Color
    @ViewBuilder let content: Content
    let onBack: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: Chrome.statusBarBlock)
                BackToRoot(action: onBack).padding(.leading, 18)
                content
            }
        }
        .background(alignment: .top) {
            Ellipse()
                .fill(RadialGradient(stops: [
                    .init(color: glow.opacity(0.13), location: 0),
                    .init(color: glow.opacity(0.035), location: 0.6),
                    .init(color: glow.opacity(0), location: 1),
                ], center: .center, startRadius: 0, endRadius: 215))
                .frame(width: 430, height: 370)
                .offset(y: -60)
        }
        .carbonPage()
        .ignoresSafeArea(.container, edges: .vertical)
        .navigationBarBackButtonHidden()
    }
}

struct BackToRoot: View {
    var label: String = "TODAY"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Path { p in
                    p.move(to: CGPoint(x: 7, y: 1))
                    p.addLine(to: CGPoint(x: 1.5, y: 6.5))
                    p.addLine(to: CGPoint(x: 7, y: 12))
                }
                .stroke(NB.macroLabel, style: StrokeStyle(lineWidth: 1.6, lineCap: .square))
                .frame(width: 8, height: 13)
                Text(label)
                    .font(NBFont.ui(500, 11)).tracking(0.24 * 11)
                    .foregroundStyle(NB.macroLabel)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SegmentedPills: View {
    let options: [String]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { o in
                Button { selection = o } label: {
                    Text(o)
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
    let title: String
    var trailing: String? = nil
    var trailingIsDot = false
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
                        .foregroundStyle(trailingIsDot ? NB.macroValue : NB.text3Prod)
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
            Text("NEXT")
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
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { grown = fill } }
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
                .foregroundStyle(NB.text3)
        }
        .frame(height: 44)
    }
}

/// The 200pt version of the ring. Same ruler, same three lanes.
struct BigTrainingRing: View {
    let load: Double?
    let target: Double?
    let zone: ClosedRange<Double>?
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().strokeBorder(NB.ringTrack, lineWidth: 14)
                .frame(width: 186, height: 186)
            RingArc(from: 0, to: shown / 21)
                .stroke(NB.cyan1, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .frame(width: 172, height: 172)
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
                    .foregroundStyle(load == nil ? NB.text3 : NB.cyan1)
                Text("OF 21")
                    .font(NBFont.ui(500, 11)).tracking(0.22 * 11)
                    .foregroundStyle(NB.text3Prod)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { shown = load ?? 0 } }
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

                Circle().fill(NB.carbon2).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(NB.cyan1, lineWidth: 2.5))
                    .position(nowPoint)
                Circle().fill(NB.cyanPale).frame(width: 7, height: 7)
                    .position(pt(min(23.5, nowX + 2.1), target, size))

                Text("TARGET \(String(format: "%.1f", target))")
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
                                .frame(height: h * CGFloat(values[i] / 21))
                        }
                        .frame(width: 34, height: h)
                        if i < values.count - 1 { Spacer(minLength: 0) }
                    }
                }
                Path { p in
                    let y = h - h * CGFloat(average / 21)
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(NB.cyanPale.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
    }
}
