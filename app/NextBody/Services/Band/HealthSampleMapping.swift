import Foundation

struct TemperatureSample: Equatable {
    let time: String
    let celsius: Double
}

struct HrvMinuteSample: Equatable {
    let time: String
    /// RMSSD computed from the vendor RR intervals. This is the only HRV value that may be
    /// labelled milliseconds in the product.
    let rmssdMS: Double?
    /// The vendor's opaque HRV scalar. Retained for diagnostics, never substituted for RMSSD.
    let vendorValue: Double?
    let rrCount: Int
}

struct HrvNightReading: Equatable {
    let rmssdMS: Double
    let bucketCount: Int
    let rrCount: Int
}

/// Pure conversion at the closed-source SDK boundary. Keeping this free of Veepoo types makes
/// the unit and missing-value rules testable without a band or the arm64-only framework.
enum HealthSampleMapping {
    static func deviceDayOffsets(daysBack: Int, straddles: Bool) -> [Int] {
        guard straddles else { return [max(0, daysBack)] }
        // A user day D 04:00 → D+1 04:00 spans calendar day D and the following day.
        // Device offsets count backwards, so the second page is one *smaller* offset.
        if daysBack == 0 { return [0, 1] }
        return [daysBack, daysBack - 1]
    }

    static func instant(time: String, calendarDay: Date, calendar: Calendar) -> Date? {
        guard let normalized = clock(time) else { return nil }
        let parts = normalized.split(separator: ":").compactMap { Int($0) }
        let day = calendar.dateComponents([.year, .month, .day], from: calendarDay)
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day,
                                                  hour: parts[0], minute: parts[1]))
    }

    static func temperature(from raw: [String: Any]) -> TemperatureSample? {
        guard let hour = integer(raw["hour"]), let minute = integer(raw["minute"]),
              (0..<24).contains(hour), (0..<60).contains(minute),
              // The product stores skin temperature, which Veepoo names originalValue.
              let unscaled = number(raw["originalValue"] ?? raw["riginalValue"])
        else { return nil }

        let celsius = unscaled > 100 ? unscaled / 10 : unscaled
        guard (10...50).contains(celsius) else { return nil }
        return TemperatureSample(time: String(format: "%02d:%02d", hour, minute),
                                 celsius: celsius)
    }

    static func hrv(from raw: [String: Any]) -> HrvMinuteSample? {
        guard let time = clock(raw["time"] as? String) else { return nil }
        let rr = (raw["hearts"] as? [Any] ?? [])
            .compactMap(number)
            .map { $0 * 10 }
            .filter { (250...2_500).contains($0) }
        let rmssd: Double? = rr.count > 1 ? {
            let squared = zip(rr.dropFirst(), rr).map { next, previous in
                let delta = next - previous
                return delta * delta
            }
            return sqrt(squared.reduce(0, +) / Double(squared.count))
        }() : nil
        return HrvMinuteSample(time: time, rmssdMS: rmssd,
                               vendorValue: number(raw["hrvValue"]), rrCount: rr.count)
    }

    /// Collapse minute-level RR data before upload: median minute RMSSD inside each 15-minute
    /// bucket, then the median bucket value for the 00:00–11:59 night window.
    static func nightHRV(from samples: [HrvMinuteSample]) -> HrvNightReading? {
        let night = samples.compactMap { sample -> (bucket: Int, value: Double, rr: Int)? in
            guard let minutes = minutesSinceMidnight(sample.time), minutes < 12 * 60,
                  let value = sample.rmssdMS, value.isFinite, (1...300).contains(value)
            else { return nil }
            return (minutes / 15, value, sample.rrCount)
        }
        guard !night.isEmpty else { return nil }
        let grouped = Dictionary(grouping: night, by: \.bucket)
        let bucketValues = grouped.values.compactMap { median($0.map(\.value)) }
        guard let value = median(bucketValues) else { return nil }
        return HrvNightReading(rmssdMS: value, bucketCount: bucketValues.count,
                               rrCount: night.reduce(0) { $0 + $1.rr })
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? { number(value).map(Int.init) }

    private static func clock(_ value: String?) -> String? {
        guard let value,
              let match = value.range(of: #"(\d{1,2}):(\d{2})"#, options: .regularExpression)
        else { return nil }
        let parts = value[match].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1])
        else { return nil }
        return String(format: "%02d:%02d", parts[0], parts[1])
    }

    private static func minutesSinceMidnight(_ time: String) -> Int? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
