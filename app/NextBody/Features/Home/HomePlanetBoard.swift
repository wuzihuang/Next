import SwiftUI

/// 06-A · the centre page, measured off the 390×746 board.
/// Planets are particle spheres drawn in code (see ParticlePlanet).
struct HomePlanetBoard: View {
    let model: HomeV2Model.Planet
    let events: Int
    let onGuide: () -> Void
    let onTimeline: () -> Void
    let onReadiness: () -> Void
    let onSleep: () -> Void
    let onLoad: () -> Void
    let onFood: () -> Void

    @AppStorage("nb.home.mcpGuideDismissed") private var guideDismissed = false

    private var face: Face { Face(model, events: events) }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 16)
            hero
                .frame(maxHeight: .infinity)
            twin
            food
            Color.clear.frame(height: 17)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon)
    }

    private var hero: some View {
        Button(action: onReadiness) {
            heroPlate
        }
        .buttonStyle(HotZoneTap(pressedScale: 1))
        .accessibilityIdentifier("READINESS")
    }

    private var heroPlate: some View {
        ZStack(alignment: .topTrailing) {
            ParticlePlanet(kind: .terra, center: UnitPoint(x: 0.79, y: 0.54), radius: 0.32, pitch: 1.5,
                           lit: face.terraLit, sunSide: 1, day: 90, stars: 70)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(face.orbitColor).frame(width: 6, height: 6)
                    Text(face.orbit)
                        .font(NBFont.dot(700, 11))
                        .tracking(0.12 * 11)
                        .foregroundStyle(face.orbitColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(L("READINESS"))
                    .font(jost(500, 11))
                    .tracking(0.18 * 11)
                    .foregroundStyle(Color.white.opacity(0.72))
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(face.readiness)
                        .font(NBFont.dot(800, 88))
                        .tracking(-0.04 * 88)
                        .foregroundStyle(NB.lime1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("/100")
                        .font(NBFont.dot(700, 16))
                        .foregroundStyle(Color.white.opacity(0.30))
                }
                .padding(.top, 2)
                HStack(spacing: 6) {
                    Text(face.statusLead)
                        .font(NBFont.dot(700, 11))
                        .tracking(0.08 * 11)
                        .foregroundStyle(NB.lime1)
                    Text("·")
                        .font(NBFont.dot(700, 11))
                        .foregroundStyle(Color.white.opacity(0.56))
                    Text(face.statusDelta)
                        .font(NBFont.dot(700, 11))
                        .foregroundStyle(Color.white.opacity(0.56))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .frame(minHeight: 244)
        .clipped()
    }

    private var twin: some View {
        HStack(spacing: 0) {
            sleepCell
            loadCell
        }
        .frame(height: 170)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }

    private var sleepCell: some View {
        Button(action: onSleep) {
            sleepPlate
        }
        .buttonStyle(HotZoneTap(pressedScale: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("SLEEP")
    }

    private var sleepPlate: some View {
        ZStack(alignment: .topLeading) {
            ParticlePlanet(kind: .luna, center: UnitPoint(x: 0.70, y: 0.43), radius: 0.29, pitch: 1.34,
                           lit: face.lunaLit, sunSide: -1, day: 50, stars: 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(L("SLEEP"))
                        .font(jost(500, 11))
                        .tracking(0.16 * 11)
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text(L("LUNA"))
                        .font(NBFont.dot(700, 9))
                        .foregroundStyle(NB.violet1)
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(face.sleepScore)
                        .font(NBFont.dot(800, 44))
                        .tracking(-0.04 * 44)
                        .foregroundStyle(NB.violet1)
                    Text("/100")
                        .font(NBFont.dot(700, 12))
                        .foregroundStyle(Color.white.opacity(0.30))
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
                meter(fill: face.sleepFill, tint: NB.violet1, marker: nil)
                HStack {
                    Text(face.sleepDuration)
                        .foregroundStyle(NB.violet1)
                    Spacer()
                    Text(face.sleepDeep)
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .font(NBFont.dot(700, 10))
                .padding(.top, 6)
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1) }
    }

    private var loadCell: some View {
        Button(action: onLoad) {
            loadPlate
        }
        .buttonStyle(HotZoneTap(pressedScale: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("LOAD")
    }

    private var loadPlate: some View {
        ZStack(alignment: .topLeading) {
            ParticlePlanet(kind: .mars, center: UnitPoint(x: 0.72, y: 0.43), radius: 0.29, pitch: 1.34,
                           lit: face.marsLit, sunSide: -1, day: 36, stars: 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(L("LOAD"))
                        .font(jost(500, 11))
                        .tracking(0.16 * 11)
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text(L("MARS"))
                        .font(NBFont.dot(700, 9))
                        .foregroundStyle(NB.run1)
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(face.load)
                        .font(NBFont.dot(800, 44))
                        .tracking(-0.04 * 44)
                        .foregroundStyle(face.loadHit ? NB.lime1 : NB.run1)
                    Text("/" + face.loadTarget)
                        .font(NBFont.dot(800, 20))
                        .foregroundStyle(NB.lime1)
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
                meter(fill: face.loadFill, tint: face.loadHit ? NB.lime1 : NB.run1, marker: face.aimTick)
                HStack {
                    Text(face.aimLeft)
                        .foregroundStyle(NB.lime1)
                    Spacer()
                    Text(face.aimRight)
                        .foregroundStyle(Color.white.opacity(0.56))
                }
                .font(NBFont.dot(700, 10))
                .padding(.top, 6)
            }
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func meter(fill: CGFloat, tint: Color, marker: CGFloat?) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 3)
                Rectangle().fill(tint).frame(width: max(0, width * fill), height: 3)
                if let marker {
                    Rectangle()
                        .fill(NB.lime1)
                        .frame(width: 2, height: 9)
                        .offset(x: width * marker - 1)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 9)
    }

    @ViewBuilder
    private var food: some View {
        VStack(spacing: 0) {
            switch face.food {
            case .empty(let kcal, let meals, let protein, let carbs, let fat, let guide):
                Button(action: onFood) {
                    allowanceRow(kcal: kcal, meals: meals) {
                        HStack(spacing: 12) {
                            macroTarget(L("PROTEIN"), protein, NB.optimal2)
                            macroTarget(L("CARBS"), carbs, NB.lime1)
                            macroTarget(L("FAT"), fat, NB.run1)
                        }
                    }
                }
                .buttonStyle(HotZoneTap(pressedScale: 1))
                .accessibilityIdentifier("FOOD")
                if !guideDismissed {
                Button(action: onGuide) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(guide)
                            .font(jost(400, 15))
                            .foregroundStyle(Color.white)
                            .lineSpacing(7)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(L("CONNECT MCP →"))
                            .font(NBFont.dot(700, 11))
                            .tracking(0.08 * 11)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                    }
                }
                .buttonStyle(HotZoneTap(pressedScale: 1))
                .accessibilityIdentifier("CONNECT_MCP")
                .overlay(alignment: .bottomTrailing) {
                    Button { withAnimation(.easeOut(duration: 0.2)) { guideDismissed = true } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.65))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("CONNECT_MCP_DISMISS")
                }
                }
            case .logged(let eaten, let allow, let meals, let left, let rows):
                Button(action: onFood) {
                    VStack(spacing: 0) {
                        loggedHeader(eaten: eaten, allow: allow, meals: meals, left: left)
                        loggedMacros(rows)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(HotZoneTap(pressedScale: 1))
                .accessibilityIdentifier("FOOD")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }

    /// Unlogged top line: today's allowance, with the three macro targets on the right.
    private func allowanceRow<Trailing: View>(kcal: String, meals: String,
                                              @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("FOOD"))
                        .font(jost(600, 10))
                        .tracking(0.18 * 10)
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text(meals)
                        .font(NBFont.dot(700, 9))
                        .foregroundStyle(Color.white.opacity(0.52))
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(kcal)
                        .font(NBFont.dot(800, 28))
                        .tracking(-0.03 * 28)
                        .foregroundStyle(Color.white)
                    Text(L("KCAL ALLOW"))
                        .font(NBFont.dot(700, 11))
                        .tracking(0.04 * 11)
                        .foregroundStyle(Color.white.opacity(0.65))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func macroTarget(_ name: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(NBFont.dot(800, 16))
                .foregroundStyle(tint)
            Text(name)
                .font(jost(600, 9))
                .tracking(0.12 * 9)
                .foregroundStyle(Color.white.opacity(0.52))
        }
    }

    private func loggedHeader(eaten: String, allow: String, meals: String, left: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("FOOD"))
                    .font(jost(600, 10))
                    .tracking(0.18 * 10)
                    .foregroundStyle(Color.white.opacity(0.72))
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(eaten)
                        .font(NBFont.dot(800, 28))
                        .tracking(-0.03 * 28)
                        .foregroundStyle(Color.white)
                    Text(L("/ %@ ALLOW", allow))
                        .font(NBFont.dot(700, 12))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(meals)
                    .font(NBFont.dot(700, 9))
                    .foregroundStyle(Color.white.opacity(0.52))
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1) }
            VStack(alignment: .trailing, spacing: 4) {
                Text(L("LEFT"))
                    .font(jost(600, 10))
                    .tracking(0.18 * 10)
                    .foregroundStyle(Color.white.opacity(0.72))
                Text(left)
                    .font(NBFont.dot(800, 28))
                    .tracking(-0.03 * 28)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(L("KCAL"))
                    .font(NBFont.dot(700, 9))
                    .tracking(0.08 * 9)
                    .foregroundStyle(Color.white.opacity(0.52))
            }
            .padding(.leading, 12)
            .padding(.trailing, 20)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(width: 124, alignment: .trailing)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }

    private func loggedMacros(_ rows: [Face.Row]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                loggedMacro(row, index: index, count: rows.count)
            }
        }
        .frame(height: 68)
    }

    private func loggedMacro(_ row: Face.Row, index: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(row.name)
                    .font(jost(600, 9))
                    .tracking(0.14 * 9)
                    .foregroundStyle(Color.white.opacity(0.56))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !row.aside.isEmpty {
                    Text(row.aside)
                        .font(NBFont.dot(700, 9))
                        .foregroundStyle(row.met ? row.tint : Color.white.opacity(0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 2)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(row.eaten)
                    .font(NBFont.dot(800, 20))
                    .foregroundStyle(row.tint)
                Text("/\(row.target)G")
                    .font(NBFont.dot(700, 10))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
            Spacer(minLength: 2)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.10))
                    Rectangle().fill(row.tint).frame(width: max(0, geo.size.width * row.fill))
                }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 10)
        .padding(.leading, index == 0 ? 20 : 14)
        .padding(.trailing, index == count - 1 ? 20 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            if index < count - 1 {
                Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            ChevronUp()
            Button(action: onTimeline) {
                VStack(spacing: 4) {
                    Text(L("TODAY TIMELINE · %d EVENTS", events))
                        .font(NBFont.dot(600, 11))
                        .tracking(0.18 * 11)
                        .foregroundStyle(NB.lime1)
                    if events == 0 {
                        Text(L("Start your workout"))
                            .font(.custom("Jost-Regular", size: 12))
                            .foregroundStyle(Color.white.opacity(0.48))
                    }
                }
            }
            .buttonStyle(HotZoneTap(pressedScale: 1))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private func jost(_ weight: Int, _ size: CGFloat) -> Font {
        let style: String
        switch weight {
        case ..<450: style = "Regular"
        case ..<550: style = "Medium"
        case ..<650: style = "SemiBold"
        default: style = "Bold"
        }
        return .custom("Jost-\(style)", size: size)
    }
}

private struct ChevronUp: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 2, y: size.height - 2))
            path.addLine(to: CGPoint(x: size.width / 2, y: 2))
            path.addLine(to: CGPoint(x: size.width - 2, y: size.height - 2))
            context.stroke(path, with: .color(NB.lime1), style: StrokeStyle(lineWidth: 1.4, lineCap: .square, lineJoin: .miter))
        }
        .frame(width: 16, height: 10)
        .accessibilityHidden(true)
    }
}

