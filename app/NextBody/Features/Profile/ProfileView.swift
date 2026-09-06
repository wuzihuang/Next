import SwiftUI

/// 11C · 我的 Profile · Instrument. The title is ME, not SETTINGS: the first thing
/// this page gives you is you, not a control panel. Reached only from the avatar;
/// back goes to the root. The DEVICE row is the way onto the band page.
struct ProfileView: View {
    @ObservedObject private var language = AppLanguage.shared
    @ObservedObject private var consent = ConsentStore.shared
    @ObservedObject private var haptics = HapticsSetting.shared
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    private var hasScans: Bool { !data.weighIns.isEmpty }

    /// Lime / outline / red — not the two greys. Weigh-ins never colour this map
    /// (F0 D05); an empty grid with five morning scans was the copy lying.
    private var hasLitSquares: Bool {
        ([data.today] + data.history).contains {
            switch $0.direction {
            case .deficit, .level, .surplus: return true
            case .greyNothing, .greyNoBurn: return false
            }
        }
    }

    var body: some View {
        DetailScroll(glow: NB.lime1, title: L("ME"), trailing: {
            // 11C · the page's own pip. Device says CONNECTED the same way.
            HStack(spacing: 7) {
                Circle().fill(NB.lime1).frame(width: 6, height: 6)
                Text(L("YOU"))
                    .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                    .foregroundStyle(NB.lime1)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
        }) {
            VStack(alignment: .leading, spacing: 16) {
                identityCard
                bodyBatteryCard
                compositionCard
                // ADR 0010 · Composition 回答「这一年往哪走」，这块回答「我最近测了什么」。
                // 净变化已经收进 Composition 底栏，不再单独占三张瓦片。
                measurementsCard

                GroupLabel(L("ACCOUNT"))
                RowGroup {
                    SettingRow(title: L("PERSONAL INFO"), value: data.profile.displayName.uppercased()) {
                        router.sheet = .profileEdit
                    }
                    SettingRow(title: L("BODY METRICS"),
                               value: "\(Int(data.profile.heightCm)) CM · \(Fmt.kg(data.today.weightKg)) KG") {
                        router.sheet = .weighIn
                    }
                    // 11 edge 2 · the sheet closes and the value changes at once; today's target and
                    // macros do not. The 「明天生效」 line lives on the row, not only in the sheet.
                    SettingRow(title: L("TRAINING GOAL"), value: goalLabel,
                               detail: goalChangedToday ? "FROM TOMORROW · TODAY IS UNCHANGED" : nil) {
                        router.sheet = .goal
                    }
                    // The band page — overview, firmware, heart-rate alarm.
                    SettingRow(title: L("DEVICE"),
                               value: data.band.connected
                                    ? "HOOP · \(data.band.batteryPercent.map { "\($0)%" } ?? Fmt.dash)"
                                    : "HOOP · DAY 1") {
                        router.open(.device, from: .profile)
                    }
                }

                GroupLabel(L("PREFERENCES"))
                RowGroup {
                    SettingRow(title: L("NOTIFICATIONS"), value: L("ON")) { router.sheet = .notifications }
                    // Every motor in the product behind one switch: the typing stream on the
                    // screen and under the keyboard, the orb's hold, the tap that marks an
                    // answer. Toggled in place, like COLLECTING HEALTH DATA below — and it
                    // keeps its chevron for the same reason that row does: a lane of rows
                    // with one arrow missing reads as broken, not as a different kind of row.
                    SettingRow(title: L("HAPTICS"), value: haptics.enabled ? L("ON") : L("OFF")) {
                        haptics.toggle()
                        // Turning it on answers in the hand; turning it off says nothing.
                        if haptics.enabled { HoldHaptics.shared.release() }
                    }
                    SettingRow(title: L("UNITS"), value: data.profile.usesMetric ? L("METRIC · KG") : L("IMPERIAL · LB")) {
                        router.sheet = .units
                    }
                    // SYNCED means an import completed; the date is the last successful read.
                    SettingRow(title: L("APPLE HEALTH"),
                               value: data.profile.appleHealthLinked ? "SYNCED" : "NOT CONNECTED",
                               valueTint: data.profile.appleHealthLinked ? nil : NB.ember1,
                               detail: healthLastRead.map { "LAST READ \($0)" }) {
                        router.sheet = .appleHealth
                    }
                    SettingRow(title: L("LANGUAGE"), value: language.locale.rowLabel) { router.sheet = .language }
                }

                GroupLabel(L("DATA & LEGAL"))
                RowGroup {
                    // 补屏 rule 06 · 「撤回 ≠ 删除，两个动作、两行入口、两条权利」. This row stops
                    // collection; DELETE ACCOUNT, three rows down, is the other right.
                    SettingRow(title: L("COLLECTING HEALTH DATA"), value: consent.granted ? L("ON") : L("OFF")) {
                        if consent.granted {
                            Task { await ConsentStore.shared.record(.withdrawn, msOnScreen: nil) }
                        } else {
                            router.takeover = .consent
                        }
                    }
                    // 11 edge 3 · export is async, not modal: the row says PREPARING… and the page can
                    // be left.
                    SettingRow(title: L("EXPORT MY DATA"),
                               value: data.exportPreparing ? L("PREPARING…") : hasScans ? L("ALL TIME") : L("NOTHING YET"),
                               valueTint: data.exportPreparing ? NB.ember1.opacity(0.85) : nil,
                               detail: data.exportPreparing ? L("YOU CAN LEAVE THIS PAGE") : nil) {
                        router.sheet = .export
                    }
                    SettingRow(title: L("PRIVACY POLICY"), value: L("UPDATED JUN 24")) { router.sheet = .privacy }
                    SettingRow(title: L("TERMS OF SERVICE"), value: "V 2.1") { router.sheet = .about }
                    // The second of only two places in the product allowed to use red.
                    SettingRow(title: L("DELETE ACCOUNT"), value: L("PERMANENT"),
                               titleTint: NB.alert2) { router.sheet = .deleteAccount }
                }

                Button { router.sheet = .signOut } label: {
                    Text(L("SIGN OUT"))
                        .font(NBFont.ui(500, 12)).tracking(0.2 * 12)
                        .foregroundStyle(NB.text1)
                        .frame(width: NB.Layout.contentWidth, height: 48)
                        .background(Color(hex: 0x141418), in: Capsule())
                        .overlay(Capsule().stroke(NB.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                Text(L("NEXTBODY 1.4.2  ·  BUILD 2831"))
                    .font(NBFont.dot(500, 10)).tracking(0.16 * 10)
                    .foregroundStyle(NB.white.opacity(0.22))
                    .frame(width: NB.Layout.contentWidth, alignment: .center)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            router.backToRoot()
        }
    }

    /// 11 rule 06 · true only on the day the goal was changed.
    private var goalChangedToday: Bool {
        UserDefaults.standard.string(forKey: "nb.goal.changedDay") == UserDay.containing(Date()).key
    }
    /// The day Health last answered with anything, or nil if it never has.
    private var healthLastRead: String? {
        guard let at = UserDefaults.standard.object(forKey: "nb.health.lastRead") as? Date else { return nil }
        return Fmt.displayDate(at, format: "MMM d").uppercased()
    }

    private var goalLabel: String {
        switch data.profile.goal {
        case .cut: L("ENDURANCE"); case .recomp: L("RECOMP"); case .bulk: L("STRENGTH")
        }
    }

    /// 11C · NOW, the name at brand size, the avatar on the right. The three gauges
    /// sit under a hairline. Tapping the head goes to PERSONAL INFO, same as the row below.
    private var identityCard: some View {
        VStack(spacing: 0) {
            Button { router.sheet = .profileEdit } label: {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("NOW"))
                            .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                            .foregroundStyle(NB.text2)
                        Text(data.profile.displayName.uppercased())
                            .font(NBFont.brand(700, 28))
                            .foregroundStyle(NB.text1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .lineHeight(32)
                        Text(data.profile.email)
                            .font(NBFont.dot(500, 11)).tracking(0.02 * 11)
                            .foregroundStyle(NB.text3Prod)
                    }
                    Spacer(minLength: 0)
                    Avatar(size: 44, initials: data.profile.initials, ink: NB.lime1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Hairline()

            HStack(spacing: 0) {
                InstrumentGauge(label: L("HEIGHT"),
                                value: "\(Int(data.profile.heightCm))", unit: "CM",
                                slot: .leading)
                VHair()
                InstrumentGauge(label: L("WEIGHT"),
                                value: Fmt.kg(data.today.weightKg), unit: "KG",
                                slot: .middle)
                VHair()
                InstrumentGauge(label: L("AGE"),
                                value: "\(data.profile.age)", unit: nil,
                                slot: .trailing)
            }
        }
        .frame(width: NB.Layout.contentWidth)
        .instrumentPlate()
    }

    /// 13 / ADR 0017 · scheme A. One hot zone between identity and COMPOSITION.
    /// The curve is the read; PEAK / NIGHT / NOW sit under the hairline.
    private var bodyBatteryCard: some View {
        let m = data.todayForDisplay
        let night = m.reserveDrivers?.lastNight
        let peak = m.reserveCurve.max(by: { $0.value < $1.value })
        let peakValue = peak?.value ?? m.bbWake
        let peakClock = peak.map { Fmt.clock($0.ts) } ?? (m.bbWake == nil ? nil : "07:12")
        let word = night.map { BodyBattery.chargeWord(Int($0.rounded())) }
        let chargeLine: String = {
            if let word, let night {
                return L("%@ · %@", L(word), Fmt.signed(night))
            }
            return m.bodyBattery == nil ? L("NO NIGHT YET") : L("FROM WRIST DATA")
        }()
        return Button {
            router.open(.bodyBattery, from: .profile)
        } label: {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("NOW"))
                                .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                                .foregroundStyle(NB.text2)
                            Text(MetricNames.bodyBattery)
                                .font(NBFont.brand(700, 22))
                                .foregroundStyle(NB.text1)
                                .lineHeight(26)
                            Text(chargeLine)
                                .font(NBFont.dot(500, 11)).tracking(0.02 * 11)
                                .foregroundStyle(NB.lime1)
                        }
                        Spacer(minLength: 0)
                        Chevron()
                    }
                    BatteryCurve(samples: m.reserveCurve)
                        .frame(height: 88)
                }
                .padding(14)

                Hairline()

                HStack(spacing: 0) {
                    InstrumentGauge(label: L("PEAK"),
                                    value: peakValue.map(String.init) ?? Fmt.dash,
                                    unit: peakClock,
                                    tint: peakValue == nil ? NB.text3Prod : NB.lime1,
                                    slot: .leading)
                    VHair()
                    InstrumentGauge(label: L("NIGHT"),
                                    value: night.map(Fmt.signed) ?? Fmt.dash,
                                    tint: night == nil ? NB.text3Prod : NB.lime1,
                                    slot: .middle)
                    VHair()
                    InstrumentGauge(label: L("NOW"),
                                    value: m.bodyBattery.map(String.init) ?? Fmt.dash,
                                    tint: m.bodyBattery == nil ? NB.text3Prod : NB.text1,
                                    slot: .trailing)
                }
            }
            .frame(width: NB.Layout.contentWidth, alignment: .leading)
            .instrumentPlate()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("BODY_BATTERY")
    }

    /// A2 + 11C · the only "one year" view. Header opens today; a cell opens that day.
    /// The three 12-week numbers live on this plate, not as tiles under it.
    private var compositionCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    router.open(.composition(date: data.today.day.start), from: .profile)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("YEAR"))
                                .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                                .foregroundStyle(NB.text2)
                            Text(L("COMPOSITION"))
                                .font(NBFont.brand(700, 22))
                                .foregroundStyle(NB.text1)
                                .lineHeight(26)
                            Text(hasScans ? L("RECOMP · 12 W") : L("NO WEIGH-INS YET"))
                                .font(NBFont.dot(500, 11)).tracking(0.02 * 11)
                                .foregroundStyle(NB.text3Prod)
                        }
                        Spacer(minLength: 0)
                        Chevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("COMPOSITION")

