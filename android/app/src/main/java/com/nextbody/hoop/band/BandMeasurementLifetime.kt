package com.nextbody.hoop.band

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

/** Owns the native measurement until its cancellation and SDK stop have drained. A
 *  dismissed view can no longer hold the device, and a successor cannot race its stop.
 *  Main-thread confined (Swift @MainActor). */
class BandMeasurementLifetime(
    private val acquire: suspend () -> Unit,
    private val release: suspend () -> Unit,
    private val changed: () -> Unit,
    private val taskScope: CoroutineScope = BandMain.scope,
) {
    private data class Current(val id: UUID, val generation: UUID, val task: Job)

    private var current: Current? = null
    val isBusy: Boolean get() = current != null

    fun start(id: UUID, operation: suspend () -> Unit): Job {
        val previous = current?.task
        previous?.cancel()
        val generation = UUID.randomUUID()
        val task = taskScope.launch {
            withContext(NonCancellable) { previous?.join() }
            if (!isActive) { finish(generation); return@launch }
            withContext(NonCancellable) { acquire() }
            if (isActive) runCatching { operation() }
            // Cancellation still owes release; SDK streams may enqueue their stop on the
            // main queue after the consumer leaves its iterator.
            withContext(NonCancellable) { release() }
            finish(generation)
        }
        current = Current(id, generation, task)
        changed()
        return task
    }

    fun cancel(id: UUID) {
        if (current?.id != id) return
        current?.task?.cancel()
    }

    private fun finish(generation: UUID) {
        if (current?.generation != generation) return
        current = null
        changed()
    }
}
