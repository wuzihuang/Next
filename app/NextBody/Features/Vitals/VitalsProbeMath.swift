import Foundation

/// 探点 arithmetic, with no SwiftUI in it. A finger fraction in 0…1 either lands on a
/// recorded sample or it does not; the math never invents a value between ticks.
public enum VitalsProbeMath {
    /// Half the ten-minute break the traces already use: closer than this and the nearest
    /// tick is a neighbour; farther and the finger is in a gap.
    public static let neighbourSeconds: TimeInterval = 5 * 60

    /// Same dead zone as `HotZoneTap.slop` — 10 screen points. Travel at or inside this
    /// stays undecided so the page can still take a vertical scroll.
    public static let slop: Double = 10

    /// Copy separator. The app wraps this in `L("%@ · %@")`; tests assert the same string.
    public static let dash = "——"

    public struct Point: Equatable, Sendable {
        public var fraction: Double
        /// 0 is the top of the field, 1 the floor. Nil when the series has no vertical ruler.
        public var yFraction: Double?
        public var text: String

        public init(fraction: Double, yFraction: Double? = nil, text: String) {
            self.fraction = fraction
            self.yFraction = yFraction
            self.text = text
        }
    }

    public struct Bin: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var yFraction: Double?
        public var text: String
        /// An hour (or night) the band did not report. The readout is still named — it is
        /// `——` — so a missing slot is a slot, not a skip to the next filled one.
        public var vacant: Bool

