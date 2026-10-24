package com.nextbody.hoop.band

import com.nextbody.hoop.services.SupabaseFailure
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset

class BandSyncPolicyTest {

    @Test fun settlementRetriesOnlyTransportFailures() {
        assertTrue(BandSyncPolicy.retriesSettle(SupabaseFailure.Transport(java.io.IOException("offline"))))
        assertFalse(BandSyncPolicy.retriesSettle(SupabaseFailure.Http(57014, """{"code":"57014"}""")))
        assertFalse(BandSyncPolicy.retriesSettle(IllegalStateException()))
    }

    @Test fun headerPrioritisesConnectionAndTransfer() {
        assertEquals("CONNECTING", BandSyncPolicy.header("connecting", false, "off"))
        assertEquals("SYNCING…", BandSyncPolicy.header("syncing", true, "off"))
        assertEquals("REACHING", BandSyncPolicy.header("idle", true, "reaching"))
        assertEquals("OFFLINE", BandSyncPolicy.header("idle", false, "live"))
        assertEquals("STANDBY", BandSyncPolicy.header("idle", true, "off"))
    }

    @Test fun reconnectMatchesBoundDevice() {
        assertTrue(BandSyncPolicy.matchesBoundDevice("ABC-123", bound = "abc-123"))
        assertFalse(BandSyncPolicy.matchesBoundDevice("other", bound = "abc-123"))
        assertFalse(BandSyncPolicy.matchesBoundDevice("abc-123", bound = null))
        assertTrue(BandSyncPolicy.matchesBoundDevice("uuid-1", sdkAddress = "AA:BB", bound = "aa:bb"))
        assertTrue(BandSyncPolicy.matchesBoundDevice("UUID-1", sdkAddress = "changed", bound = "AA:BB", boundPeripheral = "uuid-1"))
        assertFalse(BandSyncPolicy.matchesBoundDevice("other", sdkAddress = "CC:DD", bound = "AA:BB", boundPeripheral = "uuid-1"))
        assertFalse(BandSyncPolicy.matchesBoundDevice("uuid-1", bound = null, boundPeripheral = "uuid-1"))
        assertFalse(BandSyncPolicy.matchesBoundDevice("", sdkAddress = "", bound = "AA:BB", boundPeripheral = ""))
    }

    @Test fun legacyPeripheralMigration() {
        val uuid = "758F52C1-BF3E-45FE-9DF6-2F1D5509BF01"
        assertEquals(uuid, BandSyncPolicy.legacyPeripheralIdentifier("aa:bb", "AA:BB", uuid.lowercase()))
        assertNull(BandSyncPolicy.legacyPeripheralIdentifier("AA:BB", "CC:DD", uuid))
        assertNull(BandSyncPolicy.legacyPeripheralIdentifier(null, "AA:BB", uuid))
        assertNull(BandSyncPolicy.legacyPeripheralIdentifier("AA:BB", "AA:BB", "not-a-uuid"))
        assertNull(BandSyncPolicy.legacyPeripheralIdentifier("AA:BB", "AA:BB", null))
    }

    @Test fun historyDays() {
        assertEquals(6, BandSyncPolicy.historyDays(7))
        assertEquals(0, BandSyncPolicy.historyDays(1))
        assertEquals(6, BandSyncPolicy.historyDays(0))
        assertEquals(6, BandSyncPolicy.historyDays(null))
        assertEquals(29, BandSyncPolicy.historyDays(30))
    }

    private val domains = listOf("origin", "hrv", "temperature", "rr", "sleep", "oxygen", "response")
    private val auditNow = Instant.ofEpochSecond(1_789_000_000)
    private val dayStart = BandTime.addingDays(BandTime.startOfDay(auditNow), -3)
    private val dayEnd = BandTime.addingDays(dayStart, 1)

    private fun confirmed(at: Instant? = null, end: Instant? = null) = domains.map {
        BandDomainSyncState(it, BandDomainReadStatus.complete, at ?: auditNow, dayStart, end ?: dayEnd, null, null)
    }

    private fun needsAudit(states: List<BandDomainSyncState>, outcome: BandRefreshResult.Status? = BandRefreshResult.Status.success,
                           requireToday: Boolean = true) =
        BandSyncPolicy.needsHistorySync(states, outcome, dayStart, dayEnd, auditNow, requireAcknowledgedToday = requireToday)

