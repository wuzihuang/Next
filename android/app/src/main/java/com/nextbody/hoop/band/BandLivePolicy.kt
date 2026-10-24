package com.nextbody.hoop.band

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/** The heart stream follows the screen. The home panel asks for it while someone is
 *  looking; a page that is not looking lets it go; leaving the app ends it.
 *  ⚠️ It used to run whenever the app was *not* active. Nothing consumed those samples —
 *  no store, no widget, no Live Activity — but the band was measuring the whole time the
 *  app was away: the optical LED lit, the battery paying for a number nobody read
 *  (ADR 0023). `.inactive` (a call, Control Center) keeps an open stream rather than
 *  churning it; `.background` never holds one. */
object BandLivePolicy {
    enum class Phase { active, inactive, background }

    data class Owner(val account: String, val binding: String)

    fun shouldRun(phase: Phase, foregroundWanted: Boolean, hasOwner: Boolean,
                  consent: Boolean, connected: Boolean, exclusive: Boolean): Boolean =
        hasOwner && consent && connected && !exclusive && foregroundWanted && phase != Phase.background
}

/** Keep the old task until its cancellation cleanup completes. New eligibility may change
 *  repeatedly during that await; only the latest request is started afterwards.
 *  Main-thread confined (Swift @MainActor). */
class BandLiveTaskOwner(private val taskScope: CoroutineScope = BandMain.scope) {
    private var task: Job? = null
    private var taskOwner: BandLivePolicy.Owner? = null
    private var desired: BandLivePolicy.Owner? = null
    private var operation: (suspend () -> Unit)? = null
    private var stopping = false
    private var generation: Long = 0

    fun update(owner: BandLivePolicy.Owner?, operation: suspend () -> Unit) {
        desired = owner
        this.operation = operation
        if (task != null) {
            if (owner != taskOwner || stopping) {
                stopping = true
                task?.cancel()
            }
            return
        }
        launchIfWanted()
    }

    private fun launchIfWanted() {
        val desired = desired ?: return
        val operation = operation ?: return
        generation += 1
        val token = generation
        taskOwner = desired
        stopping = false
        val job = taskScope.launch(start = kotlinx.coroutines.CoroutineStart.LAZY) {
            try {
                operation()
            } finally {
                // Swift's Task body runs past cancellation; the cleanup must too.
                if (generation == token) {
                    val restart = stopping
                    task = null
                    taskOwner = null
                    stopping = false
                    if (restart) launchIfWanted()
                }
            }
        }
        task = job
        job.start()
    }
}
