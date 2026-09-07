import SwiftUI

// 07 · AI 屏 MCP 渲染契约.
// The server sends one envelope; the panel is the only thing that renders it.
// Ten renderers cover 27 types. Four fields are required: type, title, sentence, data.

/// 27 types. The type decides the chart and, through the ACCENT MAP, the colour.
enum PanelType: String, Codable, CaseIterable, Hashable {
    case battery, metric, text, line, band, bars, days, sparks, ring, gauge, split
    case cells, hypnogram, zones, wave, table, workout, events, heat, o2night
    case food, meal, fuel, balance, recomp, delta, dual
    /// ADR 0018 · the plan face's own frame: title, summary, three to five tasks.
    case plan
    /// 2026-09-06 gap audit · six shapes the database had data for and the screen did not.
    case score, poincare, matrix, call, curve, response

    /// ⚠️ Ruling reversed on 2026-09-03: the user asked for sleep staging on the screen,
    /// in front of board 07, which draws all three (12 hypnogram · 10 split · 19 o2night).
    /// F0 rule 03 and 1EEU's not-in-V1 list are superseded for these three. The property
    /// stays because the catalogue still groups them; nothing drops them any more.
    var isSleepWidget: Bool {
        switch self {
        case .hypnogram, .split, .o2night: true
        default: false
        }
    }

    /// 09 · B — ten renderers over 27 types.
    var renderer: PanelRenderer {
        switch self {
        case .metric, .text:                        return .number
        case .line, .o2night:                       return .curve
        case .dual:                                 return .dual
        case .band:                                 return .pair
        case .bars, .days, .delta:                  return .column
        case .ring, .gauge, .battery:               return .arc
        case .split, .fuel, .balance:               return .stack
        case .cells, .heat, .recomp:                return .grid
        // 07 · 12 vs 13 · the night is three lanes of run-length blocks; the zones widget is
        // five columns. One renderer drew both as a single stacked bar, which is neither.
        case .hypnogram:                            return .lanes
        case .zones:                                return .columns
        case .wave:                                 return .trace
        case .sparks, .table, .events, .workout, .meal, .food, .plan: return .rows
        // 2026-09-06 · curve and response ride the curve renderer; the marks and the
        // threshold are its own optional slots, not a second renderer.
        case .curve, .response:                     return .curve
        case .score:                                return .meter
        case .poincare:                             return .scatter
        case .matrix:                               return .matrix
        case .call:                                 return .verdict
        }
    }

    /// 05 · ACCENT MAP — colour is the data domain, not decoration.
    var accent: Color {
        switch self {
        case .battery, .days, .cells, .recomp, .plan:       return NB.lime1      // move · steps
        case .fuel, .meal, .food, .balance, .split:         return NB.cyan1      // fuel · protein
        case .hypnogram, .delta, .dual:                     return NB.violet1    // recover · sleep
        case .metric, .ring, .gauge, .line, .bars, .heat, .workout, .events, .table:
                                                            return NB.ember1     // heart · fat
        case .o2night, .band:                               return NB.blue1      // spo2 · carbs
        case .zones, .curve:                                return NB.ember1
        case .score, .poincare:                             return NB.violet1
        case .matrix, .call:                                return NB.lime1
        case .response:                                     return NB.cyan1
        case .wave:                                         return NB.alert2     // warning · rr
        case .sparks, .text:                                return NB.white      // stress · hrv
        }
    }

    /// Slot 3 · which hero layout this type uses.
    var hero: HeroStyle {
        switch self {
        case .metric:               return .large
        case .ring, .gauge, .battery: return .ring
        case .sparks:               return .none
        // ⚠️ Not .large: that slot is sized for a short number ("68 bpm") and a six-letter
        // verdict at 60 pt ran straight through the chart. The word takes the ordinary hero
        // line; the renderer under it shows the set it was chosen from.
        case .text, .food:          return .own
        default:                    return .small
        }
    }

    /// The fallback for frames the app builds itself. A frame off the wire uses the target
    /// the envelope declared — see `PanelWidget.targetOverride`.
    var target: Destination {
        switch self {
        case .battery, .hypnogram, .o2night:                                   return .bodyBattery
        case .food, .meal, .fuel, .balance:                                    return .fuel
        case .recomp, .delta, .dual:                                           return .composition(date: nil)
        case .plan:                                                            return .planFace
        case .score, .poincare, .wave:                                         return .bodyBattery
        case .response:                                                        return .fuel
        case .call:                                                            return .composition(date: nil)
        case .matrix:                                                          return .profile
        default:                                                               return .training
        }
    }
}

enum PanelRenderer: String, Hashable {
    case number, curve, pair, column, arc, stack, grid, strip, trace, rows
    /// score · a total plus the sub-scores that make it, each against its own full value.
    case meter
    /// poincare · the beat-to-beat cloud.
    case scatter
    /// matrix · domain × day, five states in five colours rather than one ramp.
    case matrix
    /// call · one word out of a closed set, with the evidence behind it.
    case verdict
    /// 26 · dual · two series on their own scales, no fill between them.
    case dual
    /// 12 · hypnogram · AWAKE / LIGHT / DEEP lanes, run-length blocks.
    case lanes
    /// 13 · zones · five columns, one per heart-rate zone.
    case columns
}

enum HeroStyle: Hashable { case large, small, ring, own, none }

