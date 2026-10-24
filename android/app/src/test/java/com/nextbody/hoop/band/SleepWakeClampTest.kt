package com.nextbody.hoop.band

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

/** Issue #20 · using the app is wake evidence the band cannot collect. */
class SleepWakeClampTest {
    private val bed = Instant.ofEpochSecond(1_788_400_000)
    private fun at(seconds: Double) = BandTime.adding(bed, seconds)
    private fun night(hours: Double) = bed to at(hours * 3600)

    @Test fun foregroundMarkInsideTheNightEndsIt() {
        val (start, recorded) = night(8.0)
        val usedTheApp = at(6.5 * 3600)
        assertEquals(usedTheApp, SleepWakeClamp.wake(start, recorded, listOf(usedTheApp)))
    }

    @Test fun theFirstMarkWinsRatherThanTheLast() {
        val (start, recorded) = night(8.0)
        val first = at(6.0 * 3600)
        val later = at(7.0 * 3600)
        assertEquals(first, SleepWakeClamp.wake(start, recorded, listOf(later, first)))
    }

    @Test fun aGlanceWhileFallingAsleepIsNotAWake() {
        val (start, recorded) = night(8.0)
        assertNull(SleepWakeClamp.wake(start, recorded, listOf(at(SleepWakeClamp.minimumNight - 60))))
    }

    @Test fun aMarkTheBandAlreadyAgreesWithChangesNothing() {
        val (start, recorded) = night(8.0)
        assertNull(SleepWakeClamp.wake(start, recorded, listOf(BandTime.adding(recorded, -SleepWakeClamp.tolerance + 30))))
    }

    @Test fun marksOutsideTheNightAreIgnored() {
        val (start, recorded) = night(8.0)
        assertNull(SleepWakeClamp.wake(start, recorded, listOf(at(-2.0 * 3600), BandTime.adding(recorded, 3600.0))))
    }

    @Test fun cuttingIsIdempotent() {
        val (start, recorded) = night(8.0)
        val mark = at(6.5 * 3600)
        assertEquals(mark, SleepWakeClamp.wake(start, recorded, listOf(mark)))
        assertNull(SleepWakeClamp.wake(start, mark, listOf(mark)))
    }

    @Test fun repeatedForegroundsWithinAMinuteAreOneWaking() {
        AwakeEvidence.reset()
        AwakeEvidence.record(at = bed)
        AwakeEvidence.record(at = at(20.0))
        AwakeEvidence.record(at = at(30.0))
        assertEquals(listOf(bed), AwakeEvidence.marks())
    }

    @Test fun marksOlderThanTheRetentionAreDropped() {
        AwakeEvidence.reset()
        AwakeEvidence.record(at = bed)
        val muchLater = at(AwakeEvidence.retention + 3600)
        AwakeEvidence.record(at = muchLater)
        assertEquals(listOf(muchLater), AwakeEvidence.marks())
    }
}
