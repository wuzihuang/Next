import SwiftUI

/// 11 · 我的 Profile. The title is ME, not SETTINGS: the first thing this page gives you is
/// you, not a control panel. Reached only from the avatar; back goes to the root.
/// The only second-level page in the product hangs off the DEVICE row.
struct ProfileView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    private var hasScans: Bool { !data.weighIns.isEmpty }

    var body: some View {
        DetailScroll(glow: NB.lime1) {
            VStack(alignment: .leading, spacing: 14) {
                header
                identityCard
                heatMapCard
                statTiles

                GroupLabel("ACCOUNT")
                RowGroup {
                    SettingRow(title: "PERSONAL INFO", value: data.profile.name.uppercased()) {
                        router.sheet = .profileEdit
                    }
                    SettingRow(title: "BODY METRICS",
                               value: "\(Int(data.profile.heightCm)) CM · \(Fmt.kg(data.today.weightKg)) KG") {
                        router.sheet = .weighIn
                    }
                    SettingRow(title: "TRAINING GOAL", value: goalLabel) {
                        router.sheet = .goal
                    }
                    // The only second level in the product — it really has a page of content.
                    SettingRow(title: "DEVICE",
                               value: data.band.connected
                                    ? "HOOP · \(data.band.batteryPercent)%"
                                    : "HOOP · DAY 1") {
                        router.open(.device, from: .profile)
                    }
                }

                GroupLabel("PREFERENCES")
                RowGroup {
                    SettingRow(title: "NOTIFICATIONS", value: "ON") { router.sheet = .notifications }
                    SettingRow(title: "UNITS", value: data.profile.usesMetric ? "METRIC · KG" : "IMPERIAL · LB") {
                        router.sheet = .units
                    }
                    SettingRow(title: "APPLE HEALTH",
                               value: data.profile.appleHealthLinked ? "SYNCED" : "NOT CONNECTED",
                               valueTint: data.profile.appleHealthLinked ? nil : NB.ember1) {
                        router.sheet = .appleHealth
                    }
                    SettingRow(title: "LANGUAGE", value: "ENGLISH") { router.sheet = .language }
                }

                GroupLabel("DATA & LEGAL")
                RowGroup {
                    SettingRow(title: "EXPORT MY DATA", value: hasScans ? "ALL TIME" : "NOTHING YET") {
                        router.sheet = .export
                    }
                    SettingRow(title: "PRIVACY POLICY", value: "UPDATED JUN 24") { router.sheet = .privacy }
                    SettingRow(title: "TERMS OF SERVICE", value: "V 2.1") { router.sheet = .about }
                    // The second of only two places in the product allowed to use red.
                    SettingRow(title: "DELETE ACCOUNT", value: "PERMANENT",
                               titleTint: NB.alert2) { router.sheet = .deleteAccount }
                }

                Button { router.sheet = .signOut } label: {
                    Text("SIGN OUT")
                        .font(NBFont.ui(500, 12)).tracking(0.2 * 12)
                        .foregroundStyle(NB.text1)
                        .frame(width: NB.Layout.contentWidth, height: 48)
                        .background(Color(hex: 0x141418), in: Capsule())
                        .overlay(Capsule().stroke(NB.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                Text("NEXTBODY 1.4.2  ·  BUILD 2831")
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

    private var goalLabel: String {
        switch data.profile.goal {
        case .cut: "ENDURANCE"; case .recomp: "RECOMP"; case .bulk: "STRENGTH"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROFILE")
                .font(NBFont.ui(500, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.text3Prod)
            Text("ME")
                .font(NBFont.brand(700, 34)).tracking(-0.02 * 34)
                .foregroundStyle(NB.text1)
        }
        .padding(.top, 14)
    }

    /// Name, email and the three numbers that barely move — a card, not a settings row.
    /// Tapping it goes to PERSONAL INFO, the same place as the row below.
    private var identityCard: some View {
        VStack(spacing: 0) {
            Button { router.sheet = .profileEdit } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color(hex: 0x1B1B20))
                        Circle().stroke(NB.hairline, lineWidth: 1)
                        Text(initials)
                            .font(NBFont.ui(600, 14)).tracking(0.06 * 14)
                            .foregroundStyle(NB.text1)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(data.profile.name.uppercased())
                            .font(NBFont.ui(600, 16)).tracking(0.04 * 16)
                            .foregroundStyle(NB.text1)
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
                IdentityStat(label: "HEIGHT", value: "\(Int(data.profile.heightCm))", unit: "CM")
                IdentityStat(label: "WEIGHT", value: Fmt.kg(data.today.weightKg), unit: "KG")
                IdentityStat(label: "AGE", value: "\(data.profile.age)", unit: nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(width: NB.Layout.contentWidth)
        .cardSkin()
    }

    private var initials: String {
        data.profile.name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
    }

    /// A2 · the only "one year" view in the product, so it earns half the first screen and
    /// sits above every setting. One cell is one day, and the colour is Daily Direction —
    /// never the quadrant palette (F0 rule 05).
    private var heatMapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("COMPOSITION")
                    .font(NBFont.ui(500, 11)).tracking(0.24 * 11)
                    .foregroundStyle(NB.text1)
                Spacer(minLength: 0)
                Text(hasScans ? "RECOMP · 12 W" : "NO WEIGH-INS YET")
                    .font(NBFont.dot(500, 11)).tracking(0.04 * 11)
                    .foregroundStyle(hasScans ? NB.macroValue : NB.text3)
            }
            MonthAxis()
            DirectionHeatMap(history: data.history) { day in
                router.open(.composition(date: day.start), from: .profile)
            }
            DirectionLegend()
            if !hasScans {
                HStack(alignment: .center) {
                    Text("WEIGH IN ON 5 MORNINGS AND\nTHE FIRST SQUARE LIGHTS UP")
                        .font(NBFont.ui(400, 11)).tracking(0.04 * 11)
                        .lineSpacing(4)
                        .foregroundStyle(NB.text3Prod)
                    Spacer(minLength: 0)
                    Button { router.sheet = .weighIn } label: {
                        Text("ADD A WEIGH-IN")
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
            NetTile(label: "FAT MASS", value: Fmt.signedKg(data.netFatMass12w, decimals: 1), unit: "KG",
                    tint: data.netFatMass12w == nil ? NB.text3 : NB.lime1)
            NetTile(label: "LEAN MASS", value: Fmt.signedKg(data.netLeanMass12w, decimals: 1), unit: "KG",
                    tint: data.netLeanMass12w == nil ? NB.text3 : NB.lime1)
            NetTile(label: "BODY FAT", value: Fmt.kg(data.bodyFatPercent), unit: "%",
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(NBFont.ui(500, 13)).tracking(0.06 * 13)
                    .foregroundStyle(titleTint ?? NB.text1)
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .font(NBFont.dot(500, 10.5)).tracking(0.14 * 10.5)
                        .foregroundStyle(valueTint ?? NB.text3Prod)
                }
                Chevron()
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
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
            Text(isAbsolute ? "ABSOLUTE" : "12 W NET")
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
            f.dateFormat = "MMM"
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

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 3
            let cell = (geo.size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks)
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
        .frame(height: 7 * 9 + 6 * 3)
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
                LegendChip(direction: .greyNothing, label: "NOT LOGGED", note: "NOTHING TO GO ON")
            }
            LegendChip(direction: .greyNoBurn, label: "NO BURN", note: "BAND OFF MOST OF THE DAY")
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
