package com.nextbody.hoop.band

/** Cold-start cover is a still: PingFang `NextBody` + the launch line.
 *  No film. Harness launches skip the cover so UI tests keep the 1.2s door. */
object LaunchFilmPolicy {
    /** Same key `FirstRun` writes after the 7.40s page fold. */
    const val firstRunPlayedKey = "nb.firstRunPlayed"
    const val lastDurationKey = "nb.launch.lastMs"

    /** Stamped on first access. `NextBodyApplication.onCreate` must touch it so the clock
     *  starts at process entry, not at the first Compose frame. Seconds (monotonic). */
    val processStart: Double = System.nanoTime() / 1_000_000_000.0

    val elapsed: Double get() = System.nanoTime() / 1_000_000_000.0 - processStart

    fun shouldHoldStill(environment: Map<String, String>): Boolean = !isHarness(environment)

    fun isHarness(environment: Map<String, String>): Boolean {
        if (environment["XCTestConfigurationFilePath"] != null) return true
        if (environment["NB_DEBUG_STAGE"] != null) return true
        if (environment["NB_DEBUG_ROUTE"] != null) return true
        if (environment["NB_DEBUG_TAKEOVER"] != null) return true
        return false
    }
}
