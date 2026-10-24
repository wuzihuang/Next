package com.nextbody.hoop.services

import android.content.Context
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.WidgetGlancePort
import java.time.Instant

/**
 * iOS writes the home-strip numbers into the App Group its WidgetKit widgets read. The Android
 * port has no home-screen widget, so publishing is a no-op (kept so call sites stay 1:1).
 */
object WidgetGlancePublisher : WidgetGlancePort {
    override fun publish(store: DataStore) = publish(store, null)
    @Suppress("UNUSED_PARAMETER")
    fun publish(store: DataStore, numbersAt: Instant? = null, now: Instant = Instant.now()) = Unit
    override fun clear() = Unit
}

/**
 * ADR 0026 · the half-hourly BGAppRefreshTask exists only to keep the iOS widget fresh while the
 * app is away. With no Android widget there is nothing to keep fresh, so this is a no-op:
 * the app refreshes on launch/foreground as before. (A JobScheduler job can be added here
 * if an Android widget is ever built.)
 */
object BackgroundRefresh {
    @Suppress("UNUSED_PARAMETER")
    fun register(context: Context) = Unit
    fun scheduleIfWidgetPlaced() = Unit
}
