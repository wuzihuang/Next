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
    /// Original five-minute MET; preferred over cadence estimates for energy.
    var met: Double? = nil
    /// Vendor original-data calorie counter. Veepoo documents this as `cal`, not kcal, and
    /// it includes the vendor's basal component. Archive it for evidence; never sum or show it.
    var vendorCalories: Double? = nil
    var dis: Double? = nil
    var hrv: Double? = nil
    /// Explicit RR evidence can revoke an older HRV value; an absent reading cannot.
    var hrvValid: Bool? = nil
    var hrvObservedAt: Date? = nil

    init(ts: Date, hr: Int?, stress: Int?, temp: Double? = nil, steps: Int? = nil,
         met: Double? = nil, vendorCalories: Double? = nil, dis: Double? = nil, hrv: Double? = nil,
         hrvValid: Bool? = nil, hrvObservedAt: Date? = nil) {
        self.ts = ts
        self.hr = hr
        self.stress = stress
        self.temp = temp
        self.steps = steps
        self.met = Self.validatedMET(met)
        self.vendorCalories = vendorCalories
        self.dis = dis
        self.hrv = hrvValid == false ? nil : hrv
        self.hrvValid = hrvValid == true && hrv == nil ? nil : hrvValid
        self.hrvObservedAt = hrvObservedAt
    }

    /// Match the ingestion payload range. Invalid readings are missing, never zero load.
    static func validatedMET(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
    }

    var hasReading: Bool {
        hr != nil || stress != nil || temp != nil || steps != nil
            || met != nil || vendorCalories != nil || dis != nil || hrv != nil
    }

    /// Merge freshly read band points into a stored curve without erasing auxiliary fields
    /// that arrived from a different SDK stream. HRV carries its observation clock so a
    /// stale read cannot undo a later correction; other fresh non-nil values win per tick.
    static func merging(_ stored: [VitalSample], with fresh: [VitalSample]) -> [VitalSample] {
        var samplesByTimestamp: [Date: VitalSample] = [:]

        for var sample in stored + fresh {
            sample.met = validatedMET(sample.met)
            guard let current = samplesByTimestamp[sample.ts] else {
                samplesByTimestamp[sample.ts] = sample
                continue
            }
            let hasHRVEvidence = sample.hrv != nil || sample.hrvValid == false
            let acceptsHRV = hasHRVEvidence && (current.hrvObservedAt == nil
                || (sample.hrvObservedAt.map { $0 > current.hrvObservedAt! } ?? false))
            samplesByTimestamp[sample.ts] = VitalSample(
                ts: sample.ts,
                hr: sample.hr ?? current.hr,
                stress: sample.stress ?? current.stress,
                temp: sample.temp ?? current.temp,
                steps: sample.steps ?? current.steps,
                met: sample.met ?? current.met,
                vendorCalories: sample.vendorCalories ?? current.vendorCalories,
                dis: sample.dis ?? current.dis,
                hrv: acceptsHRV ? sample.hrv : current.hrv,
                hrvValid: acceptsHRV ? sample.hrvValid : current.hrvValid,
                hrvObservedAt: acceptsHRV ? sample.hrvObservedAt : current.hrvObservedAt
            )
        }

        return samplesByTimestamp.values.sorted { $0.ts < $1.ts }
    }

    private enum CodingKeys: String, CodingKey {
        case ts, hr, stress, temp, steps, met, dis, hrv, hrvValid, hrvObservedAt
        case vendorCalories = "cal"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            ts: try values.decode(Date.self, forKey: .ts),
            hr: try values.decodeIfPresent(Int.self, forKey: .hr),
            stress: try values.decodeIfPresent(Int.self, forKey: .stress),
            temp: try values.decodeIfPresent(Double.self, forKey: .temp),
            steps: try values.decodeIfPresent(Int.self, forKey: .steps),
            met: try values.decodeIfPresent(Double.self, forKey: .met),
            vendorCalories: try values.decodeIfPresent(Double.self, forKey: .vendorCalories),
            dis: try values.decodeIfPresent(Double.self, forKey: .dis),
            hrv: try values.decodeIfPresent(Double.self, forKey: .hrv),
            hrvValid: try values.decodeIfPresent(Bool.self, forKey: .hrvValid),
            hrvObservedAt: try values.decodeIfPresent(Date.self, forKey: .hrvObservedAt)
        )
    }

    /// Issue #19 · the samples a card labelled TODAY may draw: this user day's, from
    /// local midnight to now. It used to be a rolling 24 hours, which put last night's
    /// evening on this morning's card.
    static func today(_ samples: [VitalSample], endingAt now: Date) -> [VitalSample] {
        let window = VitalsTimelinePolicy.today(endingAt: now)
        return samples.filter { window.contains($0.ts) }
    }
}
