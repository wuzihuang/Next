package com.nextbody.hoop.services

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandLog
import com.nextbody.hoop.band.SportRecapArchive
import com.nextbody.hoop.band.SportSessionRecap
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.services.storage.LocalDataStore
import com.nextbody.hoop.services.storage.lower
import com.nextbody.hoop.services.storage.parseUuid
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * Finished workouts survive navigation, restart and (after upload) reinstallation. Sensor
 * evidence and calculated load keep their existing publication path. Compose-observable.
 */
object SportRecapStore {
    val shared: SportRecapStore get() = this

    var recaps: List<SportSessionRecap> by mutableStateOf(emptyList())
        private set
    var errorLine: String? by mutableStateOf(null)
        private set
    var pendingCount: Int by mutableStateOf(0)
        private set
    var updatingTraining: Boolean by mutableStateOf(false)
    var trainingError: String? by mutableStateOf(null)
    private var account: String? = null
    private var flushing = false
    private var unsaved: List<SportSessionRecap> = emptyList()

    fun reset() {
        account = null
        recaps = emptyList()
        unsaved = emptyList()
        errorLine = null
        pendingCount = 0
        updatingTraining = false
        trainingError = null
    }

    private fun adopt(owner: String): SportRecapArchive {
        // Bind before opening disk: only an actual account change discards unsaved records.
        if (account != owner) {
            reset()
            account = owner
        }
        val archive = SportRecapArchive(LocalDataStore.shared())
        if (recaps.isEmpty()) recaps = archive.read(owner)
        return archive
    }

    fun record(recap: SportSessionRecap) {
        if (Band.allowsSeed || !ConsentStore.granted) return
        val owner = SupabaseClient.currentUserIdSnapshot() ?: return
        if (recap.ownerUserID != owner) return
        try {
            val archive = adopt(owner)
            archive.stage(recap, owner)
            recaps = archive.read(owner)
            pendingCount = archive.local.operations(owner, SportRecapArchive.kind).size
            errorLine = null
        } catch (e: Exception) {
            unsaved = unsaved.filter { it.id != recap.id } + recap
            recaps = listOf(recap) + recaps.filter { it.id != recap.id }
            errorLine = L("Session could not be saved. Retry before closing the app.")
            BandLog.shared.record("save session recap", error = e)
        }
    }

    suspend fun flush() = withContext(Dispatchers.Main.immediate) {
        if (Band.allowsSeed || flushing || !ConsentStore.granted) return@withContext
        val owner = SupabaseClient.currentUserIdSnapshot() ?: return@withContext
        if (!Reachability.isOnline) {
            errorLine = L("Session upload is waiting for a connection.")
            return@withContext
        }
        flushing = true
        val generation = Repository.sessionGeneration
        try {
            val archive = adopt(owner)
            unsaved = archive.stagePending(unsaved.filter { it.ownerUserID == owner }, owner)
            recaps = archive.read(owner)
            val operations = archive.local.operations(owner, SportRecapArchive.kind)
            pendingCount = operations.size
            var uploadFailed = false
            for (operation in operations) {
                if (!current(owner, generation)) return@withContext
                try {
                    val payload = JSONObject(String(operation.payload, Charsets.UTF_8))
                    val recap = SportSessionRecap.fromJson(payload)
                    val id = recap.sessionID
                    if (id == null || recap.ownerUserID != owner) continue
                    val result = SupabaseClient.rpc("save_sport_recap", mapOf(
                        "p_id" to id.lower(),
                        "p_started_at" to Iso.fractional(recap.startedAt),
                        "p_ended_at" to Iso.fractional(recap.endedAt),
                        "p_payload" to payload), expectedOwner = owner)
                    if (!current(owner, generation)) return@withContext
                    val receipt = result as? JSONObject
                    if (receipt?.optStringOrNull("id")?.lowercase() != id.lower()) {
                        throw LocalDataStore.Failure.Database("Missing session receipt")
                    }
                    archive.local.acknowledge(owner, operation.id)
                    pendingCount -= 1
                } catch (e: Exception) {
                    if (e is CancellationException && e !is SessionChangedException) throw e
                    if (!current(owner, generation)) return@withContext
                    uploadFailed = true
                    BandLog.shared.record("upload session recap", error = e)
                    // Keep this immutable operation for retry; other sessions may still publish.
                }
            }
            pendingCount = archive.local.operations(owner, SportRecapArchive.kind).size
            errorLine = if (unsaved.isNotEmpty()) {
                if (unsaved.any { !it.isValid }) L("This session exceeds the supported record limits. Other sessions can still sync.")
                else L("Session could not be saved. Retry before closing the app.")
            } else if (uploadFailed) L("Session upload failed. Your record is saved on this phone. Retry sync.") else null
        } catch (e: Exception) {
            if (e is CancellationException && e !is SessionChangedException) throw e
            if (!current(owner, generation)) return@withContext
            errorLine = if (unsaved.isEmpty()) L("Session upload failed. Your record is saved on this phone. Retry sync.")
                else L("Session could not be saved. Retry before closing the app.")
            BandLog.shared.record("upload session recap", error = e)
        } finally {
            flushing = false
        }
    }

