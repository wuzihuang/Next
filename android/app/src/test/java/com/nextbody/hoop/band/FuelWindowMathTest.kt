package com.nextbody.hoop.band

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime

class FuelWindowMathTest {
    private val utc: ZoneId = ZoneOffset.UTC
    private fun at(month: Int, day: Int, hour: Int, minute: Int = 0, zone: ZoneId = utc): Instant =
        ZonedDateTime.of(2026, month, day, hour, minute, 0, 0, zone).toInstant()

    private fun fact(day: UserDay, intake: Double?, burned: Double?, foods: Int, fasted: Boolean = false, open: Boolean = false) =
        FuelDayFacts(day, intake, burned, foods, fasted, open)

    @Test fun measuredMetWinsAndInvalidFallsBack() {
        assertEquals(6.0, FuelWindowMath.activityMet(6.0, 0)!!, 0.0)
        assertEquals(3.0, FuelWindowMath.activityMet(0.0, 500)!!, 0.0)
        assertEquals(3.0, FuelWindowMath.activityMet(Double.NaN, 500)!!, 0.0)
        assertNull(FuelWindowMath.activityMet(26.0, null))
    }

    @Test fun burnCurveKeepsRestingSlopeAndOpeningTick() {
        val start = at(9, 5, 4)
        val now = start.plusSeconds(8 * 3600)
        val middle = start.plusSeconds(4 * 3600)
        val ticks = listOf(VitalSample(ts = start, hr = null, stress = null, steps = 0, met = 6.0),
            VitalSample(ts = middle, hr = null, stress = null, steps = 0, met = 1.0))
        val line = FuelWindowMath.burnCurve(start, now, 800.0, 1800.0, 500.0, ticks, utc)
        assertEquals(800.0, line.solid.last().y, 0.0)
        val middleX = FuelWindowMath.clockFraction(middle, start, utc)
        assertEquals(550.0, line.solid.last { it.x == middleX }.y, 1e-9)
    }

    @Test fun settledMovementWithoutTimedEvidenceHasNoCurve() {
        val start = Instant.now()
        assertTrue(FuelWindowMath.burnCurve(start, start.plusSeconds(3600), 500.0, 2000.0, 60.0, emptyList(), utc).solid.isEmpty())
    }

    @Test fun weekSumIncludesFastedZero() {
        val today = UserDay.containing(Instant.now())
        val facts = listOf(
            fact(today.adding(-6), 2840.0, 2710.0, 6), fact(today.adding(-5), 2650.0, 2890.0, 5),
            fact(today.adding(-4), 0.0, 2180.0, 0, fasted = true), fact(today.adding(-3), 3120.0, 2760.0, 8),
            fact(today.adding(-2), 2410.0, 2680.0, 4), fact(today.adding(-1), 2780.0, 2540.0, 6),
            fact(today, 1070.0, 820.0, 3, open = true))
        val total = FuelWindowMath.sum(facts)!!
        assertEquals(14870.0, total.intake!!, 1e-9)
        assertEquals(16580.0, total.burned!!, 1e-9)
        assertEquals(-1710.0, total.gap!!, 1e-9)
        assertEquals(2124.285, FuelWindowMath.perDay(total, 7)!!.intake!!, 0.01)
    }

    @Test fun emptyWindowHasNoSumAndMismatchedDaysNoGap() {
        val today = UserDay.containing(Instant.now())
        assertNull(FuelWindowMath.sum((0 until 7).map { fact(today.adding(-it), null, null, 0) }))
        val mismatched = FuelWindowMath.sum(listOf(fact(today.adding(-1), 1800.0, null, 3), fact(today, null, 2000.0, 0)))!!
        assertEquals(1800.0, mismatched.intake!!, 0.0)
        assertNull(mismatched.gap)
        assertEquals(0, mismatched.pairedDays)
    }

