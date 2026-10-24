package com.nextbody.hoop.band

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.UUID
import kotlin.coroutines.resume

/** One short BLE transaction at a time. An account/binding change cannot share the old
 *  result or start competing commands; callers still validate their scope after waiting.
 *  Main-thread confined (Swift @MainActor). */
class BandReadinessFlight(private val taskScope: CoroutineScope = BandMain.scope) {
    private data class Current(val key: String, val id: UUID, val task: Deferred<Boolean>)

    private var current: Current? = null

    suspend fun run(key: String, operation: suspend () -> Boolean): Boolean {
        val active = current
        if (active != null) {
            val result = active.task.await()
            if (active.key == key) return result
            if (current?.id == active.id) current = null
            return run(key, operation)
        }
        val id = UUID.randomUUID()
        val task = taskScope.async(start = CoroutineStart.LAZY) { operation() }
        current = Current(key, id, task)
        task.start()
        val result = task.await()
        if (current?.id == id) current = null
        return result
    }
}

/** A timestamp alone is insufficient: only this owner and this verified link may reuse it. */
object BandReadinessReceiptPolicy {
    fun canReuse(requested: Boolean, connected: Boolean, exclusive: Boolean,
                 ownerMatches: Boolean, age: Double, maxAge: Double = 3.0): Boolean =
        requested && connected && !exclusive && ownerMatches && age.isFinite() && age >= 0 && age <= maxAge
}

/** A takeover closes admission before waiting here. Only native BLE work holds a lease;
 *  network uploads and historical orchestration never delay the sensor handoff.
 *  Main-thread confined (Swift @MainActor). */
class BandNativeDrain {
    private var active = 0
    private val waiters = mutableListOf<kotlinx.coroutines.CancellableContinuation<Unit>>()

    val isIdle: Boolean get() = active == 0

    fun begin() { active += 1 }

    fun end() {
        check(active > 0)
        active -= 1
        if (active != 0) return
        val released = waiters.toList()
        waiters.clear()
        for (waiter in released) if (waiter.isActive) waiter.resume(Unit)
    }

    suspend fun waitUntilIdle() {
        if (active <= 0) return
        suspendCancellableCoroutine { waiters.add(it) }
    }
}
