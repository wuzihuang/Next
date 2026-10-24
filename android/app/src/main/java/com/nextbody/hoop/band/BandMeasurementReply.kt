package com.nextbody.hoop.band

import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.cancellation.CancellationException
import kotlin.coroutines.coroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** One native measurement owns its stop and continuation. Every terminal path stops on
 *  main before releasing the caller, and late native replies cannot stop its successor.
 *  Main-thread confined (Swift @MainActor). */
class BandMeasurementReply<Value>(private val taskScope: CoroutineScope = BandMain.scope) {
    class Timeout : Exception("Timeout")

    private var continuation: CancellableContinuation<Value>? = null
    private var stop: (() -> Unit)? = null
    private var timeout: Job? = null
    private var finished = false

    val isPending: Boolean get() = continuation != null && !finished

    suspend fun wait(seconds: Double, start: (complete: (Result<Value>) -> Unit) -> Unit, stop: () -> Unit): Value {
        coroutineContext.ensureActive()
        return suspendCancellableCoroutine { continuation ->
            this.continuation = continuation
            this.stop = stop
            continuation.invokeOnCancellation {
                taskScope.launch { finish(Result.failure(CancellationException())) }
            }
            timeout = taskScope.launch {
                delay((seconds * 1000).toLong())
                finish(Result.failure(Timeout()))
            }
            start { result -> finish(result) }
        }
    }

    private fun finish(result: Result<Value>) {
        val continuation = continuation
        if (finished || continuation == null) return
        finished = true
        this.continuation = null
        timeout?.cancel()
        timeout = null
        val stop = this.stop
        this.stop = null
        stop?.invoke()
        if (continuation.isActive) {
            result.fold({ continuation.resume(it) }, { continuation.resumeWithException(it) })
        }
    }
}
