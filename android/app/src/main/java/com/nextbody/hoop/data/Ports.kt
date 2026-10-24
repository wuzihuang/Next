package com.nextbody.hoop.data

import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.app.DebugLaunch
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BoundBand
import com.nextbody.hoop.band.LaunchFilmPolicy
import com.nextbody.hoop.services.SessionKeychain
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.band.UserDay
import java.util.UUID

// Seams between the shared data layer (DataStore / SessionStore) and the services other
// agents port: Supabase, Repository, the outbox queues, the BLE band, notifications, the
// home snapshot cache and the widget. Every port has a do-nothing default so the seeded
// emulator build runs before those services exist. Each owner replaces its port once, at
// startup (Application.onCreate), e.g. `Ports.repository = Repository`.
//
// Defaults already point at the services that exist (SupabaseClient, SessionKeychain,
// BoundBand, LaunchFilmPolicy). TODO(port): every `Noop…` default is a placeholder; the real
// implementation installs itself here.

/**
 * The launch environment. Swift read `ProcessInfo.processInfo.environment["NB_DEBUG_…"]`;
 * on Android the launcher activity's debug intent extras, read by `app.DebugLaunch`.
 * Release builds always read null.
 */
object DebugEnv {
    operator fun get(key: String): String? = if (BuildConfig.DEBUG) DebugLaunch[key] else null
}

/**
 * DEBUG only · `NB_DEBUG_EDGE=stale` (or autohr · notworn · over · … · restonly) forces one
 * board edge state on an emulator whose data would never produce it, so each can be walked 1:1.
 * (Swift: Services/DebugEdge.swift; `DEBUG && targetEnvironment(simulator)`.)
 */
object DebugEdgeFlag {
    // `Band.allowsSeed` stands in for `targetEnvironment(simulator)`.
    val name: String? get() = if (BuildConfig.DEBUG && Band.allowsSeed) DebugEnv["NB_DEBUG_EDGE"] else null
    fun on(s: String): Boolean = name == s
}

/** SupabaseClient + SessionKeychain + DemoAccount, as far as DataStore / SessionStore reach. */
interface SupabasePort {
    /** `SupabaseClient.currentUserIdSnapshot()` — synchronous, last known user id. */
    fun currentUserIdSnapshot(): String?
    /** `await SupabaseClient.shared.currentUserId`. */
    suspend fun currentUserId(): String?
    suspend fun signedInEmail(): String?
    suspend fun restoreSession(): Boolean
    suspend fun signOut()
    /** `SessionKeychain.refreshToken`. */
    val keychainRefreshToken: String?
    /** `SessionKeychain.userId`. */
    val keychainUserId: String?
}

/** The Repository calls SessionStore and DataStore make. */
interface RepositoryPort {
    suspend fun bootstrapHome(store: DataStore)
    /** `Repository.shared.fetchAccountGate().stage`. */
    suspend fun fetchAccountGateStage(): SessionStore.Stage
    suspend fun flushPendingEvidence()
    fun resetBootstrap()
}

/** MealQueue (durable meal outbox). Methods throw on failure, like the Swift ones. */
interface MealQueuePort {
    /** Returns the id of the submitted meal row. */
    fun createManual(text: String, kcal: Double, day: UserDay, store: DataStore): UUID
    fun enqueueAmend(mealID: UUID, replacement: Map<String, Any?>, source: MealEntry.Source,
                     revisions: Int, ownerUserId: String)
    fun enqueueDelete(mealID: UUID, ownerUserId: String)
    fun purge(ownerUserId: String)
}

interface WeighInQueuePort {
    fun enqueue(weighIn: WeighIn, ownerUserId: String)
    fun purge()
}

/** Everything `SessionStore.purgeAfterAccountDelete()` sweeps besides DataStore. */
interface AccountPurgePort {
    /** `BandDomainSyncState.purge(userId:)`. */
    fun purgeBandDomainSyncState(userId: String)
    fun purgeBodyCompositionQueue()
    fun purgeBalanceCheckQueue()
    fun purgePlanCheckQueue()
    /** `PlanStore.shared.reset()`. */
    fun resetPlanStore()
    /** `PlanStore.purge(owner:)`. */
    fun purgePlanStore(owner: String?)
    /** `ConsentStore.shared.purge()`. */
    fun purgeConsent()
    /** `await Analytics.shared.purge()`. */
    suspend fun purgeAnalytics()
}

/** `BoundBand` (VeepooBand.swift): the identifier of the band this phone is bound to. */
interface BoundBandPort {
    var identifier: String?
    fun forget()
}

/** `Band.live` — the connected band service, as far as SessionStore reaches. */
interface BandLivePort {
    suspend fun disconnect()
}

/** Services/NotificationReach.swift. */
interface NotificationReachPort {
    fun evaluate(store: DataStore)
    fun stampDisconnect(connected: Boolean)
}

/** Services/HomeSnapshot.swift — the account's on-disk copy of the home board. */
interface HomeSnapshotPort {
    fun hydrate(store: DataStore)
    fun removeAll()
}

/** Services/WidgetGlancePublisher.swift. */
interface WidgetGlancePort {
    fun publish(store: DataStore)
    fun clear()
}

/** Services/Band/LaunchFilmPolicy.swift. */
interface LaunchFilmPort {
    fun shouldHoldStill(): Boolean
    /** Seconds since process start. */
    val elapsed: Double
    val lastDurationKey: String
}