/// How much of each planet the sun reaches. Never less than half, so the planet always reads; a full
/// score lights the whole disc.
private extension Face {
    var terraLit: Double { Self.lit(Int(readiness)) }
    var lunaLit: Double { Self.lit(Int(sleepScore)) }
    var marsLit: Double { 0.5 + 0.5 * Double(loadFill) }

    static func lit(_ score: Int?) -> Double {
        guard let score else { return 0.5 }
        return 0.5 + 0.5 * Double(max(0, min(100, score))) / 100
    }
}

private struct Face {
    var orbit: String
    var orbitColor: Color
    var readiness: String
    var statusLead: String
    var statusDelta: String
    var sleepScore: String
    var sleepDuration: String
    var sleepDeep: String
    var sleepFill: CGFloat
    var load: String
    var loadTarget: String
    var loadFill: CGFloat
    var aimTick: CGFloat
    var aimLeft: String
    var aimRight: String
    var loadHit: Bool
    var food: Food

    enum Food {
        case empty(kcal: String, meals: String, protein: String, carbs: String, fat: String, guide: String)
        case logged(eaten: String, allow: String, meals: String, left: String, rows: [Row])
    }

    struct Row: Identifiable {
        var id: String
        var name: String
        var eaten: String
        var target: String
        var fill: CGFloat
        var tint: Color
        var met: Bool
        var aside: String
    }

