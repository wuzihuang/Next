import SwiftUI

/// ADR 0008 · the sleep board's three windows.
///
/// The windows are **rolling** — the last 1, 7 and 30 nights — not calendar weeks and
/// months. A natural week collapses to one bar every Monday morning, which reads as data
/// loss rather than as a Monday; and the data layer counts backwards from `user_day`
/// anyway, so rolling costs nothing.
///
/// ⚠️ RESPONSE now carries the same three pills (ADR 0012). The other six keep the window
/// `VitalsMetric.timeline` fixes for them, because "a week of steps" is a sum and "a week
/// of heart rate" is a distribution — different aggregations wearing one word. Sleep still
/// medians a night; RESPONSE means a week.
/// One slot on the multi-night chart: the day it belongs to and the score it settled, if any.
struct SleepNightSlot: Identifiable {
    let day: UserDay
    let score: SleepScore?
    var id: String { day.key }
}

/// Everything the week and month windows print, reduced from the slots once.
///
/// Medians, not means, throughout: one two-hour night on a wrist taken off at 01:00 drags a
/// mean far enough to be read as a bad week. The codebase already medians elsewhere for the
/// same reason — night HRV is a median of bucket medians.
struct SleepWindowSummary {
    let slots: [SleepNightSlot]
    let recorded: Int
    let score: Int?
    let weakest: SleepScoreGroup?
    let durationMinutes: Int?
    let deepPercent: Double?
    let lightPercent: Double?
    let remPercent: Double?
    let bedOffset: Double?
    let wakes: Double?

    init(slots: [SleepNightSlot]) {
        self.slots = slots
        let scored = slots.compactMap(\.score)
        recorded = scored.count
        score = Self.median(scored.map { Double($0.score) }).map { Int($0.rounded()) }

        // The one thing a median score cannot say by itself: which part is dragging.
        weakest = SleepScoreMath.weakest(SleepScoreGroup.allCases.map { group in
            (key: group, values: scored.compactMap { $0.value(of: group).map(Double.init) })
        })

        func input(_ key: String) -> Double? { Self.median(scored.compactMap { $0.inputs[key] }) }
        durationMinutes = input("duration_min").map { Int($0.rounded()) }
        deepPercent = input("deep_pct")
        lightPercent = input("light_pct")
        remPercent = input("rem_pct")
        bedOffset = input("bed_offset")
        wakes = input("wakes")
    }

    static func median(_ values: [Double]) -> Double? { SleepScoreMath.median(values) }

    var scores: [SleepScore] { slots.compactMap(\.score) }

    func groupMedian(_ group: SleepScoreGroup) -> Int? {
        Self.median(scores.compactMap { $0.value(of: group).map(Double.init) })
            .map { Int($0.rounded()) }
    }

    /// `bed_offset` is minutes past 18:00 local, which is how a 23:40 and a 01:20 bedtime
    /// stay 100 minutes apart instead of twenty-two hours.
    var bedClock: String? {
        guard let bedOffset else { return nil }
        return SleepScoreMath.bedClock(offset: bedOffset)
    }

    /// Stage proportions across the window, renormalised over the stages that were measured.
    /// REM drops out entirely on a run of nights the band filed no stage line for, rather
    /// than being drawn as a zero-width band nobody can tell from "you had no REM".
    var bands: [VitalsSplit.Band] {
        var raw: [(String, Color, Double)] = []
        if let deepPercent { raw.append((L("Deep"), NB.violet1, deepPercent)) }
        if let lightPercent { raw.append((L("Light"), NB.violet2, lightPercent)) }
        if let remPercent, remPercent > 0 { raw.append((L("REM"), NB.blue1, remPercent)) }
        guard raw.reduce(0, { $0 + $1.2 }) > 0 else { return [] }
        let shares = SleepScoreMath.renormalised(raw.map(\.2))
        return zip(raw, shares).map { entry, share in
            .init(name: entry.0, tint: entry.1, share: share,
                  detail: "\(Int(share.rounded()))%")
        }
    }
}

// MARK: - the chart

/// One bar a night, height by score, coloured by the score's own band. A night with no
/// record is a dotted slot at full height: the reader has to be able to see *which* night is
/// missing, and a chart that simply drew fewer bars cannot say that.
///
/// The rail carries the scale so nothing is printed in the field — 04's envelope-band
/// skeleton, the same one `VitalsHistogram` stands on. The score's domain is a fixed 0–100,
/// which is the one rail in vitals that never rescales.
struct SleepScoreBars: View {
    let slots: [SleepNightSlot]
    var tint: Color = NB.violet1
    var height: CGFloat = 160

