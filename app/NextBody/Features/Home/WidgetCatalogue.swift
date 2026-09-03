#if DEBUG
import SwiftUI

/// 07 · the render contract, laid out so it can be audited.
///
/// The panel only ever shows one widget at a time, and which one is the model's choice —
/// which makes the catalogue the one board that cannot be checked by using the app. This
/// screen renders every type the model is allowed to pick, with data shaped exactly as the
/// contract table on 07 specifies it, so the ten renderers, the accent map and the four
/// hero styles can be read against the board in one pass.
///
/// ⚠️ DEBUG only, and reachable only from a long press on the wordmark. It is not a
/// product surface: there is no route to it, and it ships in no release build.
struct WidgetCatalogue: View {
    @Environment(\.dismiss) private var dismiss

    /// All 27. The night's three came back on 2026-09-03 with the user's own ruling, so the
    /// catalogue covers the contract in full again.
    private var types: [PanelType] { PanelType.allCases }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text("\(types.count) TYPES · 12 RENDERERS")
                        .font(NBFont.dot(600, 10)).tracking(0.18 * 10)
                        .foregroundStyle(NB.text3Prod)
                    Spacer(minLength: 12)
                    Button("CLOSE") { dismiss() }
                        .font(NBFont.dot(600, 10)).tracking(0.18 * 10)
                        .foregroundStyle(NB.lime1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)

