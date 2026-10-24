package com.nextbody.hoop.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.features.vitals.VitalsMetric
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/**
 * F1 · The Map. Four kinds of surface and no fifth.
 *  A · GATE      — a straight line walked once per account
 *  B · THE ROOT  — Home, the only root
 *  C · FROM THE ROOT · 5 — full pages, never nested, back always returns to the root
 *  D · ON TOP    — takeovers and sheets; closing one restores the same scroll position
 */
sealed class Destination {
    data object Training : Destination()
    data object Fuel : Destination()
    /** 09 edge 5 · a closed day, reached from THIS WEEK's day labels. */
    data class FuelDay(val day: UserDay) : Destination()
    data object BodyBattery : Destination()
    /** 04 · one of page two's vitals boards, opened from its own card. */
    data class Vitals(val metric: VitalsMetric) : Destination()
    data class Composition(val date: LocalDate? = null) : Destination()
    data object Profile : Destination()
    /** ADR 0010 · 主动测量记录的清单。从「我的」那块 MEASUREMENTS 进，返回回「我的」。 */
    data object Measurements : Destination()
    /** reached from profile or the home battery pip */
    data object Device : Destination()
    /** trend behind the device ring */
    data object Battery : Destination()
    data object DeviceAutoMonitor : Destination()
    /** Plus menu · Sport Mode. Pick one of the catalogued modes and open it on the band. */
    data object SportMode : Destination()

    /** AI destinations exist on the wire but AI is off (AIFeature.enabled = false). */
    val isAI: Boolean get() = false

    val key: String
        get() = when (this) {
            is FuelDay -> "fuelDay:${day}"
            is Vitals -> "vitals:${metric.raw}"
            is Composition -> "composition:${date}"
            else -> this::class.simpleName ?: "?"
        }

    companion object {
        /**
         * F0 rule 06 · the values `TARGETS` allows on the wire. `device`, `measurements` and the
         * device sheets are deliberately absent: they are reachable only from profile.
         */
        fun fromEnvelopeTarget(raw: String): Destination? = when (raw) {
            "training" -> Training
            "fuel" -> Fuel
            "bodyBattery" -> BodyBattery
            "composition" -> Composition(null)
            "profile" -> Profile
            else -> {
                if (!raw.startsWith("vitals.")) null
                else {
                    val name = raw.removePrefix("vitals.")
                    // Night HRV lives on the sleep page.
                    if (name == "hrv") Vitals(VitalsMetric.sleep)
                    else VitalsMetric.from(name)?.let { Vitals(it) }
                }
            }
        }
    }
}

/** Where a detail page was entered from. One layer only — no multi-level history stack. */
enum class EntryPoint { home, profile }

/** Full-screen takeovers. Not pages: the panel on Home grown to full size. */
sealed class Takeover {
    /** 2.6s brand animation, no close mark */
    data object Wordmark : Takeover()
    data class Measure(val kind: MeasureKind) : Takeover()
    /** 补屏 A · from NOT COLLECTING or Settings › Data */
    data object Consent : Takeover()
    /** F5 C4 · before the one system dialog, after the first real morning */
    data object NotificationPrimer : Takeover()
}

enum class MeasureKind(val raw: String) {
    heartRate("heartRate"), bloodOxygen("bloodOxygen"), bloodPressure("bloodPressure"),
    ecg("ecg"), temperature("temperature"), bodyComposition("bodyComposition");

    companion object {
        fun from(raw: String): MeasureKind? = entries.firstOrNull { it.raw == raw }
    }
}

