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

    var contributorScores: [SleepScore] { scores.filter(\.usesContributors) }

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
        if score.usesContributors {
            SleepContributorBreakdown(score: score)
        } else {
            legacyBody
        }
    }

    private var legacyBody: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(SleepScoreGroup.allCases, id: \.self) { group in
                row(group)
            }
            Text(L(score.inputs["duration_score_cap"] == nil
                   ? "WEIGHTS ARE SHARES OF THIS SCORE; MISSING GROUPS ARE EXCLUDED"
                   : "WEIGHTS APPLY BEFORE THE DURATION LIMIT; MISSING GROUPS ARE EXCLUDED"))
                    .font(NBFont.dot(500, 9)).tracking(0.06 * 9)
                    .foregroundStyle(NB.text3Prod)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            if let cap = score.appliedDurationCap {
                Text(L("SHORT SLEEP · SCORE CAPPED AT %d", cap))
                    .font(NBFont.dot(500, 9)).tracking(0.06 * 9)
                    .foregroundStyle(NB.compareAmber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sleep.durationCap")
            }
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
            if score.inputs["bed_offset"] == nil { return L("NO BEDTIME RECORDED") }
            // The baseline is this person's own median bedtime; it exists from the third
            // prior night, so the note counts up to it instead of saying "not yet".
            return L("%d / %d NIGHTS", Int(score.inputs["baseline_bed_nights"] ?? 0), SleepScoreMath.regularityBaselineNights)
        }
        return score.effectiveWeight(of: group).map { L("WEIGHT %.1f%%", $0) } ?? Fmt.dash
    }
}

extension SleepScore {
    func effectiveWeight(of group: SleepScoreGroup) -> Double? {
        guard !usesContributors else { return nil }
        let groups = SleepScoreGroup.allCases
        let weights = SleepScoreMath.effectiveWeights(
            values: groups.map { value(of: $0).map(Double.init) },
            weights: groups.map { group in
                guard let weight = inputs["weight_\(group.rawValue)"],
                      weight.isFinite, weight > 0 else { return Double(group.weight) }
                return weight
            })
        guard let index = groups.firstIndex(of: group) else { return nil }
        return weights[index]
    }

    var appliedDurationCap: Int? {
        guard inputs["duration_cap_applied"] == 1,
              let cap = inputs["duration_score_cap"], cap.isFinite,
              (0...100).contains(cap) else { return nil }
        return Int(cap.rounded())
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
        if !summary.contributorScores.isEmpty {
            SleepContributorWindow(summary: summary)
        } else {
            legacyBody
        }
    }

