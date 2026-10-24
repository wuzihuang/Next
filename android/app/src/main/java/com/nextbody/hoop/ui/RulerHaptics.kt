package com.nextbody.hoop.ui

import android.os.SystemClock

/**
 * The detents of a physical ruler under the thumb. Every 0.1 is a thin, bright click; every
 * 0.5 is a touch heavier; every whole unit is a full notch you could count without looking.
 * A fast flick blurs the minor clicks the way a ratchet does — quieter and spaced out so the
 * motor never smears into a buzz — while the whole-unit notches still land. Hitting either
 * end of the range is one dull bump, not a click, and it does not repeat while the finger
 * keeps pushing.
 */
class RulerHaptics {
    enum class Mark { Minor, Half, Major }

    private var lastFire = 0.0
    private var atEdge = false

    private fun now(): Double = SystemClock.uptimeMillis() / 1000.0

    /** Kept so call sites port 1:1 (warms the engine on iOS). */
    fun prepare() {}

    /** The needle crossed one or more ticks; [mark] is the most significant one it crossed. */
    fun tick(mark: Mark) {
        atEdge = false
        if (!HapticsSetting.enabled) return
        val now = now()
        val gap = now - lastFire
        if (mark == Mark.Minor && gap < MIN_GAP) return
        lastFire = now

        // How hard the thumb is moving: 0 at a slow crawl, 1 at a flick.
        val speed = ((FLICK_GAP * 2 - gap) / FLICK_GAP).coerceIn(0.0, 1.0).toFloat()
        val (intensity, sharpness) = when (mark) {
            Mark.Minor -> (0.42f - 0.17f * speed) to 0.95f
            Mark.Half -> (0.62f - 0.12f * speed) to 0.85f
            Mark.Major -> 0.92f to 0.6f
        }
        HapticMotor.transient(intensity, sharpness)
    }

    /** The value pinned at either end of the range. */
    fun edge() {
        if (atEdge) return
        atEdge = true
        if (!HapticsSetting.enabled) return
        lastFire = now()
        HapticMotor.transient(1.0f, 0.2f)
    }

    /** The finger lifted; the next push into an edge bumps again. */
    fun end() {
        atEdge = false
    }

    private companion object {
        /** Below this gap the motor cannot separate two transients; minor clicks inside it drop. */
        const val MIN_GAP = 0.018
        /** At or below this gap the drag counts as a flick and the minor clicks soften. */
        const val FLICK_GAP = 0.045
    }
}
