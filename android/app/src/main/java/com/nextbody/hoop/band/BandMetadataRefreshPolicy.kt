package com.nextbody.hoop.band

/** Process-local: each new app process initializes once, not every health-data pull.
 *  Only confirmed publication can be reused, and never for another ownership row/firmware. */
class BandMetadataRefreshPolicy {
    data class Key(
        val account: String,
        val binding: String,
        val deviceID: String,
        val firmware: String,
    )

    private var confirmed: Key? = null

    fun needsRefresh(key: Key?): Boolean = key == null || key != confirmed

    fun complete(key: Key?, success: Boolean) {
        if (success) confirmed = key
    }
}