    private var legacyBody: some View {
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

struct SleepContributorBreakdown: View {
    let score: SleepScore
    @State private var selected: SleepContributor?
    @State private var showsMethod = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(SleepContributor.allCases, id: \.self) { contributor in
                Button {
                    selected = contributor
                } label: {
                    SleepContributorRow(
                        title: contributor.title, value: measured(contributor),
                        score: score.contributorScore(contributor), showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sleep.contributor.\(contributor.rawValue)")
            }
            if let cap = score.appliedDurationCap {
                Text(L("SHORT SLEEP · SCORE CAPPED AT %d", cap))
                    .font(NBFont.dot(500, 10)).foregroundStyle(NB.compareAmber)
                    .accessibilityIdentifier("sleep.durationCap")
            }
            Button { showsMethod = true } label: {
                HStack {
                    Text(L("ABOUT THIS SLEEP SCORE")).font(NBFont.ui(500, 11))
                    Spacer()
                    Image(systemName: "info.circle").font(.system(size: 15))
                }
                .foregroundStyle(NB.text3Prod)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sleep.scoringInfo")
        }
        .sheet(item: $selected) { contributor in factorSheet(contributor) }
        .sheet(isPresented: $showsMethod) { methodSheet }
    }

    private func measured(_ contributor: SleepContributor, detailed: Bool = false) -> String {
        func number(_ key: String) -> Double? {
            guard let value = score.inputs[key], value.isFinite, value >= 0, value <= 100_000 else { return nil }
            return value
        }
        func duration(_ key: String) -> String {
            number(key).map { Fmt.duration(Int($0.rounded())) } ?? Fmt.dash
        }
        switch contributor {
        case .totalSleep: return duration("duration_min")
        case .efficiency:
            return number("efficiency_pct").map { String(format: "%.0f%%", $0) } ?? L("NOT MEASURED")
        case .restfulness:
            return score.contributorScore(contributor).map(SleepContributor.rating) ?? L("NOT MEASURED")
        case .rem, .deep:
            let key = contributor.rawValue
            guard number("\(key)_min") != nil else { return L("NOT MEASURED") }
            return duration("\(key)_min") + (number("\(key)_pct").map { String(format: " · %.0f%%", $0) } ?? "")
        case .latency: return L("NOT MEASURED")
        case .timing:
            if !detailed {
                return score.contributorScore(contributor).map(SleepContributor.rating) ?? L("NOT MEASURED")
            }
            guard let midpoint = number("midpoint_min"), midpoint < 1440 else { return L("NOT MEASURED") }
            return L("MIDPOINT %@", SleepScoreMath.bedClock(offset: midpoint - 1080))
        }
    }

    private func factorSheet(_ contributor: SleepContributor) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sheetHeader(contributor.title) { selected = nil }
                Text(measured(contributor, detailed: true))
                    .font(NBFont.dot(700, 28)).foregroundStyle(NB.white)
                if let value = score.contributorScore(contributor) {
                    HStack {
                        Text(SleepContributor.rating(value))
                        Spacer()
                        Text(L("%.0f OUT OF 100", value))
                    }
                    .font(NBFont.dot(600, 12)).foregroundStyle(SleepContributorRow.tint(value))
                }
                Text(contributor.explanation)
                    .font(NBFont.ui(400, 15)).foregroundStyle(NB.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(score.contributorWeight(contributor).map { L("WEIGHT %.1f%%", $0) }
                     ?? L("NOT MEASURED · EXCLUDED FROM SCORE"))
                    .font(NBFont.dot(500, 11)).foregroundStyle(NB.text3Prod)
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(NB.carbon)
        .preferredColorScheme(.dark)
    }

    private var methodSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sheetHeader(L("ABOUT THIS SLEEP SCORE")) { showsMethod = false }
                Text(L("NEXTBODY scoring inspired by Oura's public contributors, not Oura's proprietary formula. Missing factors are excluded and remaining weights are normalized."))
                    .font(NBFont.ui(400, 14)).foregroundStyle(NB.text2)
                    .fixedSize(horizontal: false, vertical: true)
                SleepContributorCoverage(score: score)
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(NB.carbon)
        .preferredColorScheme(.dark)
    }

    private func sheetHeader(_ title: String, close: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).font(NBFont.ui(600, 21)).foregroundStyle(NB.text1)
                .padding(.top, 8)
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(NB.text2).frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("CLOSE"))
            .accessibilityIdentifier("sleep.factor.close")
        }
    }
}

struct SleepContributorRow: View {
    let title: String
    let value: String
    let score: Double?
    var showsChevron = false

    static func tint(_ score: Double?) -> Color {
        guard let score else { return NB.text3Prod }
        switch score {
        case 85...: return NB.optimal2
        case 70..<85: return NB.violet1
        case 60..<70: return NB.compareAmber
        default: return NB.ember1
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(NBFont.ui(500, 14)).foregroundStyle(NB.text1)
                Spacer(minLength: 4)
                Text(value).font(NBFont.dot(600, 14)).foregroundStyle(readingTint)
                    .multilineTextAlignment(.trailing)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NB.text3Prod).frame(width: 12)
                        .fixedSize()
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(NB.barTrack)
                    if let score, score.isFinite {
                        Capsule().fill(readingTint)
                            .frame(width: geometry.size.width * CGFloat(min(100, max(0, score))) / 100)
                    }
                }
            }
            .frame(height: 4)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(score.map { L("%@ · %.0f OUT OF 100", SleepContributor.rating($0), $0) } ?? L("NOT MEASURED"))
    }

    private var readingTint: Color {
        guard let score else { return NB.text3Prod }
        return score < 70 ? NB.compareAmber : NB.white
    }
}

struct SleepContributorCoverage: View {
    let score: SleepScore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("%d OF 7 FACTORS SCORED", SleepContributor.allCases.filter { score.contributorScore($0) != nil }.count))
                .font(NBFont.dot(600, 11)).foregroundStyle(NB.text1)
            if score.inputs["duration_recorded"] != 1 {
                Text(L("Duration is reported or estimated, not fully measured time asleep."))
            }
            if let missing = score.inputs["unstaged_minutes"], missing.isFinite, missing > 0, missing <= 2880 {
                Text(L("%@ WITHOUT STAGES · EFFICIENCY AND RESTFULNESS EXCLUDED", Fmt.duration(Int(missing.rounded()))))
            }
            Text(L("Latency is unavailable. Efficiency covers recorded periods only; restfulness uses wake episodes only. Timing uses a population midpoint reference."))
            Text(L("Only recorded sleep is included. Unrecorded naps are not added. Heart rate, HRV, oxygen and respiration remain supporting measurements, not sleep-score factors."))
        }
        .font(NBFont.ui(400, 11)).foregroundStyle(NB.text3Prod)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SleepContributorWindow: View {
    let summary: SleepWindowSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(SleepContributor.allCases, id: \.self) { contributor in
                let values = summary.contributorScores.compactMap { $0.contributorScore(contributor) }
                let median = SleepScoreMath.median(values)
                VStack(alignment: .leading, spacing: 4) {
                    SleepContributorRow(title: contributor.title,
                                        value: median.map { String(Int($0.rounded())) } ?? L("NOT MEASURED"),
                                        score: median)
                    Text(L("%d OF %d NIGHTS MEASURED", values.count, summary.slots.count))
                        .font(NBFont.dot(500, 9)).foregroundStyle(NB.text3Prod)
                }
            }
            if summary.contributorScores.count != summary.scores.count {
                Text(L("LEGACY SCORES ARE SHOWN IN THE TREND, NOT MIXED INTO THE SEVEN FACTORS"))
                    .font(NBFont.ui(400, 10)).foregroundStyle(NB.compareAmber)
            }
            Text(L("FACTOR MEDIANS ARE SEPARATE; THE TOTAL IS THE MEDIAN OF NIGHTLY SCORES"))
                .font(NBFont.ui(400, 10)).foregroundStyle(NB.text3Prod)
        }
        .fixedSize(horizontal: false, vertical: true)
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