                // Two columns at 44%, so the whole contract fits in three screenfuls and can
                // be read against the board in one sitting rather than scrolled past.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)], spacing: 16) {
                    ForEach(types, id: \.self) { type in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(type.rawValue.uppercased()) · \(String(describing: type.renderer).uppercased())")
                                .font(NBFont.dot(500, 8)).tracking(0.12 * 8)
                                .foregroundStyle(NB.text3Prod)
                                .lineLimit(1)
                            PanelWidgetView(widget: Self.sample(type)) { _ in }
                                .frame(width: NB.Layout.contentWidth, height: NB.Layout.panelHeight)
                                .background(NB.carbon2, in: RoundedRectangle(cornerRadius: NB.R.hero,
                                                                             style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: NB.R.hero, style: .continuous)
                                    .stroke(NB.hairline, lineWidth: 1))
                                // ⚠️ Default (centre) anchor. With .topLeading the scaled
                                // panel keeps its original layout origin and spills out of
                                // the cell, so the left column drew off the screen edge and
                                // the columns overlapped.
                                .scaleEffect(0.44)
                                .frame(width: NB.Layout.contentWidth * 0.44,
                                       height: NB.Layout.panelHeight * 0.44)
                                .clipped()
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 40)
        }
        .background(NB.carbon)
    }

    /// One envelope per type, with the data shape the contract table gives it.
    static func sample(_ type: PanelType) -> PanelWidget {
        let series: [Double] = [58, 60, 58, 64, 63, 62, 66, 64, 69, 71, 68, 72]
        switch type {
        case .battery:
            return w(type, MetricNames.bodyBattery, "64 right now.", .ring(value: 64, goal: 100, unit: "%"))
        case .metric:
            var m = w(type, "HEART RATE", "Calm pulse — right where it should be", .none)
            m.hero = "68 bpm"
            m.heroSub = "+4 VS RHR 52 · MEASURED 14:20"
            m.footer = "RANGE TODAY 52–172 · BASELINE STEADY"
            return m
        case .text:
            // 07 · rule 6 · the board's own text screen, its three lines and no sentence slot.
            var t = w(type, "TODAY'S CALL", "4 days since your last lift · legs are fresh",
                      .none)
            t.tag = .move
            t.headline = HeadlineBlock(eyebrow: "BATTERY 86% · TARGET 14.5",
                                       headline: "LIFT TODAY", sub: "STRENGTH · 45 MIN")
            t.action = "PRIME WINDOW 17:00 → 20:00"
            t.footer = "8,432 STEPS · 7H12M IN BED"
            return t
        case .line:
            var l = w(type, "HRV · 12 NIGHTS", "62 ms over twelve nights", .series(series))
            l.hero = "62 ms"
            return l
        case .band:
            return w(type, "BLOOD PRESSURE", "118 / 76 · in range", .pair(hi: series.map { $0 + 50 }, lo: series))
        case .bars:
            return w(type, "STEPS · 30-MIN", "The evening walk carried the day",
                     .bins([("06:00", 120), ("08:00", 340), ("10:00", 260), ("12:00", 410),
                            ("14:00", 300), ("16:00", 620), ("18:00", 1904), ("20:00", 480)]))
        case .days:
            return w(type, "LOAD", "7d avg 13.1", .bins([("M", 15), ("T", 9.3), ("W", 16),
                                                         ("T", 11.5), ("F", 6.9), ("S", 13.9), ("S", 12.4)]))
        case .sparks:
            return w(type, "LAST NIGHT", "Three inputs, all measured.",
                     .rows([.init(label: "HRV", value: "62 ms", spark: series),
                            .init(label: "RHR", value: "48 bpm", spark: series.reversed()),
                            .init(label: "SPO2", value: "97 %", spark: series)]))
        case .ring:
            return w(type, MetricNames.training, "5.0 of 21", .ring(value: 5, goal: 21, unit: ""))
        case .gauge:
            return w(type, "STRESS", "31 · resting", .gauge(value: 31, zones: [(0, 40, "REST"),
                                                                               (40, 70, "MID"),
                                                                               (70, 100, "HIGH")]))
        case .cells:
            return w(type, "WEIGH-INS", "5 of 7 days", .cells(rows: 1, cols: 7,
                                                              values: [1, 1, 0, 1, 1, 0, 1], levels: 2))
        case .zones:
            // 13 · five columns, minutes per zone.
            return w(type, "TIME IN ZONE", "50 min elevated · Z2 carried it",
                     .zones([25, 30, 20, 8, 0]))
        case .hypnogram:
            // 12 · run-length lanes: 0 awake · 1 light · 2 deep.
            return w(type, "SLEEP · 23:41 → 07:18", "Two clean deep blocks before 3 am",
                     .lanes(runs: [(0, 18), (1, 42), (2, 108), (1, 36), (2, 44), (1, 30),
                                   (0, 14), (1, 46), (0, 30)],
                            from: "23:41", to: "07:18"))
        case .split:
            return w(type, "SLEEP MIX", "Deep sleep did its job — 24% of the night",
                     hero: "7H38",
                     .parts([("DEEP", 108, NB.violet1), ("LIGHT", 324, NB.violet1.opacity(0.6)),
                             ("AWAKE", 26, NB.white.opacity(0.5))]))
        case .o2night:
            return w(type, "NIGHT O2", "Two brief dips — worth watching",
                     .series([97, 96, 96, 95, 97, 96, 89, 94, 96, 97, 91, 96]))
        case .wave:
            return w(type, "ECG", "avg 68 bpm", .trace(samples: series, hz: 4))
        case .table:
            return w(type, "TODAY'S BUILD", "Three sources, 5.0 total",
                     .rows([.init(label: "MORNING WALK", value: "+2.0"),
                            .init(label: "ELEVATED HR", value: "+1.3"),
                            .init(label: "STEPS", value: "+1.7")]))
        case .workout:
            return w(type, "SESSION", "45 min · avg 136 bpm", hero: "45 MIN",
                     .rows([.init(label: "STRENGTH", value: "45 MIN"),
                            .init(label: "AVG HR", value: "136")]))
        case .events:
            return w(type, "TODAY", "Four things happened", hero: "4",
                     .rows([.init(label: "07:20 BREAKFAST", value: "375"),
                            .init(label: "07:30 WALK", value: "+2.0"),
                            .init(label: "12:40 LUNCH", value: "532"),
                            .init(label: "18:00 SESSION", value: "+8.9")]))
        case .heat:
            return w(type, "WEEK × HOUR", "Evenings are the load", hero: "18:00",
                     .cells(rows: 7, cols: 12,
                            values: (0..<84).map { ($0 * 7) % 4 }, levels: 4))
        case .food:
            // 07 · 20 · the plate: name, kcal as the hero, three macro rows.
            var f = w(type, "LOGGED · 12:42", "Good pick — 48 g protein still to place",
                      .rows([.init(label: "CHICKEN SALAD", value: "420")]))
            f.plate = PlateBlock(name: "Chicken salad", portion: "1 bowl", kcal: 420,
                                 protein: 32, carb: 18, fat: 22, pctOfBudget: 31)
            f.footer = "660 KCAL LEFT · KITCHEN CLOSES 21:00"
            return f
        case .meal:
            return w(type, "LUNCH", "532 kcal · 50 g protein", hero: "532",
                     .rows([.init(label: "CHICKEN", value: "310"),
                            .init(label: "RICE", value: "160"),
                            .init(label: "GREENS", value: "62")]))
        case .fuel:
            // ⚠️ 07 gives fuel's hero as "biggest gap", which needs the target beside each
            // eaten value — the stack shape carries one number per part and cannot derive
            // it. The server sends it as data.hero, and that is the case data.hero exists
            // for; deriving parts[0] instead would name protein whether or not it is the gap.
            return w(type, "MACROS", "Protein is the gap", hero: "61 G PRO",
                     .parts([("PRO", 84, NB.violet1), ("CARB", 80, NB.optimal2), ("FAT", 22, NB.run1)]))
        case .balance:
            // Same reason: the board's hero is "in − out", not either operand.
            return w(type, "ENERGY", "907 in · 1,578 out", hero: "−671",
                     .parts([("IN", 907, NB.ember1), ("OUT", 1578, NB.cyan1)]))
        case .recomp:
            return w(type, "COMPOSITION · 12 W", "Nine of the last twelve weeks moved fat down",
                     hero: "−3.1 % FAT",
                     .cells(rows: 7, cols: 12, values: (0..<84).map { $0 % 5 }, levels: 5))
        case .delta:
            return w(type, "NET CHANGE", "−0.5 kg fat, +2.0 kg lean",
                     .bins([("FAT", -0.5), ("LEAN", 2.0)]))
        case .dual:
            return w(type, "FAT VS LEAN", "The lines crossed in week 9",
                     .pair(hi: series, lo: series.map { $0 * 0.8 }))
        }
    }

    private static func w(_ type: PanelType, _ title: String, _ sentence: String,
                          hero: String? = nil, _ data: PanelData) -> PanelWidget {
        PanelWidget(type: type, title: title, tag: nil, sentence: sentence,
                    footer: nil, action: nil, hero: hero, data: data)
    }
}
#endif
