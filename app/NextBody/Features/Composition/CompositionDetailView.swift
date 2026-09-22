import SwiftUI

/// 10E · 成分详情。主语是体脂率。DAY 是这一次对上一次；WEEK / MONTH 是滚动窗口。
/// 数只来自已经落进 `body_composition` 的扫描行——SDK 里没落库的字段不画。
struct CompositionDetailView: View {
    let focus: Date?

    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @State private var rangeRaw = RollingPills.day.rawValue

    private var range: RollingPills { .parse(rangeRaw) }
    private var detail: DetailWindow { DetailWindow(.composition, range) }
    private var day: UserDay { UserDay.containing(focus ?? Date()) }
    private var now: Date { Date() }

    private var scans: [CompositionScan] {
        #if DEBUG
        if DebugEdge.on("empty") { return [] }
        if DebugEdge.on("firstscan") { return Array(data.compositionScans.prefix(1)) }
        #endif
        return data.compositionScans
    }

    private var window: (start: Date, end: Date) {
        CompositionWindowMath.bounds(range: range, endingOn: day, now: now)
    }
    private var windowScans: [CompositionScan] {
        CompositionWindowMath.inWindow(scans, from: window.start, to: window.end)
    }
    private var reading: CompositionDayReading? {
        CompositionWindowMath.dayReading(scans: scans, asOf: min(now, day.end))
    }
    private var plot: CompositionPlot {
        CompositionWindowMath.plot(scans: scans, range: range, endingOn: day, now: now)
    }
    private var buckets: [CompositionWeekBucket] {
        CompositionWindowMath.weekBuckets(scans: scans, endingOn: day)
    }
    private var weekDays: [UserDay] {
        day.rollingBack(7)
    }