/// 07 · 04 信封. Fourteen fields, four required. Anything outside the table is dropped, not an error.
struct PanelWidget: Identifiable, Hashable {
    let id = UUID()
    var type: PanelType
    var title: String                 // ≤ 18, upper-cased
    var tag: PanelTag?                // MOVE / FUEL / RECOVER / ALERT — classification only
    var sentence: String              // ≤ 48, two lines max
    var footer: String?               // ≤ 42, segments joined by " · "
    var action: String?               // ≤ 32, upper-cased, takes the accent
    /// 07's table gives some types an explicit `data.hero` rather than deriving one, and
    /// they fall into two groups. `events`, `heat`, `meal` and `workout` have no sensible
    /// first row to take. `fuel` and `balance` do, but their heroes are "biggest gap" and
    /// "in − out" — derivations the stack shape cannot make, because it carries one number
    /// per part and neither the targets nor the sign. When present this wins over the shape.
    var hero: String?
    var accentOverride: Color?
    /// 13 col 01 · where the night ends and the day begins on a curve, and the day's colour.
    var curveSplit: Int?
    var curveSecondary: Color?
    /// 2026-09-06 · the threshold a curve is read against (21 for the day's load), and the
    /// sample indices worth a hairline (a meal's first minute, the minute it settled).
    var curveMark: Double?
    var curveMarks: [Int] = []
    /// F0 rule 06 · where a tap lands, as the envelope declared it.
    ///
    /// ⚠️ The server has always sent this — `contract.ts` marks the field "No target, no
    /// screen" and refuses its own frames without it — and this side threw it away, deriving
    /// the destination from the widget's *type* instead. The type map ends in
    /// `default: .training`, so every shape it does not name landed on training no matter what
    /// the model said. Frames built in the app keep using the type map; anything off the wire
    /// carries its own answer.
    var targetOverride: Destination?
    var data: PanelData
    /// 05 · C·07 · the photo track's answer carries two optional blocks the other tracks do not:
    /// the source chip at the top (the thumbnail and `IMG · PLATE · PARSED OK`) and the
    /// 「已记入今天的 fuel」 line at the bottom. Optional blocks of one template, not a second screen.
    var photo: PhotoAnswer?
    /// 06 · 20 · the body scan's result on the panel, as the board draws it: the settled fat
    /// percent as the hero with the last reading under it, four fields in tiles, the
    /// sentence, then the spine. An optional block of the one template, like `photo`.
    var composition: CompositionAnswer?
    /// 06 · the balance check's own frame: the Poincaré cloud, the two shares and the line
    /// under them. Like `composition`, it owns the whole panel rather than filling slots.
    var balance: BalanceAnswer?
    /// 07 · rule 6 · `text` is the one type with no sentence slot on screen: an eyebrow, one
    /// lime headline — the only highlight on the panel — and a sub. Its own skeleton, like
    /// `photo` and `composition`.
    var headline: HeadlineBlock?
    /// 07 · 20 · `food` is the plate: name, the kcal as the hero, three macro rows.
    var plate: PlateBlock?
    /// 06 · 17 · a measurement's result "becomes a message": tapping it asks her about the
    /// numbers instead of opening a page. Only the frames the band just produced carry this.
    var replyPrompt: String?
    /// 06 · 16 · the measured number is the hero of the frame even on a trace-shaped widget:
    /// top-left like the small hero, but 60 pt, in the accent, with its own line under it.
    var heroLarge = false
    var heroSub: String?
    var ttlMinutes: Int = 20
    var priority: Priority = .normal
    /// When this frame went up. The thinking state counts on it; nothing else looks.
    var startedAt = Date()
    /// Original server payload retained for faithful chat history replay.
    var envelopeData: Data?

    enum Priority: String, Hashable { case normal, alert }

    var accent: Color { accentOverride ?? type.accent }

    static func == (a: PanelWidget, b: PanelWidget) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// The panel while she is working. Not a type — a state of the same surface.
    /// The question is carried in `sentence` so the singularity can echo it; nothing else
    /// reads that slot while the title is THINKING.
    static func thinking(_ question: String = "") -> PanelWidget {
        PanelWidget(type: .text, title: "THINKING", tag: nil,
                    sentence: String(question.prefix(38)),
                    footer: nil, action: nil, data: .none)
    }
    static var thinking: PanelWidget { thinking("") }
}

enum PanelTag: String, Hashable, CaseIterable {
    case move = "MOVE", fuel = "FUEL", recover = "RECOVER", alert = "ALERT"
}

/// The payload shapes behind the ten renderers.
enum PanelData: Hashable {
    case none
    case series([Double])                                     // curve
    case pair(hi: [Double], lo: [Double])                     // pair
    case bins([(String, Double)])                             // column
    case ring(value: Double, goal: Double, unit: String)      // arc
    case gauge(value: Double, zones: [(Double, Double, String)])
    case parts([(String, Double, Color)])                     // stack
    case cells(rows: Int, cols: Int, values: [Int], levels: Int)  // grid
    case strip([(Int, Double)])                               // strip · (level, share)
    /// 12 · (lane, minutes) in order, plus the night's ends.
    case lanes(runs: [(Int, Double)], from: String, to: String)
    /// 13 · five minute counts, Z1…Z5.
    case zones([Double])
    case trace(samples: [Double], hz: Double)                 // trace
    case rows([RowItem])                                      // rows
    /// score · (label, value, full value) per sub-score.
    case meter(parts: [(String, Double, Double)])
    /// poincare · consecutive interval pairs in milliseconds, the box to draw them in, and
    /// the readings that stand beside it. A cloud with no numbers is a shape, not a reading.
    case scatter(points: [CGPoint], lo: Double, hi: Double, stats: [(String, String)])
    /// matrix · domain rows × day columns, one state code per cell.
    case matrix(rows: Int, cols: Int, values: [Int], rowLabels: [String])
    /// call · the verdict, what it was not, and how much evidence stands behind it.
    case verdict(word: String, options: [String], confidence: Int, steps: Int)

    struct RowItem: Hashable {
        var label: String
        var value: String
        var spark: [Double]? = nil
        var tint: Color? = nil
    }

    static func == (a: PanelData, b: PanelData) -> Bool {
        String(describing: a) == String(describing: b)
    }
    func hash(into h: inout Hasher) { h.combine(String(describing: self)) }
}

// MARK: - The renderer

/// 07 · 03 面板解剖. Eight slots at absolute Y inside 358 × 470.
/// Only three things are truly nailed down: the top row at y16, the action at y434,
/// and the 306-wide two-line sentence box at y352.
struct PanelWidgetView: View {
    let widget: PanelWidget
    let onTap: (Destination) -> Void
    /// 07 · the panel is printed through a dot screen. AIPanel draws the widget twice on the
    /// same 358 × 470 canvas: the chart layer *behind* the screen, where a stroke becomes a
    /// trail of LEDs the way board 07 draws every chart, and the text layer in front of it,
    /// crisp. `.all` is the flat rendering the catalogue and the photo / composition
    /// canvases keep.
    var layer: Layer = .all
    /// AIPanel reserves the top-right lane for its dismiss key. Flat catalogue renders do
    /// not show that control, so they keep the board's original full-width tag lane.
    var showsCloseControl = false
    /// Balance results use the full available panel height in board coordinates.
    var canvasHeight: CGFloat = 470
    enum Layer { case all, chart, text }