                MonthAxis()
                DirectionHeatMap(history: data.history, today: data.today) { day in
                    router.open(.composition(date: day.start), from: .profile)
                }
                DirectionLegend()
                if !hasLitSquares {
                    HStack(alignment: .center) {
                        Text(L("LOG TWO MEALS ON A DAY YOU WEAR THE BAND\nAND THE FIRST SQUARE LIGHTS UP"))
                            .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                            .lineSpacing(4)
                            .foregroundStyle(NB.text3Prod)
                        Spacer(minLength: 0)
                        if !hasScans {
                            Button { router.sheet = .weighIn } label: {
                                Text(L("ADD A WEIGH-IN"))
                                    .font(NBFont.ui(600, 11)).tracking(0.12 * 11)
                                    .foregroundStyle(NB.lime1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)

            Hairline()

            HStack(spacing: 0) {
                InstrumentGauge(label: L("FAT MASS"),
                                value: Fmt.signedKg(data.netFatMass12w, decimals: 1),
                                unit: "KG",
                                tint: data.netFatMass12w == nil ? NB.text3Prod : NB.lime1,
                                slot: .leading)
                VHair()
                InstrumentGauge(label: L("LEAN MASS"),
                                value: Fmt.signedKg(data.netLeanMass12w, decimals: 1),
                                unit: "KG",
                                tint: data.netLeanMass12w == nil ? NB.text3Prod : NB.lime1,
                                slot: .middle)
                VHair()
                InstrumentGauge(label: L("BODY FAT"),
                                value: Fmt.kg(data.bodyFatPercent),
                                unit: "%",
                                tint: data.bodyFatPercent == nil ? NB.text3Prod : NB.text1,
                                slot: .trailing)
            }
        }
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .instrumentPlate()
    }

    /// ADR 0010 · 主动测量记录。最近三条，混排倒序，底部一行进清单。
    ///
    /// ⚠️ 行本身不可点。这张卡唯一的热区是底部的 ALL MEASUREMENTS——F0 的规矩是一张卡一个
    /// 热区，而这里那个热区不能是整张卡：整张卡可点的话，「看最近三条」和「看全部」就成了
    /// 同一个动作，那三行也就没有理由留在这一页上。
    private var measurementsCard: some View {
        let recent = Array(data.measurements.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("MEASUREMENTS"))
                    .font(NBFont.ui(500, 11)).tracking(0.24 * 11)
                    .foregroundStyle(NB.text1)
                Spacer(minLength: 0)
                // 只有一种话：距上次多久。次数是虚荣指标，而且两种测量混着数没有意义。
                Text(lastMeasurementLabel)
                    .font(NBFont.dot(500, 11)).tracking(0.04 * 11)
                    .foregroundStyle(recent.isEmpty ? NB.text3Prod : NB.macroValue)
            }

            if recent.isEmpty {
                Text(L("HOLD THE SIDE KEY FROM THE PLUS MENU.\nTHIRTY SECONDS MAKES THE FIRST ROW."))
                    .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                    .lineSpacing(4)
                    .foregroundStyle(NB.text3Prod)
                    .padding(.top, 16)
            } else {
                VStack(spacing: 13) {
                    // 只测过一种就只列那一种。绝不露出一行永远空着的另一种——那看起来像坏了。
                    ForEach(recent) { record in
                        MeasurementRow(record: record, style: .card)
                    }
                }
                .padding(.top, 16)
            }

            Hairline().padding(.top, 14)

            Button {
                if recent.isEmpty { router.sheet = .plusMenu }
                else { router.open(.measurements, from: .profile) }
            } label: {
                HStack {
                    Text(L("ALL MEASUREMENTS"))
                        .font(NBFont.ui(600, 11)).tracking(0.12 * 11)
                        .foregroundStyle(recent.isEmpty ? NB.text3Prod : NB.lime1)
                    Spacer(minLength: 0)
                    if recent.isEmpty {
                        // 没有记录时这一行没有清单可去，右端换成开始测一次的入口——而且开的是
                        // 加号菜单的测量组，不直接开接管：哪一种得由人选。
                        Text(L("MEASURE"))
                            .font(NBFont.ui(600, 11)).tracking(0.12 * 11)
                            .foregroundStyle(NB.lime1)
                    } else {
                        Chevron(color: NB.lime1)
                    }
                }
                .frame(height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 13)
            // 这张卡唯一的热区，给它一个不随文案和语言变的名字。
            .accessibilityIdentifier("ALL_MEASUREMENTS")
        }
        .padding(14)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .instrumentPlate()
    }

    private var lastMeasurementLabel: String {
        guard let days = data.measurements.daysSinceLatest() else { return L("NONE YET") }
        return days <= 0 ? L("LAST · TODAY") : L("LAST · %d D AGO", days)
    }
}

// MARK: pieces

/// 11C · the three data plates wash at `--panel-chrome`. Settings rows stay `cardSkin`.
private struct InstrumentPlate: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
        content
            .background(NB.panelWash, in: shape)
            .overlay(shape.stroke(NB.hairline, lineWidth: 1))
            .clipShape(shape)
    }
}
extension View {
    fileprivate func instrumentPlate() -> some View { modifier(InstrumentPlate()) }
}