/// One night on the schedule: when the person fell asleep and when they woke, as minutes
/// past 18:00 local — `bed_offset`'s own ruler, which keeps a 23:40 and a 01:20 bedtime
/// 100 minutes apart. `wake` is on the same ruler and is always later than `bed`.
struct SleepScheduleNight: Identifiable {
    let day: UserDay
    let bed: Double?
    let wake: Double?
    var id: String { day.key }
    var isRecorded: Bool { bed != nil && wake != nil }

    /// The band's own window when the night was synced to this phone, else the settled
    /// score's bedtime plus its recorded minutes. A night with neither draws as a gap.
    init(day: UserDay, score: SleepScore?, summary: SleepSummary?) {
        self.day = day
        if let start = summary?.sleepStart, let end = summary?.wakeAt, end > start {
            let bed = Self.eveningOffset(start)
            self.bed = bed
            self.wake = bed + end.timeIntervalSince(start) / 60
        } else if let bed = score?.inputs["bed_offset"],
                  let minutes = score?.inputs[score?.usesContributors == true ? "sleep_elapsed_minutes" : "duration_min"],
                  bed.isFinite, minutes.isFinite, minutes > 0, minutes <= 2880 {
            self.bed = bed
            self.wake = bed + minutes
        } else {
            bed = nil
            wake = nil
        }
    }

    static func eveningOffset(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return Double(((minutes - 1080) % 1440 + 1440) % 1440)
    }
}

/// The regularity group's chart: a week of nights side by side, each a column from the
/// minute the person fell asleep down to the minute they woke, on one shared clock that
/// runs evening-to-morning top-to-bottom. Regularity is a *shape* — seven columns whose
/// tops line up are a regular week, a top that wanders is the irregular one — and a shape
/// is read in one look where a deviation number has to be decoded.
///
/// This person's usual bedtime is the band behind the columns (median ± the 30 minutes the
/// score gives full marks for), so a column top inside the band is a night that scored.
/// The rail carries the clock; nothing is printed over the columns.
struct SleepScheduleBars: View {
    let nights: [SleepScheduleNight]
    /// Median bedtime on the evening ruler — the line the score calls "usually". nil while
    /// the baseline is still being learned; the band is then simply not drawn.
    let baseline: Double?
    var tint: Color = NB.violet1
    var height: CGFloat = 176

