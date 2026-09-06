import XCTest
@testable import NextBodySleepCore

final class VitalsProbeMathTests: XCTestCase {

    // MARK: - nearest point

    func testNearestPointSnapsOntoTheSampleNotTheFinger() {
        let points = [
            VitalsProbeMath.Point(fraction: 0.20, yFraction: 0.4, text: "A"),
            VitalsProbeMath.Point(fraction: 0.80, yFraction: 0.6, text: "B"),
        ]
        let pick = VitalsProbeMath.pickPoint(finger: 0.22, points: points, maxFraction: 0.10)
        XCTAssertEqual(pick.marker, 0.20)
        XCTAssertEqual(pick.text, "A")
        XCTAssertEqual(pick.yFraction, 0.4)
        XCTAssertEqual(pick.identity, "p:0")
        XCTAssertTrue(pick.snaps)
    }

    func testAFingerInAGapDoesNotBorrowTheNeighbour() {
        let points = [
            VitalsProbeMath.Point(fraction: 0.10, text: "A"),
            VitalsProbeMath.Point(fraction: 0.90, text: "B"),
        ]
        let pick = VitalsProbeMath.pickPoint(finger: 0.50, points: points, maxFraction: 0.10)
        XCTAssertEqual(pick.marker, 0.50)
        XCTAssertNil(pick.text)
        XCTAssertEqual(pick.identity, "gap")
        XCTAssertFalse(pick.snaps)
    }

    func testEmptyPointsAreAGapAtTheFinger() {
        let pick = VitalsProbeMath.pickPoint(finger: 0.3, points: [], maxFraction: 0.1)
        XCTAssertEqual(pick.marker, 0.3)
        XCTAssertNil(pick.text)
        XCTAssertFalse(pick.snaps)
    }

    func testFingerOutsideTheFieldClampsBeforePicking() {
        let points = [VitalsProbeMath.Point(fraction: 0, text: "left"),
                      VitalsProbeMath.Point(fraction: 1, text: "right")]
        let left = VitalsProbeMath.pickPoint(finger: -4, points: points, maxFraction: 0.1)
        assertPick(left, marker: 0, text: "left", identity: "p:0")
        let right = VitalsProbeMath.pickPoint(finger: 8, points: points, maxFraction: 0.1)
        assertPick(right, marker: 1, text: "right", identity: "p:1")
    }

    func testEqualDistancePrefersTheLaterSample() {
        let points = [
            VitalsProbeMath.Point(fraction: 0.25, text: "earlier"),
            VitalsProbeMath.Point(fraction: 0.75, text: "later"),
        ]
        let pick = VitalsProbeMath.pickPoint(finger: 0.50, points: points, maxFraction: 0.50)
        XCTAssertEqual(pick.text, "later")
        XCTAssertEqual(pick.identity, "p:1")
    }

    func testPointIdentityIsTheIndexNotTheFloat() {
        let points = [
            VitalsProbeMath.Point(fraction: 1.0 / 3.0, text: "a"),
            VitalsProbeMath.Point(fraction: 2.0 / 3.0, text: "b"),
        ]
        let pick = VitalsProbeMath.pickPoint(finger: 0.34, points: points, maxFraction: 0.1)
        XCTAssertEqual(pick.identity, "p:0")
        XCTAssertNotEqual(pick.identity, "p:\(points[0].fraction)")
    }

    func testFiveMinuteNeighboursOnA24HourWindowSnap() {
        let span: TimeInterval = 24 * 3600
        let gap = VitalsProbeMath.gapFraction(span: span)
        let tick: Double = 300 / span
        let points = [
            VitalsProbeMath.Point(fraction: 0.40, text: "noon"),
            VitalsProbeMath.Point(fraction: 0.40 + tick, text: "five later"),
        ]
        let mid = VitalsProbeMath.pickPoint(
            finger: 0.40 + tick / 2, points: points, maxFraction: gap)
        assertPick(mid, marker: 0.40 + tick, text: "five later", identity: "p:1")
    }