private struct GroupLabel: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text)
            .font(NBFont.ui(500, 11)).tracking(0.24 * 11)
            .foregroundStyle(Color(hex: 0x8A8A96))
            .padding(.leading, 2)
            .padding(.top, 8)
    }
}

private struct RowGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .frame(width: NB.Layout.contentWidth)
            .cardSkin()
    }
}

private struct SettingRow: View {
    let title: String
    var value: String? = nil
    var valueTint: Color? = nil
    var titleTint: Color? = nil
    /// 11 edges · 「最多加一行副文案」. The row is the alarm; the sub-line is its reason.
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(NBFont.ui(500, 13)).tracking(0.06 * 13)
                        .foregroundStyle(titleTint ?? NB.text1)
                    if let detail {
                        Text(detail)
                            .font(NBFont.ui(300, 11)).tracking(0.04 * 11)
                            .foregroundStyle(NB.text3Prod)
                    }
                }
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .font(NBFont.dot(500, 10.5)).tracking(0.14 * 10.5)
                        .foregroundStyle(valueTint ?? NB.text3Prod)
                }
                Chevron()
            }
            .padding(.horizontal, 16)
            .frame(height: detail == nil ? 48 : 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Hairline().padding(.leading, 16)
        }
    }
}

struct Chevron: View {
    var color: Color = Color(hex: 0x5A5A66)
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 1, y: 1))
            p.addLine(to: CGPoint(x: 5, y: 5))
            p.addLine(to: CGPoint(x: 1, y: 9))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
        .frame(width: 6, height: 10)
    }
}

