package com.nextbody.hoop.band

import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import java.util.UUID
import kotlin.math.pow

/** A start attempt has its own identity even when the next workout uses the same mode. */
data class SportSessionLifetime(
    val account: String?,
    val binding: String?,
    private val id: UUID = UUID.randomUUID(),
) {
    fun accepts(current: SportSessionLifetime?, account: String?, binding: String?, consent: Boolean): Boolean =
        this == current && consent && this.account == account && this.binding == binding
}

/** Cancellation does not retract an SDK command already on the wire. Finish its callback
 *  before issuing final stop, then let a subsequent session acquire the band. */
object SportSessionTaskFence {
    suspend fun cancelAndWait(opening: Job?, reading: Job?) {
        opening?.cancel()
        reading?.cancel()
        opening?.join()
        reading?.join()
    }

    /** Once stop has cancelled collection it must either retain its original lifetime
     *  and proceed, or fully retire that lifetime. Losing permission cannot leave a
     *  half-stopped session, and an old waiter cannot retire a replacement session. */
    suspend fun prepareStop(
        owner: SportSessionLifetime,
        current: () -> SportSessionLifetime?,
        authorized: () -> Boolean,
        opening: Job?, reading: Job?,
        quiesce: suspend () -> Unit,
        retire: suspend () -> Unit,
    ): Boolean {
        cancelAndWait(opening, reading)
        if (current() != owner) return false
        quiesce()
        if (current() != owner) return false
        if (!authorized()) { retire(); return false }
        return true
    }
}

/** Retry the bound device without turning a missing wrist into a tight scan loop. */
object SportReconnectPolicy {
    fun delay(failures: Int): Double = minOf(30.0, 3 * 2.0.pow(minOf(4, maxOf(0, failures - 1)).toDouble()))
}

/** Only an issued command with an uncertain/successful result can need final close.
 *  A definitive busy reply means this start did not acquire the sport mode. */
enum class SportStartDisposition {
    notIssued, issued, busy, opened;

    val needsCleanup: Boolean get() = this == issued || this == opened

    companion object {
        fun shouldRetryBusy(previousRetries: Int): Boolean = previousRetries == 0
        fun canJoin(observedRunState: Int?): Boolean = observedRunState == 1
    }
}

object SportStartRetry {
    suspend fun perform(
        settle: suspend () -> Unit,
        start: suspend () -> Unit,
        isBusy: (Throwable) -> Boolean,
        disposition: (SportStartDisposition) -> Unit,
    ) {
        var retries = 0
        while (true) {
            settle()
            currentCoroutineContext().ensureActive()
            disposition(SportStartDisposition.issued)
            try {
                start()
                disposition(SportStartDisposition.opened)
                return
            } catch (error: Throwable) {
                if (error is kotlinx.coroutines.CancellationException || !isBusy(error)) throw error
                disposition(SportStartDisposition.busy)
                if (!SportStartDisposition.shouldRetryBusy(retries) || !currentCoroutineContext().isActive) throw error
                retries += 1
            }
        }
    }
}
