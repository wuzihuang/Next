package com.nextbody.hoop.features.device

import com.nextbody.hoop.features.connect.DottedProgress
import com.nextbody.hoop.features.connect.LimePillButton
import com.nextbody.hoop.features.profile.Chevron

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.app.Destination
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.app.SheetRoute
import com.nextbody.hoop.app.Takeover
import com.nextbody.hoop.band.AutoMonitorSlot
import com.nextbody.hoop.band.AutoMonitoringRead
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandBattery
import com.nextbody.hoop.band.BandConnectionState
import com.nextbody.hoop.band.BandHealthLightPreference
import com.nextbody.hoop.band.BandHealthLightState
import com.nextbody.hoop.band.BandHost
import com.nextbody.hoop.band.BandIdentity
import com.nextbody.hoop.band.BandLiveLifecycle
import com.nextbody.hoop.band.BandReadiness
import com.nextbody.hoop.band.BandRefreshRequest
import com.nextbody.hoop.band.BandRefreshResult
import com.nextbody.hoop.band.BandSyncActivity
import com.nextbody.hoop.band.BandSyncProgress
import com.nextbody.hoop.band.BatteryLeft
import com.nextbody.hoop.band.BatteryLog
import com.nextbody.hoop.band.BatteryPlot
import com.nextbody.hoop.band.BatteryPoint
import com.nextbody.hoop.band.BoundBand
import com.nextbody.hoop.band.BatteryDrainMath
import com.nextbody.hoop.band.DeviceCompanionMath
import com.nextbody.hoop.band.DeviceSetStore
import com.nextbody.hoop.band.FirmwareOffer
import com.nextbody.hoop.band.FirmwareUpdateResult
import com.nextbody.hoop.band.HoopSlot
import com.nextbody.hoop.band.LiveReadout
import com.nextbody.hoop.band.OpticalAutoSwitch
import com.nextbody.hoop.band.OriginDataSync
import com.nextbody.hoop.band.SyncCadence
import com.nextbody.hoop.band.WearRun
import com.nextbody.hoop.band.WearTimeline
import com.nextbody.hoop.band.localizedDescription
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.training.EdgeNote
import com.nextbody.hoop.l10n.AppLanguage
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.SportModeCatalog
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.ui.DetailScroll
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.cardSkin
import com.nextbody.hoop.ui.hotZoneTap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.max
import kotlin.math.min

/**
 * 12X · 04 ACTION TILES. Lime identity slab (NEXTBODY + SYNC + 2×2), then two carbon bricks
 * (Find NEXTBODY / Alarms). No charge numeral on this card.
 * 9-0 A · the two-NEXTBODY set: both slots, the wear timeline, the link moves.
 */