    init(_ model: HomeV2Model.Planet, events: Int) {
        switch ProcessInfo.processInfo.environment["NB_DEBUG_HOME_BOARD"] {
        case "A": self = .boardA; return
        case "B": self = .boardB; return
        case "C": self = .boardC; return
        case "D": self = .boardD; return
        default: break
        }
        _ = events
        orbitColor = model.food.face == .complete ? NB.lime1 : (model.band == .recover ? Color.white.opacity(0.72) : NB.blue1)
        orbit = L("TERRA · %@ · %@", model.orbitPlace, model.orbitState)
        readiness = model.readiness.map(String.init) ?? Fmt.dash
        statusLead = model.band == .unknown ? Fmt.dash : L("%@ · %@", model.statusWord, model.statusPhrase)
        statusDelta = model.vsAverage.map { HomeV2Model.signedInt($0) + " " + L("VS AVG") } ?? L("—— VS AVG")
        sleepScore = model.sleepScore.map(String.init) ?? Fmt.dash
        sleepDuration = model.sleepMinutes.map { Fmt.duration($0) } ?? Fmt.dash
        sleepDeep = model.sleepDeepMinutes.map { L("DEEP %@", Fmt.duration($0)) } ?? model.sleepFoot
        sleepFill = CGFloat(model.sleepScore ?? 0) / 100
        load = Fmt.load(model.load)
        loadTarget = model.loadTarget.map { Fmt.load($0) } ?? Fmt.dash
        let target = model.loadTarget ?? 0
        let current = model.load ?? 0
        loadHit = target > 0 && current >= target
        loadFill = target > 0 ? min(1, CGFloat(current / target)) : 0
        let ceiling = max(target, 10)
        aimTick = target > 0 ? min(1, CGFloat(target / ceiling)) : 0
        if model.band == .recover, let aim = model.loadTarget {
            aimLeft = L("LOW AIM %@", Fmt.load(aim))
            aimRight = L("HOLD & REST")
        } else if loadHit {
            aimLeft = L("AIM %@ HIT", loadTarget)
            aimRight = model.band == .peak ? L("OPTIMAL") : L("HIT")
        } else if let aim = model.loadTarget, let now = model.load {
            aimLeft = L("AIM %@", Fmt.load(aim))
            aimRight = L("%@ TO GO", Fmt.load(max(0, aim - now)))
        } else {
            aimLeft = L("NO AIM YET")
            aimRight = Fmt.dash
        }
        switch model.food.face {
        case .unlogged, .recovery:
            food = .empty(
                kcal: model.food.targetKcal.map { Fmt.kcal(Double($0)) } ?? Fmt.dash,
                meals: L("%d MEALS", model.food.meals),
                protein: model.food.protein.target.map(String.init) ?? Fmt.dash,
                carbs: model.food.carb.target.map(String.init) ?? Fmt.dash,
                fat: model.food.fat.target.map(String.init) ?? Fmt.dash,
                guide: model.food.guide ?? "")
        case .remaining, .complete:
            let left = model.food.kcalLeft.map { Fmt.kcal(Double(max(0, $0))) } ?? Fmt.dash
            food = .logged(
                eaten: model.food.eatenKcal.map { Fmt.kcal(Double($0)) } ?? Fmt.dash,
                allow: model.food.targetKcal.map { Fmt.kcal(Double($0)) } ?? Fmt.dash,
                meals: L("%d MEALS", model.food.meals),
                left: left,
                rows: [
                    Self.macro("protein", L("PROTEIN"), model.food.protein, NB.optimal2),
                    Self.macro("carbs", L("CARBS"), model.food.carb, NB.lime1),
                    Self.macro("fat", L("FAT"), model.food.fat, NB.run1)
                ])
        }
    }

