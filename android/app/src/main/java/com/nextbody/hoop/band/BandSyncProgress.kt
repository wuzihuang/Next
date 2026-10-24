package com.nextbody.hoop.band

import java.util.concurrent.atomic.AtomicReference

/** Fixed workflow segments, not an estimate of remaining time. SDK dump completion is
 *  only one segment; only the shared refresh's terminal success can publish 100%. */
data class BandSyncProgress(
    var stage: Stage = Stage.searching,
    var fraction: Double = 0.0,
    var active: Boolean = false,
    var isHistory: Boolean = false,
    private var filed: Int = 0,
    private var expected: Int = 2,
) {
    enum class Destination(val raw: String) { app("APP"), cloud("CLOUD") }

    enum class Stage {
        searching, connecting, verifying, identity, battery, capabilities,
        reading, saving, updating, finishing, complete, stopped;

        /** Swift `rawValue` — the case name. */
        val raw: String get() = name

        val destination: Destination?
            get() = when (this) {
                saving, updating -> Destination.cloud
                complete, stopped -> null
                else -> Destination.app
            }

        val buttonLabel: String
            get() = when (this) {
                searching -> "SEARCHING"
                connecting -> "CONNECTING"
                verifying -> "VERIFYING"
                identity, battery, capabilities, reading -> "READING"
                saving -> "SAVING"
                updating -> "UPDATING"
                finishing -> "FINISHING"
                complete, stopped -> "SYNC"
            }

        val label: String
            get() = when (this) {
                searching -> "SEARCHING FOR NEXTBODY"
                connecting -> "ESTABLISHING BLUETOOTH"
                verifying -> "VERIFYING DEVICE"
                identity -> "READING DEVICE INFO"
                battery -> "READING BATTERY"
                capabilities -> "PREPARING DEVICE DATA"
                reading -> "SYNCING TO APP"
                saving -> "SYNCING TO CLOUD"
                updating -> "UPDATING CLOUD RESULTS"
                finishing -> "FINISHING SYNC"
                complete -> "SYNC COMPLETE"
                stopped -> "SYNC INCOMPLETE"
            }
    }

    val modeLabel: String get() = if (isHistory) "BACKFILLING HISTORY" else "DAILY SYNC"

    fun beginHistory() { if (active) isHistory = true }

    fun begin() {
        stage = Stage.searching; fraction = 0.0; active = true; isHistory = false; filed = 0; expected = 2
    }

    fun show(next: Stage) {
        if (!active || next == Stage.complete || next == Stage.stopped) return
        stage = next
        val floor = when (next) {
            Stage.searching -> 0.0
            Stage.connecting -> 0.03
            Stage.verifying -> 0.08
            Stage.identity -> 0.12
            Stage.battery -> 0.16
            Stage.capabilities -> 0.20
            Stage.reading -> 0.25
            Stage.finishing -> 0.0
            else -> 0.0
        }
        fraction = maxOf(fraction, floor)
    }

    fun read(value: Double) {
        if (!active || !value.isFinite()) return
        fraction = maxOf(fraction, 0.25 + 0.30 * minOf(1.0, maxOf(0.0, value)))
    }

    fun expect(count: Int) { expected = maxOf(1, maxOf(filed, count)) }

    fun filedDay() {
        if (!active) return
        filed += 1
        fraction = maxOf(fraction, 0.55 + 0.35 * minOf(1.0, filed.toDouble() / expected.toDouble()))
    }

    fun updatingResults() {
        show(Stage.updating)
        if (active) fraction = maxOf(fraction, 0.92)
    }

    fun resultsLoaded() { if (active) fraction = maxOf(fraction, 0.96) }

    fun finish(success: Boolean) {
        if (!active) return
        active = false
        stage = if (success) Stage.complete else Stage.stopped
        if (success) fraction = 1.0
    }
}

/** The background task's expiration handler is not on the main thread. The stage is copied
 *  here whenever the sync moves, so that handler can say where the pull was cut. */
object BandSyncDiagnostics {
    private val stage = AtomicReference("idle")
    fun setStage(value: String) = stage.set(value)
    fun currentStage(): String = stage.get()
}

/** Native history has no stop command. A stalled read must disconnect before its queue
 *  slot is released; continuing progress gets a longer absolute ceiling for backfills. */
class BandSyncDeadline(private val startedAt: Double = uptime()) {
    private val lock = Any()
    private var advancedAt: Double = startedAt
    private var lastKey: String? = null

    fun advance(key: String, now: Double = uptime()) = synchronized(lock) {
        if (key == lastKey) return@synchronized
        lastKey = key
        advancedAt = now
    }

    fun expired(now: Double = uptime()): Boolean = synchronized(lock) {
        now - advancedAt >= 45 || now - startedAt >= 300
    }

    companion object {
        /** ProcessInfo.systemUptime, seconds. */
        fun uptime(): Double = System.nanoTime() / 1_000_000_000.0
    }
}
