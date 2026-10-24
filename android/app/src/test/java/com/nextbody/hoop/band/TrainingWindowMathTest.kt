package com.nextbody.hoop.band

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class TrainingWindowMathTest {
    private val today = UserDay.containing(Instant.now())
    private fun fact(day: UserDay, load: Double?, zones: List<Int>? = null, open: Boolean = false) =
        TrainingDayFacts(day, load, null, null, zones, null, null, null, load != null, open)
    private fun point(day: UserDay, minute: Double, load: Double) =
        TrainingCurvePoint(BandTime.adding(day.start, minute * 60), load)

    @Test fun averageIgnoresTodayAndEmptySlots() {
        val facts = listOf(fact(today.adding(-6), 14.0), fact(today.adding(-5), null), fact(today.adding(-4), 10.0),
            fact(today.adding(-3), 12.0), fact(today.adding(-2), null), fact(today.adding(-1), 8.0), fact(today, 3.0, open = true))
        assertEquals(11.0, TrainingWindowMath.averageLoad(facts)!!, 0.001)
        assertEquals(5, TrainingWindowMath.wornCount(facts))
        assertEquals(2, TrainingWindowMath.emptyCount(facts))
        assertNull(TrainingWindowMath.averageLoad((0 until 7).map { fact(today.adding(-it), null) }))
    }

    @Test fun typicalZonesAndSessions() {
        val facts = listOf(fact(today.adding(-2), 12.0, listOf(60, 30, 20, 10, 5)), fact(today.adding(-1), 8.0),
            fact(today, 10.0, listOf(40, 20, 10, 20, 5), open = true))
        assertEquals(listOf(60.0, 30.0, 20.0, 10.0, 5.0), TrainingWindowMath.typicalZones(facts))
        val s = listOf(fact(today.adding(-2), 16.0, listOf(10, 10, 10, 15, 10)), fact(today.adding(-1), 9.0, listOf(40, 20, 10, 5, 0)),
            fact(today, 12.0, listOf(10, 10, 10, 30, 0)))
        assertEquals(2, TrainingWindowMath.sessionDays(s))
    }

    @Test fun bandAndRangeStatus() {
        assertEquals(TrainingBand.steady, TrainingWindowMath.band(12.4, 12.0..16.5))
        assertEquals(TrainingBand.light, TrainingWindowMath.band(10.0, 12.0..16.5))
        assertEquals(TrainingBand.heavy, TrainingWindowMath.band(17.0, 12.0..16.5))
        assertEquals(TrainingBand.over, TrainingWindowMath.band(20.9, 12.0..16.5))
        assertEquals(TrainingBand.unknown, TrainingWindowMath.band(9.0, null))
        assertEquals(TrainingRangeStatus.NoLoad, TrainingWindowMath.rangeStatus(null, 16.0, 14.0..18.0))
        assertEquals(TrainingRangeStatus.NoTarget, TrainingWindowMath.rangeStatus(6.4, null, null))
        assertEquals(TrainingRangeStatus.Below(4.0), TrainingWindowMath.rangeStatus(10.0, 16.0, 14.0..18.0))
        assertEquals(TrainingRangeStatus.InRange, TrainingWindowMath.rangeStatus(18.0, 16.0, 14.0..18.0))
        assertEquals(TrainingRangeStatus.Above(1.0), TrainingWindowMath.rangeStatus(19.0, 16.0, 14.0..18.0))
        assertEquals(TrainingRangeStatus.Capped, TrainingWindowMath.rangeStatus(20.9, 16.0, 14.0..18.0))
    }

    @Test fun weekRollsOldestFirst() {
        val facts = (0 until 16).map { back -> fact(today.adding(-(15 - back)), if (back == 3) null else 10.0) }
        val rolls = TrainingWindowMath.weekRolls(facts)
        assertEquals(listOf(2, 7, 7), rolls.map { it.days })
        assertEquals(today, rolls.last().end)
        assertEquals(10.0, rolls[1].average!!, 0.001)
        assertEquals(listOf(2, 7, 7, 7, 7), TrainingWindowMath.weekRolls(today.rollingBack(30).map { fact(it, 6.0) }).map { it.days })
    }

    @Test fun historyWithoutOwnTargetRemainsUnknown() {
        val historical = fact(today.adding(-1), 16.0)
        val current = fact(today, 6.0, open = true).copy(zone = 3.0..7.0)
        val first = TrainingWindowMath.bandCounts(listOf(historical, current))
        assertEquals(1, first.unknown); assertEquals(0, first.heavy)
        assertEquals(1, TrainingWindowMath.bandCounts(listOf(historical.copy(zone = 10.0..14.0), current)).heavy)
    }

    @Test fun curveData() {
        val day = today
        val empty = TrainingWindowMath.curveData(emptyList(), day, day.start.plusSeconds(3600))
        assertTrue(empty.segments.isEmpty())
        assertEquals(listOf(DateInterval(day.start, day.start.plusSeconds(3600))), empty.gaps)

        val points = listOf(point(day, 60.0, 2.0), point(day, 65.0, 3.0), point(day, 90.0, 5.0))
        val curve = TrainingWindowMath.curveData(points, day, day.start.plusSeconds(120 * 60))
        assertEquals(listOf(points.take(2), listOf(points[2])), curve.segments)
        assertEquals(listOf(60.0, 20.0, 25.0), curve.gaps.map { it.duration / 60 })
        assertEquals(day.start.plusSeconds(70 * 60), curve.gaps[1].start)

        val first = point(day, 0.0, 2.0); val second = point(day, 5.0, 3.0); val future = point(day, 120.0, 9.0)
        val c2 = TrainingWindowMath.curveData(listOf(second, future, first), day, day.start.plusSeconds(600))
        assertEquals(listOf(listOf(first, second)), c2.segments)
        assertTrue(c2.gaps.isEmpty())
    }

    @Test fun dayFractionAndLineRuns() {
        assertEquals(0.0, TrainingWindowMath.dayFraction(today.start, today), 0.0)
        assertEquals(1.0, TrainingWindowMath.dayFraction(today.end, today), 0.0)
        fun idx(v: List<Double?>) = TrainingWindowMath.lineRuns(v).map { r -> r.map { it.index } }
        assertEquals(listOf(listOf(0, 1), listOf(3)), idx(listOf(1.0, 2.0, null, 4.0)))
        assertEquals(listOf(listOf(1, 2), listOf(5)), idx(listOf(null, 3.0, 4.0, null, null, 9.0)))
        assertEquals(emptyList<List<Int>>(), idx(listOf(null, null)))
    }
}
