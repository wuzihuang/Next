import Foundation

/// How the battery trend fills a stretch the phone did not hear.
///
/// A lithium pack does not sit still, and it does not travel in a ruler line.
/// Discharge eases in (holds, then falls). Charge eases out (climbs, then
/// tapers). The phone never heard these points — the chart dashes them.
enum BatteryEta: Equatable, Sendable {
    case full(Date)
    case empty(Date)
}

/// How long the unplugged pack still has, from the same learned slope as `eta`.
/// Hours when empty is today-ish; whole days after that. Never the spec pack.
enum BatteryLeft: Equatable, Sendable {
    case hours(Int)
    case days(Int)
}

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
    /// A printed clock stays inside these bounds. Wider than this, the slope is not a time.
    static let maxChargeHours: Double = 8
    static let maxEmptyHours: Double = 14 * 24
    /// Under this, LEFT prints hours. Eighteen hours still reads as 1 DAY.
    static let leftHourCutoff: Double = 18

    static func cliff(isPercent: Bool) -> Double { isPercent ? 8 : 1 }

    /// Many firmwares keep sending `.charging` at 100% / 4 bars and never
    /// flip to `.full`. The pack is already topped — that is Charged.
    static func isToppedUp(isPercent: Bool, percent: Int?, level: Int?) -> Bool {
        if isPercent { return (percent ?? 0) >= 100 }
        return (level ?? 0) >= 4
    }

    static func settle(
        _ charge: BatteryObservation.Charge,
        isPercent: Bool,
        percent: Int?,
        level: Int?
    ) -> BatteryObservation.Charge {
        charge == .charging && isToppedUp(isPercent: isPercent, percent: percent, level: level)
            ? .full
            : charge
    }

    /// SDK `default: .unknown` packets that still carry a percent or bar count.
    /// Those values are stale. A connect row with no reading is not a ghost.
    static func isGhost(_ sample: BatteryObservation) -> Bool {
        sample.plotValue != nil && sample.charge == .unknown
    }

    /// Drop every valued `unknown` packet, then collapse a first-connect cliff,
    /// then any leftover V-dip inside the clash window.
    static func collapse(_ samples: [BatteryObservation]) -> [BatteryObservation] {
        let ordered = samples.sorted { $0.at < $1.at }
        func valued(_ sample: BatteryObservation) -> Bool {
            sample.connected && sample.plotValue != nil
        }
        let withoutGhosts = ordered.filter { !isGhost($0) }

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
        medianSlope(in: samples, charge: .unplugged, rising: false) ?? yMax / packHours
    }

    /// Learned % (or bars) per hour. Nil when this log has no usable pair.
    static func medianSlope(
        in samples: [BatteryObservation],
        charge: BatteryObservation.Charge,
        rising: Bool
    ) -> Double? {
        let rows = samples
            .filter { $0.connected && $0.charge == charge && $0.plotValue != nil }
            .sorted { $0.at < $1.at }
        var rates: [Double] = []
        for (a, b) in zip(rows, rows.dropFirst()) {
            guard a.isPercent == b.isPercent,
                  let va = a.plotValue, let vb = b.plotValue else { continue }
            if rising {
                guard vb > va + 0.05 else { continue }
            } else {
                guard vb < va - 0.05 else { continue }
            }
            let hours = b.at.timeIntervalSince(a.at) / 3600
            guard hours >= 0.4 else { continue }
            rates.append(abs(vb - va) / hours)
        }
        guard !rates.isEmpty else { return nil }
        let sorted = rates.sorted()
        return sorted[sorted.count / 2]
    }

    /// One rough clock: full if the last heard packet is charging, empty if it
    /// is unplugged. Bars, a full pack, and an unlearned slope stay silent.
    static func eta(in samples: [BatteryObservation], now: Date) -> BatteryEta? {
        let ordered = collapse(samples)
        guard let last = ordered.last(where: {
            $0.connected && $0.plotValue != nil && $0.isPercent
        }), let value = last.plotValue else { return nil }
        let aged = max(0, now.timeIntervalSince(last.at) / 3600)
        switch last.charge {
        case .charging:
            guard value < 99.5,
                  let rate = medianSlope(in: ordered, charge: .charging, rising: true),
                  rate > 0 else { return nil }
            let current = min(100, value + rate * aged)
            let hours = (100 - current) / rate
            guard hours > 0.05, hours <= maxChargeHours else { return nil }
            return .full(now.addingTimeInterval(hours * 3600))
        case .unplugged, .unknown:
            guard value > 0.5,
                  let rate = medianSlope(in: ordered, charge: .unplugged, rising: false),
                  rate > 0 else { return nil }
            let current = max(0, value - rate * aged)
            let hours = current / rate
            guard hours > 0.08, hours <= maxEmptyHours else { return nil }
            return .empty(now.addingTimeInterval(hours * 3600))
        case .full:
            return nil
        }
    }

    /// Remaining wear from the learned unplugged slope. Silent wherever `eta`
    /// is silent — charging, full, bars, or an unlearned rate.
    static func left(in samples: [BatteryObservation], now: Date) -> BatteryLeft? {
        guard case .empty(let at) = eta(in: samples, now: now) else { return nil }
        let hours = at.timeIntervalSince(now) / 3600
        guard hours > 0.08 else { return nil }
        if hours < leftHourCutoff {
            return .hours(max(1, Int(hours.rounded())))
        }
        return .days(max(1, Int((hours / 24).rounded())))
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
