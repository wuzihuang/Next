package com.nextbody.hoop.band

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.services.SupabaseClient
import kotlinx.coroutines.Job
import java.time.Instant

/**
 * The band's own facts on the home screen: whether it is linked, what its battery says,
 * what firmware it runs. On a device none of this was ever written after the gate — the
 * header printed the simulator's 82% for as long as the band was worn — because the only
 * writers were the pairing screen (walked once) and the device page (opened rarely).
 *
 * One subscriber to `BandService.events` for the life of the process, plus one read after
 * every reconnect. Everything here is a fact the band reported; nothing is carried forward
 * from a value it did not.
 */
class BandPresence private constructor() {
    companion object {
        val shared: BandPresence by lazy { BandPresence() }
    }

    private var listener: Job? = null
    private val metadata = BandMetadataRefreshPolicy()

    /** Idempotent. `.state` keeps STANDBY / OFFLINE true to the link; `.battery` is what the
     *  SDK pushes on its own, which is the number the pip should show without being asked. */
    fun start(store: DataStore) {
        if (listener != null) return
        store.hydrateBatteryLog()
        listener = BandMain.launch {
            Band.live.events.collect { event ->
                when (event) {
                    is BandEvent.State -> {
                        val on = event.state == BandConnectionState.connected
                        store.recordBandLink(connected = on)
                        if (event.state != BandConnectionState.connected) BandReadiness.shared.invalidateSnapshot()
                    }
                    is BandEvent.Battery -> {
                        if (!BandHost.consentGranted() || SupabaseClient.currentUserIdSnapshot() == null ||
                            BoundBand.identifier == null) return@collect
                        store.applyBandObservation(battery = event.battery)
                    }
                    is BandEvent.HistoryRead ->
                        BandSyncActivity.shared.reportRead(day = event.day, of = event.of, percent = event.percent)
                    is BandEvent.ConnectionStep -> {
                        val activity = BandSyncActivity.shared
                        if (activity.phase == "connecting" && activity.workflow.stage in listOf(
                                BandSyncProgress.Stage.searching, BandSyncProgress.Stage.connecting,
                                BandSyncProgress.Stage.verifying)) {
                            activity.show(event.stage)
                        }
                    }
                    else -> Unit
                }
            }
        }
    }

    /** After a reconnect: identity, battery and capabilities off the band, and the devices
     *  row brought up to date so sync_runs and device_capabilities have an id to name.
     *  Quiet on failure — the header keeps showing a dash rather than a guess. */
    suspend fun refresh(store: DataStore, prepared: BandReadiness.Snapshot? = null) {
        if (Band.live.state != BandConnectionState.connected || !BandHost.consentGranted()) return
        val account = SupabaseClient.currentUserIdSnapshot() ?: return
        val binding = BoundBand.identifier ?: return
        fun isCurrent(): Boolean =
            BandHost.consentGranted() && !BandLiveLifecycle.shared.hasExclusiveOperation
                && SupabaseClient.currentUserIdSnapshot() == account
                && BoundBand.identifier == binding && Band.live.state == BandConnectionState.connected
        store.setBandConnected(true)
        val valid = prepared?.takeIf { it.account == account && it.binding == binding }
        val identity: BandIdentity?
        val battery: BandBattery?
        if (valid != null) {
            identity = valid.identity
            battery = valid.battery
        } else {
            identity = runCatching { BandReadiness.read(account, binding) { Band.live.readIdentity() } }.getOrNull()
            if (!isCurrent()) return
            battery = runCatching { BandReadiness.read(account, binding) { Band.live.readBattery() } }.getOrNull()
        }
        if (!isCurrent()) return
        store.applyBandObservation(identity = identity, battery = battery)
        val repository = BandHost.repository
        fun metadataKey(): BandMetadataRefreshPolicy.Key? {
            val deviceID = repository.deviceId
            if (identity == null || deviceID == null) return null
            return BandMetadataRefreshPolicy.Key(account = account, binding = binding, deviceID = deviceID, firmware = identity.firmware)
        }
        // Battery observations remain fresh, but registration/capability publication is
        // initialization, not something to repeat on every automatic health-data pull.
        if (!metadata.needsRefresh(metadataKey())) return
        BandSyncActivity.shared.show(BandSyncProgress.Stage.saving)
        if (!repository.registerDevice(identity = identity, battery = battery)) return

        if (!isCurrent()) return
        BandSyncActivity.shared.show(BandSyncProgress.Stage.capabilities)

        // 07 · the plus menu is gated on what this NEXTBODY says it can do, read from the band
        // and stored, so the gate is right before the device page has ever been opened.
        val caps = runCatching { BandReadiness.read(account, binding) { Band.live.readCapabilities() } }.getOrNull()
        if (caps != null) {
            if (!isCurrent()) return
            store.capabilities = caps
            store.capabilitiesReadAt = Instant.now()
            val deviceId = repository.deviceId
            val userId = SupabaseClient.currentUserId
            if (deviceId != null && userId != null) {
                if (userId != account || !isCurrent()) return
                BandSyncActivity.shared.show(BandSyncProgress.Stage.saving)
                val saved = repository.saveCapabilities(caps, deviceId = deviceId, userId = userId,
                    holdsDays = identity?.watchDataDayNumber)
                if (!isCurrent()) return
                metadata.complete(metadataKey(), success = saved)
            }
        }
        // iOS DEBUG-only NB_DEBUG_PROBE probes (manualdata / microtest / capsweep /
        // healthglance) and the health-function log are launch-flag diagnostics; not ported.
    }
}