@Composable
fun DeviceView() {
    val data = DataStore
    val syncActivity = BandSyncActivity.shared
    val hoops = DeviceSetStore.shared
    val scope = rememberCoroutineScope()

    var sheet by remember { mutableStateOf<SheetRoute?>(null) }
    var identity by remember { mutableStateOf<BandIdentity?>(null) }
    /** 12 edge 3 · the band clamped a write: what was asked, what it kept. */
    var clamped by remember { mutableStateOf<Triple<String, String, String>?>(null) }
    /** 12 edge 4 · a write answered DEVICE_BUSY and is queued behind the measurement. */
    var busyQueued by remember { mutableStateOf(false) }
    /** 12 edge 5 · the OTA result, three-state. */
    var ota by remember { mutableStateOf<OTAState?>(null) }
    /** What the update server said when the page asked. `offer` null with `check` settled means
     *  the band is current; a failed check is its own line, never "up to date". */
    var offer by remember { mutableStateOf<FirmwareOffer?>(null) }
    var check by remember { mutableStateOf<OTACheck>(OTACheck.Idle) }
    /** 0…1 from the SDK while the file crosses. */
    var otaProgress by remember { mutableStateOf(0.0) }
    /** How often this phone asks the band for the day. Mirrors SyncCadence. */
    var cadence by remember { mutableIntStateOf(SyncCadence.minutes) }
    /** Device SYNC is in flight. */
    var syncing by remember { mutableStateOf(false) }
    var syncMessage by remember { mutableStateOf<String?>(null) }
    /** What Automatic measurement actually read — not a guess from capability bits. */
    var autoRead by remember { mutableStateOf<AutoMonitoringRead?>(null) }
    /** After the first new-alarm read. The Alarms brick shows this number, not a guess. */
    var alarmCount by remember { mutableStateOf<Int?>(null) }
    var sportProbe by remember { mutableStateOf(false) }
    var capabilitySweep by remember { mutableStateOf(false) }
    /** The state chosen on the Health light sheet, mirrored so the row follows its writes. */
    var healthLight by remember { mutableStateOf(BandHealthLightPreference.stored()) }

    val connected = data.band.connected
    val syncInProgress = syncing || syncActivity.phase != "idle"
    val connectingForSync = syncActivity.phase == "connecting"

    /** Page reads participate in the same drain as sync. A page task resumed after a pairing
     *  sheet opens cannot enqueue a stale command against the borrowed link. */
    suspend fun <T> readDevice(work: suspend () -> T): T {
        val account = SupabaseClient.currentUserIdSnapshot() ?: throw CancellationException("signed out")
        val binding = BoundBand.identifier ?: throw CancellationException("unbound")
        return BandReadiness.read(account, binding, work)
    }

    /** Ask the update server; a failed check never promises an up-to-date band. */
    suspend fun checkForUpdate() {
        if (!DataStore.band.connected || check == OTACheck.Checking) return
        check = OTACheck.Checking
        try {
            offer = readDevice { Band.live.checkFirmwareUpdate() }
            check = OTACheck.Done
        } catch (e: Throwable) {
            offer = null
            check = OTACheck.Failed(e.localizedDescription)
        }
        Analytics.track("DEV_OTA_CHECK", mapOf("OFFER" to (offer?.version ?: "none"), "OK" to (check == OTACheck.Done)))
    }

    /** 12 rule 08 · the update runs, and the result is one of three. */
    fun runUpdate() {
        val target = offer ?: return
        scope.launch {
            ota = OTAState.Running
            otaProgress = 0.0
            Analytics.track("DEV_OTA_START", mapOf("FROM" to (identity?.firmware ?: data.band.firmware), "TO" to target.version))
            val t0 = Instant.now()
            val result = try {
                Band.live.updateFirmware(target.version) { p -> otaProgress = p }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                FirmwareUpdateResult.Failed("$e")
            }
            when (result) {
                is FirmwareUpdateResult.Completed -> {
                    ota = OTAState.Completed
                    DataStore.band = DataStore.band.copy(firmware = result.version)
                    runCatching { Band.live.readIdentity() }.getOrNull()?.let {
                        identity = it
                        data.applyBandObservation(identity = it)
                    }
                }
                is FirmwareUpdateResult.Failed -> ota = OTAState.Failed(result.reason)
                FirmwareUpdateResult.VersionUnverified -> ota = OTAState.Unverified
            }
            Analytics.track("DEV_OTA_END", mapOf("RESULT" to "$result", "MS" to Duration.between(t0, Instant.now()).toMillis().toInt()))
        }
    }

    /** The shared refresh owns readiness, admission, history and the actual completion. */
    fun pullBandNow() {
        if (syncing) return
        scope.launch {
            syncMessage = null
            syncing = true
            try {
                launch { Analytics.track("DEV_SYNC_TAP", mapOf("CONNECTED" to connected)) }
                val result = OriginDataSync.refreshNow(data, BandRefreshRequest.fullHistory)
                when (result.status) {
                    BandRefreshResult.Status.success -> identity = BandReadiness.shared.snapshot?.identity
                    BandRefreshResult.Status.consentRequired -> Router.setTakeover(Takeover.Consent)
                    BandRefreshResult.Status.signedOut -> syncMessage = L("Sign in to sync this NEXTBODY.")
                    BandRefreshResult.Status.busy -> syncMessage = L("Finish the current measurement or device operation, then sync again.")
                    BandRefreshResult.Status.disconnected, BandRefreshResult.Status.unbound -> {
                        val snap = hoops.snapshot(hoops.wearing)
                        syncMessage = if (snap?.isFlat == true || snap?.isLow == true)
                            L("Could not reach this NEXTBODY. It was nearly out of charge when last read — put it on its charger, then tap Sync.")
                        else L("Could not reach this NEXTBODY. Keep it nearby, check Bluetooth, then tap Sync to try again.")
                    }
                    BandRefreshResult.Status.partial ->
                        syncMessage = syncActivity.failureLine ?: L("Some readings could not sync. Tap Sync to try again.")
                    BandRefreshResult.Status.failed ->
                        syncMessage = syncActivity.failureLine ?: L("Sync did not complete. Tap Sync to try again.")
                    BandRefreshResult.Status.cancelled, BandRefreshResult.Status.throttled -> Unit
                }
            } finally {
                syncing = false
            }
        }
    }

    suspend fun readAutoMonitoring() {
        autoRead = try {
            readDevice { Band.live.readAutoMonitoring() }.also { rememberOpticalSwitch(it) }
        } catch (e: Throwable) {
            AutoMonitoringRead.failed(e)
        }
    }

    // .task · the device set, and the DEBUG walk-throughs that drive it.
    LaunchedEffect(Unit) {
        val debug = BuildConfig.DEBUG && Band.allowsSeed
        val stageRaw = if (debug) DebugEnv["NB_DEBUG_SYNC_STAGE"] else null
        val stage = stageRaw?.let { raw -> BandSyncProgress.Stage.entries.firstOrNull { it.raw == raw } }
        if (stage != null) {
            syncActivity.beginCounting()
            syncActivity.phase = "connecting"
            if (stage in listOf(BandSyncProgress.Stage.reading, BandSyncProgress.Stage.saving, BandSyncProgress.Stage.updating,
                    BandSyncProgress.Stage.finishing, BandSyncProgress.Stage.complete)) {
                syncActivity.phase = "syncing"
                syncActivity.reportRead(day = 3, of = 3, percent = 100)
            }
            when (stage) {
                BandSyncProgress.Stage.complete -> syncActivity.complete(success = true)
                BandSyncProgress.Stage.updating -> syncActivity.updatingResults()
                else -> syncActivity.show(stage)
            }
            return@LaunchedEffect
        }
        val progressRaw = if (BuildConfig.DEBUG) DebugEnv["NB_DEBUG_SYNC_PROGRESS"] else null
        if (progressRaw != null) {
            syncing = true
            val n = progressRaw.toIntOrNull()
            val parts = progressRaw.split(":")
            if (n != null) {
                syncActivity.debugShow(done = n, total = 9)
            } else if (parts.size == 2 && parts[0].toIntOrNull() != null && parts[1].toIntOrNull() != null) {
                // `=3:50` · half way through the fourth day.
                syncActivity.debugShow(done = parts[0].toInt(), total = 9)
                syncActivity.within(percent = parts[1].toInt())
            } else {
                // `=connecting` · no size yet.
                syncActivity.beginCounting()
                syncActivity.phase = "connecting"
            }
        }
        hoops.load()
        // `NB_DEBUG_SWITCH=B,A,B` taps the switch for you, 1.2 s apart.
        val script = if (BuildConfig.DEBUG) DebugEnv["NB_DEBUG_SWITCH"] else null
        if (script != null) {
            val slots = script.split(",").mapNotNull { HoopSlot.fromRaw(it) }
            val gap = DebugEnv["NB_DEBUG_SWITCH_MS"]?.toLongOrNull() ?: 1200L
            launch {
                for (slot in slots) {
                    delay(gap)
                    hoops.declareWearing(slot, store = data)
                }
            }
        }
        hoops.noteTransportObservation(data.band, lastSync = data.lastSync)
        hoops.noteHoldsDays(identity?.watchDataDayNumber, slot = hoops.transport)
        hoops.reconcileTransport(data)
    }
    LaunchedEffect(data.band) { hoops.noteTransportObservation(data.band, lastSync = data.lastSync) }
    LaunchedEffect(identity?.watchDataDayNumber) { hoops.noteHoldsDays(identity?.watchDataDayNumber, slot = hoops.transport) }
    LaunchedEffect(Router.deviceSheetRequest) {
        val request = Router.deviceSheetRequest ?: return@LaunchedEffect
        sheet = request
        Router.deviceSheetRequest = null
    }
    fun debugSheet() {
        if (!BuildConfig.DEBUG) return
        sheet = when (DebugEnv["NB_DEBUG_DEVICE_SHEET"]) {
            "findHoop" -> SheetRoute.FindHoop
            "bandAlarms" -> SheetRoute.BandAlarms
            "bandAutoMonitor" -> SheetRoute.BandAutoMonitor
            "healthLight" -> SheetRoute.HealthLight
            "activateSecond" -> SheetRoute.ActivateSecond
            "wearSwitch" -> SheetRoute.WearSwitch(hoops.wearing.other.raw)
            "releaseSet" -> SheetRoute.ReleaseSet
            else -> sheet
        }
    }
    LaunchedEffect(Unit) { debugSheet() }

    // .task · the page's reads.
    LaunchedEffect(Unit) {
        if (DebugEdgeFlag.on("disconnected")) DataStore.band = DataStore.band.copy(connected = false)
        if (DebugEdgeFlag.on("clamped")) clamped = Triple("Heart rate alarm", "50–140 BPM", "50–130 BPM")
        if (DebugEdgeFlag.on("busy")) busyQueued = true
        if (DebugEdgeFlag.on("otaunverified")) ota = OTAState.Unverified
        if (DebugEdgeFlag.on("otarunning")) { ota = OTAState.Running; otaProgress = 0.42 }
        if (DebugEdgeFlag.on("otacompleted")) ota = OTAState.Completed
        if (DebugEdgeFlag.on("otafailed")) ota = OTAState.Failed("The band moved out of range")
        if (DebugEdgeFlag.on("levelonly")) {
            data.applyBandObservation(battery = BandBattery(isPercent = false, percent = null, level = 3,
                chargeState = BandBattery.ChargeState.unplugged))
        }
        if (Router.path.lastOrNull() == Destination.DeviceAutoMonitor) sheet = SheetRoute.BandAutoMonitor
        Analytics.track("DEVICE_PAGE_OPEN", mapOf("CONNECTED" to connected))
        // WITH YOU reads the earliest bind or wrist tick. Refresh even when the radio is down.
        com.nextbody.hoop.services.Repository.loadLastSync(data)
        if (!DataStore.band.connected || BandLiveLifecycle.shared.hasExclusiveOperation) return@LaunchedEffect
        // Seeded BandState is already CONNECTED; the mock radio may still be idle.
        if (Band.live.state != BandConnectionState.connected) {
            if (!BandReadiness.shared.ensureReady(data, reason = "device-page")) return@LaunchedEffect
        }
        if (!DebugEdgeFlag.on("levelonly")) {
            runCatching { readDevice { Band.live.readBattery() } }.getOrNull()?.let { data.applyBandObservation(battery = it) }
        }
        identity = runCatching { readDevice { Band.live.readIdentity() } }.getOrNull()
        identity?.let { data.applyBandObservation(identity = it) }
        runCatching { readDevice { Band.live.readCapabilities() } }.getOrNull()?.let { fresh ->
            data.capabilities = fresh
            val deviceId = BandHost.repository.deviceId
            val userId = SupabaseClient.currentUserId
            if (deviceId != null && userId != null) {
                BandHost.repository.saveCapabilities(fresh, deviceId, userId, holdsDays = identity?.watchDataDayNumber)
            }
        }
        checkForUpdate()
        runCatching { readDevice { Band.live.readAlarms() } }.getOrNull()?.let { alarmCount = it.size }
        debugSheet()
        OriginDataSync.refreshNow(data)
        readAutoMonitoring()
        if (DebugEdgeFlag.on("otarunning")) { ota = OTAState.Running; otaProgress = 0.42 }
        if (DebugEdgeFlag.on("otacompleted")) ota = OTAState.Completed
        if (DebugEdgeFlag.on("otafailed")) ota = OTAState.Failed("The band moved out of range")
    }
    // .onChange(of: connected)
    var seenConnected by remember { mutableStateOf(connected) }
    LaunchedEffect(connected) {
        if (connected == seenConnected) return@LaunchedEffect
        seenConnected = connected
        if (!connected) { autoRead = null; return@LaunchedEffect }
        if (BandLiveLifecycle.shared.hasExclusiveOperation) return@LaunchedEffect
        if (!DebugEdgeFlag.on("levelonly")) {
            runCatching { readDevice { Band.live.readBattery() } }.getOrNull()?.let { data.applyBandObservation(battery = it) }
        }
        if (identity == null) {
            runCatching { readDevice { Band.live.readIdentity() } }.getOrNull()?.let {
                identity = it
                data.applyBandObservation(identity = it)
            }
        }
        if (check == OTACheck.Idle) checkForUpdate()
        runCatching { readDevice { Band.live.readAlarms() } }.getOrNull()?.let { alarmCount = it.size }
        readAutoMonitoring()
    }

    val reportedFirmware = data.band.firmware.ifEmpty { identity?.firmware ?: Fmt.dash }

    DetailScroll(
        glow = NB.lime1,
        title = L("DEVICE"),
        onBack = { Router.back() },
        trailing = {
            Row(
                Modifier
                    .height(24.dp)
                    .let { if (connected) it else it.border(1.dp, NB.hairline, CircleShape) }
                    .padding(horizontal = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(7.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(6.dp).background(if (connected) NB.lime1 else NB.white.copy(alpha = 0.3f), CircleShape))
                // The pill names the band on the link (A/B); the lime slab names the worn one.
                Text(
                    if (connected) L("CONNECTED") + (if (hoops.hasSecond) " · ${hoops.transport.raw}" else "") else L("DISCONNECTED"),
                    style = NBFont.dot(600, 10f).tracking(0.2f),
                    color = if (connected) NB.lime1 else NB.text3Prod,
                    maxLines = 1,
                )
            }
        },
    ) {
        // Cards, spaced 12pt apart; each group's title is lime and sits above its card.
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 30.dp)) {
            // 9-0 A · slots never move: A above, B below. The wearing slot is the one that
            // carries the lime marker — that is the only thing that changes places.
            for (slot in listOf(HoopSlot.a, HoopSlot.b)) {
                if (slot == HoopSlot.b && !hoops.hasSecond) {
                    EmptySlotSlab(hoops.openSlot?.raw ?: "B", enabled = BoundBand.identifier != null) {
                        sheet = SheetRoute.ActivateSecond
                    }
                    continue
                }
                Crossfade(targetState = slot == hoops.wearing, animationSpec = tween(350), label = "slot.${slot.raw}") { worn ->
                    if (worn) {
                        LimeHero(
                            slot = slot,
                            spaced = slot != HoopSlot.a,
                            stripWord = stripWord(hoops, connected, connectingForSync, syncInProgress),
                            syncing = syncing,
                            onSync = ::pullBandNow,
                        )
                    } else {
                        StandbySlab(slot, spaced = slot != HoopSlot.a) { sheet = SheetRoute.WearSwitch(slot.raw) }
                    }
                }
            }
            ActionTiles(
                alarmCount = alarmCount,
                onFind = { sheet = SheetRoute.FindHoop },
                onAlarms = { sheet = SheetRoute.BandAlarms },
            )
            syncMessage?.let {
                Text(
                    it,
                    style = NBFont.ui(400, 12f),
                    color = NB.ember1,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp).testTag("device-sync-message"),
                )
            }
            if (!connected) ReadOnlyNotice()
            if (busyQueued) BusyCard()
            clamped?.let { ClampCard(it.first, it.second, it.third) }

            GroupLabel12(L("FIRMWARE"))
            RowCard {
                FirmwareSection(
                    connected = connected,
                    identity = identity,
                    reportedFirmware = reportedFirmware,
                    offer = offer,
                    check = check,
                    ota = ota,
                    otaProgress = otaProgress,
                    onAction = {
                        if (offer != null && ota != OTAState.Unverified) runUpdate() else scope.launch { checkForUpdate() }
                    },
                )
            }

            if (BuildConfig.DEBUG) {
                DebugHeader()
                DebugCard(
                    identity = identity,
                    reportedFirmware = reportedFirmware,
                    autoDetail = autoDetail(connected, autoRead),
                    autoValue = autoValue(autoRead),
                    cadence = cadence,
                    healthLight = healthLight,
                    connected = connected,
                    onAuto = { sheet = SheetRoute.BandAutoMonitor },
                    onCadence = { sheet = SheetRoute.SyncCadence },
                    onSportProbe = { sportProbe = true },
                    onSweep = { capabilitySweep = true },
                    onHealthLight = { sheet = SheetRoute.HealthLight },
                )
            }

            GroupLabel12(L("CONNECTION"))
            RowCard {
                if (connected) {
                    DestructiveRow(L("Disconnect"), L("It keeps recording. Nothing reaches the app."), NB.text1) {
                        sheet = SheetRoute.Disconnect
                    }
                } else {
                    DestructiveRow(L("Why won't it connect?"), L("Bluetooth, distance, or a flat battery."), NB.text1) {
                        sheet = SheetRoute.FindBand
                    }
                }
                if (hoops.hasSecond) {
                    DestructiveRow(
                        L("Remove a NEXTBODY"),
                        L("Choose one to remove. Your other NEXTBODY and history stay."),
                        NB.alert2, last = true, tag = "device.removeHoop",
                    ) { sheet = SheetRoute.ReleaseSet }
                } else {
                    DestructiveRow(L("Forget this NEXTBODY"), L("Removes it from this phone. Your history stays."),
                        NB.alert2, last = true) { sheet = SheetRoute.Unbind }
                }
            }
        }
    }

    val route = sheet
    if (route != null) {
        DevicePageSheet(deviceSheetFraction(route), onDismiss = {
            sheet = null
            healthLight = BandHealthLightPreference.stored()
        }) { close ->
            when (route) {
                SheetRoute.BandAutoMonitor -> AutoMeasurementSheet(initial = autoRead) { autoRead = it }
                SheetRoute.SyncCadence -> SyncCadenceSheet(cadence) { cadence = it }
                SheetRoute.Unbind -> ReleaseSetSheet(close = close, initialSlot = hoops.wearing)
                SheetRoute.Disconnect -> DisconnectSheet(close)
                SheetRoute.FindBand -> WhyWontItConnectSheet()
                SheetRoute.FindHoop -> FindHoopSheet(close)
                SheetRoute.ActivateSecond -> ActivateSecondSheet(close)
                is SheetRoute.WearSwitch -> WearSwitchSheet(HoopSlot.fromRaw(route.slot) ?: hoops.wearing.other, close)
                SheetRoute.ReleaseSet -> ReleaseSetSheet(close = close)
                SheetRoute.BandAlarms -> AlarmsSheet { alarmCount = it }
                SheetRoute.HealthLight -> if (BuildConfig.DEBUG) HealthLightSheet() else WhyWontItConnectSheet()
                else -> WhyWontItConnectSheet()
            }
        }
    }
    if (BuildConfig.DEBUG && sportProbe) {
        DevicePageSheet(1f, onDismiss = { sportProbe = false }, large = true) { SportProbeSheet() }
    }
    if (BuildConfig.DEBUG && capabilitySweep) {
        DevicePageSheet(1f, onDismiss = { capabilitySweep = false }, large = true) { CapabilitySweepSheet() }
    }
}

