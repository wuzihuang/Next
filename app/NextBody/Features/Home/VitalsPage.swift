import SwiftUI

/// One of the eight page-two hot zones. Seven open a vitals board;
/// Body Battery opens the same reserve page Profile and the morning widget use.
enum PageTwoCard: Hashable {
    case vitals(VitalsMetric)
    case bodyBattery

    var cardKey: String {
        switch self {
        case .vitals(let metric): return metric.cardKey
        case .bodyBattery: return "BODY_BATTERY"
        }
    }

    var destination: Destination {
        switch self {
        case .vitals(let metric): return .vitals(metric)
        case .bodyBattery: return .bodyBattery
        }
    }
}

/// 04C · PAGE TWO · 往右一滑是仪表，不是判断. Eight of the strip's own 174-wide cards:
/// SLEEP · HEART / BODY BATTERY · STRESS / TEMP · STEPS / DISTANCE · ACTIVE. Night HRV
/// lives on the sleep page. Body Battery is the reserve score. RESPONSE is no longer
/// a page-two card; `vitals.response` still deep-links to that board. No dock, no
/// buttons, no adjectives — and not one read of the band.
struct VitalsPage: View {
    let m: DailyMetrics
    /// Rolling 24h stress on the STRESS card uses nights behind today so the bars and
    /// "now" share one window.
    let history: [DailyMetrics]
    let vitals: LiveVitals
    /// ADR 0008 · passed in rather than read off `m`, because a later loadHome replaces
    /// `store.today` wholesale and the copy carried on that struct goes with it.
    var sleepScore: SleepScore? = nil
    var width: CGFloat = NB.Layout.contentWidth
    /// The height the root frames the page to (panel top → over the dots' lane). The cards
    /// grow into it: row gaps stay a constant 10 and the card height takes the rest, the way
    /// the panel takes the rest on page one — a tall phone gets taller cards, not air.
    var height: CGFloat = 585
    /// 04 · every card is a hot zone now, each opening its own second level. The comment
    /// that used to sit here said a press state promises a page — the eight pages exist, so
    /// all eight cards press.
    let onOpen: (PageTwoCard) -> Void

    /// 04B rule 01 · the card is a fixed 174 wide; its height is whatever the phone leaves
    /// after the foot (12 + 12) and three row gaps of 10.
    private var cardHeight: CGFloat { (height - 12 - 12 - 3 * NB.Layout.cardGap) / 4 }

    private var freshness: TickFreshness { vitals.freshness }
    /// 04B rule 05 · one source for "now": the last tick. 90 minutes on it dims to 45 %,
    /// six hours turns the number itself into ——.
    private var dim: Double { freshness == .stale ? 0.45 : 1 }
    private var gone: Bool { freshness == .gone }
    private var day: UserDay { m.day }
    private var ticks: [VitalSample] { m.vitalsCurve }

