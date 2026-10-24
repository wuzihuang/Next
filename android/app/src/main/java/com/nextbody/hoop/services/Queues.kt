package com.nextbody.hoop.services

import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandLog
import com.nextbody.hoop.band.BodyCompositionReading
import com.nextbody.hoop.band.SportEnergyEvidence
import com.nextbody.hoop.band.SportHeartRateEvidence
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.data.WeighIn
import com.nextbody.hoop.data.WeighInQueuePort
import com.nextbody.hoop.services.storage.DurableQueue
import com.nextbody.hoop.services.storage.JsonCodec
import com.nextbody.hoop.services.storage.LocalDataStore
import com.nextbody.hoop.services.storage.LocalOperation
import com.nextbody.hoop.services.storage.ReflectJson
import com.nextbody.hoop.services.storage.lower
import com.nextbody.hoop.services.storage.sortedBytes
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** Main-thread scope the queues use for Swift's `Task { … }`. */
internal val queueScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

/** Runs `flush` whenever the connection comes back (Swift `Reachability.$isOnline.sink`). */
internal fun onReconnect(flush: suspend () -> Unit) {
    queueScope.launch {
        var previous: Boolean? = null
        Reachability.online.collect { online ->
            if (online && previous != null) launch { flush() }
            previous = online
        }
    }
}

private fun isConflict(e: Throwable): Boolean = e is SupabaseFailure.Http && e.code == 409
private fun rethrowCancel(e: Throwable) { if (e is CancellationException && e !is SessionChangedException) throw e }

/**
 * 10S rule 09 · save is optimistic: the sheet closes, the number changes, and the row goes up
 * when it can. OFFLINE: `SAVED · NOT SYNCED`. Pending rows survive a relaunch.
 */
object WeighInQueue : WeighInQueuePort {
    data class Pending(
        /** client_op_id — the server dedupes on it. */
        val id: UUID,
        val measuredAt: Instant,
        val tz: String,
        val kg: Double,
        /** 'manual' | 'health' | 'band' */
        val source: String,
        val healthUUID: String?,
        /** The account that created this operation; never reassigned to whoever signs in next. */
        val ownerUserId: String?,
    )

    private val _pending = MutableStateFlow<List<Pending>>(emptyList())
    val pending: StateFlow<List<Pending>> = _pending.asStateFlow()
    private val _persistenceError = MutableStateFlow<String?>(null)
    val persistenceError: StateFlow<String?> = _persistenceError.asStateFlow()
    private var flushing = false
    private val flushWaiters = mutableListOf<CompletableDeferred<Unit>>()
    private val codec: JsonCodec<Pending> = ReflectJson.codec(Pending::class.java)

    private fun durable() = DurableQueue("weigh-in", LocalDataStore.shared(), codec)

    fun init() {
        try { _pending.value = durable().items() } catch (e: Exception) { _persistenceError.value = e.message }
        onReconnect { flush() }
    }

    /**
     * 11 · DELETE EVERYTHING. ⚠️ Rows left on the phone are flushed by whoever signs in next;
     * clear in memory and on disk.
     */
    override fun purge() {
        try {
            for (row in _pending.value) row.ownerUserId?.let { durable().acknowledge(row.id.toString().uppercase(), it) }
            _pending.value = emptyList()
        } catch (e: Exception) { _persistenceError.value = e.message }
    }

    fun isPending(id: UUID): Boolean = _pending.value.any { it.id == id }

    override fun enqueue(weighIn: WeighIn, ownerUserId: String) {
        val source = when (weighIn.origin) {
            WeighIn.Origin.health -> "health"
            WeighIn.Origin.band -> "band"
            WeighIn.Origin.manual -> "manual"
        }
        val item = Pending(weighIn.id, weighIn.date, ZoneId.systemDefault().id, weighIn.weightKg, source,
            weighIn.healthUUID, ownerUserId)
        durable().save(item, item.id.toString().uppercase(), ownerUserId)
        _pending.value = durable().items()
        queueScope.launch { flush() }
    }