private sealed class OTAState {
    data object Running : OTAState()
    data object Completed : OTAState()
    data class Failed(val why: String) : OTAState()
    data object Unverified : OTAState()
}

private sealed class OTACheck {
    data object Idle : OTACheck()
    data object Checking : OTACheck()
    data object Done : OTACheck()
    data class Failed(val why: String) : OTACheck()
}

private fun rememberOpticalSwitch(read: AutoMonitoringRead?) {
    read?.slots?.firstOrNull { it.kind == AutoMonitorSlot.Kind.bloodGlucose }?.let { OpticalAutoSwitch.record(on = it.on) }
}

/** The band tints the SYNC key by where the work is: lime on the band, blue in the cloud. */
private val BandSyncProgress.tint: Color
    get() = if (stage.destination == BandSyncProgress.Destination.cloud) NB.blue1 else NB.lime1

// MARK: dates

private val zone: ZoneId get() = ZoneId.systemDefault()

private fun localized(skeleton: String, at: Instant): String {
    val locale = AppLanguage.locale.javaLocale
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, skeleton)
    return DateTimeFormatter.ofPattern(pattern, locale).format(at.atZone(zone))
}

private fun isToday(at: Instant): Boolean = at.atZone(zone).toLocalDate() == LocalDate.now(zone)

/** `HH:mm` today, `MMM d HH:mm` otherwise. */
private fun stamp(at: Instant): String = localized(if (isToday(at)) "HH:mm" else "MMMd HH:mm", at)

/** A deadline in a sentence carries its day: `today 13:52`, `tomorrow 09:00`, `Sep 17`. */
private fun dayStamp(at: Instant): String {
    val day = at.atZone(zone).toLocalDate()
    val today = LocalDate.now(zone)
    if (day == today) return L("today") + " " + stamp(at)
    if (day == today.plusDays(1)) return L("tomorrow") + " " + stamp(at)
    return localized("MMMd", at)
}

private fun eventStamp(at: Instant?): String {
    if (at == null) return L("NEVER")
    val clock = Fmt.clock(at)
    val day = at.atZone(zone).toLocalDate()
    val today = LocalDate.now(zone)
    if (day == today) return L("TODAY %@", clock)
    if (day == today.minusDays(1)) return L("YDAY %@", clock)
    return clock
}

// MARK: 9-0 A · the set

private fun pendingDays(hoops: DeviceSetStore, slot: HoopSlot): Int {
    val snap = hoops.snapshot(slot)
    return WearTimeline.pendingDays(lastSync = snap?.lastSync, boundAt = snap?.boundAt, now = Instant.now(), holdsDays = snap?.holdsDays)
}

/** The strip and the chrome pill must never contradict each other: the pill is the link, so
 *  once it says CONNECTED the strip stops saying CONNECTING and names what the link does. */
private fun stripWord(hoops: DeviceSetStore, connected: Boolean, connectingForSync: Boolean, syncInProgress: Boolean): String {
    return when (val phase = hoops.phase) {
        // PRD W2 · the band being left finishes the command it is on.
        is DeviceSetStore.Phase.Finishing ->
            L("FINISHING") + " ${phase.slot.raw} · " + L("THEN") + " ${hoops.wearing.raw}"
        is DeviceSetStore.Phase.Switching ->
            if (phase.slot == hoops.wearing) {
                if (connected) L("WEARING · SYNCING") else L("WEARING · CONNECTING")
            } else defaultStripWord(hoops, connected, connectingForSync, syncInProgress)
        is DeviceSetStore.Phase.Activating -> L("WEARING · LINK AWAY")
        else -> defaultStripWord(hoops, connected, connectingForSync, syncInProgress)
    }
}

private fun defaultStripWord(hoops: DeviceSetStore, connected: Boolean, connectingForSync: Boolean, syncInProgress: Boolean): String {
    if (connected && hoops.transport == hoops.wearing) {
        // The bar under this strip says CONNECTING while the link is being prepared; the strip
        // must not claim reading has started.
        if (connectingForSync) return L("WEARING · CONNECTING")
        return if (syncInProgress) L("WEARING · SYNCING") else L("WEARING")
    }
    // A flat band is not a Bluetooth problem, and saying so sends people to the wrong fix.
    if (hoops.isFlat(hoops.wearing)) return L("WEARING · FLAT")
    return L("WEARING · NOT CONNECTED")
}

private fun standbyWord(hoops: DeviceSetStore, snap: DeviceSetStore.SlotSnapshot?, pending: Int): String {
    if (hoops.phase is DeviceSetStore.Phase.Activating) return L("ACTIVATING")
    if (snap?.isFlat == true) return L("FLAT")
    if (pending > 0) return L("PENDING") + " $pending " + L(if (pending == 1) "DAY" else "DAYS")
    if (snap?.isLow == true) return L("LOW")
    return when (snap?.battery?.chargeState) {
        BandBattery.ChargeState.charging -> L("CHARGING")
        BandBattery.ChargeState.full -> L("CHARGED · READY")
        else -> L("READY")
    }
}

/** The state line at the top of a slab: the slot letter, the strip word, since when. 50pt,
 *  not 34: a 28pt key inside 34 left three points of air and read as a seam. */
@Composable
private fun SlotStrip(slot: HoopSlot, onLime: Boolean, stripWord: String) {
    val hoops = DeviceSetStore.shared
    val activity = BandSyncActivity.shared
    val pending = pendingDays(hoops, slot)
    Row(
        Modifier
            .fillMaxWidth()
            .height(50.dp)
            .testTag("device.slotStrip.${slot.raw}")
            .drawBehind {
                val i = 16.dp.toPx()
                drawRect(NB.hairline, Offset(i, size.height - 1.dp.toPx()), Size(size.width - 2 * i, 1.dp.toPx()))
            }
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // The wearing NEXTBODY's key is the one lime-filled mark on the page.
        HoopKeyGlyph(slot.raw, lit = onLime)
        FitText(
            if (onLime) stripWord else standbyWord(hoops, hoops.snapshot(slot), pending),
            NBFont.dot(600, 10.5f).tracking(0.2f),
            if (onLime) NB.lime1 else if (pending > 0) NB.ember1 else NB.white.copy(alpha = 0.55f),
            Modifier.weight(1f),
            minScale = 0.8f,
        )
        Spacer(Modifier.width(0.dp)) // 10 + 0 + 10, as SwiftUI spaces around the Spacer
        val since = hoops.wearingSince
        if (onLime && activity.total > 0) {
            Text(
                "${activity.done} / ${activity.total} " + L("DAYS"),
                style = NBFont.dot(600, 10f).tracking(0.16f),
                color = NB.white.copy(alpha = 0.7f),
            )
        } else if (onLime && since != null) {
            Text(
                L("SINCE") + " " + stamp(since).uppercase(),
                style = NBFont.dot(500, 10f).tracking(0.16f),
                color = NB.white.copy(alpha = 0.55f),
            )
        }
    }
}

/** One card of the page. Slots and tiles are spaced 12pt apart; a row group that follows its
 *  own title sits flush under it. */
