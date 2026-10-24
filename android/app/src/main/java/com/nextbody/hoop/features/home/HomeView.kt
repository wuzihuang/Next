package com.nextbody.hoop.features.home

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.DpRect
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.features.sport.LiveSessionLayer
import com.nextbody.hoop.features.sport.LiveSessionStore
import com.nextbody.hoop.ui.Chrome
import com.nextbody.hoop.ui.HomeHeaderHeight
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.nextbody.hoop.app.AppSession
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.app.Takeover
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandLiveLifecycle
import com.nextbody.hoop.band.BandRefreshRequest
import com.nextbody.hoop.band.OriginDataSync
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.Defaults
import com.nextbody.hoop.data.SessionStore
import com.nextbody.hoop.features.home.panel.PanelWidget
import com.nextbody.hoop.features.home.panel.VitalsMath
import com.nextbody.hoop.features.home.panel.VitalsPage
import com.nextbody.hoop.services.ConsentStore
import com.nextbody.hoop.services.NotificationReach
import com.nextbody.hoop.services.Repository
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.ui.carbonPage
import com.nextbody.hoop.ui.rememberReduceMotion
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * 04 · THE ROOT. The only root in the product; every detail page returns here.
 *
 * Port note: with `AIFeature.enabled == false` the iOS root draws `HomeV2Shell` and nothing
 * else — the dock, the panel, the plus sheet, the plan face and every voice / photo / turn
 * path are behind the AI switch (or, for the dock and panel, no longer composed at all).
 * What remains here is the root's lifecycle: hydration, the 30 s refresh, the morning
 * frame and the notification primer, the live-readout demand, and page two's analytics.
 */