    var body: some View {
        VStack(spacing: 0) {
            // 04B rule 01 · the row gaps are a constant 10 on every phone; the cards take
            // whatever height is left (cardHeight), so a tall phone grows the cards and a
            // short one still fits — no space-between band, no overflow.
            VStack(spacing: NB.Layout.cardGap) {
                HStack(spacing: NB.Layout.cardGap) {
                    zone(.vitals(.sleep)) { sleepCard }
                    zone(.vitals(.heart)) { heartCard }
                }
                HStack(spacing: NB.Layout.cardGap) {
                    zone(.bodyBattery) { bodyBatteryCard }
                    zone(.vitals(.stress)) { stressCard }
                }
                HStack(spacing: NB.Layout.cardGap) {
                    zone(.vitals(.temp)) { tempCard }
                    zone(.vitals(.steps)) { stepsCard }
                }
                HStack(spacing: NB.Layout.cardGap) {
                    zone(.vitals(.distance)) { distanceCard }
                    zone(.vitals(.active)) { ActiveEnergyCard(m: m, height: cardHeight) }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.bottom, 12)
            // 04B · LAST TICK 22:29 · 12 MIN AGO · 1H 05M OFF WRIST, pinned to the foot. The
            // page dots are not the page's: they are the root's furniture, crossfading in
            // the lane below this line (04B rule 02).
            Text(footLine)
                .font(NBFont.dot(500, 9.5)).tracking(0.12 * 9.5)
                .lineLimit(1).minimumScaleFactor(0.85)
                .foregroundStyle(NB.white.opacity(0.38))
                .frame(width: width)
        }
        .frame(width: width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Vitals, page two"))
    }

    /// ADR-0001 · a card presses like the strip's do: `HotZoneTap` retires the tap the moment
    /// the finger passes the slop, so the page drag underneath always wins a swipe.
    private func zone<Card: View>(_ slot: PageTwoCard,
                                  @ViewBuilder card: () -> Card) -> some View {
        Button { onOpen(slot) } label: { card() }
            .buttonStyle(HotZoneTap())
            .accessibilityIdentifier(slot.cardKey)
    }

    // MARK: cards

    /// ADR 0008 · the score takes the main position and the duration rides beside it as the
    /// unit — it is the largest single component of the score and the one quantity nobody
    /// has to be taught to read. No missing-input note here: this card is glanced at, the
    /// board is where a score gets explained. The stage strip is drawn only when the band
    /// filed a real stage line; a night with only totals gets no invented shape.
    private var sleepCard: some View {
        let night = m.sleep
        let score = sleepScore
        let duration = night.map { Fmt.duration($0.totalMinutes) }
        let hasLine = !(night?.line.isEmpty ?? true)
        return InstrumentCard(label: L("SLEEP"), tag: L("LAST NIGHT"), tint: NB.violet1,
                              height: cardHeight,
                              value: score.map { String($0.score) } ?? duration,
                              unit: score == nil ? (night == nil ? nil : L("ASLEEP")) : duration,
                              foot: Self.sleepFoot(night: night, score: score),
                              valueTint: score?.tint) {
            if hasLine, let night { SleepStrip(sleep: night, tint: NB.violet1) }
        }
    }

    private static func sleepFoot(night: SleepSummary?, score: SleepScore?) -> String {
        guard let night else { return L("NO NIGHT YET") }
        guard let score else { return L("SCORE NOT SETTLED YET") }
        // The calibration note lives here until the baselines are this person's own.
        if score.isCalibrating { return L("TYPICAL-ADULT BASELINE") }
        if let start = night.sleepStart, let wake = night.wakeAt, wake > start {
            return L("BED %@ · WAKE %@", Fmt.clock(start), Fmt.clock(wake))
        }
        return L("WINDOW NOT ON RECORD")
    }

    private var heartCard: some View {
        let peak = m.peakHR ?? ticks.compactMap(\.hr).max()
        let resting = m.nightInputs?.rhr.map { Int($0.rounded()) }
        // The newest tick often has steps or MET and no PPG. The number is the last
        // heart reading in the same 24h window the spark is drawn from — same rule as
        // the detail page and the STRESS card — not only LiveVitals.hr on that newest row.
        let samples = VitalSample.today(
            VitalSample.merging(history.flatMap(\.vitalsCurve), with: ticks),
            endingAt: Date())
        let latest = gone ? nil : (vitals.hr ?? samples.last(where: { $0.hr != nil })?.hr)
        // 04B F5 · DAY ONE. No tick has ever landed: the number is ——, the curve is not
        // drawn, and the card says so in words — an empty page, not a zeroed one.
        let dayOne = vitals.at == nil && ticks.isEmpty
        return InstrumentCard(label: L("HEART"), tag: L("NOW"), tint: NB.lime1,
                              height: cardHeight,
                              value: latest.map(String.init), unit: "BPM",
                              foot: L("RESTING %@ · PEAK %@", Fmt.int(resting), Fmt.int(peak)),
                              dim: dim,
                              // 04B F3 · GONE keeps the unit, greyed with the dash — the
                              // number is missing, the instrument is not.
                              unitWhenEmpty: gone && !dayOne,
                              status: dayOne ? ("NO TICKS YET", "FIRST SYNC DRAWS IT") : nil) {
            DaySpark(samples: ticks, day: day, value: { $0.hr.map(Double.init) }, low: 40, high: 160, tint: NB.lime1)
        }
    }

    private var bodyBatteryCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            bodyBatteryInstrument(now: context.date)
        }
    }

    private func bodyBatteryInstrument(now: Date) -> some View {
        #if DEBUG
        let forceEmpty = DebugEdge.on("empty")
        #else
        let forceEmpty = false
        #endif
        let freshness = m.bodyBatteryFreshness(at: now)
        let value = forceEmpty ? nil : m.bodyBatteryForDisplay(at: now)
        let stale = freshness != .fresh
        let empty = forceEmpty || (value == nil && m.bodyBatteryObservedAt == nil)
        let status: (String, String)? = empty
            ? (L("NO TICKS YET"), L("FIRST SYNC DRAWS IT"))
            : nil
        let foot: String
        if empty {
            foot = L("NO RECENT BATTERY READING")
        } else if value == nil, let at = m.bodyBatteryObservedAt {
            // #25 · the card is already showing ——. Say why, so it cannot be read as 0%.
            foot = L("NOT WORN SINCE %@", Fmt.clock(at))
        } else if stale, let at = m.bodyBatteryObservedAt {
            foot = L("SYNCED %@", Fmt.clock(at))
        } else if let charge = m.reserveDrivers?.nightCharge {
            foot = L("%@ · %@", L(BodyBattery.chargeWord(Int(charge.rounded()))), Fmt.signed(charge))
        } else {
            foot = L("FROM WRIST DATA")
        }
        return InstrumentCard(
            label: MetricNames.bodyBattery, tag: L("NOW"), tint: NB.lime1,
            height: cardHeight,
            value: value.map(String.init), unit: nil,
            foot: foot,
            dim: stale ? 0.45 : 1,
            status: status) {
            BatteryCurve(samples: m.reserveCurve, day: m.day, dim: stale, compact: true)
        }
    }