    /**
     * One row at a time, oldest first. A refusal that means "already there" clears the row
     * too; anything else keeps it for the next try.
     */
    suspend fun flush(): Boolean = withContext(Dispatchers.Main.immediate) {
        if (flushing) {
            val waiter = CompletableDeferred<Unit>()
            flushWaiters += waiter
            waiter.await()
            // Another edit may have been queued during the upload we just awaited.
            return@withContext flush()
        }
        if (_pending.value.isEmpty()) return@withContext true
        if (!Reachability.isOnline || DebugEdgeFlag.on("offline")) return@withContext false
        flushing = true
        try {
            val userId = SupabaseClient.userId ?: return@withContext false
            for (row in _pending.value.filter { it.ownerUserId == userId }) {
                if (SupabaseClient.userId != userId) return@withContext false
                val opId = row.id.toString().uppercase()
                try {
                    SupabaseClient.insert("weigh_ins", listOf(mapOf(
                        "user_id" to userId,
                        "measured_at" to Iso.fractional(row.measuredAt),
                        "sampled_tz" to row.tz,
                        "weight_kg" to row.kg,
                        "source" to row.source,
                        "health_uuid" to row.healthUUID,
                        "client_op_id" to row.id.lower())), returning = false)
                    if (SupabaseClient.currentUserIdSnapshot() != userId || !currentCoroutineContext().isActive) return@withContext false
                    durable().acknowledge(opId, userId)
                    _pending.value = _pending.value.filter { it.id != row.id }
                    Analytics.track("WEIGHIN_SYNCED", mapOf("SOURCE" to row.source))
                } catch (e: Exception) {
                    rethrowCancel(e)
                    if (!isConflict(e)) {
                        ServiceLog.record("WeighInQueue: kept ${row.id}", e)
                        break
                    }
                    try {
                        val accepted = SupabaseClient.select("weigh_ins", listOf(
                            "client_op_id" to "eq.${row.id.lower()}",
                            "user_id" to "eq.$userId",
                            "select" to "weight_kg,source,measured_at"))
                        val fact = accepted.firstOrNull() ?: break
                        val date = Iso.parse(fact.optStringOrNull("measured_at")) ?: break
                        if (fact.number("weight_kg") != row.kg || fact.optStringOrNull("source") != row.source ||
                            kotlin.math.abs(java.time.Duration.between(row.measuredAt, date).toNanos()) >= 1_000_000) break
                        if (SupabaseClient.currentUserIdSnapshot() != userId || !currentCoroutineContext().isActive) return@withContext false
                        durable().acknowledge(opId, userId)
                        _pending.value = _pending.value.filter { it.id != row.id }
                    } catch (inner: Exception) {
                        rethrowCancel(inner)
                        _persistenceError.value = inner.message
                        break
                    }
                }
            }
            _pending.value.none { it.ownerUserId == userId }
        } finally {
            flushing = false
            val waiters = flushWaiters.toList()
            flushWaiters.clear()
            waiters.forEach { it.complete(Unit) }
        }
    }
}

/**
 * Durable, account-owned outbox for band BIA results. A scan is too expensive to repeat just
 * because the phone was offline, and it must never be uploaded under a later account.
 */
object BodyCompositionQueue {
    data class Pending(
        val id: UUID,
        val ownerUserId: String,
        val measuredAt: Instant,
        val userDay: String,
        val inputWeightKg: Double,
        val bodyFatPercent: Double,
        val fatMassKg: Double,
        val leanMassKg: Double,
        val bmrKcal: Int?,
        val muscleMassKg: Double? = null,
        val bodyWaterPercent: Double? = null,
        val boneMassKg: Double? = null,
        val proteinPercent: Double? = null,
    )