@Composable
fun HomeView(modifier: Modifier = Modifier) {
    val data = DataStore
    val session: SessionStore = AppSession.session
    val context = LocalContext.current
    val reduceMotion = rememberReduceMotion()
    val firstRun = remember { FirstRun() }
    val scope = rememberCoroutineScope()
    val lifecycle = LocalLifecycleOwner.current.lifecycle

    var active by remember { mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    /** The panel frame (昨夜). There is no panel on the V2 root; the value is kept for the readout gate. */
    var widget by remember { mutableStateOf<PanelWidget?>(null) }
    /** `router.homePage`, mirrored. */
    var homePage by remember { mutableStateOf(Router.homePage) }
    var pageTwoSince by remember { mutableStateOf<Instant?>(null) }
    var pageTwoTrack by remember { mutableStateOf<Job?>(null) }
    /** True while page two is holding a session that was running when the page turned. */
    var readoutHeldOnPageTwo by remember { mutableStateOf(false) }
    var readoutHold by remember { mutableStateOf<Job?>(null) }

    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> active = true
                Lifecycle.Event.ON_PAUSE -> {
                    active = false
                    readoutHold?.cancel()
                    readoutHold = null
                    readoutHeldOnPageTwo = false
                }
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }

    /**
     * 04 · when the root's resting face gets to hold the band. Everything that covers it ends
     * the readout: a takeover, a detail page, the first-run ceremony. Leaving the app ends it
     * too (`BandLivePolicy`, ADR 0023). ⚠️ A live readout nobody is looking at is a band flat by
     * lunchtime, and without consent the band is not read at all: pairing is not permission.
     */
    val liveReadoutAllowed = firstRun.dockVisible && !firstRun.playing &&
        Router.path.isEmpty() && Router.takeover == null &&
        widget == null && LiveSessionStore.session == null &&
        data.band.connected && ConsentStore.granted
    val liveReadoutWanted = liveReadoutAllowed && (homePage == 0 || readoutHeldOnPageTwo)

    // The app owns the stream. This page contributes demand, not task lifetime.
    LaunchedEffect(liveReadoutWanted) { BandLiveLifecycle.shared.setForegroundWanted(liveReadoutWanted) }
    DisposableEffect(Unit) { onDispose { BandLiveLifecycle.shared.setForegroundWanted(false) } }

    /**
     * 04B 上线前 · every opening of page two reports what the cards actually showed — after the
     * page has been held for a moment; a turn away cancels it.
     */
    fun trackPageTwoOpen() {
        pageTwoTrack?.cancel()
        pageTwoTrack = scope.launch {
            delay(3000)
            val m = data.today
            val vitals = data.vitals
            val lastSync = data.lastSync
            val states = VitalsPage.cardStates(
                m = m, vitals = vitals, history = data.history,
                mealResponsePoints = data.mealResponsePoints,
                mealResponseZerosToday = data.mealResponseZerosToday,
            )
            val gap = VitalsMath.offWrist(m.vitalsCurve)
            for (card in listOf("SLEEP", "HEART", "BODY_BATTERY", "STRESS", "TEMP", "STEPS", "DISTANCE", "ACTIVE")) {
                track("PAGE2_CARD_STATE", mapOf("CARD" to card, "STATE" to (states[card] ?: "EMPTY")))
            }
            if (lastSync == null) track("PAGE2_NOT_SYNCED", mapOf("PLATFORM" to "android"))
            if (gap != null && gap.minutes >= 60) {
                val key = "nb.page2.offwrist.${m.day.key}"
                if (!Defaults.getBoolean(key)) {
                    Defaults.putBoolean(key, true)
                    track("PAGE2_OFF_WRIST", mapOf("MIN" to gap.minutes))
                }
            }
        }
    }

    // router.pager.$page — the page set by a turn, or by a detail page returning the user.
    LaunchedEffect(Unit) {
        var first = true
        snapshotFlow { Router.homePage }.collect { p ->
            if (first) { first = false; homePage = p; return@collect }
            if (p == homePage) return@collect
            homePage = p
            // 04 · the readout is handed to page two for a short grace, and only if it was
            // actually running — the grace holds a session open, it never opens one.
            readoutHold?.cancel()
            readoutHold = null
            if (p == 1 && liveReadoutAllowed) {
                readoutHeldOnPageTwo = true
                readoutHold = scope.launch {
                    delay(PAGE_TWO_READOUT_GRACE_MS)
                    readoutHeldOnPageTwo = false
                }
            } else {
                readoutHeldOnPageTwo = false
            }
            if (p == 1) {
                pageTwoSince = Instant.now()
                trackPageTwoOpen()
            } else {
                val since = pageTwoSince
                if (since != null) {
                    pageTwoTrack?.cancel()
                    pageTwoSince = null
                    val ms = Instant.now().toEpochMilli() - since.toEpochMilli()
                    track("HOME_PAGE2_DWELL", mapOf("MS" to ms.toInt()))
                }
            }
        }
    }

    // nextbody://home?panel=body_battery puts 昨夜 on the panel. The V2 root has no panel to
    // put it on; the request is still consumed so it cannot fire later.
    LaunchedEffect(Router.pendingHomePanel) {
        if (Router.pendingHomePanel != "body_battery") return@LaunchedEffect
        Router.pendingHomePanel = null
    }

    // A fresh measurement lands on the panel (`onChange(of: router.measuredWidget)`).
    LaunchedEffect(Router.measuredWidget) {
        val w = Router.measuredWidget ?: return@LaunchedEffect
        widget = w
        Router.measuredWidget = null
    }

    LaunchedEffect(session.holdingLaunchStill) {
        if (!session.holdingLaunchStill) firstRun.start(reduceMotion = reduceMotion, lowPower = lowPower(context))
    }

    LaunchedEffect(Unit) {
        if (!session.holdingLaunchStill) firstRun.start(reduceMotion = reduceMotion, lowPower = lowPower(context))

        // F3 §05 · the home screen reads one row of daily_results and nothing else.
        // ⚠️ Not tied to the page's visibility: a push over the root must not cancel the load
        // (a cancelled load fell back to the offline seed and turned the app into a mock).
        val store = data
        val sync = scope.async { OriginDataSync.refreshNow(store, BandRefreshRequest.foreground) }
        val load = scope.async { Repository.bootstrapHome(store) }
        load.await()

        // A device with no session is not a home screen, it is a gate that was skipped.
        // Back to the gate; the band stays bound, the history stays on the server.
        if (!Band.allowsSeed && SupabaseClient.currentUserId == null) {
            session.stage = SessionStore.Stage.gateSignIn
            return@LaunchedEffect
        }

        // 13 col 01 · 昨夜, once a day, within six hours of waking. F5 C4 · the primer still
        // follows the first real morning; later edges do not re-ask.
        if (widget == null) {
            val morning = MorningWidget.frame(data.today, data.history)
            if (morning != null) {
                widget = morning
                MorningWidget.markShown(data.today.day, morning)
                NotificationReach.cancelMorning()
                if (NotificationPrimerPolicy.shouldOffer(context)) Router.setTakeover(Takeover.NotificationPrimer)
            }
        }
        NotificationReach.refresh(
            today = data.today, history = data.history, store = data,
            page = com.nextbody.hoop.band.NotifyPage.valueOf(Router.notifyPage.name), appIsActive = active,
        )

        // The shared pull started alongside cloud hydration and still retains all history.
        sync.await()

        // The view owns only this timer. The shared refresh applies the current cadence and
        // sensor eligibility; checking every half minute picks up cadence changes.
        while (isActive) {
            delay(30_000)
            if (!isActive) break
            OriginDataSync.refreshNow(store, BandRefreshRequest.foreground)
        }
    }

    Box(modifier.fillMaxSize().carbonPage()) {
        HomeV2Shell()
        // 14 · the sport session the band is running. While one is on, the panel is the whole
        // screen, the page does not turn, and the resting readout is stood down.
        val safeTop = ScreenMetrics.safeTop
        val safeBottom = ScreenMetrics.safeBottom
        val gutter = NB.Layout.gutter
        val panelTop = safeTop + HomeHeaderHeight + 12.dp
        val homeIndicatorExtra = (safeBottom - Chrome.boardHomeIndicator.dp).coerceAtLeast(0.dp)
        val dockBottom = safeBottom + 60.dp - homeIndicatorExtra - 4.dp
        val panelHeight = ScreenMetrics.height - panelTop - 12.dp - NB.Layout.stripHeight - 12.dp -
            NB.Layout.dockHeight - dockBottom
        val columnWidth = ScreenMetrics.width - gutter * 2
        Box(Modifier.zIndex(6f)) {
            LiveSessionLayer(
                panelFrame = DpRect(DpOffset(gutter, panelTop), DpSize(columnWidth, panelHeight)),
                onWidget = { summary -> widget = summary },
            )
        }
    }
}

/**
 * 04B · page two is the one cover that does not end the readout on the spot: a flip to the
 * instruments and back is the same person looking at the same face. ⚠️ Seconds, not minutes.
 */
private const val PAGE_TWO_READOUT_GRACE_MS = 20_000L

private fun lowPower(context: android.content.Context): Boolean = runCatching {
    (context.getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager).isPowerSaveMode
}.getOrDefault(false)
