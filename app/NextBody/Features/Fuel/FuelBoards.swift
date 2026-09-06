import SwiftUI

/// Paper 09H · stacked IN / OUT / DIFF. Five-digit Doto never sits side by side.
struct FuelStackedHero: View {
    let intake: String
    let burned: String
    let gap: String
    var gapTint: Color = NB.cyan1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            heroRow(L("IN"), intake, NB.ember1)
            heroRow(L("OUT"), burned, NB.cyan1)
            heroRow(L("DIFF"), gap, gapTint)
        }
    }

    private func heroRow(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(NBFont.ui(500, 11)).tracking(0.12 * 11)
                .foregroundStyle(NB.text3Prod)
            Spacer(minLength: 8)
            Text(value)
                .font(NBFont.dot(700, 28)).tracking(-0.02 * 28)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// 09E-C / 09H-A · 24h clock. Orange step is IN, cyan burn follows movement, white is NOW.
struct FuelDayChart: View {
    let meals: [(Date, Double)]
    let burnedNow: Double?
    let burnedFull: Double?
    let budget: Double?
    let now: Date
    let dayStart: Date
    let happenedIntake: Double
    var burnTicks: [(Date, Int?)] = []
    var outUnknown: Bool = false

    var body: some View {
        let maxY = FuelWindowMath.chartMax(budget: budget, intake: happenedIntake,
                                           burnedNow: burnedNow, burnedFull: burnedFull)
        let intake = FuelWindowMath.intakeSteps(meals: meals, dayStart: dayStart, now: now,
                                                projectTo: budget)
        let burn = burnedNow.map {
            FuelWindowMath.burnCurve(dayStart: dayStart, now: now, burnedNow: $0,
                                     burnedFull: burnedFull, ticks: burnTicks)
        }
        let nowX = FuelWindowMath.clockFraction(at: now, dayStart: dayStart)
        return VStack(alignment: .leading, spacing: 8) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                func px(_ p: FuelClockPoint) -> CGPoint {
                    CGPoint(x: w * p.x, y: h * (1 - p.y / maxY))
                }
                if let budget, budget > 0 {
                    var budgetLine = Path()
                    let y = h * (1 - budget / maxY)
                    budgetLine.move(to: CGPoint(x: 0, y: y))
                    budgetLine.addLine(to: CGPoint(x: w, y: y))
                    ctx.stroke(budgetLine, with: .color(NB.white.opacity(0.22)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                if !outUnknown, let burn {
                    let fill = band(intake.solid, burn.solid, width: w, height: h, maxY: maxY)
                    ctx.fill(fill, with: .color(NB.lime2.opacity(0.14)))
                    stroke(ctx, burn.solid, px: px, color: NB.cyan1, dashed: false)
                    stroke(ctx, burn.dashed, px: px, color: NB.cyan1, dashed: true)
                }
                stroke(ctx, intake.solid, px: px, color: NB.ember1, dashed: false)
                stroke(ctx, intake.dashed, px: px, color: NB.ember1, dashed: true)

                var nowLine = Path()
                nowLine.move(to: CGPoint(x: w * nowX, y: 0))
                nowLine.addLine(to: CGPoint(x: w * nowX, y: h))
                ctx.stroke(nowLine, with: .color(NB.white.opacity(0.85)), lineWidth: 1)

                if let last = intake.solid.last {
                    let at = px(last)
                    ctx.fill(Path(ellipseIn: CGRect(x: at.x - 3.5, y: at.y - 3.5, width: 7, height: 7)),
                             with: .color(NB.ember1))
                }
                if !outUnknown, let last = burn?.solid.last {
                    let at = px(last)
                    ctx.fill(Path(ellipseIn: CGRect(x: at.x - 3.5, y: at.y - 3.5, width: 7, height: 7)),
                             with: .color(NB.cyan1))
                }
            }
            .frame(height: 148)
            HStack {
                ForEach(["00", "06", "12", "18", "24"], id: \.self) { label in
                    Text(label)
                        .font(NBFont.dot(label == "24" ? 700 : 500, 9))
                        .foregroundStyle(label == "24" ? NB.ember1 : NB.white.opacity(0.34))
                    if label != "24" { Spacer(minLength: 0) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("THE DAY SO FAR"))
        .accessibilityValue(L("IN %@ · OUT %@", Fmt.kcal(happenedIntake),
                              outUnknown ? Fmt.dash : Fmt.kcal(burnedNow)))
    }

    private func stroke(_ ctx: GraphicsContext, _ points: [FuelClockPoint],
                        px: (FuelClockPoint) -> CGPoint, color: Color, dashed: Bool) {
        guard points.count >= 2 else { return }
        var path = Path()
        path.move(to: px(points[0]))
        for point in points.dropFirst() { path.addLine(to: px(point)) }
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: 2, dash: dashed ? [5, 4] : []))
    }

    private func band(_ intake: [FuelClockPoint], _ burn: [FuelClockPoint],
                      width: CGFloat, height: CGFloat, maxY: Double) -> Path {
        func px(_ p: FuelClockPoint) -> CGPoint {
            CGPoint(x: width * p.x, y: height * (1 - p.y / maxY))
        }
        guard intake.count >= 2, burn.count >= 2 else { return Path() }
        var path = Path()
        path.move(to: px(intake[0]))
        for point in intake.dropFirst() { path.addLine(to: px(point)) }
        for point in burn.reversed() { path.addLine(to: px(point)) }
        path.closeSubpath()
        return path
    }
}

struct FuelWeekBars: View {
    let days: [FuelDayFacts]
    let budget: Double?

    var body: some View {
        let maxY = FuelWindowMath.chartMax(
            budget: budget,
            intake: days.compactMap(\.intake).max() ?? 0,
            burnedNow: days.compactMap(\.burned).max(),
            burnedFull: nil)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let h = geo.size.height
                ZStack(alignment: .topLeading) {
                    if let budget, budget > 0 {
                        Rectangle().fill(NB.white.opacity(0.22))
                            .frame(width: geo.size.width, height: 1)
                            .offset(y: h * (1 - budget / maxY))
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .bottom, spacing: 3) {
                                bar(row.intake, NB.ember1, height: h, maxY: maxY)
                                bar(row.burned, NB.cyan1, height: h, maxY: maxY)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(height: 132)
            HStack {
                ForEach(Array(days.enumerated()), id: \.offset) { i, row in
                    Text(String(Fmt.weekday(row.day.date).prefix(2)))
                        .font(NBFont.dot(i == days.count - 1 ? 700 : 500, 9))
                        .foregroundStyle(i == days.count - 1 ? NB.ember1 : NB.white.opacity(0.34))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityLabel(L("THIS WEEK"))
    }

    private func bar(_ value: Double?, _ tint: Color, height: CGFloat, maxY: Double) -> some View {
        let fraction = (value ?? 0) / maxY
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(value == nil ? Color.clear : tint)
            .frame(width: 9, height: max(value == nil ? 0 : 3, height * fraction))
    }
}

struct FuelMonthBars: View {
    let days: [FuelDayFacts]
    let budget: Double?

    var body: some View {
        let chunks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        let maxY = FuelWindowMath.chartMax(
            budget: budget,
            intake: days.compactMap(\.intake).max() ?? 0,
            burnedNow: nil, burnedFull: nil)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let h = geo.size.height
                ZStack(alignment: .topLeading) {
                    if let budget, budget > 0 {
                        Rectangle().fill(NB.white.opacity(0.22))
                            .frame(width: geo.size.width, height: 1)
                            .offset(y: h * (1 - budget / maxY))
                    }
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(chunks.enumerated()), id: \.offset) { _, week in
                            HStack(alignment: .bottom, spacing: 2) {
                                ForEach(Array(week.enumerated()), id: \.offset) { _, row in
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .fill(row.intake == nil ? Color.clear : NB.ember1)
                                        .frame(width: 6,
                                               height: max(row.intake == nil ? 0 : 3,
                                                           h * ((row.intake ?? 0) / maxY)))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(height: 120)
            HStack {
                ForEach(Array(chunks.enumerated()), id: \.offset) { i, week in
                    let last = i == chunks.count - 1
                    Text(last ? L("%@ · NOW", monthMark(week.first?.day)) : monthMark(week.first?.day))
                        .font(NBFont.dot(last ? 700 : 500, 9))
                        .foregroundStyle(last ? NB.ember1 : NB.white.opacity(0.34))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityLabel(L("A TYPICAL DAY"))
    }

    private func monthMark(_ day: UserDay?) -> String {
        guard let day else { return "" }
        return Fmt.displayDate(day.date, format: "d MMM").uppercased()
    }
}

/// Fixed-width ledger. Numbers never share a slot and never wrap.
struct FuelLedgerTable: View {
    let title: String
    let trailing: String
    let dayHeader: String
    let rows: [FuelLedgerRow]
    var footer: FuelLedgerRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
                Text(trailing)
                    .font(NBFont.ui(500, 11)).tracking(0.06 * 11)
                    .foregroundStyle(NB.text3Prod)
                    .lineLimit(1)
            }
            .padding(.bottom, 10)
            header
            ForEach(rows) { row in
                Hairline()
                ledgerRow(row)
            }
            if let footer {
                Hairline()
                ledgerRow(footer, muted: true)
            }
        }
        .padding(16)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(dayHeader)
                .font(NBFont.ui(500, 10)).tracking(0.12 * 10)
                .foregroundStyle(NB.text3Prod)
                .frame(width: 110, alignment: .leading)
            headerCell(L("IN"), NB.ember1)
            headerCell(L("OUT"), NB.cyan1)
            headerCell(L("DIFF"), NB.text3Prod)
        }
        .padding(.bottom, 6)
    }

    private func headerCell(_ title: String, _ tint: Color) -> some View {
        Text(title)
            .font(NBFont.ui(500, 10)).tracking(0.12 * 10)
            .foregroundStyle(tint)
            .lineLimit(1)
            .frame(width: 72, alignment: .trailing)
    }

    private func ledgerRow(_ row: FuelLedgerRow, muted: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(NBFont.ui(muted ? 500 : 600, 13))
                    .foregroundStyle(muted ? NB.text3Prod : NB.text1)
                    .lineLimit(1)
                if let caption = row.caption {
                    Text(caption)
                        .font(NBFont.ui(500, 10)).tracking(0.04 * 10)
                        .foregroundStyle(row.captionTint)
                        .lineLimit(1)
                }
            }
            .frame(width: 110, alignment: .leading)
            numberCell(row.intake, NB.ember1)
            numberCell(row.burned, NB.cyan1)
            numberCell(row.gap, row.gapTint)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title) \(row.intake) \(row.burned) \(row.gap)")
    }

    private func numberCell(_ value: String, _ tint: Color) -> some View {
        Text(value)
            .font(NBFont.ui(600, 15))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 72, alignment: .trailing)
    }
}

struct FuelLedgerRow: Identifiable {
    let id: String
    let title: String
    var caption: String?
    var captionTint: Color = NB.text3Prod
    let intake: String
    let burned: String
    let gap: String
    var gapTint: Color = NB.cyan1
}

/// One flat meal list. TIME / ITEM / KCAL / P / C / F — no breakfast / lunch / dinner groups.
struct FuelFoodTable: View {
    let meals: [MealEntry]
    let trailing: String
    var onSelect: (MealEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("FOOD"))
                    .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                    .foregroundStyle(NB.text3Prod)
                Spacer(minLength: 0)
                Text(trailing)
                    .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
                    .foregroundStyle(NB.ember1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.bottom, 8)
            header
            ForEach(meals) { meal in
                Hairline()
                Button { onSelect(meal) } label: { foodRow(meal) }
                    .buttonStyle(.plain)
            }
            if !meals.isEmpty {
                Hairline()
                totals
            }
        }
        .padding(16)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
        .accessibilityIdentifier("fuel.food")
    }

    private var header: some View {
        HStack(spacing: 0) {
            col(L("TIME"), width: 46, align: .leading, tint: NB.text3Prod, tracking: true)
            col(L("ITEM"), width: nil, align: .leading, tint: NB.text3Prod, tracking: true)
            col(L("KCAL"), width: 56, align: .trailing, tint: NB.text3Prod, tracking: true)
            col(L("P"), width: 40, align: .trailing, tint: NB.violet1, tracking: true)
            col(L("C"), width: 40, align: .trailing, tint: NB.optimal2, tracking: true)
            col(L("F"), width: 40, align: .trailing, tint: NB.run1, tracking: true)
        }
        .padding(.bottom, 6)
    }

    private func foodRow(_ meal: MealEntry) -> some View {
        HStack(spacing: 0) {
            col(clock(meal), width: 46, align: .leading, tint: NB.text3Prod, size: 12)
            Text(meal.text.isEmpty ? L(meal.slot.rawValue) : meal.text)
                .font(NBFont.ui(600, 14))
                .foregroundStyle(NB.text1)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            col(Fmt.kcal(meal.kcal), width: 56, align: .trailing, tint: NB.ember1, size: 14, weight: 600)
            col("\(meal.protein)", width: 40, align: .trailing, tint: NB.violet1, size: 13, weight: 600)
            col("\(meal.carb)", width: 40, align: .trailing, tint: NB.optimal2, size: 13, weight: 600)
            col("\(meal.fat)", width: 40, align: .trailing, tint: NB.run1, size: 13, weight: 600)
        }
        .padding(.vertical, 10)
    }

    private var totals: some View {
        HStack(spacing: 0) {
            Text(L("LOGGED"))
                .font(NBFont.ui(600, 11)).tracking(0.12 * 11)
                .foregroundStyle(NB.text2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            col(Fmt.kcal(meals.reduce(0) { $0 + $1.kcal }), width: 56, align: .trailing, tint: NB.text1, size: 14, weight: 600)
            col("\(meals.reduce(0) { $0 + $1.protein })", width: 40, align: .trailing, tint: NB.violet1, size: 13, weight: 600)
            col("\(meals.reduce(0) { $0 + $1.carb })", width: 40, align: .trailing, tint: NB.optimal2, size: 13, weight: 600)
            col("\(meals.reduce(0) { $0 + $1.fat })", width: 40, align: .trailing, tint: NB.run1, size: 13, weight: 600)
        }
        .padding(.top, 10)
    }

    private func col(_ text: String, width: CGFloat?, align: Alignment, tint: Color,
                     size: CGFloat = 10, weight: Int = 500, tracking: Bool = false) -> some View {
        Text(text)
            .font(NBFont.ui(weight, size))
            .tracking(tracking ? 0.12 * size : 0)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: align)
            .frame(width: width, alignment: align)
    }

    private func clock(_ meal: MealEntry) -> String {
        let clock = Fmt.clock(meal.at)
        let same = Calendar.current.isDate(meal.at, inSameDayAs: meal.day.start)
        return same ? clock : "\(clock)+1"
    }
}