    func testAFifteenMinuteHoleOnA24HourWindowIsAGap() {
        let span: TimeInterval = 24 * 3600
        let gap = VitalsProbeMath.gapFraction(span: span)
        let points = [
            VitalsProbeMath.Point(fraction: 12 * 3600 / span, text: "12:00"),
            VitalsProbeMath.Point(fraction: 14 * 3600 / span, text: "14:00"),
        ]
        let pick = VitalsProbeMath.pickPoint(finger: 13 * 3600 / span, points: points, maxFraction: gap)
        XCTAssertEqual(pick.identity, "gap")
        XCTAssertNil(pick.text)
        XCTAssertEqual(pick.marker, 13 * 3600 / span, accuracy: 1e-12)
    }

    // MARK: - bins

    func testBinLandsOnTheHourThatContainsTheFinger() {
        let bins = [
            VitalsProbeMath.Bin(start: 0, end: 0.5, yFraction: 0.2, text: "first", vacant: false),
            VitalsProbeMath.Bin(start: 0.5, end: 1, yFraction: nil, text: "empty", vacant: true),
        ]
        let first = VitalsProbeMath.pickBin(finger: 0.1, bins: bins)
        XCTAssertEqual(first.marker, 0.25)
        XCTAssertEqual(first.text, "first")
        XCTAssertEqual(first.yFraction, 0.2)

        let vacant = VitalsProbeMath.pickBin(finger: 0.8, bins: bins)
        XCTAssertEqual(vacant.marker, 0.75)
        XCTAssertEqual(vacant.text, "empty")
        XCTAssertNil(vacant.yFraction)
        XCTAssertEqual(vacant.identity, "b:0.5")
        XCTAssertTrue(vacant.snaps)
    }

    func testLastBinIncludesTheRightEdge() {
        let bins = [VitalsProbeMath.Bin(start: 0, end: 1, text: "only")]
        let pick = VitalsProbeMath.pickBin(finger: 1, bins: bins)
        XCTAssertEqual(pick.text, "only")
    }

    func testAHoleBetweenBinsIsAGapNotTheLastBin() {
        let bins = [
            VitalsProbeMath.Bin(start: 0, end: 0.3, text: "left"),
            VitalsProbeMath.Bin(start: 0.7, end: 1, text: "right"),
        ]
        let pick = VitalsProbeMath.pickBin(finger: 0.5, bins: bins)
        XCTAssertEqual(pick.identity, "gap")
        XCTAssertEqual(pick.marker, 0.5)
        XCTAssertNil(pick.text)
        XCTAssertFalse(pick.snaps)
    }

    func testEmptyBinsAreAGap() {
        let pick = VitalsProbeMath.pickBin(finger: 0.4, bins: [])
        XCTAssertEqual(pick.identity, "gap")
        XCTAssertEqual(pick.marker, 0.4)
    }

    func testVacantHourIsNamedAndDoesNotBorrowANeighbour() {
        let bins = hourBins([120, nil, 80], span: 3 * 3600)
        XCTAssertTrue(bins[1].vacant)
        XCTAssertEqual(bins[1].text, VitalsProbeMath.gap("01:00"))
        let pick = VitalsProbeMath.pickBin(finger: 0.4, bins: bins)
        XCTAssertEqual(pick.text, VitalsProbeMath.gap("01:00"))
        XCTAssertNil(pick.yFraction)
        XCTAssertNotEqual(pick.text, bins[0].text)
    }

    func testAZeroHourIsVacantTheSameAsAMissingHour() {
        XCTAssertTrue(VitalsProbeMath.isVacantHour(nil))
        XCTAssertTrue(VitalsProbeMath.isVacantHour(0))
        XCTAssertTrue(VitalsProbeMath.isVacantHour(-3))
        XCTAssertFalse(VitalsProbeMath.isVacantHour(1))
    }

    // MARK: - runs

    func testRunKeepsTheMarkerOnTheFinger() {
        let runs = [
            VitalsProbeMath.Run(start: 0, end: 0.4, yFraction: 0.8, text: "DEEP"),
            VitalsProbeMath.Run(start: 0.4, end: 1, yFraction: 0.2, text: "AWAKE"),
        ]
        let pick = VitalsProbeMath.pickRun(finger: 0.25, runs: runs)
        XCTAssertEqual(pick.marker, 0.25)
        XCTAssertEqual(pick.text, "DEEP")
        XCTAssertEqual(pick.yFraction, 0.8)
    }