    private enum Slot {
        static let safeX: CGFloat = 22
        static let topY: CGFloat = 16
        static let heroSmall = CGPoint(x: 24, y: 44)
        static let heroLargeY: CGFloat = 118
        static let heroRing = CGRect(x: 95, y: 146, width: 168, height: 168)
        static let heroRefY: CGFloat = 56
        static let subY: CGFloat = 216
        static let chartY: CGFloat = 96
        static let chartBottom: CGFloat = 336
        static let sentence = CGRect(x: 26, y: 352, width: 306, height: 50)
        static let factsY: CGFloat = 408
        static let actionY: CGFloat = 434
    }

    private var topRowWidth: CGFloat {
        358 - Slot.safeX * 2 - (showsCloseControl ? 42 : 0)
    }

    var body: some View {
        // 06 · 20 · a composition result is the reading. Tapping the numbers must not
        // leave the panel — only TAP FOR ALL 14 FIELDS does that. Other widgets stay
        // one tap to their page (F0 rule 06).
        Group {
            if layer == .chart {
                // The LEDs do not take taps; the text layer above them does.
                canvas.allowsHitTesting(false)
            } else if widget.composition != nil || widget.balance != nil {
                canvas
            } else {
                // ADR-0001 · a hot zone: a touch that travels past the slop is the page drag's,
                // never this tap — the system button let a drag from the panel open the page.
                Button { go() } label: { canvas }
                    .buttonStyle(HotZoneTap(pressedScale: 1))
            }
        }
        .accessibilityLabel("\(L(widget.title)) · \(L(widget.sentence))")
    }

    private func go() { onTap(widget.targetOverride ?? widget.type.target) }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            // Photo answers used to sit on Color.clear, so the idle planet showed
            // through the reading. An opaque unlit plate is the ground; the words
            // sit on it, never on the orbit.
            if widget.photo != nil {
                unlitField
            } else {
                Color.clear
            }

            if let photo = widget.photo {
                photoCanvas(photo)
            } else if let composition = widget.composition {
                compositionCanvas(composition)
            } else if let balance = widget.balance {
                balanceCanvas(balance)
            } else if let h = widget.headline {
                headlineCanvas(h)
            } else if let plate = widget.plate {
                plateCanvas(plate)
            } else {
            if layer != .chart {
            // Slot 1 · title
            Text(L(widget.title).uppercased())
                .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
                .foregroundStyle(widget.accent)
                .offset(x: Slot.safeX, y: Slot.topY)

            // Slot 2 · tag — never takes the accent
            if let tag = widget.tag {
                Text(L(tag.rawValue))
                    .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                    .foregroundStyle(NB.white.opacity(0.30))
                    .frame(width: topRowWidth, alignment: .trailing)
                    .offset(x: Slot.safeX, y: Slot.topY)
            }

            hero
            }
            chart

            if layer != .chart {
            // Slot 6 · sentence — the brightest text on the screen
            Text(L(widget.sentence))
                .font(NBFont.brand(500, 18))
                .lineSpacing(7)
                .multilineTextAlignment(.center)
                .foregroundStyle(NB.white)
                .frame(width: Slot.sentence.width, alignment: .center)
                .offset(x: Slot.sentence.minX, y: Slot.sentence.minY)

            // Slot 7 · facts
            if let footer = widget.footer {
                Text(footer)
                    .font(NBFont.brand(400, 11.5))
                    .foregroundStyle(NB.white.opacity(0.50))
                    .frame(width: 358, alignment: .center)
                    .offset(y: Slot.factsY)
            }

            // Slot 8 · action
            if let action = widget.action {
                Text(L(action).uppercased())
                    .font(NBFont.dot(500, 10.5)).tracking(0.16 * 10.5)
                    .foregroundStyle(widget.accent)
                    .frame(width: 358, alignment: .center)
                    .offset(y: Slot.actionY)
            }
            }

            }

