import SwiftUI

/// 08 · 训练详情 Training Load. Nine sections, from the ring all the way to
/// "so what do I do now". Back always returns to the root; there is no history stack here.
struct TrainingDetailView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    enum Range: String, CaseIterable { case day = "DAY", week = "WEEK", month = "MONTH" }
    @State private var range: Range = .day

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

                // 09 · the one CTA. It stays live in the empty state — that is exactly
                // when it should be tapped.
                Button {
                    // startSport(mode:) — the band has no on-wrist mode picker.
                } label: {
                    Text("START A SESSION")
                        .font(NBFont.ui(500, 12)).tracking(0.2 * 12)
                        .foregroundStyle(NB.text1)
                        .frame(width: NB.Layout.contentWidth, height: 48)
                        .background(Color(hex: 0x141418), in: Capsule())
                        .overlay(Capsule().stroke(NB.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
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
            SegmentedPills(options: Range.allCases.map(\.rawValue),
                           selection: Binding(get: { range.rawValue },
                                              set: { range = Range(rawValue: $0) ?? .day }))
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

    /// 03 · a four-link causal chain, in order: this morning's charge → the target on the ring
    /// → the acceptable band → the recent load. The last line is the only one worth having:
    /// it looks at history instead of at today.
    private var whyCard: some View {
        CardBlock(title: scaled ? "WHY \(Fmt.load(m.targetLoad))" : "WHAT THE RING NEEDS",
                  trailing: scaled ? "BODY BATTERY DECIDES IT" : "0 OF 4 READY") {
            VStack(alignment: .leading, spacing: 13) {
                ReasonLine(dot: NB.optimal2, title: "BODY BATTERY THIS MORNING",
                           value: m.bbWake.map { "\($0)%" } ?? Fmt.dash, valueColor: NB.optimal2,
                           detail: scaled ? "HRV 62 MS · RHR 48 BPM · CHARGED OVERNIGHT"
                                          : "ONE NIGHT OF SLEEP ON THE BAND")
                ReasonLine(dot: NB.cyanPale, title: "TARGET ON THE RING",
                           value: Fmt.load(m.targetLoad), valueColor: NB.cyanPale,
                           detail: scaled ? "\(Fmt.pct(m.bbWake)) LANDS AT 69% OF THE FULL RING"
                                          : "BODY BATTERY DECIDES IT — NOTHING TO DECIDE FROM YET")
                ReasonLine(dot: NB.cyan2, title: "OPTIMAL ZONE",
                           value: m.optimalZone.map { String(format: "%.1f – %.1f", $0.lowerBound, $0.upperBound) } ?? Fmt.dash,
                           valueColor: NB.macroValue,
                           detail: scaled ? "ANYWHERE IN HERE COUNTS AS HITTING THE DAY"
                                          : "THE ZONE MOVES WITH THE TARGET")
                ReasonLine(dot: NB.ember1, title: "RECENT LOAD",
                           value: scaled ? "LIGHT" : "NONE", valueColor: NB.ember1,
                           detail: scaled ? "4 DAYS SINCE YOUR LAST LIFT · 7D AVG 11.8"
                                          : "NO SESSIONS ON RECORD · 7D AVG \(Fmt.dash)")
            }
        }
    }

    /// 04 · the number on the ring must be breakable into parts. The time column is a fixed
    /// slot so ALL DAY sits in the same lane as a clock time.
    private var buildCard: some View {
        CardBlock(title: "TODAY'S BUILD",
                  trailing: scaled ? "4 SOURCES · \(Fmt.load(m.trainingLoad)) TOTAL" : "0 SOURCES · 0.0 TOTAL") {
            if scaled {
                VStack(spacing: 10) {
                    BuildRow(time: "06:40", name: "MORNING WALK", detail: "32 MIN · AVG 108 BPM", delta: "+2.1")
                    Hairline()
                    BuildRow(time: "12:10", name: "CYCLE COMMUTE", detail: "22 MIN · AVG 131 BPM", delta: "+2.6")
                    Hairline()
                    BuildRow(time: "15:30", name: "ELEVATED HR", detail: "2H 40M · MEETINGS, NOT MOVEMENT", delta: "+2.9")
                    Hairline()
                    BuildRow(time: "ALL DAY", name: "STEPS & MOVEMENT", detail: "8,432 STEPS · 6.1 KM",
                             delta: "+4.8", timeIsLabel: true)
                }
                // 05 · one suggestion, never a list. It sits last and is drawn in a dashed
                // box so it can't be mistaken for something already done.
                NextSuggestion(title: "STRENGTH · 45 MIN",
                               detail: "PUTS YOU AT \(Fmt.load(m.targetLoad)) — IN ZONE",
                               delta: "+2.1")
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
            CumulativeCurve(target: m.targetLoad ?? 14.5, now: m.trainingLoad ?? 0)
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
        CardBlock(title: "TIME IN ZONE", trailing: "6H 54M ELEVATED", trailingIsDot: true) {
            VStack(spacing: 9) {
                ZoneBar(zone: "Z1", fill: 1.00, tint: NB.cyanDeep, value: "4H 12M")
                ZoneBar(zone: "Z2", fill: 0.39, tint: NB.cyan1, value: "1H 38M")
                ZoneBar(zone: "Z3", fill: 0.17, tint: NB.lime2, value: "42 MIN")
                ZoneBar(zone: "Z4", fill: 0.07, tint: NB.ember1, value: "18 MIN")
                ZoneBar(zone: "Z5", fill: 0.02, tint: NB.alert2, value: "5 MIN")
            }
            Hairline()
            Text("Z4 AND ABOVE IS WHERE THE RING MOVES FAST — 23 MIN TODAY, AGAINST 45 MIN ON A FULL LIFT DAY.")
                .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                .lineSpacing(5)
                .foregroundStyle(NB.text3Prod)
        }
    }

    /// 08 · it answers "how have I been lately", so it lives at the very bottom.
    /// Today is not counted into the average; only finished days are.
    private var thisWeekCard: some View {
        CardBlock(title: "THIS WEEK", trailing: "7D AVG 12.1", trailingIsDot: true) {
            WeekBars(values: [15.0, 9.3, 16.0, 11.5, 6.9, 13.9, 12.4], average: 12.1)
                .frame(height: 88)
            HStack {
                ForEach(Array(["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"].enumerated()), id: \.offset) { i, d in
                    Text(d)
                        .font(NBFont.dot(i == 6 ? 700 : 500, 10))
                        .foregroundStyle(i == 6 ? NB.cyan1 : Color(hex: 0x8A8A96))
                        .frame(width: 34)
                    if i < 6 { Spacer(minLength: 0) }
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

    private let points: [(Double, Double)] = [
        (0, 0), (5, 0.1), (6.25, 1.9), (7.5, 2.6), (10.1, 3.3),
        (10.8, 5.3), (12.5, 6.2), (13.75, 8.1), (15, 10.2),
    ]

    private func pt(_ x: Double, _ y: Double, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * x / 24, y: size.height - 12 - CGFloat(y / 21) * (size.height - 24))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let size = geo.size
            let nowPoint = pt(15, now, size)
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
                Path { p in p.move(to: nowPoint); p.addLine(to: pt(17.1, target, size)) }
                    .stroke(NB.cyan2, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5]))

                Circle().fill(NB.carbon2).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(NB.cyan1, lineWidth: 2.5))
                    .position(nowPoint)
                Circle().fill(NB.cyanPale).frame(width: 7, height: 7).position(pt(17.1, target, size))

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