    private static func macro(_ id: String, _ name: String, _ macro: HomeV2Model.Macro, _ tint: Color) -> Row {
        let eaten = macro.eaten
        let target = macro.target
        let fill: CGFloat = {
            guard let eaten, let target, target > 0 else { return 0 }
            return min(1, CGFloat(eaten) / CGFloat(target))
        }()
        let aside: String = {
            if macro.met { return L("HIT") + " ✓" }
            if let left = macro.left { return L("%dG LEFT", max(0, left)) }
            return ""
        }()
        return Row(
            id: id,
            name: name,
            eaten: eaten.map(String.init) ?? Fmt.dash,
            target: target.map(String.init) ?? Fmt.dash,
            fill: fill,
            tint: tint,
            met: macro.met,
            aside: aside)
    }

    static var boardA: Face {
        Face(
            orbit: "TERRA · HOME BASE · STEADY",
            orbitColor: NB.blue1,
            readiness: "78",
            statusLead: "STEADY · READY TO TRAIN",
            statusDelta: "+12 VS AVG",
            sleepScore: "82",
            sleepDuration: "7H 12M",
            sleepDeep: "DEEP 1H 48M",
            sleepFill: 0.82,
            load: "5.1",
            loadTarget: "8.0",
            loadFill: 98.0 / 154.0,
            aimTick: 124.0 / 154.0,
            aimLeft: "AIM 8.0",
            aimRight: "2.9 TO GO",
            loadHit: false,
            food: .empty(
                kcal: "2,280",
                meals: "0 MEALS",
                protein: "145",
                carbs: "290",
                fat: "60",
                guide: "Connect MCP, then type what you eat in your personal agent."))
    }

