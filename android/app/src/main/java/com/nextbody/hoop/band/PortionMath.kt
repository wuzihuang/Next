package com.nextbody.hoop.band

import com.nextbody.hoop.model.rounded
import com.nextbody.hoop.model.swiftFormat
import kotlin.math.max

/**
 * Servings, without arithmetic.
 *
 * The estimate already says how much it thought the plate was — "1 碗", "200 g", "2 slices".
 * Correcting it is almost always "that was half of that" or "it was a big one", which is one
 * multiplication of four numbers the person should never have to do by hand.
 *
 * ⚠️ A portion whose words carry no number cannot be scaled honestly. "半份" doubled is not
 * "半份", and leaving the old words beside doubled calories is a claim the row no longer
 * supports — so the words are dropped and the numbers stand alone.
 */
object PortionMath {
    /** The multipliers the plate offers. One of them is the identity, which is how a person
     *  undoes a mis-tap without reaching for the keyboard. */
    val factors: List<Double> = listOf(0.5, 1.0, 1.5, 2.0)

    /** How a multiplier is printed on a pill: "0.5", "1", "1.5", "2". */
    fun label(factor: Double): String =
        if (factor == factor.rounded()) factor.toInt().toString() else swiftFormat("%.1f", factor)

    fun isUsable(factor: Double): Boolean =
        !factor.isNaN() && !factor.isInfinite() && factor > 0 && factor <= 20

    /** A nutrient, scaled to one decimal place. Never below 1 for a kcal that was
     *  positive: a quarter of a 60 kcal side is still food, and 0 means "the parser failed"
     *  everywhere else in this product. */
    fun scale(value: Double, factor: Double, floorAtOne: Boolean = false): Double {
        if (!isUsable(factor) || value.isNaN() || value.isInfinite()) return value
        val scaled = (value * factor * 10).rounded() / 10
        if (floorAtOne && value >= 1) return max(1.0, scaled)
        return max(0.0, scaled)
    }

    fun scale(value: Int, factor: Double): Int = scale(value.toDouble(), factor).rounded().toInt()

    /** The portion phrase, scaled — or nothing, when its words cannot carry the new amount. */
    fun scale(portion: String?, factor: Double): String? {
        if (portion == null) return null
        val text = portion.trim(' ', '\t')
        if (text.isEmpty() || !isUsable(factor)) return portion
        if (factor == 1.0) return portion
        val (amount, rest) = leadingAmount(text) ?: return null
        val scaled = amount * factor
        if (scaled.isNaN() || scaled.isInfinite() || scaled <= 0) return null
        val unit = rest.trim(' ', '\t')
        return if (unit.isEmpty()) format(scaled) else "${format(scaled)} $unit"
    }

    private fun isNumberChar(c: Char): Boolean = when (Character.getType(c)) {
        Character.DECIMAL_DIGIT_NUMBER.toInt(), Character.LETTER_NUMBER.toInt(), Character.OTHER_NUMBER.toInt() -> true
        else -> false
    }

    /** "1.5 碗" → (1.5, "碗"), "1/2 cup" → (0.5, "cup"), "200g" → (200, "g"). */
    fun leadingAmount(text: String): Pair<Double, String>? {
        val digits = StringBuilder()
        var index = 0
        while (index < text.length && (isNumberChar(text[index]) || text[index] == '.' || text[index] == '/')) {
            digits.append(text[index])
            index += 1
        }
        if (digits.isEmpty()) return null
        val rest = text.substring(index)
        val d = digits.toString()
        if (d.contains('/')) {
            val parts = d.split('/').filter { it.isNotEmpty() }
            if (parts.size != 2) return null
            val top = parts[0].toDoubleOrNull() ?: return null
            val bottom = parts[1].toDoubleOrNull() ?: return null
            if (bottom == 0.0) return null
            return (top / bottom) to rest
        }
        val value = d.toDoubleOrNull() ?: return null
        return value to rest
    }

    private fun format(value: Double): String {
        val rounded = (value * 100).rounded() / 100
        if (rounded == rounded.rounded()) return rounded.toInt().toString()
        return swiftFormat(if (rounded == (rounded * 10).rounded() / 10) "%.1f" else "%.2f", rounded)
    }
}
