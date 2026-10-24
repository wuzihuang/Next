package com.nextbody.hoop.band

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import java.time.Instant

/** Requests describe different work, not the screen that happened to ask for it.
 *  How much of a refresh this request is allowed to do.
 *  Light keeps a widget or a timer inside the background budget. Daily repairs
 *  today and yesterday. Full is the manual sync and the first pull after binding. */
enum class BandRefreshTier(val raw: String) { light("light"), daily("daily"), full("full") }

enum class BandRefreshRequest {
    automatic, foreground, resume, background, fullHistory, latest, phoneTool;

    val tier: BandRefreshTier
        get() = when (this) {
            background, foreground -> BandRefreshTier.light
            automatic, resume, phoneTool, latest -> BandRefreshTier.daily
            fullHistory -> BandRefreshTier.full
        }

    internal fun minimumInterval(cadence: Double): Double = when (this) {
        automatic, foreground -> cadence
        // ADR 0026 · coming back to the app asks the wrist again whatever the cadence is set
        // to. The one-minute floor only folds an app switched away and straight back into
        // the pull that just ran; it never lets the device page's EVERY HOUR hold it.
        resume -> minOf(60.0, cadence)
        // A background launch is already spaced by the system. The floor is the server's
        // own five-minute tick: a day settled inside it cannot come back different.
        background -> minOf(300.0, cadence)
        fullHistory, latest, phoneTool -> 0.0
    }

    /** A live receipt seconds old is proof enough that the link is up for a pull the user
     *  did not press for; explicit pulls still walk readiness in full. */
    val reusesRecentLiveReceipt: Boolean get() = this == foreground || this == resume
}

data class BandRefreshResult(
    val status: Status,
    val points: Int = 0,
    val syncedAt: Instant? = null,
) {
    enum class Status(val raw: String) {
        success("success"), partial("partial"), failed("failed"), signedOut("signedOut"),
        consentRequired("consentRequired"), unbound("unbound"),
        busy("busy"), disconnected("disconnected"), throttled("throttled"), cancelled("cancelled");

        companion object { fun fromRaw(raw: String): Status? = entries.firstOrNull { it.raw == raw } }
    }

    companion object {
        /** A day may fail after another day succeeded. Never let the last day hide that. */
        fun combining(results: List<BandRefreshResult>, at: Instant): BandRefreshResult {
            val status = when {
                results.all { it.status == Status.success } -> Status.success
                results.any { it.status == Status.success || it.status == Status.partial } -> Status.partial
                else -> Status.failed
            }
            return BandRefreshResult(status, results.sumOf { it.points }, if (status == Status.success) at else null)
        }
    }
}

/** One process-owned refresh includes readiness, yesterday, today and any requested history.
 *  Cancelling a view's waiter does not cancel work shared by another caller or durable replay.
 *  Main-thread confined (Swift @MainActor): `taskScope` should run on the main dispatcher. */
