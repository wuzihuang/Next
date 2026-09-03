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
        case .line, .o2night:                       return .curve
        case .dual:                                 return .dual
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
    /// 26 · dual · two series on their own scales, no fill between them.
    case dual
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
    /// 05 · C·07 · the photo track's answer carries two optional blocks the other tracks do not:
    /// the source chip at the top (the thumbnail and `IMG · PLATE · PARSED OK`) and the
    /// 「已记入今天的 fuel」 line at the bottom. Optional blocks of one template, not a second screen.
    var photo: PhotoAnswer?
    /// 06 · 20 · the body scan's result on the panel, as the board draws it: the settled fat
    /// percent as the hero with the last reading under it, four fields in tiles, the
    /// sentence, then the spine. An optional block of the one template, like `photo`.
    var composition: CompositionAnswer?
    /// 06 · 17 · a measurement's result "becomes a message": tapping it asks her about the
    /// numbers instead of opening a page. Only the frames the band just produced carry this.
    var replyPrompt: String?
    /// 06 · 16 · the measured number is the hero of the frame even on a trace-shaped widget:
    /// top-left like the small hero, but 60 pt, in the accent, with its own line under it.
    var heroLarge = false
    var heroSub: String?
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
        // 06 · 20 · a composition result is the reading. Tapping the numbers must not
        // leave the panel — only TAP FOR ALL 14 FIELDS does that. Other widgets stay
        // one tap to their page (F0 rule 06).
        Group {
            if widget.composition != nil {
                canvas
            } else {
                Button { go() } label: { canvas }
                    .buttonStyle(.plain)
            }
        }
        .accessibilityLabel("\(widget.title) · \(widget.sentence)")
    }

    private func go() { onTap(widget.targetOverride ?? widget.type.target) }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            if let photo = widget.photo {
                photoCanvas(photo)
            } else if let composition = widget.composition {
                compositionCanvas(composition)
            } else {
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

            }

            // ALERT is the fourth and last layer of the stack; nothing draws above it.
            if widget.priority == .alert {
                Color(hex: 0xEF4444, opacity: 0.12).allowsHitTesting(false)
            }
        }
        .frame(width: 358, height: 470, alignment: .topLeading)
    }

    // MARK: 06 · 20 · BODY COMPOSITION · JUST NOW

    /// The board's frame to the pixel: 358 × 470, its own LED ground (a reading is not drawn
    /// over the standby art), the lime hairline that marks a frame the band just produced,
    /// header at y16, hero at y70, the four tiles at y206, the sentence at y300, the spine at y378.
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
            Text(widget.title.uppercased())
                .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
                .foregroundStyle(NB.lime1)
            Spacer(minLength: 0)
            Text("JUST NOW")
                .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                .foregroundStyle(NB.white.opacity(0.30))
        }
        .frame(width: 318, height: 14)
        .offset(x: 20, y: 16)

        // hero · the number the scan settled, and where it stood last time
        VStack(spacing: 10) {
            Text(widget.hero ?? Fmt.dash)
                .font(NBFont.brand(700, 66)).tracking(-0.045 * 66)
                .foregroundStyle(NB.lime1)
            Text(c.heroSub.uppercased())
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
        Text(widget.sentence)
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
                    Text(action.uppercased())
                        .font(NBFont.dot(600, 10.5)).tracking(0.16 * 10.5)
                        .foregroundStyle(NB.lime1.opacity(0.85))
                        .frame(width: 318, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 318)
        .offset(x: 20, y: 378)
    }

    // MARK: 05 · C·07 · FROM YOUR PHOTO

    /// The same 358 × 470 canvas as A·08 / B·07, plus the source chip and the logged line.
    @ViewBuilder private func photoCanvas(_ photo: PhotoAnswer) -> some View {
        Text("FROM YOUR PHOTO")
            .font(NBFont.brand(500, 11.5)).tracking(0.08 * 11.5)
            .foregroundStyle(NB.white.opacity(0.70))
            .offset(x: Slot.safeX, y: Slot.topY)
        Text("PHOTO + TEXT")
            .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
            .foregroundStyle(NB.white.opacity(0.40))
            .frame(width: 358 - Slot.safeX * 2, alignment: .trailing)
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
        Text(widget.sentence)
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
            Text("LOG THE PLATE")
                .font(NBFont.dot(600, 10)).tracking(0.14 * 10)
                .foregroundStyle(NB.lime1)
                .frame(width: 120, height: 40)
                .overlay(Capsule().stroke(NB.lime1.opacity(0.6), lineWidth: 2.5))
            Text("SHOW FUEL")
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
                .offset(y: Slot.heroLargeY)

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
            case .dual:
                // ⚠️ The catalogue drew dual through the curve renderer, which eats one
                // series — the second line never existed. Two scales, one panel.
                if case .pair(let a, let b) = widget.data {
                    DualRenderer(a: a, b: b, accent: widget.accent,
                                 secondary: widget.curveSecondary ?? NB.white.opacity(0.45)).frame(height: h)
                }
            case .column:
                if case .bins(let b) = widget.data {
                    // 09 · B · delta 用带零轴的变体.
                    ColumnRenderer(bins: b, accent: widget.accent, zeroAxis: widget.type == .delta).frame(height: h)
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


/// 05 · C·07 · what the photo answer adds to the panel.
/// 06 · 20 · what the body scan's frame carries beyond the template: the line under the hero
/// and the four tiles. Everything in it came off the band or out of the store — never a
/// placeholder (a printed 34.2 no band produced is a number the user will believe).
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
