package com.nextbody.hoop.features.sport

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import com.nextbody.hoop.R
import com.nextbody.hoop.app.NextBodyApplication
import com.nextbody.hoop.l10n.L
import java.time.Instant
import kotlin.math.roundToInt

/**
 * 14 · LIVE SESSION · the app's end of the Dynamic Island. On Android the closest surface is an
 * ongoing notification: it carries the sport, the running clock (the system chronometer counts
 * the seconds on its own), the heart rate and the burn — or the one line the session is saying.
 *
 * ⚠️ Updates are rationed: a push goes out at most every two seconds, except the ones that
 * change what the thing *says* (the wrist coming and going, the note, the end).
 */
object SessionActivity {
    private const val TAG = "island"
    private const val CHANNEL = "nb.session"
    private const val ID = 0x5E55

    /** Swift `SessionAttributes.ContentState`. */
    data class ContentState(
        val heartRate: Int?,
        val kcal: Int,
        val startedAt: Instant,
        val live: Boolean,
        val effort: Double,
        val note: String?,
        val energyEstimated: Boolean,
        val energyAvailable: Boolean,
    )

    private var sport: String? = null
    private var lastPushAt = 0L
    private var lastState: ContentState? = null

    /** The floor between routine pushes. */
    private const val CADENCE_MS = 2_000L

    val isRunning: Boolean get() = sport != null

    private val context: Context? get() = runCatching { NextBodyApplication.context }.getOrNull()

    private fun manager(): NotificationManager? =
        context?.getSystemService(NotificationManager::class.java)

    /** Whether the user lets this app post. Not an error when off — the session lives on screen. */
    val enabled: Boolean get() = manager()?.areNotificationsEnabled() == true

    fun start(sport: String, @Suppress("UNUSED_PARAMETER") modeRawValue: Int, state: ContentState) {
        if (this.sport != null) return
        if (!enabled) {
            Log.i(TAG, "notifications are off for this app")
            return
        }
        this.sport = sport
        manager()?.createNotificationChannel(NotificationChannel(CHANNEL, L("SESSION"),
            NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
        post(state, ongoing = true)
        lastState = state
        lastPushAt = System.currentTimeMillis()
        Log.i(TAG, "island up · $sport")
    }

    /** Push the wrist. `force` skips the cadence for the changes a person would notice. */
    fun update(state: ContentState, force: Boolean = false) {
        if (sport == null) return
        val last = lastState
        if (!force && last == state) return
        val says = last?.let { it.live != state.live || it.note != state.note } ?: true
        if (!(force || says || System.currentTimeMillis() - lastPushAt >= CADENCE_MS)) return
        lastState = state
        lastPushAt = System.currentTimeMillis()
        post(state, ongoing = true)
    }

    /** The session is over. The final numbers stay a moment for someone who put the phone down
     *  before pressing stop, then the notification goes. */
    fun end(state: ContentState) {
        if (sport == null) return
        post(state.copy(live = false, note = "SESSION ENDED"), ongoing = false, timeoutMs = 20_000)
        sport = null
        lastState = null
        Log.i(TAG, "island down")
    }

    /** Anything this process left behind — a crash mid-session. Called at launch. */
    fun clearOrphans() {
        if (sport == null) runCatching { manager()?.cancel(ID) }
    }

    private fun post(state: ContentState, ongoing: Boolean, timeoutMs: Long? = null) {
        val ctx = context ?: return
        val title = (sport ?: "").uppercase()
        val text = state.note ?: run {
            val hr = state.heartRate?.let { "$it BPM" } ?: "——"
            val kcal = if (state.energyAvailable) (if (state.energyEstimated) "≈" else "") + state.kcal + " KCAL" else "——"
            "$hr · $kcal"
        }
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val builder = Notification.Builder(ctx, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(L("LIVE") + " · " + title)
            .setContentText(text)
            .setOngoing(ongoing)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_WORKOUT)
            .setShowWhen(true)
            .setWhen(state.startedAt.toEpochMilli())
            .setUsesChronometer(ongoing)
            .setProgress(100, (state.effort * 100).roundToInt(), false)
        if (timeoutMs != null) builder.setTimeoutAfter(timeoutMs)
        if (launch != null) {
            builder.setContentIntent(PendingIntent.getActivity(ctx, 0, launch,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        }
        // A refusal is not worth a word on screen: the session is on the phone either way.
        runCatching { manager()?.notify(ID, builder.build()) }
            .onFailure { Log.e(TAG, "island refused · $it") }
    }
}
