package com.nextbody.hoop.band

import com.nextbody.hoop.services.SupabaseFailure

import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.util.Base64
import java.util.UUID

/** Cold-start rules for Home numbers. The screen must paint last-known same-day values
 *  immediately, then replace them with the server's current row — not wait for 182 days
 *  of history or a BLE pull before anything is visible. */
object HomeLaunchPolicy {
    /** Access tokens this close to expiry are treated as gone; refresh instead of racing
     *  a 401 on the first Home read. */
    const val accessTokenLeeway: Double = 15.0

    /** Home's first paint only needs today plus the previous user day (rolling 24 h vitals). */
    const val fastLoadLookbackDays = 1

    /** A snapshot taken on a different user day is yesterday's score, not today's. */
    fun shouldPaintToday(snapshotDayKey: String, currentDayKey: String): Boolean = snapshotDayKey == currentDayKey

    fun isAccessTokenUsable(token: String, now: Instant = Instant.now()): Boolean {
        val expiry = jwtExpiry(token) ?: return false
        return BandTime.interval(expiry, now) > accessTokenLeeway
    }

    fun jwtExpiry(token: String): Instant? = jwtNumber(token, "exp")?.let { BandTime.fromSeconds(it) }

    fun jwtSubject(token: String): String? = jwtPayload(token)?.get("sub") as? String

    fun jwtEmail(token: String): String? = jwtPayload(token)?.get("email") as? String

    fun jwtPayload(token: String): Map<String, Any?>? {
        val parts = token.split(".")
        if (parts.size < 2) return null
        val encoded = StringBuilder(parts[1].replace("-", "+").replace("_", "/"))
        while (encoded.length % 4 != 0) encoded.append("=")
        val data = runCatching { Base64.getDecoder().decode(encoded.toString()) }.getOrNull() ?: return null
        val json = runCatching { JSONObject(String(data, Charsets.UTF_8)) }.getOrNull() ?: return null
        return json.keys().asSequence().associateWith { key -> json.opt(key).takeUnless { it == JSONObject.NULL } }
    }

    /** PostgREST `in.(id,id)` — null when there is nothing to ask, so a miss does not
     *  become an unfiltered table dump. */
    fun postgrestIn(ids: List<String>): String? {
        val clean = ids.filter { it.isNotEmpty() }
        if (clean.isEmpty()) return null
        return "in.(${clean.joinToString(",")})"
    }

    private fun jwtNumber(token: String, key: String): Double? =
        (jwtPayload(token)?.get(key) as? Number)?.toDouble()

    fun acceptsRead(account: String?, currentAccount: String?, generation: Long, currentGeneration: Long): Boolean =
        account != null && account == currentAccount && generation == currentGeneration

    /** Legacy rows lack a revision until first settlement after upgrade. A missing
     *  revision is unknown freshness, never proof that a cached row is current. */
    fun shouldRefreshSummary(revision: String?, cachedRevision: String?, hasCachedRow: Boolean): Boolean {
        if (revision == null) return true
        return !hasCachedRow || revision != cachedRevision
    }

    /** Upload receipts confirm facts, not publication. Old dirty or unversioned results
     *  still require settlement even after the local outbox has become empty. */
    fun needsEvidenceSettlement(pending: List<Boolean?>?): Boolean {
        if (pending.isNullOrEmpty()) return true
        return pending.any { it != false }
    }

    /** Issue #21 · Body Battery and the sleep score keep moving while the phone is in a
     *  pocket: the reserve drains against the clock, so today's row goes stale without a
     *  single new fact arriving and `pending` stays false. The hourly cron was the only
     *  thing that moved it, which is why opening the app could show an hour-old number.
     *  Coming forward now always asks for today, whether or not new evidence exists.
     *
     *  The floor is the server's own calculation tick: nb.recompute_range bins `now` into
     *  five minutes and skips a day already settled at that tick, so asking more often
     *  than this cannot produce a different number — it can only cost a round trip. */
    const val foregroundSettleInterval: Double = 300.0

    fun shouldSettleOnForeground(pending: List<Boolean?>?, lastSettledAt: Instant?,
                                 bandRefreshActive: Boolean = false, now: Instant = Instant.now()): Boolean {
        // The refresh settles its uploaded window itself. A second settlement here
        // would hold calculation_work while the refresh is still publishing facts.
        if (bandRefreshActive) return false
        if (needsEvidenceSettlement(pending)) return true
        if (lastSettledAt == null) return true
        return BandTime.interval(now, lastSettledAt) >= foregroundSettleInterval
    }
}

/** Shared connection/history and display decisions for automatic and explicit pulls. */
object BandSyncPolicy {
    const val connectionAttempts = 3

    fun retriesSettle(error: Throwable): Boolean = error is SupabaseFailure.Transport

