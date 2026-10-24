package com.nextbody.hoop.band

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import kotlin.math.abs
import com.nextbody.hoop.band.BatteryObservation.Charge as C

class BatteryMathTest {
    private val t0: Instant = Instant.ofEpochSecond(1_800_000_000)
    private fun h(hours: Double): Instant = BandTime.adding(t0, hours * 3600)
    private fun obs(at: Instant, percent: Int, charge: BatteryObservation.Charge = BatteryObservation.Charge.unplugged, connected: Boolean = true) =
        BatteryObservation(at, true, percent, null, charge, connected)

    @Test fun progressCurves() {
        assertTrue(BatteryDrainMath.progress(0.5, rising = false) < 0.5)
        assertTrue(BatteryDrainMath.progress(0.5, rising = true) > 0.5)
        assertEquals(1.0, BatteryDrainMath.progress(1.0, rising = false), 1e-4)
    }

    @Test fun drainRateLearnsAndFallsBack() {
        assertEquals(2.0, BatteryDrainMath.drainRate(listOf(obs(t0, 90), obs(h(3.0), 84), obs(h(6.0), 78)), 100.0), 0.01)
        assertEquals(100 / BatteryDrainMath.packHours, BatteryDrainMath.drainRate(listOf(obs(t0, 80)), 100.0), 1e-4)
        assertEquals(0.5, BatteryDrainMath.drainRate(listOf(obs(t0, 80), obs(h(2.0), 80), obs(h(2.5), 79), obs(h(8.0), 76)), 100.0), 0.001)
        val sparse = listOf(obs(t0, 90), obs(h(12.0), 84))
        val frequent = (0..24).map { obs(h(it * 0.5), 90 - it / 4) }
        assertEquals(BatteryDrainMath.drainRate(sparse, 100.0), BatteryDrainMath.drainRate(frequent, 100.0), 0.001)
    }

    @Test fun recentCycleReplacesOldOne() {
        val samples = (0..12).map { obs(h(it.toDouble()), 90 - 2 * it) } +
            listOf(obs(h(13.0), 66, C.charging), obs(h(15.0), 100, C.full), obs(h(16.0), 100), obs(h(28.0), 94))
        assertEquals(0.5, BatteryDrainMath.drainRate(samples, 100.0), 0.001)
    }

    @Test fun etaSilences() {
        val charge = listOf(obs(t0, 90), obs(h(1.0), 90, C.charging), obs(h(8.0), 86))
        assertNull(BatteryDrainMath.eta(charge, charge.last().at))
        val tiny = listOf(obs(t0, 80), obs(h(1.0), 79))
        assertNull(BatteryDrainMath.eta(tiny, tiny.last().at))
        val old = listOf(obs(t0, 90), obs(h(12.0), 84))
        assertNull(BatteryDrainMath.eta(old, BandTime.adding(old.last().at, 25.0 * 3600)))
    }

    @Test fun previousCycleTeachesNewlyUnplugged() {
        val samples = listOf(obs(t0, 90), obs(h(12.0), 84), obs(h(13.0), 84, C.charging), obs(h(14.0), 100, C.full), obs(h(15.0), 100))
        val eta = BatteryDrainMath.eta(samples, samples.last().at) as BatteryEta.Empty
        assertEquals(200.0 * 3600, BandTime.interval(eta.at, samples.last().at), 1.0)
    }

    @Test fun cachedDisconnectAgesLastReading() {
        val disconnect = obs(h(12.0), 84, connected = false)
        val samples = listOf(obs(t0, 90), obs(h(6.0), 84), disconnect)
        assertEquals(1.0, BatteryDrainMath.drainRate(samples, 100.0), 0.001)
        val eta = BatteryDrainMath.eta(samples, disconnect.at) as BatteryEta.Empty
        assertEquals(78.0 * 3600, BandTime.interval(eta.at, disconnect.at), 1.0)
    }

    @Test fun recordRules() {
        val first = BatteryLog.record(emptyList(), t0, true, 82, null, C.unplugged, true)
        assertEquals(1, BatteryLog.record(first, h(60.0 / 3600), true, 82, null, C.unplugged, true).size)
        assertEquals(2, BatteryLog.record(first, h(0.5), true, 82, null, C.unplugged, true).size)
        assertEquals(listOf(C.full), BatteryLog.record(emptyList(), t0, true, 100, null, C.charging, true).map { it.charge })
        assertEquals(listOf(C.charging), BatteryLog.record(emptyList(), t0, true, 99, null, C.charging, true).map { it.charge })
        val on = BatteryLog.record(emptyList(), t0, true, 70, null, C.unplugged, true)
        assertEquals(listOf(true, false), BatteryLog.record(on, h(10.0 / 3600), true, 70, null, C.unplugged, false).map { it.connected })
        val old = BatteryLog.record(emptyList(), h(-31.0 * 24), true, 10, null, C.unplugged, true)
        assertEquals(listOf<Int?>(80), BatteryLog.record(old, t0, true, 80, null, C.unplugged, true).map { it.percent })
        val kept = BatteryLog.record(emptyList(), h(-29.0 * 24), true, 10, null, C.unplugged, true)
        assertEquals(listOf<Int?>(10, 80), BatteryLog.record(kept, t0, true, 80, null, C.unplugged, true).map { it.percent })
    }

    @Test fun windowsAreRollingHours() {
        val day = BatteryLog.window(t0, RollingPills.day)
        val month = BatteryLog.window(t0, RollingPills.month)
        assertEquals(24.0 * 3600, BandTime.interval(day.end, day.start), 0.001)
        assertEquals(30.0 * 24 * 3600, BandTime.interval(month.end, month.start), 0.001)
    }

    @Test fun plotFillsQuietStretchWithDrainCurve() {
        val samples = listOf(obs(t0, 80), obs(h(6.0), 68), obs(h(6.0), 68, connected = false), obs(h(12.0), 62))
        val end = h(18.0)
        val plot = BatteryLog.plot(samples, t0, end)
        val points = plot.points
        assertEquals(80.0, points.first().value, 0.0)
        assertEquals(end, points.last().at)
        assertTrue(points.last().estimated)
        assertEquals(53.0, points.last().value, 0.01)
        assertTrue(points.any { it.value == 62.0 && !it.estimated })
        assertTrue(points.count { it.estimated } > 2)
        assertEquals(80.0, plot.high!!, 0.0)
        val midAt = h(3.0)
        val mid = points.minBy { abs(BandTime.interval(it.at, midAt)) }
        assertNotEquals(74.0, mid.value, 0.05)
    }

    @Test fun seedEndsOnPercent() {
        val seed = BatteryLog.seed(t0, 82)
        assertEquals(82, seed.last().percent)
    }
}
