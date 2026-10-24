package com.nextbody.hoop.ui

import android.os.SystemClock

/**
 * The stream you can feel: a hair-light transient under the characters as they land, a
 * firmer one when a line is whole, and one crisp tap when the turn is over.
 *
 * Three rules keep it from turning into a buzz:
 * * the typing tick is throttled — anything over ~12 taps a second reads as a motor;
 * * intensity is low and sharpness mid — a keyboard tap, not an alert;
 * * Reduce Motion, Battery Saver and hardware without composition primitives get nothing
 *   rather than a coarse thud on every character. The line and turn taps still land.
 */
object StreamHaptics {
    /** Fastest the character tick may repeat (46 cps typing lands roughly every fourth char). */
    private const val TYPE_INTERVAL = 0.085
    private var lastType = 0.0
    private var lastLine = 0.0
    private var active = false

    private fun now(): Double = SystemClock.uptimeMillis() / 1000.0

    /** A turn started. */
    fun activate() {
        active = true
    }

    /** The turn ended, or the screen went away: a stale stream cannot keep tapping. */
    fun deactivate() {
        active = false
    }

    /** One character landed. Cheap, throttled, and skipped entirely when the turn is not live. */
    fun type() {
        if (!active || quiet || !HapticMotor.rich) return
        val now = now()
        if (now - lastType < TYPE_INTERVAL) return
        lastType = now
        HapticMotor.transient(0.26f, 0.62f)
    }

    /** A whole line arrived. Softer and rounder than a character so the two are distinguishable. */
    fun lineLanded() {
        if (!active) return
        val now = now()
        if (now - lastLine < 0.12) return
        lastLine = now
        lastType = now
        if (quiet) return
        HapticMotor.transient(0.5f, 0.35f)
    }

    /**
     * The turn is over and the answer is on screen. One needle — a single high-sharpness
     * transient. It fires even under Reduce Motion: it is an outcome, not decoration.
     */
    fun settled() {
        if (!HapticsSetting.enabled) return
        HapticMotor.transient(0.9f, 1.0f)
    }

    /** Reduce Motion and Battery Saver both mean: do not run a motor for texture. */
    private val quiet: Boolean
        get() {
            if (!HapticsSetting.enabled) return true
            val ctx = HapticMotor.appContext ?: return false
            return SystemMotion.reduceMotion(ctx) || SystemMotion.lowPower(ctx)
        }
}