    private var stressCard: some View {
        let now = Date()
        let window = VitalsTimelinePolicy.today(endingAt: now)
        let samples = VitalSample.today(
            VitalSample.merging(history.flatMap(\.vitalsCurve), with: ticks),
            endingAt: now)
        let bins = VitalsMath.halfHourMean(samples, range: window, value: { $0.stress.map(Double.init) })
        let peak = VitalsMath.peak(bins)
        // The newest tick often has heart from PPG and no stress. The number is the last
        // stress reading in the same today window the bars are drawn from — same rule as
        // the detail page — not only LiveVitals.stress on that newest row.
        let latest = gone ? nil : (vitals.stress ?? samples.last(where: { $0.stress != nil })?.stress)
        return InstrumentCard(label: L("STRESS"), tag: L("TODAY"), tint: NB.ember1,
                              height: cardHeight,
                              value: latest.map(String.init), unit: L("/100 NOW"),
                              foot: peak.map { L("PEAK %d AT %@", Int($0.value.rounded()), Fmt.clock(window.start.addingTimeInterval(TimeInterval($0.index * 30 * 60)))) } ?? L("NO TICKS YET"),
                              dim: dim, unitWhenEmpty: gone) {
            FineBars(values: bins, tint: NB.ember1, highlight: { $0 > 60 })
        }
    }

    /// Shared by the card and by analytics.
    private var skinTempNight: SkinTempNightRange.Result {
        SkinTempPresentation.nightRange(today: m, history: history)
    }

    private var tempCard: some View {
        let window = VitalsTimelinePolicy.today(endingAt: Date())
        let samples = VitalSample.merging(history.flatMap(\.vitalsCurve), with: ticks)
            .filter { window.contains($0.ts) }
        let last = gone ? nil : samples.last(where: { $0.temp != nil })?.temp
        // ADR 0009 · the glance carries last night's verdict; LOW / HIGH live on the detail
        // page. The spark is ruled by this wrist's own range, never by 35.5–37.0 °C — that
        // is a core-temperature ruler and it flattens a 33 °C trace against the floor.
        let night = skinTempNight
        let axis = SkinTempPresentation.axis(night.range, pad: 1.0)
        let foot: String
        if let delta = night.delta, let tier = night.tier {
            foot = L("LAST NIGHT %+.1f · %@", delta, SkinTempPresentation.shortTier(tier))
        } else if let empty = night.empty {
            foot = SkinTempPresentation.reason(empty, learningNights: night.learningNights)
        } else {
            foot = L("NO TICKS YET")
        }
        return InstrumentCard(label: L("TEMP"), tag: L("NOW"), tint: NB.cyan1,
                              height: cardHeight,
                              value: last.map { String(format: "%.1f", $0) }, unit: L("°C SKIN"),
                              foot: foot,
                              dim: dim, unitWhenEmpty: gone) {
            DaySpark(samples: samples, day: day, value: \.temp,
                     low: axis.lowerBound, high: axis.upperBound, tint: NB.cyan1, range: window)
        }
    }

    private var stepsCard: some View {
        let bins = VitalsMath.hourSum(ticks, day: day, value: { $0.steps.map(Double.init) })
        let total = m.steps.map(Double.init) ?? VitalsMath.total(bins)
        let peak = VitalsMath.peak(bins)
        return InstrumentCard(label: L("STEPS"), tag: L("TODAY"), tint: NB.optimal2,
                              height: cardHeight,
                              value: total.map { Fmt.kcal($0) }, unit: nil,
                              foot: peak.map { L("PEAK %@ AT %@", Fmt.kcal($0.value), VitalsMath.clock(day: day, minute: $0.index * 60)) } ?? L("NO TICKS YET")) {
            HourBars(values: bins, tint: NB.optimal2)
        }
    }

