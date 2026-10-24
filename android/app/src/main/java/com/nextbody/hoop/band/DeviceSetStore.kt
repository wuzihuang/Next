package com.nextbody.hoop.band

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nextbody.hoop.data.BandState
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.services.SupabaseClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import java.time.Instant
import java.time.OffsetDateTime
import java.util.UUID

/**
 * docs/plans/2026-09-12-dual-device-continuity.md §04.5 · the phone's view of the set.
 *
 * One NEXTBODY is worn; the other charges. The person says which (`I'm wearing B`), and that
 * declaration is the only rule the server uses to pick a source. This store keeps both
 * slots' last-known facts, the wear timeline, and drives the two link moves the manual
 * model needs: the handover (transport follows the declaration) and the standby sync
 * (transport briefly visits the other band, then comes back).
 */
class DeviceSetStore private constructor() {
    companion object {
        val shared: DeviceSetStore by lazy { DeviceSetStore() }

        private fun timestamp(raw: String): Instant? =
            runCatching { OffsetDateTime.parse(raw).toInstant() }.getOrNull()
                ?: runCatching { Instant.parse(raw) }.getOrNull()

        private fun int(any: Any?): Int? = when (any) {
            is Int -> any
            is Long -> any.toInt()
            is Double -> any.toInt()
            is Number -> any.toInt()
            is String -> any.toIntOrNull()
            else -> null
        }

        @Suppress("UNCHECKED_CAST")
        private fun rows(any: Any?): List<Map<String, Any?>> =
            (any as? List<*>)?.mapNotNull { it as? Map<String, Any?> } ?: emptyList()
    }

    /** Last-known facts about one slot. Off-link values are what the server or the last
     *  visit reported, with the time they were read — never a guess. */
    data class SlotSnapshot(
        var slot: HoopSlot,
        var deviceId: String? = null,
        var identifier: String? = null,
        var name: String,
        var firmware: String? = null,
        var battery: BandBattery? = null,
        var batteryReadAt: Instant? = null,
        var lastSync: Instant? = null,
        var boundAt: Instant? = null,
        var holdsDays: Int? = null,
        var standbySamples: Int = 0,
    ) {
        val isBound: Boolean get() = identifier != null

        /** A band at the bottom of its pack has stopped recording. Level-only firmware
         *  reports 0–4 bars instead of a percent, so both shapes count. */
        val isFlat: Boolean
            get() {
                val battery = battery ?: return false
                if (battery.chargeState == BandBattery.ChargeState.charging || battery.chargeState == BandBattery.ChargeState.full) return false
                if (battery.isPercent && battery.percent != null) return battery.percent <= 2
                if (battery.level != null) return battery.level <= 0
                return false
            }

        /** Low enough that it will not last the day, but still recording. */
        val isLow: Boolean
            get() {
                val battery = battery ?: return false
                if (isFlat || battery.chargeState == BandBattery.ChargeState.charging || battery.chargeState == BandBattery.ChargeState.full) return false
                if (battery.isPercent && battery.percent != null) return battery.percent <= 15
                if (battery.level != null) return battery.level <= 1
                return false
            }
    }

    sealed class Phase {
        data object Idle : Phase()
        /** The band being left is finishing the command it is on. The SDK has no stop, so
         *  this wait is real — but it is one day's read, not the rest of a week's history. */
        data class Finishing(val slot: HoopSlot) : Phase()
        /** The declaration is recorded; the link is moving to the declared band. */
        data class Switching(val slot: HoopSlot) : Phase()
        /** The second band is being verified and given its slot. */
        data class Activating(val slot: HoopSlot) : Phase()
    }

    var slots by mutableStateOf<Map<HoopSlot, SlotSnapshot>>(emptyMap())
        private set
    var timeline by mutableStateOf(DeviceSlots.timeline)
        private set
    var wearing by mutableStateOf(DeviceSlots.wearing)
        private set
    var transport by mutableStateOf(DeviceSlots.transport)
        private set
    var phase by mutableStateOf<Phase>(Phase.Idle)
        private set
    var lastError by mutableStateOf<String?>(null)
        private set
    var isReleasing by mutableStateOf(false)
        private set
    private var bindingRevision = 0
    private var replaying = false
    val activationGate = DeviceActivationGate()