    fun matchesBoundDevice(discovered: String, sdkAddress: String? = null,
                           bound: String?, boundPeripheral: String? = null): Boolean {
        if (bound.isNullOrEmpty()) return false
        val matchesBinding = listOfNotNull(discovered, sdkAddress).any { it.isNotEmpty() && it.equals(bound, ignoreCase = true) }
        if (matchesBinding || boundPeripheral.isNullOrEmpty()) return matchesBinding
        return discovered.isNotEmpty() && discovered.equals(boundPeripheral, ignoreCase = true)
    }

    /** An SDK address may become a MAC after verification. Recover its local peripheral
     *  only when the SDK's remembered address proves it belongs to the existing binding. */
    fun legacyPeripheralIdentifier(bound: String?, rememberedAddress: String?, rememberedPeripheral: String?): String? {
        if (bound.isNullOrEmpty() || rememberedAddress.isNullOrEmpty() ||
            !rememberedAddress.equals(bound, ignoreCase = true) || rememberedPeripheral == null) return null
        val uuid = runCatching { UUID.fromString(rememberedPeripheral) }.getOrNull() ?: return null
        if (rememberedPeripheral.length != 36) return null
        // Swift `uuid.uuidString` is upper-case.
        return uuid.toString().uppercase()
    }

    fun historyDays(retained: Int?): Int {
        val held = retained?.takeIf { it > 0 } ?: 7
        return maxOf(0, minOf(held, 366) - 1)
    }

    fun historyDayOffsets(retained: Int?, cachedOffsets: List<Int>): List<Int> {
        val days = historyDays(retained)
        val retainedOffsets = if (days > 0) (1..days).toList() else emptyList()
        return (retainedOffsets + cachedOffsets.filter { it in 1..6 }).toSet().sorted()
    }

    /** SDK offsets follow the current calendar day; refresh offsets follow its captured
     *  day. Recent failures override older receipts, while recent successes are reused. */
    fun historyOffsetsToSync(available: List<Int>, elapsedDays: Int = 0,
                             recentDays: Map<Int, BandRefreshResult.Status>,
                             needsSync: (Int) -> Boolean): List<Int> =
        available.map { it - elapsedDays }.filter { offset ->
            if (offset <= 0) return@filter false
            val status = recentDays[offset]
            if (status != null) status != BandRefreshResult.Status.success else needsSync(offset)
        }

    /** Daily historical verification is per account/device/day through its persisted
     *  domain receipts. Missing domains and failed uploads remain repair work even after
     *  other dates passed their daily audit. Oxygen owns its recorded overnight window.
     *  `requireAcknowledgedToday` is the full sync's once-a-day audit. A daily repair
     *  leaves a complete acknowledgement in place until it fails or loses coverage. */
    fun needsHistorySync(states: List<BandDomainSyncState>, outcome: BandRefreshResult.Status?,
                         start: Instant, end: Instant, now: Instant, zone: ZoneId = ZoneId.systemDefault(),
                         requireAcknowledgedToday: Boolean = true): Boolean {
        if (!(outcome == BandRefreshResult.Status.success && start < end && end <= now)) return true
        val expected = listOf("origin", "hrv", "temperature", "rr", "sleep", "oxygen", "response")
        return expected.any { domain ->
            val state = states.firstOrNull { it.domain == domain } ?: return@any true
            val okStatus = state.status == BandDomainReadStatus.complete || state.status == BandDomainReadStatus.notCollected ||
                state.status == BandDomainReadStatus.unsupported
            val acknowledgedStart = state.acknowledgedStart
            val acknowledgedEnd = state.acknowledgedEnd
            if (!okStatus || state.repairStart != null || state.repairEnd != null || state.attemptedAt > now ||
                (requireAcknowledgedToday && !BandTime.sameDay(state.attemptedAt, now, zone)) ||
                acknowledgedStart == null || acknowledgedEnd == null || acknowledgedStart >= acknowledgedEnd) return@any true
            domain != "oxygen" && (acknowledgedStart > start || acknowledgedEnd < end)
        }
    }

    /** Today is always first. Light reads yesterday only while the night may still be open,
     *  or when yesterday has not been confirmed. */
    fun refreshIncludesYesterday(tier: BandRefreshTier, now: Instant, yesterdayConfirmed: Boolean,
                                 zone: ZoneId = ZoneId.systemDefault()): Boolean = when (tier) {
        BandRefreshTier.daily, BandRefreshTier.full -> true
        BandRefreshTier.light -> if (!yesterdayConfirmed) true else now.atZone(zone).hour < 4
    }

    fun refreshDayOffsets(tier: BandRefreshTier, includesYesterday: Boolean): List<Int> = when (tier) {
        BandRefreshTier.light -> if (includesYesterday) listOf(0, 1) else listOf(0)
        BandRefreshTier.daily, BandRefreshTier.full -> listOf(0, 1)
    }

    /** HRV, oxygen and temperature dumps walk every day the band still holds.
     *  A full sync always runs them. Any other sync runs one when that night is still
     *  unconfirmed, or when this connection has not finished the command in the last half hour. */
    const val auxiliaryReuse: Double = 30.0 * 60

