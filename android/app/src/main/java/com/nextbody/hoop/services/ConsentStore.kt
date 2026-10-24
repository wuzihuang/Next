package com.nextbody.hoop.services

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONObject
import java.security.MessageDigest
import java.time.Instant

/**
 * 补屏 A · MHMDA consent — the seventh onboarding screen, and the switch in Settings › Data.
 *
 *  01 the screen comes before Health Connect's dialog and before the first band read.
 *  05 a decision is stored with consent_version · granted_at · text_sha256 · locale.
 *  06 withdrawing is not deleting.
 *  edge 1 declining is not a dead end.
 *
 * Decisions are appended, never edited: each row is one answer, and the newest wins.
 */
object ConsentStore {
    /** 1.3.0 · ADR 0008 · sleep score copy. */
    const val version = "1.3.0"
    const val locale = "en-US"

    enum class Choice(val raw: String) {
        Granted("granted"), Declined("declined"), Withdrawn("withdrawn");
        companion object { fun of(raw: String?) = values().firstOrNull { it.raw == raw } }
    }

    private const val KEY = "nb.consent"
    private const val PENDING_KEY = "nb.consent.pendingUpload"
    private var prefs: SharedPreferences? = null

    /** Compose-observable. */
    var choice: Choice? by mutableStateOf(null)
        private set
    val granted: Boolean get() = choice == Choice.Granted
    /** True once the screen has been answered at all. */
    val decided: Boolean get() = choice != null

    fun init(context: Context) {
        val p = context.applicationContext.getSharedPreferences("nb", Context.MODE_PRIVATE)
        prefs = p
        val raw = p.getString(KEY, null)?.let { runCatching { JSONObject(it) }.getOrNull() }
        if (raw?.optString("version") == version) choice = Choice.of(raw.optString("choice"))
    }

    suspend fun record(c: Choice, msOnScreen: Int?) {
        choice = c
        val stored = JSONObject().put("version", version).put("choice", c.raw).put("at", Iso.string(Instant.now()))
        if (msOnScreen != null) stored.put("msOnScreen", msOnScreen)
        prefs?.edit()?.putString(KEY, stored.toString())?.putBoolean(PENDING_KEY, true)?.apply()
        // Rule 05 · on the phone first, on the server as soon as it can be; pending until taken.
        flushPending()
        when (c) {
            Choice.Granted, Choice.Declined -> Analytics.track("CONSENT_RESULT", mapOf(
                "VERSION" to version, "CHOICE" to c.raw.uppercase(), "MS_ON_SCREEN" to (msOnScreen ?: 0)))
            Choice.Withdrawn -> Analytics.track("CONSENT_WITHDRAWN", mapOf("VERSION" to version))
        }
    }

    /** Called after a decision and every time the app comes forward. */
    suspend fun flushPending() {
        val p = prefs ?: return
        if (!p.getBoolean(PENDING_KEY, false)) return
        val raw = p.getString(KEY, null)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return
        val choice = raw.optStringOrNull("choice") ?: return
        val uid = SupabaseClient.currentUserId ?: return
        val row = mutableMapOf<String, Any?>(
            "user_id" to uid,
            "consent_version" to (raw.optStringOrNull("version") ?: version),
            "choice" to choice,
            "text_sha256" to textSHA256,
            "locale" to locale,
        )
        raw.optStringOrNull("at")?.let { row["decided_at"] = it }
        if (raw.has("msOnScreen")) row["ms_on_screen"] = raw.optInt("msOnScreen")
        try {
            SupabaseClient.insert("consents", listOf(row), returning = false)
            p.edit().putBoolean(PENDING_KEY, false).apply()
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            ServiceLog.record("insert consents", e)
        }
    }

    /** 11 · DELETE EVERYTHING. The pending flag goes with it. */
    fun purge() {
        choice = null
        prefs?.edit()?.remove(KEY)?.remove(PENDING_KEY)?.apply()
    }