    private val repository get() = BandHost.repository

    private fun setSlot(slot: HoopSlot, snap: SlotSnapshot?) {
        slots = if (snap == null) slots - slot else slots + (slot to snap)
    }

    suspend fun prepareActivation(owner: UUID) {
        if (isReleasing || !(phase == Phase.Idle || activationGate.owner == owner) || openSlot == null) {
            throw DeviceActivationGate.Failure.busy()
        }
        // Close admission synchronously before the first suspension/scan. Existing pulls
        // stop at their next scope check instead of finishing a week of history.
        try {
            activationGate.prepare(owner = owner, acquired = {
                bindingRevision += 1
                BandLiveLifecycle.shared.refreshEligibility()
            }) {
                OriginDataSync.isIdle && BandReadiness.shared.isNativeIdle
            }
            LiveReadout.shared.standDown { }
            BandLiveLifecycle.shared.refreshEligibility()
            currentCoroutineContext().ensureActive()
            val slot = openSlot ?: throw DeviceActivationGate.Failure.busy()
            phase = Phase.Activating(slot)
            BandTrace.notice("deviceset activate: radio ready for scan")
        } catch (e: Throwable) {
            endActivation(owner)
            BandLiveLifecycle.shared.refreshEligibility()
            throw e
        }
    }

    fun endActivation(owner: UUID) {
        if (activationGate.owner != owner) return
        activationGate.release(owner = owner)
        phase = Phase.Idle
        BandLiveLifecycle.shared.refreshEligibility()
    }

    val hasSecond: Boolean get() = slots.size >= 2
    val standbySlot: HoopSlot? get() = if (hasSecond) wearing.other else null
    /** What the last read said about a band's charge. Off-link this is the last known
     *  value, never a live one, so the card says when it was read. */
    fun isFlat(slot: HoopSlot): Boolean = slots[slot]?.isFlat ?: false
    fun snapshot(slot: HoopSlot): SlotSnapshot? = slots[slot]
    val wearingSince: Instant? get() = timeline.wearingSince()

    /** The empty slot the next activation fills, if the set has room. */
    val openSlot: HoopSlot?
        get() {
            if (slots.size != 1) return if (slots.isEmpty()) HoopSlot.a else null
            return slots.keys.first().other
        }

    /** One handover at a time. A second tap does not start a second link move; it changes
     *  where the one in flight is headed. */
    private var handover: Job? = null
    private var releaseCleanup: Job? = null
    /** Where the last move ended and when. A second tap on the NEXTBODY the link just landed
     *  on is not a reason to read it again. */
    private var landed: Pair<HoopSlot, Instant>? = null

    init {
        hydrateFromLocal()
    }

    // MARK: loading

    /** Local first, so the page draws without a network round trip; then the server's set. */
    fun hydrateFromLocal() {
        val next = mutableMapOf<HoopSlot, SlotSnapshot>()
        for (binding in DeviceSlots.bindings) {
            val snap = (slots[binding.slot] ?: SlotSnapshot(slot = binding.slot, name = binding.name ?: "NEXTBODY")).copy()
            snap.deviceId = binding.deviceId
            snap.identifier = binding.identifier
            snap.boundAt = binding.boundAt ?: snap.boundAt
            binding.name?.let { snap.name = it }
            next[binding.slot] = snap
        }
        slots = next
        timeline = DeviceSlots.timeline
        wearing = DeviceSlots.wearing
        transport = DeviceSlots.transport
        // iOS DEBUG `NB_DEBUG_STANDBY` charge fixtures are launch-flag only; not ported.
    }