        public init(start: Double, end: Double, yFraction: Double? = nil,
                    text: String, vacant: Bool = false) {
            self.start = start
            self.end = end
            self.yFraction = yFraction
            self.text = text
            self.vacant = vacant
        }
    }

    public struct Run: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var yFraction: Double?
        public var text: String

        public init(start: Double, end: Double, yFraction: Double? = nil, text: String) {
            self.start = start
            self.end = end
            self.yFraction = yFraction
            self.text = text
        }
    }

    public struct Pick: Equatable, Sendable {
        /// Where the 标线 is drawn, 0…1 in the field.
        public var marker: Double
        public var yFraction: Double?
        /// Nil only on a point-series gap. Bins and runs always carry copy.
        public var text: String?
        /// Stable for the life of one sample / bin / run; changes fire the selection haptic.
        public var identity: String
        public var snaps: Bool

        public init(marker: Double, yFraction: Double?, text: String?,
                    identity: String, snaps: Bool) {
            self.marker = marker
            self.yFraction = yFraction
            self.text = text
            self.identity = identity
            self.snaps = snaps
        }
    }

    public struct StageSpan: Equatable, Sendable {
        public var start: Double
        public var end: Double

        public init(start: Double, end: Double) {
            self.start = start
            self.end = end
        }
    }

    public enum Series: Equatable, Sendable {
        case points([Point])
        case bins([Bin])
        case runs([Run])

        public var isEmpty: Bool {
            switch self {
            case .points(let points): return points.isEmpty
            case .bins(let bins): return bins.isEmpty
            case .runs(let runs): return runs.isEmpty
            }
        }

        /// Lift-off copy: last recorded sample in the window. Vacant bins at the end are
        /// skipped so a trailing missing hour does not become the idle readout.
        public var idleText: String? {
            switch self {
            case .points(let points):
                return points.last?.text
            case .bins(let bins):
                return bins.last(where: { !$0.vacant })?.text ?? bins.last?.text
            case .runs(let runs):
                return runs.last?.text
            }
        }

        public var voItems: [Pick] {
            switch self {
            case .points(let points):
                return points.enumerated().map { index, point in
                    Pick(marker: point.fraction, yFraction: point.yFraction,
                         text: point.text, identity: pointIdentity(index), snaps: true)
                }
            case .bins(let bins):
                return bins.map {
                    Pick(marker: ($0.start + $0.end) / 2,
                         yFraction: $0.vacant ? nil : $0.yFraction,
                         text: $0.text, identity: binIdentity($0.start), snaps: true)
                }
            case .runs(let runs):
                return runs.map {
                    Pick(marker: ($0.start + $0.end) / 2, yFraction: $0.yFraction,
                         text: $0.text, identity: runIdentity($0.start), snaps: true)
                }
            }
        }

        public func pick(finger: Double, gapFraction: Double) -> Pick {
            switch self {
            case .points(let points):
                return pickPoint(finger: finger, points: points, maxFraction: gapFraction)
            case .bins(let bins):
                return pickBin(finger: finger, bins: bins)
            case .runs(let runs):
                return pickRun(finger: finger, runs: runs)
            }
        }
    }

    public enum AxisLock: Equatable, Sendable {
        case undecided
        case horizontal
        case vertical
    }

    public static func line(_ time: String, _ value: String) -> String {
        "\(time) · \(value)"
    }

    public static func gap(_ time: String) -> String {
        line(time, dash)
    }

    public static func readout(pick: Pick?, idle: String?, gap: String) -> String {
        if let pick {
            return pick.text ?? gap
        }
        return idle ?? gap
    }

    public static func voStep(items: [Pick], currentIdentity: String?, increment: Bool) -> Pick? {
        guard !items.isEmpty else { return nil }
        let current = currentIdentity.flatMap { id in
            items.firstIndex(where: { $0.identity == id })
        } ?? items.count - 1
        let next = increment ? min(items.count - 1, current + 1) : max(0, current - 1)
        return items[next]
    }

    public static func gapFraction(span: TimeInterval) -> Double {
        guard span > 0 else { return 0.5 }
        return min(0.5, neighbourSeconds / span)
    }

    public static func yFraction(value: Double, low: Double, high: Double) -> Double {
        let span = max(0.001, high - low)
        let clamped = min(high, max(low, value))
        return 1 - (clamped - low) / span
    }

    public static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    /// Map a touch x onto the field, discounting the gutters either side of it: a left one
    /// for the hypnogram's lane labels, a right one for the scale rail. Both are chrome —
    /// the field is what is left between them, and a finger on the rail reads the last slot
    /// rather than an eleventh hour that is not there.
    public static func fingerFraction(x: Double, width: Double, leadingInset: Double,
                                      trailingInset: Double = 0) -> Double {
        clamp((x - leadingInset) / max(1, width - leadingInset - trailingInset))
    }

    /// Axis lock against page scroll. Travel at or inside `slop` is still the dead zone.
    public static func axisLock(dx: Double, dy: Double, slop: Double = slop) -> AxisLock {
        if (dx * dx + dy * dy).squareRoot() <= slop { return .undecided }
        return abs(dx) >= abs(dy) ? .horizontal : .vertical
    }

    /// One slot's fraction range on a window. Slots that start at or past the right edge are
    /// dropped so a nine-hour user day does not grow twenty-four zero-width bins.
    public static func timeSlot(index: Int, seconds: TimeInterval,
                                span: TimeInterval) -> (start: Double, end: Double)? {
        guard span > 0, seconds > 0, index >= 0 else { return nil }
        let start = min(1, TimeInterval(index) * seconds / span)
        let end = min(1, TimeInterval(index + 1) * seconds / span)
        guard end > start else { return nil }
        return (start, end)
    }

    /// Every slot of `seconds` the window has room for. A window that does not divide evenly
    /// keeps its short last slot rather than rounding the window up.
    public static func timeSlots(seconds: TimeInterval,
                                 span: TimeInterval) -> [(index: Int, start: Double, end: Double)] {
        guard span > 0, seconds > 0 else { return [] }
        let count = Int((span / seconds).rounded(.up))
        var slots: [(index: Int, start: Double, end: Double)] = []
        slots.reserveCapacity(count)
        for index in 0..<count {
            guard let range = timeSlot(index: index, seconds: seconds, span: span) else { continue }
            slots.append((index, range.start, range.end))
        }
        return slots
    }

    public static func hourSlot(index: Int, span: TimeInterval) -> (start: Double, end: Double)? {
        timeSlot(index: index, seconds: 3600, span: span)
    }

    public static func hourSlots(count: Int, span: TimeInterval) -> [(index: Int, start: Double, end: Double)] {
        var slots: [(index: Int, start: Double, end: Double)] = []
        slots.reserveCapacity(max(count, 0))
        for index in 0..<count {
            guard let range = hourSlot(index: index, span: span) else { continue }
            slots.append((index, range.start, range.end))
        }
        return slots
    }

    /// One occupied value run inside a time slot.
    ///
    /// ⚠️ This is not a min–max fill. `low` and `high` are the ends of ticks that actually
    /// sat next to each other; a hole such as 70–75 with no sample stays out of the mark.
    /// A slot the band did not report is absent from the result rather than flat at zero.
    public struct Envelope: Equatable, Sendable {
        public var index: Int
        public var start: Double
        public var end: Double
        public var low: Double
        public var high: Double
        /// How many ticks this run reduced. One tick is a legitimate envelope of no height.
        public var count: Int

        public init(index: Int, start: Double, end: Double,
                    low: Double, high: Double, count: Int) {
            self.index = index
            self.start = start
            self.end = end
            self.low = low
            self.high = high
            self.count = count
        }

        public var mid: Double { (start + end) / 2 }
    }

    /// The mark that occupies one envelope's own slot. Width follows the slot, not a
    /// 7pt cap: a night of twenty-eight quarter-hours on a 300pt field is ~10pt a slot,
    /// and a 7pt pill left a dead strip against the rail that read as a cropped window.
    public static func slotBar(start: Double, end: Double, field: Double,
                               gap: Double = 2, minWidth: Double = 2.5)
        -> (x: Double, width: Double) {
        let left = field * min(1, max(0, start))
        let right = field * min(1, max(start, end))
        let span = max(0, right - left)
        let inset = min(gap, span * 0.25)
        let width = max(minWidth, span - inset)
        // A slot shorter than the minimum mark still sits flush on its right edge, so
        // the last ten minutes of a night do not leave a hole against the rail.
        let x = width >= span ? max(0, right - width) : left + (span - width) / 2
        return (x, width)
    }

    /// Capsule heads stay a column, not a pill, once a slot is wider than 12pt.
    public static func slotBarRadius(width: Double, cap: Double = 6) -> Double {
        min(max(width / 2, 0), cap)
    }

    /// A hole larger than this fraction of the ruler is left empty. 4% of 40–160 is
    /// 4.8 BPM: two ticks 8 BPM apart stay two marks; a dense climb stays one run.
    public static let occupancyGapFraction = 0.04

    /// The merge distance for occupancy runs on a given ruler.
    public static func occupancyGap(low: Double, high: Double) -> Double {
        max(0, (high - low) * occupancyGapFraction)
    }

    /// Cluster ticks that sit next to each other. A gap larger than `gap` starts a new
    /// run, so a slot that recorded 45, 50 and 90 paints 45–50 and 90, never 45–90.
    ///
    /// A non-finite gap (the default on `envelopes`) keeps the old one-run min–max, so
    /// arithmetic tests that only care about slot membership still compile as one mark.
    public static func occupancyRuns(values: [Double], gap: Double)
        -> [(low: Double, high: Double)] {
        let sorted = values.filter(\.isFinite).sorted()
        guard let first = sorted.first, let last = sorted.last else { return [] }
        if !gap.isFinite || gap < 0 { return [(first, last)] }
        var runs: [(low: Double, high: Double)] = []
        var lo = first
        var hi = first
        for value in sorted.dropFirst() {
            if value - hi > gap {
                runs.append((lo, hi))
                lo = value
                hi = value
            } else {
                hi = value
            }
        }
        runs.append((lo, hi))
        return runs
    }

    /// Reduce a window's ticks to occupied runs per slot. 288 ticks over 24 hours become
    /// 96 fifteen-minute columns; each column only paints the value bands that have ticks.
    public static func envelopes(points: [(fraction: Double, value: Double)],
                                 seconds: TimeInterval, span: TimeInterval,
                                 valueGap: Double = .infinity) -> [Envelope] {
        let slots = timeSlots(seconds: seconds, span: span)
        guard !slots.isEmpty else { return [] }
        var buckets = [[Double]](repeating: [], count: slots.count)
        for point in points {
            guard point.value.isFinite else { continue }
            let slot = clamp(point.fraction) * span / seconds
            let index = min(slots.count - 1, max(0, Int(slot.rounded(.down))))
            buckets[index].append(point.value)
        }
        return slots.flatMap { slot -> [Envelope] in
            let values = buckets[slot.index]
            guard !values.isEmpty else { return [] }
            return occupancyRuns(values: values, gap: valueGap).map { run in
                Envelope(index: slot.index, start: slot.start, end: slot.end,
                         low: run.low, high: run.high,
                         count: values.filter { $0 >= run.low && $0 <= run.high }.count)
            }
        }
    }

    public static func equalSlots(count: Int) -> [(start: Double, end: Double)] {
        let n = max(count, 1)
        var slots: [(start: Double, end: Double)] = []
        slots.reserveCapacity(n)
        for index in 0..<n {
            let start = Double(index) / Double(n)
            let end = Double(index + 1) / Double(n)
            slots.append((start, end))
        }
        return slots
    }

    /// Climb totals: a missing or zero hour is a flat stretch, not a skip.
    public static func cumulativeTotals(_ increments: [Double?]) -> [Double] {
        var running = 0.0
        return increments.map { increment in
            if let increment, increment > 0 { running += increment }
            return running
        }
    }

    public static func isVacantHour(_ value: Double?) -> Bool {
        guard let value, value > 0 else { return true }
        return false
    }

    /// Sequential runs, or offset-placed runs on a night window. Offsets win when every
    /// run carries one, matching the hypnogram's own layout.
    public static func stageSpans(minutes: [Int], offsets: [Int]?, windowMinutes: Double?) -> [StageSpan] {
        if let offsets, offsets.count == minutes.count {
            let farthest = zip(offsets, minutes).map { $0 + $1 }.max() ?? 0
            let total = max(windowMinutes ?? 0, Double(farthest))
            guard total > 0 else { return [] }
            var spans: [StageSpan] = []
            spans.reserveCapacity(minutes.count)
            for (offset, length) in zip(offsets, minutes) {
                spans.append(StageSpan(start: Double(offset) / total, end: Double(offset + length) / total))
            }
            return spans
        }
        let total = Double(minutes.reduce(0, +))
        guard total > 0 else { return [] }
        var cursor = 0.0
        var spans: [StageSpan] = []
        spans.reserveCapacity(minutes.count)
        for length in minutes {
            let start = cursor
            let width = Double(length) / total
            cursor += width
            spans.append(StageSpan(start: start, end: start + width))
        }
        return spans
    }

    /// Nearest recorded point, or a gap at the finger when that point is not a neighbour.
    /// Equal distance prefers the later sample so a midpoint on a time series reads forward.
    public static func pickPoint(finger: Double, points: [Point], maxFraction: Double) -> Pick {
        let f = clamp(finger)
        guard !points.isEmpty else {
            return gapPick(at: f)
        }
        var bestIndex = 0
        var bestDist = abs(points[0].fraction - f)
        for (index, point) in points.enumerated().dropFirst() {
            let dist = abs(point.fraction - f)
            // A midpoint is equal in the product sense even when binary floats are a ulp apart.
            if dist < bestDist - 1e-12 || (abs(dist - bestDist) <= 1e-12 && index > bestIndex) {
                bestIndex = index
                bestDist = dist
            }
        }
        let best = points[bestIndex]
        if bestDist <= maxFraction {
            return Pick(marker: best.fraction, yFraction: best.yFraction, text: best.text,
                        identity: pointIdentity(bestIndex), snaps: true)
        }
        return gapPick(at: f)
    }

    /// The bin that contains the finger. Marker sits on the bin's centre. A hole between
    /// bins is a gap — never the last bin just because nothing else matched.
    public static func pickBin(finger: Double, bins: [Bin]) -> Pick {
        let f = clamp(finger)
        guard let bin = bin(containing: f, in: bins) else {
            return gapPick(at: f)
        }
        let marker = (bin.start + bin.end) / 2
        return Pick(marker: marker, yFraction: bin.vacant ? nil : bin.yFraction,
                    text: bin.text, identity: binIdentity(bin.start), snaps: true)
    }

    /// The run under the finger. The marker stays at the finger — the whole run is the same
    /// sample — so pointing at twenty minutes of DEEP does not jump to the run's edge.
    public static func pickRun(finger: Double, runs: [Run]) -> Pick {
        let f = clamp(finger)
        guard let run = run(containing: f, in: runs) else {
            return gapPick(at: f)
        }
        return Pick(marker: f, yFraction: run.yFraction, text: run.text,
                    identity: runIdentity(run.start), snaps: true)
    }

    public static func pointIdentity(_ index: Int) -> String { "p:\(index)" }
    public static func binIdentity(_ start: Double) -> String { "b:\(start)" }
    public static func runIdentity(_ start: Double) -> String { "r:\(start)" }

    private static func gapPick(at f: Double) -> Pick {
        Pick(marker: f, yFraction: nil, text: nil, identity: "gap", snaps: false)
    }

    private static func bin(containing f: Double, in bins: [Bin]) -> Bin? {
        for (index, bin) in bins.enumerated() {
            if contains(f, start: bin.start, end: bin.end, last: index == bins.count - 1) {
                return bin
            }
        }
        return nil
    }

    private static func run(containing f: Double, in runs: [Run]) -> Run? {
        for (index, run) in runs.enumerated() {
            if contains(f, start: run.start, end: run.end, last: index == runs.count - 1) {
                return run
            }
        }
        return nil
    }

    /// Occupancy is `[start, end)` except the last interval includes 1.
    private static func contains(_ f: Double, start: Double, end: Double, last: Bool) -> Bool {
        f >= start && (f < end || (last && f <= end))
    }
}