    static var boardB: Face {
        Face(
            orbit: "TERRA · LOW ORBIT · RECOVERY HOLD",
            orbitColor: Color.white.opacity(0.72),
            readiness: "44",
            statusLead: "RECOVER · REST TODAY",
            statusDelta: "−24 VS AVG",
            sleepScore: "52",
            sleepDuration: "5H 10M",
            sleepDeep: "DEBT −2H 15M",
            sleepFill: 0.52,
            load: "1.8",
            loadTarget: "3.0",
            loadFill: 0.22,
            aimTick: 3.0 / 10.0,
            aimLeft: "LOW AIM 3.0",
            aimRight: "HOLD & REST",
            loadHit: false,
            food: .empty(
                kcal: "2,100",
                meals: "0 MEALS",
                protein: "145",
                carbs: "245",
                fat: "60",
                guide: "Connect MCP, then type what you eat in your personal agent."))
    }

    static var boardC: Face {
        Face(
            orbit: "TERRA · ORBIT LOCKED · ALL TARGETS MET",
            orbitColor: NB.lime1,
            readiness: "88",
            statusLead: "PEAK · FULL CHARGE",
            statusDelta: "+18 VS AVG",
            sleepScore: "90",
            sleepDuration: "7H 54M",
            sleepDeep: "OPTIMAL FULL",
            sleepFill: 0.90,
            load: "8.2",
            loadTarget: "8.0",
            loadFill: 1,
            aimTick: 0.80,
            aimLeft: "AIM 8.0 HIT",
            aimRight: "OPTIMAL",
            loadHit: true,
            food: .logged(
                eaten: "2,240",
                allow: "2,280",
                meals: "3 MEALS",
                left: "40",
                rows: [
                    Row(id: "protein", name: "PROTEIN", eaten: "142", target: "145", fill: 142.0 / 145.0, tint: NB.optimal2, met: true, aside: "HIT ✓"),
                    Row(id: "carbs", name: "CARBS", eaten: "282", target: "290", fill: 282.0 / 290.0, tint: NB.lime1, met: true, aside: "HIT ✓"),
                    Row(id: "fat", name: "FAT", eaten: "58", target: "60", fill: 58.0 / 60.0, tint: NB.run1, met: true, aside: "HIT ✓")
                ]))
    }