    suspend fun load() {
        if (isReleasing || activationGate.isHeld) return
        hydrateFromLocal()
        val revision = bindingRevision
        replayPending()
        val set = try { repository.loadDeviceSet() } catch (e: CancellationException) { throw e } catch (_: Throwable) { null }
        if (set == null) {
            if (!activationGate.isHeld && revision == bindingRevision) hydrateFromLocal()
            return
        }
        if (isReleasing || activationGate.isHeld || revision != bindingRevision) return
        apply(set)
        // A switch settles once the band has been read, but that read can still be
        // draining when the handover finishes. Finishing the job here costs one call and
        // makes the start right the next time the page is opened.
        val current = timeline.current()
        if (phase == Phase.Idle && current != null && current.source == "auto" &&
            BandTime.interval(Instant.now(), current.recordedAt) < 6 * 3600) {
            val settled = runCatching { repository.settleWearStart() }.getOrNull()
            if (!settled.isNullOrEmpty() && !isReleasing && revision == bindingRevision) apply(settled)
        }
    }

    private fun apply(set: Map<String, Any?>) {
        val devices = rows(set["devices"])
        val next = mutableMapOf<HoopSlot, SlotSnapshot>()
        val claims = mutableListOf<Pair<String, String>>()
        for (row in devices) {
            val raw = row["slot"] as? String ?: continue
            val slot = HoopSlot.entries.firstOrNull { it.raw == raw } ?: continue
            val key = row["device_key"] as? String ?: continue
            var binding = DeviceSlots.binding(slot) ?: SlotBinding(slot = slot, identifier = key)
            binding = binding.copy(
                deviceId = row["id"] as? String,
                boundAt = (row["bound_at"] as? String)?.let(::timestamp) ?: binding.boundAt)
            DeviceSlots.set(binding)
            // The server must know the key this phone files evidence under, or the wearer
            // rule holds the worn band's own ticks (found on the first device walk).
            val id = binding.deviceId
            if (id != null && row["client_key"] as? String != binding.identifier &&
                binding.identifier != BoundBand.seedIdentifier) {
                claims.add(id to binding.identifier)
            }
            val snap = (slots[slot] ?: SlotSnapshot(slot = slot, name = binding.name ?: "NEXTBODY")).copy()
            snap.deviceId = binding.deviceId
            snap.identifier = binding.identifier
            snap.boundAt = binding.boundAt
            snap.firmware = row["firmware_version"] as? String ?: snap.firmware
            snap.lastSync = (row["last_origin_sync_at"] as? String)?.let(::timestamp) ?: snap.lastSync
            snap.standbySamples = int(row["standby_samples"]) ?: 0
            val percent = int(row["battery_percent"])
            if (snap.battery == null && percent != null) {
                snap.battery = BandBattery(isPercent = (row["battery_is_percent"] as? Boolean) ?: true,
                    percent = percent, level = int(row["battery_level"]),
                    chargeState = BandBattery.ChargeState.unknown)
                snap.batteryReadAt = snap.lastSync
            }
            next[slot] = snap
        }
        // A slot the server no longer has is gone here too (released on another phone).
        for (slot in HoopSlot.entries) if (next[slot] == null) DeviceSlots.remove(slot)
        slots = next
        val events = mutableListOf<WearEvent>()
        for (row in rows(set["events"])) {
            val raw = row["slot"] as? String ?: continue
            val slot = HoopSlot.entries.firstOrNull { it.raw == raw } ?: continue
            val at = (row["effective_at"] as? String)?.let(::timestamp) ?: continue
            events.add(WearEvent(slot = slot, effectiveAt = at,
                recordedAt = (row["recorded_at"] as? String)?.let(::timestamp) ?: at,
                clientOpId = null, source = row["source"] as? String))
        }
        // Local declarations that have not reached the server yet still count.
        events.addAll(DeviceSlots.pendingOps)
        DeviceSlots.events = events
        timeline = DeviceSlots.timeline
        val worn = timeline.wearer(Instant.now())
        if (worn != null && DeviceSlots.binding(worn) != null) DeviceSlots.wearing = worn
        wearing = DeviceSlots.wearing
        transport = DeviceSlots.transport
        if (claims.isNotEmpty()) {
            val revision = bindingRevision
            BandMain.launch {
                for ((id, key) in claims) {
                    if (isReleasing || revision != bindingRevision) return@launch
                    val claimed = runCatching { repository.claimDeviceKey(deviceId = id, clientKey = key) }.getOrNull()
                    if (!claimed.isNullOrEmpty()) {
                        if (isReleasing || revision != bindingRevision) return@launch
                        apply(claimed)
                    }
                }
            }
        }
    }

