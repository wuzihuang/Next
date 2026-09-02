import SwiftUI

/// 补屏 B · NO TARGET 整屏 — 09 板 · 四块不是六块 · ONE ACTION.
///
/// Shown only to an account that has never had a weight (rule 07). 「一句「请先添加体重」写得出
/// 来，但它浪费掉这一屏唯一一次机会」— so the page says what it *can* count without a denominator,
/// and what a weigh-in turns on. Rule 08: what disappears is the bar, not the number — grams and
/// kcal eaten stay as bare figures; rings, percentages and 「/ 目标」 do not draw. Rule 09: any
/// subtraction with a —— in it is ——, never 0. Rule 11: the last block is text only.
struct NoTargetFuel: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router
    private var m: DailyMetrics { data.today }

    private let ink = Color(hex: 0xF4F4F6)
    private let sub = Color(hex: 0x8A8A93)

    var body: some View {
        DetailScroll(glow: NB.ember1) {
            VStack(alignment: .leading, spacing: 22) {
                // Same header as the page with a target, so the two never feel like two apps.
                HStack(alignment: .firstTextBaseline) {
                    Text("FUEL").font(NBFont.brand(700, 28)).tracking(-0.02 * 28).foregroundStyle(NB.text1)
                    Spacer(minLength: 0)
                    Text("\(Fmt.dash) TARGET").font(NBFont.dot(700, 12)).tracking(0.04 * 12).foregroundStyle(NB.emberPale)
                }

                // NO TARGET · the one action
                VStack(alignment: .leading, spacing: 16) {
                    Text("NO TARGET").font(NBFont.dot(700, 11)).tracking(0.24 * 11).foregroundStyle(NB.ember1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Fmt.dash).font(NBFont.dot(800, 64)).foregroundStyle(NB.white.opacity(0.24))
                        Text("KCAL TARGET").font(NBFont.dot(600, 11)).tracking(0.2 * 11).foregroundStyle(NB.text3Prod)
                    }
                    Text("Targets are built from your body weight. Without it, HOOP can count what you eat, but it can't tell you how much you need.")
                        .font(NBFont.ui(300, 15)).lineSpacing(8).foregroundStyle(sub)
                    // 1F5B · one 298 × 52 pill, the screen's only action.
                    Button { router.sheet = .weighIn } label: {
                        Text("Add a weigh-in")
                            .font(NBFont.ui(500, 13.5)).tracking(0.15 * 13.5)
                            .foregroundStyle(NB.carbon)
                            .frame(width: 298, height: 52)
                            .background(NB.lime1, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Text("Type it in, or pull the latest from Apple Health.")
                        .font(NBFont.ui(300, 13)).lineSpacing(6).foregroundStyle(sub)
                }
                .padding(22)
                .frame(width: NB.Layout.contentWidth, alignment: .leading)
                .cardSkin()

                // LOGGED TODAY · counts, not comparisons
                VStack(alignment: .leading, spacing: 16) {
                    Text("LOGGED TODAY").font(NBFont.dot(600, 11)).tracking(0.24 * 11).foregroundStyle(NB.text3Prod)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Fmt.kcal(m.eIn)).font(NBFont.dot(800, 44)).foregroundStyle(m.eIn == nil ? NB.white.opacity(0.24) : NB.ember1)
                            Text("KCAL EATEN").font(NBFont.dot(600, 11)).tracking(0.2 * 11).foregroundStyle(NB.text3Prod)
                        }
                        Text(mealsLine).font(NBFont.ui(300, 13)).foregroundStyle(sub)
                    }
                    HStack(spacing: 0) {
                        gram("PROTEIN", m.protein?.eaten).frame(width: 102, alignment: .leading)
                        gram("CARBS", m.carb?.eaten).frame(width: 91, alignment: .leading)
                        gram("FAT", m.fat?.eaten).frame(width: 80, alignment: .leading)
                    }
                    Text("No targets to compare them to yet.").font(NBFont.ui(300, 13)).foregroundStyle(sub)
                }
                .padding(22)
                .frame(width: NB.Layout.contentWidth, alignment: .leading)
                .cardSkin()

                // THE BAND COUNTED · true without a weight
                VStack(alignment: .leading, spacing: 0) {
                    Text("THE BAND COUNTED").font(NBFont.dot(600, 11)).tracking(0.24 * 11).foregroundStyle(NB.text3Prod)
                        .padding(.bottom, 8)
                    countRow("Steps", m.steps.map { Fmt.int($0) } ?? Fmt.dash)
                    countRow("Distance", distance)
                    countRow("Active minutes", m.activeMinutes.map(String.init) ?? Fmt.dash)
                    HStack {
                        Text("Burn").font(NBFont.ui(400, 15)).foregroundStyle(ink)
                        Spacer(minLength: 0)
                        Text("NEEDS YOUR WEIGHT").font(NBFont.dot(600, 10)).tracking(0.18 * 10).foregroundStyle(NB.ember1)
                            .accessibilityLabel("Needs you")
                        Text(Fmt.dash).font(NBFont.dot(600, 15)).foregroundStyle(NB.white.opacity(0.32)).padding(.leading, 10)
                    }
                    .frame(height: 44)
                }
                .padding(22)
                .frame(width: NB.Layout.contentWidth, alignment: .leading)
                .cardSkin()

                // WHAT A WEIGH-IN TURNS ON · text only (rule 11)
                VStack(alignment: .leading, spacing: 12) {
                    Text("WHAT A WEIGH-IN TURNS ON").font(NBFont.dot(600, 11)).tracking(0.24 * 11).foregroundStyle(NB.text3Prod)
                    ForEach([
                        "A calorie target for the day, and how far you are from it.",
                        "Protein, carbs and fat measured against a target, not just a total.",
                        "Energy gap — what you ate minus what the band burned.",
                        "HOOP can finally answer \"how much more should I eat today?\"",
                    ], id: \.self) { line in
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(NB.ember1).frame(width: 4, height: 4).padding(.top, 9)
                            Text(line).font(NBFont.ui(300, 14)).lineSpacing(7).foregroundStyle(sub)
                        }
                    }
                }
                .padding(22)
                .frame(width: NB.Layout.contentWidth, alignment: .leading)
                .cardSkin()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            router.backToRoot()
        }
    }

    private var mealsLine: String {
        let n = data.meals.filter { $0.status == .confirmed }.count
        return n == 0 ? "nothing yet" : "from \(n) meal\(n == 1 ? "" : "s")"
    }
    private var distance: String {
        guard let d = m.distanceM else { return Fmt.dash }
        return UserDefaults.standard.string(forKey: "nb.units") == "imperial"
            ? String(format: "%.1f mi", Double(d) / 1609.344)
            : String(format: "%.1f km", Double(d) / 1000)
    }
    private func gram(_ label: String, _ g: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(NBFont.dot(600, 10)).tracking(0.18 * 10).foregroundStyle(NB.text3Prod)
            Text(g.map { "\($0) g" } ?? Fmt.dash).font(NBFont.brand(500, 16)).foregroundStyle(ink)
        }
    }
    private func countRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(NBFont.ui(400, 15)).foregroundStyle(ink)
            Spacer(minLength: 0)
            Text(value).font(NBFont.dot(600, 15)).foregroundStyle(value == Fmt.dash ? NB.white.opacity(0.32) : ink)
        }
        .frame(height: 44)
        .overlay(alignment: .bottom) { Hairline() }
    }
}
