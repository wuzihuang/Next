package com.nextbody.hoop.services

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import com.nextbody.hoop.R
import com.nextbody.hoop.band.BandBattery
import com.nextbody.hoop.band.BoundBand
import com.nextbody.hoop.band.NotificationDeepLink
import com.nextbody.hoop.band.NotificationReachMath
import com.nextbody.hoop.band.NotifyKind
import com.nextbody.hoop.band.NotifyPage
import com.nextbody.hoop.band.NotifyPlan
import com.nextbody.hoop.band.NotifySnapshot
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.MealEntry
import com.nextbody.hoop.data.NotificationReachPort
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.TickFreshness
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.WeekFields

/**
 * Turns edges (ADR 0019) into local notifications. The system permission dialog is only reached
 * through the UI's NotificationPrimer (`POST_NOTIFICATIONS` on Android 13+).
 *
 * Android: there is no APNs/FCM here (no push dependency), so remote registration is a no-op;
 * scheduled requests are AlarmManager alarms delivered by [NotificationReachReceiver], one per
 * [NotifyKind] (its `requestId` is the notification tag). Tapping a notification opens the
 * launcher activity with the `nextbody://…` deep link as intent data.
 */
object NotificationReach : NotificationReachPort {
    const val disconnectAtKey = "nb.notif.disconnectAt"
    private const val dayKey = "nb.notif.day"
    private const val countKey = "nb.notif.dayCount"
    private const val deliveredKey = "nb.notif.delivered"
    private const val prevKcalKey = "nb.notif.prevKcal"
    private const val prevActiveKey = "nb.notif.prevActive"
    private const val prevReserveKey = "nb.notif.prevReserve"
    private const val highReserveKey = "nb.notif.highReserve"
    private const val wrapOpenedKey = "nb.notif.wrapOpened"
    /** MorningWidget.shownKey. */
    private const val morningShownKey = "nb.bb.morningShownDay"

    /** The permission the UI asks for (Android 13+). */
    const val permission = Manifest.permission.POST_NOTIFICATIONS

    @Volatile var currentPage: NotifyPage = NotifyPage.other

    /**
     * Features/Home/MorningWidget.frame(today:history:now:ignoreShown: true) → (title, sentence).
     * Installed by the UI layer; null falls back to "LAST NIGHT · Last night is ready.".
     */
    @Volatile var morningFrame: ((DailyMetrics, List<DailyMetrics>, Instant) -> Pair<String, String>?)? = null

    /** LiveSessionStore.shared.session != nil — installed by the sport UI. */
    @Volatile var liveSessionActive: () -> Boolean = { false }

    private var context: Context? = null
    private val defaults: SharedPreferences? get() = context?.getSharedPreferences("nb", Context.MODE_PRIVATE)

    data class Prefs(val morning: Boolean, val training: Boolean, val meals: Boolean, val wrap: Boolean,
                     val energy: Boolean, val band: Boolean, val quiet: Boolean) {
        companion object {
            val current: Prefs
                get() {
                    val d = defaults
                    fun b(k: String) = d?.getBoolean(k, true) ?: true
                    return Prefs(b("nb.notif.morning"), b("nb.notif.training"), b("nb.notif.meals"),
                        b("nb.notif.wrap"), b("nb.notif.energy"), b("nb.notif.band"), b("nb.notif.quiet"))
                }
        }
    }

    fun init(context: Context) {
        this.context = context.applicationContext
        createChannels(context.applicationContext)
    }

    private fun channelId(kind: NotifyKind) = "nb.${kind.raw}"