    /** The hash of exactly what was on the screen, so a later edit to the copy is a new consent. */
    val textSHA256: String
        get() = MessageDigest.getInstance("SHA-256")
            .digest(ConsentCopy.all.joinToString("\n").toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
}

/**
 * The screen's words. One list, so the hash and the screen agree.
 * ⚠️ Android copy: "Apple Health" → "Health Connect", and Health Connect has no sex or date of
 * birth, so the first item names height and weight only. The hash therefore differs from iOS.
 */
object ConsentCopy {
    const val eyebrow = "NOTHING READ YET"
    const val title = "What NEXTBODY collects"
    const val lede = "Nothing has been read yet — not from the band, not from Health Connect. This is the complete list, and what each item is for."

    data class Item(val name: String, val why: String)
    data class Section(val head: String, val items: List<Item>)
    data class Note(val head: String, val body: String)

    val sections: List<Section> = listOf(
        Section("FROM HEALTH CONNECT · READ ONLY", listOf(
            Item("Height, weight",
                "Every calorie and body-composition number is built from these and the sex and date of birth you enter. NEXTBODY reads them and never writes anything back to Health Connect."),
        )),
        Section("FROM THE BAND", listOf(
            Item("Heart rate", "One reading about every five minutes, all day."),
            Item("Heart rate variability, including raw beat-to-beat intervals",
                "The single best signal for how recovered you are. We keep the raw intervals because the score alone cannot be recalculated later."),
            Item("Steps, distance, calories and movement intensity",
                "Your daily load, and the burn side of energy balance."),
            Item("Sleep signals",
                "Staging, duration, night HRV and overnight automatic oxygen from the night the band recorded. From these NEXTBODY settles one sleep score for the night, out of four parts — how long you slept, the structure of it, how your body recovered, and how close to your usual hour you went to bed. The score is computed on our server and can be recomputed; it is not a medical assessment."),
            Item("Body composition — 14 measures from the band's bioimpedance sensor",
                "Body fat, muscle, water, bone, protein, metabolic rate and more. Only when you start a measurement yourself. Never in the background."),
            Item("Skin temperature", "One hidden input to readiness. It is never shown as a number."),
            Item("Wrist optical meal response",
                "Shown as RESPONSE, a unitless index versus your own daytime median. It is not a blood test."),
        )),
        Section("FROM YOU", listOf(
            Item("Meals — your words and your photos",
                "Photos are read to estimate the food, kept where only you can open them, and deleted after 30 days. Location tags are removed on upload."),
            Item("What you say out loud", "Turned into text so NEXTBODY can answer. The recording is never stored."),
            Item("How you use the app", "Which screens you open and what fails, so we can fix it."),
            Item("Band battery and firmware version — not health data",
                "So the app can tell you to charge it or update it."),
        )),
    )

    val notes: List<Note> = listOf(
        Note("WHAT WE DON'T TOUCH",
            "The KR96 PRO hardware can also read blood pressure, ECG, and daytime or on-demand blood oxygen. NEXTBODY never turns those on, never stores them and never shows them. Overnight automatic oxygen is stored and shown on the sleep page only. Wrist optical meal response is stored and shown as RESPONSE; it is not a blood test."),
        Note("WHAT WE NEVER DO",
            "We never sell your health data.\nWe never give it to advertising networks or data brokers.\nWe never write anything back to Health Connect."),
        Note("WHERE IT GOES",
            "Your phone and our servers. When you ask NEXTBODY a question, only the numbers it needs go to the model that writes the answer, and it is not allowed to keep them or train on them."),
    )

    const val agree = "I agree to let NEXTBODY collect the health data listed on this screen."
    const val ifNot = "If you don't agree, NEXTBODY reads nothing. Your band stays paired and stays silent, every screen stays blank, and you can come back to this screen from Settings."
    const val withdraw = "You can withdraw at any time in Settings › Data. Withdrawing stops collection. Deleting what we already have is a separate tap on the same screen."
    const val cta = "Continue"

    val all: List<String>
        get() = listOf(eyebrow, title, lede) +
            sections.flatMap { s -> listOf(s.head) + s.items.flatMap { listOf(it.name, it.why) } } +
            notes.flatMap { listOf(it.head, it.body) } +
            listOf(agree, ifNot, withdraw, cta)
}
