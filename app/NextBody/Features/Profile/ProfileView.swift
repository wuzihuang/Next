import SwiftUI

/// 11 · 我的 Profile. The title is ME, not SETTINGS: the first thing this page gives you is
/// you, not a control panel. Reached only from the avatar; back goes to the root.
/// The only second-level page in the product hangs off the DEVICE row.
struct ProfileView: View {
    @ObservedObject private var language = AppLanguage.shared
    @ObservedObject private var consent = ConsentStore.shared
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    private var hasScans: Bool { !data.weighIns.isEmpty }

    var body: some View {
        DetailScroll(glow: NB.lime1, title: L("ME")) {
            VStack(alignment: .leading, spacing: 14) {
                identityCard
                heatMapCard
                statTiles

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
                    // The only second level in the product — it really has a page of content.
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
                    SettingRow(title: L("UNITS"), value: data.profile.usesMetric ? L("METRIC · KG") : L("IMPERIAL · LB")) {
                        router.sheet = .units
                    }
                    // 11 edge 1 · a source that stopped answering: the value goes amber and the row
                    // carries the last read. ⚠️ Read permission cannot be probed, so the row says what
                    // is known — when something last came back — never "you turned it off".
                    SettingRow(title: L("APPLE HEALTH"),
                               value: data.profile.appleHealthLinked ? "SYNCED" : "NOT CONNECTED",
                               valueTint: data.profile.appleHealthLinked ? nil : NB.ember1,
                               detail: healthLastRead.map { "LAST READ \($0) · NOTHING NEW" }) {
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
    /// The day Health last answered with anything, or nil if it never has. Shown only while
    /// the latest read came back empty.
    private var healthLastRead: String? {
        guard !data.profile.appleHealthLinked, HealthService.shared.asked,
              let at = UserDefaults.standard.object(forKey: "nb.health.lastRead") as? Date else { return nil }
        return Fmt.displayDate(at, format: "MMM d").uppercased()
    }

    private var goalLabel: String {
        switch data.profile.goal {
        case .cut: L("ENDURANCE"); case .recomp: L("RECOMP"); case .bulk: L("STRENGTH")
        }
    }

    /// Name, email and the three numbers that barely move — a card, not a settings row.
    /// Tapping it goes to PERSONAL INFO, the same place as the row below.
    private var identityCard: some View {
        VStack(spacing: 0) {
            Button { router.sheet = .profileEdit } label: {
                HStack(spacing: 14) {
                    Avatar(size: 44, initials: data.profile.initials)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(data.profile.displayName.uppercased())
                            .font(NBFont.ui(600, 16)).tracking(0.04 * 16)
                            .foregroundStyle(NB.text1)
                            .lineLimit(1)
                        Text(data.profile.email)
                            .font(NBFont.dot(500, 11)).tracking(0.02 * 11)
                            .foregroundStyle(NB.white.opacity(0.34))
                    }
                    Spacer(minLength: 0)
                    Chevron()
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            Hairline()

            HStack(spacing: 0) {
                IdentityStat(label: L("HEIGHT"), value: "\(Int(data.profile.heightCm))", unit: "CM")
                IdentityStat(label: L("WEIGHT"), value: Fmt.kg(data.today.weightKg), unit: "KG")
                IdentityStat(label: L("AGE"), value: "\(data.profile.age)", unit: nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(width: NB.Layout.contentWidth)
        .cardSkin()
    }


    /// A2 · the only "one year" view in the product, so it earns half the first screen and
    /// sits above every setting. One cell is one day, and the colour is Daily Direction —
    /// never the quadrant palette (F0 rule 05).
    private var heatMapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("COMPOSITION"))
                    .font(NBFont.ui(500, 11)).tracking(0.24 * 11)
                    .foregroundStyle(NB.text1)
                Spacer(minLength: 0)
                Text(hasScans ? L("RECOMP · 12 W") : L("NO WEIGH-INS YET"))
                    .font(NBFont.dot(500, 11)).tracking(0.04 * 11)
                    .foregroundStyle(hasScans ? NB.macroValue : NB.text3Prod)
            }
            MonthAxis()
            DirectionHeatMap(history: data.history) { day in
                router.open(.composition(date: day.start), from: .profile)
            }
            DirectionLegend()
            if !hasScans {
                HStack(alignment: .center) {
                    Text(L("WEIGH IN ON 5 MORNINGS AND\nTHE FIRST SQUARE LIGHTS UP"))
                        .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                        .lineSpacing(4)
                        .foregroundStyle(NB.text3Prod)
                    Spacer(minLength: 0)
                    Button { router.sheet = .weighIn } label: {
                        Text(L("ADD A WEIGH-IN"))
                            .font(NBFont.ui(600, 11)).tracking(0.12 * 11)
                            .foregroundStyle(NB.lime1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
    }

    /// Three numbers, all 12-week net changes except BODY FAT, which is an absolute value
    /// and therefore has to be labelled apart from the two deltas around it.
    private var statTiles: some View {
        HStack(spacing: 8) {
            NetTile(label: L("FAT MASS"), value: Fmt.signedKg(data.netFatMass12w, decimals: 1), unit: "KG",
                    tint: data.netFatMass12w == nil ? NB.text3Prod : NB.lime1)
            NetTile(label: L("LEAN MASS"), value: Fmt.signedKg(data.netLeanMass12w, decimals: 1), unit: "KG",
                    tint: data.netLeanMass12w == nil ? NB.text3Prod : NB.lime1)
            NetTile(label: L("BODY FAT"), value: Fmt.kg(data.bodyFatPercent), unit: "%",
                    tint: NB.text1, isAbsolute: true)
        }
        .frame(width: NB.Layout.contentWidth)
    }
}

// MARK: pieces

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
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 1, y: 1))
            p.addLine(to: CGPoint(x: 5, y: 5))
            p.addLine(to: CGPoint(x: 1, y: 9))
        }
        .stroke(Color(hex: 0x5A5A66), style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
        .frame(width: 6, height: 10)
    }
}

private struct IdentityStat: View {
    let label: String
    let value: String
    let unit: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(NBFont.ui(500, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.text3Prod)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(NBFont.ui(500, 17)).tracking(0.01 * 17)
                    .foregroundStyle(NB.text1)
                if let unit {
                    Text(unit)
                        .font(NBFont.dot(500, 10))
                        .foregroundStyle(NB.white.opacity(0.34))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NetTile: View {
    let label: String
    let value: String
    let unit: String
    let tint: Color
    var isAbsolute = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(NBFont.ui(500, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.text3Prod)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(NBFont.dot(700, 20))
                    .foregroundStyle(tint)
                Text(unit)
                    .font(NBFont.dot(500, 10))
                    .foregroundStyle(NB.white.opacity(0.34))
            }
            // ⚠️ BODY FAT is an absolute value sitting between two deltas — it must say so.
            Text(isAbsolute ? L("ABSOLUTE") : L("12 W NET"))
                .font(NBFont.dot(500, 9)).tracking(0.14 * 9)
                .foregroundStyle(NB.white.opacity(0.26))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous)
            .stroke(NB.hairline, lineWidth: 1))
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
                        let metrics = history.first { $0.day == day }
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

    private func dayFor(week: Int, row: Int) -> UserDay {
        let today = UserDay.containing(Date())
        let daysBack = (weeks - 1 - week) * 7 + (6 - row)
        return today.adding(days: -daysBack)
    }
}

/// F0 D05 · three tiers plus two greys. The quadrant words never appear here.
struct DirectionLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                LegendChip(direction: .deficit, label: MetricNames.deficit, note: "≤ −150 KCAL")
                LegendChip(direction: .level, label: MetricNames.level, note: "±150 KCAL")
            }
            HStack(spacing: 18) {
                LegendChip(direction: .surplus, label: MetricNames.surplus, note: "≥ +150 KCAL")
                LegendChip(direction: .greyNothing, label: L("NOT LOGGED"), note: L("NOTHING TO GO ON"))
            }
            LegendChip(direction: .greyNoBurn, label: L("NO BURN"), note: L("BAND OFF MOST OF THE DAY"))
        }
    }
}

private struct LegendChip: View {
    let direction: DailyDirection
    let label: String
    let note: String
    var body: some View {
        HStack(spacing: 8) {
            DirectionCell(direction: direction, height: 9, radius: 2)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(NBFont.ui(500, 10.5)).tracking(0.12 * 10.5)
                    .foregroundStyle(NB.text2)
                Text(note)
                    .font(NBFont.dot(500, 9)).tracking(0.1 * 9)
                    .foregroundStyle(NB.white.opacity(0.26))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
