package com.nextbody.hoop.services

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContract
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import java.time.LocalDate

/**
 * F5 · Health Connect, read only (the Android stand-in for Apple Health). Height and weight —
 * Health Connect has no record for biological sex or date of birth, so those two always come
 * back empty and the onboarding/profile screens keep their manual entry for them.
 *
 * The consent screen promises never to write, and only READ permissions are requested.
 *
 * UI usage:
 * ```
 * val launcher = rememberLauncherForActivityResult(HealthService.permissionContract()) { granted ->
 *     HealthService.onPermissionResult(granted)
 *     scope.launch { val b = HealthService.readBaseline() … }
 * }
 * if (HealthService.available) launcher.launch(HealthService.readPermissions)
 * else HealthService.openInstallPage(context)
 * ```
 */
object HealthService {
    data class Baseline(
        var sexIsMale: Boolean? = null,
        /** Year/month/day of birth. Never filled by Health Connect. */
        var born: LocalDate? = null,
        var heightCm: Double? = null,
        var weightKg: Double? = null,
        var weightAt: Instant? = null,
    ) {
        val isEmpty: Boolean get() = sexIsMale == null && born == null && heightCm == null && weightKg == null
    }

    data class LatestWeight(val kg: Double, val at: Instant, val uuid: String)

    private const val PROVIDER = "com.google.android.apps.healthdata"
    private var appContext: Context? = null

    fun init(context: Context) { appContext = context.applicationContext }

    private val prefs get() = appContext?.getSharedPreferences("nb", Context.MODE_PRIVATE)

    /** The READ permissions the consent sheet asks for. */
    val readPermissions: Set<String> = setOf(
        HealthPermission.getReadPermission(HeightRecord::class),
        HealthPermission.getReadPermission(WeightRecord::class),
    )

    /** Health Connect SDK status. Not installed / unsupported → false. */
    val available: Boolean
        get() {
            val ctx = appContext ?: return false
            return HealthConnectClient.getSdkStatus(ctx, PROVIDER) == HealthConnectClient.SDK_AVAILABLE
        }

    /** True when the provider can be installed or updated from Play (show an install link). */
    val installable: Boolean
        get() {
            val ctx = appContext ?: return false
            return HealthConnectClient.getSdkStatus(ctx, PROVIDER) ==
                HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED
        }

    /** The system permission sheet, for `rememberLauncherForActivityResult`. */
    fun permissionContract(): ActivityResultContract<Set<String>, Set<String>> =
        PermissionController.createRequestPermissionResultContract()

    /** Record that the sheet was shown — the only thing about the permission iOS could know. */
    fun onPermissionResult(@Suppress("UNUSED_PARAMETER") granted: Set<String>) {
        prefs?.edit()?.putBoolean("nb.health.asked", true)?.apply()
    }

    /**
     * Swift `requestRead()`: on Android the sheet has to be launched by the UI through
     * [permissionContract]. This returns false only when Health Connect is not on the device;
     * when permissions are already held it marks the sheet as asked.
     */
    suspend fun requestRead(): Boolean {
        if (!available) return false
        if (hasPermissions()) prefs?.edit()?.putBoolean("nb.health.asked", true)?.apply()
        return true
    }

    /** True once the sheet has been shown. */
    val asked: Boolean get() = prefs?.getBoolean("nb.health.asked", false) ?: false

    suspend fun hasPermissions(): Boolean {
        val client = client() ?: return false
        return runCatching {
            client.permissionController.getGrantedPermissions().containsAll(readPermissions)
        }.getOrDefault(false)
    }

    private fun client(): HealthConnectClient? {
        val ctx = appContext ?: return null
        if (!available) return null
        return runCatching { HealthConnectClient.getOrCreate(ctx, PROVIDER) }.getOrNull()
    }

    suspend fun readBaseline(): Baseline {
        val b = Baseline()
        if (!available) return b
        latestHeight()?.let { b.heightCm = it.height.inMeters * 100.0 }
        latestWeightRecord()?.let {
            b.weightKg = it.weight.inKilograms
            b.weightAt = it.time
        }
        if (!b.isEmpty) prefs?.edit()?.putLong("nb.health.lastRead", System.currentTimeMillis())?.apply()
        return b
    }

    suspend fun latestWeight(): LatestWeight? {
        val w = latestWeightRecord() ?: return null
        return LatestWeight(w.weight.inKilograms, w.time, w.metadata.id)
    }

    private suspend fun latestHeight(): HeightRecord? {
        val client = client() ?: return null
        return runCatching {
            client.readRecords(ReadRecordsRequest(HeightRecord::class,
                TimeRangeFilter.before(Instant.now()), ascendingOrder = false, pageSize = 1)).records.firstOrNull()
        }.getOrNull()
    }

    private suspend fun latestWeightRecord(): WeightRecord? {
        val client = client() ?: return null
        return runCatching {
            client.readRecords(ReadRecordsRequest(WeightRecord::class,
                TimeRangeFilter.before(Instant.now()), ascendingOrder = false, pageSize = 1)).records.firstOrNull()
        }.getOrNull()
    }

    /** Play Store page for Health Connect when it is missing or out of date. */
    fun openInstallPage(context: Context) {
        val uri = Uri.parse("market://details?id=$PROVIDER&url=healthconnect%3A%2F%2Fonboarding")
        val intent = Intent(Intent.ACTION_VIEW, uri).setPackage("com.android.vending")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }.onFailure {
            runCatching {
                context.startActivity(Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://play.google.com/store/apps/details?id=$PROVIDER"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
    }
}
