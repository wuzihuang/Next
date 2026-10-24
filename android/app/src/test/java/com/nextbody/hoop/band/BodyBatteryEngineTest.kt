package com.nextbody.hoop.band

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.exp

class BodyBatteryEngineTest {
    private val baseline = BodyBatteryEngine.Baseline(
        restingHeartRate = 55.0, maximumHeartRate = 190.0, hrvMS = 50.0, recoveryMultiplier = 1.0)

    private fun replay(tick: BodyBatteryEngine.Tick, count: Int = 24, anchor: Double = 50.0) =
        BodyBatteryEngine.replay(anchor, List(count) { tick }, baseline)

    private fun T(heartRate: Int? = null, hrvMS: Double? = null, stress: Int? = null, steps: Int? = null,
                  met: Double? = null, sleepStage: Int? = null, oxygen: Double? = null, durationMinutes: Double = 5.0,
                  inSession: Boolean = false) =
        BodyBatteryEngine.Tick(durationMinutes = durationMinutes, heartRate = heartRate, hrvMS = hrvMS, stress = stress,
            steps = steps, met = met, sleepStage = sleepStage, oxygen = oxygen, inSession = inSession)

    @Test fun sustainedDaytimeRestActuallyRecharges() {
        assertTrue(replay(T(55, 55.0, 20, 0, 1.0)).value > 53)
    }

    @Test fun sustainedRestingPulseRecoversWithMissingAutonomicChannels() {
        assertTrue(replay(T(heartRate = 55, steps = 0, met = 1.0)).value > 50)
    }

    @Test fun elevatedNonExerciseHeartRateCostsReserve() {
        val calm = replay(T(heartRate = 72, steps = 0, met = 1.0))
        val elevated = replay(T(heartRate = 90, steps = 0, met = 1.0))
        assertTrue(elevated.value < calm.value - 3)
    }

    @Test fun sustainedSevereStrainReachesLowReserve() {
        val r = replay(T(90, 20.0, 90, 0, 1.0), count = 144, anchor = 85.0)
        assertTrue(r.value < 25)
        assertTrue(85 - r.value > 60)
    }

    @Test fun missingEvidenceAndBriefRestCannotRefill() {
        assertEquals(50.0, replay(T(), count = 144).value, 0.0)
        assertTrue(replay(T(heartRate = 55, stress = 20, steps = 0, met = 1.0), count = 1).value <= 50)
        assertTrue(replay(T(55, 55.0, 90, 0, 1.0)).value <= 50)
    }

    @Test fun recordingGapRestartsRestWindow() {
        val quiet = T(55, 55.0, 20, 0, 1.0)
        val r = BodyBatteryEngine.replay(50.0, List(4) { quiet } + T() + List(4) { quiet }, baseline)
        assertEquals(0.0, r.drivers.restorativeRest, 0.0)
        assertTrue(r.value < 50)
    }

    @Test fun isolatedOxygenDipDoesNotChangeSleepRecovery() {
        val quiet = T(heartRate = 55, stress = 20, sleepStage = 1, oxygen = 98.0)
        val ticks = MutableList(24) { quiet }
        ticks[10] = ticks[10].copy(oxygen = 85.0)
        val oneDip = BodyBatteryEngine.replay(50.0, ticks, baseline)
        assertEquals(replay(quiet).value, oneDip.value, 1e-10)
        for (i in 10 until 16) ticks[i] = ticks[i].copy(oxygen = 92.0)
        assertTrue(BodyBatteryEngine.replay(50.0, ticks, baseline).value < oneDip.value)
    }

    @Test fun increasingStressNeverImprovesReserveAndDriversClose() {
        for (anchor in listOf(0.0, 0.1, 20.0, 50.0, 90.0, 100.0)) {
            var previous = Double.POSITIVE_INFINITY
            for (stress in 20..100 step 10) {
                val r = replay(T(55, 50.0, stress, 0, 1.0), anchor = anchor)
                assertTrue(r.value <= previous + 1e-9)
                assertTrue(r.value in 0.0..100.0)
                val d = r.drivers
                assertEquals(r.value - anchor, d.recovery + d.restorativeRest - d.awake - d.movement - d.stress, 1e-9)
                previous = r.value
            }
        }
    }

    @Test fun effectiveDriversCloseAtZero() {
        val r = BodyBatteryEngine.replay(0.1, listOf(T(190, 10.0, 100, 1000, 10.0)), baseline)
        val d = r.drivers
        assertEquals(0.0, r.value, 0.0)
        assertEquals(r.value - 0.1, d.recovery - d.awake - d.movement - d.stress + d.restorativeRest, 1e-10)
    }

