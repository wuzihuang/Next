package com.nextbody.hoop.band

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException

/** Regular refreshes share one publication. Finishing a sport needs a new drain after
 *  that flight: its outbox snapshot may predate the last observed interval.
 *  Main-thread confined (Swift @MainActor). */
class EvidencePublicationDrain(private val taskScope: CoroutineScope = BandMain.scope) {
    private class Flight(val id: UUID, val task: Job)

    private var flight: Flight? = null

    /** A band refresh must finish the foreground publisher's existing settlement
     *  before uploading new facts to the same account's calculation lock. */
    suspend fun waitForCurrent() { flight?.task?.join() }

    fun cancel() {
        flight?.task?.cancel()
        flight = null
    }

    suspend fun run(afterCurrent: Boolean = false, authorized: () -> Boolean, publish: suspend () -> Unit) {
        if (!authorized() || !currentCoroutineContext().isActive) return
        val running = flight
        if (running != null) {
            running.task.join()
            if (!afterCurrent || !authorized() || !currentCoroutineContext().isActive) return
            // The waiting caller may resume before the original caller clears its slot.
            if (flight?.id == running.id) flight = null
            run(authorized = authorized, publish = publish)
            return
        }
        val id = UUID.randomUUID()
        val task = taskScope.launch {
            if (!authorized() || !isActive) return@launch
            publish()
        }
        flight = Flight(id, task)
        try {
            task.join()
        } catch (cancelled: CancellationException) {
            // withTaskCancellationHandler { … } onCancel: { task.cancel() }
            task.cancel()
            withContext(NonCancellable) { if (flight?.id == id) flight = null }
            throw cancelled
        }
        if (flight?.id == id) flight = null
    }
}