    suspend fun load() = withContext(Dispatchers.Main.immediate) {
        if (Band.allowsSeed) return@withContext
        val owner = SupabaseClient.currentUserIdSnapshot() ?: return@withContext
        val generation = Repository.sessionGeneration
        try {
            val archive = adopt(owner)
            pendingCount = archive.local.operations(owner, SportRecapArchive.kind).size
            var offset = 0
            do {
                val rows = SupabaseClient.select("sport_session_recaps", listOf(
                    "select" to "id,payload",
                    "order" to "started_at.desc,id.desc",
                    "limit" to "200", "offset" to offset.toString()))
                if (!current(owner, generation)) return@withContext
                val loaded = rows.mapNotNull { row ->
                    val payload = row.objOrNull("payload") ?: return@mapNotNull null
                    val id = parseUuid(row.optStringOrNull("id")) ?: return@mapNotNull null
                    val recap = runCatching { SportSessionRecap.fromJson(payload) }.getOrNull() ?: return@mapNotNull null
                    recap.copy(ownerUserID = owner, sessionID = id).takeIf { it.isValid }
                }
                archive.cache(loaded, owner)
                recaps = archive.read(owner)
                if (rows.size < 200) break
                offset += rows.size
            } while (currentCoroutineContext().isActive)
        } catch (e: Exception) {
            if (e is CancellationException && e !is SessionChangedException) throw e
            if (!current(owner, generation)) return@withContext
            errorLine = L("Session history could not refresh. Saved records are still available.")
            BandLog.shared.record("read session recaps", error = e)
        }
    }

    suspend fun retry() {
        Repository.settleAfterSport()
        load()
    }

    private suspend fun current(owner: String, generation: Long): Boolean =
        currentCoroutineContext().isActive && ConsentStore.granted &&
            owner == SupabaseClient.currentUserIdSnapshot() && generation == Repository.sessionGeneration
}

/**
 * [DEBUG-night-hrv] Local summaries only (Swift writes a leased JSONL file). On Android: logcat
 * in debug builds, nothing in release. Never pass identities, credentials or raw SDK payloads.
 */
class NightDiagnostics private constructor(val isEnabled: Boolean) {
    fun record(event: String, fields: Map<String, String> = emptyMap()) {
        if (!isEnabled) return
        android.util.Log.d("NightDiagnostics", event + if (fields.isEmpty()) "" else " " + fields.entries.joinToString(" ") { "${it.key}=${it.value}" })
    }

    companion object {
        val shared = NightDiagnostics(BuildConfig.DEBUG)
    }
}