    private fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val names = mapOf(
            NotifyKind.morning to "Morning", NotifyKind.meal to "Meals", NotifyKind.training to "Training",
            NotifyKind.daily to "Daily wrap", NotifyKind.reserve to "Readiness",
            NotifyKind.bandBattery to "Band battery", NotifyKind.bandAway to "Band away")
        for (kind in NotifyKind.entries) {
            manager.createNotificationChannel(NotificationChannel(channelId(kind),
                L(names[kind] ?: kind.raw), NotificationManager.IMPORTANCE_DEFAULT))
        }
    }

    /** Authorized = the app may post (permission granted on 13+, and not blocked in Settings). */
    fun isAuthorized(): Boolean {
        val ctx = context ?: return false
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(ctx, permission) != PackageManager.PERMISSION_GRANTED) return false
        return NotificationManagerCompat.from(ctx).areNotificationsEnabled()
    }

    suspend fun didGainAuthorization() {
        registerRemote()
        Analytics.track("NOTIF_AUTHORIZED")
    }

    /** No remote push on Android (no FCM dependency); kept so call sites read like iOS. */
    fun registerRemote() = Unit

    private var disconnectLivedThisProcess = false

    override fun stampDisconnect(connected: Boolean) = stampDisconnect(connected, Instant.now(), processLaunch = false)

    fun stampDisconnect(connected: Boolean, now: Instant, processLaunch: Boolean) {
        val d = defaults ?: return
        if (connected) {
            d.edit().remove(disconnectAtKey).apply()
            disconnectLivedThisProcess = true
            return
        }
        if (processLaunch && !disconnectLivedThisProcess) {
            // Dead process: start the 4h clock now. Do not backfill the old stamp.
            d.edit().putLong(disconnectAtKey, now.epochSecond).apply()
            disconnectLivedThisProcess = true
            return
        }
        if (!d.contains(disconnectAtKey)) d.edit().putLong(disconnectAtKey, now.epochSecond).apply()
        disconnectLivedThisProcess = true
    }

    private fun appIsActive(): Boolean =
        ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)

    override fun evaluate(store: DataStore) = evaluate(store, null)

    fun evaluate(store: DataStore, page: NotifyPage?) {
        queueScope.launch { refresh(store.today, store.history, store, page ?: currentPage, appIsActive()) }
    }

    /** Settings toggles cancel only. They must not backfill an edge that already exists. */
    fun applyPrefs() {
        val prefs = Prefs.current
        val drop = mutableListOf<NotifyKind>()
        if (!prefs.morning) drop += NotifyKind.morning
        if (!prefs.training) drop += NotifyKind.training
        if (!prefs.meals) drop += NotifyKind.meal
        if (!prefs.wrap) drop += NotifyKind.daily
        if (!prefs.energy) drop += NotifyKind.reserve
        if (!prefs.band) { drop += NotifyKind.bandBattery; drop += NotifyKind.bandAway }
        removePending(drop)
        removeDelivered(drop)
    }

    suspend fun refresh(today: DailyMetrics, history: List<DailyMetrics>, store: DataStore,
                        page: NotifyPage, appIsActive: Boolean) {
        currentPage = page
        val d = defaults ?: return
        val prefs = Prefs.current
        if (!isAuthorized()) {
            removePending(NotifyKind.entries)
            return
        }
        rollDay(today.day.key, d)
        stampDisconnect(store.band.connected, Instant.now(), processLaunch = true)
        harvestDelivered(d)

        // Lock-screen delivery is not on a page. Swallow only when the app is in front.
        val pageForMath = if (appIsActive) page else NotifyPage.other
        val snap = snapshot(today, history, store, pageForMath, prefs, d)
        persistEdges(today, d)

        val keep = mutableSetOf<NotifyKind>()
        when (val plan = NotificationReachMath.decide(snap)) {
            is NotifyPlan.Skip -> Unit
            is NotifyPlan.Later -> {
                keep += plan.kind
                Analytics.track("NOTIF_HOLD", mapOf("KIND" to plan.kind.raw))
                schedule(plan.kind, plan.at, today, history, plan.mealSlot, plan.weekly)
            }
            is NotifyPlan.Fire -> {
                keep += plan.kind
                Analytics.track("NOTIF_EDGE", mapOf("KIND" to plan.kind.raw))
                schedule(plan.kind, Instant.now().plusSeconds(2), today, history, plan.mealSlot, plan.weekly)
            }
        }

        val awayAt = NotificationReachMath.awayFireAt(snap)
        if (awayAt != null && NotifyKind.bandAway !in keep && NotifyKind.bandBattery !in keep &&
            snap.deliveredCount < NotificationReachMath.budget) {
            var fire: Instant = awayAt
            if (snap.quietEnabled && NotificationReachMath.isQuiet(fire)) {
                fire = maxOf(fire, NotificationReachMath.quietEnd(maxOf(fire, snap.now)))
            }
            keep += NotifyKind.bandAway
            schedule(NotifyKind.bandAway, fire, today, history, null, false)
        }
        removePending(NotifyKind.entries.filter { it !in keep })
    }

    fun cancelMorning() {
        removePending(listOf(NotifyKind.morning))
        removeDelivered(listOf(NotifyKind.morning))
    }

    /** Called by the receiver when a notification is shown (or swallowed). */
    internal fun markPresented(kind: NotifyKind) {
        val d = defaults ?: return
        markDelivered(kind, d)
        queueScope.launch { Analytics.track("NOTIF_DELIVERED", mapOf("KIND" to kind.raw)) }
    }

    /** ADR 0019 swallow: the page this edge links to is already open. */
    internal fun swallows(kind: NotifyKind): Boolean =
        appIsActive() && NotificationReachMath.swallows(kind, currentPage)

    internal fun markSeenPublic(kind: NotifyKind) { defaults?.let { markSeen(kind, it) } }

    private fun harvestDelivered(d: SharedPreferences) {
        val ctx = context ?: return
        val manager = ctx.getSystemService(NotificationManager::class.java) ?: return
        for (note in runCatching { manager.activeNotifications.toList() }.getOrDefault(emptyList())) {
            val kind = NotifyKind.entries.firstOrNull { it.requestId == note.tag } ?: continue
            markDelivered(kind, d)
        }
    }

    private fun snapshot(today: DailyMetrics, history: List<DailyMetrics>, store: DataStore,
                         page: NotifyPage, prefs: Prefs, d: SharedPreferences): NotifySnapshot {
        val now = Instant.now()
        val m = history.firstOrNull { it.day == today.day && it.reserveCurve.isNotEmpty() } ?: today
        val peak = m.bodyBatteryWakeAt ?: NotificationReachMath.wakePeak(m.day.start, m.reserveCurve.map { it.ts to it.value })
        val shown = d.getString(morningShownKey, null) == m.day.key
        val meals = store.meals + store.recentMeals
        val weekDays = UserDay.last(7, today.day)
        val meals7 = meals.count { it.day in weekDays && it.status == MealEntry.Status.confirmed }
        val todayMeals = meals.filter { it.day == today.day && it.status == MealEntry.Status.confirmed }
        val slots = todayMeals.map { it.slot }.toSet()
        val prevKcal = if (d.contains(prevKcalKey)) java.lang.Double.longBitsToDouble(d.getLong(prevKcalKey, 0)) else null
        val prevActive = if (d.contains(prevActiveKey)) d.getInt(prevActiveKey, 0) else null
        val kcalRose = prevKcal?.let { (today.eOutNow ?: 0.0) > it } ?: false
        val activeRose = prevActive?.let { (today.activeMinutes ?: 0) > it } ?: false
        val prevReserve = if (d.contains(prevReserveKey)) d.getInt(prevReserveKey, 0) else null
        val storedHigh = if (d.contains(highReserveKey)) d.getInt(highReserveKey, 0) else null
        val reserve = today.bodyBatteryForDisplay(now)
        val high = listOfNotNull(storedHigh, reserve, today.bbWake).maxOrNull()
        val disconnect = if (d.contains(disconnectAtKey)) Instant.ofEpochSecond(d.getLong(disconnectAtKey, 0)) else null
        val zone = ZoneId.systemDefault()
        val prevDay = today.day.adding(-1).start
        // Calendar.current's week (locale first weekday), like Swift `.weekOfYear`.
        val week = WeekFields.of(java.util.Locale.getDefault()).weekOfWeekBasedYear()
        val weekRolled = today.day.start.atZone(zone).get(week) != prevDay.atZone(zone).get(week)
        val priorWeek = UserDay.last(7, today.day.adding(-1))
        val validPrior = history.count { it.day in priorWeek && (it.bbWake != null || it.trainingLoad != null) }
        val charge = store.band.displayedCharge
        val charging = charge == BandBattery.ChargeState.charging || charge == BandBattery.ChargeState.full
        val last = store.band.lastBattery
        return NotifySnapshot(
            now = now, quietEnabled = prefs.quiet,
            deliveredCount = d.getInt(countKey, 0),
            delivered = deliveredSet(d),
            page = page,
            morningOn = prefs.morning, trainingOn = prefs.training, mealsOn = prefs.meals,
            wrapOn = prefs.wrap, energyOn = prefs.energy, bandOn = prefs.band,
            wakePeak = peak, morningShown = shown,
            daySealed = today.day.end <= now,
            mealsInLast7Days = meals7,
            breakfastConfirmed = MealEntry.Slot.breakfast in slots,
            lunchConfirmed = MealEntry.Slot.lunch in slots,
            dinnerConfirmed = MealEntry.Slot.dinner in slots,
            moved = kcalRose || activeRose,
            trainingLoad = today.trainingLoad, targetLoad = today.targetLoad,
            reserveNow = reserve, prevReserve = prevReserve, bbWake = today.bbWake,
            dayHighReserve = high, liveSession = liveSessionActive(),
            reserveFresh = today.bodyBatteryFreshness(now) != TickFreshness.gone,
            hasNightCharge = m.reserveDrivers?.nightCharge != null,
            hasConfirmedMeal = todayMeals.isNotEmpty(),
            weekRolled = weekRolled, priorWeekValidDays = validPrior,
            appOpenedAfterComplete = d.getBoolean(wrapOpenedKey, false),
            bandBound = BoundBand.identifier != null,
            bandConnected = store.band.connected,
            bandCharging = charging,
            bandPercent = if (last?.isPercent == true) store.band.batteryPercent else null,
            bandBars = if (last?.isPercent == false) last.level else null,
            disconnectStarted = if (store.band.connected) null else disconnect)
    }

    private fun persistEdges(today: DailyMetrics, d: SharedPreferences) {
        val e = d.edit()
        today.eOutNow?.let { e.putLong(prevKcalKey, java.lang.Double.doubleToRawLongBits(it)) }
        today.activeMinutes?.let { e.putInt(prevActiveKey, it) }
        today.bodyBattery?.let { r ->
            e.putInt(prevReserveKey, r)
            val high = maxOf(if (d.contains(highReserveKey)) d.getInt(highReserveKey, r) else r, r)
            e.putInt(highReserveKey, high)
        }
        e.apply()
    }

    private fun rollDay(key: String, d: SharedPreferences) {
        if (d.getString(dayKey, null) == key) return
        d.edit().putString(dayKey, key).putInt(countKey, 0).putString(deliveredKey, "")
            .putBoolean(wrapOpenedKey, false).remove(prevKcalKey).remove(prevActiveKey)
            .remove(prevReserveKey).remove(highReserveKey).apply()
    }

    private fun deliveredSet(d: SharedPreferences): Set<NotifyKind> =
        (d.getString(deliveredKey, "") ?: "").split(",").mapNotNull { raw -> NotifyKind.entries.firstOrNull { it.raw == raw } }.toSet()

    private fun markDelivered(kind: NotifyKind, d: SharedPreferences) {
        if (!markSeen(kind, d)) return
        d.edit().putInt(countKey, d.getInt(countKey, 0) + 1).apply()
    }

    private fun markSeen(kind: NotifyKind, d: SharedPreferences): Boolean {
        val set = deliveredSet(d).toMutableSet()
        if (!set.add(kind)) return false
        d.edit().putString(deliveredKey, set.map { it.raw }.sorted().joinToString(",")).apply()
        return true
    }

    private fun pendingIntent(ctx: Context, kind: NotifyKind, intent: Intent?, flags: Int): PendingIntent? =
        PendingIntent.getBroadcast(ctx, 7000 + kind.ordinal,
            intent ?: Intent(ctx, NotificationReachReceiver::class.java).setAction(ACTION),
            flags or PendingIntent.FLAG_IMMUTABLE)

    private fun removePending(kinds: Collection<NotifyKind>) {
        val ctx = context ?: return
        val alarms = ctx.getSystemService(AlarmManager::class.java) ?: return
        for (kind in kinds) {
            pendingIntent(ctx, kind, null, PendingIntent.FLAG_NO_CREATE)?.let { alarms.cancel(it); it.cancel() }
        }
    }

    private fun removeDelivered(kinds: Collection<NotifyKind>) {
        val ctx = context ?: return
        val manager = NotificationManagerCompat.from(ctx)
        kinds.forEach { manager.cancel(it.requestId, 0) }
    }

    private suspend fun schedule(kind: NotifyKind, fire: Instant, m: DailyMetrics, history: List<DailyMetrics>,
                                 mealSlot: String?, weekly: Boolean) {
        val ctx = context ?: return
        val link = if (kind == NotifyKind.meal) NotificationDeepLink.Fuel(mealSlot) else kind.deepLink
        val (title, body) = when (kind) {
            NotifyKind.morning -> morningFrame?.invoke(m, history, fire) ?: (L("LAST NIGHT") to L("Last night is ready."))
            NotifyKind.meal -> L(mealSlot?.uppercase() ?: "LUNCH") to L("Have you eaten yet?")
            NotifyKind.training -> L("TRAINING") to L("You are still under today's target.")
            NotifyKind.daily -> (if (weekly) L("THIS WEEK") else L("TODAY")) to wrapBody(m)
            NotifyKind.reserve -> L("READINESS") to L("Readiness is low.")
            NotifyKind.bandBattery -> L("NEXTBODY") to L("Charge NEXTBODY.")
            NotifyKind.bandAway -> L("NEXTBODY") to L("NEXTBODY has been away for 4 hours.")
        }
        val soon = maxOf(fire, Instant.now().plusSeconds(2))
        val intent = Intent(ctx, NotificationReachReceiver::class.java).setAction(ACTION)
            .putExtra(EXTRA_KIND, kind.raw).putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_BODY, body).putExtra(EXTRA_URL, link.url)
        val pending = pendingIntent(ctx, kind, intent, PendingIntent.FLAG_UPDATE_CURRENT) ?: return
        val alarms = ctx.getSystemService(AlarmManager::class.java) ?: return
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, soon.toEpochMilli(), pending)
        Analytics.track("NOTIF_SCHEDULED", mapOf("KIND" to kind.raw, "AT" to Iso.string(soon)))
    }

    private fun wrapBody(m: DailyMetrics): String {
        val parts = mutableListOf<String>()
        m.trainingLoad?.let { parts += L("Load %@", formatG(it)) }
        m.eIn?.let { parts += L("%@ in", Math.round(it).toString()) }
        m.bodyBatteryForDisplay()?.let { parts += L("reserve %@", it.toString()) }
        if (parts.isEmpty()) return L("The day is filling in.")
        return parts.joinToString(" · ") + "."
    }

    /** `String(format: "%g", x)` — trailing zeros trimmed. */
    private fun formatG(x: Double): String {
        val s = String.format(java.util.Locale.ROOT, "%g", x)
        return if (s.contains('e')) s else s.trimEnd('0').trimEnd('.')
    }

    internal const val ACTION = "com.nextbody.hoop.NOTIFY"
    internal const val EXTRA_KIND = "kind"
    internal const val EXTRA_TITLE = "title"
    internal const val EXTRA_BODY = "body"
    internal const val EXTRA_URL = "url"

    /** Posts the notification for an alarm that fired (or swallows it). */
    internal fun deliver(ctx: Context, intent: Intent) {
        if (context == null) init(ctx)
        val kind = NotifyKind.entries.firstOrNull { it.raw == intent.getStringExtra(EXTRA_KIND) } ?: return
        if (!isAuthorized()) return
        if (swallows(kind)) { markSeenPublic(kind); return }
        val url = intent.getStringExtra(EXTRA_URL) ?: NotificationDeepLink.Home.url
        val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            ?.setAction(Intent.ACTION_VIEW)?.setData(Uri.parse(url))
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val content = open?.let {
            PendingIntent.getActivity(ctx, 8000 + kind.ordinal, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val notification = NotificationCompat.Builder(ctx, channelId(kind))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(intent.getStringExtra(EXTRA_TITLE))
            .setContentText(intent.getStringExtra(EXTRA_BODY))
            .setStyle(NotificationCompat.BigTextStyle().bigText(intent.getStringExtra(EXTRA_BODY)))
            .setAutoCancel(true)
            .setContentIntent(content)
            .setGroup(kind.requestId)
            .build()
        try {
            NotificationManagerCompat.from(ctx).notify(kind.requestId, 0, notification)
            markPresented(kind)
        } catch (e: SecurityException) {
            ServiceLog.record("notify", e)
        }
    }
}

/** AlarmManager target for scheduled edges. Declared in the manifest (not exported). */
class NotificationReachReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == NotificationReach.ACTION) NotificationReach.deliver(context, intent)
    }
}