    /** The transport band's live facts, as the sync lane learns them. */
    fun noteTransportObservation(state: BandState, lastSync: Instant?) {
        val slot = DeviceSlots.transport
        val snap = slots[slot]?.copy() ?: return
        if (state.name.isNotEmpty()) snap.name = state.name
        snap.firmware = if (state.firmware.isEmpty()) snap.firmware else state.firmware
        state.lastBattery?.let { packet ->
            snap.battery = packet
            snap.batteryReadAt = Instant.now()
        }
        if (lastSync != null) snap.lastSync = lastSync
        setSlot(slot, snap)
        DeviceSlots.binding(slot)?.let { DeviceSlots.set(it.copy(name = snap.name)) }
    }

    fun noteHoldsDays(days: Int?, slot: HoopSlot) {
        if (days == null) return
        val snap = slots[slot]?.copy() ?: return
        snap.holdsDays = days
        setSlot(slot, snap)
    }

    // MARK: declarations

    /**
     * `I'm wearing this one`. Recorded locally first, sent to the server, then the link
     * follows. The declaration stands whatever the link does afterwards (§04.5 W3).
     *
     * `since` is null on the switching path: the app files the declaration at the tap and
     * the band's own wrist evidence moves the start back once the phone has read it. A
     * date is a time the wearer pinned on the correction sheet and is never second-guessed.
     */
    fun declareWearing(slot: HoopSlot, since: Instant? = null, store: DataStore): Boolean {
        if (isReleasing || activationGate.isHeld || slots[slot] == null) return false
        val now = Instant.now()
        val floor = timeline.earliestSwitch(slot) ?: BandTime.distantPast
        val requested = since ?: now
        val effective = maxOf(minOf(requested, now), floor)
        val opId = UUID.randomUUID().toString().uppercase()
        val source = if (since == null) "auto" else "manual"
        val event = WearEvent(slot = slot, effectiveAt = effective, recordedAt = now, clientOpId = opId, source = source)
        DeviceSlots.events = timeline.declaring(slot, at = effective, recordedAt = now, opId = opId, source = source).events
        DeviceSlots.pendingOps = DeviceSlots.pendingOps + event
        DeviceSlots.wearing = slot
        timeline = DeviceSlots.timeline
        wearing = slot
        BandMain.launch { BandHost.analytics("WEAR_SWITCH_REQUESTED", mapOf("TO" to slot.raw, "PINNED" to (since != null))) }
        // The declaration is the whole answer to the tap, and it is already stored. The
        // network and the radio follow on their own: no signal, a flat band or a link that
        // will not come up can delay them, but none of them can take the declaration back.
        BandMain.launch { replayPending() }
        scheduleHandover(store, settling = if (source == "auto") opId else null)
        return true
    }

    /** Move the link to whichever band is declared worn, one move at a time. Tapping
     *  A → B → A in quick succession runs at most one extra move and always ends on the
     *  band named last; it never runs two link moves at once. */
    private fun scheduleHandover(store: DataStore, settling: String?) {
        val previous = handover
        handover = BandMain.launch {
            previous?.join()
            if (!isActive) return@launch
            // A burst of taps is one intention, not four. Letting it settle for less time
            // than the sheet takes to close turns A → B → A into no link move at all.
            try { delay(400) } catch (_: CancellationException) {}
            if (!isActive) return@launch
            var target = DeviceSlots.wearing
            while (isActive) {
                if (activationGate.isHeld) return@launch
                val landed = landed
                if (DeviceSlots.transport == target && landed != null && landed.first == target &&
                    BandTime.interval(Instant.now(), landed.second) < 5) {
                    BandTrace.notice("handover skip target=${target.raw} · just landed")
                    break
                }
                BandTrace.notice("handover run target=${target.raw}")
                moveTransport(target, store, Phase.Switching(target))
                target = DeviceSlots.wearing
                if (target == DeviceSlots.transport) break
            }
            if (!isActive || settling == null) return@launch
            settleStart(settling)
        }
    }

