package com.nextbody.hoop.services

import android.os.Build
import com.nextbody.hoop.BuildConfig
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.Instant

/**
 * analytics_events. The boards name their events exactly; a different name is a line nobody
 * can check. Queued and posted in batches of four so a tap never costs a request.
 */
object Analytics {
    private val mutex = Mutex()
    private val pending = mutableListOf<MutableMap<String, Any?>>()
    private var flushing = false

    suspend fun track(name: String, props: Map<String, Any?> = emptyMap()) {
        val size = mutex.withLock {
            pending += mutableMapOf(
                "name" to name,
                "props" to props,
                "client_ts" to Iso.string(Instant.now()),
                "app_version" to BuildConfig.VERSION_NAME,
                "device_model" to "Android ${Build.MANUFACTURER} ${Build.MODEL}",
            )
            pending.size
        }
        if (size >= 4) flush()
    }

    /** 11 · DELETE EVERYTHING: a buffer of the deleted account must not post under the next one. */
    suspend fun purge() = mutex.withLock { pending.clear() }

    suspend fun flush() {
        val userId = SupabaseClient.currentUserId ?: return
        val batch = mutex.withLock {
            if (flushing || pending.isEmpty()) return
            flushing = true
            val b = pending.map { it.toMutableMap().also { r -> r["user_id"] = userId } }
            pending.clear()
            b
        }
        // Write-only by design: no select policy, so nothing may be asked for in return.
        val ok = runCatching { SupabaseClient.insert("analytics_events", batch, returning = false) }.isSuccess
        mutex.withLock {
            if (!ok) pending.addAll(0, batch.map { it.toMutableMap().also { r -> r.remove("user_id") } })
            flushing = false
        }
    }
}