    func testAFingerOnARunBoundaryBelongsToTheNextRun() {
        let runs = [
            VitalsProbeMath.Run(start: 0, end: 0.4, text: "DEEP"),
            VitalsProbeMath.Run(start: 0.4, end: 1, text: "LIGHT"),
        ]
        let pick = VitalsProbeMath.pickRun(finger: 0.4, runs: runs)
        XCTAssertEqual(pick.text, "LIGHT")
        XCTAssertEqual(pick.marker, 0.4)
        XCTAssertEqual(pick.identity, "r:0.4")
    }

    func testAFingerPastEveryRunIsAGap() {
        let runs = [VitalsProbeMath.Run(start: 0.1, end: 0.4, text: "DEEP")]
        let pick = VitalsProbeMath.pickRun(finger: 0.8, runs: runs)
        XCTAssertNil(pick.text)
        XCTAssertEqual(pick.marker, 0.8)
    }

    func testLastRunIncludesTheRightEdge() {
        let runs = [
            VitalsProbeMath.Run(start: 0, end: 0.5, text: "DEEP"),
            VitalsProbeMath.Run(start: 0.5, end: 1, text: "LIGHT"),
        ]
        XCTAssertEqual(VitalsProbeMath.pickRun(finger: 1, runs: runs).text, "LIGHT")
    }

    // MARK: - rulers and gaps

    func testGapFractionIsFiveMinutesOfTheWindow() {
        XCTAssertEqual(VitalsProbeMath.gapFraction(span: 24 * 3600), 5 * 60 / (24 * 3600))
        XCTAssertEqual(VitalsProbeMath.gapFraction(span: 7 * 3600), 5 * 60 / (7 * 3600))
        XCTAssertEqual(VitalsProbeMath.gapFraction(span: 0), 0.5)
    }

    func testYFractionPutsTheHighOnTop() {
        XCTAssertEqual(VitalsProbeMath.yFraction(value: 160, low: 40, high: 160), 0)
        XCTAssertEqual(VitalsProbeMath.yFraction(value: 40, low: 40, high: 160), 1)
        XCTAssertEqual(VitalsProbeMath.yFraction(value: 100, low: 40, high: 160), 0.5, accuracy: 1e-12)
    }

    func testYFractionClampsPastTheRuler() {
        XCTAssertEqual(VitalsProbeMath.yFraction(value: 200, low: 40, high: 160), 0)
        XCTAssertEqual(VitalsProbeMath.yFraction(value: 0, low: 40, high: 160), 1)
    }

    // MARK: - copy

    func testLineJoinsTimeAndValue() {
        XCTAssertEqual(VitalsProbeMath.line("14:32", "72 BPM"), "14:32 · 72 BPM")
        XCTAssertEqual(VitalsProbeMath.line("14:00", "1,420"), "14:00 · 1,420")
        XCTAssertEqual(VitalsProbeMath.line("02:14", "DEEP"), "02:14 · DEEP")
        XCTAssertEqual(VitalsProbeMath.line("MON 8", "78"), "MON 8 · 78")
    }

    func testGapCopyUsesTheEmDash() {
        XCTAssertEqual(VitalsProbeMath.dash, "——")
        XCTAssertEqual(VitalsProbeMath.gap("14:32"), "14:32 · ——")
    }

    func testReadoutPrefersThePickThenIdleThenTheGap() {
        let pick = VitalsProbeMath.Pick(marker: 0.2, yFraction: 0.4, text: "14:32 · 72 BPM",
                                        identity: "p:0", snaps: true)
        XCTAssertEqual(VitalsProbeMath.readout(pick: pick, idle: "NOW · 80 BPM", gap: "14:00 · ——"),
                       "14:32 · 72 BPM")

        let gapPick = VitalsProbeMath.Pick(marker: 0.5, yFraction: nil, text: nil,
                                           identity: "gap", snaps: false)
        XCTAssertEqual(VitalsProbeMath.readout(pick: gapPick, idle: "NOW · 80 BPM", gap: "14:32 · ——"),
                       "14:32 · ——")

        XCTAssertEqual(VitalsProbeMath.readout(pick: nil, idle: "NOW · 80 BPM", gap: "NOW · ——"),
                       "NOW · 80 BPM")
        XCTAssertEqual(VitalsProbeMath.readout(pick: nil, idle: nil, gap: "NOW · ——"),
                       "NOW · ——")
    }

