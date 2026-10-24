package com.nextbody.hoop.band

import kotlin.math.abs

/** Phone-find-wrist distance. Same RSSI cuts as the vendor table; the words are
 *  how far, never how good. */
enum class FindDistance(val raw: String) {
    near("near"), close("close"), away("away"), far("far");

    val label: String
        get() = when (this) { near -> "NEAR"; close -> "CLOSE"; away -> "AWAY"; far -> "FAR" }

    /** Chinese catalog keys. Never `CLOSE` (that key means dismiss → 关闭)
     *  or `NEAR` (vitals → 近中位). English UI still paints `label`. */
    val copyKey: String
        get() = when (this) {
            near -> "Find · very near"; close -> "Find · nearer"
            away -> "Find · farther"; far -> "Find · very far"
        }

    /** One step farther on the lamp strip. FAR has nowhere left to fall. */
    val farther: FindDistance?
        get() = when (this) { near -> close; close -> away; away -> far; far -> null }

    /** Timeout face's four rising pips. Strength counts from the left. */
    val barsLit: Int
        get() = when (this) { near -> 4; close -> 3; away -> 2; far -> 1 }

    companion object {
        /** Paper KLF-0: current cell is lime, the next farther cell is a 40% falloff,
         *  the rest sit at hairline. Not a single isolated square. */
        fun glow(lamp: FindDistance, current: FindDistance?): FindLampGlow {
            if (current == null) return FindLampGlow.off
            if (lamp == current) return FindLampGlow.hot
            if (lamp == current.farther) return FindLampGlow.warm
            return FindLampGlow.off
        }

        /** Unicode minus so −52 matches the instrument face, not a hyphen. */
        fun glyph(rssi: Int): String = if (rssi < 0) "−${abs(rssi)}" else "$rssi"

        /** NEAR `> −60`. CLOSE `−70 … −60` inclusive. AWAY `−85 … < −70`. FAR `< −85`.
         *  −70 is CLOSE. −85 is AWAY. */
        fun from(rssi: Int): FindDistance {
            if (rssi > -60) return near
            if (rssi >= -70) return close
            if (rssi >= -85) return away
            return far
        }
    }
}

/** Stepped lime on the LED strip. Hot is the current distance. */
enum class FindLampGlow { hot, warm, off }

/** Firmware answers from `veepooSDK_searchDeviceFuntionWithState`. */
enum class FindHoopPhase(val raw: Int) {
    unsupported(0), enter(1), exit(2), timeout(3);

    companion object {
        fun from(rawValue: Int): FindHoopPhase = entries.firstOrNull { it.raw == rawValue } ?: unsupported
        fun fromRaw(raw: Int): FindHoopPhase? = entries.firstOrNull { it.raw == raw }
    }
}
