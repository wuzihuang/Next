import Foundation

/// Product boundary between vendor counters and energy that is safe to label as kcal.
///
/// `raw_samples.cal` is retained as source evidence, but Veepoo documents it as `cal` and
/// its original-data counter includes the vendor's own basal component. It is therefore
/// neither an active-kcal sample nor something that can be summed into an hourly chart.
enum ActivityEnergyPolicy {
    static func displayTotal(settledActiveKcal: Double?,
                             archivedVendorCalories: [Double]) -> Double? {
        _ = archivedVendorCalories
        guard let settledActiveKcal, settledActiveKcal.isFinite, settledActiveKcal >= 0 else {
            return nil
        }
        return settledActiveKcal
    }

    static func hourlyBins(count: Int, archivedVendorCalories: [Double]) -> [Double?] {
        _ = archivedVendorCalories
        return Array(repeating: nil, count: max(0, count))
    }
}