    static var boardD: Face {
        Face(
            orbit: "TERRA · HOME BASE · STEADY",
            orbitColor: NB.blue1,
            readiness: "78",
            statusLead: "STEADY · READY TO TRAIN",
            statusDelta: "+12 VS AVG",
            sleepScore: "82",
            sleepDuration: "7H 12M",
            sleepDeep: "DEEP 1H 48M",
            sleepFill: 0.82,
            load: "5.1",
            loadTarget: "8.0",
            loadFill: 98.0 / 154.0,
            aimTick: 124.0 / 154.0,
            aimLeft: "AIM 8.0",
            aimRight: "2.9 TO GO",
            loadHit: false,
            food: .logged(
                eaten: "1,420",
                allow: "2,280",
                meals: "2 MEALS",
                left: "860",
                rows: [
                    Row(id: "protein", name: "PROTEIN", eaten: "96", target: "145", fill: 96.0 / 145.0, tint: NB.optimal2, met: false, aside: "49G LEFT"),
                    Row(id: "carbs", name: "CARBS", eaten: "142", target: "290", fill: 142.0 / 290.0, tint: NB.lime1, met: false, aside: "148G LEFT"),
                    Row(id: "fat", name: "FAT", eaten: "48", target: "60", fill: 48.0 / 60.0, tint: NB.run1, met: false, aside: "12G LEFT")
                ]))
    }

    private init(orbit: String, orbitColor: Color, readiness: String, statusLead: String, statusDelta: String,
                 sleepScore: String, sleepDuration: String, sleepDeep: String, sleepFill: CGFloat,
                 load: String, loadTarget: String, loadFill: CGFloat, aimTick: CGFloat,
                 aimLeft: String, aimRight: String, loadHit: Bool, food: Food) {
        self.orbit = orbit
        self.orbitColor = orbitColor
        self.readiness = readiness
        self.statusLead = statusLead
        self.statusDelta = statusDelta
        self.sleepScore = sleepScore
        self.sleepDuration = sleepDuration
        self.sleepDeep = sleepDeep
        self.sleepFill = sleepFill
        self.load = load
        self.loadTarget = loadTarget
        self.loadFill = loadFill
        self.aimTick = aimTick
        self.aimLeft = aimLeft
        self.aimRight = aimRight
        self.loadHit = loadHit
        self.food = food
    }
}
