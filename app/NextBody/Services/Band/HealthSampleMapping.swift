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

    /// The day's HRV placed on the five-minute grid the sample table uses. The band measures
    /// roughly every ten minutes, all day, so most slots stay empty; a slot that caught more
    /// than one measured minute keeps their median rather than whichever arrived last.
    /// ⚠️ RMSSD only, and only inside the 1–300 ms band the server's own night rule trusts
    /// (nb.night_hrv_parts) — a chart of ticks and the night's number must never disagree
    /// about which readings were plausible.
    static func hrvBySlot(_ samples: [HrvMinuteSample]) -> [String: Double] {
        let measured = samples.compactMap { sample -> (slot: String, value: Double)? in
            guard let minutes = minutesSinceMidnight(sample.time),
                  let value = sample.rmssdMS, value.isFinite, (1...300).contains(value)
            else { return nil }
            let slot = (minutes / 5) * 5
            return (String(format: "%02d:%02d", slot / 60, slot % 60), value)
        }
        return Dictionary(grouping: measured, by: \.slot)
            .compactMapValues { median($0.map(\.value)) }
    }

    /// ⚠️ Reconstructed on 2026-09-03 from HealthSampleMappingTests after a concurrent edit
    /// to this file was overwritten; the tests are the specification it was rebuilt against.
    ///
    /// The band reports a slot's distance in kilometres on some firmwares and in whole metres
    /// on others — 0.036 and 36 are both thirty-six metres. A fractional value is kilometres;
    /// a whole one is already metres.
    static func distanceMeters(from value: Any?) -> Int? {
        guard let raw = number(value), raw.isFinite, raw >= 0 else { return nil }
        let isKilometres = raw.truncatingRemainder(dividingBy: 1) != 0
        return Int((isKilometres ? raw * 1_000 : raw).rounded())
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
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