@Composable
private fun DeviceBlock(spaced: Boolean = true, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .padding(top = if (spaced) 12.dp else 0.dp)
            .then(modifier)
            .fillMaxWidth()
            .cardSkin()
            .clip(RoundedCornerShape(NB.R.card))
            // The last row's rule sits one point below the frame and is clipped, so the
            // card's own edge closes the list.
            .layout { measurable, constraints ->
                val p = measurable.measure(constraints)
                val cut = 1.dp.roundToPx()
                layout(p.width, max(0, p.height - cut)) { p.place(0, 0) }
            },
        content = content,
    )
}

@Composable
private fun RowCard(content: @Composable ColumnScope.() -> Unit) = DeviceBlock(spaced = false, content = content)

/** A section title: lime and large enough to find from the other end of the page. */
@Composable
private fun GroupLabel12(text: String) {
    Text(
        text,
        style = NBFont.ui(700, 16f).tracking(0.1f),
        color = NB.lime1,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp).padding(top = 30.dp, bottom = 10.dp),
    )
}

/** Name + SYNC, 12 BRIDGE TREND lead corridor, then WORN / WITH YOU / SYNCED / LAST POINT. */
@Composable
private fun LimeHero(slot: HoopSlot, spaced: Boolean, stripWord: String, syncing: Boolean, onSync: () -> Unit) {
    val data = DataStore
    val hoops = DeviceSetStore.shared
    val activity = BandSyncActivity.shared
    val now = Instant.now()
    DeviceBlock(spaced) {
        if (hoops.hasSecond) SlotStrip(slot, onLime = true, stripWord = stripWord)
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 18.dp, bottom = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FitText(
                if (hoops.hasSecond) hoops.snapshot(slot)?.name ?: data.band.name else data.band.name,
                NBFont.ui(600, 26f).tracking(-0.03f),
                NB.text1,
                Modifier.weight(1f),
                minScale = 0.7f,
            )
            DeviceSyncButton(syncing, onSync)
        }

        // The band answers one day at a time and the SDK sets that pace, so the honest thing
        // to show is how far the read has got, not a speed.
        AnimatedVisibility(activity.showsProgress, enter = fadeIn(), exit = fadeOut()) {
            val fraction by animateFloatAsState(activity.fraction.toFloat(), tween(150), label = "sync.fraction")
            Column(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 10.dp).testTag("device.syncProgress"),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                DottedProgress(fraction.toDouble(), Modifier.fillMaxWidth().height(6.dp),
                    lit = activity.workflow.tint, track = NB.white.copy(alpha = 0.14f))
                Text(activity.progressLine, style = NBFont.dot(600, 9.5f).tracking(0.18f), color = NB.white.copy(alpha = 0.62f))
            }
        }

        val left = leftParts(now)
        Column(
            Modifier
                .fillMaxWidth()
                .testTag("device.trend")
                .semantics { contentDescription = L("TREND"); stateDescription = left?.let { "${it.first} ${it.second}" } ?: "" }
                .hotZoneTap(pressedScale = 1f) { Router.open(Destination.Battery, Router.entry) }
                .padding(horizontal = 16.dp)
                .padding(top = 6.dp, bottom = 18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(L("TREND"), style = NBFont.dot(700, 11f).tracking(0.20f), color = NB.text1, modifier = Modifier.alignByBaseline())
                    Text("· " + L("7D DRAIN CURVE"), style = NBFont.ui(600, 11f).tracking(0.04f),
                        color = NB.white.copy(alpha = 0.55f), modifier = Modifier.alignByBaseline())
                }
                Spacer(Modifier.width(16.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (left != null) {
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(left.first, style = NBFont.dot(700, 15f), color = NB.lime1, modifier = Modifier.alignByBaseline())
                            Text(left.second, style = NBFont.dot(600, 10f).tracking(0.08f),
                                color = NB.white.copy(alpha = 0.55f), modifier = Modifier.alignByBaseline())
                        }
                    }
                    Chevron(color = NB.white.copy(alpha = 0.28f), modifier = Modifier.padding(start = 4.dp))
                }
            }
            val window = BatteryLog.window(endingAt = now, days = 7)
            LimeTrendLead(BatteryLog.plot(data.batteryLog, window.start, window.end), Modifier.fillMaxWidth().height(40.dp))
        }

        Hairline(modifier = Modifier.padding(horizontal = 16.dp))

        val worn: Pair<String, String?> = when (val flame = data.wearFlame) {
            is WearRun.Flame.Live -> "${flame.days}" to L("DAYS")
            else -> Fmt.dash to null
        }
        // Inclusive user days from the earliest bind or wrist tick. Firmware saveDays never land here.
        val companion: Pair<String, String?> = DeviceCompanionMath.days(data.boundAt, now)?.let { "$it" to L("DAYS") } ?: (Fmt.dash to null)
        // Same timestamp as the home panel. NEVER / JUST NOW stay a single value.
        val synced: Pair<String, String?> = data.lastSync?.let { at ->
            val mins = max(0L, Duration.between(at, now).toMinutes())
            when {
                mins < 1 -> L("JUST NOW") to null
                mins < 60 -> "$mins" to L("MIN")
                else -> "${mins / 60}" to L("HRS")
            }
        } ?: (L("NEVER") to null)
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            LimeMetric(L("WORN"), worn.first, worn.second, Modifier.weight(1f))
            VRule()
            LimeMetric(L("WITH YOU"), companion.first, companion.second, Modifier.weight(1f))
        }
        Hairline(modifier = Modifier.padding(horizontal = 16.dp))
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            LimeMetric(L("SYNCED"), synced.first, synced.second, Modifier.weight(1f))
            VRule()
            LimeMetric(L("LAST POINT"), data.vitals.at?.let { Fmt.clock(it) } ?: Fmt.dash, null, Modifier.weight(1f))
        }
    }
}

private fun leftParts(now: Instant): Pair<String, String>? {
    return when (val left = BatteryDrainMath.left(DataStore.batteryLog, now) ?: return null) {
        is BatteryLeft.Hours -> "${left.hours}" to L(if (left.hours == 1) "HR LEFT" else "HRS LEFT")
        is BatteryLeft.Days -> "${left.days}" to L(if (left.days == 1) "DAY LEFT" else "DAYS LEFT")
    }
}

/** SYNC stays actionable off-link: it first reconnects the bound NEXTBODY. */
@Composable
private fun DeviceSyncButton(syncing: Boolean, onSync: () -> Unit) {
    val activity = BandSyncActivity.shared
    val workflow = activity.workflow
    val enabled = BoundBand.identifier != null && !syncing
    Box(
        Modifier
            .defaultMinSize(minWidth = 44.dp, minHeight = 44.dp)
            .semantics {
                contentDescription = L("Sync now")
                stateDescription = if (workflow.active) L(workflow.stage.label) else ""
            }
            .hotZoneTap(enabled = enabled, pressedScale = 1f) { onSync() },
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier
                .height(36.dp)
                .background(workflow.tint, CircleShape)
                .padding(horizontal = 16.dp)
                .widthIn(min = 40.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (workflow.active) SmallSpinner(NB.carbon4, size = 14.dp)
            Text(
                if (workflow.active) L(workflow.stage.buttonLabel) else L("SYNC"),
                style = NBFont.ui(600, 11f).tracking(0.12f),
                color = NB.carbon4,
                maxLines = 1,
            )
        }
    }
}

/** The other NEXTBODY: what it last said, when it was last read. Nothing here is live — the
 *  app talks to one band at a time. The whole card is the switch. */
@Composable
private fun StandbySlab(slot: HoopSlot, spaced: Boolean, onTap: () -> Unit) {
    val hoops = DeviceSetStore.shared
    val snap = hoops.snapshot(slot)
    val deadline = WearTimeline.syncDeadline(lastSync = snap?.lastSync, boundAt = snap?.boundAt, holdsDays = snap?.holdsDays)
    val pending = pendingDays(hoops, slot)
    val atRisk = standbyAtRisk(pending, deadline)
    DeviceBlock(spaced, Modifier.testTag("device.standbySlab").hotZoneTap(pressedScale = 1f) { onTap() }) {
        SlotStrip(slot, onLime = false, stripWord = "")
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 17.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                FitText(snap?.name ?: "NEXTBODY", NBFont.ui(600, 22f).tracking(-0.03f), NB.text1, minScale = 0.7f)
                Text(
                    standbyPlan(snap, pending, deadline),
                    style = NBFont.ui(400, 12f).tracking(0.01f),
                    color = if (atRisk) NB.ember1 else NB.white.copy(alpha = 0.42f),
                    maxLines = 2,
                )
            }
            Chevron()
        }
        Hairline(modifier = Modifier.padding(horizontal = 16.dp))
        Row(Modifier.fillMaxWidth().height(56.dp)) {
            StandbyCell(L("BATTERY"), standbyBattery(snap), Modifier.weight(1f))
            VRule()
            StandbyCell(L("LAST SYNC"), snap?.lastSync?.let { stamp(it).uppercase() } ?: L("NEVER"), Modifier.weight(1f))
            VRule()
            StandbyCell(L("SYNC BEFORE"), deadline?.let { stamp(it).uppercase() } ?: Fmt.dash, Modifier.weight(1f))
        }
    }
}

/** One sentence under the name: what happens to this band's days, and by when. A band that
 *  has gone flat records nothing, so "wear it" is not the answer. */
private fun standbyPlan(snap: DeviceSetStore.SlotSnapshot?, pending: Int, deadline: Instant?): String {
    if (snap?.isFlat == true) return L("It is out of charge and recording nothing. Charge it.")
    if (standbyAtRisk(pending, deadline) && deadline != null) {
        return L("Wear it before") + " " + dayStamp(deadline) + " " + L("or its oldest days are gone.")
    }
    if (pending > 0) return L("What it recorded syncs when you put it on.")
    if (snap?.isLow == true) return L("Nearly out of charge. Top it up before you swap.")
    return L("Waiting on its charger. Tap to wear it instead.")
}

/** The firmware only keeps so many days. Inside the last day of that window the oldest
 *  unsynced day is about to be overwritten. */
private fun standbyAtRisk(pending: Int, deadline: Instant?): Boolean {
    if (pending <= 0 || deadline == null) return false
    return Instant.now() > deadline.minusSeconds(86_400)
}

