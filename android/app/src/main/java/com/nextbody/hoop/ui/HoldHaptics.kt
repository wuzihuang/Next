package com.nextbody.hoop.ui

/**
 * Two short taps: a brief, high-sharpness click the instant the hold arms, and a crisp pulse
 * on release. The arm click is deliberately thin and bright — the orb answers the press like
 * a switch, not like a hum. Keeping the finger down does not sustain or repeat the vibration,
 * and the person's HAPTICS switch silences both.
 */
object HoldHaptics {
    /** Nothing to warm on Android; kept so call sites port 1:1. */
    fun prepare() {}

    /** One short, high-sharpness transient at the threshold; never a continuous event. */
    fun beginHold() {
        if (!HapticsSetting.enabled) return
        HapticMotor.transient(0.95f, 0.9f)
    }

    /** The finger lifted from an armed hold: one crisp tap. */
    fun release() {
        if (!HapticsSetting.enabled) return
        HapticMotor.transient(1.0f, 0.75f)
    }

    /** A cancelled or interrupted hold has no release tap. */
    fun cancel() {}
}