/** Bottom sheets. The screen underneath always shows its title and one row of value. */
sealed class SheetRoute {
    // 03 · onboarding
    data object Height : SheetRoute()
    data object WeightBaseline : SheetRoute()
    data object Birthday : SheetRoute()
    // 10S
    data object WeighIn : SheetRoute()
    /** 14 · the scale dial in front of a body scan. */
    data object ScanWeighIn : SheetRoute()
    // 11 · profile
    data object ProfileEdit : SheetRoute()
    data object Goal : SheetRoute()
    data object Units : SheetRoute()
    data object Notifications : SheetRoute()
    /** Was `appleHealth` on iOS: the Health Connect link sheet. */
    data object HealthConnect : SheetRoute()
    data object Language : SheetRoute()
    data object About : SheetRoute()
    data object Privacy : SheetRoute()
    data object DeleteAccount : SheetRoute()
    data object SignOut : SheetRoute()
    data object Widgets : SheetRoute()
    /** ADR 0032 · the MCP address and every assistant connected to this account. */
    data object Assistants : SheetRoute()
    /** Profile › REPORT A PROBLEM · title, words, screenshots → one GitHub issue. */
    data object Feedback : SheetRoute()
    /** ADR 0010 · 一条测量记录的全部字段。 */
    data class Measurement(val id: UUID) : SheetRoute()
    // 12S · device
    data object BandAutoMonitor : SheetRoute()
    data object FindBand : SheetRoute()
    data object Unbind : SheetRoute()
    data object Disconnect : SheetRoute()
    data object Firmware : SheetRoute()
    data object SyncCadence : SheetRoute()
    /** 9-0 A·S1–S6 · give the second NEXTBODY its slot. */
    data object ActivateSecond : SheetRoute()
    /** 9-0 A·S8 · one tap on the other NEXTBODY's card; payload is the slot being switched to. */
    data class WearSwitch(val slot: String) : SheetRoute()
    /** Choose one NEXTBODY to remove; the other binding and account history stay. */
    data object ReleaseSet : SheetRoute()
    /** 12Y · find the wrist (LED). Not `.findBand`. */
    data object FindHoop : SheetRoute()
    /** 12Y · new-alarm table (SWITCH). */
    data object BandAlarms : SheetRoute()
    /** 12S · the light on the side. DEBUG only. */
    data object HealthLight : SheetRoute()
    // dock
    data object PlusMenu : SheetRoute()
}

/** The phone's notification deep links (ADR 0019). */
sealed class NotificationDeepLink {
    data object HomePanel : NotificationDeepLink()
    data object Home : NotificationDeepLink()
    data class Fuel(val slot: String?) : NotificationDeepLink()
    data object Training : NotificationDeepLink()
    data object Device : NotificationDeepLink()
    data class Composition(val day: String?) : NotificationDeepLink()
    data object LogPhoto : NotificationDeepLink()

    companion object {
        /** `nextbody://<host>?<query>` */
        fun parse(uri: android.net.Uri): NotificationDeepLink? {
            if (uri.scheme != "nextbody") return null
            return when (uri.host) {
                "home" -> if (uri.getQueryParameter("panel") == "body_battery") HomePanel else Home
                "fuel" -> Fuel(uri.getQueryParameter("slot"))
                "training" -> Training
                "device" -> Device
                "composition" -> Composition(uri.getQueryParameter("day"))
                "log-photo", "logPhoto" -> LogPhoto
                else -> null
            }
        }
    }
}

/** ADR 0019 · which deep-link page is already open, for swallow. */
enum class NotifyPage { fuel, training, device, bodyBattery, other }

/** A detail page asks for its data on push; reads wait out what is left of the push slide. */
object PushSettle {
    private var pushedAt = 0L
    private const val TRANSITION_MS = 400L
    fun mark() { pushedAt = System.currentTimeMillis() }
    suspend fun await() {
        val left = TRANSITION_MS - (System.currentTimeMillis() - pushedAt)
        if (left > 0) kotlinx.coroutines.delay(left)
    }
}

object Router {
    var path by mutableStateOf(listOf<Destination>())

    /** ADR 0019 · which deep-link page is already open, for swallow. */
    val notifyPage: NotifyPage
        get() = when (path.lastOrNull()) {
            is Destination.Fuel, is Destination.FuelDay -> NotifyPage.fuel
            Destination.Training -> NotifyPage.training
            Destination.Device -> NotifyPage.device
            Destination.BodyBattery -> NotifyPage.bodyBattery
            else -> NotifyPage.other
        }

    var entry by mutableStateOf(EntryPoint.home)
    var takeoverGeneration = 0L
        private set
    @set:JvmName("assignTakeover")
    var takeover by mutableStateOf<Takeover?>(null)
        private set

    fun setTakeover(t: Takeover?) {
        val previous = takeover
        takeoverGeneration += 1
        takeover = t
        onTakeoverChanged?.invoke(previous, t)
        if (t == null) flushQueuedLink()
    }

    /** Installed by the app shell (BandLiveLifecycle exclusivity, consent refresh). */
    var onTakeoverChanged: ((Takeover?, Takeover?) -> Unit)? = null

    var sheet by mutableStateOf<SheetRoute?>(null)

