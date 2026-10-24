package com.nextbody.hoop.band

import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import java.util.UUID
import kotlin.coroutines.coroutineContext

/** Owns the radio from BEFORE scanning until activation/scan cleanup completes.
 *  A timeout abandons only the waiter, never an in-flight native command.
 *  Main-thread confined (Swift @MainActor). */
class DeviceActivationGate {
    var owner: UUID? = null
        private set
    val isHeld: Boolean get() = owner != null

    /** `timeoutSeconds` is Swift's `Duration` (default 20 s). */
    suspend fun prepare(owner: UUID, timeoutSeconds: Double = 20.0, acquired: () -> Unit = {}, idle: () -> Boolean) {
        if (this.owner != null && this.owner != owner) throw Failure.Busy
        this.owner = owner
        acquired()
        try {
            val deadline = System.nanoTime() + (timeoutSeconds * 1_000_000_000).toLong()
            while (!idle()) {
                coroutineContext.ensureActive()
                if (System.nanoTime() >= deadline) throw Failure.Busy
                delay(50)
            }
            coroutineContext.ensureActive()
        } catch (error: Throwable) {
            release(owner)
            throw error
        }
    }

    fun release(owner: UUID) {
        if (this.owner == owner) this.owner = null
    }

    sealed class Failure : Exception() {
        data object Busy : Failure() { private fun readResolve(): Any = Busy }

        /** Swift `.busy`. */
        companion object { fun busy(): Failure = Busy }
    }
}
