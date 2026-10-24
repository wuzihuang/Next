package com.nextbody.hoop.band

import com.nextbody.hoop.services.storage.LocalDataStore
import com.nextbody.hoop.services.storage.LocalOperation
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.util.UUID

/** A completed session's observations. Calculated training load is always read from
 *  the current server settlement; this document never becomes a second load ledger. */
data class SportSessionRecap(
    val title: String,
    val startedAt: Instant,
    val endedAt: Instant,
    val seconds: Int,
    val avgHR: Int?,
    val peakHR: Int?,
    val kcal: Double,
    val caloriesEstimated: Boolean,
    val curve: List<Double>,
    val zoneMinutes: List<Double>,
    val aerobicMinutes: Int,
    val anaerobicMinutes: Int,
    val conclusion: String,
    val sessionID: UUID?,
    val ownerUserID: String?,
    val loadBefore: Double?,
    val loadAfter: Double?,
    val curvePoints: List<SportRecapMath.Beat>? = null,
    val observedSeconds: Double? = null,
    val hasCalories: Boolean? = null,
    val restHR: Int? = null,
    val maxHR: Int? = null,
    val energyObservedSeconds: Double? = null,
) {
    val id: String get() = sessionID?.toString()?.uppercase() ?: BandTime.seconds(startedAt).toString()
    val hasZones: Boolean get() = (observedSeconds ?: (if (avgHR == null) 0.0 else 1.0)) > 0
    val hasEnergy: Boolean get() = hasCalories ?: (kcal > 0)
    val isValid: Boolean
        get() = endedAt >= startedAt && BandTime.interval(endedAt, startedAt) <= 86_400
            && seconds in 0..86_400 && kcal.isFinite() && kcal in 0.0..100_000.0
            && (energyObservedSeconds?.let { it.isFinite() && it in 0.0..86_400.0 } ?: true)
            && zoneMinutes.size == 5 && zoneMinutes.all { it.isFinite() && it in 0.0..1440.0 }
            && (curvePoints?.all { it.bpm in 1..250 } ?: true)

    /** Swift `JSONEncoder` shape: dates as seconds since 2001-01-01, UUIDs uppercase, nil keys omitted. */
    fun toJson(): JSONObject = JSONObject().apply {
        put("title", title)
        put("startedAt", encodeDate(startedAt))
        put("endedAt", encodeDate(endedAt))
        put("seconds", seconds)
        avgHR?.let { put("avgHR", it) }
        peakHR?.let { put("peakHR", it) }
        put("kcal", kcal)
        put("caloriesEstimated", caloriesEstimated)
        put("curve", JSONArray(curve))
        put("zoneMinutes", JSONArray(zoneMinutes))
        put("aerobicMinutes", aerobicMinutes)
        put("anaerobicMinutes", anaerobicMinutes)
        put("conclusion", conclusion)
        sessionID?.let { put("sessionID", it.toString().uppercase()) }
        ownerUserID?.let { put("ownerUserID", it) }
        loadBefore?.let { put("loadBefore", it) }
        loadAfter?.let { put("loadAfter", it) }
        curvePoints?.let { pts ->
            put("curvePoints", JSONArray().apply {
                pts.forEach { b -> put(JSONObject().put("at", encodeDate(b.at)).put("bpm", b.bpm).put("segment", b.segment)) }
            })
        }
        observedSeconds?.let { put("observedSeconds", it) }
        hasCalories?.let { put("hasCalories", it) }
        restHR?.let { put("restHR", it) }
        maxHR?.let { put("maxHR", it) }
        energyObservedSeconds?.let { put("energyObservedSeconds", it) }
    }

    companion object {
        private const val referenceDate = 978_307_200.0
        fun encodeDate(i: Instant): Double = BandTime.seconds(i) - referenceDate
        fun decodeDate(d: Double): Instant = BandTime.fromSeconds(d + referenceDate)

        fun fromJson(o: JSONObject): SportSessionRecap {
            fun optInt(k: String): Int? = if (o.has(k) && !o.isNull(k)) o.getInt(k) else null
            fun optDouble(k: String): Double? = if (o.has(k) && !o.isNull(k)) o.getDouble(k) else null
            fun doubles(a: JSONArray): List<Double> = (0 until a.length()).map { a.getDouble(it) }
            return SportSessionRecap(
                title = o.getString("title"),
                startedAt = decodeDate(o.getDouble("startedAt")),
                endedAt = decodeDate(o.getDouble("endedAt")),
                seconds = o.getInt("seconds"),
                avgHR = optInt("avgHR"),
                peakHR = optInt("peakHR"),
                kcal = o.getDouble("kcal"),
                caloriesEstimated = o.getBoolean("caloriesEstimated"),
                curve = doubles(o.getJSONArray("curve")),
                zoneMinutes = doubles(o.getJSONArray("zoneMinutes")),
                aerobicMinutes = o.getInt("aerobicMinutes"),
                anaerobicMinutes = o.getInt("anaerobicMinutes"),
                conclusion = o.getString("conclusion"),
                sessionID = if (o.has("sessionID") && !o.isNull("sessionID")) UUID.fromString(o.getString("sessionID")) else null,
                ownerUserID = if (o.has("ownerUserID") && !o.isNull("ownerUserID")) o.getString("ownerUserID") else null,
                loadBefore = optDouble("loadBefore"),
                loadAfter = optDouble("loadAfter"),
                curvePoints = o.optJSONArray("curvePoints")?.let { a ->
                    (0 until a.length()).map { i ->
                        val b = a.getJSONObject(i)
                        SportRecapMath.Beat(decodeDate(b.getDouble("at")), b.getInt("bpm"), b.optInt("segment", 0))
                    }
                },
                observedSeconds = optDouble("observedSeconds"),
                hasCalories = if (o.has("hasCalories") && !o.isNull("hasCalories")) o.getBoolean("hasCalories") else null,
                restHR = optInt("restHR"),
                maxHR = optInt("maxHR"),
                energyObservedSeconds = optDouble("energyObservedSeconds"))
        }

        fun encodeList(recaps: List<SportSessionRecap>): ByteArray =
            JSONArray().apply { recaps.forEach { put(it.toJson()) } }.toString().toByteArray(Charsets.UTF_8)

        fun decodeList(data: ByteArray): List<SportSessionRecap> {
            val a = JSONArray(String(data, Charsets.UTF_8))
            return (0 until a.length()).map { fromJson(a.getJSONObject(it)) }
        }
    }
}

