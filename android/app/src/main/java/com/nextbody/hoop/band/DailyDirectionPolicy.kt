package com.nextbody.hoop.band

/**
 * F2 §06 / F0 D05 · Daily Direction colour gates, kept free of SwiftUI so
 * NextBodySyncCore can pin the heat-map cases.
 *
 * Calendar close is not a gate. The fuel page already shows live E_OUT_NOW, and
 * the heat map has to light the same day the equation exists — otherwise a user
 * who logged two slots and wore the band still sees 182 empty squares until 04:00.
 */
object DailyDirectionPolicy {
    sealed class Fuel {
        data object Unlogged : Fuel()
        data class Partial(val slots: Int) : Fuel()
        data object Fasted : Fuel()
        data object Confirmed : Fuel()
    }

    enum class Color(val raw: String) {
        deficit("deficit"),
        level("level"),
        surplus("surplus"),
        greyNothing("greyNothing"),
        greyNoBurn("greyNoBurn"),
    }

    fun color(balance: Double?, fuel: Fuel, bandCoverage: Double): Color {
        when (fuel) {
            Fuel.Unlogged -> return Color.greyNothing
            is Fuel.Partial -> if (fuel.slots < 2) return Color.greyNothing
            else -> {}
        }
        // 0 is "not loaded", not "wore the band 0% of the day". A computed balance
        // already required burn, so only a known-low coverage is NO BURN.
        if (bandCoverage > 0 && bandCoverage < 0.5) return Color.greyNoBurn
        if (balance == null) return Color.greyNoBurn
        if (balance <= -150) return Color.deficit
        if (balance >= 150) return Color.surplus
        return Color.level
    }
}
