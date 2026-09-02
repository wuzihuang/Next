import SwiftUI

// 07 · AI 屏 MCP 渲染契约.
// The server sends one envelope; the panel is the only thing that renders it.
// Ten renderers cover 27 types. Four fields are required: type, title, sentence, data.

/// 27 types. The type decides the chart and, through the ACCENT MAP, the colour.
enum PanelType: String, Codable, CaseIterable, Hashable {
    case battery, metric, text, line, band, bars, days, sparks, ring, gauge, split
    case cells, hypnogram, zones, wave, table, workout, events, heat, o2night
    case food, meal, fuel, balance, recomp, delta, dual

    /// ⚠️ 1EEU · the three sleep widgets are not in V1, and F0 rule 03 is the reason: the
    /// night only ever reaches the screen as the Body Battery it produced. They stay in the
    /// enum because the contract has 27 types, but a frame carrying one is dropped rather
    /// than drawn — the server no longer offers them, and this is the second lock.
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
        case .line, .o2night, .dual:                return .curve
        case .band:                                 return .pair
        case .bars, .days, .delta:                  return .column
        case .ring, .gauge, .battery:               return .arc
        case .split, .fuel, .balance:               return .stack
        case .cells, .heat, .recomp:                return .grid
        case .hypnogram, .zones:                    return .strip
        case .wave:                                 return .trace
        case .sparks, .table, .events, .workout, .meal, .food: return .rows
        }
    }

    /// 05 · ACCENT MAP — colour is the data domain, not decoration.
    var accent: Color {
        switch self {
        case .battery, .days, .cells, .recomp:              return NB.lime1      // move · steps
        case .fuel, .meal, .food, .balance, .split:         return NB.cyan1      // fuel · protein
        case .hypnogram, .delta, .dual:                     return NB.violet1    // recover · sleep
        case .metric, .ring, .gauge, .line, .bars, .heat, .workout, .events, .table:
                                                            return NB.ember1     // heart · fat
        case .o2night, .band:                               return NB.blue1      // spo2 · carbs
        case .zones:                                        return NB.ember1
        case .wave:                                         return NB.alert2     // warning · ecg
        case .sparks, .text:                                return NB.white      // stress · hrv
        }
    }

    /// Slot 3 · which hero layout this type uses.
    var hero: HeroStyle {
        switch self {
        case .metric:               return .large
        case .ring, .gauge, .battery: return .ring
        case .sparks:               return .none
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
        default:                                                               return .training
        }
    }
}

enum PanelRenderer: String, Hashable {
    case number, curve, pair, column, arc, stack, grid, strip, trace, rows
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
    var ttlMinutes: Int = 20
    var priority: Priority = .normal

    enum Priority: String, Hashable { case normal, alert }

    var accent: Color { accentOverride ?? type.accent }

    static func == (a: PanelWidget, b: PanelWidget) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// The panel while she is working. Not a type — a state of the same surface.
    static let thinking = PanelWidget(
        type: .text, title: "THINKING", tag: nil,
        sentence: "记下了。正在把它换算成今天的额度。",
        footer: nil, action: nil, data: .none)
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
    case trace(samples: [Double], hz: Double)                 // trace
    case rows([RowItem])                                      // rows

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

    var body: some View {
        Button { onTap(widget.targetOverride ?? widget.type.target) } label: { canvas }
            .buttonStyle(.plain)
            .accessibilityLabel("\(widget.title) · \(widget.sentence)")
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            // Slot 1 · title
            Text(widget.title.uppercased())
                .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
                .foregroundStyle(widget.accent)
                .offset(x: Slot.safeX, y: Slot.topY)

            // Slot 2 · tag — never takes the accent
            if let tag = widget.tag {
                Text(tag.rawValue)
                    .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                    .foregroundStyle(NB.white.opacity(0.30))
                    .frame(width: 358 - Slot.safeX * 2, alignment: .trailing)
                    .offset(x: Slot.safeX, y: Slot.topY)
            }

            hero
            chart

            // Slot 6 · sentence — the brightest text on the screen
            Text(widget.sentence)
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
                Text(action.uppercased())
                    .font(NBFont.dot(500, 10.5)).tracking(0.16 * 10.5)
                    .foregroundStyle(widget.accent)
                    .frame(width: 358, alignment: .center)
                    .offset(y: Slot.actionY)
            }