    @Test fun typicalDayUsesObservedClosedDays() {
        val today = UserDay.containing(Instant.now())
        val facts = (0 until 28).map { fact(today.adding(it - 27), null, null, 0) }.toMutableList()
        facts[0] = fact(facts[0].day, 1800.0, 2000.0, 3)
        facts[8] = fact(facts[8].day, 2200.0, null, 3)
        facts[9] = fact(facts[9].day, 2300.0, null, 3)
        facts[27] = fact(today, 200.0, 150.0, 1, open = true)
        val typical = FuelWindowMath.typicalDay(FuelWindowMath.weekRolls(facts))!!
        assertEquals(2100.0, typical.intake!!, 1e-9)
        assertEquals(2000.0, typical.burned!!, 1e-9)
        assertEquals(-200.0, typical.gap!!, 1e-9)
        assertEquals(3, typical.intakeDays); assertEquals(1, typical.burnedDays); assertEquals(1, typical.pairedDays)
    }

    @Test fun typicalDayIsMeanOfWeeks() {
        val today = UserDay.containing(Instant.now())
        val facts = mutableListOf<FuelDayFacts>()
        listOf(2480.0, 2210.0, 2540.0, 2120.0).forEachIndexed { week, daily ->
            for (day in 0 until 7) facts.add(fact(today.adding(-((3 - week) * 7 + (6 - day))), daily, daily + 200, 4))
        }
        val rolls = FuelWindowMath.weekRolls(facts)
        assertEquals(4, rolls.size)
        assertEquals(today, rolls.first().end)
        assertEquals(2337.5, FuelWindowMath.typicalDay(rolls)!!.intake!!, 0.01)
    }

    @Test fun clockFractionAndDstLabels() {
        val start = at(9, 5, 4)
        assertEquals(9.333 / 24, FuelWindowMath.clockFraction(at(9, 5, 13, 20), start, utc), 0.002)
        assertEquals(21.333 / 24, FuelWindowMath.clockFraction(at(9, 6, 1, 20), start, utc), 0.001)
        val ny = ZoneId.of("America/New_York")
        for ((md, hours) in listOf(Pair(3 to 7, 23.0), Pair(10 to 31, 25.0))) {
            val s = at(md.first, md.second, 4, zone = ny)
            val end = FuelWindowMath.dayEnd(s, ny)
            assertEquals(hours, BandTime.interval(end, s) / 3600, 0.0)
            assertEquals(0.5, FuelWindowMath.clockFraction(BandTime.adding(s, hours * 1800), s, ny), 1e-12)
            assertEquals(1.0, FuelWindowMath.clockFraction(end, s, ny), 0.0)
            val labels = FuelWindowMath.clockLabels(s, ny)
            assertEquals("04", labels.first()); assertEquals("04", labels.last()); assertEquals(5, labels.size)
        }
    }

    @Test fun intakeStepsAndBurnLine() {
        val start = at(9, 5, 4); val now = at(9, 5, 13, 20)
        val line = FuelWindowMath.intakeSteps(listOf(at(9, 5, 7, 40) to 350.0, at(9, 5, 12, 35) to 720.0), start, now, 2900.0, utc)
        assertEquals(1070.0, line.solid.last().y, 0.0)
        assertEquals(2900.0, line.dashed.last().y, 0.0)
        assertTrue(line.solid.last().x in 0.3..0.4)
        val burn = FuelWindowMath.burnLine(start, now, 820.0, 2280.0, utc)
        assertEquals(0.0, burn.solid.first().x, 0.001)
        assertEquals(0.0, burn.solid.first().y, 0.0)
        assertEquals(820.0, burn.solid.last().y, 0.0)
        assertEquals(2280.0, burn.dashed.last().y, 0.0)
    }

    @Test fun burnCurveSteepensWhenStepsCluster() {
        val start = at(9, 5, 4); val now = at(9, 5, 13, 20)
        val ticks = mutableListOf<VitalSample>()
        var cursor = start
        while (cursor <= now) {
            val hour = cursor.atZone(utc).hour
            ticks.add(VitalSample(ts = cursor, hr = null, stress = null, steps = if (hour == 11) 400 else 8))
            cursor = cursor.plusSeconds(300)
        }
        val line = FuelWindowMath.burnCurve(start, now, 820.0, 2280.0, 700.0, ticks, utc)
        assertEquals(820.0, line.solid.last().y, 1e-9)
        val morning = line.solid.last { it.x < 6.0 / 24 }.y
        val afterWalk = line.solid.last { it.x < 8.0 / 24 }.y
        assertTrue(afterWalk - morning > morning * 0.15)
    }
}
