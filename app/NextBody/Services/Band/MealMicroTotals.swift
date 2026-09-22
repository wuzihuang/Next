import Foundation

/// Fibre, sugar and sodium for a day.
///
/// The estimate reports these only for foods whose composition it actually knows, so most
/// days have some rows that can say and some that cannot.
///
/// ⚠️ A day's total is therefore all-or-nothing. Summing what is known and skipping the rest
/// prints a number that is true of *part* of the day while looking like the whole of it —
/// the same failure as writing 0 kcal for a plate the parser could not read. When a row is
/// silent the day is silent, and the page says how many rows were silent.
public enum MealMicroTotals {
    public static func total(_ values: [Double?]) -> Double? {
        guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
        return values.reduce(0) { $0 + ($1 ?? 0) }
    }

    public static func unknownCount(_ values: [Double?]) -> Int {
        values.filter { $0 == nil }.count
    }

    /// True when at least one row reported this nutrient — the difference between "nothing
    /// on this day ever knows" (say nothing at all) and "three of five rows know".
    public static func anyKnown(_ values: [Double?]) -> Bool {
        values.contains { $0 != nil }
    }
}