            // ALERT is the fourth and last layer of the stack; nothing draws above it.
            if widget.priority == .alert {
                Color(hex: 0xEF4444, opacity: 0.12).allowsHitTesting(false)
            }
        }
        .frame(width: 358, height: 470, alignment: .topLeading)
    }

    // MARK: hero

    @ViewBuilder private var hero: some View {
        switch widget.type.hero {
        case .large:
            Text(heroValue)
                .font(NBFont.brand(700, 84)).tracking(-0.045 * 84)
                .foregroundStyle(NB.white.opacity(0.45))
                .frame(width: 358, alignment: .center)
                .offset(y: Slot.heroLargeY)

            if let sub = subText {
                Text(sub)
                    .font(NBFont.dot(500, 10.5)).tracking(0.20 * 10.5)
                    .foregroundStyle(NB.white.opacity(0.42))
                    .frame(width: 358, alignment: .center)
                    .offset(y: Slot.subY)
            }

        case .small:
            Text(heroValue)
                .font(NBFont.brand(700, 44)).tracking(-0.045 * 44)
                .foregroundStyle(NB.white.opacity(0.45))
                .offset(x: Slot.heroSmall.x, y: Slot.heroSmall.y)

            if let ref = heroRef {
                Text(ref)
                    .font(NBFont.dot(600, 10.5)).tracking(0.14 * 10.5)
                    .foregroundStyle(widget.accent)
                    .frame(width: 358 - Slot.safeX * 2, alignment: .trailing)
                    .offset(x: Slot.safeX, y: Slot.heroRefY)
            }

        case .ring, .own, .none:
            EmptyView()
        }
    }

    private var heroValue: String {
        if let hero = widget.hero, !hero.isEmpty { return hero }
        switch widget.data {
        case .series(let s):                      return s.last.map { Fmt.kg($0) } ?? Fmt.dash
        case .ring(let v, let g, let u):          return u.isEmpty ? "\(Int(v))/\(Int(g))" : "\(Int(v))\(u)"
        case .gauge(let v, _):                    return Fmt.kg(v)
        case .bins(let b):                        return Fmt.kcal(b.reduce(0) { $0 + $1.1 })
        case .parts(let p):                       return p.first.map { Fmt.kcal($0.1) } ?? Fmt.dash
        case .cells(_, _, let v, _):              return "\(v.filter { $0 > 0 }.count)"
        case .rows(let r):                        return r.first?.value ?? Fmt.dash
        case .pair(let hi, _):                    return hi.last.map { Fmt.kg($0) } ?? Fmt.dash
        case .trace(let s, _):                    return s.isEmpty ? Fmt.dash : "\(Int(s.reduce(0, +) / Double(s.count)))"
        case .strip(let s):                       return "\(s.count)"
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
        Group {
            switch widget.type.renderer {
            case .number:
                EmptyView()
            case .curve:
                if case .series(let s) = widget.data {
                    CurveRenderer(values: s, accent: widget.accent,
                                  splitAt: widget.curveSplit, accent2: widget.curveSecondary).frame(height: h)
                }
            case .pair:
                if case .pair(let hi, let lo) = widget.data {
                    PairRenderer(hi: hi, lo: lo, accent: widget.accent).frame(height: h)
                }
            case .column:
                if case .bins(let b) = widget.data {
                    ColumnRenderer(bins: b, accent: widget.accent).frame(height: h)
                }
            case .arc:
                if case .ring(let v, let g, _) = widget.data {
                    ArcRenderer(fraction: g > 0 ? v / g : 0, accent: widget.accent, label: Fmt.kg(v, decimals: 0))
                        .frame(width: Slot.heroRing.width, height: Slot.heroRing.height)
                } else if case .gauge(let v, let z) = widget.data {
                    GaugeRenderer(value: v, zones: z, accent: widget.accent)
                        .frame(width: Slot.heroRing.width, height: Slot.heroRing.height)
                }
            case .stack:
                if case .parts(let p) = widget.data {
                    StackRenderer(parts: p).frame(height: h)
                }
            case .grid:
                if case .cells(let r, let c, let v, let l) = widget.data {
                    GridRenderer(rows: r, cols: c, values: v, levels: l, accent: widget.accent).frame(height: h)
                }
            case .strip:
                if case .strip(let s) = widget.data {
                    StripRenderer(segments: s).frame(height: h)
                }
            case .trace:
                if case .trace(let s, let hz) = widget.data {
                    TraceRenderer(samples: s, hz: hz, accent: widget.accent).frame(height: h)
                }
            case .rows:
                if case .rows(let r) = widget.data {
                    RowsRenderer(items: r, accent: widget.accent).frame(height: h)
                }
            }
        }
        .frame(width: widget.type.renderer == .arc ? Slot.heroRing.width : 358 - Slot.safeX * 2)
        .offset(x: widget.type.renderer == .arc ? Slot.heroRing.minX : Slot.safeX,
                y: widget.type.renderer == .arc ? Slot.heroRing.minY : Slot.chartY)
    }
}
