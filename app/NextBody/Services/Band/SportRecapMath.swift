import Foundation

/// End-of-session arithmetic for the folded recap (#38) and the simulator load bump (#37).
/// Zone boundaries mirror nb.training_zone / nb.zone_of. Z0 stays below the training zones.
/// Adjacent beats farther than 15 s do not add duration — the same gap the ingest path uses.
enum SportRecapMath {
    static let continuityGap: TimeInterval = 15

    struct Beat: Equatable, Codable, Sendable {
        var at: Date
        var bpm: Int
        var segment: Int = 0
    }

    struct Recap: Equatable, Sendable {
        var seconds: Int
        var avgHR: Int?
        var peakHR: Int?
        var curve: [Double]
        var curvePoints: [Beat]
        var observedSeconds: Double
        var zoneMinutes: [Double]
        var aerobicMinutes: Int
        var anaerobicMinutes: Int
        var loadDelta: Double
        var conclusion: Conclusion

        enum Conclusion: String, Equatable, Sendable {
            case noHeart = "No heart-rate record."
            case insufficient = "Not enough continuous heart-rate data for zones."
            case belowZones = "Recorded heart rate stayed below Z1."
            case aerobic = "Mostly aerobic."
            case anaerobic = "Mostly anaerobic."
            case mixed = "Mixed aerobic and anaerobic."
        }
    }

    static func recap(beats: [Beat], restHR: Int?, maxHR: Int, seconds: Int) -> Recap {
        let valid = beats.filter { (1...250).contains($0.bpm) && $0.at.timeIntervalSince1970.isFinite }.sorted { $0.at < $1.at }
        let avg = valid.isEmpty ? nil : Int((Double(valid.reduce(0) { $0 + $1.bpm })
            / Double(valid.count)).rounded())
        let peak = valid.map(\.bpm).max()
        var zones = [Double](repeating: 0, count: 5)
        var load = 0.0
        var observed = 0.0
        if valid.count >= 2 {
            for i in 1..<valid.count {
                let dt = valid[i].at.timeIntervalSince(valid[i - 1].at)
                guard dt > 0, dt <= continuityGap, valid[i].segment == valid[i - 1].segment else { continue }
                observed += dt
                let zone = zoneIndex(bpm: valid[i].bpm, rest: restHR, maxHR: maxHR)
                if zone > 0 { zones[zone - 1] += dt / 60 }
                // Simulator-only visual fixture. Production load comes from settlement.
                load += dt / 60 * [0.0, 0.15, 0.5, 1.2, 3.0, 6.0][zone]
            }
        }
        let aerobicSeconds = (zones[0] + zones[1] + zones[2]) * 60
        let anaerobicSeconds = (zones[3] + zones[4]) * 60
        let aerobic = Int((aerobicSeconds / 60).rounded())
        let anaerobic = Int((zones[3] + zones[4]).rounded())
        let conclusion: Recap.Conclusion
        if valid.isEmpty {
            conclusion = .noHeart
        } else if observed == 0 {
            conclusion = .insufficient
        } else if zones.reduce(0, +) == 0 {
            conclusion = .belowZones
        } else if aerobicSeconds > anaerobicSeconds * 2 {
            conclusion = .aerobic
        } else if anaerobicSeconds > aerobicSeconds * 2 {
            conclusion = .anaerobic
        } else {
            conclusion = .mixed
        }
        return Recap(
            seconds: Swift.max(0, seconds),
            avgHR: avg,
            peakHR: peak,
            curve: downsample(valid.map { Double($0.bpm) }, count: 40),
            curvePoints: displayPoints(valid),
            observedSeconds: observed,
            zoneMinutes: zones,
            aerobicMinutes: aerobic,
            anaerobicMinutes: anaerobic,
            loadDelta: min(20.9, 21 * (1 - exp(-load / 60))),
            conclusion: conclusion)
    }

    /// Returns Z0…Z5, including observed heart rates below the first training zone.
    static func zoneIndex(bpm: Int, rest: Int?, maxHR: Int) -> Int {
        guard maxHR > 0 else { return 0 }
        let thresholds: [Double]
        let pct: Double
        if let rest, maxHR > rest {
            pct = Double(bpm - rest) / Double(maxHR - rest)
            thresholds = [0.30, 0.40, 0.55, 0.70, 0.85]
        } else {
            pct = Double(bpm) / Double(maxHR)
            thresholds = [0.50, 0.60, 0.70, 0.80, 0.90]
        }
        return thresholds.filter { pct >= $0 }.count
    }

    /// Preserve time and continuity before bounding the drawing payload. A long workout
    /// must fit the cloud document budget; subsampling never turns a true gap into a line.
    static func displayPoints(_ beats: [Beat], limit: Int = 4_000) -> [Beat] {
        guard limit > 1, !beats.isEmpty else { return [] }
        var segment = 0
        var previous: Beat?
        let normalized = beats.map { beat -> Beat in
            if let previous, beat.segment != previous.segment
                || beat.at.timeIntervalSince(previous.at) > continuityGap { segment += 1 }
            previous = beat
            return Beat(at: beat.at, bpm: beat.bpm, segment: segment)
        }
        guard normalized.count > limit else { return normalized }
        let step = Double(normalized.count - 1) / Double(limit - 1)
        return (0..<limit).map { normalized[Int((Double($0) * step).rounded())] }
    }

    private static func downsample(_ values: [Double], count: Int) -> [Double] {
        guard !values.isEmpty else { return [] }
        if values.count <= count { return values }
        let step = Double(values.count - 1) / Double(count - 1)
        return (0..<count).map { i in
            values[min(values.count - 1, Int((Double(i) * step).rounded()))]
        }
    }
}
