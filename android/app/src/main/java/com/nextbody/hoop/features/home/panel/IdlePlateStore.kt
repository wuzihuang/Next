package com.nextbody.hoop.features.home.panel

import com.nextbody.hoop.band.IdlePlateLock
import com.nextbody.hoop.data.Defaults
import org.json.JSONObject
import java.time.Instant

/**
 * Local lock for the idle plate. The picker stays in `IdlePlateLock`; this
 * only remembers yesterday's snapshot, the DEBUG visit cursor, and when
 * the bound band last dropped.
 */
object IdlePlateStore {
    private const val snapKey = "nb.idlePlate.snapshot"
    private const val downKey = "nb.idlePlate.disconnectStamp"
    private const val visitKey = "nb.idlePlate.visitPlate"

    /** Stored as the same JSON iOS's `JSONEncoder` writes: `{"day","plate","lockedBy"}`. */
    fun load(): IdlePlateLock.Snapshot? {
        val raw = Defaults.getString(snapKey) ?: return null
        return runCatching {
            val o = JSONObject(raw)
            val lockedBy = IdlePlateLock.LockedBy.fromRaw(o.getString("lockedBy")) ?: return null
            IdlePlateLock.Snapshot(day = o.getString("day"), plate = o.getInt("plate"), lockedBy = lockedBy)
        }.getOrNull()
    }

    fun save(snap: IdlePlateLock.Snapshot) {
        val o = JSONObject()
            .put("day", snap.day)
            .put("plate", snap.plate)
            .put("lockedBy", snap.lockedBy.raw)
        Defaults.putString(snapKey, o.toString())
    }

    fun loadVisitPlate(): Int? {
        val plate = Defaults.getInt(visitKey)
        return if (plate > 0) plate else null
    }

    fun saveVisitPlate(plate: Int) {
        Defaults.putInt(visitKey, plate)
    }

    fun disconnectStamp(): Instant? = Defaults.getLong(downKey)?.let { Instant.ofEpochMilli(it) }

    /**
     * First drop of this disconnect keeps the stamp so a four-hour away
     * edge can fire. A reconnect clears it. A flap while already down
     * does not restart the clock.
     */
    fun noteConnection(connected: Boolean) {
        if (connected) {
            Defaults.remove(downKey)
        } else if (!Defaults.contains(downKey)) {
            Defaults.putLong(downKey, Instant.now().toEpochMilli())
        }
    }
}
