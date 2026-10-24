package com.nextbody.hoop.band

import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BandSyncProgressTest {

    @Test fun stagesDistinguishAppFromCloud() {
        for (s in listOf(BandSyncProgress.Stage.searching, BandSyncProgress.Stage.connecting, BandSyncProgress.Stage.verifying, BandSyncProgress.Stage.identity, BandSyncProgress.Stage.battery, BandSyncProgress.Stage.capabilities, BandSyncProgress.Stage.reading, BandSyncProgress.Stage.finishing)) {
            assertEquals(BandSyncProgress.Destination.app, s.destination)
        }
        assertEquals(BandSyncProgress.Destination.cloud, BandSyncProgress.Stage.saving.destination)
        assertEquals(BandSyncProgress.Destination.cloud, BandSyncProgress.Stage.updating.destination)
        assertNull(BandSyncProgress.Stage.complete.destination)
        assertNull(BandSyncProgress.Stage.stopped.destination)
    }

    @Test fun historyReturnsToAppWithoutRewinding() {
        val p = BandSyncProgress()
        p.begin(); p.show(BandSyncProgress.Stage.reading); p.read(1.0); p.show(BandSyncProgress.Stage.saving)
        p.filedDay()
        val saved = p.fraction
        p.show(BandSyncProgress.Stage.reading)
        assertEquals(saved, p.fraction, 0.0)
        p.updatingResults()
        assertEquals(BandSyncProgress.Destination.cloud, p.stage.destination)
        p.finish(success = false)
        assertNull(p.stage.destination)
        p.show(BandSyncProgress.Stage.saving)
        assertNull(p.stage.destination)
        p.begin()
        assertEquals(BandSyncProgress.Destination.app, p.stage.destination)
    }

    @Test fun modes() {
        val p = BandSyncProgress()
        p.begin(); assertEquals("DAILY SYNC", p.modeLabel)
        p.beginHistory(); assertEquals("BACKFILLING HISTORY", p.modeLabel)
        p.begin(); assertEquals("DAILY SYNC", p.modeLabel)
    }

    @Test fun deadlineTracksProgress() {
        val d = BandSyncDeadline(startedAt = 100.0)
        assertFalse(d.expired(144.0))
        d.advance("day1:10", 120.0)
        d.advance("day1:10", 140.0)
        assertFalse(d.expired(164.0))
        assertTrue(d.expired(165.0))
        d.advance("day1:20", 165.0)
        assertFalse(d.expired(166.0))
        d.advance("day7:99", 399.0)
        assertTrue(d.expired(400.0))
    }

    @Test fun dumpAt100DoesNotCompleteWholeSync() {
        val p = BandSyncProgress()
        p.begin(); p.show(BandSyncProgress.Stage.reading); p.read(1.0)
        assertTrue(p.fraction < 1); assertTrue(p.active)
        p.expect(3); repeat(3) { p.filedDay() }
        p.updatingResults(); p.resultsLoaded(); p.show(BandSyncProgress.Stage.finishing)
        assertTrue(p.fraction < 1)
        p.finish(success = true)
        assertEquals(1.0, p.fraction, 0.0)
        assertFalse(p.active)
        assertEquals(BandSyncProgress.Stage.complete, p.stage)
    }

    @Test fun connectionStepsAdvanceAndRetryDoesNotRewind() {
        val p = BandSyncProgress()
        p.begin()
        for (s in listOf(BandSyncProgress.Stage.connecting, BandSyncProgress.Stage.verifying, BandSyncProgress.Stage.identity, BandSyncProgress.Stage.battery, BandSyncProgress.Stage.capabilities)) {
            val before = p.fraction
            p.show(s)
            assertTrue(p.fraction > before)
        }
        val before = p.fraction
        p.show(BandSyncProgress.Stage.searching)
        assertEquals(BandSyncProgress.Stage.searching, p.stage)
        assertEquals(before, p.fraction, 0.0)
    }

    @Test fun partialFailureLateEventsAndNewAttempt() {
        val p = BandSyncProgress()
        p.begin(); p.read(1.0); p.show(BandSyncProgress.Stage.finishing); p.finish(false)
        assertEquals(BandSyncProgress.Stage.stopped, p.stage)
        p.read(1.0); p.show(BandSyncProgress.Stage.identity); p.finish(true)
        assertEquals(BandSyncProgress.Stage.stopped, p.stage)
        p.begin()
        assertEquals(0.0, p.fraction, 0.0)
        p.read(Double.NaN)
        assertEquals(0.0, p.fraction, 0.0)
    }

    private fun state(binding: () -> String = { "band" }) = {
        BandRefreshCoordinator.State("account", binding(), consent = true, exclusive = false, connected = true)
    }

    @Test fun sharedRefreshWaitsForAsyncCompletionReceipt() = runTest {
        var persisted = false
        lateinit var coordinator: BandRefreshCoordinator
        coordinator = BandRefreshCoordinator(state(), taskScope = this)
        val result = coordinator.refresh(BandRefreshRequest.latest, 0.0, BandRefreshCoordinator.Work(
            prepare = { true }, day = { BandRefreshResult(BandRefreshResult.Status.success) },
            history = { BandRefreshCoordinator.HistoryResult(null) },
            completed = { yield(); assertFalse(coordinator.isIdle); persisted = true }))
        assertEquals(BandRefreshResult.Status.success, result.status)
        assertTrue(persisted)
        assertTrue(coordinator.isIdle)
    }

    @Test fun scopeChangeDuringCleanupCannotPublish100() = runTest {
        var binding = "A"
        val progress = BandSyncProgress()
        val coordinator = BandRefreshCoordinator(state { binding }, taskScope = this)
        val result = coordinator.refresh(BandRefreshRequest.fullHistory, 0.0, BandRefreshCoordinator.Work(
            prepare = { progress.begin(); true },
            day = { BandRefreshResult(BandRefreshResult.Status.success) },
            history = { BandRefreshCoordinator.HistoryResult(BandRefreshResult(BandRefreshResult.Status.success)) },
            finish = { binding = "B" },
            completed = { progress.finish(it.status == BandRefreshResult.Status.success) }))
        assertEquals(BandRefreshResult.Status.cancelled, result.status)
        assertEquals(BandSyncProgress.Stage.stopped, progress.stage)
        assertTrue(progress.fraction < 1)
    }

    @Test fun throttlesAutomaticButNotExplicitPulls() = runTest {
        var now = java.time.Instant.ofEpochSecond(10_000)
        var prepares = 0
        val coordinator = BandRefreshCoordinator(state(), now = { now }, taskScope = this)
        val work = BandRefreshCoordinator.Work(prepare = { prepares++; true },
            day = { BandRefreshResult(BandRefreshResult.Status.success, points = 1) },
            history = { BandRefreshCoordinator.HistoryResult(null) })
        assertEquals(BandRefreshResult.Status.success, coordinator.refresh(BandRefreshRequest.automatic, 600.0, work).status)
        assertEquals(BandRefreshResult.Status.throttled, coordinator.refresh(BandRefreshRequest.automatic, 600.0, work).status)
        assertEquals(BandRefreshResult.Status.success, coordinator.refresh(BandRefreshRequest.latest, 600.0, work).status)
        now = now.plusSeconds(601)
        assertEquals(2, coordinator.refresh(BandRefreshRequest.automatic, 600.0, work).points)
        assertEquals(3, prepares)
    }

    @Test fun rejectionsAndConsentReplay() = runTest {
        var consent = false
        val coordinator = BandRefreshCoordinator({
            BandRefreshCoordinator.State("a", "b", consent, exclusive = false, connected = true)
        }, taskScope = this)
        val work = BandRefreshCoordinator.Work(prepare = { true },
            day = { BandRefreshResult(BandRefreshResult.Status.failed) },
            history = { BandRefreshCoordinator.HistoryResult(null) })
        assertEquals(BandRefreshResult.Status.consentRequired, coordinator.refresh(BandRefreshRequest.fullHistory, 0.0, work).status)
        consent = true
        assertEquals(BandRefreshResult.Status.failed, coordinator.refreshAfterConsent(0.0, work)?.status)
        assertNull(coordinator.refreshAfterConsent(0.0, work))
    }
}