    var body: some View {
        VitalsChartProbe(
            series: .bins(probeBins),
            tint: tint,
            height: height,
            trailingInset: VitalsScaleRail.gutter,
            accessibilityTitle: L("SLEEP SCORE BY NIGHT"),
            accessibilityName: "vitals.probe.score"
        ) { _ in
            HStack(spacing: VitalsScaleRail.gap) {
                GeometryReader { geo in
                    let count = max(slots.count, 1)
                    let spacing: CGFloat = slots.count > 10 ? 2 : 6
                    let width = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
                    // A month of nights is ~8pt a slot, so `width / 2` wins and the head is
                    // a true capsule. ⚠️ Capped for the week window, where a slot is 38pt
                    // and half of that would read as a pill rather than a column.
                    let radius = min(width / 2, 6)
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(slots) { slot in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: radius, style: .continuous)
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                                    .foregroundStyle(NB.hairline)
                                    .opacity(slot.score == nil ? 1 : 0)
                                if let score = slot.score {
                                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                                        .fill(score.tint)
                                        // The worst night on record still reads as a column
                                        // rather than as a scratch on the floor.
                                        .frame(height: max(radius * 2,
                                                           height * CGFloat(score.score) / 100))
                                }
                            }
                            .frame(width: width, height: height)
                        }
                    }
                }

                VitalsScaleRail(labels: ["100", "50", "0"], tint: tint)
            }
        }
    }

    /// What the colours mean, said under the field instead of keyed in it. The four bands
    /// are the score's own, so a violet month and a green month are readable as different
    /// months rather than as a palette.
    static var legend: VitalsChartLegend {
        VitalsChartLegend(
            items: [
                .init(text: L("80+"), tint: NB.optimal2),
                .init(text: L("60–79"), tint: NB.violet1),
                .init(text: L("40–59"), tint: NB.compareAmber),
                .init(text: L("UNDER 40"), tint: NB.ember1),
            ],
            trailing: L("DOTTED · NO SETTLED SCORE"),
            trailingTint: NB.white.opacity(0.45)
        )
    }

    private var probeBins: [VitalsProbeMath.Bin] {
        let ranges = VitalsProbeMath.equalSlots(count: slots.count)
        return zip(slots, ranges).map { slot, range in
            let day = Calendar.current.component(.day, from: slot.day.date)
            let clock = "\(Fmt.weekday(slot.day.date)) \(day)"
            if let score = slot.score {
                return .init(
                    start: range.start,
                    end: range.end,
                    yFraction: 1 - Double(score.score) / 100,
                    text: VitalsProbeCopy.line(clock, String(score.score))
                )
            }
            return .init(
                start: range.start,
                end: range.end,
                yFraction: nil,
                text: VitalsProbeCopy.gap(clock),
                vacant: true
            )
        }
    }
}

// MARK: - the breakdown

/// ADR 0008 · the score explains itself on the next screenful, not five cards down. Four
/// rows, one per group, each carrying its weight and — when the night was missing inputs —
/// how much of the group it actually got to see.
struct SleepScoreBreakdown: View {
    let score: SleepScore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(SleepScoreGroup.allCases, id: \.self) { group in
                row(group)
            }
            Text(L("WEIGHTS ARE SHARES OF THIS SCORE; MISSING GROUPS ARE EXCLUDED"))
                    .font(NBFont.dot(500, 9)).tracking(0.06 * 9)
                    .foregroundStyle(NB.text3Prod)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            SleepScoreCalibration(score: score)
        }
    }

    @ViewBuilder
    private func row(_ group: SleepScoreGroup) -> some View {
        let value = score.value(of: group)
        let present = group.memberKeys.filter { score.inputs[$0] != nil }.count
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(group.title)
                    .font(NBFont.ui(500, 10)).tracking(0.14 * 10)
                    .foregroundStyle(NB.text3Prod)
                    .frame(width: 84, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NB.barTrack)
                        if let value {
                            Capsule().fill(NB.violet1)
                                .frame(width: max(2, geo.size.width * CGFloat(value) / 100))
                        }
                    }
                }
                .frame(height: 6)
                Text(value.map(String.init) ?? Fmt.dash)
                    .font(NBFont.dot(700, 12))
                    .foregroundStyle(value == nil ? NB.text3Prod : NB.text1)
                    .frame(width: 26, alignment: .trailing)
                Text(note(group, value: value))
                    .font(NBFont.dot(500, 9)).tracking(0.05 * 9)
                    .foregroundStyle(NB.text3Prod)
                    .frame(width: 74, alignment: .trailing)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            // A group name alone says nothing — "recovery 52" is unreadable until the reader
            // knows recovery is HRV, resting heart rate, oxygen and breathing. The members
            // print with what was measured, and a member the night did not have prints ——,
            // which is also the only place the renormalisation becomes visible.
            Text(SleepInputLabel.line(for: group, inputs: score.inputs))
                .font(NBFont.dot(500, 9)).tracking(0.05 * 9)
                .foregroundStyle(NB.white.opacity(0.34))
                .lineLimit(2).minimumScaleFactor(0.8)
                .padding(.leading, 92)
            if value != nil, present < group.memberKeys.count {
                Text(L("%d OF %d INPUTS", present, group.memberKeys.count))
                    .font(NBFont.dot(500, 9)).foregroundStyle(NB.text3Prod)
                    .padding(.leading, 92)
            }
        }
    }

    /// A group that scored on fewer inputs than it has says so. This is the one place the
    /// missing-input note appears — the SLEEP card is glanced at, this page explains.
    private func note(_ group: SleepScoreGroup, value: Int?) -> String {
        if value == nil {
            guard group == .regularity else { return L("NOT SCORED") }
            return score.inputs["bed_offset"] == nil ? L("NO BEDTIME RECORDED") : L("NO BASELINE YET")
        }
        return score.effectiveWeight(of: group).map { L("WEIGHT %.1f%%", $0) } ?? Fmt.dash
    }
}

