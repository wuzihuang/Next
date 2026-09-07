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
    /// Pin the band's result layout without starting a BLE measurement.
    static var balanceResult: PanelWidget {
        let points: [CGPoint] = (0..<22).map { i in
            let interval = CGFloat(850 + i * 4)
            let variation = CGFloat((i % 3 - 1) * 9)
            return CGPoint(x: interval, y: interval + variation)
        }
        return PanelWidget(type: .balance, title: L("BALANCE"), sentence: "", data: .none,
                           balance: BalanceAnswer(
                            headline: L("Drive is leading."),
                            note: L("Your beats came at a steadier spacing, which is what effort, caffeine or a busy head all look like from here."),
                            restShare: 0.19,
                            footer: L("67 BPM · SD1 7 MS · SD2 30 MS · 22 BEATS"),
                            points: points))
    }

    @Environment(\.dismiss) private var dismiss

    /// All 34. The night's three came back on 2026-09-03 with the user's own ruling, and the
    /// 2026-09-06 gap audit added six more, so the catalogue covers the contract in full.
    private var types: [PanelType] { PanelType.allCases }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text(L("%d TYPES · 16 RENDERERS", types.count))
                        .font(NBFont.dot(600, 10)).tracking(0.18 * 10)
                        .foregroundStyle(NB.text3Prod)
                    Spacer(minLength: 12)
                    Button(L("CLOSE")) { dismiss() }
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
            m.heroSub = L("+4 VS RHR 52 · MEASURED 14:20")
            m.footer = L("RANGE TODAY 52–172 · BASELINE STEADY")
            return m
        case .text:
            // 07 · rule 6 · the board's own text screen, its three lines and no sentence slot.
            var t = w(type, "TODAY'S CALL", "4 days since your last lift · legs are fresh",
                      .none)
            t.tag = .move
            t.headline = HeadlineBlock(eyebrow: L("BATTERY 86% · TARGET 14.5"),
                                       headline: L("LIFT TODAY"), sub: L("STRENGTH · 45 MIN"))
            t.action = L("PRIME WINDOW 17:00 → 20:00")
            t.footer = L("8,432 STEPS · 7H12M IN BED")
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
                     .rows([.init(label: L("HRV"), value: "62 ms", spark: series),
                            .init(label: L("RHR"), value: "48 bpm", spark: series.reversed()),
                            .init(label: L("SPO2"), value: "97 %", spark: series)]))
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
            return w(type, "NIGHT O2", "Mean 95% · lowest 89%",
                     .series([97, 96, 96, 95, 97, 96, 89, 94, 96, 97, 91, 96]))
        case .wave:
            // 2026-09-06 · wave used to be captioned ECG, which the band does not produce
            // (metric-query marks ecg unsupported). Its source is the RR tachogram: one
            // sample per beat, in milliseconds, so the copy is milliseconds too.
            var wv = w(type, "RR INTERVALS", "Steady beat to beat", hero: "48 BEATS",
                       .trace(samples: [812, 796, 824, 808, 788, 832, 800, 776, 820, 804,
                                        796, 840, 812, 784, 808, 828, 792, 816, 800, 780],
                              hz: 1.3))
            wv.footer = L("MEAN 806 MS · LAST READING")
            return wv
        case .table:
            return w(type, "TODAY'S BUILD", "Three sources, 5.0 total",
                     .rows([.init(label: L("MORNING WALK"), value: "+2.0"),
                            .init(label: L("ELEVATED HR"), value: "+1.3"),
                            .init(label: L("STEPS"), value: "+1.7")]))
        case .workout:
            return w(type, "SESSION", "45 min · avg 136 bpm", hero: "45 MIN",
                     .rows([.init(label: L("STRENGTH"), value: "45 MIN"),
                            .init(label: L("AVG HR"), value: "136")]))
        case .events:
            return w(type, "TODAY", "Four things happened", hero: "4",
                     .rows([.init(label: L("07:20 BREAKFAST"), value: "375"),
                            .init(label: L("07:30 WALK"), value: "+2.0"),
                            .init(label: L("12:40 LUNCH"), value: "532"),
                            .init(label: L("18:00 SESSION"), value: "+8.9")]))
        case .heat:
            return w(type, "WEEK × HOUR", "Evenings are the load", hero: "18:00",
                     .cells(rows: 7, cols: 12,
                            values: (0..<84).map { ($0 * 7) % 4 }, levels: 4))
        case .food:
            // 07 · 20 · the plate: name, kcal as the hero, three macro rows.
            var f = w(type, "LOGGED · 12:42", "Good pick — 48 g protein still to place",
                      .rows([.init(label: L("CHICKEN SALAD"), value: "420")]))
            f.plate = PlateBlock(name: L("Chicken salad"), portion: L("1 bowl"), kcal: 420,
                                 protein: 32, carb: 18, fat: 22, pctOfBudget: 31)
            f.footer = L("660 KCAL LEFT · KITCHEN CLOSES 21:00")
            // ⚠️ A real food frame always carries one: `screen.render.food` is a draft the
            // screen submits, and turn/index.ts forces its action to 「确认记录」 / CONFIRM.
            // The sample had none, so the catalogue showed a plate that looked finished —
            // which is how the missing confirm (issue #22) stayed invisible in review too.
            f.action = L("CONFIRM")
            return f
        case .plan:
            // ADR 0018 · the plan face's frame: the tasks are rows, the summary is the sentence.
            return w(type, "EASY DAY", "Yesterday was light. Keep it easy, sleep early.",
                     .rows([.init(label: L("BED BY 23:00"), value: ""),
                            .init(label: L("WALK 30 MIN"), value: ""),
                            .init(label: L("PROTEIN AT DINNER"), value: "")]))
        case .meal:
            return w(type, "LUNCH", "532 kcal · 50 g protein", hero: "532",
                     .rows([.init(label: L("CHICKEN"), value: "310"),
                            .init(label: L("RICE"), value: "160"),
                            .init(label: L("GREENS"), value: "62")]))
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
        // ---------------------------------------------------------- 2026-09-06 gap audit
        case .score:
            // The sub-score that dragged the night down is the point of the panel, so the
            // sentence names it and the renderer tints that one bar alert.
            var sc = w(type, "SLEEP SCORE", "Architecture is the drag — 42 min deep", hero: "73",
                       .meter(parts: [("DURATION", 78, 100), ("ARCHITECTURE", 61, 100),
                                      ("RECOVERY", 84, 100), ("REGULARITY", 92, 100)]))
            sc.footer = L("6 BELOW YOUR 7-DAY MEAN")
            return sc
        case .poincare:
            // A cloud along the diagonal with a narrow waist: rest-led, spread 48 ms.
            var pts: [CGPoint] = []
            var seed = 7.0
            for _ in 0..<90 {
                seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
                let a = seed / 233280
                seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
                let b = seed / 233280
                let along = 760 + (a - 0.5) * 220
                let across = (b - 0.5) * 46
                pts.append(CGPoint(x: along - across, y: along + across))
            }
            var po = w(type, "BALANCE CHECK", "Tight cloud, rest side leading", hero: "48 ms",
                       .scatter(points: pts, lo: 600, hi: 900,
                                stats: [("SDNN", "48 ms"), ("LEAD", "REST"), ("REST SHARE", "64 %")]))
            po.footer = L("812 BEATS · 2 MIN 14 S")
            return po
        case .matrix:
            // 0 not collected · 1 unsupported · 2 failed · 3 partial · 4 complete.
            let m: [[Int]] = [[4, 4, 4, 4, 4, 4, 4],
                              [4, 4, 3, 4, 4, 4, 4],
                              [4, 4, 0, 0, 4, 2, 4],
                              [4, 4, 4, 4, 4, 4, 4],
                              [0, 0, 4, 0, 0, 0, 4]]
            var mx = w(type, "SYNC STATUS", "Body comp is the gap — 5 days missing",
                       .matrix(rows: 5, cols: 7, values: m.flatMap { $0 },
                               rowLabels: [L("HEART"), L("SLEEP"), L("SPO2"), L("STEPS"), L("BODY")]))
            mx.footer = L("9 OF 35 CELLS NOT COMPLETE")
            return mx
        case .call:
            var c = w(type, "THE CALL", "Weight flat, lean +0.4 kg, fat −0.5 kg",
                      .verdict(word: "RECOMP", options: ["RECOMP", "CUT", "BULK", "DRIFT", "NO_CHANGE"],
                               confidence: 2, steps: 3))
            c.footer = L("MEDIUM · 4 WEIGH-INS IN 14 DAYS")
            return c
        case .curve:
            // The day's TRAINING LOAD accumulating towards its full value of 21.
            var cv = w(type, "LOAD TODAY", "Two blocks, most of it before noon", hero: "14.2",
                       .series([0, 0.4, 1.2, 2.6, 4.1, 6.8, 9.2, 10.1, 10.3, 10.4, 11.8, 13.6, 14.2]))
            cv.curveMark = 21
            cv.footer = L("Z4+Z5 11 MIN · PEAK 178 BPM")
            return cv
        case .response:
            // Unitless on purpose: the rise over this meal's own baseline. Never a lab unit.
            var rp = w(type, "MEAL RESPONSE", "Peak at 42 min, back down by 14:05", hero: "+38",
                       .series([2, 1, 3, 12, 26, 35, 38, 34, 27, 19, 12, 7, 4, 3, 2]))
            rp.curveMarks = [2, 12]
            rp.footer = L("LUNCH · 115 MIN TO BASELINE")
            return rp
        }
    }

    private static func w(_ type: PanelType, _ title: String, _ sentence: String,
                          hero: String? = nil, _ data: PanelData) -> PanelWidget {
        PanelWidget(type: type, title: L(title), tag: nil, sentence: L(sentence),
                    footer: nil, action: nil, hero: hero, data: data)
    }
}
#endif