    @Test fun historyAuditSkipsOnlyConfirmedFullDaysCheckedToday() {
        assertFalse(needsAudit(confirmed()))
        assertTrue(needsAudit(emptyList()))
        assertTrue(needsAudit(confirmed().dropLast(1)))
        assertTrue(needsAudit(confirmed(at = auditNow.minusSeconds(86_400))))
        assertTrue(needsAudit(confirmed(at = auditNow.plusSeconds(60))))
        assertTrue(needsAudit(confirmed(end = auditNow.minusSeconds(4 * 86_400))))
        assertFalse(needsAudit(confirmed(at = auditNow.minusSeconds(86_400)), requireToday = false))
        assertTrue(needsAudit(confirmed(), outcome = BandRefreshResult.Status.partial))
        assertTrue(needsAudit(confirmed(), outcome = null))
    }

    @Test fun failedDomainRetainsRepair() {
        val states = confirmed().toMutableList()
        val prior = states.removeAt(states.size - 1)
        states.add(prior.copy(status = BandDomainReadStatus.failed, repairStart = prior.acknowledgedStart, repairEnd = prior.acknowledgedEnd))
        assertTrue(needsAudit(states))
    }

    @Test fun oxygenKeepsItsRecordedNightWindow() {
        val states = confirmed().toMutableList()
        val oxygen = states.removeAt(5)
        states.add(oxygen.copy(status = BandDomainReadStatus.notCollected,
            acknowledgedStart = oxygen.acknowledgedStart!!.minusSeconds(3600),
            acknowledgedEnd = oxygen.acknowledgedStart!!.plusSeconds(7 * 3600)))
        assertFalse(needsAudit(states))
    }

    @Test fun historyOffsetSelection() {
        val checked = mutableListOf<Int>()
        val offsets = BandSyncPolicy.historyOffsetsToSync(listOf(1, 2, 3, 4, 5, 6),
            recentDays = mapOf(0 to BandRefreshResult.Status.success, 1 to BandRefreshResult.Status.success)) { checked.add(it); it in listOf(3, 6) }
        assertEquals(listOf(3, 6), offsets)
        assertEquals(listOf(2, 3, 4, 5, 6), checked)
        assertEquals(listOf(1), BandSyncPolicy.historyOffsetsToSync(listOf(1, 2, 3),
            recentDays = mapOf(0 to BandRefreshResult.Status.success, 1 to BandRefreshResult.Status.partial)) { false })
        assertEquals(listOf(2, 3, 4, 5), BandSyncPolicy.historyOffsetsToSync(listOf(1, 2, 3, 4, 5, 6),
            elapsedDays = 1, recentDays = mapOf(0 to BandRefreshResult.Status.success, 1 to BandRefreshResult.Status.success)) { true })
    }

    @Test fun dayStatus() {
        assertEquals(BandRefreshResult.Status.success, BandSyncPolicy.dayStatus(2, 2, true))
        assertEquals(BandRefreshResult.Status.partial, BandSyncPolicy.dayStatus(1, 2, true))
        assertEquals(BandRefreshResult.Status.partial, BandSyncPolicy.dayStatus(2, 2, false))
    }

    @Test fun lightTierReadsYesterdayOnlyBeforeFourOrWhenUnconfirmed() {
        val utc = ZoneOffset.UTC
        val early = LocalDateTime.of(2026, 10, 17, 3, 0).toInstant(utc)
        val day = LocalDateTime.of(2026, 10, 17, 10, 0).toInstant(utc)
        val light = BandRefreshTier.light
        assertEquals(listOf(0, 1), BandSyncPolicy.refreshDayOffsets(light, BandSyncPolicy.refreshIncludesYesterday(light, early, true, utc)))
        assertEquals(listOf(0), BandSyncPolicy.refreshDayOffsets(light, BandSyncPolicy.refreshIncludesYesterday(light, day, true, utc)))
        assertEquals(listOf(0, 1), BandSyncPolicy.refreshDayOffsets(light, BandSyncPolicy.refreshIncludesYesterday(light, day, false, utc)))
        assertEquals(listOf(0, 1), BandSyncPolicy.refreshDayOffsets(BandRefreshTier.daily, true))
    }

