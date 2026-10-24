package com.nextbody.hoop.ui

import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * One switch for every motor in the product: the typing stream, the orb's hold, the taps
 * that mark an outcome. ME → PREFERENCES → HAPTICS. On by default; the choice survives
 * launches. Reduce Motion and Battery Saver still silence the texture on their own — this is
 * the person saying so directly, and it wins over both.
 *
 * Call [init] once from the Application / root Activity.
 */
object HapticsSetting {
    private const val KEY = "nb.haptics.enabled"
    private var prefs: SharedPreferences? = null
    private var state by mutableStateOf(true)

    /** Observable from Compose. */
    var enabled: Boolean
        get() = state
        set(value) {
            state = value
            prefs?.edit()?.putBoolean(KEY, value)?.apply()
        }

    fun init(context: Context) {
        val p = context.getSharedPreferences("nb", Context.MODE_PRIVATE)
        prefs = p
        // Absent means never chosen, which is on — not off.
        state = p.getBoolean(KEY, true)
        HapticMotor.init(context)
    }

    fun toggle() {
        enabled = !enabled
    }
}

/** UIKit's impact styles, kept so call sites port 1:1. */
enum class ImpactStyle { Light, Medium, Heavy, Soft, Rigid }

/** UIKit's notification feedback types. */
enum class NotificationFeedback { Success, Warning, Error }

/**
 * The one gate every motor in the product goes through. Call sites never own a Vibrator of
 * their own — that is how a switched-off product kept buzzing on iOS — they call these.
 */
object Haptics {
    val on: Boolean get() = HapticsSetting.enabled

    fun impact(style: ImpactStyle, intensity: Float? = null) {
        if (!on) return
        val (base, sharpness) = when (style) {
            ImpactStyle.Light -> 0.45f to 0.7f
            ImpactStyle.Medium -> 0.7f to 0.5f
            ImpactStyle.Heavy -> 1.0f to 0.3f
            ImpactStyle.Soft -> 0.6f to 0.2f
            ImpactStyle.Rigid -> 0.85f to 0.95f
        }
        HapticMotor.transient(base * (intensity ?: 1f), sharpness)
    }

    fun notification(type: NotificationFeedback) {
        if (!on) return
        HapticMotor.notification(type)
    }

    fun selection() {
        if (!on) return
        HapticMotor.transient(0.35f, 0.95f)
    }
}

/** System motion / power state the haptics and the animations respect. */
object SystemMotion {
    /** Android's Reduce Motion: "Remove animations" sets the animator scale to 0. */
    fun reduceMotion(context: Context): Boolean = runCatching {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }.getOrDefault(false)

    /** Low Power Mode → Battery Saver. */
    fun lowPower(context: Context): Boolean =
        runCatching { context.getSystemService(PowerManager::class.java)?.isPowerSaveMode == true }.getOrDefault(false)
}

/**
 * Core Haptics' transient (intensity, sharpness) on Android's vibrator. API 30+ plays a
 * composition primitive — TICK for thin bright clicks, CLICK for crisp ones, THUD for dull
 * bumps — scaled by intensity; older phones fall back to predefined effects, then a one-shot.
 * Needs `android.permission.VIBRATE` in the manifest; without it every call is a silent no-op.
 */
internal object HapticMotor {
    var appContext: Context? = null
        private set
    private var vibrator: Vibrator? = null

    fun init(context: Context) {
        val ctx = context.applicationContext
        appContext = ctx
        vibrator = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                ctx.getSystemService(VibratorManager::class.java)?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                ctx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        }.getOrNull()
    }

    val supported: Boolean get() = vibrator?.hasVibrator() == true

    /** A rich engine (Core Haptics equivalent): composition primitives are available. */
    val rich: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            vibrator?.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_CLICK) == true

    fun transient(intensity: Float, sharpness: Float) {
        val v = vibrator ?: return
        val i = intensity.coerceIn(0.01f, 1f)
        play(v) {
            if (rich) {
                val primitive = primitiveFor(v, i, sharpness)
                VibrationEffect.startComposition().addPrimitive(primitive, i).compose()
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                VibrationEffect.createPredefined(
                    when {
                        i >= 0.85f || sharpness < 0.35f -> VibrationEffect.EFFECT_HEAVY_CLICK
                        i < 0.45f -> VibrationEffect.EFFECT_TICK
                        else -> VibrationEffect.EFFECT_CLICK
                    },
                )
            } else {
                oneShot(v, (8 + 14 * i).toLong(), i)
            }
        }
    }

    fun notification(type: NotificationFeedback) {
        val v = vibrator ?: return
        play(v) {
            if (rich) {
                val c = VibrationEffect.startComposition()
                when (type) {
                    NotificationFeedback.Success -> c
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.6f)
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 1f, 90)
                    NotificationFeedback.Warning -> c
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 1f)
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.6f, 140)
                    NotificationFeedback.Error -> c
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.8f)
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.8f, 70)
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 1f, 70)
                }
                c.compose()
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && type != NotificationFeedback.Error) {
                VibrationEffect.createPredefined(VibrationEffect.EFFECT_DOUBLE_CLICK)
            } else {
                val timings = when (type) {
                    NotificationFeedback.Success -> longArrayOf(0, 15, 90, 20)
                    NotificationFeedback.Warning -> longArrayOf(0, 20, 140, 15)
                    NotificationFeedback.Error -> longArrayOf(0, 18, 70, 18, 70, 22)
                }
                VibrationEffect.createWaveform(timings, -1)
            }
        }
    }

    private fun primitiveFor(v: Vibrator, intensity: Float, sharpness: Float): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && sharpness < 0.35f &&
            v.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_THUD)
        ) return VibrationEffect.Composition.PRIMITIVE_THUD
        if (sharpness >= 0.85f && intensity < 0.5f &&
            v.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_TICK)
        ) return VibrationEffect.Composition.PRIMITIVE_TICK
        return VibrationEffect.Composition.PRIMITIVE_CLICK
    }

    private fun oneShot(v: Vibrator, ms: Long, intensity: Float): VibrationEffect =
        VibrationEffect.createOneShot(
            ms,
            if (v.hasAmplitudeControl()) (intensity * 255).toInt().coerceIn(1, 255) else VibrationEffect.DEFAULT_AMPLITUDE,
        )

    @SuppressLint("MissingPermission")
    private inline fun play(v: Vibrator, build: () -> VibrationEffect) {
        if (!v.hasVibrator()) return
        runCatching { v.vibrate(build()) }
    }
}