private fun standbyBattery(snap: DeviceSetStore.SlotSnapshot?): String {
    val battery = snap?.battery ?: return Fmt.dash
    val p = battery.percent
    if (p != null && battery.isPercent) return "$p%"
    battery.level?.let { return L("LEVEL") + " $it" }
    return Fmt.dash
}

@Composable
private fun StandbyCell(label: String, value: String, modifier: Modifier) {
    Column(
        modifier.fillMaxHeight().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
    ) {
        Text(label, style = NBFont.dot(500, 9f).tracking(0.2f), color = NB.white.copy(alpha = 0.34f), maxLines = 1)
        FitText(value, NBFont.dot(600, 12f).tracking(0.06f), NB.text1, minScale = 0.7f)
    }
}

/** The only entry for the second NEXTBODY (§03.3 step 5): a dashed empty slot on DEVICE. */
@Composable
private fun EmptySlotSlab(letter: String, enabled: Boolean, onTap: () -> Unit) {
    Row(
        Modifier
            .padding(top = 12.dp)
            .fillMaxWidth()
            .heightIn(min = 72.dp)
            .testTag("device.addSecond")
            // A dashed outline says the slot is empty.
            .drawBehind {
                val k = 1.dp.toPx()
                val r = NB.R.card.toPx()
                drawRoundRect(
                    NB.white.copy(alpha = 0.22f),
                    topLeft = Offset(k / 2, k / 2),
                    size = Size(size.width - k, size.height - k),
                    cornerRadius = CornerRadius(r, r),
                    style = Stroke(k, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4 * k, 4 * k))),
                )
            }
            .alpha(if (enabled) 1f else 0.5f)
            .hotZoneTap(enabled = enabled, pressedScale = 1f) { onTap() }
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        HoopKeyGlyph(letter)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(L("Add your second NEXTBODY"), style = NBFont.ui(600, 16f).tracking(-0.02f), color = NB.text1)
            Text(L("KEEP WEARING. CHARGE THE OTHER."), style = NBFont.dot(500, 10f).tracking(0.16f), color = NB.white.copy(alpha = 0.4f))
        }
        Spacer(Modifier.width(0.dp))
        Chevron()
    }
}

/** Two cells split by one vertical rule: lime eyebrow, 18pt title, the same 14pt gap. The
 *  alarm count rides the eyebrow (`CLOCK · 2`) so both cells keep one height. */
@Composable
private fun ActionTiles(alarmCount: Int?, onFind: () -> Unit, onAlarms: () -> Unit) {
    DeviceBlock {
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            ActionTile(L("PING"), L("Find NEXTBODY"), "device.findHoop", Modifier.weight(1f), onFind)
            VRule()
            ActionTile(alarmCount?.let { L("CLOCK") + " · $it" } ?: L("CLOCK"), L("Alarms"), "device.alarms", Modifier.weight(1f), onAlarms)
        }
    }
}

@Composable
private fun ActionTile(eyebrow: String, title: String, tag: String, modifier: Modifier, onTap: () -> Unit) {
    Column(
        modifier
            .fillMaxHeight()
            .heightIn(min = 88.dp)
            .testTag(tag)
            .hotZoneTap(pressedScale = 1f) { onTap() }
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(eyebrow, style = NBFont.dot(600, 10f).tracking(0.16f), color = NB.lime1)
        Text(title, style = NBFont.ui(600, 18f).tracking(-0.02f), color = NB.text1)
    }
}

@Composable
private fun VRule() {
    Box(Modifier.width(1.dp).fillMaxHeight().background(NB.hairline))
}

/** 12 BRIDGE lead corridor sparkline on the slab: the 7-day drain points across the width,
 *  ending on a live terminal dot. */
@Composable
private fun LimeTrendLead(plot: BatteryPlot, modifier: Modifier) {
    Canvas(modifier.clearAndSetSemantics { }) {
        val k = 1.dp.toPx()
        val spanY = max(0.001, plot.yMax)
        val spanX = max(0.001, Duration.between(plot.start, plot.end).toMillis() / 1000.0)
        val inset = 1 * k
        fun y(v: Double): Float = (size.height - 2 * k - min(plot.yMax, max(0.0, v)) / spanY * (size.height - 4 * k)).toFloat()
        fun x(at: Instant): Float = (inset + Duration.between(plot.start, at).toMillis() / 1000.0 / spanX * (size.width - inset * 2)).toFloat()
        fun point(p: BatteryPoint) = Offset(x(p.at), y(p.value))
        drawRuns(plot, ::point, heardWidth = 1.5f * k, guessAlpha = 0.4f, round = false)
        val end = plot.runs.lastOrNull()?.lastOrNull()
        if (end != null) {
            drawCircle(NB.lime1, 2 * k, point(end))
        } else if (plot.runs.all { it.isEmpty() }) {
            drawLine(NB.white.copy(alpha = 0.2f), Offset(0f, size.height / 2), Offset(size.width, size.height / 2), 1.2f * k,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(2 * k, 3 * k)))
        }
    }
}

/** One cell on the slab, number + unit split the way the board does. */
@Composable
private fun LimeMetric(label: String, value: String, unit: String?, modifier: Modifier) {
    Column(modifier.padding(horizontal = 16.dp, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(label, style = NBFont.ui(500, 10f).tracking(0.16f), color = NB.white.copy(alpha = 0.55f))
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(value, style = NBFont.dot(700, 20f), color = NB.lime1, modifier = Modifier.alignByBaseline())
            if (unit != null) {
                Text(unit, style = NBFont.dot(500, 10f), color = NB.white.copy(alpha = 0.55f), modifier = Modifier.alignByBaseline())
            }
        }
    }
}

// MARK: firmware

/** Version, offer, CHECK / UPDATE, then the identity rows the board lists. DEVICE NO. is not
 *  a firmware fact — it stays in DEBUG. */
@Composable
private fun FirmwareSection(
    connected: Boolean,
    identity: BandIdentity?,
    reportedFirmware: String,
    offer: FirmwareOffer?,
    check: OTACheck,
    ota: OTAState?,
    otaProgress: Double,
    onAction: () -> Unit,
) {
    val data = DataStore
    val unverified = ota == OTAState.Unverified
    /** An offer is only installable while the last attempt is not sitting unverified — pushing
     *  the same file again over a version we could not read is how a band bricks. */
    val installable = offer != null && !unverified
    val line = when (ota) {
        OTAState.Running -> L("Installing · keep the band close")
        OTAState.Completed -> L("Installed · %@ is on the band", reportedFirmware)
        is OTAState.Failed -> L(ota.why)
        OTAState.Unverified -> L("The update finished but we could not read the new version back. Check the band before trying again.")
        null -> when {
            !connected -> if (offer == null) L("Reconnect to check for updates") else L("Reconnect to install this update")
            check is OTACheck.Failed -> L("Could not reach the update server · %@", L(check.why))
            check == OTACheck.Done -> offer?.let { it.notes.firstOrNull() ?: L("Update available") } ?: L("Up to date")
            else -> L("Checking for updates…")
        }
    }
    val button = when {
        ota == OTAState.Running -> if (otaProgress > 0) L("UPDATING %d %%", (otaProgress * 100).toInt()) else L("UPDATING…")
        ota == OTAState.Completed -> L("DONE")
        installable -> L("UPDATE")
        else -> L("CHECK")
    }
    Row(
        Modifier.fillMaxWidth().padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                if (unverified) L("VERSION UNCONFIRMED") else L("VERSION"),
                style = NBFont.ui(500, 11f).tracking(0.2f),
                color = if (unverified) NB.ember1 else NB.text3Prod,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(reportedFirmware, style = NBFont.dot(700, 22f).tracking(0.04f), color = NB.text1)
                if (offer != null && ota != OTAState.Completed) {
                    Text(if (unverified) L("?") else L("→"), style = NBFont.dot(700, 13f), color = if (unverified) NB.ember1 else NB.lime1)
                    Text(offer.version, style = NBFont.dot(700, 22f).tracking(0.04f), color = if (unverified) NB.macroValue else NB.lime1)
                }
            }
            Text(
                line,
                style = NBFont.ui(400, 12f).tracking(0.02f).lineGap(3f),
                color = if (ota == OTAState.Completed) NB.lime1 else NB.text3Prod,
            )
        }
        Spacer(Modifier.width(0.dp))
        if (offer != null || (connected && check != OTACheck.Checking && ota != OTAState.Completed)) {
            val lit = connected && installable
            val enabled = connected && ota != OTAState.Running && ota != OTAState.Completed
            Box(
                Modifier
                    .height(36.dp)
                    .background(if (lit) NB.lime1 else Color.Transparent, CircleShape)
                    .let { if (lit) it else it.border(1.dp, NB.hairline, CircleShape) }
                    .alpha(if (enabled) 1f else 0.5f)
                    .hotZoneTap(enabled = enabled, pressedScale = 1f) { onAction() }
                    .padding(horizontal = 18.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(button, style = NBFont.ui(600, 11f).tracking(0.12f), color = if (lit) NB.carbon else NB.text2, maxLines = 1)
            }
        }
    }
    if (ota == OTAState.Running) {
        val p by animateFloatAsState(otaProgress.toFloat().coerceIn(0f, 1f), tween(250), label = "ota")
        Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 12.dp).height(3.dp).background(NB.barTrack, CircleShape)) {
            Box(Modifier.fillMaxWidth(p).fillMaxHeight().background(NB.lime1, CircleShape))
        }
    }
    Hairline(modifier = Modifier.padding(horizontal = 16.dp))
    IdentityRow("MODEL", identityValue(identity?.model))
    IdentityRow("HARDWARE", identityValue(identity?.hardware))
    IdentityRow("BLUETOOTH", bluetoothValue(identity))
    IdentityRow("LAST PLUG", eventStamp(BatteryLog.lastPlug(data.batteryLog)))
    IdentityRow("LAST LINK", eventStamp(BatteryLog.lastLink(data.batteryLog)))
    IdentityRow("SPORT", identityValue(identity?.sportMode), last = true)
}

private fun identityValue(raw: String?): String = if (raw.isNullOrEmpty()) Fmt.dash else raw

/** Six hex pairs are a MAC and use colons. Anything else stays as the identifier the phone
 *  actually has — it is not relabelled as a MAC. */