    // MARK: - series idle / voiceover

    func testIdleOnPointsIsTheLastSample() {
        let series = VitalsProbeMath.Series.points([
            .init(fraction: 0.2, text: "first"),
            .init(fraction: 0.9, text: "last"),
        ])
        XCTAssertEqual(series.idleText, "last")
    }

    func testIdleOnBinsSkipsATrailingVacantHour() {
        let series = VitalsProbeMath.Series.bins([
            .init(start: 0, end: 0.5, text: "filled"),
            .init(start: 0.5, end: 1, text: "——", vacant: true),
        ])
        XCTAssertEqual(series.idleText, "filled")
    }

    func testIdleOnAllVacantBinsStillNamesTheLastSlot() {
        let series = VitalsProbeMath.Series.bins([
            .init(start: 0, end: 1, text: "MON 8 · ——", vacant: true),
        ])
        XCTAssertEqual(series.idleText, "MON 8 · ——")
    }

    func testIdleOnRunsIsTheLastRun() {
        let series = VitalsProbeMath.Series.runs([
            .init(start: 0, end: 0.4, text: "DEEP"),
            .init(start: 0.4, end: 1, text: "AWAKE"),
        ])
        XCTAssertEqual(series.idleText, "AWAKE")
    }

    func testVoiceOverItemsSharePickIdentities() {
        let series = VitalsProbeMath.Series.points([
            .init(fraction: 0.2, text: "A"),
            .init(fraction: 0.8, text: "B"),
        ])
        let items = series.voItems
        let picked = series.pick(finger: 0.21, gapFraction: 0.1)
        XCTAssertEqual(items[0].identity, picked.identity)
        XCTAssertEqual(items[0].text, "A")
        XCTAssertEqual(items[1].identity, "p:1")
    }

    func testVoiceOverStartsAtTheLastSampleAndStepsBack() {
        let items = VitalsProbeMath.Series.points([
            .init(fraction: 0.2, text: "A"),
            .init(fraction: 0.5, text: "B"),
            .init(fraction: 0.9, text: "C"),
        ]).voItems
        let idle = VitalsProbeMath.voStep(items: items, currentIdentity: nil, increment: false)
        XCTAssertEqual(idle?.text, "B")
        let first = VitalsProbeMath.voStep(items: items, currentIdentity: idle?.identity, increment: false)
        XCTAssertEqual(first?.text, "A")
        let stillFirst = VitalsProbeMath.voStep(items: items, currentIdentity: first?.identity, increment: false)
        XCTAssertEqual(stillFirst?.text, "A")
        let last = VitalsProbeMath.voStep(items: items, currentIdentity: items[2].identity, increment: true)
        XCTAssertEqual(last?.text, "C")
    }

    func testVoiceOverOfNothingIsNothing() {
        XCTAssertNil(VitalsProbeMath.voStep(items: [], currentIdentity: nil, increment: true))
    }

    func testLiftIsIdleBecauseANilPickReadsTheIdleText() {
        let series = VitalsProbeMath.Series.points([
            .init(fraction: 0.1, text: "14:00 · 70 BPM"),
            .init(fraction: 0.9, text: "NOW · 80 BPM"),
        ])
        let probing = series.pick(finger: 0.1, gapFraction: 0.2)
        XCTAssertEqual(VitalsProbeMath.readout(pick: probing, idle: series.idleText, gap: "——"),
                       "14:00 · 70 BPM")
        XCTAssertEqual(VitalsProbeMath.readout(pick: nil, idle: series.idleText, gap: "——"),
                       "NOW · 80 BPM")
    }

    // MARK: - hour / night layout

    func testHourSlotsTileANineHourUserDay() {
        let slots = VitalsProbeMath.hourSlots(count: 24, span: 9 * 3600)
        XCTAssertEqual(slots.count, 9)
        XCTAssertEqual(slots.first?.start, 0)
        XCTAssertEqual(slots.last?.end, 1)
        XCTAssertEqual(slots[0].end, slots[1].start)
    }