    /** Let the evidence move the start of the declaration this phone just filed. */
    private suspend fun settleStart(opId: String) {
        if (isReleasing) return
        val revision = bindingRevision
        if (DeviceSlots.pendingOps.any { it.clientOpId == opId }) return
        val set = runCatching { repository.settleWearStart(opId) }.getOrNull()
        if (set.isNullOrEmpty()) return
        if (isReleasing || revision != bindingRevision) return
        val before = timeline.current()?.effectiveAt
        apply(set)
        val after = timeline.current()?.effectiveAt
        if (after != null && (before == null || after.isBefore(before.minusSeconds(60)))) {
            val minutes = (BandTime.interval(Instant.now(), after) / 60).toInt()
            BandMain.launch { BandHost.analytics("WEAR_START_SETTLED", mapOf("MINUTES" to minutes)) }
        }
    }

    /** Declarations made offline go up in order on the next chance. */
    suspend fun replayPending() {
        if (isReleasing || replaying) return
        replaying = true
        try {
            val revision = bindingRevision
            val pending = DeviceSlots.pendingOps
            if (pending.isEmpty()) return
            val remaining = pending.toMutableList()
            for (event in pending) {
                val deviceId = DeviceSlots.binding(event.slot)?.deviceId
                val opId = event.clientOpId
                if (deviceId == null || opId == null) {
                    remaining.removeAll { it.clientOpId == event.clientOpId }
                    continue
                }
                try {
                    val set = repository.recordWearEvent(
                        deviceId = deviceId, effectiveAt = if (event.isPinned) event.effectiveAt else null, opId = opId)
                    if (isReleasing || revision != bindingRevision) return
                    remaining.removeAll { it.clientOpId == opId }
                    DeviceSlots.pendingOps = DeviceSlots.pendingOps.filter { it.clientOpId != opId }
                    if (set.isNotEmpty()) apply(set)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    BandTrace.error("wear event not recorded: $e")
                    break
                }
            }
            // Preserve declarations appended while this request was in flight.
            val completed = pending.mapNotNull { it.clientOpId }.toSet() - remaining.mapNotNull { it.clientOpId }.toSet()
            DeviceSlots.pendingOps = DeviceSlots.pendingOps.filterNot { op -> op.clientOpId?.let { it in completed } ?: false }
        } finally {
            replaying = false
        }
    }

    // MARK: the link

    /** Point the link at `slot`: finish the pull in flight (never a hard stop), drop the
     *  old link, retarget, reconnect and read. The wearer's declaration is already stored,
     *  so a failure here leaves `WEARING · NOT CONNECTED`, not a reverted declaration. */
    private suspend fun moveTransport(slot: HoopSlot, store: DataStore, phase: Phase) {
        if (DeviceSlots.binding(slot) == null) return
        val began = Instant.now()
        this.phase = phase
        try {
            if (DeviceSlots.transport != slot) {
                val leaving = DeviceSlots.transport
                noteTransportObservation(store.band, lastSync = store.lastSync)
                // A pull already walking the old band's week would otherwise hold the switch
                // for minutes. Pointing the app at the new band first makes that pull see a
                // scope it no longer owns, so it stops at its next day boundary — the wait
                // below is one day's read, not the rest of the history. A measurement is not
                // interruptible that way, so when nothing is pulling we wait first instead.
                BandTrace.notice("move begin from=${leaving.raw} to=${slot.raw}")
                val pulling = BandSyncActivity.shared.phase != "idle"
                if (!pulling) BandReadiness.shared.awaitNativeIdle()
                if (!currentCoroutineContext().isActive) return
                BoundBand.switchTransport(slot)
                BandReadiness.shared.invalidateSnapshot()
                transport = slot
                if (pulling) {
                    this.phase = Phase.Finishing(leaving)
                    OriginDataSync.waitForCurrentPull()
                    BandReadiness.shared.awaitNativeIdle()
                    if (!currentCoroutineContext().isActive) return
                    this.phase = phase
                }
                Band.live.disconnect()
                if (!currentCoroutineContext().isActive) return
                store.band = BandState.unknown.copy(name = slots[slot]?.name ?: "NEXTBODY")
                store.lastSync = slots[slot]?.lastSync
                repository.adoptTransportDevice(slots[slot]?.deviceId)
            }
            // One pull reads the link, today and everything the band still holds. Splitting it
            // in two made the page connect and sync twice for a single tap.
            //
            // The handover itself is over as soon as the link is up, so the phase is released
            // there rather than at the end of the read: the strip stops saying CONNECTING and
            // the bar carries the rest.
            val releasing = BandMain.launch {
                repeat(300) {
                    if (!isActive) return@launch
                    if (BandSyncActivity.shared.phase == "syncing") { this@DeviceSetStore.phase = Phase.Idle; return@launch }
                    delay(200)
                }
            }
            val result = OriginDataSync.refreshNow(store, BandRefreshRequest.fullHistory)
            releasing.cancel()
            if (!currentCoroutineContext().isActive) return
            noteTransportObservation(store.band, lastSync = store.lastSync)
            val ms = (BandTime.interval(Instant.now(), began) * 1000).toInt()
            BandTrace.notice("move done to=${slot.raw} result=${result.status.raw} ms=$ms")
            BandMain.launch {
                BandHost.analytics("WEAR_SWITCH_CONNECTED", mapOf("SLOT" to slot.raw, "RESULT" to result.status.raw, "MS" to ms))
            }
            landed = slot to Instant.now()
        } finally {
            this.phase = Phase.Idle
            transport = DeviceSlots.transport
        }
    }

