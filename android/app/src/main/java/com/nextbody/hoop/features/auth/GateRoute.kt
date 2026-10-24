package com.nextbody.hoop.features.auth

import com.nextbody.hoop.band.BandBattery
import com.nextbody.hoop.band.BandCapabilities
import com.nextbody.hoop.band.BandIdentity
import com.nextbody.hoop.band.BodyCompositionReading
import com.nextbody.hoop.band.LaunchGate
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.data.Defaults
import com.nextbody.hoop.data.Profile
import com.nextbody.hoop.data.SessionStore
import com.nextbody.hoop.model.Goal
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.services.saveDisplayName
import com.nextbody.hoop.services.saveProfile
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

// Port of Services/GateRoute.swift (GateDecision · AccountGate · AuthLock · OnboardingDraft),
// plus the handful of Repository calls the gate makes, routed to `services.Repository`.

/** The gate's SessionStore: Swift read it from the environment; here it is the app's one instance. */
object GateSession {
    val current: SessionStore get() = com.nextbody.hoop.app.AppSession.session
}

/** F1 §02 · after a session exists, the gate is four facts, not the last screen. */
object GateDecision {
    fun stage(hasBoundBand: Boolean, profileComplete: Boolean): SessionStore.Stage =
        SessionStore.Stage.fromRaw(LaunchGate.stage(hasBoundBand, profileComplete)) ?: SessionStore.Stage.gateConnect

    fun isFirstRun(hasBoundBand: Boolean, profileComplete: Boolean): Boolean =
        LaunchGate.isFirstRun(hasBoundBand, profileComplete)

    /** GoTrue's expired OTP body is `otp_expired · Token has expired or is invalid`. */
    fun isExpiredCode(status: Int, body: String): Boolean = LaunchGate.isExpiredCode(status, body)
}

/** What the server knows about this account for the gate. */
data class AccountGate(
    var hasBoundBand: Boolean = false,
    var sex: String? = null,
    var heightCm: Double? = null,
    var birthDate: LocalDate? = null,
    var goal: Goal? = null,
    var displayName: String? = null,
    var weightKg: Double? = null,
) {
    val profileComplete: Boolean get() = sex != null && heightCm != null && birthDate != null
    val hasAnyProfileField: Boolean
        get() = sex != null || heightCm != null || birthDate != null || !(displayName ?: "").isEmpty()
    val isFirstRun: Boolean get() = GateDecision.isFirstRun(hasBoundBand, profileComplete)
    val stage: SessionStore.Stage get() = GateDecision.stage(hasBoundBand, profileComplete)
}

/** 01 rule 03 · five wrong codes lock that email for 15 minutes on this phone. */
object AuthLock {
    private fun norm(email: String) = email.lowercase().trim()
    private fun lockKey(email: String) = "nb.auth.lock.${norm(email)}"
    private fun wrongKey(email: String) = "nb.auth.wrong.${norm(email)}"

    /** Seconds left on the lock, or null. */
    fun remaining(email: String): Double? {
        val until = Defaults.getLong(lockKey(email)) ?: return null
        val left = (until - System.currentTimeMillis()) / 1000.0
        return if (left > 0) left else null
    }

    fun isLocked(email: String): Boolean = remaining(email) != null

    /** Returns true when this wrong attempt engaged the 15-minute lock. */
    fun registerWrong(email: String): Boolean {
        val key = wrongKey(email)
        val n = Defaults.getInt(key) + 1
        Defaults.putInt(key, n)
        if (n < 5) return false
        Defaults.putLong(lockKey(email), System.currentTimeMillis() + 15 * 60 * 1000L)
        return true
    }

    fun clearWrongs(email: String) = Defaults.remove(wrongKey(email))
}

