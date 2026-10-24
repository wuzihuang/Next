package com.nextbody.hoop.features.home

/**
 * Linear sRGB channels in 0…1. Compose wraps the result in a `Color`; this stays pure
 * so the body-map hues can be tested without the app.
 */
data class BodyRGB(val red: Double, val green: Double, val blue: Double, val alpha: Double = 1.0) {
    fun mixed(other: BodyRGB, fraction: Double): BodyRGB {
        val t = minOf(1.0, maxOf(0.0, fraction))
        fun lerp(a: Double, b: Double) = a + (b - a) * t
        return BodyRGB(lerp(red, other.red), lerp(green, other.green), lerp(blue, other.blue), lerp(alpha, other.alpha))
    }
}

/**
 * The two data-driven hues on the Home body map. Legs grade by step volume, not by
 * shortfall: low is neutral, ~8k green, 10k yellow, 20k orange, 30k+ orange-red.
 * Gut mixes the macro colours by their share of recorded calories.
 */
object BodyTintMath {
    data class LegPalette(
        val neutral: BodyRGB,
        val green: BodyRGB,
        val yellow: BodyRGB,
        val orange: BodyRGB,
        val orangeRed: BodyRGB,
    )

    val legStops: List<Double> = listOf(0.0, 8_000.0, 10_000.0, 20_000.0, 30_000.0)

    fun legs(steps: Double?, palette: LegPalette): BodyRGB {
        if (steps == null || !steps.isFinite() || steps <= 0) return palette.neutral
        val colors = listOf(palette.neutral, palette.green, palette.yellow, palette.orange, palette.orangeRed)
        val upper = legStops.indexOfFirst { steps <= it }
        if (upper < 0) return palette.orangeRed
        val low = legStops[upper - 1]
        val high = legStops[upper]
        return colors[upper - 1].mixed(colors[upper], (steps - low) / (high - low))
    }

    /** 0.35 for any reading, rising to full at 30k so heavy days glow harder. */
    fun legsIntensity(steps: Double?): Double =
        0.35 + 0.65 * minOf(1.0, maxOf(0.0, (steps ?: 0.0) / legStops[legStops.size - 1]))

    /**
     * Protein and carbohydrate at 4 kcal/g, fat at 9. A missing macro adds nothing;
     * with no macro calories at all there is no composition to show.
     */
    fun gut(
        protein: Int?, carb: Int?, fat: Int?,
        proteinColor: BodyRGB, carbColor: BodyRGB, fatColor: BodyRGB,
    ): BodyRGB? {
        val kcal = listOf((protein ?: 0) * 4.0, (carb ?: 0) * 4.0, (fat ?: 0) * 9.0)
        val colors = listOf(proteinColor, carbColor, fatColor)
        val parts = kcal.zip(colors).filter { it.first > 0 }
        val total = parts.sumOf { it.first }
        if (total <= 0) return null
        return parts.fold(BodyRGB(0.0, 0.0, 0.0)) { sum, part ->
            val share = part.first / total
            BodyRGB(sum.red + part.second.red * share, sum.green + part.second.green * share,
                sum.blue + part.second.blue * share)
        }
    }
}