class BandRefreshCoordinator(
    private val state: () -> State,
    private val now: () -> Instant = { Instant.now() },
    private val taskScope: CoroutineScope = BandMain.scope,
) {
    data class Scope(val account: String, val binding: String)

    data class State(
        val account: String?,
        val binding: String?,
        val consent: Boolean,
        val exclusive: Boolean,
        val connected: Boolean,
    ) {
        val scope: Scope? get() = if (account != null && binding != null) Scope(account, binding) else null

        fun rejection(expected: Scope? = null): BandRefreshResult.Status? {
            if (expected != null && scope != expected) return BandRefreshResult.Status.cancelled
            if (account == null) return BandRefreshResult.Status.signedOut
            if (binding == null) return BandRefreshResult.Status.unbound
            if (!consent) return BandRefreshResult.Status.consentRequired
            if (exclusive) return BandRefreshResult.Status.busy
            return null
        }
    }

    data class HistoryResult(
        /** Null means no historical work was needed; it is not an extra successful day. */
        val result: BandRefreshResult?,
        /** A retry repaired a recent day whose original result would otherwise remain partial. */
        val recoveredDays: Set<Int> = emptySet(),
    )

    /** Production uses the band and existing publication module; tests control their waits. */
    class Work(
        val prepare: suspend (reuseRecentLiveReceipt: Boolean) -> Boolean,
        val day: suspend (daysAgo: Int) -> BandRefreshResult,
        val history: suspend (recentDays: Map<Int, BandRefreshResult>) -> HistoryResult,
        /** Offsets to read, today first. The caller decides whether yesterday is in the list. */
        val days: () -> List<Int> = { listOf(0, 1) },
        val checkHistory: () -> Boolean = { false },
        val finish: suspend () -> Unit = {},
        val completed: suspend (BandRefreshResult) -> Unit = {},
    )

    private class Flight(val scope: Scope, var wantsHistory: Boolean) {
        lateinit var task: Deferred<BandRefreshResult>
    }

    private var current: Flight? = null
    private var lastAttempt: Pair<Scope, Instant>? = null
    private var consentRequest: Pair<Scope, BandRefreshRequest>? = null

    /** Consuming also discards a declined or stale request. It cannot follow a new account. */
    suspend fun refreshAfterConsent(cadence: Double, work: Work): BandRefreshResult? {
        val pending = consentRequest ?: return null
        consentRequest = null
        state().rejection(expected = pending.first)?.let { return BandRefreshResult(it) }
        return refresh(pending.second, cadence, work)
    }

    suspend fun refresh(request: BandRefreshRequest, cadence: Double, work: Work): BandRefreshResult {
        if (!currentCoroutineContext().isActive) return BandRefreshResult(BandRefreshResult.Status.cancelled)
        val initial = state()
        initial.rejection()?.let { rejected ->
            if (rejected == BandRefreshResult.Status.consentRequired && request == BandRefreshRequest.fullHistory) {
                initial.scope?.let { consentRequest = it to request }
            }
            return BandRefreshResult(rejected)
        }
        val scope = initial.scope ?: return BandRefreshResult(BandRefreshResult.Status.signedOut)
        // ADR 0018: a phone tool cannot wait for a disconnected band to come back.
        if (request == BandRefreshRequest.phoneTool && !initial.connected) return BandRefreshResult(BandRefreshResult.Status.disconnected)

        while (true) {
            val flight = current ?: break
            if (flight.scope == scope) {
                if (request == BandRefreshRequest.fullHistory) flight.wantsHistory = true
                val result = flight.task.await()
                return resultForWaiter(result, scope)
            }
            // A different account/binding never receives the old result or overlaps its work.
            flight.task.await()
            if (current === flight) current = null
            state().rejection(expected = scope)?.let { return BandRefreshResult(it) }
            if (!currentCoroutineContext().isActive) return BandRefreshResult(BandRefreshResult.Status.cancelled)
        }
        if (request == BandRefreshRequest.phoneTool && !state().connected) return BandRefreshResult(BandRefreshResult.Status.disconnected)
        val interval = request.minimumInterval(cadence)
        val last = lastAttempt
        if (interval > 0 && last != null && last.first == scope && BandTime.interval(now(), last.second) < interval) {
            return BandRefreshResult(BandRefreshResult.Status.throttled)
        }

        val flight = Flight(scope, request == BandRefreshRequest.fullHistory)
        current = flight
        flight.task = taskScope.async(start = CoroutineStart.LAZY) {
            val result = perform(flight, request.reusesRecentLiveReceipt, work)
            // Await the BLE-cache lifetime cleanup before releasing this shared flight.
            // A different account or new refresh cannot have its cache ended by old work.
            work.finish()
            work.completed(resultForWaiter(result, scope))
            // A failed connection is still an attempt. Automatic callers must not
            // restart preparation on every timer tick; explicit retries bypass cadence.
            if (result.status == BandRefreshResult.Status.success || result.status == BandRefreshResult.Status.partial ||
                result.status == BandRefreshResult.Status.failed || result.status == BandRefreshResult.Status.disconnected) {
                lastAttempt = scope to now()
            }
            if (current === flight) current = null
            result
        }
        flight.task.start()
        val result = flight.task.await()
        return resultForWaiter(result, scope)
    }

    suspend fun waitForCurrentPull() { current?.task?.await() }
    val isIdle: Boolean get() = current == null

    private suspend fun resultForWaiter(result: BandRefreshResult, scope: Scope): BandRefreshResult {
        if (!currentCoroutineContext().isActive) return BandRefreshResult(BandRefreshResult.Status.cancelled, result.points)
        state().rejection(expected = scope)?.let { return BandRefreshResult(it, result.points) }
        return result
    }

    private suspend fun perform(flight: Flight, reuseReceipt: Boolean, work: Work): BandRefreshResult {
        val scope = flight.scope
        state().rejection(expected = scope)?.let { return BandRefreshResult(it) }
        val ready = work.prepare(reuseReceipt)
        state().rejection(expected = scope)?.let { return BandRefreshResult(it) }
        if (!ready) return BandRefreshResult(if (state().connected) BandRefreshResult.Status.failed else BandRefreshResult.Status.disconnected)
        val recentDays = LinkedHashMap<Int, BandRefreshResult>()
        for (offset in work.days()) {
            state().rejection(expected = scope)?.let { return BandRefreshResult(it, recentDays.values.sumOf { r -> r.points }) }
            recentDays[offset] = work.day(offset)
        }
        state().rejection(expected = scope)?.let { return BandRefreshResult(it, recentDays.values.sumOf { r -> r.points }) }
        var history: BandRefreshResult? = null
        if (flight.wantsHistory || work.checkHistory()) {
            val checked = work.history(recentDays.toMap())
            history = checked.result
            for (offset in checked.recoveredDays) {
                val existing = recentDays[offset] ?: continue
                recentDays[offset] = BandRefreshResult(BandRefreshResult.Status.success, existing.points)
            }
        }
        val results = recentDays.values.toList() + listOfNotNull(history)
        state().rejection(expected = scope)?.let { return BandRefreshResult(it, results.sumOf { r -> r.points }) }
        return BandRefreshResult.combining(results, now())
    }
}
