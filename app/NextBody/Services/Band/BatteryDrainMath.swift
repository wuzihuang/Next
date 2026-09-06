import Foundation

/// How the battery trend fills a stretch the phone did not hear.
///
/// A lithium pack does not sit still, and it does not travel in a ruler line.
/// Discharge eases in (holds, then falls). Charge eases out (climbs, then
/// tapers). The phone never heard these points — the chart dashes them.
enum BatteryDrainMath {
    /// Quiet measuring wear. Used only when this log has no unplugged drop to learn from.
    static let packHours: Double = 5 * 24
    /// Percent-scale. Bars scale by `yMax / 100`.
    static let chargePerHourAt100: Double = 40
    static let step: TimeInterval = 15 * 60
    static let maxSteps = 48
    static let minCurveSpan: TimeInterval = 15 * 60
    /// First-connect stale + fresh land in the same minute. Closer than this, the later packet wins.
    static let clash: TimeInterval = 2 * 60

    static func cliff(isPercent: Bool) -> Double { isPercent ? 8 : 1 }

    /// The phone's real log: an `unknown` packet with a stale, lower percent lands
    /// 0.1–0.2 s before the vendor read (`30 → 23 unknown → 31 charging`). Those
    /// are not drain. Strip them, then collapse a first-connect cliff, then any
    /// leftover V-dip inside the clash window.
    static func collapse(_ samples: [BatteryObservation]) -> [BatteryObservation] {
        let ordered = samples.sorted { $0.at < $1.at }
        func valued(_ sample: BatteryObservation) -> Bool {
            sample.connected && sample.plotValue != nil
        }
        let trusted = ordered.filter { valued($0) && $0.charge != .unknown }
        let withoutGhosts = ordered.filter { sample in
            guard valued(sample), sample.charge == .unknown else { return true }
            return !trusted.contains {
                $0.isPercent == sample.isPercent
                    && abs($0.at.timeIntervalSince(sample.at)) < clash
            }
        }

        var out: [BatteryObservation] = []
        for sample in withoutGhosts {
            if let last = out.last,
               valued(last), valued(sample),
               last.isPercent == sample.isPercent,
               let va = last.plotValue, let vb = sample.plotValue,
               sample.at.timeIntervalSince(last.at) < clash,
               abs(va - vb) >= cliff(isPercent: sample.isPercent) {
                out.removeLast()
            }
            out.append(sample)
        }

        var index = 1
        while index + 1 < out.count {
            let previous = out[index - 1], mid = out[index], next = out[index + 1]
            if valued(previous), valued(mid), valued(next),
               previous.isPercent == mid.isPercent, mid.isPercent == next.isPercent,
               let low = mid.plotValue, let left = previous.plotValue, let right = next.plotValue,
               low < left - 0.5, low < right - 0.5,
               mid.at.timeIntervalSince(previous.at) < clash,
               next.at.timeIntervalSince(mid.at) < clash {
                out.remove(at: index)
                continue
            }
            index += 1
        }
        return out
    }

    /// Estimated points that sit on top of a heard packet are the dest we drew to NOW
    /// before the first read landed. They are the noon cliff.
    static func scrub(_ points: [BatteryPoint]) -> [BatteryPoint] {
        let heard = points.filter { !$0.estimated }.map(\.at)
        return points.filter { point in
            guard point.estimated else { return true }
            return !heard.contains { abs($0.timeIntervalSince(point.at)) < clash }
        }
    }

    static func clip(_ spans: [BatterySpan], from start: Date, to end: Date) -> [BatterySpan] {
        spans.compactMap { span in
            let lo = max(span.start, start)
            let hi = min(span.end, end)
            guard hi > lo else { return nil }
            return BatterySpan(start: lo, end: hi)
        }
    }

    static func progress(_ u: Double, rising: Bool) -> Double {
        let t = min(1, max(0, u))
        if rising { return 1 - pow(1 - t, 2.1) }
        return pow(t, 1.65)
    }

    /// Median % (or bars) per hour from consecutive unplugged drops. Chatter
    /// shorter than the plateau is ignored so a 1 % blip cannot set the slope.
    static func drainRate(in samples: [BatteryObservation], yMax: Double) -> Double {
        let fallback = yMax / packHours
        let rows = samples
            .filter { $0.connected && $0.charge == .unplugged && $0.plotValue != nil }
            .sorted { $0.at < $1.at }
        var rates: [Double] = []
        for (a, b) in zip(rows, rows.dropFirst()) {
            guard a.isPercent == b.isPercent,
                  let va = a.plotValue, let vb = b.plotValue,
                  vb < va - 0.05 else { continue }
            let hours = b.at.timeIntervalSince(a.at) / 3600
            guard hours >= 0.4 else { continue }
            rates.append((va - vb) / hours)
        }
        guard !rates.isEmpty else { return fallback }
        let sorted = rates.sorted()
        return sorted[sorted.count / 2]
    }

    static func project(
        from last: BatteryPoint,
        to end: Date,
        yMax: Double,
        drainPerHour: Double
    ) -> Double {
        let hours = end.timeIntervalSince(last.at) / 3600
        guard hours > 0 else { return last.value }
        switch last.charge {
        case .charging:
            let rise = (yMax / 100) * chargePerHourAt100 * hours
            return min(yMax, last.value + rise)
        case .unplugged, .unknown, .full:
            return max(0, last.value - drainPerHour * hours)
        }
    }

    /// Points between `start` and `end`, not including either end. Empty when
    /// the span is too short to bend.
    static func interiorCurve(from start: BatteryPoint, to end: BatteryPoint) -> [BatteryPoint] {
        let span = end.at.timeIntervalSince(start.at)
        guard span >= minCurveSpan else { return [] }
        let rising = end.value > start.value
        let steps = min(maxSteps, max(2, Int(span / step)))
        var points: [BatteryPoint] = []
        for i in 1..<steps {
            let u = Double(i) / Double(steps)
            let s = progress(u, rising: rising)
            points.append(BatteryPoint(
                at: start.at.addingTimeInterval(span * u),
                value: start.value + (end.value - start.value) * s,
                charge: start.charge,
                estimated: true))
        }
        return points
    }
}