    private var distanceCard: some View {
        let bins = VitalsMath.hourSum(ticks, day: day, value: \.dis)
        let metres = m.distanceM.map(Double.init) ?? VitalsMath.total(bins)
        let peak = VitalsMath.peak(bins)
        return InstrumentCard(label: L("DISTANCE"), tag: L("TODAY"), tint: NB.violetPink,
                              height: cardHeight,
                              value: metres.map { String(format: "%.1f", $0 / 1000) }, unit: "KM",
                              foot: peak.map { L("%.1f KM AT %@", $0.value / 1000, VitalsMath.clock(day: day, minute: $0.index * 60)) } ?? L("NO TICKS YET")) {
            HourBars(values: bins, tint: NB.violetPink)
        }
    }

    // MARK: foot

    private var footLine: String {
        guard let at = vitals.at else { return L("NO TICKS YET · FIRST SYNC DRAWS THE LINE") }
        let age = VitalsMath.age(of: at)
        var line = freshness == .stale ? L("SYNCED %@ · %@", Fmt.clock(at), age)
                                       : L("LAST TICK %@ · %@", Fmt.clock(at), age)
        // 04B rule 04 · gaps of an hour or more are named once, here, never on a card.
        if let gap = VitalsMath.offWrist(ticks), gap.minutes >= 60 {
            line += L(" · %@ OFF WRIST", Fmt.duration(gap.minutes))
        }
        return line
    }

    /// 04C · PAGE2_CARD_STATE{CARD,STATE}. RESPONSE stays in the map so a
    /// `vitals.response` deep link can still join against the same key; the page-two
    /// slot that used to carry it is BODY_BATTERY.
    static func cardStates(m: DailyMetrics, vitals: LiveVitals, history: [DailyMetrics] = [],
                           mealResponsePoints: [MealResponseIndex.Point] = [],
                           mealResponseZerosToday: Bool = false) -> [String: String] {
        func nowCard(_ value: Bool) -> String {
            guard vitals.at != nil else { return "EMPTY" }
            switch vitals.freshness {
            case .gone: return "GONE"
            case .stale: return value ? "STALE" : "EMPTY"
            case .fresh: return value ? "FRESH" : "EMPTY"
            }
        }
        let day = m.day, ticks = m.vitalsCurve
        let rolling = VitalSample.today(
            VitalSample.merging(history.flatMap(\.vitalsCurve), with: ticks),
            endingAt: Date())
        let steps = m.steps.map(Double.init) ?? VitalsMath.total(VitalsMath.hourSum(ticks, day: day, value: { $0.steps.map(Double.init) }))
        let metres = m.distanceM.map(Double.init) ?? VitalsMath.total(VitalsMath.hourSum(ticks, day: day, value: \.dis))
        let kcal = ActiveEnergyMath.totals(
            bmr: m.bmr, eActive: m.eActive, eTrain: m.eTrain, eOutNow: m.eOutNow).active
        let response = MealResponsePresentation.index(
            today: m, history: history, points: mealResponsePoints,
            zerosToday: mealResponseZerosToday)
        let battery: String = {
            switch m.bodyBatteryFreshness() {
            case .gone:  return m.bodyBatteryObservedAt == nil ? "EMPTY" : "GONE"
            case .stale: return "STALE"
            case .fresh: return m.bodyBattery != nil ? "FRESH" : "EMPTY"
            }
        }()
        return [
            "SLEEP": m.sleep == nil ? "EMPTY" : "FRESH",
            "HEART": nowCard(vitals.hr != nil || rolling.contains { $0.hr != nil }),
            "BODY_BATTERY": battery,
            "RESPONSE": response.analyticsState,
            "STRESS": nowCard(vitals.stress != nil || rolling.contains { $0.stress != nil }),
            // Which of the night-range states the card is actually in, not just whether a
            // tick arrived — LEARNING and a real verdict are different products.
            "TEMP": SkinTempPresentation.nightRange(today: m, history: history).analyticsState,
            "STEPS": steps == nil ? "EMPTY" : "FRESH",
            "DISTANCE": metres == nil ? "EMPTY" : "FRESH",
            "ACTIVE": kcal == nil ? "EMPTY" : "FRESH",
        ]
    }
}

/// 174-wide ACTIVE ENERGY card. Kept off `VitalsPage.body` so Home's type checker
/// does not have to solve the ledger arithmetic inside the eight-card grid.
struct ActiveEnergyCard: View {
    let m: DailyMetrics
    let height: CGFloat

    var body: some View {
        let model = snapshot
        return InstrumentCard(label: L("ACTIVE ENERGY"), tag: L("TODAY"), tint: NB.lime1,
                              height: height,
                              value: model.value, unit: "KCAL",
                              foot: model.foot,
                              spokenHint: model.hint) {
            LivedHourBars(hours: model.hours, tint: NB.lime1, height: 28)
        }
    }