    var pending: List<Pending> = emptyList()
        private set
    var persistenceError: String? = null
        private set
    private var flushing = false
    private val codec = ReflectJson.codec(Pending::class.java)
    private fun durable() = DurableQueue("body-composition", LocalDataStore.shared(), codec)

    fun init() {
        try { pending = durable().items() } catch (e: Exception) { persistenceError = e.message }
        onReconnect { flush() }
    }

    fun enqueue(reading: BodyCompositionReading, at: Instant, ownerUserId: String) {
        val item = Pending(
            id = UUID.randomUUID(), ownerUserId = ownerUserId, measuredAt = at,
            userDay = UserDay.containing(at).key,
            inputWeightKg = reading.inputWeightKg, bodyFatPercent = reading.bodyFatPercent,
            fatMassKg = reading.fatMassKg, leanMassKg = reading.leanMassKg,
            bmrKcal = reading.bmrKcal,
            muscleMassKg = reading.muscleKg, bodyWaterPercent = reading.bodyWaterPercent,
            boneMassKg = reading.boneKg, proteinPercent = reading.proteinPercent)
        durable().save(item, item.id.toString().uppercase(), ownerUserId)
        pending = durable().items()
        queueScope.launch { flush() }
    }

    suspend fun flush() = withContext(Dispatchers.Main.immediate) {
        if (flushing || !Reachability.isOnline || DebugEdgeFlag.on("offline")) return@withContext
        val currentUser = SupabaseClient.currentUserId ?: return@withContext
        flushing = true
        try {
            for (item in pending.filter { it.ownerUserId == currentUser }) {
                if (SupabaseClient.currentUserId != currentUser) return@withContext
                val opId = item.id.toString().uppercase()
                val row = mutableMapOf<String, Any?>(
                    "id" to item.id.lower(),
                    "user_id" to item.ownerUserId,
                    "measured_at" to Iso.fractional(item.measuredAt),
                    "user_day" to item.userDay,
                    "measurement_source" to "device_bia",
                    "input_weight_kg" to item.inputWeightKg,
                    "body_fat_pct" to item.bodyFatPercent,
                    "fat_mass_kg" to item.fatMassKg,
                    "lean_body_mass_kg" to item.leanMassKg)
                item.bmrKcal?.let { row["bmr_kcal"] = it }
                item.muscleMassKg?.let { row["muscle_mass_kg"] = it }
                item.bodyWaterPercent?.let { row["body_water_pct"] = it }
                item.boneMassKg?.let { row["bone_mass_kg"] = it }
                item.proteinPercent?.let { row["protein_pct"] = it }
                try {
                    SupabaseClient.insert("body_composition", listOf(row), returning = false)
                    if (SupabaseClient.currentUserIdSnapshot() != currentUser || !currentCoroutineContext().isActive) return@withContext
                    durable().acknowledge(opId, currentUser)
                    pending = pending.filter { it.id != item.id }
                    Analytics.track("SCAN_SYNCED", mapOf("SOURCE" to "device_bia"))
                } catch (e: Exception) {
                    rethrowCancel(e)
                    if (!isConflict(e)) {
                        BandLog.shared.record("body composition outbox", error = e)
                        break
                    }
                    try {
                        val fact = SupabaseClient.select("body_composition", listOf(
                            "id" to "eq.${item.id.lower()}", "user_id" to "eq.$currentUser")).firstOrNull() ?: break
                        if (fact.number("body_fat_pct") != item.bodyFatPercent ||
                            fact.number("input_weight_kg") != item.inputWeightKg ||
                            fact.number("fat_mass_kg") != item.fatMassKg ||
                            fact.number("lean_body_mass_kg") != item.leanMassKg ||
                            fact.optStringOrNull("measurement_source") != "device_bia") break
                        if (SupabaseClient.currentUserIdSnapshot() != currentUser || !currentCoroutineContext().isActive) return@withContext
                        durable().acknowledge(opId, currentUser)
                        pending = pending.filter { it.id != item.id }
                    } catch (inner: Exception) {
                        rethrowCancel(inner)
                        persistenceError = inner.message
                        break
                    }
                }
            }
        } finally {
            flushing = false
        }
    }

