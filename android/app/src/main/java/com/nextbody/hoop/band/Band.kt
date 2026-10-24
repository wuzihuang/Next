package com.nextbody.hoop.band

import android.content.pm.PackageManager
import android.os.Build
import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.app.DebugLaunch
import com.nextbody.hoop.app.NextBodyApplication

/**
 * One place decides which band the app is talking to, and whether the seeded board runs.
 *
 * Port of Swift's `Band.allowsSeed` gate. On iOS the seeded board (every number in
 * `DataStore`'s seed functions) runs on the simulator only; on Android it runs on an emulator
 * in a debug build, or in a debug build launched with `-e NB_DEBUG_STAGE …` / `-e NB_DEBUG_SEED 1`.
 * A phone must never get the seed dumped onto a real account.
 *
 * ⚠️ Decide it before the first touch of `DataStore`: that object's initial values are chosen
 * from this flag at construction, exactly as the Swift stored-property defaults were.
 */
/** `adb shell setprop debug.nb.seed 0` — read at process start, before any launch extra exists. */
private fun debugProp(key: String): String? = runCatching {
    Class.forName("android.os.SystemProperties").getMethod("get", String::class.java).invoke(null, key) as String
}.getOrNull()?.takeIf { it.isNotEmpty() }

object Band {
    @Volatile
    var allowsSeed: Boolean = BuildConfig.DEBUG && DebugLaunch["NB_DEBUG_SEED"] != "0" && debugProp("debug.nb.seed") != "0" &&
        (isEmulator() || DebugLaunch["NB_DEBUG_STAGE"] != null || DebugLaunch.on("NB_DEBUG_SEED"))

    /** `targetEnvironment(simulator)`. */
    @get:JvmName("isEmulatorFlag") val isEmulator: Boolean get() = isEmulator()

    val live: BandService by lazy {
        when {
            allowsSeed -> MockBand()
            hasBluetoothLE -> VeepooBand()
            else -> DisconnectedBand()
        }
    }

    /** True when the app is driving a real band rather than the simulator's stand-in. */
    val isReal: Boolean get() = !allowsSeed && hasBluetoothLE

    private val hasBluetoothLE: Boolean
        get() = runCatching {
            NextBodyApplication.context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
        }.getOrDefault(false)

    @JvmStatic
    fun isEmulator(): Boolean = runCatching {
        val fingerprint = Build.FINGERPRINT ?: ""
        val model = Build.MODEL ?: ""
        val product = Build.PRODUCT ?: ""
        val hardware = Build.HARDWARE ?: ""
        fingerprint.startsWith("generic") || fingerprint.contains("emulator") ||
            fingerprint.contains("sdk_gphone") || hardware.contains("goldfish") ||
            hardware.contains("ranchu") || model.contains("Emulator") ||
            model.contains("Android SDK built for") || product.contains("sdk") ||
            product.contains("emulator") || product.contains("simulator")
    }.getOrDefault(false)
}
