package com.nextbody.hoop.band

/** Pure F1 §02 / 01-code helpers. Kept free of Android UI so they run under plain JUnit. */
object LaunchGate {
    fun stage(hasBoundBand: Boolean, profileComplete: Boolean): String {
        if (hasBoundBand && profileComplete) return "root"
        if (hasBoundBand) return "gateOnboarding"
        return "gateConnect"
    }

    fun isFirstRun(hasBoundBand: Boolean, profileComplete: Boolean): Boolean = !hasBoundBand && !profileComplete

    fun isExpiredCode(status: Int, body: String): Boolean {
        if (status == 429) return false
        val text = body.lowercase()
        return text.contains("otp_expired") || text.contains("token has expired")
    }
}