    @Test fun restCreditStartsAfterTwentyQuietMinutes() {
        val tick = T(55, 55.0, 20, 0, 1.0)
        val twenty = BodyBatteryEngine.replay(50.0, List(4) { tick }, baseline)
        val twentyFive = BodyBatteryEngine.replay(50.0, List(5) { tick }, baseline)
        assertEquals(0.0, twenty.drivers.restorativeRest, 0.0)
        assertTrue(twentyFive.drivers.restorativeRest > 0)
        assertTrue(twentyFive.value > twenty.value)
    }

    @Test fun recoveryMultiplierUsesServerLowerBound() {
        val b = BodyBatteryEngine.Baseline(restingHeartRate = 55.0, maximumHeartRate = 190.0, hrvMS = 50.0, recoveryMultiplier = 0.65)
        val r = BodyBatteryEngine.replay(20.0, List(96) { T(sleepStage = 2) }, b)
        assertEquals(95 - 75 * exp(-0.011 * 0.65 * 96), r.value, 1e-9)
    }

    @Test fun sleepDebtBounds() {
        assertEquals(1.0, BodyBatteryEngine.sleepDebt(480.0), 0.0)
        assertEquals(1.0, BodyBatteryEngine.sleepDebt(420.0), 0.0)
        assertEquals(1.6, BodyBatteryEngine.sleepDebt(240.0), 1e-12)
        assertEquals(1.6, BodyBatteryEngine.sleepDebt(60.0), 1e-12)
        assertEquals(1.0, BodyBatteryEngine.sleepDebt(null), 0.0)
        assertEquals(1.6, BodyBatteryEngine.sleepDebt(null, wornThroughTheNight = true), 0.0)
    }

    private fun workingDay(withWorkout: Boolean): List<BodyBatteryEngine.Tick> {
        val ticks = MutableList(216) { i ->
            when (i % 20) {
                in 0 until 8 -> T(60, 50.0, 45, 10, 1.1)
                in 8 until 17 -> T(80, 47.0, 50, 150, 2.0)
                else -> T(100, 44.0, 60, 450, 3.5)
            }
        }
        if (withWorkout) for (i in 0 until 12) {
            ticks[120 + i] = T(150, 38.0, 75, 900, 9.0)
            ticks[132 + i] = T(102, 40.0, 68, 120, 1.6)
        }
        return ticks
    }

    private fun close(slept: Double?, workout: Boolean): Double {
        val b = BodyBatteryEngine.Baseline(restingHeartRate = 55.0, maximumHeartRate = 190.0, hrvMS = 50.0,
            recoveryMultiplier = 1.0, sleepDebt = BodyBatteryEngine.sleepDebt(slept))
        return BodyBatteryEngine.replay(100.0, workingDay(workout), b).value
    }

    @Test fun drainCalibration() {
        val shortNight = close(240.0, false)
        val fullNight = close(480.0, false)
        assertTrue(shortNight > 55)
        assertTrue(shortNight < fullNight - 5)
        assertTrue(close(450.0, true) < close(450.0, false) - 10)
    }

    @Test fun oneHourOfZoneThreeOrFourCostsFourteenToTwentyTwo() {
        val heart = (55 + 0.75 * (190 - 55)).roundedAway().toInt()
        val b = BodyBatteryEngine.Baseline(restingHeartRate = 55.0, maximumHeartRate = 190.0, hrvMS = 50.0,
            recoveryMultiplier = 1.0, morningReadiness = 82.0)
        val r = BodyBatteryEngine.replay(82.0, List(12) { T(heart, 30.0, 60, 800, 8.0, inSession = true) }, b)
        val drop = 82 - r.value
        assertTrue(drop in 14.0..22.0)
    }

    @Test fun quietOfficeKeepsMorningReadiness() {
        val b = BodyBatteryEngine.Baseline(restingHeartRate = 52.0, maximumHeartRate = 190.0, hrvMS = 48.0,
            recoveryMultiplier = 1.0, sleepDebt = BodyBatteryEngine.sleepDebt(450.0), morningReadiness = 82.0)
        val r = BodyBatteryEngine.replay(82.0, List(120) { T(58, 48.0, 25, 40, 1.5) }, b)
        assertTrue(r.value >= 78)
        assertTrue(r.drivers.awake <= 3)
        assertEquals(0.0, r.drivers.movement, 0.05)
    }
}