/** Shared progress spans connection, device reads, upload and historical backfill. */
class BandSyncActivity private constructor() {
    companion object {
        val shared: BandSyncActivity by lazy { BandSyncActivity() }
    }

    var phase by mutableStateOf("idle")
    /** Bumped on every in-place change of [progress] / [workflow] so Compose readers redraw. */
    private var revision by mutableIntStateOf(0)
    private val _progress = BandSyncPolicy.ReadProgress()
    private val _workflow = BandSyncProgress()
    /** Days the current pull has finished, and how many it expects. The band answers one
     *  day at a time and the SDK sets the pace, so this is the honest thing to show: not a
     *  speed, but where the read has got to. Zero total means nothing is being counted. */
    val progress: BandSyncPolicy.ReadProgress get() { revision; return _progress }
    val workflow: BandSyncProgress get() { revision; return _workflow }
    var failureLine by mutableStateOf<String?>(null)
        private set

    val done: Int get() = progress.done
    val total: Int get() = progress.total
    val percent: Int get() = progress.percent
    val fraction: Double get() = workflow.fraction
    /** Only while the sync is running. Completion clears the bar on both surfaces at once;
     *  a finished bar left sitting at 100% is not a state, it is clutter. */
    val showsProgress: Boolean get() = workflow.active

    /** Home's display and Device render this exact line, including the same rounding
     *  and day counter. Neither surface owns another sync state or percentage. */
    val progressLine: String
        get() {
            val destination = workflow.stage.destination?.let { L(it.raw) + " · " } ?: ""
            val prefix = L(workflow.modeLabel) + " · " + destination + "${(fraction * 100).toInt()}% · "
            if (workflow.stage == BandSyncProgress.Stage.reading && total > 0) {
                return prefix + L("READING DAY") + " ${minOf(done + 1, total)} " + L("OF") + " $total"
            }
            return prefix + L(workflow.stage.label)
        }

    private inline fun mutate(block: () -> Unit) { block(); revision += 1 }

    fun show(stage: BandSyncProgress.Stage) {
        mutate { _workflow.show(stage) }
        BandSyncDiagnostics.setStage(_workflow.stage.raw)
    }
    fun beginHistory() = mutate { _workflow.beginHistory() }
    fun failed(error: Throwable) {
        when {
            error is BandError.Timeout -> failureLine = L("SYNC TIMED OUT · RETRY")
            error is BandError.Busy ->
                failureLine = L("Finish the current measurement or device operation, then sync again.")
            error is BandError.NotConnected ->
                failureLine = L("Could not reach this NEXTBODY. Keep it nearby, check Bluetooth, then tap Sync to try again.")
            failureLine == null -> failureLine = L("Some readings could not sync. Tap Sync to try again.")
        }
    }
    fun updatingResults() = mutate { _workflow.updatingResults() }
    fun resultsLoaded() = mutate { _workflow.resultsLoaded() }
    fun complete(success: Boolean) {
        mutate { _workflow.finish(success = success) }
        BandSyncDiagnostics.setStage(_workflow.stage.raw)
        if (success) failureLine = null
        else if (failureLine == null) failureLine = L("Sync did not complete. Tap Sync to try again.")
        phase = "idle"
    }

    fun beginCounting() { mutate { _progress.begin(); _workflow.begin() }; failureLine = null }
    /** The backfill knows how many retained days it will walk once it has asked the band. */
    fun expect(total: Int) = mutate {
        _progress.expect(total = total)
        _workflow.expect(total)
    }
    fun step() = mutate {
        _progress.step()
        _workflow.filedDay()
    }
    /** Movement inside the day being read, 0…100. Ignored once the dump is driving. */
    fun within(percent: Int) {
        if (phase == "idle") return
        mutate {
            _progress.within(percent = percent)
            _workflow.read(_progress.fraction)
        }
    }
    /** The real number of days this pull will read, once the plan is known. */
    fun revise(total: Int) {
        if (phase == "idle") return
        mutate {
            _progress.revise(total = total)
            _workflow.expect(total)
        }
    }
    /** SDK dump tick: which day of how many, and 0…100 of that day. */
    fun reportRead(day: Int, of: Int, percent: Int) {
        if (phase == "idle") return
        mutate {
            _progress.reportRead(day = day, of = of, percent = percent)
            _workflow.read(_progress.fraction)
        }
    }
    fun stopCounting() = mutate { _progress.stop() }

    /** `NB_DEBUG_SYNC_PROGRESS=3` paints the bar without a band to read. */
    fun debugShow(done: Int, total: Int) {
        phase = "syncing"
        mutate {
            _progress.begin()
            _progress.expect(total = total)
            repeat(done) { _progress.step() }
            _workflow.begin()
            _workflow.show(BandSyncProgress.Stage.reading)
            _workflow.read(_progress.fraction)
        }
    }
}
