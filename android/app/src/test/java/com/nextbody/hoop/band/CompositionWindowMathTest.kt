package com.nextbody.hoop.band

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.UUID

class CompositionWindowMathTest {
    private fun day(y: Int, m: Int, d: Int, hour: Int = 12): Instant =
        ZonedDateTime.of(y, m, d, hour, 0, 0, 0, ZoneId.systemDefault()).toInstant()
    private fun scan(at: Instant, fat: Double?, fatMass: Double? = 13.4, lean: Double? = 62.1) =
        CompositionScan(UUID.randomUUID(), at, fat, fatMass, lean, 1640.0, 75.5)

    @Test fun currentIgnoresLaterScanAndReadingHasDelta() {
        val now = day(2026, 9, 5, 10)
        val scans = listOf(scan(day(2026, 9, 5, 18), 17.0), scan(day(2026, 9, 5, 7), 17.8, 13.4, 62.1), scan(day(2026, 9, 3, 7), 18.0, 13.6, 62.0))
        assertEquals(17.8, CompositionWindowMath.current(scans, now)!!.bodyFatPercent!!, 0.0)
        val r = CompositionWindowMath.dayReading(scans, now)!!
        assertEquals(-0.2, r.bodyFat.delta!!, 1e-4)
        assertEquals(-0.2, r.fatMass.delta!!, 1e-4)
        assertEquals(0.1, r.leanMass.delta!!, 1e-4)
        assertNull(CompositionWindowMath.dayReading(listOf(scan(day(2026, 9, 5, 7), 17.8)), now)!!.bodyFat.delta)
        assertNull(CompositionWindowMath.dayReading(emptyList(), now))
    }

    @Test fun weekPointsBreakTheLine() {
        val friday = UserDay.containing(day(2026, 9, 4))
        val days = friday.rollingBack(7)
        val scans = listOf(scan(friday.start.plusSeconds(3 * 3600), 17.8),
            scan(friday.adding(-1).start.plusSeconds(3 * 3600), 17.9), scan(friday.adding(-3).start.plusSeconds(3 * 3600), 18.0))
        val points = CompositionWindowMath.weekPoints(scans, days)
        assertEquals(listOf(18.0, 17.9, 17.8), points.map { it.value })
        val runs = CompositionWindowMath.runs(points, days)
        assertEquals(listOf(listOf(18.0), listOf(17.9, 17.8)), runs.map { r -> r.map { it.value } })
    }

    @Test fun plots() {
        val friday = UserDay.containing(day(2026, 9, 4))
        val week = CompositionWindowMath.plot(listOf(scan(friday.start.plusSeconds(3 * 3600), 17.8),
            scan(friday.adding(-2).start.plusSeconds(3 * 3600), 18.1)), RollingPills.week, friday, friday.start.plusSeconds(10 * 3600))
        assertEquals(2, week.scanCount)
        assertEquals(17.95, week.median!!, 1e-4)
        assertTrue(week.yMax > 18.1 && week.yMin < 17.8)
        val end = UserDay.containing(day(2026, 9, 5))
        val month = CompositionWindowMath.plot(listOf(scan(day(2026, 8, 10, 7), 18.4), scan(day(2026, 8, 20, 7), 18.1),
            scan(day(2026, 9, 5, 7), 17.8)), RollingPills.month, end, day(2026, 9, 5, 10))
        assertEquals(1, month.runs.size)
        assertEquals(listOf(18.4, 18.1, 17.8), month.points.map { it.value })
        val d = CompositionWindowMath.plot(listOf(scan(day(2026, 9, 5, 7), 17.8)), RollingPills.day, end, day(2026, 9, 5, 10))
        assertTrue(d.points.isEmpty()); assertEquals(1, d.scanCount)
    }

    @Test fun weekBucketsAndScale() {
        val end = UserDay.containing(day(2026, 9, 5))
        val buckets = CompositionWindowMath.weekBuckets(listOf(scan(day(2026, 9, 5, 7), 17.8), scan(day(2026, 9, 3, 7), 18.0),
            scan(day(2026, 8, 28, 7), 18.2), scan(day(2026, 8, 26, 7), 18.4)), end, 4)
        assertEquals(17.9, buckets[0].averageFat!!, 1e-4)
        assertEquals(18.3, buckets[1].averageFat!!, 1e-4)
        assertEquals(-0.4, buckets[0].delta!!, 1e-4)
        assertNull(buckets[3].delta)
        val s = CompositionWindowMath.scale(listOf(18.0, 18.0))
        assertEquals(17.6, s.min, 0.001); assertEquals(18.4, s.max, 0.001)
        val span = CompositionWindowMath.span({ it.fatMassKg }, listOf(scan(day(2026, 9, 5, 7), 17.8, 13.4), scan(day(2026, 8, 10, 7), 18.4, 14.0)))
        assertEquals(14.0, span.first!!, 0.0); assertEquals(13.4, span.last!!, 0.0)
    }

    @Test fun weekCells() {
        val end = UserDay.containing(day(2026, 9, 26))
        fun week(o: Int) = end.adding(-o * 7)
        val scans = listOf(scan(week(24).start.plusSeconds(3600), 18.0, 14.0, 60.0), scan(week(10).start.plusSeconds(3600), 17.0, 13.0, 60.2),
            scan(week(4).start.plusSeconds(3600), 18.2, 14.3, 60.2), scan(week(1).start.plusSeconds(3600), 18.2, 14.4, 60.15))
        val cells = CompositionWindowMath.weekCells(scans, CompositionAim.recomp, end)
        assertEquals(26, cells.size)
        assertEquals(CompositionWeekTone.noScan, cells[0].tone)
        assertEquals(CompositionWeekTone.held, cells[1].tone)
        assertEquals(CompositionWeekTone.aligned, cells[15].tone)
        assertEquals(CompositionWeekTone.drift, cells[21].tone)
        assertEquals(CompositionWeekTone.held, cells[24].tone)
        assertEquals(CompositionWeekTone.noScan, cells[25].tone)
        assertEquals(CompositionWeekTone.aligned, CompositionWindowMath.classify(0.3, 0.2, CompositionAim.bulk))
        assertEquals(CompositionWeekTone.drift, CompositionWindowMath.classify(0.3, 0.2, CompositionAim.cut))
        assertEquals(CompositionWeekTone.drift, CompositionWindowMath.classify(0.0, -0.2, CompositionAim.bulk))
        assertEquals(CompositionWeekTone.held, CompositionWindowMath.classify(null, null, CompositionAim.cut))
    }
}