    func testHourSlotsOnAnExactDayCoverTwentyFourHours() {
        let slots = VitalsProbeMath.hourSlots(count: 24, span: 24 * 3600)
        XCTAssertEqual(slots.count, 24)
        XCTAssertEqual(slots[0].start, 0)
        XCTAssertEqual(slots[23].end, 1)
        XCTAssertEqual(slots[13].index, 13)
    }

    func testAZeroSpanHasNoHourSlots() {
        XCTAssertTrue(VitalsProbeMath.hourSlots(count: 24, span: 0).isEmpty)
        XCTAssertNil(VitalsProbeMath.hourSlot(index: 0, span: 0))
    }

    func testHalfHourSlotsTileARolling24HourWindow() {
        let slots = VitalsProbeMath.timeSlots(seconds: 30 * 60, span: 24 * 3600)
        XCTAssertEqual(slots.count, 48)
        XCTAssertEqual(slots[0].start, 0)
        XCTAssertEqual(slots[47].end, 1)
        XCTAssertEqual(slots[0].end, slots[1].start)
    }

    func testAWindowThatDoesNotDivideKeepsAShortLastSlot() {
        // 7h10m of a user day: fourteen full half hours and a ten-minute tail. The tail is
        // a slot the band really reported into, so rounding it away would drop its ticks.
        let slots = VitalsProbeMath.timeSlots(seconds: 30 * 60, span: 7 * 3600 + 600)
        XCTAssertEqual(slots.count, 15)
        XCTAssertEqual(slots.last?.end, 1)
        XCTAssertLessThan(slots[14].end - slots[14].start, slots[13].end - slots[13].start)
    }

    func testAZeroSpanHasNoSlotsAtAll() {
        XCTAssertTrue(VitalsProbeMath.timeSlots(seconds: 1800, span: 0).isEmpty)
        XCTAssertTrue(VitalsProbeMath.timeSlots(seconds: 0, span: 3600).isEmpty)
    }

    // MARK: - envelopes

    func testEnvelopeIsTheSlotsOwnLowestAndHighestTick() {
        let span: TimeInterval = 3600
        // Two half hours: 60/72/65 in the first, 80/88 in the second.
        let points: [(fraction: Double, value: Double)] = [
            (0.05, 60), (0.20, 72), (0.40, 65),
            (0.60, 80), (0.90, 88)
        ]
        let marks = VitalsProbeMath.envelopes(points: points, seconds: 1800, span: span)
        XCTAssertEqual(marks.count, 2)
        XCTAssertEqual(marks[0].low, 60)
        XCTAssertEqual(marks[0].high, 72)
        XCTAssertEqual(marks[0].count, 3)
        XCTAssertEqual(marks[1].low, 80)
        XCTAssertEqual(marks[1].high, 88)
        XCTAssertEqual(marks[1].index, 1)
    }

    func testASlotTheBandDidNotReportIsAbsentRatherThanZero() {
        // 08 rule 07 · a gap is never interpolated. The middle half hour has no ticks, so it
        // must not appear at all — a zero-height mark at the floor would read as a 0 BPM.
        let points: [(fraction: Double, value: Double)] = [(0.1, 70), (0.9, 74)]
        let marks = VitalsProbeMath.envelopes(points: points, seconds: 1800, span: 3 * 1800)
        XCTAssertEqual(marks.map(\.index), [0, 2])
        XCTAssertFalse(marks.contains { $0.low == 0 || $0.high == 0 })
    }

