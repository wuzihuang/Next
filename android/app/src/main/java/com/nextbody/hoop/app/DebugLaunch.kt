package com.nextbody.hoop.app

import android.content.Intent
import com.nextbody.hoop.BuildConfig

/**
 * The Android twin of the iOS `SIMCTL_CHILD_NB_DEBUG_*` walk switches. Debug builds read them
 * from launch-intent extras, e.g.
 * `adb shell am start -n com.nextbody.hoop/.app.MainActivity -e NB_DEBUG_STAGE root -e NB_DEBUG_ROUTE training`.
 * Release builds ignore every one of them.
 */
object DebugLaunch {
    private val values = HashMap<String, String>()

    fun read(intent: Intent?) {
        if (!BuildConfig.DEBUG || intent == null) return
        val extras = intent.extras ?: return
        for (k in extras.keySet()) {
            if (k.startsWith("NB_")) extras.getString(k)?.let { values[k] = it }
        }
    }

    operator fun get(key: String): String? = values[key]

    fun on(key: String): Boolean = values[key] == "1" || values[key] == "true"
}