    private var snapshot: (value: String?, foot: String, hint: String?, hours: [ActiveEnergyHour]) {
        let now = min(VitalsClock.now, min(m.asOf ?? VitalsClock.now, m.day.end))
        let samples = m.vitalsCurve
        let windows = ActiveEnergyModel.sportWindows(m)
        let split = ActiveEnergyMath.split(
            dayStart: m.day.start, now: now, bmr: m.bmr, bmrFull: m.bmrFull,
            eActive: m.eActive, eTrain: m.eTrain, eOutNow: m.eOutNow,
            ticks: samples, sportWindows: windows)
        let hours = ActiveEnergyMath.hourly(
            dayStart: m.day.start, now: now, split: split,
            ticks: samples, sportWindows: windows)
        let peak = ActiveEnergyMath.peakHour(hours)
        let kcal = split.active
        let foot = kcal == nil ? L("WAITING FOR VERIFIED ENERGY")
                               : L("%@ + %@ = %@",
                                   Fmt.kcal(split.resting),
                                   Fmt.kcal(split.active),
                                   Fmt.kcal(split.out))
        let hint = peak.map {
            L("PEAK %@ · %@ + %@ = %@",
              VitalsMath.clock(day: m.day, minute: $0.index * 60),
              Fmt.kcal(split.resting),
              Fmt.kcal(split.active),
              Fmt.kcal(split.out))
        }
        return (kcal.map { Fmt.kcal($0) }, foot, hint, hours)
    }
}

/// 04B rule 03 · a card is a label, a tag, a number, a chart and a foot. Only the tag, the
/// number and the chart take the card's colour; the rest stays the strip's own white-grey.
struct InstrumentCard<Chart: View>: View {
    let label: String
    let tag: String
    let tint: Color
    let value: String?
    let unit: String?
    let foot: String
    var dim: Double = 1
    /// 04B rule 01 · the strip's cards are the fixed 136; page two's cards grow into
    /// whatever height the phone leaves (VitalsPage.cardHeight).
    var height: CGFloat = NB.Layout.stripHeight
    /// 04B F3 · GONE: the number is —— but the unit stays, greyed with it. F1/F5 (never had
    /// data) hide the unit — there is nothing for it to measure yet.
    var unitWhenEmpty = false
    /// ADR 0008 · the numeral alone may take a colour of its own; the label, the tag and the
    /// card keep the metric's accent. F0 rule 01 governs a card's identity, not one number
    /// inside it — a card that changed colour nightly would read as a different object.
    var valueTint: Color? = nil
    /// 04B F1 / F5 · the two-line state foot. When set it replaces the chart and the foot:
    /// the first line names the state, the second says what happens next.
    var status: (line: String, sub: String)? = nil
    var spokenHint: String? = nil
    @ViewBuilder let chart: () -> Chart

    /// The page-two cards pass `height` right after `tint`, ahead of `value` — an explicit
    /// init keeps their call order while the stored order stays what the body reads.
    init(label: String, tag: String, tint: Color, height: CGFloat = NB.Layout.stripHeight,
         value: String?, unit: String?, foot: String, dim: Double = 1,
         unitWhenEmpty: Bool = false, valueTint: Color? = nil,
         status: (line: String, sub: String)? = nil,
         spokenHint: String? = nil,
         @ViewBuilder chart: @escaping () -> Chart) {
        self.label = label
        self.tag = tag
        self.tint = tint
        self.value = value
        self.unit = unit
        self.foot = foot
        self.dim = dim
        self.height = height
        self.unitWhenEmpty = unitWhenEmpty
        self.valueTint = valueTint
        self.status = status
        self.spokenHint = spokenHint
        self.chart = chart
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(label)
                        .font(NBFont.ui(500, 11)).tracking(0.2 * 11)
                        .foregroundStyle(NB.text3Prod)
                    Spacer(minLength: 0)
                    Text(tag)
                        .font(NBFont.dot(700, 12)).tracking(0.04 * 12)
                        .foregroundStyle(value == nil ? NB.text3Prod : tint)
                        .opacity(dim)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    // F2 rule 05 · a number that is not there is ——, never 0.
                    Text(value ?? Fmt.dash)
                        .font(NBFont.dot(700, 26)).tracking(-0.02 * 26)
                        .foregroundStyle(value == nil ? NB.text3Prod : (valueTint ?? tint))
                        .opacity(dim)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if let unit, value != nil || unitWhenEmpty {
                        Text(unit)
                            .font(NBFont.dot(500, 11))
                            .foregroundStyle(value == nil ? NB.text3Prod : NB.macroValue)
                            .opacity(dim)
                    }
                }
            }
            Spacer(minLength: 0)
            if let status {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.line)
                        .font(NBFont.dot(600, 10)).tracking(0.14 * 10)
                        .foregroundStyle(NB.white.opacity(0.55))
                    Text(status.sub)
                        .font(NBFont.dot(500, 10)).tracking(0.05 * 10)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(NB.macroValue)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    chart()
                        .frame(height: 28)
                        .opacity(dim)
                    Text(foot)
                        .font(NBFont.dot(500, 10)).tracking(0.05 * 10)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(NB.macroValue)
                }
            }
        }
        .padding(12)
        .frame(width: NB.Layout.cardWidth, height: height, alignment: .topLeading)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous).stroke(NB.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenHint.map { "\(label), \(tag), \($0)" } ?? "\(label), \(tag)")
        .accessibilityValue(status.map { "\($0.line), \($0.sub)" }
            ?? value.map { "\($0) \(unit ?? ""), \(foot)" } ?? "no data, \(foot)")
    }
}

