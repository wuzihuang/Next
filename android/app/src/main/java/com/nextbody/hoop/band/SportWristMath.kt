package com.nextbody.hoop.band

/**
 * What a sport-mode report is allowed to say about the wrist.
 *
 * NEXTBODY's sport packet is `heartRate = 0` until the optical lock lands — often
 * about twenty seconds after the mode opens. That zero is "not yet", not a
 * loose strap. The same path already learned this on the heart *test*
 * (`VPTestHeartStateStart`); the live report used to treat every empty beat
 * as `noContact` and paint TIGHTEN THE BAND for the whole lock.
 */
object SportWristMath {
    /** First optical lock after the mode is running. Longer than the ~20 s NEXTBODY
     *  typically needs, short enough that a band on the table still gets said. */
    const val acquireGrace: Double = 30.0
    /** After a lock, a brief zero is a dropout. Same window as a live beat. */
    const val dropoutGrace: Double = SportMetricAccumulator.liveWindow

    enum class Face { reaching, live, noContact, paused }

    fun face(runState: Int?, heartRate: Int?, hadHeart: Boolean, seekingFor: Double, silentFor: Double): Face {
        if (runState == 2) return Face.paused
        if (heartRate != null && heartRate in 1..255) return Face.live
        if (!hadHeart) return if (seekingFor < acquireGrace) Face.reaching else Face.noContact
        return if (silentFor < dropoutGrace) Face.reaching else Face.noContact
    }
}
