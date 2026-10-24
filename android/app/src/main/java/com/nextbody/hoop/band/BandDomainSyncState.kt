package com.nextbody.hoop.band

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/** An empty successful read means not collected, never an inferred healthy measurement. */
enum class BandDomainReadStatus(val raw: String) {
    complete("complete"), notCollected("not_collected"), unsupported("unsupported"), failed("failed"), partial("partial");

    companion object { fun fromRaw(raw: String): BandDomainReadStatus? = entries.firstOrNull { it.raw == raw } }
}

data class BandIngestionAcknowledgment(
    val inserted: Int,
    val completed: Int,
    val unchanged: Int,
    val rejected: Int,
    val affectedDays: List<String>,
    /** Only server-verified, equal stored content can be reused on the next read. */
    val receipts: Map<String, String>? = null,
    val needsSamples: List<String>? = null,
) {
    val hasChanges: Boolean get() = inserted + completed > 0

    fun confirms(offered: Int): Boolean =
        (needsSamples ?: emptyList()).isEmpty() && inserted >= 0 && completed >= 0 && unchanged >= 0 && rejected == 0 &&
            inserted + completed + unchanged == offered

    companion object {
        /** Decodable: keys `affected_days`, `needs_samples`. */
        fun fromJson(json: JSONObject): BandIngestionAcknowledgment {
            fun strings(a: JSONArray?) = a?.let { arr -> (0 until arr.length()).map { arr.getString(it) } }
            val receipts = json.optJSONObject("receipts")?.let { o -> o.keys().asSequence().associateWith { o.getString(it) } }
            return BandIngestionAcknowledgment(
                inserted = json.getInt("inserted"), completed = json.getInt("completed"),
                unchanged = json.getInt("unchanged"), rejected = json.getInt("rejected"),
                affectedDays = strings(json.getJSONArray("affected_days")) ?: emptyList(),
                receipts = receipts,
                needsSamples = if (json.isNull("needs_samples")) null else strings(json.optJSONArray("needs_samples")))
        }
    }
}

/** Only acknowledged ranges are durable. Each failed read/upload retains its repair range. */
data class BandDomainSyncState(
    val domain: String,
    val status: BandDomainReadStatus,
    val attemptedAt: Instant,
    val acknowledgedStart: Instant?,
    val acknowledgedEnd: Instant?,
    val repairStart: Instant?,
    val repairEnd: Instant?,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("domain", domain); put("status", status.raw)
        put("attemptedAt", BandTime.seconds(attemptedAt))
        acknowledgedStart?.let { put("acknowledgedStart", BandTime.seconds(it)) }
        acknowledgedEnd?.let { put("acknowledgedEnd", BandTime.seconds(it)) }
        repairStart?.let { put("repairStart", BandTime.seconds(it)) }
        repairEnd?.let { put("repairEnd", BandTime.seconds(it)) }
    }

    companion object {
        private fun JSONObject.instant(key: String): Instant? =
            if (has(key) && !isNull(key)) BandTime.fromSeconds(getDouble(key)) else null

        fun fromJson(o: JSONObject): BandDomainSyncState = BandDomainSyncState(
            domain = o.getString("domain"),
            status = BandDomainReadStatus.fromRaw(o.getString("status")) ?: throw IllegalArgumentException("status"),
            attemptedAt = BandTime.fromSeconds(o.getDouble("attemptedAt")),
            acknowledgedStart = o.instant("acknowledgedStart"), acknowledgedEnd = o.instant("acknowledgedEnd"),
            repairStart = o.instant("repairStart"), repairEnd = o.instant("repairEnd"))

        fun load(userId: String, deviceKey: String, day: String): List<BandDomainSyncState> {
            val raw = BandPrefs.string(key(userId, deviceKey, day)) ?: return emptyList()
            return runCatching {
                val array = JSONArray(raw)
                (0 until array.length()).map { fromJson(array.getJSONObject(it)) }
            }.getOrDefault(emptyList())
        }

        fun save(states: List<BandDomainSyncState>, userId: String, deviceKey: String, day: String) {
            val previous = load(userId, deviceKey, day)
            val merged = states.map { state ->
                val old = previous.firstOrNull { it.domain == state.domain }
                state.copy(
                    acknowledgedStart = state.acknowledgedStart ?: old?.acknowledgedStart,
                    acknowledgedEnd = state.acknowledgedEnd ?: old?.acknowledgedEnd)
            }
            BandPrefs.setString(key(userId, deviceKey, day), JSONArray(merged.map { it.toJson() }).toString())
        }

        fun purge(userId: String) {
            val prefixes = listOf("nb.sync.domains.v1.$userId.", "nb.sync.day-outcome.v1.$userId.")
            for (key in BandPrefs.keys.toList()) if (prefixes.any { key.startsWith(it) }) BandPrefs.remove(key.removeSuffix("#d"))
        }

        private fun key(user: String, device: String, day: String) = "nb.sync.domains.v1.$user.$device.$day"
    }
}