// The eight cards press like the strip's cards (HotZoneTap, ADR-0001).

/// 04 · 04B · the two 4 pt page dots. The current page is the bright one.
struct PageDots: View {
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .fill(NB.white.opacity(i == current ? 0.72 : 0.24))
                    .frame(width: 4, height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: charts · 148 × 28 in the board, whatever the card's inner width is on device.

/// A day of one tick series, midnight → midnight across the width, y on a fixed scale — the ruler
/// never changes with the day (04B rule 04). A gap in the ticks is a dashed gap in the line,
/// never a straight segment across it; the last tick carries a dot.
struct DaySpark: View {
    let samples: [VitalSample]
    let day: UserDay
    let value: (VitalSample) -> Double?
    let low: Double
    let high: Double
    let tint: Color
    var range: VitalsTimelineRange? = nil

    var body: some View {
        Canvas { ctx, size in
            let span = max(0.001, high - low)
            func point(_ s: VitalSample, _ v: Double) -> CGPoint {
                let t = min(1, max(0, s.ts.timeIntervalSince(range?.start ?? day.start) / max(1, range?.span ?? 86_400)))
                let clamped = min(high, max(low, v))
                let y = size.height - 2 - (clamped - low) / span * (size.height - 4)
                return CGPoint(x: size.width * t, y: y)
            }
            var runs: [[CGPoint]] = []
            var run: [CGPoint] = []
            var lastTs: Date?
            for s in samples {
                guard let v = value(s) else { continue }
                // Two ticks more than ten minutes apart were not neighbours on the wrist.
                if let lastTs, s.ts.timeIntervalSince(lastTs) > 10 * 60, !run.isEmpty {
                    runs.append(run); run = []
                }
                run.append(point(s, v))
                lastTs = s.ts
            }
            if !run.isEmpty { runs.append(run) }
            guard !runs.isEmpty else { return }
            for (i, r) in runs.enumerated() {
                var p = Path()
                p.move(to: r[0])
                for pt in r.dropFirst() { p.addLine(to: pt) }
                if r.count == 1 { p.addLine(to: r[0]) }
                ctx.stroke(p, with: .color(tint.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if i + 1 < runs.count {
                    var gap = Path()
                    gap.move(to: r[r.count - 1]); gap.addLine(to: runs[i + 1][0])
                    ctx.stroke(gap, with: .color(tint.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1.2, dash: [2, 2.5]))
                }
            }
            if let end = runs.last?.last {
                ctx.fill(Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)),
                         with: .color(tint))
            }
        }
    }
}

/// 24 bars of an hour each across the day. The tallest hour is the bright one; a bin with no
/// ticks is left empty, never drawn as 0.
struct HourBars: View {
    let values: [Double?]
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, values.count)
            let gap: CGFloat = 2
            let w = (size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            let top = values.compactMap { $0 }.max() ?? 0
            guard top > 0 else { return }
            for (i, v) in values.enumerated() {
                guard let v, v > 0 else { continue }
                let h = max(0.8, size.height * v / top)
                let rect = CGRect(x: CGFloat(i) * (w + gap), y: size.height - h, width: w, height: h)
                ctx.fill(Path(rect), with: .color(tint.opacity(v >= top ? 1 : 0.4)))
            }
        }
    }
}

/// 48 half-hour bars, 2 wide. 04B · the bars over 60 are the same colour, only brighter —
/// intensity is not a semantic colour.
struct FineBars: View {
    let values: [Double?]
    let tint: Color
    let highlight: (Double) -> Bool

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, values.count)
            let gap: CGFloat = 1
            let w = (size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            for (i, v) in values.enumerated() {
                guard let v else { continue }
                let h = max(0.8, size.height * min(1, v / 100))
                let rect = CGRect(x: CGFloat(i) * (w + gap), y: size.height - h, width: w, height: h)
                ctx.fill(Path(rect), with: .color(tint.opacity(highlight(v) ? 1 : 0.4)))
            }
        }
    }
}