private fun bluetoothValue(identity: BandIdentity?): String {
    val raw = identity?.bleIdentifier ?: DataStore.band.mac
    if (raw.isEmpty()) return Fmt.dash
    val parts = raw.split("-")
    if (parts.size == 6) return parts.joinToString(":")
    return raw
}

/** Only what this NEXTBODY actually reported for automatic measurement. */
private fun autoDetail(connected: Boolean, read: AutoMonitoringRead?): String {
    if (!connected) return L("CONNECT TO READ")
    if (read == null) return L("ASKING THIS NEXTBODY")
    val slots = read.slots
    if (slots.isNotEmpty()) return slots.joinToString(" · ") { L(autoShort(it.kind)) }
    return when (read) {
        is AutoMonitoringRead.Interval -> L("NOT REPORTED")
        is AutoMonitoringRead.Switches -> L("INTERVAL IS FIRMWARE-OWNED")
        is AutoMonitoringRead.Failed -> L("COULD NOT READ")
    }
}

private fun autoValue(read: AutoMonitoringRead?): String {
    val n = read?.slots?.size ?: return "—"
    return if (n == 0) "—" else "$n"
}

private fun autoShort(kind: AutoMonitorSlot.Kind): String = when (kind) {
    AutoMonitorSlot.Kind.heartRate -> "HR"
    AutoMonitorSlot.Kind.bloodPressure -> "BP"
    AutoMonitorSlot.Kind.bloodGlucose -> "RESP"
    AutoMonitorSlot.Kind.stress -> "STRESS"
    AutoMonitorSlot.Kind.bloodOxygen -> "SPO2"
    AutoMonitorSlot.Kind.temperature -> "TEMP"
    AutoMonitorSlot.Kind.lorentz -> "LORENTZ"
    AutoMonitorSlot.Kind.hrv -> "HRV"
    AutoMonitorSlot.Kind.scientificSleep -> "SLEEP"
    AutoMonitorSlot.Kind.bloodComponents -> "BLOOD"
}

// MARK: DEBUG

@Composable
private fun DebugHeader() {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 4.dp).padding(top = 30.dp, bottom = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(L("DEBUG"), style = NBFont.ui(700, 16f).tracking(0.1f), color = NB.ember1)
        Text(L("BUILD ONLY"), style = NBFont.dot(600, 9f).tracking(0.14f), color = NB.ember1)
    }
}

/**
 * 12S · the light on the side of the band (ADR 0023): this firmware answers
 * `healthLightType=0`, so the row stays as a probe, inside DEBUG. The value is the phone's
 * saved choice; "band default" means nothing has been chosen and nothing is sent.
 */
@Composable
private fun DebugCard(
    identity: BandIdentity?,
    reportedFirmware: String,
    autoDetail: String,
    autoValue: String,
    cadence: Int,
    healthLight: BandHealthLightState?,
    connected: Boolean,
    onAuto: () -> Unit,
    onCadence: () -> Unit,
    onSportProbe: () -> Unit,
    onSweep: () -> Unit,
    onHealthLight: () -> Unit,
) {
    val shape = RoundedCornerShape(NB.R.card)
    Column(
        Modifier
            .fillMaxWidth()
            .background(NB.carbon4, shape)
            .border(1.dp, NB.ember1.copy(alpha = 0.33f), shape)
            .clip(shape),
    ) {
        IdentityRow("MODEL", identityValue(identity?.model))
        IdentityRow("HARDWARE", identityValue(identity?.hardware))
        IdentityRow("SOFTWARE", reportedFirmware)
        IdentityRow("DEVICE NO.", identityValue(identity?.deviceNumber))
        IdentityRow("SPORT MODE", identityValue(identity?.sportMode))
        IdentityRow("BLUETOOTH", bluetoothValue(identity))
        NavRow(L("Automatic measurement"), autoDetail, autoValue, valueTint = NB.ember1, enabled = connected, action = onAuto)
        NavRow(L("Read the band"), L("HOW OFTEN THE DAY IS PULLED"), SyncCadence.label(cadence), valueTint = NB.ember1, action = onCadence)
        NavRow(L("Sport mode probe"), L("TAP A TYPE · THE BAND OPENS IT, THEN CLOSES IT"), identity?.sportMode ?: "—",
            valueTint = NB.ember1, action = onSportProbe)
        NavRow(L("Capability sweep"), L("READ WHAT THIS FIRMWARE ANSWERS"), "", valueTint = NB.ember1, action = onSweep)
        NavRow(
            L("Health light"),
            L("THE LIGHT ON THE SIDE · WRITTEN BACK ON EVERY CONNECT"),
            healthLight?.let { L(it.title) } ?: L("BAND DEFAULT"),
            valueTint = NB.ember1,
            enabled = connected,
            last = true,
            action = onHealthLight,
        )
    }
}

@Composable
private fun NavRow(
    title: String,
    detail: String,
    value: String,
    valueTint: Color = NB.text3Prod,
    enabled: Boolean = true,
    last: Boolean = false,
    action: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 62.dp)
            .rowRule(last)
            .alpha(if (enabled) 1f else 0.55f)
            .hotZoneTap(enabled = enabled, pressedScale = 1f) { action() }
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = NBFont.ui(500, 15f), color = if (enabled) NB.text1 else NB.text2)
            Text(detail, style = NBFont.dot(500, 10f).tracking(0.14f), color = NB.white.copy(alpha = 0.5f))
        }
        Spacer(Modifier.width(0.dp))
        Text(
            value,
            style = NBFont.dot(600, 11f).tracking(0.08f),
            color = valueTint,
            textAlign = TextAlign.End,
            modifier = Modifier.widthIn(min = 44.dp),
        )
        Chevron()
    }
}

@Composable
private fun IdentityRow(name: String, value: String, last: Boolean = false) {
    Row(
        Modifier.fillMaxWidth().height(48.dp).rowRule(last).padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(L(name), style = NBFont.ui(500, 13f).tracking(0.06f), color = NB.text1, maxLines = 1)
        Spacer(Modifier.weight(1f))
        FitText(value, NBFont.dot(500, 11f).tracking(0.08f), NB.white.copy(alpha = 0.55f), minScale = 0.7f)
    }
}

@Composable
private fun DestructiveRow(
    title: String,
    detail: String,
    tint: Color,
    last: Boolean = false,
    tag: String? = null,
    action: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(66.dp)
            .rowRule(last)
            .let { if (tag != null) it.testTag(tag) else it }
            .hotZoneTap(pressedScale = 1f) { action() }
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = NBFont.ui(500, 15f), color = tint)
            Text(detail, style = NBFont.ui(400, 11.5f).tracking(0.02f), color = NB.white.copy(alpha = 0.5f))
        }
        Spacer(Modifier.width(16.dp))
        Chevron()
    }
}

// MARK: edge cards

/** 12 edge 3 · WRITE CLAMPED · RENDER THE READBACK. */
@Composable
private fun ClampCard(name: String, asked: String, got: String) {
    Column(
        Modifier.padding(top = 12.dp).fillMaxWidth().cardSkin().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(name, style = NBFont.ui(500, 14f), color = NB.text1)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(got, style = NBFont.dot(700, 22f).tracking(0.02f), color = NB.text1, modifier = Modifier.alignByBaseline())
            Text(L("YOU ASKED FOR %@", asked), style = NBFont.dot(500, 11f).tracking(0.06f),
                color = NB.ember1.copy(alpha = 0.85f), modifier = Modifier.alignByBaseline())
        }
        Text(L("THE BAND SET WHAT IT COULD. THIS IS ITS ANSWER, NOT OURS."), style = NBFont.ui(300, 11f).tracking(0.04f),
            color = NB.text3Prod)
    }
}

/** 12 edge 4 · DEVICE BUSY · QUEUE, DON'T FAIL. */
@Composable
private fun BusyCard() {
    Column(
        Modifier.padding(top = 12.dp).fillMaxWidth().cardSkin().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(L("DEVICE BUSY"), style = NBFont.dot(700, 11f).tracking(0.14f), color = NB.ember1)
        Text(
            L("A measurement is running. Your change is queued and will go through when it finishes."),
            style = NBFont.ui(300, 12.5f).tracking(0.02f).lineGap(5f),
            color = NB.white.copy(alpha = 0.70f),
        )
    }
}

/** One sentence with a padlock covers the whole read-only stretch. Switches are not hidden and
 *  not greyed into illegibility — they simply do not move. */