    var body: some View {
        DetailScroll(glow: NB.lime1, title: L("COMPOSITION"), trailing: {
            Text(headerPeriod)
                .font(NBFont.dot(600, 11)).tracking(0.24 * 11)
                .foregroundStyle(NB.text3Prod)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }) {
            VStack(alignment: .leading, spacing: 14) {
                SegmentedPills(options: RollingPills.words,
                               selection: $rangeRaw)
                windowCard
                sinceBaselineCard
                if range == .day {
                    dayRows
                } else if range == .week {
                    scanRows
                } else {
                    weekRows
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("composition.page")
        } onBack: {
            router.back()
        }
        .onReceive(router.$windowRequest) { request in
            guard let request else { return }
            rangeRaw = request.rawValue
            router.windowRequest = nil
        }
        .task {
            #if DEBUG
            if let override = DetailWindow.debugRange(for: .composition) {
                rangeRaw = override.rawValue
            }
            #endif
            await BodyCompositionQueue.shared.flush()
            await Repository.shared.hydrate(detail, endingAt: day, into: data)
            await Analytics.shared.track("COMP_DETAIL_OPEN", [
                "RANGE": range.rawValue,
                "SCANS": windowScans.count,
                "HAS_CURRENT": reading != nil,
            ])
        }
    }

    /// Am I changing, and when is the next scan worth taking.
    ///
    /// Everything else on this page is a window — today against the last scan, a week, a
    /// month. This card is the only one that answers the question a person actually opened
    /// the app with, which is about the whole distance from where they started.
    ///
    /// The cadence line is a measurement suggestion, never a streak: a week is simply the
    /// shortest gap where two wrist BIA readings differ because of the body rather than
    /// because of breakfast. Missing it costs nothing and is never counted.
    @ViewBuilder private var sinceBaselineCard: some View {
        let ordered = scans.sorted { $0.at < $1.at }
        if let first = ordered.first, let latest = ordered.last,
           let change = BodyScanCadence.change(
            firstAt: first.at, firstFat: first.bodyFatPercent, firstLean: first.leanMassKg,
            latestAt: latest.at, latestFat: latest.bodyFatPercent, latestLean: latest.leanMassKg) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("SINCE YOUR FIRST SCAN"))
                        .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                        .foregroundStyle(NB.text3Prod)
                    Spacer(minLength: 0)
                    Text(L("%d DAYS", change.days))
                        .font(NBFont.dot(600, 11)).tracking(0.08 * 11)
                        .foregroundStyle(NB.lime1)
                }
                HStack(spacing: 0) {
                    CompositionFact(label: L("BODY FAT"),
                                    value: change.bodyFatPoints.map { Fmt.signedKg($0, decimals: 1) } ?? Fmt.dash,
                                    unit: change.bodyFatPoints == nil ? nil : "PT",
                                    valueTint: change.bodyFatPoints == nil ? NB.text1 : NB.lime1)
                    Rectangle().fill(NB.hairline).frame(width: 1)
                    CompositionFact(label: L("LEAN"),
                                    value: change.leanKg.map { Fmt.signedKg($0, decimals: 1) } ?? Fmt.dash,
                                    unit: change.leanKg == nil ? nil : "KG",
                                    valueTint: change.leanKg == nil ? NB.text1 : NB.lime1)
                    Rectangle().fill(NB.hairline).frame(width: 1)
                    CompositionFact(label: L("NEXT SCAN"),
                                    value: BodyScanCadence.isDue(since: latest.at)
                                        ? L("DUE") : "\(BodyScanCadence.daysLeft(since: latest.at))",
                                    unit: BodyScanCadence.isDue(since: latest.at) ? nil : L("D"),
                                    valueTint: BodyScanCadence.isDue(since: latest.at) ? NB.ember1 : NB.text1)
                }
            }
            .padding(16)
            .frame(width: NB.Layout.contentWidth, alignment: .leading)
            .cardSkin()
            .accessibilityIdentifier("composition.sinceBaseline")
        }
    }

    private var headerPeriod: String {
        switch range {
        case .day:
            guard let scan = reading?.current else { return L(detail.periodKey) }
            let clock = Fmt.clock(scan.at)
            if UserDay.containing(scan.at) == UserDay.containing(now) {
                return L("TODAY %@", clock)
            }
            return "\(Fmt.weekday(scan.at)) \(clock)"
        case .week, .month:
            return L(detail.periodKey)
        }
    }

    private var windowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(windowTitle)
                        .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                        .foregroundStyle(NB.white.opacity(0.60))
                    Spacer(minLength: 0)
                    if range == .day {
                        Text(L("NO CHART"))
                            .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                            .foregroundStyle(NB.white.opacity(0.60))
                    } else {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(NB.lime1.opacity(0.28))
                                .frame(width: 10, height: 10)
                            Text(L(range == .week ? "WEEK BAND" : "YOUR BAND"))
                                .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                                .foregroundStyle(NB.white.opacity(0.60))
                        }
                    }
                }

                if range == .day {
                    Text(dayCaption)
                        .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                        .foregroundStyle(NB.text2)
                } else if plot.points.isEmpty {
                    Text(L("No body scan in this window yet. A finished 30-second scan writes the first row."))
                        .font(NBFont.ui(400, 13)).tracking(0.02 * 13)
                        .foregroundStyle(NB.text3Prod)
                        .frame(height: 148, alignment: .topLeading)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(spacing: 8) {
                            CompositionTrendChart(plot: plot, labels: axisLabels)
                            HStack(spacing: 0) {
                                ForEach(Array(axisLabels.enumerated()), id: \.offset) { i, label in
                                    let last = i == axisLabels.count - 1
                                    Text(label.text)
                                        .font(NBFont.dot(last ? 700 : (label.dim ? 500 : 500), 9))
                                        .tracking(0.08 * 9)
                                        .foregroundStyle(last ? NB.lime1 : NB.white.opacity(label.dim ? 0.20 : 0.34))
                                    if i < axisLabels.count - 1 { Spacer(minLength: 0) }
                                }
                            }
                        }
                        CompositionScaleRail(labels: railLabels)
                            .frame(height: 148)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle().fill(NB.hairline).frame(height: 1)
            strip
        }
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
        .clipShape(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("COMPOSITION"))
        .accessibilityValue(L(detail.periodKey))
    }

    private var windowTitle: String {
        let n = range == .day ? (reading == nil ? 0 : 1) : plot.scanCount
        let count = n == 1 ? L("%d SCAN", n) : L("%d SCANS", n)
        return "\(L("BODY FAT")) % · \(count)"
    }

    private var dayCaption: String {
        guard let reading else {
            return L("No body scan yet. A finished 30-second scan writes the first row.")
        }
        if reading.previous == nil {
            return L("This is the first scan on this account. There is no previous row to compare.")
        }
        return L("A single scan cannot make a line. The last scan is the reference.")
    }

    private var strip: some View {
        HStack(spacing: 0) {
            switch range {
            case .day:
                CompositionFact(label: L("NOW"), value: fat(reading?.current.bodyFatPercent), unit: "%")
                Rectangle().fill(NB.hairline).frame(width: 1)
                CompositionFact(label: L("VS LAST"),
                                value: signedNumber(reading?.bodyFat.delta),
                                unit: reading?.bodyFat.delta == nil ? nil : "PT",
                                valueTint: reading?.bodyFat.delta == nil ? NB.text1 : NB.lime1)
                Rectangle().fill(NB.hairline).frame(width: 1)
                CompositionFact(label: L("LAST SCAN"), value: lastScanAge.value, unit: lastScanAge.unit)
            case .week:
                CompositionFact(label: L("NOW"), value: fat(plot.now), unit: "%")
                Rectangle().fill(NB.hairline).frame(width: 1)
                CompositionFact(label: L("7D LOW"), value: fat(plot.windowLow), unit: "%")
                Rectangle().fill(NB.hairline).frame(width: 1)
                CompositionFact(label: L("7D HIGH"), value: fat(plot.windowHigh), unit: "%")
            case .month:
                CompositionFact(label: L("NOW"), value: fat(plot.now), unit: "%")
                Rectangle().fill(NB.hairline).frame(width: 1)
                CompositionFact(label: L("30D LOW"), value: fat(plot.windowLow), unit: "%")
                Rectangle().fill(NB.hairline).frame(width: 1)
                CompositionFact(label: L("30D HIGH"), value: fat(plot.windowHigh), unit: "%")
            }
        }
    }

    private var lastScanAge: (value: String, unit: String?) {
        guard let previous = reading?.previous, let current = reading?.current else {
            return (Fmt.dash, nil)
        }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: previous.at),
            to: calendar.startOfDay(for: current.at)
        ).day ?? 0
        if days <= 0 { return (Fmt.clock(previous.at), nil) }
        return ("\(days)", L("D AGO"))
    }

    @ViewBuilder
    private var dayRows: some View {
        if let reading {
            dayDeltaCard(reading)
        }
    }

    private func dayDeltaCard(_ reading: CompositionDayReading) -> some View {
        let rows: [(name: String, field: CompositionFieldDelta, unit: String, highlight: Bool)] = [
            (L("BODY FAT"), reading.bodyFat, "%", true),
            (L("FAT MASS"), reading.fatMass, "KG", false),
            (L("LEAN MASS"), reading.leanMass, "KG", false),
            (L("BMR ESTIMATE"), reading.bmr, "KCAL/DAY", false),
            (L("INPUT WEIGHT"), reading.inputWeight, "KG", false),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            listHead(
                left: reading.previous.map { L("VS %@", "\(Fmt.weekday($0.at)) \(Fmt.clock($0.at))") }
                    ?? L("THIS SCAN"),
                right: L("5 FIELDS")
            )
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Rectangle().fill(NB.hairline).frame(height: 1)
                CompositionDeltaRow(
                    name: row.name,
                    before: number(row.field.before, unit: row.unit),
                    now: number(row.field.now, unit: row.unit),
                    delta: signed(row.field.delta, unit: row.unit == "%" ? "PT" : row.unit),
                    highlight: row.highlight
                )
            }
        }
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
        .clipShape(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
    }

    private var scanRows: some View {
        let ordered = windowScans.sorted { $0.at > $1.at }
        return VStack(alignment: .leading, spacing: 0) {
            listHead(left: L("EVERY SCAN"), right: L("NEWEST FIRST"))
            if ordered.isEmpty {
                Rectangle().fill(NB.hairline).frame(height: 1)
                emptyList
            } else {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, scan in
                    Rectangle().fill(NB.hairline).frame(height: 1)
                    let older = index + 1 < ordered.count ? ordered[index + 1] : nil
                    let delta: Double? = {
                        guard let now = scan.bodyFatPercent, let then = older?.bodyFatPercent else { return nil }
                        return now - then
                    }()
                    CompositionScanRow(
                        label: "\(Fmt.weekday(scan.at)) \(Fmt.clock(scan.at))",
                        value: fat(scan.bodyFatPercent),
                        unit: "%",
                        delta: older == nil ? "—" : signed(delta, unit: "PT"),
                        newest: index == 0
                    )
                }
                Rectangle().fill(NB.hairline).frame(height: 1)
                footnote(CompositionWindowMath.inWindow(scans, from: window.start, to: window.end))
            }
        }
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
        .clipShape(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
    }

    private var weekRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            listHead(left: L("WEEK AVERAGES"), right: L("NEWEST FIRST"))
            ForEach(Array(buckets.enumerated()), id: \.element.offset) { index, bucket in
                Rectangle().fill(NB.hairline).frame(height: 1)
                CompositionScanRow(
                    label: weekLabel(bucket.offset),
                    value: fat(bucket.averageFat),
                    unit: "%",
                    delta: bucket.offset + 1 >= buckets.count ? "—" : signed(bucket.delta, unit: "PT"),
                    newest: index == 0
                )
            }
            Rectangle().fill(NB.hairline).frame(height: 1)
            footnote(windowScans)
        }
        .frame(width: NB.Layout.contentWidth, alignment: .leading)
        .cardSkin()
        .clipShape(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
    }

    private func listHead(left: String, right: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(left)
                .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                .foregroundStyle(NB.white.opacity(0.60))
            Spacer(minLength: 0)
            Text(right)
                .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.white.opacity(0.60))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var emptyList: some View {
        Text(L("No body scan in this window yet."))
            .font(NBFont.ui(300, 13))
            .foregroundStyle(NB.text3Prod)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }

    private func footnote(_ scans: [CompositionScan]) -> some View {
        let fat = CompositionWindowMath.span(\.fatMassKg, in: scans)
        let lean = CompositionWindowMath.span(\.leanMassKg, in: scans)
        let bmr = CompositionWindowMath.span(\.bmrKcal, in: scans)
        let parts = [
            arrow(L("FAT MASS"), fat, "kg"),
            arrow(L("LEAN MASS"), lean, "kg"),
            arrow(L("BMR ESTIMATE"), bmr, "kcal/day"),
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 4) {
            Text(L("SAME WINDOW"))
                .font(NBFont.dot(600, 9)).tracking(0.2 * 9)
                .foregroundStyle(NB.white.opacity(0.34))
            Text(parts.isEmpty ? L("No other fields in this window.") : parts.joined(separator: " · "))
                .font(NBFont.ui(300, 11))
                .foregroundStyle(NB.text3Prod)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func arrow(_ name: String, _ span: CompositionSpan, _ unit: String) -> String? {
        guard let last = span.last else { return nil }
        if let first = span.first, first != last {
            return "\(name) \(fmt(first, unit: unit)) → \(fmt(last, unit: unit)) \(unit)"
        }
        return "\(name) \(fmt(last, unit: unit)) \(unit)"
    }

    private func weekLabel(_ offset: Int) -> String {
        switch offset {
        case 0: return L("THIS WEEK")
        case 1: return L("LAST WEEK")
        default: return L("%d WKS AGO", offset)
        }
    }

    private var axisLabels: [CompositionAxisLabel] {
        switch range {
        case .day:
            return []
        case .week:
            let measured = Set(plot.points.map(\.day))
            return weekDays.enumerated().map { index, slot in
                let last = index == weekDays.count - 1
                let text = last && slot == UserDay.containing(now) ? L("NOW") : Fmt.weekday(slot.start)
                return CompositionAxisLabel(text: text, dim: !measured.contains(slot) && !last)
            }
        case .month:
            return [
                CompositionAxisLabel(text: L("−30D"), dim: false),
                CompositionAxisLabel(text: L("−20D"), dim: false),
                CompositionAxisLabel(text: L("−10D"), dim: false),
                CompositionAxisLabel(text: L("NOW"), dim: false),
            ]
        }
    }

    private var railLabels: [String] {
        [plot.yMax, (plot.yMax + plot.yMin) / 2, plot.yMin].map { String(format: "%.1f", $0) }
    }

    private func fat(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? Fmt.dash
    }

    private func signedNumber(_ value: Double?) -> String {
        guard let value else { return Fmt.dash }
        let sign = value < 0 ? "−" : value > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", abs(value)))"
    }

    private func signed(_ value: Double?, unit: String) -> String {
        guard let value else { return "—" }
        let sign = value < 0 ? "−" : value > 0 ? "+" : ""
        if unit == "KCAL" {
            return "\(sign)\(Int(value.rounded())) \(unit)"
        }
        return "\(sign)\(String(format: "%.1f", abs(value))) \(unit)"
    }

    private func number(_ value: Double?, unit: String) -> String {
        guard let value else { return Fmt.dash }
        if unit == "KCAL" { return "\(Int(value.rounded()))" }
        return String(format: "%.1f", value)
    }

    private func fmt(_ value: Double, unit: String) -> String {
        unit == "kcal" ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
    }
}

private struct CompositionAxisLabel {
    var text: String
    var dim: Bool
}

private struct CompositionFact: View {
    let label: String
    let value: String
    var unit: String? = nil
    var valueTint: Color = NB.text1

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(NBFont.ui(500, 10)).tracking(0.16 * 10)
                .foregroundStyle(NB.text3Prod)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(NBFont.dot(700, 20))
                    .foregroundStyle(valueTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let unit {
                    Text(unit)
                        .font(NBFont.dot(500, 10))
                        .foregroundStyle(NB.white.opacity(0.45))
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompositionTrendChart: View {
    let plot: CompositionPlot
    let labels: [CompositionAxisLabel]
    var height: CGFloat = 148

    var body: some View {
        Canvas { ctx, size in
            let spanY = max(0.001, plot.yMax - plot.yMin)
            func y(_ value: Double) -> CGFloat {
                let clamped = min(plot.yMax, max(plot.yMin, value))
                return CGFloat((plot.yMax - clamped) / spanY) * (size.height - 2) + 1
            }
            func x(_ fraction: Double) -> CGFloat {
                CGFloat(min(1, max(0, fraction))) * (size.width - 6) + 3
            }
            func point(_ p: CompositionPoint) -> CGPoint {
                CGPoint(x: x(p.x), y: y(p.value))
            }

            let ticks = max(2, labels.count)
            for i in 0..<ticks {
                var lane = Path()
                let at = x(Double(i) / Double(ticks - 1))
                lane.move(to: CGPoint(x: at, y: 0))
                lane.addLine(to: CGPoint(x: at, y: size.height))
                ctx.stroke(lane, with: .color(NB.white.opacity(0.06)), lineWidth: 1)
            }

            if let low = plot.bandLow, let high = plot.bandHigh {
                let top = y(high)
                let bottom = y(low)
                ctx.fill(
                    Path(CGRect(x: 0, y: top, width: size.width, height: max(2, bottom - top))),
                    with: .color(NB.lime1.opacity(0.10))
                )
            }
            if let median = plot.median {
                var mid = Path()
                mid.move(to: CGPoint(x: 0, y: y(median)))
                mid.addLine(to: CGPoint(x: size.width, y: y(median)))
                ctx.stroke(mid, with: .color(NB.white.opacity(0.16)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            for run in plot.runs {
                guard let first = run.first else { continue }
                var path = Path()
                path.move(to: point(first))
                for item in run.dropFirst() { path.addLine(to: point(item)) }
                if run.count == 1 {
                    path.addLine(to: CGPoint(x: point(first).x + 0.5, y: point(first).y))
                }
                ctx.stroke(path, with: .color(NB.lime1),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                for item in run {
                    let at = point(item)
                    let last = item.at == plot.points.last?.at
                    let r: CGFloat = last ? 3.5 : 2.5
                    ctx.fill(Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)),
                             with: .color(NB.lime1))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

private struct CompositionScaleRail: View {
    let labels: [String]

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                    let fraction = labels.count > 1
                        ? Double(i) / Double(labels.count - 1)
                        : 0
                    let y = g.size.height * fraction
                    Text(label)
                        .font(NBFont.dot(600, 9))
                        .tracking(0.06 * 9)
                        .foregroundStyle(NB.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .offset(x: 0, y: y - 6)
                }
            }
        }
        .frame(width: 28)
        .accessibilityHidden(true)
    }
}

private struct CompositionDeltaRow: View {
    let name: String
    let before: String
    let now: String
    let delta: String
    var highlight = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(NBFont.ui(500, 12)).tracking(0.02 * 12)
                .foregroundStyle(highlight ? NB.text1 : NB.text2)
                .frame(width: 80, alignment: .leading)
            Text(before)
                .font(NBFont.dot(500, 12))
                .foregroundStyle(NB.white.opacity(0.34))
            Text("→")
                .font(NBFont.dot(500, 12))
                .foregroundStyle(NB.white.opacity(0.20))
            Text(now)
                .font(NBFont.dot(700, 15))
                .foregroundStyle(NB.text1)
            Spacer(minLength: 0)
            Text(delta)
                .font(NBFont.dot(600, 11)).tracking(0.1 * 11)
                .foregroundStyle(highlight ? NB.lime1 : NB.text2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

private struct CompositionScanRow: View {
    let label: String
    let value: String
    let unit: String
    let delta: String
    var newest = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(NBFont.ui(500, 12)).tracking(0.02 * 12)
                .foregroundStyle(newest ? NB.text1 : NB.text2)
                .frame(width: 92, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(NBFont.dot(700, 15))
                    .foregroundStyle(NB.text1)
                Text(unit)
                    .font(NBFont.dot(500, 10))
                    .foregroundStyle(NB.white.opacity(0.45))
            }
            Spacer(minLength: 0)
            Text(delta)
                .font(NBFont.dot(600, 11)).tracking(0.1 * 11)
                .foregroundStyle(newest ? NB.lime1 : NB.text2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

struct PagerButton: View {
    let forward: Bool
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color(hex: 0x141418))
                Path { p in
                    if forward {
                        p.move(to: CGPoint(x: 1, y: 1)); p.addLine(to: CGPoint(x: 5, y: 5)); p.addLine(to: CGPoint(x: 1, y: 9))
                    } else {
                        p.move(to: CGPoint(x: 5, y: 1)); p.addLine(to: CGPoint(x: 1, y: 5)); p.addLine(to: CGPoint(x: 5, y: 9))
                    }
                }
                .stroke(enabled ? Color(hex: 0x8A8A96) : Color(hex: 0x5A5A66),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                .frame(width: 6, height: 10)
            }
            .frame(width: 30, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// F2 §06 · three colours plus two greys. LEVEL is outline only — it says
/// "we can't tell", not "you hit it exactly".
struct DirectionCell: View {
    let direction: DailyDirection
    var today = false
    var height: CGFloat = 34
    var radius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(stroke, lineWidth: direction == .level ? 1.5 : (today ? 2 : 0)))
            .frame(height: height)
    }

    private var fill: Color {
        switch direction {
        case .deficit:     NB.lime1
        case .level:       .clear
        case .surplus:     NB.alert2
        case .greyNothing: Color(hex: 0x26262E)
        case .greyNoBurn:  Color(hex: 0x3A3A44)
        }
    }
    private var stroke: Color {
        if direction == .level { return NB.white.opacity(0.35) }
        return today ? NB.white.opacity(0.7) : .clear
    }
}