extension SleepScore {
    func effectiveWeight(of group: SleepScoreGroup) -> Double? {
        let groups = SleepScoreGroup.allCases
        let weights = SleepScoreMath.effectiveWeights(
            values: groups.map { value(of: $0).map(Double.init) },
            weights: groups.map { Double($0.weight) })
        guard let index = groups.firstIndex(of: group) else { return nil }
        return weights[index]
    }
}

struct SleepScoreCalibration: View {
    let score: SleepScore

    private var lines: [String] {
        let individual = [("hrv", L("HRV")), ("rhr", L("RESTING"))].compactMap { key, title -> String? in
            guard let weight = score.inputs["\(key)_personal_weight"], weight < 1 else { return nil }
            let nights = Int(score.inputs["baseline_\(key)_nights"] ?? 0)
            return L("%@ BASELINE · %d NIGHTS · %.0f%% PERSONAL", title, nights, weight * 100)
        }
        if score.inputs["hrv_personal_weight"] != nil || score.inputs["rhr_personal_weight"] != nil {
            return individual
        }
        guard score.isCalibrating else { return [] }
        return [L("BASELINE LEARNING · %d NIGHTS · %.0f%% PERSONAL",
                  Int(score.inputs["baseline_nights"] ?? 0), score.personalWeight * 100)]
    }

