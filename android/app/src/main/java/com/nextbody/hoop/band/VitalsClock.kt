package com.nextbody.hoop.band

import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.data.DebugEnv
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId

// From Features/Home/VitalsPage.swift — the seed board and the vitals pages share one "now".

/**
 * One "now" for page two and the boards behind it. DEBUG seed can freeze the
 * clock with `NB_DEBUG_NOW` so a UITest and the charts agree.
 */
object VitalsClock {
    val now: Instant
        get() {
            if (BuildConfig.DEBUG && Band.allowsSeed) {
                val raw = DebugEnv["NB_DEBUG_NOW"]
                if (raw != null) {
                    runCatching { return OffsetDateTime.parse(raw).toInstant() }
                    // `.withFullDate, .withTime` without a zone: read as local time.
                    runCatching { return LocalDateTime.parse(raw).atZone(ZoneId.systemDefault()).toInstant() }
                }
            }
            return Instant.now()
        }
}