    static let tolerance = 30.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VitalsChartProbe(
                series: .bins(probeBins),
                tint: tint,
                height: height,
                trailingInset: VitalsScaleRail.gutter,
                accessibilityTitle: L("SLEEP BY NIGHT"),
                accessibilityName: "vitals.probe.schedule"
            ) { _ in
                HStack(spacing: VitalsScaleRail.gap) {
                    GeometryReader { geo in
                        let count = max(nights.count, 1)
                        let spacing: CGFloat = nights.count > 10 ? 2 : 6
                        let width = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
                        let radius = min(width / 2, 6)
                        ZStack(alignment: .topLeading) {
                            habitBand(size: geo.size)
                            HStack(alignment: .top, spacing: spacing) {
                                ForEach(Array(nights.enumerated()), id: \.element.id) { index, night in
                                    column(night, last: index == nights.count - 1,
                                           width: width, radius: radius, fieldHeight: geo.size.height)
                                }
                            }
                        }
                    }
                    VitalsScaleRail(labels: railLabels, tint: tint)
                }
            }
            axis
        }
    }

    // MARK: the clock

    /// Evening at the top, morning at the bottom. The default 20:00–10:00 window covers a
    /// normal week; a shift worker's 04:00 bedtime or an 11:30 lie-in stretches it out to
    /// the next whole hour, so the night itself is never clipped.
    private var domain: (low: Double, high: Double) {
        var low = 120.0    // 20:00
        var high = 960.0   // 10:00
        for night in nights {
            if let bed = night.bed { low = min(low, bed - 30) }
            if let wake = night.wake { high = max(high, wake + 30) }
        }
        if let baseline {
            low = min(low, baseline - Self.tolerance - 15)
            high = max(high, baseline + Self.tolerance + 15)
        }
        low = (low / 60).rounded(.down) * 60
        high = (high / 60).rounded(.up) * 60
        return (low, max(high, low + 60))
    }

    private func y(_ offset: Double, in fieldHeight: CGFloat) -> CGFloat {
        let (low, high) = domain
        let fraction = (min(max(offset, low), high) - low) / (high - low)
        return fieldHeight * CGFloat(fraction)
    }

    private var railLabels: [String] {
        let (low, high) = domain
        return [low, (low + high) / 2, high].map { SleepScoreMath.bedClock(offset: $0) }
    }

    // MARK: the marks

    @ViewBuilder
    private func habitBand(size: CGSize) -> some View {
        if let baseline {
            let top = y(baseline - Self.tolerance, in: size.height)
            let bottom = y(baseline + Self.tolerance, in: size.height)
            Rectangle().fill(tint.opacity(0.16))
                .frame(width: size.width, height: max(1, bottom - top))
                .offset(y: top)
            Rectangle().fill(tint.opacity(0.7))
                .frame(width: size.width, height: 1)
                .offset(y: y(baseline, in: size.height))
        }
    }

    @ViewBuilder
    private func column(_ night: SleepScheduleNight, last: Bool,
                        width: CGFloat, radius: CGFloat, fieldHeight: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // A night not on record is a dotted slot at full height, so the reader can see
            // *which* night is missing instead of counting columns.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundStyle(NB.hairline)
                .opacity(night.isRecorded ? 0 : 1)
            if let bed = night.bed, let wake = night.wake {
                let top = y(bed, in: fieldHeight)
                let bottom = y(wake, in: fieldHeight)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(last ? tint : tint.opacity(0.55))
                    .frame(height: max(radius * 2, bottom - top))
                    .offset(y: top)
            }
        }
        .frame(width: width, height: fieldHeight)
    }

    /// One weekday under each column, in the column's own width, so a label sits under
    /// the night it names rather than spread across the field.
    private var axis: some View {
        HStack(spacing: 0) {
            ForEach(Array(nights.enumerated()), id: \.element.id) { index, night in
                Text(nights.count > 10 ? dayNumber(night) : Fmt.weekday(night.day.date))
                    .font(NBFont.ui(index == nights.count - 1 ? 500 : 400, 9))
                    .foregroundStyle(index == nights.count - 1 ? tint : NB.white.opacity(0.45))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    // A month is thirty slots; only every fifth date is printed.
                    .opacity(nights.count > 10 && index % 5 != nights.count % 5 - 1 && index != nights.count - 1 ? 0 : 1)
            }
        }
        .padding(.trailing, VitalsScaleRail.gutter)
        .accessibilityHidden(true)
    }

    private func dayNumber(_ night: SleepScheduleNight) -> String {
        String(Calendar.current.component(.day, from: night.day.date))
    }

    static func legend(baseline: Double?, tint: Color = NB.violet1) -> VitalsChartLegend {
        VitalsChartLegend(
            items: (baseline == nil ? [] : [.init(text: L("USUAL BEDTIME ±30 MIN"), tint: tint, isArea: true)])
                + [.init(text: L("ASLEEP → AWAKE"), tint: tint)],
            trailing: L("DOTTED · NOT RECORDED"),
            trailingTint: NB.white.opacity(0.45))
    }

    private var probeBins: [VitalsProbeMath.Bin] {
        let ranges = VitalsProbeMath.equalSlots(count: nights.count)
        let (low, high) = domain
        return zip(nights, ranges).map { night, range in
            let day = Calendar.current.component(.day, from: night.day.date)
            let clock = "\(Fmt.weekday(night.day.date)) \(day)"
            if let bed = night.bed, let wake = night.wake {
                return .init(
                    start: range.start,
                    end: range.end,
                    yFraction: (bed - low) / (high - low),
                    text: VitalsProbeCopy.ranges(
                        clock,
                        spans: [(SleepScoreMath.bedClock(offset: bed), SleepScoreMath.bedClock(offset: wake))],
                        unit: Fmt.duration(Int((wake - bed).rounded())))
                )
            }
            return .init(start: range.start, end: range.end, yFraction: nil,
                         text: VitalsProbeCopy.gap(clock), vacant: true)
        }
    }
}