            // ALERT is the fourth and last layer of the stack; nothing draws above it.
            if widget.priority == .alert {
                Color(hex: 0xEF4444, opacity: 0.12).allowsHitTesting(false)
            }
        }
        .frame(width: 358, height: canvasHeight, alignment: .topLeading)
    }

    // MARK: 07 · rule 6 · TEXT — the one big word

    /// eyebrow y128 · headline y168 (Doto 800 · 44, lime, the only highlight) · sub y232,
    /// then the facts line at y352, the action at y380 and a dim footnote at y434.
    /// ⚠️ No sentence slot: `sentence` is drawn as the facts line, which is where the
    /// board puts the words on this type.
    @ViewBuilder private func headlineCanvas(_ h: HeadlineBlock) -> some View {
        if layer != .chart {
            Text(L(widget.title).uppercased())
                .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
                .foregroundStyle(widget.accent)
                .offset(x: Slot.safeX, y: Slot.topY)
            if let tag = widget.tag {
                Text(L(tag.rawValue))
                    .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                    .foregroundStyle(NB.white.opacity(0.30))
                    .frame(width: topRowWidth, alignment: .trailing)
                    .offset(x: Slot.safeX, y: Slot.topY)
            }
            if let eyebrow = h.eyebrow {
                Text(eyebrow.uppercased())
                    .font(NBFont.dot(500, 11)).tracking(0.16 * 11)
                    .foregroundStyle(NB.white.opacity(0.45))
                    .frame(width: 358, alignment: .center)
                    .offset(y: 128)
            }
            Text(h.headline.uppercased())
                .font(NBFont.dot(800, 44)).tracking(0.02 * 44)
                .foregroundStyle(NB.lime1)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 358 - Slot.safeX * 2, alignment: .center)
                .offset(x: Slot.safeX, y: 168)
            if let sub = h.sub {
                Text(sub.uppercased())
                    .font(NBFont.dot(500, 11)).tracking(0.16 * 11)
                    .foregroundStyle(NB.white.opacity(0.55))
                    .frame(width: 358, alignment: .center)
                    .offset(y: 232)
            }
            Text(L(widget.sentence))
                .font(NBFont.brand(400, 13))
                .foregroundStyle(NB.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(width: Slot.sentence.width, alignment: .center)
                .offset(x: Slot.sentence.minX, y: 352)
            if let action = widget.action {
                Text(L(action).uppercased())
                    .font(NBFont.dot(500, 10.5)).tracking(0.16 * 10.5)
                    .foregroundStyle(widget.accent)
                    .frame(width: 358, alignment: .center)
                    .offset(y: 388)
            }
            if let footer = widget.footer {
                Text(footer.uppercased())
                    .font(NBFont.dot(500, 9.5)).tracking(0.14 * 9.5)
                    .foregroundStyle(NB.white.opacity(0.32))
                    .frame(width: 358, alignment: .center)
                    .offset(y: Slot.actionY)
            }
        }
    }

    // MARK: 07 · 20 · FOOD — one plate

    /// name y118 (32) · kcal y168 (64, the hero) · the budget line y246 · three macro rows
    /// from y300 with their own bars · sentence y352 · footer y434.
    @ViewBuilder private func plateCanvas(_ plate: PlateBlock) -> some View {
        let macros: [(String, Double?, Color)] = [
            ("PROTEIN", plate.protein, NB.cyan1),
            ("CARBS", plate.carb, NB.blue1),
            ("FAT", plate.fat, NB.run1),
        ]
        let present = macros.filter { $0.1 != nil && $0.1! > 0 }
        let mx = max(present.compactMap { $0.1 }.max() ?? 1, 1)
        if layer != .chart {
            Text(L(widget.title).uppercased())
                .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
                .foregroundStyle(widget.accent)
                .offset(x: Slot.safeX, y: Slot.topY)
            Text((plate.portion ?? widget.tag?.rawValue ?? "").uppercased())
                .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                .foregroundStyle(NB.white.opacity(0.30))
                .frame(width: topRowWidth, alignment: .trailing)
                .offset(x: Slot.safeX, y: Slot.topY)
            Text(plate.name)
                .font(NBFont.brand(700, 30)).tracking(-0.02 * 30)
                .foregroundStyle(NB.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 358 - Slot.safeX * 2, alignment: .center)
                .offset(x: Slot.safeX, y: 104)
            // ⚠️ No kcal unless a tool returned one: S3, and 07's own rule that an absent
            // number is a long dash rather than a guess.
            Text(plate.kcal.map { "\(Int($0)) kcal" } ?? Fmt.dash)
                .font(NBFont.brand(700, 62)).tracking(-0.045 * 62)
                .foregroundStyle(NB.white.opacity(0.45))
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 358 - Slot.safeX * 2, alignment: .center)
                .offset(x: Slot.safeX, y: 150)
            if let pct = plate.pctOfBudget {
                Text(L("%d%% OF TODAY'S BUDGET", pct))
                    .font(NBFont.dot(500, 10.5)).tracking(0.16 * 10.5)
                    .foregroundStyle(NB.white.opacity(0.42))
                    .frame(width: 358, alignment: .center)
                    .offset(y: 228)
            }
            ForEach(present.indices, id: \.self) { i in
                let row = present[i]
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 0) {
                        Text(L(row.0))
                            .font(NBFont.dot(600, 10)).tracking(0.14 * 10)
                            .foregroundStyle(row.2)
                        Spacer(minLength: 0)
                        Text("\(Int(row.1!)) g")
                            .font(NBFont.dot(600, 10.5))
                            .foregroundStyle(NB.white.opacity(0.60))
                    }
                    ZStack(alignment: .leading) {
                        Capsule().fill(NB.barTrack).frame(height: 5)
                        Capsule().fill(row.2)
                            .frame(width: (358 - Slot.safeX * 2) * CGFloat(row.1! / mx), height: 5)
                    }
                }
                .frame(width: 358 - Slot.safeX * 2)
                .offset(x: Slot.safeX, y: 262 + CGFloat(i) * 44)
            }
            Text(L(widget.sentence))
                .font(NBFont.brand(500, 16)).lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(NB.white)
                .frame(width: Slot.sentence.width, alignment: .center)
                .offset(x: Slot.sentence.minX, y: 396)
            if let footer = widget.footer {
                Text(footer.uppercased())
                    .font(NBFont.dot(500, 9.5)).tracking(0.14 * 9.5)
                    .foregroundStyle(NB.white.opacity(0.34))
                    .frame(width: 358, alignment: .center)
                    .offset(y: Slot.actionY)
            }
        }
    }

    // MARK: 06 · 20 · BODY COMPOSITION · JUST NOW

    /// The board's frame to the pixel: 358 × 470, its own LED ground (a reading is not drawn
    /// over the standby art), the lime hairline that marks a frame the band just produced,
    /// header at y16, hero at y70, the four tiles at y206, the sentence at y300, the spine at y378.
    /// 06 · THE BALANCE FRAME. A Poincaré plot of the beat-to-beat intervals, the two shares
    /// under it, and one sentence.
    ///
    /// ⚠️ Every dot is a pair of consecutive intervals the band measured. The diagonal is the
    /// line where a beat lasts exactly as long as the one before it, so the cloud's width
    /// ACROSS it is beat-to-beat change and its length ALONG it is the slow drift — which is
    /// exactly what the two bars below are the ratio of. Nothing is smoothed, nothing is
    /// fitted; a short run simply makes a small cloud.
    @ViewBuilder private func balanceCanvas(_ b: BalanceAnswer) -> some View {
        // AIPanel owns the edge-to-edge LED surface. Only standalone catalogue
        // renders need a local ground; a second plate leaves seams on tall panels.
        if !showsCloseControl {
            unlitField
        }

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L(widget.title).uppercased())
                    .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
                    .foregroundStyle(NB.lime1)
                Spacer(minLength: 0)
                Text(L("JUST NOW"))
                    .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                    .foregroundStyle(NB.white.opacity(0.30))
                    // The panel's own close mark sits in this corner, drawn over the widget
                    // by AIPanel — without the gap the two overlap and both read as broken.
                    .padding(.trailing, 30)
            }

            Text(b.headline)
                .font(NBFont.brand(500, 21)).tracking(-0.01 * 21)
                .foregroundStyle(NB.text1)
                .padding(.top, 14)

            PoincarePlot(points: b.points, accent: NB.lime1)
                .frame(width: 214, height: 214)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)

            // The two shares, as one split bar. Rest takes the accent; drive takes the
            // amber the rest of the product uses for "something is being asked of you".
            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Rectangle().fill(NB.lime1)
                            .frame(width: max(2, geo.size.width * b.restShare))
                        Rectangle().fill(NB.ember1.opacity(0.85))
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 10)

                HStack(spacing: 0) {
                    Text(L("REST %d%%", Int(b.restShare * 100)))
                        .font(NBFont.dot(600, 10.5)).tracking(0.16 * 10.5)
                        .foregroundStyle(NB.lime1)
                    Spacer(minLength: 0)
                    Text(L("DRIVE %d%%", 100 - Int(b.restShare * 100)))
                        .font(NBFont.dot(600, 10.5)).tracking(0.16 * 10.5)
                        .foregroundStyle(NB.ember1.opacity(0.9))
                }
            }
            .padding(.top, 16)

            Text(b.note)
                .font(NBFont.ui(300, 13)).tracking(0.01 * 13)
                .lineSpacing(20 - 13)
                .foregroundStyle(NB.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Spacer(minLength: 0)

            Text(b.footer)
                .font(NBFont.dot(500, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.white.opacity(0.34))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 358, height: canvasHeight, alignment: .topLeading)
    }

    /// Opaque unlit LED plate. Photo answers used to sit on `Color.clear`, so the
    /// idle planet showed through the reading. Same ground composition paints for itself.
    private var unlitField: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NB.R.hero, style: .continuous).fill(NB.panelInk)
            Canvas { ctx, size in
                var grid = Path()
                var y: CGFloat = 1.4
                while y < size.height {
                    var x: CGFloat = 1.4
                    while x < size.width {
                        grid.addRoundedRect(in: CGRect(x: x, y: y, width: 3.2, height: 3.2),
                                            cornerSize: CGSize(width: 0.8, height: 0.8))
                        x += 4
                    }
                    y += 4
                }
                ctx.fill(grid, with: .color(Color(hex: 0x131318)))
            }
            .clipShape(RoundedRectangle(cornerRadius: NB.R.hero, style: .continuous))
        }
        .frame(width: 358, height: 470)
        .allowsHitTesting(false)
    }

    @ViewBuilder private func compositionCanvas(_ c: CompositionAnswer) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: NB.R.hero, style: .continuous).fill(NB.panelInk)
            Canvas { ctx, size in
                var grid = Path()
                var y: CGFloat = 1.4
                while y < size.height {
                    var x: CGFloat = 1.4
                    while x < size.width {
                        grid.addRoundedRect(in: CGRect(x: x, y: y, width: 3.2, height: 3.2),
                                            cornerSize: CGSize(width: 0.8, height: 0.8))
                        x += 4
                    }
                    y += 4
                }
                ctx.fill(grid, with: .color(Color(hex: 0x131318)))
            }
            .clipShape(RoundedRectangle(cornerRadius: NB.R.hero, style: .continuous))
        }
        .frame(width: 358, height: 470)

        // header · the title in the accent, JUST NOW where the tag sits
        HStack {
            Text(L(widget.title).uppercased())
                .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
                .foregroundStyle(NB.lime1)
            Spacer(minLength: 0)
            Text(L("JUST NOW"))
                .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                .foregroundStyle(NB.white.opacity(0.30))
        }
        .frame(width: 318 - (showsCloseControl ? 42 : 0), height: 14)
        .offset(x: 20, y: 16)

        // hero · the number the scan settled, and where it stood last time
        VStack(spacing: 10) {
            Text(widget.hero ?? Fmt.dash)
                .font(NBFont.brand(700, 66)).tracking(-0.045 * 66)
                .foregroundStyle(NB.lime1)
            Text(L(c.heroSub).uppercased())
                .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                .foregroundStyle(NB.white.opacity(0.39))
        }
        .frame(width: 318, height: 89)
        .offset(x: 20, y: 70)

        // four fields · label in the field's own colour, value in white
        HStack(spacing: 8) {
            ForEach(c.fields, id: \.label) { f in
                VStack(spacing: 5) {
                    Text(f.label)
                        .font(NBFont.dot(600, 9)).tracking(0.16 * 9)
                        .foregroundStyle(f.tint)
                    Text(f.value)
                        .font(NBFont.brand(600, 18)).tracking(-0.02 * 18)
                        .foregroundStyle(NB.white)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 59)
                .background(NB.carbon5, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(width: 318, height: 59)
        .offset(x: 20, y: 206)

        // the sentence · the brightest text on the screen
        Text(L(widget.sentence))
            .font(NBFont.brand(500, 19)).tracking(-0.01 * 19)
            .lineSpacing(7)
            .multilineTextAlignment(.center)
            .foregroundStyle(NB.white)
            .frame(width: 294, height: 52, alignment: .center)
            .offset(x: 32, y: 300)

        // the spine · hairline, the facts, the one tap
        VStack(spacing: 14) {
            Rectangle().fill(NB.hairline).frame(width: 318, height: 1)
            if let footer = widget.footer {
                Text(footer)
                    .font(NBFont.brand(400, 11.5)).tracking(0.02 * 11.5)
                    .foregroundStyle(NB.white.opacity(0.50))
            }
            if let action = widget.action {
                Button(action: go) {
                    Text(L(action).uppercased())
                        .font(NBFont.dot(600, 10.5)).tracking(0.16 * 10.5)
                        .foregroundStyle(NB.lime1.opacity(0.85))
                        .frame(width: 318, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HotZoneTap(pressedScale: 1))
            }
        }
        .frame(width: 318)
        .offset(x: 20, y: 378)
    }

    // MARK: 05 · C·07 · FROM YOUR PHOTO

    /// The same 358 × 470 canvas as A·08 / B·07, plus the source chip and the logged line.
    @ViewBuilder private func photoCanvas(_ photo: PhotoAnswer) -> some View {
        Text(L("FROM YOUR PHOTO"))
            .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
            .foregroundStyle(NB.white.opacity(0.70))
            .offset(x: Slot.safeX, y: Slot.topY)
        Text(L("PHOTO + TEXT"))
            .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
            .foregroundStyle(NB.white.opacity(0.40))
            .frame(width: topRowWidth, alignment: .trailing)
            .offset(x: Slot.safeX, y: Slot.topY)
        // the source chip · 310 × 42 at y44
        HStack(spacing: 12) {
            Group {
                if let t = photo.thumbnail {
                    Image(uiImage: t).resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x2A2A32))
                }
            }
            .frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 4))
            Text(photo.chip)
                .font(NBFont.dot(600, 10.5)).tracking(0.14 * 10.5)
                .foregroundStyle(NB.white.opacity(0.55))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 310, height: 42)
        .background(Color(hex: 0x101014), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NB.white.opacity(0.13), lineWidth: 1.5))
        .offset(x: 24, y: 44)
        // the caption, said back
        Text("\"\(photo.quote.uppercased())\"")
            .font(NBFont.dot(500, 11)).tracking(0.16 * 11)
            .foregroundStyle(NB.white.opacity(0.55))
            .frame(width: 358, alignment: .center)
            .offset(y: 118)
        Text(L(widget.sentence))
            .font(NBFont.brand(500, 22)).lineSpacing(9)
            .multilineTextAlignment(.center)
            .foregroundStyle(NB.white)
            .frame(width: 286, alignment: .center)
            .offset(x: 36, y: 174)
        if let footer = widget.footer {
            Text(footer.uppercased())
                .font(NBFont.dot(700, 13)).tracking(0.18 * 13)
                .foregroundStyle(NB.lime1)
                .frame(width: 358, alignment: .center)
                .offset(y: 246)
        }
        // two pills at y318 · the plate is already logged; the second opens fuel
        HStack(spacing: 14) {
            Text(L("LOG THE PLATE"))
                .font(NBFont.dot(600, 10)).tracking(0.14 * 10)
                .foregroundStyle(NB.lime1)
                .frame(width: 120, height: 40)
                .overlay(Capsule().stroke(NB.lime1.opacity(0.6), lineWidth: 2.5))
            Text(L("SHOW FUEL"))
                .font(NBFont.dot(600, 10)).tracking(0.14 * 10)
                .foregroundStyle(NB.white.opacity(0.55))
                .frame(width: 120, height: 40)
                .overlay(Capsule().stroke(NB.white.opacity(0.30), lineWidth: 2))
        }
        .frame(width: 358)
        .offset(y: 318)
        Rectangle().fill(Color(hex: 0x24242C)).frame(width: 310, height: 2).offset(x: 24, y: 381)
        Text(photo.pulled)
            .font(NBFont.brand(400, 11.5))
            .foregroundStyle(NB.white.opacity(0.50))
            .frame(width: 358, alignment: .center)
            .offset(y: 398)
        Text(photo.logged)
            .font(NBFont.dot(500, 10)).tracking(0.16 * 10)
            .foregroundStyle(NB.white.opacity(0.35))
            .frame(width: 358, alignment: .center)
            .offset(y: 428)
    }

    // MARK: hero

    @ViewBuilder private var hero: some View {
        switch widget.type.hero {
        case .large:
            Text(heroValue)
                .font(NBFont.brand(700, 84)).tracking(-0.045 * 84)
                .foregroundStyle(NB.white.opacity(0.45))
                .frame(width: 358, alignment: .center)
                .lineLimit(1).minimumScaleFactor(0.5)
                .offset(y: Slot.heroLargeY)

            // 01 · metric · the reference line under the giant number, in Doto.
            if let ref = widget.heroSub {
                Text(ref.uppercased())
                    .font(NBFont.dot(500, 10.5)).tracking(0.20 * 10.5)
                    .foregroundStyle(NB.white.opacity(0.42))
                    .frame(width: 358, alignment: .center)
                    .offset(y: Slot.subY)
            }

            if let sub = subText {
                Text(sub)
                    .font(NBFont.dot(500, 10.5)).tracking(0.20 * 10.5)
                    .foregroundStyle(NB.white.opacity(0.42))
                    .frame(width: 358, alignment: .center)
                    .offset(y: Slot.subY)
            }

        case .small:
            let size: CGFloat = widget.heroLarge ? 60 : 44
            Text(heroValue)
                .font(NBFont.brand(700, size)).tracking(-0.045 * size)
                .foregroundStyle(widget.heroLarge ? widget.accent : NB.white.opacity(0.45))
                .offset(x: Slot.heroSmall.x, y: Slot.heroSmall.y)
            if widget.heroLarge, let sub = widget.heroSub {
                Text(sub.uppercased())
                    .font(NBFont.dot(500, 10.5)).tracking(0.20 * 10.5)
                    .foregroundStyle(NB.white.opacity(0.42))
                    .offset(x: Slot.heroSmall.x + 2, y: Slot.heroSmall.y + size + 14)
            }

            if let ref = heroRef {
                Text(ref)
                    .font(NBFont.dot(600, 10.5)).tracking(0.14 * 10.5)
                    .foregroundStyle(widget.accent)
                    .frame(width: 358 - Slot.safeX * 2, alignment: .trailing)
                    .offset(x: Slot.safeX, y: Slot.heroRefY)
            }

        case .ring:
            // The number inside the ring is text: on the printed panel it sits in front of
            // the dot screen while the arc sits behind it, so the text layer draws it and the
            // renderer keeps quiet. The flat rendering leaves it to the renderer, as before.
            if layer == .text {
                Text(arcLabel)
                    .font(NBFont.brand(700, 44)).tracking(-0.045 * 44)
                    .foregroundStyle(NB.white.opacity(0.45))
                    .frame(width: Slot.heroRing.width, height: Slot.heroRing.height)
                    .offset(x: Slot.heroRing.minX, y: Slot.heroRing.minY)
                // 08 · under the ring: the value, then what it is out of.
                if case .ring(let v, let g, let u) = widget.data, g > 0 {
                    VStack(spacing: 2) {
                        Text(Fmt.kg(v, decimals: 0))
                            .font(NBFont.dot(600, 12)).tracking(0.08 * 12)
                            .foregroundStyle(NB.white.opacity(0.55))
                        Text(L("OF %@%@", Fmt.kg(g, decimals: 0), u))
                            .font(NBFont.dot(500, 10)).tracking(0.16 * 10)
                            .foregroundStyle(NB.white.opacity(0.34))
                    }
                    .frame(width: 358, alignment: .center)
                    .offset(y: Slot.heroRing.maxY - 34)
                }
            }
        case .own, .none:
            EmptyView()
        }
    }

    /// 08 · a ring's centre is the percentage; a gauge's and the battery's is the reading.
    private var arcLabel: String {
        switch widget.data {
        case .ring(let v, let g, _) where widget.type == .ring && g > 0:
            return "\(Int((v / g * 100).rounded()))%"
        case .ring(let v, _, let u):
            return u == "%" ? "\(Fmt.kg(v, decimals: 0))%" : Fmt.kg(v, decimals: 0)
        case .gauge(let v, _):   return Fmt.kg(v, decimals: 0)
        default:                 return ""
        }
    }

    private var heroValue: String {
        if let hero = widget.hero, !hero.isEmpty { return hero }
        switch widget.data {
        // 09 · o2night's HERO is the night's average with a percent, not its last point.
        case .series(let s) where widget.type == .o2night:
            guard !s.isEmpty else { return Fmt.dash }
            return "\(Int((s.reduce(0, +) / Double(s.count)).rounded()))%"
        case .series(let s):                      return s.last.map { Fmt.kg($0) } ?? Fmt.dash
        case .ring(let v, let g, let u):          return u.isEmpty ? "\(Int(v))/\(Int(g))" : "\(Int(v))\(u)"
        case .gauge(let v, _):                    return Fmt.kg(v)
        // 09 · HERO by type: bars is the total, days is the average of the days, delta is
        // the signed net. One shape, three different questions.
        case .bins(let b) where widget.type == .days:
            let vals = b.map { $0.1 }
            return vals.isEmpty ? Fmt.dash : "\(Fmt.kg(vals.reduce(0, +) / Double(vals.count), decimals: 1)) AVG"
        case .bins(let b) where widget.type == .delta:
            let net = b.reduce(0) { $0 + $1.1 }
            return "\(net > 0 ? "+" : "")\(Fmt.kg(net, decimals: 1))"
        case .bins(let b):                        return Fmt.kcal(b.reduce(0) { $0 + $1.1 })
        case .parts(let p):                       return p.first.map { Fmt.kcal($0.1) } ?? Fmt.dash
        // 09 · cells' HERO is "filled of total".
        case .cells(_, _, let v, _):              return "\(v.filter { $0 > 0 }.count) OF \(v.count)"
        case .rows(let r):                        return r.first?.value ?? Fmt.dash
        // 09 · band's HERO is the day's hi/lo pair; dual's is series a's last point.
        case .pair(let hi, let lo) where widget.type == .band:
            // 04 · the board writes the pair high first — "118/76", systolic over diastolic.
            guard let h = hi.last, let l = lo.last else { return Fmt.dash }
            return "\(Fmt.kg(h, decimals: 0))/\(Fmt.kg(l, decimals: 0))"
        case .pair(let hi, _):                    return hi.last.map { Fmt.kg($0) } ?? Fmt.dash
        // 09 · wave's HERO was the strip's average heart rate. 2026-09-06 · the trace it
        // actually gets is the RR tachogram, whose samples are milliseconds — averaging them
        // and printing BPM would have put a plainly wrong number on the panel.
        case .trace(let s, _):
            return s.isEmpty ? Fmt.dash
                : "\(Int((s.reduce(0, +) / Double(s.count)).rounded())) MS AVG"
        case .strip(let s):                       return "\(s.count)"
        case .lanes(let runs, _, _):
            let total = runs.reduce(0) { $0 + $1.1 }
            return "\(Int(total) / 60)H\(String(format: "%02d", Int(total) % 60))"
        case .zones(let z):
            // 09 · zones' HERO is `current_zone`, which the board writes as "Z4 · 26 min".
            guard let top = z.indices.max(by: { z[$0] < z[$1] }), z[top] > 0 else { return Fmt.dash }
            return "Z\(top + 1) · \(Int(z[top])) MIN"
        // 2026-09-06 · score is the total, call is the verdict word itself, matrix counts the
        // cells that are not complete, poincare has no scalar of its own — the server's hero
        // (SDNN) is the only honest one, so an absent hero stays absent.
        case .meter(let parts):
            return parts.isEmpty ? Fmt.dash : Fmt.kg(parts.map(\.1).reduce(0, +) / Double(parts.count), decimals: 0)
        case .verdict(let word, _, _, _):         return word
        case .matrix(_, _, let v, _):             return "\(v.filter { $0 != 4 }.count) OF \(v.count)"
        case .scatter(let pts, _, _, let stats):
            // The reading is SDNN, not the number of dots; the server names it.
            return stats.first?.1 ?? (pts.isEmpty ? Fmt.dash : "\(pts.count)")
        case .none:                               return ""
        }
    }

    private var heroRef: String? {
        if case .ring(_, let goal, let unit) = widget.data { return "OF \(Int(goal))\(unit)" }
        return nil
    }

    private var subText: String? {
        if case .ring(_, let g, let u) = widget.data { return "OF \(Int(g))\(u)" }
        return nil
    }

    // MARK: chart

    @ViewBuilder private var chart: some View {
        let h = Slot.chartBottom - Slot.chartY
        // Which layer each renderer belongs to. Shapes (curves, bars, arcs, cells, strips,
        // traces) are LEDs and go behind the screen; rows, stacks and axis labels are text
        // and stay in front of it. The flat rendering draws everything at once.
        let led = layer == .chart
        let shapes = layer != .text
        let text = layer != .chart
        Group {
            switch widget.type.renderer {
            case .number:
                EmptyView()
            case .curve:
                if shapes, case .series(let s) = widget.data {
                    CurveRenderer(values: s, accent: widget.accent,
                                  splitAt: widget.curveSplit, accent2: widget.curveSecondary, led: led,
                                  mark: widget.curveMark, marks: widget.curveMarks).frame(height: h)
                }
            case .pair:
                if shapes, case .pair(let hi, let lo) = widget.data {
                    PairRenderer(hi: hi, lo: lo, accent: widget.accent, led: led).frame(height: h)
                }
            case .dual:
                // ⚠️ The catalogue drew dual through the curve renderer, which eats one
                // series — the second line never existed. Two scales, one panel.
                if shapes, case .pair(let a, let b) = widget.data {
                    DualRenderer(a: a, b: b, accent: widget.accent,
                                 secondary: widget.curveSecondary ?? NB.white.opacity(0.45), led: led).frame(height: h)
                }
            case .column:
                if case .bins(let b) = widget.data {
                    // 09 · B · delta 用带零轴的变体.
                    ColumnRenderer(bins: b, accent: widget.accent, zeroAxis: widget.type == .delta,
                                   showBars: shapes, showLabels: text).frame(height: h)
                }
            case .arc:
                if shapes, case .ring(let v, let g, _) = widget.data {
                    ArcRenderer(fraction: g > 0 ? v / g : 0, accent: widget.accent, label: Fmt.kg(v, decimals: 0),
                                showLabel: layer == .all)
                        .frame(width: Slot.heroRing.width, height: Slot.heroRing.height)
                } else if shapes, case .gauge(let v, let z) = widget.data {
                    GaugeRenderer(value: v, zones: z, accent: widget.accent, showLabel: layer == .all)
                        .frame(width: Slot.heroRing.width, height: Slot.heroRing.height)
                }
            case .stack:
                if text, case .parts(let p) = widget.data {
                    StackRenderer(parts: p, minutes: widget.type == .split).frame(height: h)
                }
            case .grid:
                if shapes, case .cells(let r, let c, let v, let l) = widget.data {
                    GridRenderer(rows: r, cols: c, values: v, levels: l, accent: widget.accent).frame(height: h)
                }
            case .strip:
                if shapes, case .strip(let s) = widget.data {
                    StripRenderer(segments: s).frame(height: h)
                }
            case .lanes:
                // 12 · the lanes are LEDs; their names and the two clock labels are text.
                if case .lanes(let runs, let from, let to) = widget.data {
                    LaneRenderer(runs: runs, from: from, to: to,
                                 showBlocks: shapes, showLabels: text).frame(height: h)
                }
            case .columns:
                if case .zones(let z) = widget.data {
                    ZoneColumnsRenderer(minutes: z, showBars: shapes, showLabels: text).frame(height: h)
                }
            case .trace:
                if shapes, case .trace(let s, let hz) = widget.data {
                    TraceRenderer(samples: s, hz: hz, accent: widget.accent, led: led).frame(height: h)
                }
            case .rows:
                if text, case .rows(let r) = widget.data {
                    RowsRenderer(items: r, accent: widget.accent).frame(height: h)
                }
            // 2026-09-06 · bars and cells are LEDs and go behind the screen; the labels,
            // the verdict chips and the domain names are text and stay in front of it.
            case .meter:
                if case .meter(let parts) = widget.data {
                    MeterRenderer(parts: parts, accent: widget.accent,
                                  showBars: shapes, showLabels: text).frame(height: h)
                }
            case .scatter:
                if case .scatter(let pts, let lo, let hi, let stats) = widget.data {
                    ScatterRenderer(points: pts, lo: lo, hi: hi, stats: stats, accent: widget.accent,
                                    showCloud: shapes, showLabels: text).frame(height: h)
                }
            case .matrix:
                if case .matrix(let r, let c, let v, let labels) = widget.data {
                    MatrixRenderer(rows: r, cols: c, values: v, rowLabels: labels,
                                   showCells: shapes, showLabels: text).frame(height: h)
                }
            case .verdict:
                if case .verdict(let w, let o, let conf, let steps) = widget.data {
                    VerdictRenderer(word: w, options: o, confidence: conf, steps: steps,
                                    accent: widget.accent, showBars: shapes, showLabels: text).frame(height: h)
                }
            }
        }
        .frame(width: widget.type.renderer == .arc ? Slot.heroRing.width : 358 - Slot.safeX * 2)
        .offset(x: widget.type.renderer == .arc ? Slot.heroRing.minX : Slot.safeX,
                y: widget.type.renderer == .arc ? Slot.heroRing.minY : Slot.chartY)
    }
}