/** F1 PROFILE GAP · About You values survive a kill. Namespaced by user. */
data class OnboardingDraft(
    val userId: String,
    val step: String,
    val sex: String,
    val year: Int,
    val month: Int,
    val day: Int,
    val heightCm: Double,
    val weightKg: Double,
    val filled: List<String>,
    val synced: Boolean,
    val sexFromHealth: Boolean,
    val bornFromHealth: Boolean,
    val heightFromHealth: Boolean,
    val weightFromHealth: Boolean,
    val goal: String,
) {
    fun save() {
        val o = JSONObject()
            .put("userId", userId).put("step", step).put("sex", sex)
            .put("year", year).put("month", month).put("day", day)
            .put("heightCm", heightCm).put("weightKg", weightKg)
            .put("filled", org.json.JSONArray(filled)).put("synced", synced)
            .put("sexFromHealth", sexFromHealth).put("bornFromHealth", bornFromHealth)
            .put("heightFromHealth", heightFromHealth).put("weightFromHealth", weightFromHealth)
            .put("goal", goal)
        Defaults.putString(key(userId), o.toString())
    }

    companion object {
        private fun key(userId: String) = "nb.onboarding.draft.$userId"

        fun load(userId: String): OnboardingDraft? {
            val raw = Defaults.getString(key(userId)) ?: return null
            return runCatching {
                val o = JSONObject(raw)
                val f = o.getJSONArray("filled")
                OnboardingDraft(
                    userId = o.getString("userId"), step = o.getString("step"), sex = o.getString("sex"),
                    year = o.getInt("year"), month = o.getInt("month"), day = o.getInt("day"),
                    heightCm = o.getDouble("heightCm"), weightKg = o.getDouble("weightKg"),
                    filled = (0 until f.length()).map { f.getString(it) }, synced = o.getBoolean("synced"),
                    sexFromHealth = o.getBoolean("sexFromHealth"), bornFromHealth = o.getBoolean("bornFromHealth"),
                    heightFromHealth = o.getBoolean("heightFromHealth"),
                    weightFromHealth = o.getBoolean("weightFromHealth"), goal = o.getString("goal"),
                )
            }.getOrNull()
        }

        fun clear(userId: String) = Defaults.remove(key(userId))
    }
}

/**
 * The Repository calls the gate makes (Repository.swift / AuditTrails.swift). Reads and
 * profile writes go through `services.Repository`, so the gate and the rest of the app share
 * one bound-device id; the three band-side writes are hooks `ServicesBootstrap` installs.
 */
object GateRepository {
    /** `Repository.deviceId` — the bound devices row, remembered by [fetchAccountGate]. */
    @Volatile var deviceId: String? = null

    var registerDeviceHook: (suspend (BandIdentity?, BandBattery?) -> Boolean)? = null
    var saveCapabilitiesHook: (suspend (BandCapabilities, String, String, Int) -> Unit)? = null
    var recordBodyCompositionHook: (suspend (BodyCompositionReading) -> Unit)? = null

    private fun number(v: Any?): Double? = when (v) {
        is Number -> v.toDouble()
        is String -> v.toDoubleOrNull()
        else -> null
    }

    private fun JSONObject.str(k: String): String? = if (isNull(k)) null else optString(k).takeIf { has(k) }

    suspend fun fetchAccountGate(): AccountGate {
        val g = com.nextbody.hoop.services.Repository.fetchAccountGate()
        deviceId = com.nextbody.hoop.services.Repository.deviceId
        return AccountGate(
            hasBoundBand = g.hasBoundBand, sex = g.sex, heightCm = g.heightCm,
            birthDate = g.birthDate?.localDate(), goal = g.goal,
            displayName = g.displayName, weightKg = g.weightKg,
        )
    }

    /** Just the name, for the one caller that has a name and nothing else to say. */
    suspend fun saveDisplayName(name: String) {
        com.nextbody.hoop.services.Repository.saveDisplayName(name)
    }

    /** What onboarding writes: the four About You facts, user-typed ones marked `edit`. */
    suspend fun saveProfile(profile: Profile, editedFields: List<String>): Boolean =
        com.nextbody.hoop.services.Repository.saveProfile(profile, editedFields)

    suspend fun registerDevice(identity: BandIdentity?, battery: BandBattery?): Boolean =
        registerDeviceHook?.invoke(identity, battery) ?: false

    suspend fun saveCapabilities(caps: BandCapabilities, deviceId: String, userId: String, holdsDays: Int) {
        saveCapabilitiesHook?.invoke(caps, deviceId, userId, holdsDays)
    }

    suspend fun recordBodyComposition(r: BodyCompositionReading) {
        recordBodyCompositionHook?.invoke(r)
    }
}

/** `Instant` → local calendar day, the way Swift's `Calendar.current.dateComponents` reads it. */
internal fun Instant.localDate(): LocalDate = atZone(ZoneId.systemDefault()).toLocalDate()
internal fun LocalDate.startInstant(): Instant = atStartOfDay(ZoneId.systemDefault()).toInstant()