object Ports {
    @Volatile var supabase: SupabasePort = SupabaseClientPort
    @Volatile var repository: RepositoryPort = NoopRepository
    @Volatile var mealQueue: MealQueuePort = NoopMealQueue
    @Volatile var weighInQueue: WeighInQueuePort = NoopWeighInQueue
    @Volatile var accountPurge: AccountPurgePort = NoopAccountPurge
    @Volatile var boundBand: BoundBandPort = BoundBandAdapter
    @Volatile var bandLive: BandLivePort = LiveBandPort
    @Volatile var notificationReach: NotificationReachPort = NoopNotificationReach
    @Volatile var homeSnapshot: HomeSnapshotPort = NoopHomeSnapshot
    @Volatile var widgetGlance: WidgetGlancePort = NoopWidgetGlance
    @Volatile var launchFilm: LaunchFilmPort = LaunchFilmPolicyPort

    /** `FlowRehearsal.on` (DEBUG rehearsal walk). */
    @Volatile var flowRehearsalOn: Boolean = false

    /**
     * Swift wrote failures to `AIService.shared.lastError`. AI is disabled on Android
     * (`AIFeature.enabled = false`), so the message goes wherever this sink sends it.
     */
    @Volatile var reportError: (String) -> Unit = { android.util.Log.w("NB", it) }
}

// MARK: - Placeholders (TODO(port): replaced by the real services)

/** The services agent's `SupabaseClient` / `SessionKeychain`. */
object SupabaseClientPort : SupabasePort {
    override fun currentUserIdSnapshot(): String? = SupabaseClient.currentUserIdSnapshot()
    override suspend fun currentUserId(): String? = SupabaseClient.currentUserId
    override suspend fun signedInEmail(): String? = SupabaseClient.signedInEmail()
    override suspend fun restoreSession(): Boolean = SupabaseClient.restoreSession()
    override suspend fun signOut() = SupabaseClient.signOut()
    override val keychainRefreshToken: String? get() = SessionKeychain.refreshToken
    override val keychainUserId: String? get() = SessionKeychain.userId
}

object NoopSupabase : SupabasePort {
    override fun currentUserIdSnapshot(): String? = null
    override suspend fun currentUserId(): String? = null
    override suspend fun signedInEmail(): String? = null
    override suspend fun restoreSession(): Boolean = false
    override suspend fun signOut() {}
    override val keychainRefreshToken: String? get() = null
    override val keychainUserId: String? get() = null
}

object NoopRepository : RepositoryPort {
    override suspend fun bootstrapHome(store: DataStore) {}
    override suspend fun fetchAccountGateStage(): SessionStore.Stage = SessionStore.Stage.gateSignIn
    override suspend fun flushPendingEvidence() {}
    override fun resetBootstrap() {}
}

object NoopMealQueue : MealQueuePort {
    override fun createManual(text: String, kcal: Double, day: UserDay, store: DataStore): UUID =
        throw IllegalStateException("MealQueue not ported yet")
    override fun enqueueAmend(mealID: UUID, replacement: Map<String, Any?>, source: MealEntry.Source,
                              revisions: Int, ownerUserId: String) =
        throw IllegalStateException("MealQueue not ported yet")
    override fun enqueueDelete(mealID: UUID, ownerUserId: String) =
        throw IllegalStateException("MealQueue not ported yet")
    override fun purge(ownerUserId: String) {}
}

object NoopWeighInQueue : WeighInQueuePort {
    override fun enqueue(weighIn: WeighIn, ownerUserId: String) =
        throw IllegalStateException("WeighInQueue not ported yet")
    override fun purge() {}
}

object NoopAccountPurge : AccountPurgePort {
    override fun purgeBandDomainSyncState(userId: String) {}
    override fun purgeBodyCompositionQueue() {}
    override fun purgeBalanceCheckQueue() {}
    override fun purgePlanCheckQueue() {}
    override fun resetPlanStore() {}
    override fun purgePlanStore(owner: String?) {}
    override fun purgeConsent() {}
    override suspend fun purgeAnalytics() {}
}

/** The band agent's `band.BoundBand` (VeepooBand.kt, backed by DeviceSlots). */
object BoundBandAdapter : BoundBandPort {
    override var identifier: String?
        get() = BoundBand.identifier
        set(value) { BoundBand.identifier = value }
    override fun forget() = BoundBand.forget()
}

/** The band agent's `Band.live`. */
object LiveBandPort : BandLivePort {
    override suspend fun disconnect() = Band.live.disconnect()
}

object NoopNotificationReach : NotificationReachPort {
    override fun evaluate(store: DataStore) {}
    override fun stampDisconnect(connected: Boolean) {}
}

object NoopHomeSnapshot : HomeSnapshotPort {
    override fun hydrate(store: DataStore) {}
    override fun removeAll() {}
}

object NoopWidgetGlance : WidgetGlancePort {
    override fun publish(store: DataStore) {}
    override fun clear() {}
}

/** `band.LaunchFilmPolicy`, fed the debug launch switches it inspects. */
object LaunchFilmPolicyPort : LaunchFilmPort {
    override fun shouldHoldStill(): Boolean {
        val env = listOf("NB_DEBUG_STAGE", "NB_DEBUG_ROUTE", "NB_DEBUG_TAKEOVER")
            .mapNotNull { k -> DebugEnv[k]?.let { k to it } }.toMap()
        return LaunchFilmPolicy.shouldHoldStill(env)
    }
    override val elapsed: Double get() = LaunchFilmPolicy.elapsed
    override val lastDurationKey: String get() = LaunchFilmPolicy.lastDurationKey
}