@Composable
private fun ReadOnlyNotice() {
    Row(
        Modifier.fillMaxWidth().padding(top = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LockGlyph()
        Text(L("Settings below are read-only until you reconnect"), style = NBFont.ui(400, 12f).tracking(0.02f), color = NB.text3Prod,
            modifier = Modifier.weight(1f))
        Spacer(Modifier.width(0.dp))
    }
}

@Composable
private fun LockGlyph() {
    Canvas(Modifier.size(14.dp)) {
        val s = size.width / 14
        drawRoundRect(NB.text3Prod, Offset(3 * s, 6 * s), Size(8 * s, 7 * s), CornerRadius(1.6f * s, 1.6f * s), style = Stroke(1.2f * s))
        drawArc(NB.text3Prod, 180f, 180f, false, Offset(7 * s - 2.6f * s, 6 * s - 2.6f * s), Size(5.2f * s, 5.2f * s), style = Stroke(1.2f * s))
    }
}

// MARK: 12S · the device sheets

/**
 * One row per thing the band can measure — only what this NEXTBODY reports is listed.
 * Interval firmware answers `readAutoMonitSwitchInfo`. Older firmware answers the
 * base-function switches, with no interval to set.
 */
@Composable
fun AutoMeasurementSheet(initial: AutoMonitoringRead?, onRead: (AutoMonitoringRead) -> Unit) {
    var read by remember { mutableStateOf(initial) }
    var loading by remember { mutableStateOf(initial == null) }
    var writeError by remember { mutableStateOf<String?>(null) }
    var writingKinds by remember { mutableStateOf<Set<AutoMonitorSlot.Kind>>(emptySet()) }
    val scope = rememberCoroutineScope()

    val slots = read?.slots ?: emptyList()
    val firmwareOwnsInterval = read is AutoMonitoringRead.Switches
    val hasScientificSleep = slots.any { it.kind == AutoMonitorSlot.Kind.scientificSleep }

    suspend fun refresh() {
        try {
            val result = Band.live.readAutoMonitoring()
            read = result
            rememberOpticalSwitch(result)
            onRead(result)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            val result = AutoMonitoringRead.failed(e)
            read = result
            onRead(result)
        } finally {
            loading = false
        }
    }

    fun apply(slot: AutoMonitorSlot) {
        if (slot.kind == AutoMonitorSlot.Kind.bloodGlucose) OpticalAutoSwitch.record(on = slot.on)
        read = when (val r = read) {
            is AutoMonitoringRead.Interval -> AutoMonitoringRead.Interval(r.rows.map { if (it.id == slot.id) slot else it })
            is AutoMonitoringRead.Switches -> AutoMonitoringRead.Switches(r.rows.map { if (it.id == slot.id) slot else it })
            else -> r
        }
    }

    fun update(original: AutoMonitorSlot, on: Boolean? = null, interval: Int? = null) {
        if (original.kind in writingKinds) return
        var updated = original
        if (on != null) updated = updated.copy(on = on)
        if (interval != null) {
            if (interval !in updated.allowedIntervals) return
            updated = updated.copy(intervalMinutes = interval, on = true)
        }
        apply(updated)
        writeError = null
        writingKinds = writingKinds + updated.kind
        scope.launch {
            try {
                Band.live.writeAutoMonitoring(updated)
                refresh()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                apply(original)
                writeError = e.localizedDescription
            } finally {
                writingKinds = writingKinds - updated.kind
            }
        }
    }

    LaunchedEffect(Unit) { refresh() }

    Column(
        Modifier
            .fillMaxSize()
            .background(NB.carbon2)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 24.dp, bottom = 28.dp),
    ) {
        Text(L("Automatic measurement"), style = NBFont.ui(500, 20f).tracking(0.01f), color = NB.text1)
        Text(
            if (firmwareOwnsInterval) {
                if (hasScientificSleep) L("This NEXTBODY lets you turn each sensor or sleep mode on or off. How often it measures is decided by the firmware.")
                else L("This NEXTBODY only lets you turn each sensor on or off. How often it measures is decided by the firmware.")
            } else {
                if (hasScientificSleep) L("Choose each sensor's own interval. Scientific sleep uses automatic PPG.")
                else L("Choose each sensor's own interval. Shorter intervals use more battery.")
            },
            style = NBFont.ui(300, 12.5f).tracking(0.02f),
            color = NB.white.copy(alpha = 0.38f),
            modifier = Modifier.padding(top = 6.dp),
        )
        if (loading && slots.isEmpty()) {
            Text(L("ASKING THIS NEXTBODY…"), style = NBFont.dot(600, 10f).tracking(0.16f), color = NB.white.copy(alpha = 0.38f),
                modifier = Modifier.padding(top = 24.dp))
        }
        if (slots.isNotEmpty()) {
            Column(Modifier.padding(top = 16.dp).fillMaxWidth().sheetLines()) {
                slots.forEachIndexed { index, slot ->
                    val isOn = slots.firstOrNull { it.id == slot.id }?.on ?: slot.on
                    MeasureToggle(
                        title = L(autoTitle(slot.kind)),
                        detail = autoSlotDetail(slot, firmwareOwnsInterval),
                        // 12S decision 2 · a chip the firmware will not let you change is not rendered.
                        chips = if (slot.supportsRange && slot.slotModifiable)
                            listOf(String.format(java.util.Locale.ROOT, "%02d:00 – %02d:00", slot.startHour, slot.endHour)) else emptyList(),
                        selectedInterval = if (slot.intervalModifiable) slot.intervalMinutes else null,
                        intervalOptions = if (slot.intervalModifiable) slot.allowedIntervals else emptyList(),
                        onIntervalSelected = { update(slot, interval = it) },
                        isWriting = slot.kind in writingKinds,
                        detailIsLime = when {
                            slot.kind == AutoMonitorSlot.Kind.scientificSleep -> slot.on
                            firmwareOwnsInterval -> slot.on
                            else -> slot.on && slot.supportsRange && slot.slotModifiable && slot.intervalModifiable
                        },
                        isOn = isOn,
                        onToggle = { update(slot, on = it) },
                        last = index == slots.size - 1,
                    )
                }
            }
            Text(
                when {
                    hasScientificSleep -> L("Scientific sleep applies to future nights and may use more battery.")
                    firmwareOwnsInterval -> L("The interval itself is not a setting on this firmware.")
                    else -> L("Only what this NEXTBODY can measure is listed")
                },
                style = NBFont.ui(300, 11.5f).tracking(0.02f),
                color = NB.white.copy(alpha = 0.30f),
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
            )
            writeError?.let {
                Text(it, style = NBFont.dot(600, 10f).tracking(0.12f), color = NB.ember1, textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 10.dp))
            }
        } else if (!loading) {
            val r = read
            Box(Modifier.fillMaxWidth().padding(top = 24.dp), contentAlignment = Alignment.Center) {
                when (r) {
                    is AutoMonitoringRead.Failed -> EdgeNote(line = L(r.headline), text = L(r.sentence))
                    is AutoMonitoringRead.Switches -> EdgeNote(
                        line = L("THIS FIRMWARE HAS NO AUTOMATIC-MEASUREMENT SWITCHES"),
                        text = L("How often it measures is decided on the band. This app cannot change that interval."))
                    else -> EdgeNote(
                        line = L("THIS NEXTBODY DID NOT REPORT ITS AUTOMATIC MEASUREMENTS"),
                        text = L("The interval API is on this firmware, but the band sent no rows. Try again while it is on your wrist."))
                }
            }
        }
    }
}

private fun autoTitle(kind: AutoMonitorSlot.Kind): String = when (kind) {
    AutoMonitorSlot.Kind.heartRate -> "Heart rate"
    AutoMonitorSlot.Kind.bloodPressure -> "Blood pressure"
    AutoMonitorSlot.Kind.bloodGlucose -> "Meal response"
    AutoMonitorSlot.Kind.stress -> "Stress"
    AutoMonitorSlot.Kind.bloodOxygen -> "Blood oxygen"
    AutoMonitorSlot.Kind.temperature -> "Skin temperature"
    AutoMonitorSlot.Kind.lorentz -> "Lorentz"
    AutoMonitorSlot.Kind.hrv -> "HRV"
    AutoMonitorSlot.Kind.scientificSleep -> "Scientific sleep"
    AutoMonitorSlot.Kind.bloodComponents -> "Blood components"
}

private fun autoSlotDetail(slot: AutoMonitorSlot, firmwareOwnsInterval: Boolean): String {
    if (slot.kind == AutoMonitorSlot.Kind.scientificSleep) {
        return if (slot.on) L("REM STAGING · AUTOMATIC PPG ON") else L("DEEP AND LIGHT ONLY")
    }
    if (!slot.on) return L("OFF")
    if (firmwareOwnsInterval) return L("FIRMWARE INTERVAL")
    if (slot.supportsRange) {
        if (slot.slotModifiable && slot.intervalModifiable) return L("WINDOW AND INTERVAL, BOTH YOURS")
        return L("%02d:00 – %02d:00 · %@", slot.startHour, slot.endHour, intervalLabel(slot.intervalMinutes))
    }
    return intervalLabel(slot.intervalMinutes)
}

private fun intervalLabel(minutes: Int): String = if (minutes == 0) L("CONTINUOUS") else L("EVERY %d MIN", minutes)