    func testASingleTickIsAnEnvelopeOfNoHeight() {
        let marks = VitalsProbeMath.envelopes(points: [(0.5, 66)], seconds: 1800, span: 1800)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[0].low, 66)
        XCTAssertEqual(marks[0].high, 66)
        XCTAssertEqual(marks[0].count, 1)
    }

    func testTheTickOnTheRightEdgeLandsInTheLastSlotNotPastIt() {
        let marks = VitalsProbeMath.envelopes(points: [(1.0, 91)], seconds: 1800, span: 24 * 3600)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[0].index, 47)
        XCTAssertEqual(marks[0].high, 91)
    }

    func testEnvelopesNeverBorrowAcrossTheirOwnEdge() {
        // A spike in slot 1 must not raise slot 0's high; that is the whole difference
        // between an envelope and a smoothing pass.
        let points: [(fraction: Double, value: Double)] = [(0.1, 60), (0.6, 158)]
        let marks = VitalsProbeMath.envelopes(points: points, seconds: 1800, span: 3600)
        XCTAssertEqual(marks[0].high, 60)
        XCTAssertEqual(marks[1].high, 158)
    }

    func testAnEnvelopeIgnoresANonFiniteTick() {
        let points: [(fraction: Double, value: Double)] = [(0.2, 70), (0.3, .nan), (0.4, 76)]
        let marks = VitalsProbeMath.envelopes(points: points, seconds: 1800, span: 1800)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[0].count, 2)
        XCTAssertEqual(marks[0].low, 70)
        XCTAssertEqual(marks[0].high, 76)
    }

    func testEnvelopeMidIsTheSlotsCentreSoTheMarkStandsInIt() {
        let marks = VitalsProbeMath.envelopes(points: [(0.1, 70)], seconds: 1800, span: 3600)
        XCTAssertEqual(marks[0].mid, 0.25, accuracy: 0.0001)
    }

    func testEqualSlotsKeepAMissingNightAsANamedVacant() {
        let slots = VitalsProbeMath.equalSlots(count: 7)
        XCTAssertEqual(slots.count, 7)
        XCTAssertEqual(slots[0].start, 0)
        XCTAssertEqual(slots[6].end, 1)
        let bins = slots.enumerated().map { index, slot in
            VitalsProbeMath.Bin(
                start: slot.start, end: slot.end,
                text: index == 2 ? VitalsProbeMath.gap("WED 3") : VitalsProbeMath.line("DAY \(index)", "70"),
                vacant: index == 2)
        }
        let missing = VitalsProbeMath.pickBin(finger: 2.5 / 7, bins: bins)
        XCTAssertEqual(missing.text, VitalsProbeMath.gap("WED 3"))
        XCTAssertTrue(missing.snaps)
        XCTAssertEqual(VitalsProbeMath.Series.bins(bins).idleText, "DAY 6 · 70")
    }

    func testClimbKeepsAMissingHourAsAFlatStretch() {
        let totals = VitalsProbeMath.cumulativeTotals([100, nil, 50, 0, 25])
        XCTAssertEqual(totals, [100, 100, 150, 150, 175])
    }

    func testStageSpansAreSequentialWhenOffsetsAreMissing() {
        let spans = VitalsProbeMath.stageSpans(minutes: [84, 60, 110], offsets: nil, windowMinutes: nil)
        XCTAssertEqual(spans.count, 3)
        XCTAssertEqual(spans[0].start, 0)
        XCTAssertEqual(spans[0].end, 84 / 254.0, accuracy: 1e-12)
        XCTAssertEqual(spans[1].start, spans[0].end, accuracy: 1e-12)
        XCTAssertEqual(spans[2].end, 1, accuracy: 1e-12)
    }

    func testStageSpansHonourOffsetsOnALongerWindow() {
        let spans = VitalsProbeMath.stageSpans(
            minutes: [10, 20], offsets: [0, 40], windowMinutes: 100)
        XCTAssertEqual(spans[0].start, 0)
        XCTAssertEqual(spans[0].end, 0.10, accuracy: 1e-12)
        XCTAssertEqual(spans[1].start, 0.40, accuracy: 1e-12)
        XCTAssertEqual(spans[1].end, 0.60, accuracy: 1e-12)
        let hole = VitalsProbeMath.pickRun(
            finger: 0.25,
            runs: spans.enumerated().map {
                .init(start: $0.element.start, end: $0.element.end, text: $0.offset == 0 ? "DEEP" : "LIGHT")
            })
        XCTAssertEqual(hole.identity, "gap")
    }

    // MARK: - finger / axis lock

    func testFingerFractionAccountsForTheHypnogramGutter() {
        XCTAssertEqual(VitalsProbeMath.fingerFraction(x: 40, width: 200, leadingInset: 40), 0)
        XCTAssertEqual(VitalsProbeMath.fingerFraction(x: 120, width: 200, leadingInset: 40), 0.5)
        XCTAssertEqual(VitalsProbeMath.fingerFraction(x: 200, width: 200, leadingInset: 40), 1)
        XCTAssertEqual(VitalsProbeMath.fingerFraction(x: 0, width: 200, leadingInset: 40), 0)
        XCTAssertEqual(VitalsProbeMath.fingerFraction(x: 400, width: 200, leadingInset: 40), 1)
    }

    func testFingerFractionAccountsForTheScaleRailGutter() {
        // A 200pt card with a 42pt rail has a 158pt field. The finger has to reach 1 at the
        // field's own right edge, not at the card's — otherwise the last half hour of the
        // day is unreachable and NOW can never be probed.
        XCTAssertEqual(VitalsProbeMath.fingerFraction(
            x: 0, width: 200, leadingInset: 0, trailingInset: 42), 0)
        XCTAssertEqual(VitalsProbeMath.fingerFraction(
            x: 79, width: 200, leadingInset: 0, trailingInset: 42), 0.5)
        XCTAssertEqual(VitalsProbeMath.fingerFraction(
            x: 158, width: 200, leadingInset: 0, trailingInset: 42), 1)
        // A finger that strays onto the rail reads the last slot rather than nothing.
        XCTAssertEqual(VitalsProbeMath.fingerFraction(
            x: 190, width: 200, leadingInset: 0, trailingInset: 42), 1)
    }

    func testBothGuttersCanApplyAtOnce() {
        XCTAssertEqual(VitalsProbeMath.fingerFraction(
            x: 40, width: 200, leadingInset: 40, trailingInset: 40), 0)
        XCTAssertEqual(VitalsProbeMath.fingerFraction(
            x: 100, width: 200, leadingInset: 40, trailingInset: 40), 0.5)
        XCTAssertEqual(VitalsProbeMath.fingerFraction(
            x: 160, width: 200, leadingInset: 40, trailingInset: 40), 1)
    }

    func testAxisLockStaysUndecidedInsideTheDeadZone() {
        XCTAssertEqual(VitalsProbeMath.axisLock(dx: 0, dy: 0), .undecided)
        XCTAssertEqual(VitalsProbeMath.axisLock(dx: 10, dy: 0), .undecided)
        XCTAssertEqual(VitalsProbeMath.axisLock(dx: 6, dy: 8), .undecided)
        XCTAssertEqual(VitalsProbeMath.axisLock(dx: 11, dy: 0), .horizontal)
        XCTAssertEqual(VitalsProbeMath.axisLock(dx: 0, dy: 11), .vertical)
        XCTAssertEqual(VitalsProbeMath.axisLock(dx: 20, dy: 19), .horizontal)
        XCTAssertEqual(VitalsProbeMath.axisLock(dx: 19, dy: 20), .vertical)
    }

    func testSeriesPickDelegatesToTheMatchingShape() {
        let points = VitalsProbeMath.Series.points([.init(fraction: 0.2, text: "A")])
        XCTAssertEqual(points.pick(finger: 0.21, gapFraction: 0.1).text, "A")
        let bins = VitalsProbeMath.Series.bins([.init(start: 0, end: 1, text: "hour")])
        XCTAssertEqual(bins.pick(finger: 0.4, gapFraction: 0).text, "hour")
        let runs = VitalsProbeMath.Series.runs([.init(start: 0, end: 1, text: "DEEP")])
        XCTAssertEqual(runs.pick(finger: 0.3, gapFraction: 0).marker, 0.3)
    }
}

private extension VitalsProbeMathTests {
    func hourBins(_ values: [Double?], span: TimeInterval) -> [VitalsProbeMath.Bin] {
        let top = values.compactMap { $0 }.filter { $0 > 0 }.max() ?? 0
        return VitalsProbeMath.hourSlots(count: values.count, span: span).map { slot in
            let value = values[slot.index]
            let clock = String(format: "%02d:00", slot.index)
            if let value, value > 0, top > 0 {
                return .init(
                    start: slot.start, end: slot.end,
                    yFraction: 1 - value / top,
                    text: VitalsProbeMath.line(clock, String(Int(value))),
                    vacant: false)
            }
            return .init(
                start: slot.start, end: slot.end,
                text: VitalsProbeMath.gap(clock),
                vacant: true)
        }
    }

    func assertPick(_ pick: VitalsProbeMath.Pick, marker: Double, text: String, identity: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(pick.marker, marker, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(pick.text, text, file: file, line: line)
        XCTAssertEqual(pick.identity, identity, file: file, line: line)
        XCTAssertTrue(pick.snaps, file: file, line: line)
    }
}
