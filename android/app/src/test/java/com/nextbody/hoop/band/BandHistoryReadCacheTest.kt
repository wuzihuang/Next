package com.nextbody.hoop.band

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant
import java.util.UUID

class BandHistoryReadCacheTest {
    private val scope = BandHistoryReadCache.Scope("alice", "band-a", "sdk-a")
    private val now = Instant.ofEpochSecond(10_000)
    private val complete = BandDomainReadStatus.complete

    @Test fun completedDomainsReusedUntilRefreshFinishes() {
        val cache = BandHistoryReadCache()
        cache.beginRefresh(scope)
        val token = cache.generation(scope)
        cache.record(complete, BandHistoryReadCache.Domain.all, token, at = now)
        assertEquals(complete, cache.status(BandHistoryReadCache.Domain.all, scope, now.plusSeconds(600)))
        cache.endRefresh()
        assertNull(cache.status(BandHistoryReadCache.Domain.all, scope, now.plusSeconds(600)))
        cache.beginRefresh(scope)
        assertNull(cache.status(BandHistoryReadCache.Domain.all, scope, now))
    }

    @Test fun independentFailure() {
        val cache = BandHistoryReadCache()
        cache.beginRefresh(scope)
        val token = cache.generation(scope)
        cache.record(complete, BandHistoryReadCache.Domain.hrv, token, at = now)
        cache.record(BandDomainReadStatus.failed, BandHistoryReadCache.Domain.temperature, token, at = now)
        cache.record(BandDomainReadStatus.unsupported, BandHistoryReadCache.Domain.oxygen, token, at = now)
        assertEquals(complete, cache.status(BandHistoryReadCache.Domain.hrv, scope, now.plusSeconds(600)))
        assertNull(cache.status(BandHistoryReadCache.Domain.temperature, scope, now))
        assertEquals(BandDomainReadStatus.unsupported, cache.status(BandHistoryReadCache.Domain.oxygen, scope, now))
    }

    @Test fun scopeChangesRejectStaleCompletions() {
        for (other in listOf(BandHistoryReadCache.Scope("bob", "band-a", "sdk-a"),
            BandHistoryReadCache.Scope("alice", "band-b", "sdk-a"),
            BandHistoryReadCache.Scope("alice", "band-a", "sdk-a", UUID.randomUUID()))) {
            val cache = BandHistoryReadCache()
            cache.beginRefresh(scope)
            val old = cache.generation(scope)
            cache.record(complete, BandHistoryReadCache.Domain.all, old, at = now)
            assertNull(cache.status(BandHistoryReadCache.Domain.all, other, now))
            cache.record(complete, BandHistoryReadCache.Domain.all, old, at = now)
            assertNull(cache.status(BandHistoryReadCache.Domain.all, other, now))
        }
        val cache = BandHistoryReadCache()
        cache.beginRefresh(scope)
        val old = cache.generation(scope)
        cache.invalidate()
        cache.record(complete, BandHistoryReadCache.Domain.all, old, at = now)
        assertNull(cache.status(BandHistoryReadCache.Domain.all, scope, now))
    }

    @Test fun outsideRefreshReceiptExpires() {
        val cache = BandHistoryReadCache()
        val token = cache.generation(scope)
        cache.record(complete, BandHistoryReadCache.Domain.all, token, at = now)
        assertEquals(complete, cache.status(BandHistoryReadCache.Domain.all, scope, now.plusSeconds(59)))
        assertNull(cache.status(BandHistoryReadCache.Domain.all, scope, now.plusSeconds(60)))
        assertNull(cache.status(BandHistoryReadCache.Domain.all, scope, now.minusSeconds(1)))
    }

    @Test fun receiptKeepsNativeTiming() {
        val cache = BandHistoryReadCache()
        cache.beginRefresh(scope)
        val token = cache.generation(scope)
        val completed = now.plusSeconds(360)
        cache.record(complete, BandHistoryReadCache.Domain.all, token, startedAt = now, at = completed)
        val reused = cache.receipt(BandHistoryReadCache.Domain.all, scope, now.plusSeconds(1200))!!
        assertEquals(now, reused.startedAt)
        assertEquals(completed, reused.completedAt)
    }

    @Test fun auxiliaryReceiptSurvivesNextRefreshForThirtyMinutes() {
        val cache = BandHistoryReadCache()
        cache.beginRefresh(scope, now)
        val token = cache.generation(scope)
        cache.record(complete, BandHistoryReadCache.Domain.hrv, token, at = now)
        cache.record(complete, BandHistoryReadCache.Domain.all, token, at = now)
        cache.endRefresh()
        val later = now.plusSeconds(60)
        cache.beginRefresh(scope, later)
        assertEquals(complete, cache.status(BandHistoryReadCache.Domain.hrv, scope, later))
        assertNull(cache.status(BandHistoryReadCache.Domain.all, scope, later))
        cache.endRefresh()
        assertEquals(complete, cache.status(BandHistoryReadCache.Domain.hrv, scope, now.plusSeconds(30 * 60 - 1)))
        assertNull(cache.status(BandHistoryReadCache.Domain.hrv, scope, now.plusSeconds(30 * 60)))
        val other = BandHistoryReadCache.Scope("alice", "band-b", "sdk-a")
        cache.beginRefresh(other, now.plusSeconds(10))
        assertNull(cache.status(BandHistoryReadCache.Domain.hrv, other, now.plusSeconds(10)))
    }
}
