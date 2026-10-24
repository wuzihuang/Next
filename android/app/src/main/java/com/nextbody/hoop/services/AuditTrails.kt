package com.nextbody.hoop.services

import android.content.Context
import android.content.SharedPreferences
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandCapabilities
import com.nextbody.hoop.band.FunctionStatus
import com.nextbody.hoop.band.LaunchGate
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.Profile
import com.nextbody.hoop.data.SessionStore
import com.nextbody.hoop.model.Goal
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

// F3's audit tables, written from the client side. An empty audit table answers "what could
// this band do / what did the user see" wrongly rather than not at all.
// (sync_runs is written by OriginDataSync, next to the sync it describes.)

private fun functionStatus(any: Any?): FunctionStatus =
    FunctionStatus.entries.firstOrNull { it.name == (any as? String) } ?: FunctionStatus.unknown

/** 12 · what this NEXTBODY reports it can do; the device page works before the band answers. */
suspend fun Repository.loadCapabilities(store: DataStore) = withContext(Dispatchers.Main.immediate) {
    val account = SupabaseClient.currentUserIdSnapshot()
    val generation = sessionGeneration
    val rows = runCatching {
        db.select("device_capabilities", listOf(
            "select" to "functions,body_component,ecg,hrv,stress,auto_measure,watch_data_day_number,read_at",
            "limit" to "1"))
    }.getOrNull() ?: emptyList()
    val row = rows.firstOrNull()
    if (account == null || account != SupabaseClient.currentUserIdSnapshot() || generation != sessionGeneration || row == null) {
        return@withContext
    }
    val caps = BandCapabilities(
        functions = row.objOrNull("functions")?.let { fns ->
            fns.keys().asSequence().associateWith { functionStatus(fns.opt(it)) }
        } ?: emptyMap(),
        bodyComponent = functionStatus(row.opt("body_component")),
        ecg = functionStatus(row.opt("ecg")),
        hrv = functionStatus(row.opt("hrv")),
        stress = functionStatus(row.opt("stress")),
        autoMeasure = functionStatus(row.opt("auto_measure")))
    store.capabilities = caps
    store.capabilitiesReadAt = timestamp(row.optStringOrNull("read_at"))
}

/**
 * ⚠️ Written verbatim, never squashed into booleans: "unknown" and "unsupported" are two
 * different problems. `holdsDays` is the band's saveDays.
 */
suspend fun Repository.saveCapabilities(caps: BandCapabilities, deviceId: String, userId: String,
                                        holdsDays: Int? = null): Boolean {
    val row = mutableMapOf<String, Any?>(
        "device_id" to deviceId,
        "user_id" to userId,
        "read_at" to Iso.string(Instant.now()),
        "functions" to caps.functions.mapValues { it.value.name },
        "body_component" to caps.bodyComponent.name,
        "ecg" to caps.ecg.name,
        "hrv" to caps.hrv.name,
        "stress" to caps.stress.name,
        "auto_measure" to caps.autoMeasure.name)
    if (holdsDays != null && holdsDays > 0) row["watch_data_day_number"] = holdsDays
    return try {
        db.upsert("device_capabilities", row, onConflict = "device_id")
        true
    } catch (e: Exception) {
        if (e is CancellationException && e !is SessionChangedException) throw e
        false
    }
}

/**
 * F3 §02.3 · profile edits are client-direct RLS writes. A field the user edits is marked `edit`
 * in field_sources, which every later Health sync skips. It is an upsert on user_id and carries
 * every column the computation reads.
 */
suspend fun Repository.saveProfile(profile: Profile, editedFields: List<String>): Boolean {
    if (Band.allowsSeed) return true
    val userId = db.currentUserId ?: return false
    val row = mutableMapOf<String, Any?>(
        "user_id" to userId,
        "timezone" to ZoneId.systemDefault().id,
        "goal" to profile.goal.raw,
        "units_metric" to profile.usesMetric,
        "height_cm" to profile.heightCm,
        "sex" to if (profile.sexIsMale) "male" else "female",
        "birth_date" to DateTimeFormatter.ofPattern("yyyy-MM-dd").format(profile.birthdate.atZone(ZoneId.systemDefault())))
    if (profile.name.isNotEmpty()) row["display_name"] = profile.name
    try {
        if (editedFields.isNotEmpty()) {
            val sources = linkedMapOf<String, String>()
            db.select("profiles", listOf("select" to "field_sources", "limit" to "1"))
                .firstOrNull()?.objOrNull("field_sources")?.let { existing ->
                    existing.keys().forEach { key -> (existing.opt(key) as? String)?.let { sources[key] = it } }
                }
            for (e in editedFields) sources[e] = "edit"
            row["field_sources"] = sources
        }
        if (userId != SupabaseClient.currentUserIdSnapshot()) return false
        db.upsert("profiles", row, onConflict = "user_id")
    } catch (e: Exception) {
        if (e is CancellationException && e !is SessionChangedException) throw e
        ServiceLog.record("Repository.saveProfile failed", e)
        return false
    }
    if (userId != SupabaseClient.currentUserIdSnapshot()) return false
    Analytics.track("PROFILE_EDITED", mapOf("FIELDS" to editedFields))
    return true
}