/// Seven nights, tonight brightest, a dashed line at the 14-night base. A night we do not
/// have is a missing bar; under five nights there is no base and no line (04B rule 06).
struct NightBars: View {
    let values: [Double?]
    let base: Double?
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            let present = values.compactMap { $0 }
            guard !present.isEmpty else { return }
            let lo = min(present.min()!, base ?? .infinity) - 8
            let hi = max(present.max()!, base ?? -.infinity) + 4
            let span = max(1, hi - lo)
            let w: CGFloat = 8, gap: CGFloat = 6
            let n = values.count
            func y(_ v: Double) -> CGFloat { size.height - CGFloat((v - lo) / span) * size.height }
            if let base {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(base)))
                line.addLine(to: CGPoint(x: CGFloat(n) * (w + gap) - gap, y: y(base)))
                ctx.stroke(line, with: .color(NB.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            for (i, v) in values.enumerated() {
                guard let v else { continue }
                let top = y(v)
                let rect = CGRect(x: CGFloat(i) * (w + gap), y: top, width: w, height: size.height - top)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(tint.opacity(i == n - 1 ? 1 : 0.35)))
            }
        }
    }
}

/// 04B rule 04 · the night as the band's own sleepLine: deep full height, light half, awake
/// a short mark, in the order the night ran — the app never re-segments it. Only a night
/// stored without a line falls back to the totals laid out in the order nights usually run.
struct SleepStrip: View {
    let sleep: SleepSummary
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            if !sleep.line.isEmpty {
                let hasOffsets = sleep.line.allSatisfy { $0.offsetMinutes != nil }
                let recordedSpan = sleep.wakeAt.flatMap { wake in sleep.sleepStart.map { wake.timeIntervalSince($0) / 60 } } ?? 0
                let total = max(1, hasOffsets ? max(recordedSpan, Double(sleep.line.map { ($0.offsetMinutes ?? 0) + $0.minutes }.max() ?? 0))
                    : Double(sleep.line.reduce(0) { $0 + $1.minutes }))
                var x: CGFloat = 0
                for run in sleep.line {
                    if hasOffsets { x = size.width * CGFloat(run.offsetMinutes ?? 0) / CGFloat(total) }
                    let w = size.width * CGFloat(run.minutes) / CGFloat(total)
                    // SDK stages: 0 deep, 1 light, 2 REM, 3 insomnia, 4 awake.
                    let (h, a): (CGFloat, Double) = switch run.stage {
                    case 0: (size.height, 0.95)
                    case 1, 2: (size.height * 16 / 28, 0.45)
                    default: (size.height * 7 / 28, 0.3)
                    }
                    let rect = CGRect(x: x, y: size.height - h, width: max(w, 0.8), height: h)
                    ctx.fill(Path(rect), with: .color(tint.opacity(a)))
                    x += w
                }
                return
            }
            // Fallback for nights stored before the line was kept: the night's proportions
            // laid out in the order nights usually run — deep early, light late.
            let total = Double(max(1, sleep.totalMinutes))
            let deep = Double(sleep.deepMinutes) / total
            let light = Double(sleep.lightMinutes) / total
            let wakes = max(0, min(sleep.wakeCount, 4))
            var segs: [(share: Double, h: CGFloat, alpha: Double)] = [
                (light * 0.2, 16, 0.45), (deep * 0.55, 28, 0.95), (light * 0.3, 16, 0.45),
                (deep * 0.45, 28, 0.95), (light * 0.5, 16, 0.45),
            ]
            let wakeShare = 0.018
            for k in 0..<wakes { segs.insert((wakeShare, 7, 0.3), at: min(segs.count, 2 + k * 2)) }
            let sum = segs.reduce(0) { $0 + $1.share }
            var x: CGFloat = 0
            for s in segs {
                let w = size.width * CGFloat(s.share / sum)
                let rect = CGRect(x: x, y: size.height - s.h, width: w, height: s.h)
                ctx.fill(Path(rect), with: .color(tint.opacity(s.alpha)))
                x += w
            }
        }
    }
}

