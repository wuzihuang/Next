package com.nextbody.hoop.band

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class SportMathTest {
    private val epoch = Instant.ofEpochSecond(1_000)
    private val empty get() = SportMetricAccumulator(weightKg = 70.0, age = 34, male = true, sportMode = 3)
    private fun at(s: Double) = BandTime.adding(epoch, s)
    private fun report(state: SportMetricAccumulator, s: Double, hr: Int? = 120, kcal: Double? = null, run: Int? = 1) =
        state.accepting(at(s), hr, kcal, run)

    @Test fun nativeZeroIsAuthoritative() {
        val estimated = report(report(empty, 0.0), 10.0)
        assertTrue(estimated.kcal > 0)
        val nativeZero = report(estimated, 11.0, kcal = 0.0)
        assertEquals(0.0, nativeZero.kcal, 0.0)
        assertEquals(SportMetricAccumulator.CalorieSource.band, nativeZero.calorieSource)
        assertTrue(nativeZero.hasEnergyEvidence)
        assertEquals(estimated.kcal, nativeZero.calorieCorrection!!.previousKcal, 0.0)
        assertEquals(0.0, report(nativeZero, 15.0).kcal, 0.0)
    }

    @Test fun profileAloneIsNotEvidence() {
        assertTrue(empty.estimationAvailable)
        assertFalse(empty.hasEnergyEvidence)
        assertFalse(report(empty, 0.0).hasEnergyEvidence)
        assertFalse(report(report(empty, 0.0), 16.0).hasEnergyEvidence)
        assertTrue(report(report(empty, 0.0), 15.0).hasEnergyEvidence)
    }

    @Test fun strengthModeUsesRunningIntervals() {
        val strength = SportMetricAccumulator(70.0, 34, true, 25)
        val second = report(report(strength, 0.0, hr = null), 10.0, hr = null)
        assertEquals((3.5 - 1) * 3.5 * 70 / 200 * 10 / 60, second.kcal, 1e-6)
        assertEquals(10.0, second.estimatedSeconds, 1e-6)
        assertNull(second.heartRate)
        val fallback = report(report(strength, 0.0, run = null), 10.0, run = null)
        assertEquals(0.0, fallback.kcal, 0.0)
        assertEquals(120, fallback.heartRate)
    }

    @Test fun cumulativeNativeTotalsReplace() {
        val next = report(report(report(empty, 0.0, kcal = 50.0), 1.0, kcal = 50.0), 2.0, kcal = 100.0)
        assertEquals(100.0, next.kcal, 0.0)
        val correction = report(next, 3.0, kcal = 75.0)
        assertEquals(75.0, correction.kcal, 0.0)
        assertNotNull(correction.calorieCorrection)
    }

    @Test fun noIntegrationAcrossPauseGapOrBackwardClock() {
        val first = report(empty, 0.0)
        for (state in listOf(report(first, 5.0, run = 0), report(first, 5.0, run = 2), report(first, 5.0, hr = null), first.interrupted())) {
            assertNull(state.heartRate)
            assertEquals(0.0, report(state, 10.0).kcal, 0.0)
            assertTrue(report(report(state, 10.0), 11.0).kcal > 0)
        }
        assertEquals(0.0, report(first, 16.0).kcal, 0.0)
        assertEquals(0.0, report(first, -1.0).kcal, 0.0)
        assertTrue(report(first, 15.0).kcal > 0)
    }

    @Test fun heartRatesExactAndFreshness() {
        for (v in listOf(-1, 0, 256, 65535)) assertNull(report(empty, 0.0, hr = v).heartRate)
        val third = report(report(report(empty, 0.0, hr = 50), 1.0, hr = 100), 2.0, hr = 150)
        assertEquals(100, third.averageHR); assertEquals(150, third.peakHR); assertEquals(3, third.sampleCount)
        val s = report(empty, 0.0)
        assertEquals(120, s.liveHR(at(14.0)))
        assertNull(s.liveHR(at(15.0)))
        assertNull(s.liveHR(at(-1.0)))
    }

    private fun beat(s: Double, bpm: Int, seg: Int = 0) = SportRecapMath.Beat(Instant.ofEpochSecond(0).plusMillis((s * 1000).toLong()), bpm, seg)

    @Test fun recapBasics() {
        val empty = SportRecapMath.recap(emptyList(), 60, 190, 600)
        assertNull(empty.avgHR); assertEquals(SportRecapMath.Recap.Conclusion.noHeart, empty.conclusion)
        val gap = SportRecapMath.recap(listOf(beat(0.0, 160), beat(16.0, 165)), 60, 190, 16)
        assertEquals(0.0, gap.zoneMinutes.sum(), 0.01); assertEquals(165, gap.peakHR)
        val aerobic = SportRecapMath.recap((0 until 120).map { beat(it.toDouble(), 130) }, 60, 190, 120)
        assertEquals(130, aerobic.avgHR); assertTrue(aerobic.loadDelta > 0)
        assertEquals(SportRecapMath.Recap.Conclusion.aerobic, aerobic.conclusion)
        val anaerobic = SportRecapMath.recap((0 until 60).map { beat(it.toDouble(), 185) }, 60, 190, 60)
        assertEquals(SportRecapMath.Recap.Conclusion.anaerobic, anaerobic.conclusion)
        val short = SportRecapMath.recap(listOf(beat(0.0, 185), beat(5.0, 185)), 60, 190, 5)
        assertEquals(0, short.anaerobicMinutes); assertEquals(SportRecapMath.Recap.Conclusion.anaerobic, short.conclusion)
        val paused = SportRecapMath.recap(listOf(beat(0.0, 130, 0), beat(5.0, 130, 1)), 60, 190, 5)
        assertEquals(SportRecapMath.Recap.Conclusion.insufficient, paused.conclusion)
        assertEquals(listOf(0, 1), paused.curvePoints.map { it.segment })
    }

    @Test fun zonesMatchTraining() {
        assertEquals(0, SportRecapMath.zoneIndex(89, 60, 160))
        listOf(90 to 1, 100 to 2, 115 to 3, 130 to 4, 145 to 5).forEach { (h, z) -> assertEquals(z, SportRecapMath.zoneIndex(h, 60, 160)) }
        assertEquals(1, SportRecapMath.zoneIndex(100, null, 200))
        val below = SportRecapMath.recap(listOf(beat(0.0, 70), beat(10.0, 70)), 60, 160, 10)
        assertEquals(SportRecapMath.Recap.Conclusion.belowZones, below.conclusion)
        assertEquals(10.0, below.observedSeconds, 0.0)
    }

    @Test fun allDayCurveIsBounded() {
        val beats = (0 until 86_400).map { beat(it.toDouble(), 130, if (it < 43_200) 0 else 1) }
        val points = SportRecapMath.displayPoints(beats)
        assertEquals(4_000, points.size)
        assertEquals(Instant.ofEpochSecond(0), points.first().at)
        assertEquals(Instant.ofEpochSecond(86_399), points.last().at)
        assertEquals(setOf(0, 1), points.map { it.segment }.toSet())
    }

    @Test fun wristFace() {
        fun face(hr: Int?, seeking: Double, had: Boolean = false, silent: Double = Double.MAX_VALUE) =
            SportWristMath.face(1, hr, had, seeking, silent)
        assertEquals(SportWristMath.Face.reaching, face(null, 0.0))
        assertEquals(SportWristMath.Face.reaching, face(0, 29.9))
        assertEquals(SportWristMath.Face.noContact, face(null, 30.0))
        assertEquals(SportWristMath.Face.live, face(128, 2.0))
        assertEquals(SportWristMath.Face.paused, SportWristMath.face(2, null, false, 40.0, 40.0))
        assertEquals(SportWristMath.Face.reaching, face(null, 40.0, true, 14.9))
        assertEquals(SportWristMath.Face.noContact, face(null, 40.0, true, 15.0))
    }

    @Test fun heartEvidenceContinuity() {
        val stream = SportHeartRateEvidenceStream()
        val a = stream.accept(at(0.0), 120, 1, 3, "UTC")!!
        assertNull(stream.accept(at(0.0), 121, 1, 3, "UTC"))
        val b = stream.accept(at(5.0), 121, 1, 3, "UTC")!!
        assertEquals(a.continuityID, b.continuityID)
        val c = stream.accept(at(30.0), 121, 1, 3, "UTC")!!
        assertTrue(c.continuityID != b.continuityID)
        assertNull(stream.accept(at(31.0), 0, 1, 3, "UTC"))
    }
}