    /** 06 rule 09 · the measuring screen folds its result back onto the panel as one widget. */
    var measuredWidget by mutableStateOf<com.nextbody.hoop.features.home.panel.PanelWidget?>(null)

    /** 09 edge 5 · ADD TO THAT DAY: back-logging goes through the dock, prefilled with the day. */
    data class DockPrefill(val text: String, val day: UserDay)
    var dockPrefill by mutableStateOf<DockPrefill?>(null)

    /**
     * 04B · which home pager page is showing. 0 = panel + strip, 1 = vitals. Lives on the
     * router so a push/pop cannot wipe it.
     */
    var homePage by mutableIntStateOf(0)

    /** docs/plans/2026-09-09-ai-tool-surface.md · the detail page that is showing switches its
     *  DAY / WEEK / MONTH pills and clears the request. */
    var windowRequest by mutableStateOf<String?>(null)
    /** The device page owns its own sheets; a request asks it to lift one once on screen. */
    var deviceSheetRequest by mutableStateOf<SheetRoute?>(null)

    /** Taken the moment the root is left. Every dismiss path restores this. */
    private var homePageOnLeave = 0
    /** F1 · a notification tap while measuring waits here until the takeover folds. */
    private var queuedLink: NotificationDeepLink? = null
    /** F1 · `nextbody://home?panel=body_battery` — Home puts 昨夜 on the panel. */
    var pendingHomePanel by mutableStateOf<String?>(null)
    /** ADR 0019 · `nextbody://fuel?slot=` lands on Fuel; the slot is for the page to read. */
    var pendingFuelSlot by mutableStateOf<String?>(null)

    /** F0 rule 06: every widget on the panel is tappable and declares its target page. */
    fun open(d: Destination, from: EntryPoint = EntryPoint.home) {
        if (d.isAI) return
        if (path.isEmpty()) homePageOnLeave = homePage
        entry = from
        var dest = d
        if (dest is Destination.Vitals && dest.metric == VitalsMetric.hrv) dest = Destination.Vitals(VitalsMetric.sleep)
        PushSettle.mark()
        path = path + dest
    }

    /** All detail pages return to the root. The home pager page is restored. */
    fun backToRoot() {
        path = emptyList()
        homePage = homePageOnLeave
    }

    /** Leaves every detail page and shows one home pager slot. */
    fun showHome(page: Int) {
        homePageOnLeave = page
        path = emptyList()
        homePage = page
    }

    fun back() {
        if (path.isEmpty()) return
        path = path.dropLast(1)
        if (path.isEmpty()) homePage = homePageOnLeave
    }

    /** F1 Sec 03 · a tap on a notification. Measuring queues it; anything else lands now. */
    fun receive(link: NotificationDeepLink) {
        if (takeover is Takeover.Measure) {
            queuedLink = link
            return
        }
        apply(link)
    }

    fun flushQueuedLink() {
        val link = queuedLink ?: return
        if (takeover != null) return
        queuedLink = null
        apply(link)
    }

    fun apply(link: NotificationDeepLink) {
        when (link) {
            NotificationDeepLink.HomePanel -> {
                if (path.isNotEmpty()) backToRoot()
                homePage = 0
                pendingHomePanel = "body_battery"
            }
            NotificationDeepLink.Home -> {
                if (path.isNotEmpty()) backToRoot()
                homePage = 0
                pendingHomePanel = null
            }
            is NotificationDeepLink.Fuel -> {
                pendingFuelSlot = link.slot
                open(Destination.Fuel)
            }
            NotificationDeepLink.Training -> open(Destination.Training)
            NotificationDeepLink.Device -> {
                if (path.isEmpty()) homePageOnLeave = homePage
                entry = EntryPoint.profile
                path = listOf(Destination.Profile, Destination.Device)
            }
            is NotificationDeepLink.Composition -> {
                val day = link.day?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                open(Destination.Composition(day))
            }
            NotificationDeepLink.LogPhoto -> Unit
        }
    }

    /** Sign-out / account switch: nothing of the previous account's navigation survives. */
    fun reset() {
        path = emptyList()
        sheet = null
        takeover = null
        homePage = 0
        homePageOnLeave = 0
        queuedLink = null
        pendingHomePanel = null
        pendingFuelSlot = null
    }

    @Suppress("unused")
    private val zone: ZoneId get() = ZoneId.systemDefault()
}