    @Test fun auxiliaryDump() {
        val now = Instant.ofEpochSecond(1_800_000)
        assertTrue(BandSyncPolicy.needsAuxiliaryDump(true, now, now, BandRefreshTier.full))
        assertTrue(BandSyncPolicy.needsAuxiliaryDump(false, now, now, BandRefreshTier.light))
        assertTrue(BandSyncPolicy.needsAuxiliaryDump(true, null, now, BandRefreshTier.daily))
        assertTrue(BandSyncPolicy.needsAuxiliaryDump(true, now.plusSeconds(5), now, BandRefreshTier.daily))
        assertFalse(BandSyncPolicy.needsAuxiliaryDump(true, now, now.plusSeconds(29 * 60), BandRefreshTier.light))
        assertTrue(BandSyncPolicy.needsAuxiliaryDump(true, now, now.plusSeconds(30 * 60), BandRefreshTier.daily))
    }

    @Test fun reusedDumpCoversDay() {
        val zone = ZoneId.of("Asia/Shanghai")
        val midnight = LocalDateTime.of(2026, 10, 22, 0, 0).atZone(zone).toInstant()
        val morning = midnight.plusSeconds(9 * 3600)
        fun covers(offset: Int, completed: Instant?) =
            BandSyncPolicy.reusedDumpCoversDay(offset, completed, morning.plusSeconds(600), zone)
        assertTrue(covers(1, morning))
        assertTrue(covers(5, morning))
        assertTrue(covers(1, midnight))
        assertFalse(covers(1, midnight.minusSeconds(60)))
        assertFalse(covers(0, morning))
        assertFalse(covers(1, null))
    }

    @Test fun skippedDomainKeepsPreviousAcknowledgement() {
        val now = Instant.ofEpochSecond(1_800_000)
        val previous = BandDomainSyncState("hrv", BandDomainReadStatus.complete, now, now, now.plusSeconds(60), null, null)
        val origin = BandDomainSyncState("origin", BandDomainReadStatus.complete, now.plusSeconds(10), now, now.plusSeconds(60), null, null)
        val kept = BandSyncPolicy.keepingSkippedDomains(listOf(origin), listOf(previous), setOf("hrv"))
        assertEquals(listOf("origin", "hrv"), kept.map { it.domain })
        assertEquals(now, kept.last().attemptedAt)
    }

    @Test fun readFraction() {
        assertEquals(0.0, BandSyncPolicy.readFraction(1, 7, 0), 1e-4)
        assertEquals(0.5 / 7, BandSyncPolicy.readFraction(1, 7, 50), 1e-4)
        assertEquals(3.5 / 7, BandSyncPolicy.readFraction(4, 7, 50), 1e-4)
        assertEquals(1.0, BandSyncPolicy.readFraction(7, 7, 100), 1e-4)
        assertEquals(0.0, BandSyncPolicy.readFraction(1, 0, 50), 0.0)
        assertEquals(1.0, BandSyncPolicy.readFraction(9, 7, 100), 0.0)
        assertEquals(1.0 / 7, BandSyncPolicy.readFraction(1, 7, 150), 1e-4)
    }

    @Test fun readProgressFollowsDeviceDump() {
        val progress = BandSyncPolicy.ReadProgress()
        progress.expect(total = 2)
        progress.reportRead(4, 7, 50)
        assertEquals(3, progress.done); assertEquals(7, progress.total); assertEquals(50, progress.percent)
        progress.step()
        progress.expect(total = 9)
        assertEquals(3.5 / 7, progress.fraction, 1e-4)
        progress.reportRead(1, 7, 0)
        assertEquals(3.5 / 7, progress.fraction, 1e-4)
        progress.reportRead(7, 7, 100)
        assertEquals(1.0, progress.fraction, 1e-4)
    }

    @Test fun readProgressWithinAndRevise() {
        val progress = BandSyncPolicy.ReadProgress()
        progress.expect(total = 4)
        progress.step()
        assertEquals(0.25, progress.fraction, 1e-3)
        progress.within(percent = 50)
        assertEquals(0.375, progress.fraction, 1e-3)
        progress.within(percent = 20)
        assertEquals(0.375, progress.fraction, 1e-3)
        progress.step()
        assertEquals(0.5, progress.fraction, 1e-3)

        val other = BandSyncPolicy.ReadProgress()
        other.expect(total = 7)
        repeat(5) { other.step() }
        other.revise(total = 2)
        assertEquals(5, other.total)
        assertEquals(1.0, other.fraction, 1e-3)
    }
}
