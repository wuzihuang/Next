package com.nextbody.hoop.band

import java.util.UUID

/** One native sport callback serves the live screen and short state probes together.
 *  A stale reader's cleanup cannot remove a later session's callback. (Main-thread only.) */
class BandSportSubscription {
    private val readers = mutableSetOf<UUID>()
    var generation = 0
        private set

    fun add(id: UUID): Boolean {
        val first = readers.isEmpty()
        readers.add(id)
        if (first) generation += 1
        return first
    }

    fun remove(id: UUID): Boolean {
        if (!readers.remove(id)) return false
        return readers.isEmpty()
    }

    fun contains(id: UUID): Boolean = id in readers
}