/// 07 · rule 6 · text's own three lines.
struct HeadlineBlock: Hashable {
    var eyebrow: String?
    var headline: String       // ≤ 12
    var sub: String?
}

/// 07 · 20 · the plate, as the board lays it out.
struct PlateBlock: Hashable {
    var name: String
    var portion: String?
    var kcal: Double?
    var protein: Double?
    var carb: Double?
    var fat: Double?
    var pctOfBudget: Int?
}

/// 05 · C·07 · what the photo answer adds to the panel.
/// 06 · 20 · what the body scan's frame carries beyond the template: the line under the hero
/// and the four tiles. Everything in it came off the band or out of the store — never a
/// placeholder (a printed 34.2 no band produced is a number the user will believe).
/// 06 · what the balance check puts on the panel. Everything here was computed from the
/// interval series the band reported — see `AutonomicBalance`.
struct BalanceAnswer: Hashable {
    var headline: String
    var note: String
    /// 0…1 · the beat-to-beat half's share of the cloud.
    var restShare: Double
    var footer: String
    /// Consecutive interval pairs in milliseconds, already paired: (this beat, the next).
    var points: [CGPoint]
}

/// The plot itself. Axes are not labelled with numbers on purpose — the shape and the spread
/// are the reading, and a millisecond grid on a 214 pt square invites measuring off the screen.
struct PoincarePlot: View {
    var points: [CGPoint]
    var accent: Color

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            // The frame, in the panel's own hairline.
            let frame = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10)
            ctx.stroke(frame, with: .color(NB.white.opacity(0.10)), lineWidth: 1)

            guard points.count > 1 else {
                ctx.draw(Text(L("NOT ENOUGH BEATS"))
                    .font(NBFont.dot(500, 9.5))
                    .foregroundStyle(NB.white.opacity(0.30)),
                         at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }

            // One square window around the cloud, padded, so the diagonal stays at 45° —
            // scaling the two axes independently would stretch the ellipse and turn the
            // ratio the bars report into something the picture disagrees with.
            let xs = points.map(\.x), ys = points.map(\.y)
            let lo = min(xs.min()!, ys.min()!), hi = max(xs.max()!, ys.max()!)
            let pad = max(20, (hi - lo) * 0.18)
            let a = lo - pad, b = hi + pad
            let span = max(1, b - a)
            func place(_ p: CGPoint) -> CGPoint {
                CGPoint(x: (p.x - a) / span * size.width,
                        // y up: a longer next-interval sits higher, the way the plot is read.
                        y: size.height - (p.y - a) / span * size.height)
            }

            // The identity line. Every dot on it is a beat that lasted exactly as long as
            // the one before it; the cloud's width across it is the reading.
            var diagonal = Path()
            diagonal.move(to: place(CGPoint(x: a, y: a)))
            diagonal.addLine(to: place(CGPoint(x: b, y: b)))
            ctx.stroke(diagonal, with: .color(NB.white.opacity(0.16)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

            var dots = Path()
            for p in points {
                let q = place(p)
                dots.addEllipse(in: CGRect(x: q.x - 2.2, y: q.y - 2.2, width: 4.4, height: 4.4))
            }
            ctx.fill(dots, with: .color(accent.opacity(0.9)))
        }
    }
}

struct CompositionAnswer: Hashable {
    struct Field: Hashable {
        var label: String
        var value: String
        var tint: Color
    }
    var heroSub: String       // BODY FAT · 22.1% IN JUNE
    var fields: [Field]       // MUSCLE · WATER · PROTEIN · BMR
}

struct PhotoAnswer: Hashable {
    var thumbnail: UIImage?
    var chip: String            // IMG · PLATE · PARSED OK
    var quote: String           // the caption, said back in Doto
    var pulled: String          // Pulled from photo — PRO 84/145 g · 61 g still to place
    var logged: String          // LOGGED TO TODAY'S FUEL
    static func == (a: PhotoAnswer, b: PhotoAnswer) -> Bool { a.chip == b.chip && a.quote == b.quote && a.pulled == b.pulled }
    func hash(into h: inout Hasher) { h.combine(chip); h.combine(quote) }
}