@Composable
private fun MeasureToggle(
    title: String,
    detail: String,
    chips: List<String>,
    selectedInterval: Int?,
    intervalOptions: List<Int>,
    onIntervalSelected: (Int) -> Unit,
    isWriting: Boolean,
    detailIsLime: Boolean,
    isOn: Boolean,
    onToggle: (Boolean) -> Unit,
    last: Boolean,
) {
    Column(
        Modifier.fillMaxWidth().rowRule(last).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(title, style = NBFont.ui(500, 14f).tracking(0.02f), color = NB.text1)
                Text(
                    detail,
                    style = NBFont.dot(600, 10.5f).tracking(0.16f),
                    color = if (detailIsLime) NB.lime1 else if (isOn) NB.text3Prod else NB.white.copy(alpha = 0.28f),
                )
            }
            Spacer(Modifier.width(16.dp))
            IosToggle(isOn, enabled = !isWriting, onChange = onToggle)
        }
        if (chips.isNotEmpty() && isOn) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (c in chips) Chip(c, Modifier.weight(1f))
                if (selectedInterval != null && intervalOptions.isNotEmpty()) {
                    IntervalMenu(selectedInterval, intervalOptions, isWriting, onIntervalSelected, Modifier.weight(1f))
                }
            }
        } else if (selectedInterval != null && isOn && intervalOptions.isNotEmpty()) {
            IntervalMenu(selectedInterval, intervalOptions, isWriting, onIntervalSelected, Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun Chip(text: String, modifier: Modifier = Modifier) {
    Box(
        modifier
            .height(32.dp)
            .background(Color(0xFF17171B), CircleShape)
            .border(1.dp, NB.lime1.copy(alpha = 0.24f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = NBFont.dot(600, 11f).tracking(0.14f), color = NB.lime1, maxLines = 1)
    }
}

@Composable
private fun IntervalMenu(selected: Int, options: List<Int>, writing: Boolean, onPick: (Int) -> Unit, modifier: Modifier) {
    var open by remember { mutableStateOf(false) }
    fun label(minutes: Int) = if (minutes == 0) "Continuous" else "$minutes min"
    Box(modifier) {
        Chip(label(selected), Modifier.fillMaxWidth().hotZoneTap(enabled = !writing, pressedScale = 1f) { open = true })
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = NB.carbon4) {
            for (m in options) {
                DropdownMenuItem(
                    text = { Text(label(m), style = NBFont.ui(400, 15f), color = if (m == selected) NB.lime1 else NB.text1) },
                    onClick = { open = false; onPick(m) },
                )
            }
        }
    }
}

/** The system switch, tinted lime (`Toggle(...).tint(NB.lime1)`): 51 × 31. */
@Composable
private fun IosToggle(isOn: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    val t by animateFloatAsState(if (isOn) 1f else 0f, com.nextbody.hoop.ui.swiftSpring(0.3f, 0.8f), label = "toggle")
    Box(
        Modifier
            .size(51.dp, 31.dp)
            .alpha(if (enabled) 1f else 0.5f)
            .background(androidx.compose.ui.graphics.lerp(Color(0x29787880), NB.lime1, t), CircleShape)
            .hotZoneTap(enabled = enabled, pressedOpacity = 1f, pressedScale = 1f) { onChange(!isOn) },
    ) {
        Box(Modifier.offset(x = (2 + 20 * t).dp, y = 2.dp).size(27.dp).background(Color.White, CircleShape))
    }
}

/**
 * 12 · how often the phone reads the band. One row per cadence, the current one marked. The
 * choice is written the moment it is tapped — there is nothing to confirm, and the home
 * screen's loop picks it up within thirty seconds.
 */
@Composable
fun SyncCadenceSheet(minutes: Int, onChange: (Int) -> Unit) {
    val scope = rememberCoroutineScope()
    Column(
        Modifier.fillMaxSize().background(NB.carbon2).padding(horizontal = 16.dp).padding(top = 24.dp),
    ) {
        Text(L("Read the band"), style = NBFont.ui(500, 20f).tracking(0.01f), color = NB.text1)
        Text(
            L("This controls how often your phone collects stored readings. Sensor intervals are set under Automatic measurement."),
            style = NBFont.ui(300, 12.5f).tracking(0.02f),
            color = NB.white.copy(alpha = 0.38f),
            modifier = Modifier.padding(top = 6.dp),
        )
        Column(Modifier.padding(top = 16.dp).fillMaxWidth().sheetLines()) {
            SyncCadence.options.forEachIndexed { index, option ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(54.dp)
                        .rowRule(index == SyncCadence.options.size - 1)
                        .hotZoneTap(pressedScale = 1f) {
                            onChange(option)
                            SyncCadence.minutes = option
                            scope.launch { Analytics.track("SYNC_CADENCE_SET", mapOf("MINUTES" to option)) }
                        }
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(SyncCadence.label(option), style = NBFont.dot(500, 12f).tracking(0.14f),
                        color = if (option == minutes) NB.lime1 else NB.text1, modifier = Modifier.weight(1f))
                    Spacer(Modifier.width(20.dp))
                    if (option == minutes) Box(Modifier.size(8.dp).background(NB.lime1, CircleShape))
                }
            }
        }
        Text(
            L("Some stored history, including temperature, still arrives in five-minute points. Faster reads do not create extra samples."),
            style = NBFont.ui(300, 11.5f).tracking(0.02f),
            color = NB.white.copy(alpha = 0.30f),
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
        )
    }
}

/** Reversible, so the safe button is not red. */
@Composable
fun DisconnectSheet(close: () -> Unit) {
    val scope = rememberCoroutineScope()
    Column(
        Modifier.fillMaxSize().background(NB.carbon2).padding(horizontal = 16.dp).padding(top = 26.dp, bottom = 26.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(L("Disconnect the NEXTBODY?"), style = NBFont.ui(500, 22f).tracking(0.01f), color = NB.text1)
        Text(
            L("It keeps recording on your wrist. Nothing new reaches the app until you connect again."),
            style = NBFont.brand(400, 14f).lineGap(7f),
            color = NB.text2,
        )
        Spacer(Modifier.weight(1f))
        LimePillButton(L("Stay connected")) { close() }
        Box(
            Modifier
                .fillMaxWidth()
                .height(52.dp)
                .border(1.dp, NB.hairline, CircleShape)
                .hotZoneTap(pressedScale = 1f) {
                    scope.launch {
                        Band.live.disconnect()
                        DataStore.band = DataStore.band.copy(connected = false)
                        close()
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            Text(L("DISCONNECT"), style = NBFont.ui(500, 12f).tracking(0.2f), color = NB.text2)
        }
    }
}

/** Three reasons, in the order they actually happen: Bluetooth, distance, a flat battery. */
@Composable
fun WhyWontItConnectSheet() {
    Column(
        Modifier.fillMaxSize().background(NB.carbon2).padding(horizontal = 16.dp).padding(top = 26.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(L("Why won't it connect?"), style = NBFont.ui(500, 22f).tracking(0.01f), color = NB.text1)
        Column(Modifier.fillMaxWidth().sheetLines()) {
            ReasonItem("01", L("Bluetooth is off"), L("Turn it on in Quick Settings, then come back."))
            ReasonItem("02", L("It's out of range"), L("Bring the band within arm's reach of the phone."))
            ReasonItem("03", L("The battery is flat"), L("Charge it for ten minutes and hold the side key."), last = true)
        }
    }
}

@Composable
private fun ReasonItem(index: String, title: String, detail: String, last: Boolean = false) {
    Row(
        Modifier.fillMaxWidth().rowRule(last).padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(index, style = NBFont.dot(600, 11f).tracking(0.16f), color = NB.lime1, modifier = Modifier.padding(top = 2.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = NBFont.ui(500, 14f).tracking(0.02f), color = NB.text1)
            Text(detail, style = NBFont.ui(400, 12f).tracking(0.02f), color = NB.white.copy(alpha = 0.42f))
        }
        Spacer(Modifier.width(0.dp))
    }
}

/**
 * DEBUG · one type per row. Tap one: the band opens that sport and closes it again — a success
 * means this firmware carries it. The SDK has no query for its own list.
 */
@Composable
private fun SportProbeSheet() {
    var results by remember { mutableStateOf<Map<Int, Boolean>>(emptyMap()) }
    var probing by remember { mutableStateOf<Int?>(null) }
    var probeError by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().background(NB.carbon2).padding(horizontal = 16.dp).padding(top = 24.dp)) {
        Text(L("SPORT MODE PROBE"), style = NBFont.ui(500, 20f).tracking(0.01f), color = NB.text1)
        Text(
            L("Each tap opens the sport on the band and closes it again. A check means this firmware carries it. The SDK cannot query its own list, so this is the only way to enumerate it."),
            style = NBFont.ui(300, 12.5f).tracking(0.02f), color = NB.white.copy(alpha = 0.38f),
            modifier = Modifier.padding(top = 6.dp),
        )
        probeError?.let {
            Text(it, style = NBFont.dot(600, 10.5f).tracking(0.12f), color = NB.ember1, modifier = Modifier.padding(top = 8.dp))
        }
        Column(Modifier.padding(top = 16.dp).fillMaxWidth().verticalScroll(rememberScrollState()).sheetLines()) {
            SportModeCatalog.modes.forEachIndexed { index, mode ->
                Row(
                    Modifier.fillMaxWidth().height(46.dp)
                        .hotZoneTap(enabled = probing == null, pressedScale = 1f) {
                            probing = mode.rawValue
                            probeError = null
                            scope.launch {
                                try {
                                    results = results + (mode.rawValue to Band.live.probeSportMode(mode.rawValue))
                                } catch (e: CancellationException) {
                                    throw e
                                } catch (e: Throwable) {
                                    probeError = e.localizedDescription
                                } finally {
                                    probing = null
                                }
                            }
                        }
                        .padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(mode.name, style = NBFont.dot(500, 12f).tracking(0.1f), color = NB.text1)
                    Text("#${mode.rawValue}", style = NBFont.dot(400, 10f).tracking(0.1f), color = NB.white.copy(alpha = 0.3f))
                    Spacer(Modifier.weight(1f))
                    if (probing == mode.rawValue) {
                        SmallSpinner(NB.lime1)
                    } else {
                        val r = results[mode.rawValue]
                        Text(
                            if (r == true) "YES" else if (r == false) "NO" else "TAP",
                            style = NBFont.dot(600, 10.5f).tracking(0.12f),
                            color = if (r == true) NB.lime1 else if (r == false) NB.ember1 else NB.white.copy(alpha = 0.3f),
                        )
                    }
                }
                if (index < SportModeCatalog.modes.size - 1) Hairline(modifier = Modifier.padding(horizontal = 16.dp))
            }
        }
    }
}

/** DEBUG · one tap: capability bits, female-health read, six seconds of GSensor, then ADC.
 *  Lines are the band's own words. Nothing here becomes a product row. */
@Composable
private fun CapabilitySweepSheet() {
    var lines by remember { mutableStateOf<List<String>>(emptyList()) }
    var running by remember { mutableStateOf(false) }
    var probeError by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().background(NB.carbon2).padding(horizontal = 16.dp).padding(top = 24.dp)) {
        Text(L("CAPABILITY SWEEP"), style = NBFont.ui(500, 20f).tracking(0.01f), color = NB.text1)
        Text(
            L("Reads the band's own capability bits, the female-health register, and six seconds of GSensor. Long optical tests stay off."),
            style = NBFont.ui(300, 12.5f).tracking(0.02f), color = NB.white.copy(alpha = 0.38f),
            modifier = Modifier.padding(top = 6.dp),
        )
        Row(
            Modifier.padding(top = 16.dp).fillMaxWidth().height(46.dp).sheetLines()
                .hotZoneTap(enabled = !running, pressedScale = 1f) {
                    running = true
                    probeError = null
                    scope.launch {
                        try {
                            LiveReadout.shared.standDown {
                                try {
                                    lines = Band.live.probeCapabilitySweep()
                                } catch (e: CancellationException) {
                                    throw e
                                } catch (e: Throwable) {
                                    probeError = e.localizedDescription
                                }
                            }
                        } finally {
                            running = false
                        }
                    }
                }
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(if (running) L("READING…") else L("RUN SWEEP"), style = NBFont.dot(600, 12f).tracking(0.12f), color = NB.lime1,
                modifier = Modifier.weight(1f))
            Spacer(Modifier.width(16.dp))
            if (running) SmallSpinner(NB.lime1)
        }
        probeError?.let {
            Text(it, style = NBFont.dot(600, 10.5f).tracking(0.12f), color = NB.ember1, modifier = Modifier.padding(top = 8.dp))
        }
        SelectionContainer(Modifier.padding(top = 16.dp).fillMaxWidth().verticalScroll(rememberScrollState())) {
            Column(Modifier.fillMaxWidth().sheetLines().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                for (line in lines) Text(line, style = NBFont.dot(400, 10f).tracking(0.04f), color = NB.text1)
            }
        }
    }
}