/** Just the name, for the one caller that has a name and nothing else (first Google sign-in). */
suspend fun Repository.saveDisplayName(name: String) {
    val userId = db.currentUserId ?: return
    if (name.isEmpty()) return
    try {
        db.upsert("profiles", mapOf("user_id" to userId, "display_name" to name), onConflict = "user_id")
    } catch (e: Exception) {
        if (e is CancellationException && e !is SessionChangedException) throw e
        ServiceLog.record("Repository.saveDisplayName failed", e)
    }
}

/**
 * The row the computation hangs off, with at least the timezone on it. A missing row is
 * created, and a phone that has moved zones tells the server.
 */
suspend fun Repository.ensureProfileRow(existingTimezone: String?) {
    val userId = db.currentUserId ?: return
    val tz = ZoneId.systemDefault().id
    if (existingTimezone == tz) return
    runCatching { db.upsert("profiles", mapOf("user_id" to userId, "timezone" to tz), onConflict = "user_id") }
}

/** GateRoute.swift · F1 §02 · after a session exists, the gate is four facts. */
object GateDecision {
    fun stage(hasBoundBand: Boolean, profileComplete: Boolean): SessionStore.Stage =
        SessionStore.Stage.fromRaw(LaunchGate.stage(hasBoundBand, profileComplete)) ?: SessionStore.Stage.gateConnect

    fun isFirstRun(hasBoundBand: Boolean, profileComplete: Boolean): Boolean =
        LaunchGate.isFirstRun(hasBoundBand, profileComplete)

    /** GoTrue's expired OTP body is `otp_expired · Token has expired or is invalid`. */
    fun isExpiredCode(status: Int, body: String): Boolean = LaunchGate.isExpiredCode(status, body)
}

/** What the server knows about this account for the gate. Weight lives on weigh_ins. */
data class AccountGate(
    var hasBoundBand: Boolean = false,
    var sex: String? = null,
    var heightCm: Double? = null,
    var birthDate: Instant? = null,
    var goal: Goal? = null,
    var displayName: String? = null,
    var weightKg: Double? = null,
) {
    val profileComplete: Boolean get() = sex != null && heightCm != null && birthDate != null
    val hasAnyProfileField: Boolean
        get() = sex != null || heightCm != null || birthDate != null || !displayName.isNullOrEmpty()
    val isFirstRun: Boolean get() = GateDecision.isFirstRun(hasBoundBand, profileComplete)
    val stage: SessionStore.Stage get() = GateDecision.stage(hasBoundBand, profileComplete)
}

/** 01 rule 03 · five wrong codes lock that email for 15 minutes on this phone. */
object AuthLock {
    private var prefs: SharedPreferences? = null
    fun init(context: Context) { prefs = context.applicationContext.getSharedPreferences("nb", Context.MODE_PRIVATE) }

    private fun norm(email: String) = email.lowercase().trim(' ')
    private fun lockKey(email: String) = "nb.auth.lock.${norm(email)}"
    private fun wrongKey(email: String) = "nb.auth.wrong.${norm(email)}"

    /** Seconds left on the lock, or null. */
    fun remaining(email: String): Double? {
        val until = prefs?.getLong(lockKey(email), 0L) ?: 0L
        val left = (until - System.currentTimeMillis()) / 1000.0
        return if (left > 0) left else null
    }

    fun isLocked(email: String): Boolean = remaining(email) != null

    /** Returns true when this wrong attempt engaged the 15-minute lock. */
    fun registerWrong(email: String): Boolean {
        val p = prefs ?: return false
        val n = p.getInt(wrongKey(email), 0) + 1
        p.edit().putInt(wrongKey(email), n).apply()
        if (n < 5) return false
        p.edit().putLong(lockKey(email), System.currentTimeMillis() + 15 * 60 * 1000L).apply()
        return true
    }

    fun clearWrongs(email: String) { prefs?.edit()?.remove(wrongKey(email))?.apply() }
}