/// The arithmetic behind the eight cards. Nothing here asks the band or the server.
enum VitalsMath {
    /// Sum of a per-tick value in each hour of the user day; hours with no ticks are nil.
    static func hourSum(_ samples: [VitalSample], day: UserDay, value: (VitalSample) -> Double?) -> [Double?] {
        var bins = [Double?](repeating: nil, count: 24)
        for s in samples {
            guard let v = value(s) else { continue }
            let i = Int(s.ts.timeIntervalSince(day.start) / 3600)
            guard (0..<24).contains(i) else { continue }
            bins[i] = (bins[i] ?? 0) + v
        }
        return bins
    }

    /// Sum into only the hours actually visible on a detail ruler. A current user day may be
    /// nine hours old, not 24; keeping 24 columns would put its newest bar under a future time.
    static func hourSum(_ samples: [VitalSample], range: VitalsTimelineRange,
                        value: (VitalSample) -> Double?) -> [Double?] {
        let count = max(1, Int(ceil(range.span / 3600)))
        var bins = [Double?](repeating: nil, count: count)
        for sample in samples {
            guard range.contains(sample.ts), let measured = value(sample) else { continue }
            let elapsed = max(0, sample.ts.timeIntervalSince(range.start))
            let index = min(count - 1, Int(elapsed / 3600))
            bins[index] = (bins[index] ?? 0) + measured
        }
        return bins
    }

    /// Mean of a per-tick value in each half hour; half hours with no ticks are nil.
    static func halfHourMean(_ samples: [VitalSample], day: UserDay, value: (VitalSample) -> Double?) -> [Double?] {
        var sum = [Double](repeating: 0, count: 48), n = [Int](repeating: 0, count: 48)
        for s in samples {
            guard let v = value(s) else { continue }
            let i = Int(s.ts.timeIntervalSince(day.start) / 1800)
            guard (0..<48).contains(i) else { continue }
            sum[i] += v; n[i] += 1
        }
        return (0..<48).map { n[$0] == 0 ? nil : sum[$0] / Double(n[$0]) }
    }

    static func halfHourMean(_ samples: [VitalSample], range: VitalsTimelineRange,
                             value: (VitalSample) -> Double?) -> [Double?] {
        let count = max(1, Int(ceil(range.span / 1800)))
        var sum = [Double](repeating: 0, count: count), n = [Int](repeating: 0, count: count)
        for sample in samples {
            guard range.contains(sample.ts), let measured = value(sample) else { continue }
            let elapsed = max(0, sample.ts.timeIntervalSince(range.start))
            let index = min(count - 1, Int(elapsed / 1800))
            sum[index] += measured
            n[index] += 1
        }
        return (0..<count).map { n[$0] == 0 ? nil : sum[$0] / Double(n[$0]) }
    }

    static func peak(_ bins: [Double?]) -> (index: Int, value: Double)? {
        var best: (Int, Double)?
        for (i, v) in bins.enumerated() { if let v, v > 0, best == nil || v > best!.1 { best = (i, v) } }
        return best.map { (index: $0.0, value: $0.1) }
    }

    static func total(_ bins: [Double?]) -> Double? {
        let present = bins.compactMap { $0 }
        return present.isEmpty ? nil : present.reduce(0, +)
    }

    /// "18:00" for a bin that starts `minute` minutes into the user day.
    static func clock(day: UserDay, minute: Int) -> String {
        Fmt.clock(day.start.addingTimeInterval(TimeInterval(minute * 60)))
    }

    /// "12 MIN AGO" under an hour, "2H 29M AGO" over it. Multiples of one minute, no seconds.
    static func age(of at: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(at) / 60))
        return minutes < 60 ? L("%d MIN AGO", minutes) : L("%@ AGO", Fmt.duration(minutes - minutes % 5))
    }

    /// 04B rule 04 · the minutes the band recorded nothing between two ticks that both
    /// exist. Two ticks ten minutes apart are neighbours; anything wider is a gap.
    static func offWrist(_ samples: [VitalSample]) -> (minutes: Int, from: Date)? {
        var minutes = 0
        var first: Date?
        var last: Date?
        for s in samples where s.hr != nil || s.stress != nil {
            if let last, s.ts.timeIntervalSince(last) > 10 * 60 {
                minutes += Int(s.ts.timeIntervalSince(last) / 60) - 5
                if first == nil { first = last }
            }
            last = s.ts
        }
        guard minutes > 0, let first else { return nil }
        return (minutes, first)
    }
}

/// One "now" for page two and the boards behind it. DEBUG seed can freeze the
/// clock with `NB_DEBUG_NOW` so a UITest and the charts agree.
enum VitalsClock {
    static var now: Date {
        #if DEBUG
        if Band.allowsSeed, let raw = ProcessInfo.processInfo.environment["NB_DEBUG_NOW"],
           let debugNow = ISO8601DateFormatter().date(from: raw) {
            return debugNow
        }
        #endif
        return Date()
    }
}