    fun purge() {
        try {
            for (item in pending) durable().acknowledge(item.id.toString().uppercase(), item.ownerUserId)
            pending = emptyList()
        } catch (e: Exception) { persistenceError = e.message }
    }
}

/**
 * ADR 0010 · the balance check's account-owned outbox, same semantics as
 * [BodyCompositionQueue]. ⚠️ Summary only — the beat-to-beat series is never stored.
 *
 * Android: `enqueue` takes the summary values of the Measure screen's `AutonomicBalance`
 * directly (lead · split.rest · sd1 · sd2 · sdnn · beatsPerMinute · points.count) so this
 * queue does not depend on the Features package.
 */
object BalanceCheckQueue {
    enum class Lead(val raw: String) { parasympathetic("rest"), sympathetic("drive"), even("even") }

    data class Pending(
        val id: UUID,
        val ownerUserId: String,
        val measuredAt: Instant,
        val userDay: String,
        val sampledTz: String,
        val lead: String,
        val restShare: Int,
        val sd1Ms: Double,
        val sd2Ms: Double,
        val sdnnMs: Double,
        val heartRate: Int?,
        val beatCount: Int,
    )

    var pending: List<Pending> = emptyList()
        private set
    var persistenceError: String? = null
        private set
    private var flushing = false
    private val codec = ReflectJson.codec(Pending::class.java)
    private fun durable() = DurableQueue("balance-check", LocalDataStore.shared(), codec)

    fun init() {
        try { pending = durable().items() } catch (e: Exception) { persistenceError = e.message }
        onReconnect { flush() }
    }

    fun enqueue(lead: Lead, restShare: Int, sd1: Double, sd2: Double, sdnn: Double,
                beatsPerMinute: Int?, pointCount: Int, heartRate: Int?, at: Instant, ownerUserId: String) {
        val item = Pending(
            id = UUID.randomUUID(), ownerUserId = ownerUserId, measuredAt = at,
            userDay = UserDay.containing(at).key,
            sampledTz = ZoneId.systemDefault().id,
            lead = lead.raw, restShare = restShare,
            sd1Ms = sd1, sd2Ms = sd2, sdnnMs = sdnn,
            // The band's own reported heart rate, else the interval mean of this measurement.
            // ⚠️ Out-of-range values become null: the table CHECKs 25–220 and a refused row
            // would block every measurement behind it.
            heartRate = plausible(heartRate ?: beatsPerMinute),
            beatCount = pointCount + 1)
        durable().save(item, item.id.toString().uppercase(), ownerUserId)
        pending = durable().items()
        queueScope.launch { flush() }
    }

    /** `balance_checks.heart_rate` CHECK is 25–220. */
    private fun plausible(bpm: Int?): Int? = bpm?.takeIf { it in 25..220 }

