package com.nextbody.hoop.band

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/** docs/plans/2026-09-12-dual-device-continuity.md §04.5 · two HOOPs, one wearer.
 *
 *  A slot is a fixed position in the account's device set. It is given when the band is
 *  activated and never moves with wearing, preference or a new BLE alias. The app talks to
 *  one band at a time (the SDK is a singleton); `transport` names that band, `wearing`
 *  names the band the person declared on the wrist. The two agree except during a standby
 *  sync, when the phone briefly reads the other band. */
enum class HoopSlot(val raw: String) {
    a("A"), b("B");

    val other: HoopSlot get() = if (this == a) b else a
    val displayName: String get() = "NEXTBODY $raw"

    companion object { fun fromRaw(raw: String?): HoopSlot? = entries.firstOrNull { it.raw == raw } }
}

/** What this phone knows about one slot. `identifier` is the durable binding key the whole
 *  sync lane is scoped by; `peripheralIdentifier` is this phone's BLE alias. */
data class SlotBinding(
    var slot: HoopSlot,
    var identifier: String,
    var peripheralIdentifier: String? = null,
    var deviceId: String? = null,
    var name: String? = null,
    var boundAt: Instant? = null,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("slot", slot.raw); put("identifier", identifier)
        peripheralIdentifier?.let { put("peripheralIdentifier", it) }
        deviceId?.let { put("deviceId", it) }
        name?.let { put("name", it) }
        boundAt?.let { put("boundAt", BandTime.seconds(it)) }
    }

    companion object {
        fun fromJson(o: JSONObject) = SlotBinding(
            slot = HoopSlot.fromRaw(o.getString("slot")) ?: throw IllegalArgumentException("slot"),
            identifier = o.getString("identifier"),
            peripheralIdentifier = o.optStringOrNull("peripheralIdentifier"),
            deviceId = o.optStringOrNull("deviceId"),
            name = o.optStringOrNull("name"),
            boundAt = o.optInstant("boundAt"))
    }
}

/** One wear declaration: from `effectiveAt` the person wore `slot`, until the next event. */
data class WearEvent(
    var slot: HoopSlot,
    var effectiveAt: Instant,
    var recordedAt: Instant,
    var clientOpId: String? = null,
    /** `auto` · the app declared at the tap and let the band's evidence move the start.
     *  `manual` · a time the wearer pinned. Absent on events an older build stored. */
    var source: String? = null,
) {
    val isPinned: Boolean get() = source == "manual"

    fun toJson(): JSONObject = JSONObject().apply {
        put("slot", slot.raw)
        put("effectiveAt", BandTime.seconds(effectiveAt)); put("recordedAt", BandTime.seconds(recordedAt))
        clientOpId?.let { put("clientOpId", it) }
        source?.let { put("source", it) }
    }

    companion object {
        fun fromJson(o: JSONObject) = WearEvent(
            slot = HoopSlot.fromRaw(o.getString("slot")) ?: throw IllegalArgumentException("slot"),
            effectiveAt = BandTime.fromSeconds(o.getDouble("effectiveAt")),
            recordedAt = BandTime.fromSeconds(o.getDouble("recordedAt")),
            clientOpId = o.optStringOrNull("clientOpId"),
            source = o.optStringOrNull("source"))
    }
}