    var body: some View {
        ForEach(lines, id: \.self) { line in
            Text(line).font(NBFont.dot(500, 9)).foregroundStyle(NB.text3Prod)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SleepScoreCoverage: View {
    let score: SleepScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(["hrv", "rhr", "spo2", "respiration"], id: \.self) { key in
                let title = SleepInputLabel.title(key == "hrv" ? "hrv_ms" : key == "spo2" ? "spo2_min" : key)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(title).foregroundStyle(NB.text3Prod)
                        Spacer()
                        Text(score.inputs["\(key)_coverage"].map { L("%.1f%% OF SLEEP", $0 * 100) }
                             ?? L("COVERAGE NOT AVAILABLE"))
                            .foregroundStyle(NB.text1)
                    }
                    .font(NBFont.dot(600, 10))
                    Text(coverageDetail(key)).font(NBFont.dot(500, 9)).foregroundStyle(NB.text3Prod)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(L("ONLY MEASURED PORTIONS CONTRIBUTE; GAPS ARE NOT TREATED AS NORMAL"))
                .font(NBFont.dot(500, 9)).foregroundStyle(NB.text3Prod)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func coverageDetail(_ key: String) -> String {
        var parts: [String] = []
        if let count = score.inputs["\(key)_sample_count"] {
            parts.append(L("%d READINGS", Int(count)))
        }
        if let minutes = score.inputs["\(key)_expected_minutes"] {
            parts.append(L("RECORDED SLEEP %@", Fmt.duration(Int(minutes.rounded()))))
        }
        if let gap = score.inputs["\(key)_longest_gap_min"] {
            parts.append(L("LONGEST GAP %@", Fmt.duration(Int(gap.rounded()))))
        }
        return parts.isEmpty ? L("THIS SCORE HAS NO COVERAGE DETAILS") : parts.joined(separator: " · ")
    }
}

/// Group medians explain a window without pretending their weighted sum is its median total.
struct SleepWindowBreakdown: View {
    let summary: SleepWindowSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(SleepScoreGroup.allCases, id: \.self) { group in
                let scored = summary.scores.filter { $0.value(of: group) != nil }
                let complete = scored.filter { score in group.memberKeys.allSatisfy { score.inputs[$0] != nil } }.count
                let weights = scored.compactMap { $0.effectiveWeight(of: group) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(group.title).font(NBFont.ui(500, 10)).foregroundStyle(NB.text3Prod)
                        Spacer()
                        Text(summary.groupMedian(group).map(String.init) ?? Fmt.dash)
                            .font(NBFont.dot(700, 14)).foregroundStyle(NB.violet1)
                    }
                    Text(L("SCORED %d OF %d NIGHTS · COMPLETE INPUTS %d", scored.count, summary.slots.count, complete))
                        .font(NBFont.dot(500, 9)).foregroundStyle(NB.text3Prod)
                        .fixedSize(horizontal: false, vertical: true)
                    if let low = weights.min(), let high = weights.max() {
                        Text(low == high ? L("WEIGHT %.1f%%", low) : L("WEIGHT %.1f–%.1f%% BY NIGHT", low, high))
                            .font(NBFont.dot(500, 9)).foregroundStyle(NB.text3Prod)
                    }
                }
            }
            let calibrating = summary.scores.filter { score in
                (score.inputs["hrv_personal_weight"] ?? score.personalWeight) < 1 ||
                (score.inputs["rhr_personal_weight"] ?? score.personalWeight) < 1
            }.count
            Text(L("%d NIGHTS STILL LEARNING PERSONAL BASELINES", calibrating))
                .font(NBFont.dot(500, 9)).foregroundStyle(NB.text3Prod)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("GROUP MEDIANS ARE SHOWN SEPARATELY; THE TOTAL IS THE MEDIAN OF NIGHTLY SCORES"))
                .font(NBFont.dot(500, 9)).foregroundStyle(NB.text3Prod)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}


// MARK: - what a group is made of

/// ADR 0008 · the names and measured values behind each group. The score is only defensible
/// if the page can say what went into it, and a member the night never recorded prints —— so
/// that "scored on 2 of 4" is visible as well as stated.
enum SleepInputLabel {
    static func line(for group: SleepScoreGroup, inputs: [String: Double]) -> String {
        group.memberKeys.map { key in
            "\(title(key)) \(inputs[key].map { value(key, $0) } ?? Fmt.dash)"
        }.joined(separator: " · ")
    }

    static func title(_ key: String) -> String {
        switch key {
        case "duration_min": L("TOTAL")
        case "deep_pct":     L("DEEP")
        case "rem_pct":      L("REM")
        case "wakes":        L("WAKES")
        case "hrv_ms":       L("HRV")
        case "rhr":          L("RESTING")
        case "spo2_min":     L("SPO2 MIN")
        case "respiration":  L("RESP")
        case "bed_offset":   L("BEDTIME")
        default:             key
        }
    }

    static func value(_ key: String, _ measured: Double) -> String {
        switch key {
        case "duration_min": Fmt.duration(Int(measured))
        case "deep_pct", "rem_pct", "spo2_min": "\(Int(measured.rounded()))%"
        case "wakes":        "\(Int(measured.rounded()))"
        case "hrv_ms":       "\(Int(measured.rounded()))MS"
        case "rhr":          "\(Int(measured.rounded()))"
        case "respiration":  "\(Int(measured.rounded()))/MIN"
        case "bed_offset":   SleepScoreMath.bedClock(offset: measured)
        default:             "\(Int(measured.rounded()))"
        }
    }
}

// MARK: - a section of the board

/// One of the score's four groups, used as a heading for the charts that feed it. The page
/// is organised by what the score is made of rather than by what the band happens to store,
/// so a reader who wants to know why recovery scored 52 scrolls to RECOVERY and finds the
/// four traces underneath it.
struct SleepSectionHeader: View {
    let group: SleepScoreGroup
    let score: Int?
    var effectiveWeight: Double? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(group.title)
                .font(NBFont.ui(600, 13)).tracking(0.18 * 13)
                .foregroundStyle(NB.text1)
            Rectangle().fill(NB.hairline).frame(height: 1)
            Text(score.map(String.init) ?? Fmt.dash)
                .font(NBFont.dot(700, 13))
                .foregroundStyle(score == nil ? NB.text3Prod : NB.violet1)
            Text(effectiveWeight.map { L("WEIGHT %.1f%%", $0) } ?? L("NOT SCORED"))
                .font(NBFont.dot(500, 9)).tracking(0.05 * 9)
                .foregroundStyle(NB.text3Prod)
        }
        .padding(.top, 4)
    }
}