    suspend fun flush() = withContext(Dispatchers.Main.immediate) {
        if (flushing || !Reachability.isOnline || DebugEdgeFlag.on("offline")) return@withContext
        val currentUser = SupabaseClient.currentUserId ?: return@withContext
        flushing = true
        try {
            for (item in pending.filter { it.ownerUserId == currentUser }) {
                if (SupabaseClient.currentUserId != currentUser) return@withContext
                val opId = item.id.toString().uppercase()
                val row = mutableMapOf<String, Any?>(
                    "user_id" to item.ownerUserId,
                    "measured_at" to Iso.fractional(item.measuredAt),
                    "user_day" to item.userDay,
                    "sampled_tz" to item.sampledTz,
                    "lead" to item.lead,
                    "rest_share" to item.restShare,
                    "sd1_ms" to item.sd1Ms,
                    "sd2_ms" to item.sd2Ms,
                    "sdnn_ms" to item.sdnnMs,
                    "beat_count" to item.beatCount,
                    // One row however many times the same measurement is replayed.
                    "client_op_id" to item.id.lower())
                item.heartRate?.let { row["heart_rate"] = it }
                try {
                    SupabaseClient.insert("balance_checks", listOf(row), returning = false)
                    if (SupabaseClient.currentUserIdSnapshot() != currentUser || !currentCoroutineContext().isActive) return@withContext
                    durable().acknowledge(opId, currentUser)
                    pending = pending.filter { it.id != item.id }
                    Analytics.track("MEASUREMENT_SYNCED", mapOf("KIND" to "balance_check"))
                } catch (e: Exception) {
                    rethrowCancel(e)
                    if (!isConflict(e)) {
                        BandLog.shared.record("balance check outbox", error = e)
                        break
                    }
                    // A replay stopped by the unique index: the row is already there.
                    if (SupabaseClient.currentUserIdSnapshot() != currentUser || !currentCoroutineContext().isActive) return@withContext
                    try {
                        durable().acknowledge(opId, currentUser)
                        pending = pending.filter { it.id != item.id }
                    } catch (inner: Exception) { persistenceError = inner.message; break }
                }
            }
        } finally {
            flushing = false
        }
    }

    fun purge() {
        try {
            for (item in pending) durable().acknowledge(item.id.toString().uppercase(), item.ownerUserId)
            pending = emptyList()
        } catch (e: Exception) { persistenceError = e.message }
    }
}

/**
 * Uses the account-scoped durable outbox. A valid live report is committed before returning
 * to the stream, then uploads in bounded batches.
 */
object SportEvidenceQueue {
    private const val heartKind = "sport-heart-rate"
    private const val energyKind = "sport-energy"
    private var scheduled: Job? = null
    private var flushing = false

    fun init() {
        onReconnect { Repository.flushPendingEvidence() }
    }

    private fun heartJson(s: SportHeartRateEvidence) = JSONObject()
        .put("id", s.id.toString().uppercase()).put("sessionID", s.sessionID.toString().uppercase())
        .put("continuityID", s.continuityID.toString().uppercase()).put("observedAt", s.observedAt.toString())
        .put("heartRate", s.heartRate).put("sampledTimeZone", s.sampledTimeZone)
        .also { o -> s.sportMode?.let { o.put("sportMode", it) } }

    private fun energyJson(s: SportEnergyEvidence) = JSONObject()
        .put("id", s.id.toString().uppercase()).put("sessionID", s.sessionID.toString().uppercase())
        .put("continuityID", s.continuityID.toString().uppercase()).put("observedAt", s.observedAt.toString())
        .put("sportMode", s.sportMode).put("sampledTimeZone", s.sampledTimeZone)

    fun enqueue(observation: SportHeartRateEvidence, ownerUserId: String) {
        // Emulator mock packets must never reach ingest_sport_heart_rate (#36 / #37).
        if (Band.allowsSeed) return
        if (ownerUserId != SupabaseClient.currentUserIdSnapshot() || !ConsentStore.granted) throw SessionChangedException()
        LocalDataStore.shared().enqueue(LocalOperation(observation.id.lower(), ownerUserId, heartKind,
            heartJson(observation).sortedBytes()))
        scheduleFlush()
    }

    fun enqueue(observation: SportEnergyEvidence, ownerUserId: String) {
        if (Band.allowsSeed) return
        if (ownerUserId != SupabaseClient.currentUserIdSnapshot() || !ConsentStore.granted) throw SessionChangedException()
        LocalDataStore.shared().enqueue(LocalOperation(observation.id.lower(), ownerUserId, energyKind,
            energyJson(observation).sortedBytes()))
        scheduleFlush()
    }