    /** If the link is not on the worn band — a handover that failed halfway, an activation
     *  that was interrupted — bring it back. The app talks to the band on your wrist and
     *  nothing else: the other one is read when you next put it on. */
    suspend fun reconcileTransport(store: DataStore) {
        if (isReleasing || activationGate.isHeld || phase != Phase.Idle) return
        if (handover != null && handover?.isCancelled != true) return
        if (DeviceSlots.transport == DeviceSlots.wearing || DeviceSlots.binding(DeviceSlots.wearing) == null) return
        scheduleHandover(store, settling = null)
        handover?.join()
    }

    // MARK: activation

    enum class ActivationStage(val raw: Int) { connect(0), verify(1), capabilities(2), activate(3) }

    /** Give the second band its slot: connect, verify, read what it can do, register the
     *  row. The worn band's link is borrowed for the duration and handed back afterwards.
     *  Nothing the new band recorded before this moment enters the timeline. */
    suspend fun activateSecond(
        device: DiscoveredBand, store: DataStore, owner: UUID,
        stage: (ActivationStage) -> Unit,
        progress: (Double) -> Unit = {},
    ): SlotSnapshot {
        val slot = openSlot
        if (isReleasing || activationGate.owner != owner || slot == null ||
            DeviceSlots.bindings.any { it.identifier == device.id }) {
            throw DeviceActivationGate.Failure.busy()
        }
        val previous = DeviceSlots.transport
        phase = Phase.Activating(slot)
        try {
            // Preparation already drained the old link before scanning began.
            noteTransportObservation(store.band, lastSync = store.lastSync)
            Band.live.disconnect()
            DeviceSlots.set(SlotBinding(slot = slot, identifier = device.id, name = device.name))
            BoundBand.switchTransport(slot)
            BandReadiness.shared.invalidateSnapshot()
            transport = slot
            try {
                stage(ActivationStage.connect)
                Band.live.connect(device) { p -> BandMain.launch { progress(0.35 * p) } }
                progress(0.35)
                stage(ActivationStage.verify)
                val identity = Band.live.readIdentity()
                progress(0.60)
                stage(ActivationStage.capabilities)
                val caps = Band.live.readCapabilities()
                progress(0.85)
                stage(ActivationStage.activate)
                val battery = Band.live.readBattery()
                if (!repository.registerDevice(identity = identity, battery = battery, slot = slot) ||
                    DeviceSlots.binding(slot)?.deviceId == null) {
                    throw BandError.Rejected(L("Pairing could not be saved. Check your connection and try again."))
                }
                val deviceId = DeviceSlots.binding(slot)?.deviceId
                val userId = SupabaseClient.currentUserId
                if (deviceId != null && userId != null) {
                    repository.saveCapabilities(caps, deviceId = deviceId, userId = userId,
                        holdsDays = identity.watchDataDayNumber)
                }
                val snap = SlotSnapshot(slot = slot, name = identity.name)
                snap.deviceId = DeviceSlots.binding(slot)?.deviceId
                snap.identifier = device.id
                snap.firmware = identity.firmware
                snap.battery = battery
                snap.batteryReadAt = Instant.now()
                snap.boundAt = DeviceSlots.binding(slot)?.boundAt ?: Instant.now()
                snap.holdsDays = identity.watchDataDayNumber
                setSlot(slot, snap)
                progress(1.0)
                BandMain.launch { BandHost.analytics("DEVICE_MEMBER_ACTIVATED", mapOf("SLOT" to slot.raw)) }
            } catch (e: Throwable) {
                DeviceSlots.remove(slot)
                setSlot(slot, null)
                Band.live.disconnect()
                BoundBand.switchTransport(previous)
                BandReadiness.shared.invalidateSnapshot()
                transport = previous
                repository.adoptTransportDevice(slots[previous]?.deviceId)
                BandMain.launch { OriginDataSync.refreshNow(store, BandRefreshRequest.latest) }
                throw e
            }
            // Hand the link back to the worn band. The new band waits on its charger.
            Band.live.disconnect()
            BoundBand.switchTransport(previous)
            BandReadiness.shared.invalidateSnapshot()
            transport = previous
            repository.adoptTransportDevice(slots[previous]?.deviceId)
            timeline = DeviceSlots.timeline
            BandMain.launch { OriginDataSync.refreshNow(store, BandRefreshRequest.latest) }
            return slots[slot]!!
        } finally {
            endActivation(owner)
        }
    }

