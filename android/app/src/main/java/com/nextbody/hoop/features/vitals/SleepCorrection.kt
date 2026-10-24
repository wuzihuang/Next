package com.nextbody.hoop.features.vitals

import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.SleepScoreLoadState
import com.nextbody.hoop.services.Repository
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.services.SupabaseFailure
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.time.temporal.ChronoUnit
import kotlin.math.max

/**
 * Shared mutation and refresh path for a reported night or an edited device window.
 * Both the button and a confirmed AI request publish the same server-side evidence.
 */
object SleepCorrection {
    /** How far back a night may be corrected. The server holds the same bound; replay is
     *  chronological, so an older correction would recompute every day after it. */
    const val horizonDays = 30

    fun canCorrect(day: UserDay, today: UserDay = UserDay.containing(Instant.now())): Boolean =
        day <= today && day.date >= today.adding(-horizonDays).date

    suspend fun save(day: UserDay, start: String, end: String, store: DataStore = DataStore): Boolean =
        write(day, store) { owner ->
            SupabaseClient.rpc("correct_sleep_window",
                mapOf("p_user_day" to day.key, "p_start" to start, "p_end" to end), expectedOwner = owner)
        }

    suspend fun create(day: UserDay, start: String, end: String, store: DataStore = DataStore): Boolean =
        write(day, store) { owner ->
            SupabaseClient.rpc("create_sleep_window",
                mapOf("p_user_day" to day.key, "p_start" to start, "p_end" to end), expectedOwner = owner)
        }

    suspend fun clear(day: UserDay, store: DataStore = DataStore): Boolean =
        write(day, store) { owner ->
            SupabaseClient.rpc("clear_sleep_correction", mapOf("p_user_day" to day.key), expectedOwner = owner)
        }

    private suspend fun write(day: UserDay, store: DataStore, call: suspend (String) -> Any): Boolean {
        val session = SupabaseClient.currentRequestSessionSnapshot()
        val owner = SupabaseClient.currentUserIdSnapshot() ?: throw CancellationException()
        Repository.flushPendingEvidence(afterCurrent = true)
        if (session != SupabaseClient.currentRequestSessionSnapshot() || !currentCoroutineContext().isActive) {
            throw CancellationException()
        }
        call(owner)
        if (session != SupabaseClient.currentRequestSessionSnapshot()) throw CancellationException()
        return republish(day.key, store, expectedOwner = owner)
    }

    /**
     * The night moved, so the night's score and the charge it fed moved with it. Settling covers
     * the corrected day and the one before it, because a night that crosses midnight is spent
     * on both — the same day-1 the server's own invalidation reaches for.
     */
    suspend fun republish(day: String, store: DataStore = DataStore, expectedOwner: String? = null): Boolean {
        val session = SupabaseClient.currentRequestSessionSnapshot()
        val owner = expectedOwner ?: SupabaseClient.currentUserIdSnapshot() ?: return false
        if (owner != SupabaseClient.currentUserIdSnapshot()) return false
        suspend fun current(): Boolean =
            session == SupabaseClient.currentRequestSessionSnapshot() && currentCoroutineContext().isActive
        val today = UserDay.containing(Instant.now())
        val corrected = day(day) ?: today
        val back = max(0L, ChronoUnit.DAYS.between(
            corrected.start.atZone(java.time.ZoneId.systemDefault()).toLocalDate(),
            today.start.atZone(java.time.ZoneId.systemDefault()).toLocalDate())).toInt()
        val windowDays = back + 2
        var settled = true
        try {
            SupabaseClient.rpc("settle_now", mapOf("p_days" to windowDays - 1), expectedOwner = owner)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            settled = false
        }
        if (!current()) return false
        Repository.load(days = windowDays - 1, endingAt = today, store = store)
        if (!current()) return false
        Repository.loadSleepScores(days = windowDays, endingAt = today, store = store)
        if (!current() || store.isOffline) return false
        if (store.sleepScoreLoadState == SleepScoreLoadState.failed) return false
        return try {
            val reply = SupabaseClient.rpc("calculation_status",
                mapOf("p_from" to corrected.adding(-1).key, "p_to" to today.key), expectedOwner = owner)
            val rows = (reply as? JSONArray) ?: return false
            if (rows.length() == 0) return false
            current() && settled && (0 until rows.length()).all {
                val row = rows.optJSONObject(it) ?: JSONObject()
                row.opt("pending") == false
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            false
        }
    }

    private val keyFormat: DateTimeFormatter =
        DateTimeFormatter.ofPattern("uuuu-MM-dd").withResolverStyle(ResolverStyle.STRICT)

    fun day(fromKey: String): UserDay? {
        val date = runCatching { LocalDate.parse(fromKey, keyFormat) }.getOrNull() ?: return null
        if (keyFormat.format(date) != fromKey) return null
        return UserDay(date.atTime(UserDay.boundaryHour, 0).atZone(java.time.ZoneId.systemDefault()).toInstant())
    }

    /** The RPC raises its refusals by name. They arrive as an HTTP body, and the name inside it
     *  is the only part worth showing anyone. */
    fun code(error: Throwable): String {
        val http = error as? SupabaseFailure.Http
            ?: return if (error is CancellationException) "CANCELLED" else "WRITE_FAILED"
        val names = listOf("SLEEP_NIGHT_EXISTS", "FUTURE_SLEEP_WINDOW", "NO_RECORDED_SLEEP", "NO_SLEEP_NIGHT",
            "WINDOW_HAS_NO_SLEEP", "NO_STAGE_LINE", "END_BEFORE_START", "WAKE_LEAVES_THE_DAY",
            "CORRECTION_TOO_OLD", "NO_CORRECTION", "BAD_TIME", "RATE_LIMITED", "CONSENT_WITHDRAWN",
            "ACCOUNT_DELETING", "UNAUTHENTICATED")
        return names.firstOrNull { http.body.contains(it) } ?: "WRITE_FAILED"
    }

    fun message(code: String): String = when (code) {
        "SLEEP_NIGHT_EXISTS" -> L("A night already exists on this day. Change its times instead.")
        "FUTURE_SLEEP_WINDOW" -> L("Sleep can only be recorded after you wake up.")
        "NO_RECORDED_SLEEP" -> L("This night was added by you and has no band times to restore.")
        "NO_SLEEP_NIGHT" -> L("There is no recorded night on that day to correct.")
        "WINDOW_HAS_NO_SLEEP" -> L("The band recorded no sleep inside those times.")
        "NO_STAGE_LINE" -> L("This night has totals only, so its times cannot be re-counted.")
        "END_BEFORE_START" -> L("The end has to be a different time from the start.")
        "WAKE_LEAVES_THE_DAY" -> L("A night is filed under the day you woke on; that end leaves it.")
        "CORRECTION_TOO_OLD" -> L("Nights older than %d days can no longer be corrected.", horizonDays)
        "NO_CORRECTION" -> L("This night is already the band's own.")
        "BAD_TIME" -> L("Use a clock time like 23:30.")
        "RATE_LIMITED" -> L("Too many changes at once. Try again in a minute.")
        "CONSENT_WITHDRAWN" -> L("Health storage is off, so nothing can be changed.")
        "CANCELLED" -> L("Not saved.")
        else -> L("Couldn't save that. Check your connection and try again.")
    }
}
