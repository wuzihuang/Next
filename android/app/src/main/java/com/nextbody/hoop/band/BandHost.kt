package com.nextbody.hoop.band

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import java.time.Instant
import com.nextbody.hoop.services.saveCapabilities

/**
 * The band state machines (BandPresence, BandReadiness, BandLiveLifecycle, LiveReadout,
 * BandHealthLightKeeper, DeviceSetStore) read a handful of app services that live outside this
 * package on iOS: ConsentStore, LiveSessionStore (Features/Sport), Repository and Analytics.
 * They reach them through this seam so the band package compiles and tests on its own.
 *
 * TODO(wire): the app installs the real implementations at startup —
 *   BandHost.liveSession = { LiveSessionGate(session != null, opening, cleaningUp) }
 *   BandHost.repository = <adapter over services.Repository>
 * and calls [BandHost.notifyChanged] whenever consent or the live session changes (the Swift
 * code subscribes to their `objectWillChange`).
 */
object BandHost {
    /** `ConsentStore.shared.granted`. */
    @Volatile var consentGranted: () -> Boolean = { com.nextbody.hoop.services.ConsentStore.granted }

    /** `LiveSessionStore.shared` — the workout screen owns the band while a session runs. */
    @Volatile var liveSession: () -> LiveSessionGate = { LiveSessionGate() }

    @Volatile var repository: BandRepositoryPort = ServicesBandRepository

    @Volatile var analytics: suspend (String, Map<String, Any?>) -> Unit =
        { name, props -> com.nextbody.hoop.services.Analytics.track(name, props) }

    private val _changes = MutableSharedFlow<Unit>(extraBufferCapacity = 16)
    /** Consent / live-session `objectWillChange`. */
    val changes: SharedFlow<Unit> = _changes.asSharedFlow()
    fun notifyChanged() { _changes.tryEmit(Unit) }
}

/** What the band layer reads off `LiveSessionStore.shared`. */
data class LiveSessionGate(
    val hasSession: Boolean = false,
    val opening: Boolean = false,
    val cleaningUp: Boolean = false,
)

/**
 * The slice of `Repository.shared` the device set and presence use. Server rows come back as
 * `[String: Any]` on iOS; here a map whose arrays are `List<Map<String, Any?>>`.
 */
/** How the server took a band. A band is held by one account (`20261024150000`). */
enum class DeviceRegistration {
    saved,
    /** Bound to another account; it has to be released there first. */
    ownedElsewhere,
    /** Already this account's, in its other slot. */
    alreadyInSet,
    failed,
}

/** The firmware's MAC, the band's identity on the server — not a phone's alias. */
fun isBandMac(value: String?): Boolean =
    value != null && Regex("^[0-9A-Fa-f]{2}([:-]?[0-9A-Fa-f]{2}){5}$").matches(value)

interface BandRepositoryPort {
    val deviceId: String?
    fun adoptTransportDevice(id: String?)
    /** Only `pairing` may create a row or point one at a different band. */
    suspend fun registerDevice(identity: BandIdentity?, battery: BandBattery?, slot: HoopSlot? = null,
                               pairing: Boolean = false): DeviceRegistration
    suspend fun saveCapabilities(caps: BandCapabilities, deviceId: String, userId: String, holdsDays: Int?): Boolean
    suspend fun releaseDevice(id: String): Map<String, Any?>
    suspend fun loadDeviceSet(): Map<String, Any?>
    suspend fun claimDeviceKey(deviceId: String, clientKey: String): Map<String, Any?>
    suspend fun recordWearEvent(deviceId: String, effectiveAt: Instant?, opId: String): Map<String, Any?>
    suspend fun settleWearStart(opId: String? = null): Map<String, Any?>

    /** No server reachable: every write is refused, every read fails — the pages draw their
     *  local state and error lines, nothing is invented. */
    object None : BandRepositoryPort {
        private var adopted: String? = null
        override val deviceId: String? get() = adopted
        override fun adoptTransportDevice(id: String?) { adopted = id }
        override suspend fun registerDevice(identity: BandIdentity?, battery: BandBattery?, slot: HoopSlot?,
                                            pairing: Boolean): DeviceRegistration = DeviceRegistration.failed
        override suspend fun saveCapabilities(caps: BandCapabilities, deviceId: String, userId: String, holdsDays: Int?): Boolean = false
        override suspend fun releaseDevice(id: String): Map<String, Any?> = throw IllegalStateException("Repository not wired")
        override suspend fun loadDeviceSet(): Map<String, Any?> = throw IllegalStateException("Repository not wired")
        override suspend fun claimDeviceKey(deviceId: String, clientKey: String): Map<String, Any?> = emptyMap()
        override suspend fun recordWearEvent(deviceId: String, effectiveAt: Instant?, opId: String): Map<String, Any?> =
            throw IllegalStateException("Repository not wired")
        override suspend fun settleWearStart(opId: String?): Map<String, Any?> = emptyMap()
    }
}

/** `Repository.shared` as the band layer reads it: server JSON objects become Kotlin maps. */
object ServicesBandRepository : BandRepositoryPort {
    private val r get() = com.nextbody.hoop.services.Repository
    @Suppress("UNCHECKED_CAST")
    private fun map(o: org.json.JSONObject): Map<String, Any?> = (jsonToKotlin(o) as? Map<String, Any?>) ?: emptyMap()

    override val deviceId: String? get() = r.deviceId
    override fun adoptTransportDevice(id: String?) = r.adoptTransportDevice(id)
    override suspend fun registerDevice(identity: BandIdentity?, battery: BandBattery?, slot: HoopSlot?,
                                        pairing: Boolean): DeviceRegistration =
        r.registerDevice(identity, battery, slot, pairing)
    override suspend fun saveCapabilities(caps: BandCapabilities, deviceId: String, userId: String, holdsDays: Int?): Boolean =
        r.saveCapabilities(caps, deviceId, userId, holdsDays)
    override suspend fun releaseDevice(id: String): Map<String, Any?> = map(r.releaseDevice(id))
    override suspend fun loadDeviceSet(): Map<String, Any?> = map(r.loadDeviceSet())
    override suspend fun claimDeviceKey(deviceId: String, clientKey: String): Map<String, Any?> = map(r.claimDeviceKey(deviceId, clientKey))
    override suspend fun recordWearEvent(deviceId: String, effectiveAt: Instant?, opId: String): Map<String, Any?> =
        map(r.recordWearEvent(deviceId, effectiveAt, opId))
    override suspend fun settleWearStart(opId: String?): Map<String, Any?> = map(r.settleWearStart(opId))
}
