import Foundation

/// Servings, without arithmetic.
///
/// The estimate already says how much it thought the plate was — "1 碗", "200 g", "2 slices".
/// Correcting it is almost always "that was half of that" or "it was a big one", which is one
/// multiplication of four numbers the person should never have to do by hand.
///
/// ⚠️ A portion whose words carry no number cannot be scaled honestly. "半份" doubled is not
/// "半份", and leaving the old words beside doubled calories is a claim the row no longer
/// supports — so the words are dropped and the numbers stand alone.
public enum PortionMath {
    /// The multipliers the plate offers. One of them is the identity, which is how a person
    /// undoes a mis-tap without reaching for the keyboard.
    public static let factors: [Double] = [0.5, 1, 1.5, 2]

    /// How a multiplier is printed on a pill: "0.5", "1", "1.5", "2".
    public static func label(_ factor: Double) -> String {
        factor == factor.rounded() ? String(Int(factor)) : String(format: "%.1f", factor)
    }

    public static func isUsable(_ factor: Double) -> Bool {
        factor.isFinite && factor > 0 && factor <= 20
    }

    /// A nutrient, scaled to one decimal place. Never below 1 for a kcal that was
    /// positive: a quarter of a 60 kcal side is still food, and 0 means "the parser failed"
    /// everywhere else in this product.
    public static func scale(_ value: Double, by factor: Double, floorAtOne: Bool = false) -> Double {
        guard isUsable(factor), value.isFinite else { return value }
        let scaled = (value * factor * 10).rounded() / 10
        if floorAtOne && value >= 1 { return max(1, scaled) }
        return max(0, scaled)
    }

    public static func scale(_ value: Int, by factor: Double) -> Int {
        Int(scale(Double(value), by: factor).rounded())
    }

    /// The portion phrase, scaled — or nothing, when its words cannot carry the new amount.
    public static func scale(_ portion: String?, by factor: Double) -> String? {
        guard let portion else { return nil }
        let text = portion.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, isUsable(factor) else { return portion }
        if factor == 1 { return portion }
        guard let (amount, rest) = leadingAmount(text) else { return nil }
        let scaled = amount * factor
        guard scaled.isFinite, scaled > 0 else { return nil }
        let unit = rest.trimmingCharacters(in: .whitespaces)
        return unit.isEmpty ? format(scaled) : "\(format(scaled)) \(unit)"
    }

    /// "1.5 碗" → (1.5, "碗"), "1/2 cup" → (0.5, "cup"), "200g" → (200, "g").
    static func leadingAmount(_ text: String) -> (Double, String)? {
        var digits = ""
        var index = text.startIndex
        while index < text.endIndex, text[index].isNumber || text[index] == "." || text[index] == "/" {
            digits.append(text[index])
            index = text.index(after: index)
        }
        guard !digits.isEmpty else { return nil }
        let rest = String(text[index...])
        if digits.contains("/") {
            let parts = digits.split(separator: "/")
            guard parts.count == 2, let top = Double(parts[0]), let bottom = Double(parts[1]), bottom != 0
            else { return nil }
            return (top / bottom, rest)
        }
        guard let value = Double(digits) else { return nil }
        return (value, rest)
    }

    private static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: rounded == (rounded * 10).rounded() / 10 ? "%.1f" : "%.2f", rounded)
    }
}
