package com.nextbody.hoop.band

import java.time.Instant
import java.util.UUID

/** Receipts for native history commands, never cached measurement rows. A shared refresh
 *  keeps each completed domain until it finishes; other callers retain the short freshness
 *  window. Connection/scope generations reject replies from a link that has already ended. */
class BandHistoryReadCache {
    data class Scope(
        val account: String?,
        val binding: String?,
        val device: String?,
        val sessionGeneration: UUID? = null,
    )

    enum class Domain { all, hrv, temperature, oxygen }

    data class Receipt(
        val status: BandDomainReadStatus,
        val startedAt: Instant,
        val completedAt: Instant,
    )

    private val lock = Any()
    private var scope: Scope? = null
    private var epoch: Long = 0
    private var refreshing = false
    private var receipts: MutableMap<Domain, Receipt> = mutableMapOf()
    /** HRV, oxygen and temperature stay valid across refreshes on the same link.
     *  The all-days origin dump does not: it is the only source of the latest five-minute slots. */
    private val auxiliaryLifetime: Double = BandSyncPolicy.auxiliaryReuse

    fun beginRefresh(scope: Scope, now: Instant = Instant.now()) = synchronized(lock) {
        val kept: MutableMap<Domain, Receipt> = if (this.scope == scope) {
            receipts.filter { (domain, receipt) ->
                if (domain == Domain.all) return@filter false
                if (receipt.status != BandDomainReadStatus.complete && receipt.status != BandDomainReadStatus.unsupported) return@filter false
                now >= receipt.completedAt && BandTime.interval(now, receipt.completedAt) < auxiliaryLifetime
            }.toMutableMap()
        } else mutableMapOf()
        epoch += 1
        refreshing = true
        receipts = kept
        this.scope = scope
    }

    fun drop(domain: Domain) = synchronized(lock) { receipts.remove(domain); Unit }

    fun endRefresh() = synchronized(lock) { refreshing = false }

    fun invalidate() = synchronized(lock) {
        reset()
        scope = null
    }

    fun generation(scope: Scope): Long = synchronized(lock) {
        adopt(scope)
        epoch
    }

    fun status(domain: Domain, scope: Scope, at: Instant = Instant.now()): BandDomainReadStatus? =
        receipt(domain, scope, at)?.status

    fun receipt(domain: Domain, scope: Scope, at: Instant = Instant.now()): Receipt? = synchronized(lock) {
        adopt(scope)
        val receipt = receipts[domain] ?: return@synchronized null
        if (at < receipt.completedAt) return@synchronized null
        if (domain == Domain.all) {
            if (!(refreshing || BandTime.interval(at, receipt.completedAt) < 60)) return@synchronized null
        } else if (!refreshing && BandTime.interval(at, receipt.completedAt) >= auxiliaryLifetime) {
            return@synchronized null
        }
        receipt
    }

    fun record(status: BandDomainReadStatus, domain: Domain, generation: Long,
               startedAt: Instant? = null, at: Instant = Instant.now()) = synchronized(lock) {
        if (generation != epoch) return@synchronized
        // Only a terminal read or explicit lack of SDK support can be reused. Failure,
        // partial progress and an uncollected database row never certify the transfer.
        if (status == BandDomainReadStatus.complete || status == BandDomainReadStatus.unsupported) {
            receipts[domain] = Receipt(status, startedAt ?: at, at)
        } else {
            receipts.remove(domain)
        }
    }

    private fun adopt(scope: Scope) {
        if (this.scope == scope) return
        reset()
        this.scope = scope
    }

    private fun reset() {
        epoch += 1
        refreshing = false
        receipts.clear()
    }
}
