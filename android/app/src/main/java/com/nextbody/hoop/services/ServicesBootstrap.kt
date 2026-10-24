package com.nextbody.hoop.services

import android.content.Context
import com.nextbody.hoop.band.BandDomainSyncState
import com.nextbody.hoop.data.AccountPurgePort
import com.nextbody.hoop.data.Ports
import com.nextbody.hoop.data.SupabasePort
import com.nextbody.hoop.l10n.AppLanguage
import com.nextbody.hoop.services.storage.LocalDataStore
import kotlinx.coroutines.launch

/**
 * One call from `Application.onCreate` (after `Defaults.init` and `AppLanguage.init`):
 * initialises the services layer and installs its implementations into [Ports].
 */
object ServicesBootstrap {
    @Volatile private var installed = false

    fun install(context: Context) {
        // The gate writes through the same repository the rest of the app uses.
        com.nextbody.hoop.features.auth.GateRepository.registerDeviceHook = { id, battery -> Repository.registerDevice(id, battery) }
        com.nextbody.hoop.features.auth.GateRepository.saveCapabilitiesHook = { caps, deviceId, userId, days ->
            Repository.saveCapabilities(caps, deviceId, userId, days)
        }
        com.nextbody.hoop.features.auth.GateRepository.recordBodyCompositionHook = { r -> Repository.recordBodyComposition(r) }

        if (installed) return
        installed = true
        val app = context.applicationContext
        SupabaseClient.init(app)
        LocalDataStore.init(app)
        Reachability.init(app)
        ConsentStore.init(app)
        HealthService.init(app)
        MealPhotoStore.init(app)
        AuthLock.init(app)
        NotificationReach.init(app)
        WeighInQueue.init()
        BodyCompositionQueue.init()
        BalanceCheckQueue.init()
        SportEvidenceQueue.init()
        MealQueue.init()

        Ports.supabase = SupabaseAdapter
        Ports.repository = Repository
        Ports.mealQueue = MealQueue
        Ports.weighInQueue = WeighInQueue
        Ports.accountPurge = AccountPurge
        Ports.notificationReach = NotificationReach
        Ports.homeSnapshot = HomeSnapshot
        Ports.widgetGlance = WidgetGlancePublisher

        // AppLanguage.syncProfile: the profile row is the server's fallback locale.
        AppLanguage.onSync = { serverLocale ->
            queueScope.launch {
                val uid = SupabaseClient.currentUserId ?: return@launch
                runCatching {
                    SupabaseClient.patchWhere("profiles", "user_id", uid, mapOf("locale" to serverLocale))
                }
            }
        }
    }

    private object SupabaseAdapter : SupabasePort {
        override fun currentUserIdSnapshot(): String? = SupabaseClient.currentUserIdSnapshot()
        override suspend fun currentUserId(): String? = SupabaseClient.currentUserId
        override suspend fun signedInEmail(): String? = SupabaseClient.signedInEmail()
        override suspend fun restoreSession(): Boolean = SupabaseClient.restoreSession()
        override suspend fun signOut() = SupabaseClient.signOut()
        override val keychainRefreshToken: String? get() = SessionKeychain.refreshToken
        override val keychainUserId: String? get() = SessionKeychain.userId
    }

    /** Plan check / PlanStore belong to the AI feature, disabled on Android: no-ops. */
    private object AccountPurge : AccountPurgePort {
        override fun purgeBandDomainSyncState(userId: String) = BandDomainSyncState.purge(userId)
        override fun purgeBodyCompositionQueue() = BodyCompositionQueue.purge()
        override fun purgeBalanceCheckQueue() = BalanceCheckQueue.purge()
        override fun purgePlanCheckQueue() = Unit
        override fun resetPlanStore() = Unit
        override fun purgePlanStore(owner: String?) = Unit
        override fun purgeConsent() = ConsentStore.purge()
        override suspend fun purgeAnalytics() = Analytics.purge()
    }
}
