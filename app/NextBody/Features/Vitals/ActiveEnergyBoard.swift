import SwiftUI

/// Paper HY1-0 · ACTIVE ENERGY day board. Five cards, one question each. The OUT
/// polyline is `FuelWindowMath.burnCurve` — the same points the calories page draws.
struct ActiveEnergyModel {
    let split: ActiveEnergySplit
    let hours: [ActiveEnergyHour]
    let outSolid: [FuelClockPoint]
    let outDashed: [FuelClockPoint]
    let restSolid: [FuelClockPoint]
    let restDashed: [FuelClockPoint]
    let metSolid: [FuelClockPoint]
    let metDashed: [FuelClockPoint]
    let peak: (index: Int, kcal: Double)?
    let weekBars: [ActiveEnergyWeekBar]
    let weekAverage: Double?
    let todayDelta: Double?
    let hoursLeft: Int
    let now: Date
    let dayStart: Date

    static func make(m: DailyMetrics, now: Date, history: [DailyMetrics]) -> ActiveEnergyModel {
        let now = min(now, min(m.asOf ?? now, m.day.end))
        let ticks = m.vitalsCurve
        let energyTicks = m.energyDistribution?.map(\.tick) ?? ticks
        let windows = sportWindows(m)
        let split = ActiveEnergyMath.split(
            dayStart: m.day.start, now: now, bmr: m.bmr, bmrFull: m.bmrFull,
            eActive: m.eActive, eTrain: m.eTrain, eOutNow: m.eOutNow,
            ticks: ticks, sportWindows: windows, energyDistribution: m.energyDistribution)
        let hours = ActiveEnergyMath.hourly(
            dayStart: m.day.start, now: now, split: split,
            ticks: energyTicks, sportWindows: windows)
        let out = split.out.map {
            ActiveEnergyMath.outCurve(dayStart: m.day.start, now: now, burnedNow: $0,
                                      burnedFull: m.eOutFull, restingNow: split.resting, ticks: energyTicks)
        }
        let rest = split.resting.map {
            ActiveEnergyMath.restCurve(dayStart: m.day.start, now: now, resting: $0)
        }
        let met = ActiveEnergyMath.intensity(dayStart: m.day.start, now: now, ticks: ticks)
        let weekDays: [(Date, Double?)] = (0..<7).map { offset in
            let day = m.day.adding(days: -(6 - offset))
            let row = day == m.day ? m : history.first { $0.day == day }
            return (day.start, row.flatMap(VitalsReadout.dayTotalBurn))
        }
        let week = ActiveEnergyMath.week(days: weekDays, todayStart: m.day.start)
        return ActiveEnergyModel(
            split: split, hours: hours,
            outSolid: out?.solid ?? [], outDashed: out?.dashed ?? [],
            restSolid: rest?.solid ?? [], restDashed: rest?.dashed ?? [],
            metSolid: met.solid, metDashed: met.dashed,
            peak: ActiveEnergyMath.peakHour(hours),
            weekBars: week.bars, weekAverage: week.average, todayDelta: week.todayDelta,
            hoursLeft: ActiveEnergyMath.hoursLeft(dayStart: m.day.start, now: now),
            now: now, dayStart: m.day.start)
    }

    static func sportWindows(_ m: DailyMetrics) -> [(Date, Date)] {
        m.segments.filter { !$0.allDay }.compactMap { segment in
            guard let minutes = segment.minutes, minutes > 0 else { return nil }
            return (segment.at, segment.at.addingTimeInterval(Double(minutes) * 60))
        }
    }

    var nowFraction: Double {
        FuelWindowMath.clockFraction(at: now, dayStart: dayStart)
    }
}

/// Ledger hero. Keeps `vitals.hero` and the sensor label so the second-level
/// UI test still lands on the right page.
struct ActiveEnergyHero: View {
    let model: ActiveEnergyModel
    let sensor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("TODAY · 04→%@", Fmt.clock(model.now)))
                .font(NBFont.ui(500, 11)).tracking(0.12 * 11)
                .foregroundStyle(NB.text3Prod)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Fmt.kcal(model.split.out))
                    .font(NBFont.dot(700, 56)).tracking(-0.04 * 56)
                    .foregroundStyle(model.split.out == nil ? NB.text3Prod : NB.lime1)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(L("KCAL OUT"))
                    .font(NBFont.ui(500, 13)).tracking(0.1 * 13)
                    .foregroundStyle(NB.text3Prod)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(L("RESTING %@ + ACTIVE %@",
                   Fmt.kcal(model.split.resting), Fmt.kcal(model.split.active)))
                .font(NBFont.ui(400, 14))
                .foregroundStyle(NB.text2)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("vitals.hero")
        .accessibilityLabel(sensor)
        .accessibilityValue(model.split.out.map { "\($0) KCAL OUT" } ?? "no reading")
    }
}