    /** The server closes one binding before any local state is removed. A surviving slot
     *  keeps its identity; removing A must not rename B or prevent filling A again. */
    suspend fun release(slot: HoopSlot, store: DataStore) {
        if (isReleasing || activationGate.isHeld || phase != Phase.Idle) throw DeviceReleaseError.busy()
        if (replaying || DeviceSlots.pendingOps.isNotEmpty()) {
            BandMain.launch { replayPending() }
            throw DeviceReleaseError.pendingChanges()
        }
        val id = DeviceSlots.binding(slot)?.deviceId ?: throw DeviceReleaseError.bindingUnavailable()
        isReleasing = true
        bindingRevision += 1
        val previous = handover
        var removingTransport = false
        var remainingKey: String? = null
        try {
            releaseCleanup = DeviceReleaseOperation.run(request = {
                repository.releaseDevice(id)
            }, publish = { set ->
                previous?.cancel()
                handover = null
                removingTransport = DeviceSlots.transport == slot
                DeviceSlots.remove(slot)
                apply(set)
                remainingKey = BoundBand.identifier
                repository.adoptTransportDevice(slots[DeviceSlots.transport]?.deviceId)
                if (removingTransport) {
                    BandReadiness.shared.invalidateSnapshot()
                    store.band = BandState.unknown
                    store.lastSync = slots[DeviceSlots.transport]?.lastSync
                }
                if (slots.isEmpty()) {
                    BoundBand.forget()
                    hydrateFromLocal()
                }
                bindingRevision += 1
            }, cleanup = {
                previous?.join()
                if (removingTransport) {
                    OriginDataSync.waitForCurrentPull()
                    BandReadiness.shared.awaitNativeIdle()
                    // A new onboarding pairing may already own the radio.
                    if (BoundBand.identifier == remainingKey) {
                        Band.live.disconnect()
                        if (slots.isNotEmpty()) {
                            landed = null
                            scheduleHandover(store, settling = null)
                        }
                    }
                }
                isReleasing = false
            })
        } catch (e: Throwable) {
            isReleasing = false
            bindingRevision += 1
            throw e
        }
    }
}