internal fun JSONObject.optStringOrNull(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null
internal fun JSONObject.optInstant(key: String): Instant? = if (has(key) && !isNull(key)) BandTime.fromSeconds(getDouble(key)) else null

/** Pure timeline math. The declaration is the only rule: whoever was declared worn at a
 *  moment owns that moment. Before any declaration the sole bound band (slot A when both
 *  exist) counts as worn since it was bound. */
class WearTimeline(events: List<WearEvent> = emptyList(), val bindings: List<SlotBinding> = emptyList()) {
    val events: List<WearEvent> = events.sortedWith(compareBy<WearEvent> { it.effectiveAt }.thenBy { it.recordedAt })

    override fun equals(other: Any?) = other is WearTimeline && other.events == events && other.bindings == bindings
    override fun hashCode() = events.hashCode() * 31 + bindings.hashCode()

    val isEmpty: Boolean get() = bindings.isEmpty()

    fun binding(slot: HoopSlot): SlotBinding? = bindings.firstOrNull { it.slot == slot }

    /** The slot declared worn at `date`, or the default wearer when nothing was declared. */
    fun wearer(at: Instant): HoopSlot? {
        events.lastOrNull { it.effectiveAt <= at }?.let { return it.slot }
        return bindings.sortedBy { it.slot.raw }.firstOrNull()?.slot
    }

    /** When the current wearer's segment began. */
    fun wearingSince(now: Instant = Instant.now()): Instant? {
        events.lastOrNull { it.effectiveAt <= now }?.let { return it.effectiveAt }
        return wearer(now)?.let { binding(it)?.boundAt }
    }

    /** Appending a declaration. A later event with the same slot as the current wearer is
     *  still recorded: it may move the switch point earlier or later. */
    fun declaring(slot: HoopSlot, at: Instant, recordedAt: Instant, opId: String, source: String = "auto"): WearTimeline {
        val next = events.filter { it.clientOpId != opId }.toMutableList()
        next.add(WearEvent(slot, at, recordedAt, opId, source))
        return WearTimeline(next, bindings)
    }

    /** The declaration in force at `date`, if the person has made one. */
    fun current(at: Instant = Instant.now()): WearEvent? = events.lastOrNull { it.effectiveAt <= at }

    /** Earliest moment a declaration for `slot` may take effect: the band cannot have been
     *  worn for this account before it was bound. */
    fun earliestSwitch(to: HoopSlot): Instant? = binding(to)?.boundAt

    companion object {
        /** Whole user days the standby band has recorded since it was last read, capped by how
         *  many days the firmware keeps. Drives `PENDING n DAYS · SYNC BEFORE …`. */
        fun pendingDays(lastSync: Instant?, boundAt: Instant?, now: Instant, holdsDays: Int?): Int {
            val since = lastSync ?: boundAt ?: return 0
            val days = (BandTime.interval(now, since) / 86_400).toInt()
            return maxOf(0, minOf(days, holdsDays ?: days))
        }

        /** The last calendar day on which the standby band can still be read before its oldest
         *  unsynced day rolls out of the firmware's retention. */
        fun syncDeadline(lastSync: Instant?, boundAt: Instant?, holdsDays: Int?): Instant? {
            val since = lastSync ?: boundAt ?: return null
            if (holdsDays == null) return null
            return BandTime.adding(since, holdsDays * 86_400.0)
        }
    }
}

/** Prefs-backed slot store. `BoundBand` reads the transport slot through here so the
 *  call sites that key readiness, refresh scope and evidence by `BoundBand.identifier`
 *  keep working unchanged.
 *
 *  A band is held by one account (ADR 0003, `20261024150000`), so every key is filed under
 *  the account that bound it. A sign-out leaves that account's bands on the phone for when
 *  it signs back in; the next account starts with none of them and cannot sync, register
 *  or claim a band it never paired. With nobody signed in there are no bands. */
object DeviceSlots {
    private const val bindingsKey = "nb.band.slots.v1"
    private const val transportKey = "nb.band.transportSlot.v1"
    private const val wearingKey = "nb.band.wearingSlot.v1"
    private const val timelineKey = "nb.band.wearEvents.v1"
    private const val pendingOpsKey = "nb.band.wearEvents.pending.v1"
    private val allKeys = listOf(bindingsKey, transportKey, wearingKey, timelineKey, pendingOpsKey)

    /** The signed-in account. The session sets it the moment it changes, before anyone is
     *  told the account changed. */
    @Volatile var owner: String? = null

    private fun key(base: String): String? = owner?.let { "$base.$it" }
    private fun string(base: String): String? = key(base)?.let { BandPrefs.string(it) }
    private fun store(base: String, value: String) { key(base)?.let { BandPrefs.setString(it, value) } }

    /** Builds before one band, one account kept a single set for the whole phone. It
     *  belongs to whoever is signed in when this build first runs; with nobody signed in it
     *  belongs to no one and goes — the server still holds the binding for its account. */
    fun adoptUnownedBindings(owner: String?) {
        for (base in allKeys) {
            val value = BandPrefs.string(base) ?: continue
            if (owner != null && BandPrefs.string("$base.$owner") == null) BandPrefs.setString("$base.$owner", value)
            BandPrefs.remove(base)
        }
    }

    private fun <T> readList(base: String, parse: (JSONObject) -> T): List<T> {
        val raw = string(base) ?: return emptyList()
        return runCatching { JSONArray(raw).let { a -> (0 until a.length()).map { parse(a.getJSONObject(it)) } } }
            .getOrDefault(emptyList())
    }

    var bindings: List<SlotBinding>
        get() = readList(bindingsKey, SlotBinding::fromJson)
        set(value) = store(bindingsKey, JSONArray(value.map { it.toJson() }).toString())

    fun binding(slot: HoopSlot): SlotBinding? = bindings.firstOrNull { it.slot == slot }

    fun set(binding: SlotBinding) {
        val all = bindings.filter { it.slot != binding.slot }.toMutableList()
        all.add(binding)
        bindings = all.sortedBy { it.slot.raw }
    }

    fun remove(slot: HoopSlot) {
        bindings = bindings.filter { it.slot != slot }
        if (transport == slot) transport = bindings.firstOrNull()?.slot ?: HoopSlot.a
        if (wearing == slot) wearing = bindings.firstOrNull()?.slot ?: HoopSlot.a
    }

    /** Which band the SDK link targets right now. */
    var transport: HoopSlot
        get() = HoopSlot.fromRaw(string(transportKey)) ?: HoopSlot.a
        set(value) = store(transportKey, value.raw)

    /** Which band the person declared on the wrist. */
    var wearing: HoopSlot
        get() = HoopSlot.fromRaw(string(wearingKey)) ?: HoopSlot.a
        set(value) = store(wearingKey, value.raw)

    var events: List<WearEvent>
        get() = readList(timelineKey, WearEvent::fromJson)
        set(value) = store(timelineKey, JSONArray(value.map { it.toJson() }).toString())

    /** Declarations made offline, replayed on the next successful network call. */
    var pendingOps: List<WearEvent>
        get() = readList(pendingOpsKey, WearEvent::fromJson)
        set(value) = store(pendingOpsKey, JSONArray(value.map { it.toJson() }).toString())

    val timeline: WearTimeline get() = WearTimeline(events, bindings)

    val hasSecond: Boolean get() = bindings.size >= 2

    /** The signed-in account's bands only; another account's set on this phone stays. */
    fun forgetAll() {
        for (base in allKeys) key(base)?.let { BandPrefs.remove(it) }
    }
}