/// 11C · one column on an instrument rail. Leading / middle / trailing carry the
/// board's own padding so the three numbers sit on the same hairline as the card edge.
private enum GaugeSlot {
    case leading, middle, trailing
    var insets: EdgeInsets {
        switch self {
        case .leading:  EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 12)
        case .middle:   EdgeInsets(top: 14, leading: 14, bottom: 16, trailing: 12)
        case .trailing: EdgeInsets(top: 14, leading: 14, bottom: 16, trailing: 16)
        }
    }
}

private struct InstrumentGauge: View {
    let label: String
    let value: String
    var unit: String? = nil
    var tint: Color = NB.text1
    let slot: GaugeSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(NBFont.dot(600, 10)).tracking(0.18 * 10)
                .foregroundStyle(NB.text2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(NBFont.dot(700, 22)).tracking(0.02 * 22)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(NBFont.dot(600, 10)).tracking(0.12 * 10)
                        .foregroundStyle(NB.text3Prod)
                }
            }
        }
        .padding(slot.insets)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VHair: View {
    var body: some View {
        Rectangle().fill(NB.hairline).frame(width: 1)
    }
}

private struct MonthAxis: View {
    var body: some View {
        let f = DateFormatter()
        let months: [String] = (0..<6).reversed().map { back in
            let d = Calendar.current.date(byAdding: .month, value: -back, to: Date())!
            f.locale = AppLanguage.shared.swiftLocale
            f.dateFormat = AppLanguage.shared.isEnglish ? "MMM" : "M月"
            return f.string(from: d).uppercased()
        }
        return HStack(spacing: 0) {
            ForEach(months, id: \.self) { m in
                Text(m)
                    .font(NBFont.dot(500, 9)).tracking(0.14 * 9)
                    .foregroundStyle(NB.white.opacity(0.26))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// One cell is one day; a column is a week; the colour is Daily Direction.
/// Every cell is tappable and lands on that day's composition detail.
struct DirectionHeatMap: View {
    let history: [DailyMetrics]
    var today: DailyMetrics? = nil
    let onDay: (UserDay) -> Void

    private let rows = 7
    private let weeks = 26
    private let gap: CGFloat = 3

    /// The card hands it `contentWidth` minus its own 14pt padding on each side. The cell
    /// size and the view's height must come from the same arithmetic: the old code measured
    /// the width in a GeometryReader but hardcoded the height to `7 * 9 + 6 * 3`, a 9pt cell
    /// no real phone has — so the grid overflowed its frame and landed on the legend.
    private var cell: CGFloat {
        (NB.Layout.contentWidth - 28 - gap * CGFloat(weeks - 1)) / CGFloat(weeks)
    }

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: gap) {
                    ForEach(0..<rows, id: \.self) { r in
                        let day = dayFor(week: w, row: r)
                        let metrics = metrics(for: day)
                        Button { onDay(day) } label: {
                            DirectionCell(direction: metrics?.direction ?? .greyNothing,
                                          height: cell, radius: 2)
                                .frame(width: cell, height: cell)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func metrics(for day: UserDay) -> DailyMetrics? {
        if let today, today.day == day { return today }
        return history.first { $0.day == day }
    }

    private func dayFor(week: Int, row: Int) -> UserDay {
        let today = UserDay.containing(Date())
        let daysBack = (weeks - 1 - week) * 7 + (6 - row)
        return today.adding(days: -daysBack)
    }
}

/// F0 D05 · four words in one row. The swatch is the same cell the map paints, so
/// LEVEL stays an outline and GAP is the empty grey — never the quadrant palette.
struct DirectionLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            chip(.deficit, MetricNames.deficit)
            chip(.surplus, MetricNames.surplus)
            chip(.level, MetricNames.level)
            chip(.greyNothing, L("GAP"))
        }
    }

    private func chip(_ direction: DailyDirection, _ label: String) -> some View {
        HStack(spacing: 6) {
            DirectionCell(direction: direction, height: 8, radius: 2)
                .frame(width: 8, height: 8)
            Text(label)
                .font(NBFont.ui(500, 10)).tracking(0.12 * 10)
                .foregroundStyle(NB.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