struct ActiveEnergyBoard: View {
    let model: ActiveEnergyModel

    var body: some View {
        accumulated
        hourly
        split
        intensity
        week
        footer
    }

    private var accumulated: some View {
        CardBlock(title: L("ACCUMULATED"), trailing: "KCAL") {
            VStack(alignment: .leading, spacing: 8) {
                if model.outSolid.isEmpty {
                    VitalsChartEmpty(line: L("HOURLY ENERGY NOT AVAILABLE"),
                                     sub: L("DAILY ACTIVE ENERGY IS WEIGHT-AWARE AND SETTLED"),
                                     height: 176)
                } else {
                    ActiveEnergyLineChart(
                        series: [
                            .init(points: model.restSolid, tint: NB.macroValue, dashed: false, width: 1.5),
                            .init(points: model.restDashed, tint: NB.macroValue, dashed: true, width: 1.5),
                            .init(points: model.outSolid, tint: NB.lime1, dashed: false, width: 2),
                            .init(points: model.outDashed, tint: NB.lime1, dashed: true, width: 2),
                        ],
                        nowX: model.nowFraction,
                        nowBright: true,
                        maxY: chartMax,
                        height: 176,
                        mark: model.outSolid.last.map { ($0, NB.lime1) },
                        restMark: model.restSolid.last.map { ($0, NB.macroValue) })
                    VitalsAxis(labels: FuelWindowMath.clockLabels(dayStart: model.dayStart),
                               highlightsLast: false, tint: NB.lime1)
                    HStack(spacing: 14) {
                        legendTick(NB.lime1, L("OUT %@", Fmt.kcal(model.split.out)))
                        legendTick(NB.macroValue, L("RESTING %@", Fmt.kcal(model.split.resting)))
                        legendTick(NB.lime1.opacity(0.5), leftoverLabel)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var leftoverLabel: String {
        guard let last = model.outDashed.last?.y, let now = model.split.out else {
            return L("EST +%@", Fmt.dash)
        }
        return L("EST +%@", Fmt.kcal(max(0, last - now)))
    }

    private var hourly: some View {
        CardBlock(title: L("PER HOUR"),
                  trailing: model.peak.map { L("PEAK %@ · %@",
                                               VitalsMath.clock(day: UserDay.containing(model.dayStart),
                                                                minute: $0.index * 60),
                                               Fmt.kcal($0.kcal)) }) {
            VStack(alignment: .leading, spacing: 8) {
                LivedHourBars(hours: model.hours, tint: NB.lime1, height: 84)
                VitalsAxis(labels: FuelWindowMath.clockLabels(dayStart: model.dayStart),
                           highlightsLast: false, tint: NB.lime1)
                Text(L("BMR floor %@/h · faded = not lived yet",
                       Fmt.kcal(model.split.bmrFull.map { $0 / (FuelWindowMath.dayEnd(dayStart: model.dayStart).timeIntervalSince(model.dayStart) / 3600) })))
                    .font(NBFont.ui(400, 11))
                    .foregroundStyle(NB.text3Prod)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private var split: some View {
        let s = model.split
        return CardBlock(title: L("SPLIT"),
                         trailing: L("4 PARTS · %@", Fmt.kcal(s.out))) {
            VStack(alignment: .leading, spacing: 12) {
                ActiveEnergySplitBar(split: s)
                HStack(alignment: .top, spacing: 12) {
                    splitCell(L("RESTING"), s.resting, NB.white.opacity(0.55),
                              s.bmrFull.flatMap { full in
                                  s.elapsedMinutes.map { L("%@ × %d / %d", Fmt.kcal(full), $0, Int(FuelWindowMath.dayEnd(dayStart: model.dayStart).timeIntervalSince(model.dayStart) / 60)) }
                              } ?? L("NEEDS YOUR WEIGHT"))
                    splitCell(L("SPORT"), s.sport, NB.lime1,
                              sportFoot(s))
                }
                HStack(alignment: .top, spacing: 12) {
                    splitCell(L("STEPS"), s.steps, NB.lime1.opacity(0.75),
                              s.stepCount.map { L("%@ steps · MET %@", Fmt.int($0),
                                                  metLabel(s.stepsMet)) }
                              ?? L("——"))
                    splitCell(L("INCIDENTAL"), s.incidental, NB.lime1.opacity(0.55),
                              s.incidentalMinutes.map { L("%d min · MET %@", $0, metLabel(s.incidentalMet)) }
                              ?? L("——"))
                }
            }
        }
    }

    private var intensity: some View {
        let peak = model.metSolid.map(\.y).max() ?? ActiveEnergyMath.stillMet
        return CardBlock(title: L("INTENSITY"),
                         trailing: L("MET · MAX %@", metLabel(peak))) {
            VStack(alignment: .leading, spacing: 8) {
                ActiveEnergyLineChart(
                    series: [
                        .init(points: model.metSolid, tint: NB.lime1, dashed: false, width: 2),
                        .init(points: model.metDashed, tint: NB.white.opacity(0.35), dashed: true, width: 2),
                    ],
                    nowX: model.nowFraction,
                    maxY: max(peak, ActiveEnergyMath.sportMet),
                    height: 84)
                VitalsAxis(labels: FuelWindowMath.clockLabels(dayStart: model.dayStart),
                           highlightsLast: false, tint: NB.lime1)
                Text(L("1.0 still · 3.0 walk · 5.1 the session"))
                    .font(NBFont.ui(400, 11))
                    .foregroundStyle(NB.text3Prod)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private var week: some View {
        CardBlock(title: L("LAST 7 DAYS"),
                  trailing: weekTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                ActiveEnergyWeekBars(bars: model.weekBars, average: model.weekAverage, height: 84)
                HStack {
                    ForEach(Array(model.weekBars.enumerated()), id: \.offset) { _, bar in
                        Text(String(Fmt.weekday(bar.start).prefix(3)).uppercased())
                            .font(NBFont.ui(bar.isToday ? 600 : 500, 10)).tracking(0.08 * 10)
                            .foregroundStyle(bar.isToday ? NB.lime1 : NB.text3Prod)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(L("Dashed = 7-day average · today has %dH left", model.hoursLeft))
                    .font(NBFont.ui(400, 11))
                    .foregroundStyle(NB.text3Prod)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private var weekTrailing: String {
        let avg = L("AVG %@", Fmt.kcal(model.weekAverage))
        guard let delta = model.todayDelta else { return avg }
        return L("%@ · TODAY %@", avg, Fmt.signedKcal(delta))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L("%@ + %@ + %@ + %@ = %@",
                   Fmt.kcal(model.split.resting),
                   Fmt.kcal(model.split.sport),
                   Fmt.kcal(model.split.steps),
                   Fmt.kcal(model.split.incidental),
                   Fmt.kcal(model.split.out)))
                .font(NBFont.ui(500, 13))
                .foregroundStyle(NB.text2)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(L("Resting energy is estimated from your body profile; active energy from recorded activity."))
                .font(NBFont.ui(400, 11))
                .foregroundStyle(NB.text3Prod)
            Text(L("Missing activity time is not included."))
                .font(NBFont.ui(400, 11))
                .foregroundStyle(NB.text3Prod)
            Text(L("A missing part reads —— not 0."))
                .font(NBFont.ui(400, 11))
                .foregroundStyle(NB.text3Prod)
        }
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .padding(.top, 2)
    }

    private var chartMax: Double {
        let ys = (model.outSolid + model.outDashed + model.restSolid + model.restDashed).map(\.y)
        return max(ys.max() ?? 1, 1)
    }

    private func sportFoot(_ split: ActiveEnergySplit) -> String {
        guard let minutes = split.sportMinutes else { return L("——") }
        return L("%d min · MET %@", minutes, metLabel(split.sportMet))
    }

    private func metLabel(_ value: Double?) -> String {
        guard let value else { return Fmt.dash }
        return String(format: "%.1f", value)
    }

    private func splitCell(_ name: String, _ value: Double?, _ tint: Color, _ foot: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(NBFont.ui(600, 11)).tracking(0.08 * 11)
                    .foregroundStyle(NB.text2)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(Fmt.kcal(value))
                    .font(NBFont.dot(600, 19))
                    .foregroundStyle(value == nil ? NB.text3Prod : tint)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(foot)
                .font(NBFont.ui(400, 10))
                .foregroundStyle(NB.text3Prod)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendTick(_ tint: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(tint).frame(width: 14, height: 2)
            Text(text)
                .font(NBFont.ui(500, 11)).tracking(0.06 * 11)
                .foregroundStyle(NB.text2)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }
}

struct ActiveEnergySplitBar: View {
    let split: ActiveEnergySplit

    var body: some View {
        let parts: [(Double, Color)] = [
            (split.resting, NB.white.opacity(0.22)),
            (split.sport, NB.lime1),
            (split.steps, NB.lime1.opacity(0.75)),
            (split.incidental, NB.lime1.opacity(0.55)),
        ].compactMap { value, tint in
            guard let value, value > 0 else { return nil }
            return (value, tint)
        }
        let total = parts.reduce(0) { $0 + $1.0 }
        GeometryReader { geo in
            HStack(spacing: 0) {
                if total <= 0 {
                    Rectangle().fill(NB.barTrack)
                } else {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        Rectangle()
                            .fill(part.1)
                            .frame(width: max(2, geo.size.width * part.0 / total))
                    }
                }
            }
        }
        .frame(height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ActiveEnergyLineChart: View {
    struct Series {
        var points: [FuelClockPoint]
        var tint: Color
        var dashed: Bool
        var width: CGFloat
    }
    let series: [Series]
    var nowX: Double = 0
    var nowBright = false
    let maxY: Double
    var height: CGFloat = 176
    var mark: (FuelClockPoint, Color)? = nil
    var restMark: (FuelClockPoint, Color)? = nil

    var body: some View {
        Canvas { ctx, size in
            func px(_ p: FuelClockPoint) -> CGPoint {
                CGPoint(x: size.width * p.x, y: size.height * (1 - p.y / max(maxY, 0.001)))
            }
            var nowLine = Path()
            nowLine.move(to: CGPoint(x: size.width * nowX, y: 0))
            nowLine.addLine(to: CGPoint(x: size.width * nowX, y: size.height))
            ctx.stroke(nowLine,
                       with: .color(NB.white.opacity(nowBright ? 0.85 : 0.12)),
                       style: StrokeStyle(lineWidth: 1, dash: nowBright ? [] : [2, 3]))
            for item in series {
                guard item.points.count >= 2 else { continue }
                var path = Path()
                path.move(to: px(item.points[0]))
                for point in item.points.dropFirst() {
                    if point.startsSegment { path.move(to: px(point)) }
                    else { path.addLine(to: px(point)) }
                }
                ctx.stroke(path, with: .color(item.tint),
                           style: StrokeStyle(lineWidth: item.width,
                                              dash: item.dashed ? [5, 4] : []))
            }
            if let restMark {
                let at = px(restMark.0)
                ctx.fill(Path(ellipseIn: CGRect(x: at.x - 3, y: at.y - 3, width: 6, height: 6)),
                         with: .color(restMark.1))
            }
            if let mark {
                let at = px(mark.0)
                ctx.fill(Path(ellipseIn: CGRect(x: at.x - 4.5, y: at.y - 4.5, width: 9, height: 9)),
                         with: .color(mark.1))
            }
        }
        .frame(height: height)
    }
}

struct LivedHourBars: View {
    let hours: [ActiveEnergyHour]
    let tint: Color
    var height: CGFloat = 28

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, hours.count)
            let gap: CGFloat = n > 20 ? 2 : 3
            let w = (size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            let top = hours.map(\.kcal).max() ?? 0
            guard top > 0 else { return }
            for (i, hour) in hours.enumerated() {
                let h = max(0.8, size.height * hour.kcal / top)
                let rect = CGRect(x: CGFloat(i) * (w + gap), y: size.height - h, width: w, height: h)
                ctx.fill(Path(rect), with: .color(tint.opacity(hour.lived ? 1 : 0.18)))
            }
        }
        .frame(height: height)
    }
}

struct ActiveEnergyWeekBars: View {
    let bars: [ActiveEnergyWeekBar]
    let average: Double?
    var height: CGFloat = 84

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, bars.count)
            let gap: CGFloat = 11
            let w = (size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            let top = max(bars.compactMap(\.out).max() ?? 0, average ?? 0, 1)
            if let average {
                var line = Path()
                let y = size.height * (1 - average / top)
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(NB.white.opacity(0.28)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            for (i, bar) in bars.enumerated() {
                guard let out = bar.out else { continue }
                let h = max(3, size.height * out / top)
                let rect = CGRect(x: CGFloat(i) * (w + gap), y: size.height - h, width: w, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                         with: .color(bar.isToday ? NB.lime1 : NB.white.opacity(0.2)))
            }
        }
        .frame(height: height)
    }
}