    fun needsAuxiliaryDump(nightConfirmed: Boolean, lastCompletedAt: Instant?, now: Instant,
                           tier: BandRefreshTier, reuse: Double = auxiliaryReuse): Boolean {
        if (tier == BandRefreshTier.full || !nightConfirmed) return true
        if (lastCompletedAt == null || lastCompletedAt > now) return true
        return BandTime.interval(now, lastCompletedAt) >= reuse
    }

    /** A dump reused from earlier on this link still holds every calendar day that ended before
     *  it finished. Skipping such a day kept its old receipt, so the daily audit never passed
     *  and every launch walked the retained week again. */
    fun reusedDumpCoversDay(dayOffset: Int, completedAt: Instant?, now: Instant,
                            zone: ZoneId = ZoneId.systemDefault()): Boolean {
        if (dayOffset <= 0 || completedAt == null) return false
        val dayEnd = BandTime.addingDays(BandTime.startOfDay(now, zone), (1 - dayOffset).toLong(), zone)
        return completedAt >= dayEnd
    }

    /** A domain skipped this refresh keeps the acknowledgement it already has.
     *  Publishing an empty read would mark it not collected. */
    fun keepingSkippedDomains(published: List<BandDomainSyncState>, previous: List<BandDomainSyncState>,
                              skipped: Set<String>): List<BandDomainSyncState> {
        val result = published.toMutableList()
        for (name in skipped.sorted()) {
            if (result.any { it.domain == name }) continue
            previous.firstOrNull { it.domain == name }?.let { result.add(it) }
        }
        return result
    }

    /** Wrist facts only. Server settlement writes derived scores later and cannot
     *  turn a complete reading into a failed one; doing so left SYNC as partial,
     *  forced the next pull to re-read the week, and showed
     *  "Some readings could not sync" after every successful upload. */
    fun dayStatus(pagesReturned: Int, wanted: Int, auxiliaryUploaded: Boolean): BandRefreshResult.Status =
        if (pagesReturned == wanted && auxiliaryUploaded) BandRefreshResult.Status.success else BandRefreshResult.Status.partial

    fun header(activity: String, connected: Boolean, live: String): String {
        if (activity == "connecting") return "CONNECTING"
        if (activity == "syncing") return "SYNCING…"
        if (!connected) return "OFFLINE"
        return when (live) {
            "live", "stress" -> "LIVE"
            "reaching" -> "REACHING"
            "noContact" -> "NO CONTACT"
            else -> "STANDBY"
        }
    }

    /** SDK history dump: `day` is the 1-based day being read, `percent` 0…100 of that day.
     *  Day 4 at 50% of 7 is 3.5/7, not 4/7 and not 1.0 after the first finished day. */
    fun readFraction(day: Int, of: Int, percent: Int): Double {
        if (of <= 0) return 0.0
        val clampedPercent = minOf(maxOf(percent, 0), 100)
        val completed = maxOf(day - 1, 0)
        return minOf(1.0, (completed.toDouble() + clampedPercent / 100.0) / of.toDouble())
    }

    /** Counting for the device-page bar. The BLE dump owns the numbers once it speaks;
     *  filing steps after that must not snap the bar to 100% or rewind it.
     *  Value type in Swift: mutate a `copy()` and reassign when held in observable state. */
    data class ReadProgress(
        var done: Int = 0,
        var total: Int = 0,
        var percent: Int = 0,
        private var deviceOwned: Boolean = false,
    ) {
        val fraction: Double get() = readFraction(day = done + 1, of = total, percent = percent)

        private fun reset() { done = 0; total = 0; percent = 0; deviceOwned = false }
        fun begin() = reset()
        fun stop() = reset()

        fun expect(total: Int) {
            if (deviceOwned) return
            this.total = maxOf(this.total, maxOf(total, done))
        }

        fun step() {
            if (deviceOwned) return
            percent = 0
            done += 1
            total = maxOf(total, done)
        }

        /** How far through the current day's own work, when the device dump is not
         *  driving. A pull that reuses the cached dump has nothing else to move the bar:
         *  without this it steps once per day and reads as three jumps. */
        fun within(percent: Int) {
            if (deviceOwned || total <= 0) return
            this.percent = maxOf(this.percent, minOf(maxOf(percent, 0), 100))
        }

        /** The seed is the band's retained-day count; the plan is what will actually be
         *  read. Correcting it downwards moves the bar forward, and stops a pull from
         *  ending at two thirds because the other days did not need reading. */
        fun revise(total: Int) {
            if (deviceOwned) return
            this.total = maxOf(done, maxOf(total, 1))
        }

        fun reportRead(day: Int, of: Int, percent: Int) {
            val next = readFraction(day, of, percent)
            if (deviceOwned && next + 0.0005 < fraction) return
            deviceOwned = true
            val days = maxOf(of, 1)
            total = days
            done = minOf(maxOf(day - 1, 0), days)
            this.percent = minOf(maxOf(percent, 0), 100)
        }
    }
}
