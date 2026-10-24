package com.nextbody.hoop.band

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * F3 §06 · THE QUEUE. Five boards each wrote a version of this; here it exists once.
 *
 * One in-process serial queue. The number of native commands in flight is always exactly
 * one — the band's protocol cannot interleave, and a second command sent while the first is
 * still answering does not fail loudly, it corrupts the first one's reply.
 *
 * P0 is something the user just pressed, P1 is a page that opened, P2 is background sync.
 * A higher priority jumps to the head of the queue but never interrupts the command already
 * in flight: cancelling mid-command is what leaves the band in a state nothing can read.
 *
 * (Swift `actor` → a lock-guarded class; jobs run one at a time on a background coroutine.)
 */
class HoopQueue {
    enum class Priority(val raw: Int) {
        /** The user pressed something: start a test, write a setting, start a firmware update. */
        p0(0),
        /** A page opened: read version, read capabilities, list settings, read a day. */
        p1(1),
        /** Background: pulling origin data. */
        p2(2);
    }

    class Job(
        val priority: Priority,
        val name: String,
        val run: suspend () -> Unit,
    ) {
        val id: UUID = UUID.randomUUID()
    }

    private val lock = Any()
    private val pending = ArrayList<Job>()
    private var inFlight: Job? = null
    private var draining = false
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** The name is what shows up in a sync_runs row when something goes wrong. */
    fun enqueue(name: String, priority: Priority = Priority.p1, run: suspend () -> Unit) {
        val job = Job(priority, name, run)
        synchronized(lock) {
            // Stable insert: same priority keeps arrival order, higher priority goes in front of
            // everything of lower priority but behind its own peers.
            val index = pending.indexOfFirst { it.priority.raw > priority.raw }.let { if (it < 0) pending.size else it }
            pending.add(index, job)
        }
        scope.launch { drain() }
    }

    /** Enqueue and wait for this one job's result. */
    suspend fun <T> run(name: String, priority: Priority = Priority.p1, body: suspend () -> T): T {
        val result = CompletableDeferred<T>()
        enqueue(name, priority) {
            try { result.complete(body()) } catch (e: Throwable) { result.completeExceptionally(e) }
        }
        return result.await()
    }

    val depth: Int get() = synchronized(lock) { pending.size + (if (inFlight == null) 0 else 1) }
    val current: String? get() = synchronized(lock) { inFlight?.name }

    /** Dropping everything that has not started. The one in flight is left alone on purpose. */
    fun cancelPending() = synchronized(lock) { pending.clear() }

    private suspend fun drain() {
        synchronized(lock) {
            if (draining) return
            draining = true
        }
        try {
            while (true) {
                val job = synchronized(lock) {
                    if (pending.isEmpty()) null else pending.removeAt(0).also { inFlight = it }
                } ?: break
                try {
                    job.run()
                } catch (e: Throwable) {
                    // A failed command does not stop the queue: the next page still needs its read.
                    BandLog.shared.record(job.name, error = e)
                }
                synchronized(lock) { inFlight = null }
            }
        } finally {
            synchronized(lock) { draining = false }
        }
        // An enqueue that lost the race with `draining = false` is picked up here.
        if (synchronized(lock) { pending.isNotEmpty() }) drain()
    }
}

/** Enough of a trail to answer "why did the band go quiet" without a debugger. */
class BandLog {
    companion object {
        val shared: BandLog = BandLog()
    }

    private val trail = ArrayList<String>()
    val lines: List<String> get() = synchronized(trail) { trail.toList() }

    fun record(name: String, error: Throwable? = null) {
        val stamp = java.time.Instant.now().truncatedTo(java.time.temporal.ChronoUnit.SECONDS).toString()
        val line = stamp + " " + name + (error?.let { " → " + it.localizedDescription } ?: "")
        synchronized(trail) {
            trail.add(line)
            if (trail.size > 400) trail.subList(0, trail.size - 400).clear()
        }
        if (error != null) BandTrace.error(line) else BandTrace.debug(line)
    }
}
