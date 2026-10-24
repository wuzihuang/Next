package com.nextbody.hoop.services

import android.util.Log

/** Stand-in for BandLog.shared.record in the services layer: logcat only, never a secret. */
object ServiceLog {
    fun record(label: String, error: Throwable) {
        Log.w("NextBody", "$label: ${error::class.java.simpleName} ${error.message?.take(300) ?: ""}")
    }
    fun note(label: String) { Log.i("NextBody", label) }
}