    private fun scheduleFlush() {
        if (scheduled != null) return
        scheduled = queueScope.launch {
            delay(15_000)
            scheduled = null
            Repository.flushPendingEvidence()
        }
    }

    private fun ok(owner: String): Boolean = owner == SupabaseClient.currentUserIdSnapshot() && ConsentStore.granted

    /** Repository owns publication/settlement after every evidence queue is drained. */
    suspend fun flush() = withContext(Dispatchers.Main.immediate) {
        if (Band.allowsSeed) return@withContext
        if (flushing || !currentCoroutineContext().isActive || !ConsentStore.granted ||
            !Reachability.isOnline || DebugEdgeFlag.on("offline")) return@withContext
        val owner = SupabaseClient.currentUserIdSnapshot() ?: return@withContext
        flushing = true
        try {
            val local = LocalDataStore.shared()
            val snapshot = local.operations(owner, heartKind)
            for (batch in snapshot.chunked(300)) {
                if (!currentCoroutineContext().isActive || !ok(owner)) return@withContext
                val samples = batch.map { operation ->
                    val sample = JSONObject(String(operation.payload, Charsets.UTF_8))
                    val row = mutableMapOf<String, Any?>(
                        "id" to sample.getString("id").lowercase(),
                        "session_id" to sample.getString("sessionID").lowercase(),
                        "continuity_id" to sample.getString("continuityID").lowercase(),
                        "observed_at" to Iso.fractional(Instant.parse(sample.getString("observedAt"))),
                        "heart_rate" to sample.getInt("heartRate"),
                        "sampled_tz" to sample.getString("sampledTimeZone"))
                    if (sample.has("sportMode")) row["sport_mode"] = sample.getInt("sportMode")
                    row
                }
                val result = SupabaseClient.rpc("ingest_sport_heart_rate", mapOf("p_samples" to samples), expectedOwner = owner)
                if (!currentCoroutineContext().isActive || !ok(owner)) return@withContext
                checkReceipt(result, batch, "Sport evidence receipt did not confirm the batch")
                local.acknowledge(owner, batch.map { it.id })
            }
            flushEnergy(owner, local)
        } catch (e: Exception) {
            rethrowCancel(e)
            BandLog.shared.record("sport evidence outbox", error = e)
        } finally {
            flushing = false
        }
    }

    private fun checkReceipt(result: Any, batch: List<LocalOperation>, message: String) {
        val acknowledged = (result as? JSONObject)?.optJSONArray("acknowledged_ids")
            ?.let { a -> (0 until a.length()).mapNotNull { a.opt(it) as? String }.map { it.lowercase() }.toSet() }
        if (acknowledged == null || acknowledged != batch.map { it.id }.toSet()) {
            throw LocalDataStore.Failure.Database(message)
        }
    }

    private suspend fun flushEnergy(owner: String, local: LocalDataStore) {
        val snapshot = local.operations(owner, energyKind)
        for (batch in snapshot.chunked(300)) {
            if (!currentCoroutineContext().isActive || !ok(owner)) return
            val samples = batch.map { operation ->
                val sample = JSONObject(String(operation.payload, Charsets.UTF_8))
                mapOf(
                    "id" to sample.getString("id").lowercase(),
                    "session_id" to sample.getString("sessionID").lowercase(),
                    "continuity_id" to sample.getString("continuityID").lowercase(),
                    "observed_at" to Iso.fractional(Instant.parse(sample.getString("observedAt"))),
                    "sport_mode" to sample.getInt("sportMode"),
                    "sampled_tz" to sample.getString("sampledTimeZone"))
            }
            val result = SupabaseClient.rpc("ingest_sport_energy", mapOf("p_samples" to samples), expectedOwner = owner)
            if (!currentCoroutineContext().isActive || !ok(owner)) return
            checkReceipt(result, batch, "Sport energy receipt did not confirm the batch")
            local.acknowledge(owner, batch.map { it.id })
        }
    }
}
