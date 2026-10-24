package com.nextbody.hoop.model

import com.nextbody.hoop.l10n.L

/**
 * One sport the band can be asked to open. Raw values are `VPDeviceRuningMode` ordinals
 * in the SDK header's own order. The product list stops at Dumbbell (#47) — that is the
 * set Device's DEBUG probe already enumerates, not the full enum (100+).
 */
data class SportModeOption(val rawValue: Int, val name: String) {
    val id: Int get() = rawValue
    val displayName: String get() = L(name)
}

object SportModeCatalog {
    val modes: List<SportModeOption> = listOf(
        SportModeOption(0, "Common"),
        SportModeOption(1, "Outdoor run"),
        SportModeOption(2, "Outdoor walk"),
        SportModeOption(3, "Indoor run"),
        SportModeOption(4, "Indoor walk"),
        SportModeOption(5, "Hiking"),
        SportModeOption(6, "Stair stepper"),
        SportModeOption(7, "Outdoor cycle"),
        SportModeOption(8, "Stationary bike"),
        SportModeOption(9, "Elliptical"),
        SportModeOption(10, "Rowing machine"),
        SportModeOption(11, "Mountaineering"),
        SportModeOption(12, "Swim"),
        SportModeOption(13, "Sit-ups"),
        SportModeOption(14, "Ski"),
        SportModeOption(15, "Jump rope"),
        SportModeOption(16, "Yoga"),
        SportModeOption(17, "Table tennis"),
        SportModeOption(18, "Basketball"),
        SportModeOption(19, "Volleyball"),
        SportModeOption(20, "Football"),
        SportModeOption(21, "Badminton"),
        SportModeOption(22, "Tennis"),
        SportModeOption(23, "Stair climb"),
        SportModeOption(24, "Fitness"),
        SportModeOption(25, "Weightlifting"),
        SportModeOption(26, "Diving"),
        SportModeOption(27, "Boxing"),
        SportModeOption(28, "Gym ball"),
        SportModeOption(29, "Squat training"),
        SportModeOption(30, "Triathlon"),
        SportModeOption(31, "Dance"),
        SportModeOption(32, "HIIT"),
        SportModeOption(33, "Rock climbing"),
        SportModeOption(34, "Sports"),
        SportModeOption(35, "Balls"),
        SportModeOption(36, "Fitness game"),
        SportModeOption(37, "Free time"),
        SportModeOption(38, "Aerobics"),
        SportModeOption(39, "Gymnastics"),
        SportModeOption(40, "Floor exercise"),
        SportModeOption(41, "Horizontal bar"),
        SportModeOption(42, "Parallel bars"),
        SportModeOption(43, "Trampoline"),
        SportModeOption(44, "Track & field"),
        SportModeOption(45, "Marathon"),
        SportModeOption(46, "Push-ups"),
        SportModeOption(47, "Dumbbell"),
    )

    /** The picker's row order: A→Z on the English name. `modes` itself stays in SDK
     *  `rawValue` order for the Device debug probe and ordinal lookups.
     *  (Swift `localizedStandardCompare`: case-insensitive; no digits in these names.) */
    val displayModes: List<SportModeOption> =
        modes.sortedWith { a, b -> String.CASE_INSENSITIVE_ORDER.compare(a.name, b.name) }

    fun name(rawValue: Int): String {
        val name = modes.firstOrNull { it.rawValue == rawValue }?.name
        if (name != null) return L(name)
        return L("Sport #%d", rawValue)
    }
}