/** Account-scoped cache and durable outbox share a transaction. A crash between
 *  upload and acknowledgement repeats the same immutable session ID and payload. */
class SportRecapArchive(val local: LocalDataStore) {
    fun read(owner: String): List<SportSessionRecap> {
        val data = local.readDocument(account = owner, key = key) ?: return emptyList()
        return SportSessionRecap.decodeList(data).filter { it.ownerUserID == owner && it.isValid }
    }

    fun stage(recap: SportSessionRecap, owner: String) {
        val id = recap.sessionID
        if (recap.ownerUserID != owner || !recap.isValid || id == null) throw LocalDataStore.Failure.InvalidOwner()
        val merged = merge(listOf(recap), owner)
        local.enqueue(
            operation = LocalOperation(id = "sport-recap:${id.toString().lowercase()}",
                account = owner, kind = kind, payload = recap.toJson().toString().toByteArray(Charsets.UTF_8)),
            documentKey = key, document = SportSessionRecap.encodeList(merged))
    }

    /** One unsupported or damaged in-memory record cannot block already valid work.
     *  Failed records stay with the caller so retry never silently discards observations. */
    fun stagePending(recaps: List<SportSessionRecap>, owner: String): List<SportSessionRecap> =
        recaps.filter { recap -> runCatching { stage(recap, owner) }.isFailure }

    fun cache(recaps: List<SportSessionRecap>, owner: String) {
        local.writeDocument(account = owner, key = key, data = SportSessionRecap.encodeList(merge(recaps, owner)))
    }

    private fun merge(recaps: List<SportSessionRecap>, owner: String): List<SportSessionRecap> {
        val rows = LinkedHashMap<String, SportSessionRecap>()
        read(owner).forEach { rows[it.id] = it }
        for (recap in recaps) if (recap.ownerUserID == owner) rows[recap.id] = recap
        return rows.values.sortedByDescending { it.startedAt }
    }

    companion object {
        const val kind = "sport-recap"
        const val key = "sport-recaps"
    }
}
