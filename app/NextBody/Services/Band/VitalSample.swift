import Foundation

/// One timestamped row of measurements copied from the band.
///
/// Every value is optional because a missing sensor reading is not zero. The model lives in
/// SyncCore so the BLE upload path and the UI curve use one merge rule.
struct VitalSample: Codable, Hashable {
    let ts: Date
    let hr: Int?
    let stress: Int?
    var temp: Double? = nil
    var steps: Int? = nil
    var cal: Double? = nil
    var dis: Double? = nil
    var hrv: Double? = nil

    var hasReading: Bool {
        hr != nil || stress != nil || temp != nil || steps != nil
            || cal != nil || dis != nil || hrv != nil
    }

    /// Merge freshly read band points into a stored curve without erasing auxiliary fields
    /// that arrived from a different SDK stream. A fresh non-nil value wins at the same tick.
    static func merging(_ stored: [VitalSample], with fresh: [VitalSample]) -> [VitalSample] {
        var samplesByTimestamp: [Date: VitalSample] = [:]

        for sample in stored + fresh {
            guard let current = samplesByTimestamp[sample.ts] else {
                samplesByTimestamp[sample.ts] = sample
                continue
            }
            samplesByTimestamp[sample.ts] = VitalSample(
                ts: sample.ts,
                hr: sample.hr ?? current.hr,
                stress: sample.stress ?? current.stress,
                temp: sample.temp ?? current.temp,
                steps: sample.steps ?? current.steps,
                cal: sample.cal ?? current.cal,
                dis: sample.dis ?? current.dis,
                hrv: sample.hrv ?? current.hrv
            )
        }

        return samplesByTimestamp.values.sorted { $0.ts < $1.ts }
    }
}