// MARK: - duration

/// The only chart DURATION can honestly have: the night against the line it is scored on.
/// A number beside a full-marks mark answers "why 74" in one look, which a bare 7H 12M
/// cannot. Stages are deliberately not drawn here — they score under STRUCTURE, and putting
/// the hypnogram under DURATION would suggest deep sleep moved this number.
struct SleepDurationBar: View {
    let minutes: Int
    /// 7.5h earns full marks and 9.5h is where the mild oversleep penalty starts.
    static let fullFrom = 450.0
    static let fullTo = 570.0
    private static let scale = 720.0   // twelve hours of track

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(NB.barTrack)
                    // The full-marks band, drawn behind the night so the night sits in or out of it.
                    Rectangle().fill(NB.optimal2.opacity(0.16))
                        .frame(width: w * (Self.fullTo - Self.fullFrom) / Self.scale)
                        .offset(x: w * Self.fullFrom / Self.scale)
                    Capsule().fill(NB.violet1)
                        .frame(width: max(3, w * min(Double(minutes), Self.scale) / Self.scale))
                    Rectangle().fill(NB.optimal2)
                        .frame(width: 1.5)
                        .offset(x: w * Self.fullFrom / Self.scale)
                }
            }
            .frame(height: 14)
            HStack(spacing: 0) {
                Text(Fmt.duration(minutes))
                    .font(NBFont.dot(700, 11)).foregroundStyle(NB.violet1)
                Spacer(minLength: 0)
                Text(L("FULL MARKS FROM %@", Fmt.duration(Int(Self.fullFrom))))
                    .font(NBFont.dot(500, 9)).tracking(0.05 * 9)
                    .foregroundStyle(NB.text3Prod)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("TOTAL"))
        .accessibilityValue(Fmt.duration(minutes))
    }
}

// MARK: - regularity

/// The exact baseline returned with the score and its full-marks tolerance.
/// The axis extends to include the night, including daytime or cross-evening sleep.
struct SleepBedtimeBox: View {
    let baseline: Double
    let tonight: Double
    var height: CGFloat = 72

    private var deviation: Double { SleepScoreMath.bedtimeDeviation(bedtime: tonight, baseline: baseline) }
    private var lower: Double { min(-60, deviation - 30) }
    private var upper: Double { max(60, deviation + 30) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { ctx, size in
                let mid = size.height / 2
                func x(_ offset: Double) -> CGFloat {
                    size.width * (offset - lower) / (upper - lower)
                }
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: mid - 5, width: size.width, height: 10),
                              cornerRadius: 5), with: .color(NB.barTrack))
                ctx.fill(Path(roundedRect: CGRect(x: x(-30), y: mid - 11,
                                                  width: x(30) - x(-30), height: 22), cornerRadius: 6),
                         with: .color(NB.violet1.opacity(0.38)))
                var median = Path()
                median.move(to: CGPoint(x: x(0), y: mid - 13))
                median.addLine(to: CGPoint(x: x(0), y: mid + 13))
                ctx.stroke(median, with: .color(NB.violet1), lineWidth: 2)
                ctx.fill(Path(ellipseIn: CGRect(x: x(deviation) - 5, y: mid - 5, width: 10, height: 10)),
                         with: .color(NB.violet1))
            }
            .frame(height: height)
            HStack {
                Text(SleepScoreMath.bedClock(offset: baseline + lower))
                Spacer()
                Text(SleepScoreMath.bedClock(offset: baseline + (lower + upper) / 2))
                Spacer()
                Text(SleepScoreMath.bedClock(offset: baseline + upper))
            }
            .font(NBFont.dot(500, 9)).foregroundStyle(NB.text3Prod)
            VitalsChartLegend(
                items: [
                    .init(text: L("WITHIN 30 MIN OF BASELINE"), tint: NB.violet1, isArea: true),
                    .init(text: L("LAST NIGHT"), tint: NB.violet1),
                ], trailing: nil)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("BEDTIME"))
        .accessibilityValue(L("%@ · USUALLY %@", SleepScoreMath.bedClock(offset: tonight),
                              SleepScoreMath.bedClock(offset: baseline)))
    }
}
