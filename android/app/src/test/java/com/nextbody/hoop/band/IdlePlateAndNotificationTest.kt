package com.nextbody.hoop.band

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset

class IdlePlateAndNotificationTest {
    private val wearer = "wearer-lock-tests"
    private val day = "2026-09-13"
    private val next = "2026-09-14"

    @Test fun sameDaySamePlate() {
        var stored: IdlePlateLock.Snapshot? = null
        val plates = (0 until 5).map { i ->
            stored = IdlePlateLock.appear(wearer, day, stored, false, 8 + i, 60 + i * 10); stored!!.plate
        }
        assertEquals(1, plates.toSet().size)
        assertEquals(IdlePlateLock.LockedBy.daily, stored!!.lockedBy)
        assertTrue(plates[0] in IdlePlateLock.dayPool)
    }

    @Test fun newDayTakesWhenNotVisibleAndSkipsYesterday() {
        val first = IdlePlateLock.appear(wearer, day, null, false)
        val watching = IdlePlateLock.appear(wearer, next, first, true, 0, 90)
        assertEquals(first, watching)
        val flipped = IdlePlateLock.appear(wearer, next, watching, false)
        assertEquals(next, flipped.day)
        assertNotEquals(first.plate, flipped.plate)
    }

    @Test fun forbiddenNeverDrawn() {
        for (d in 0 until 40) {
            val plate = IdlePlateLock.dailyPlate(wearer, String.format("2026-09-%02d", 1 + d % 28), null)
            assertFalse(plate in IdlePlateLock.forbidden)
            assertFalse(plate in listOf(11, 20, 25))
        }
    }

    @Test fun eventsAndEdges() {
        var snap = IdlePlateLock.appear(wearer, day, null, false)
        assertEquals(IdlePlateLock.Event.lowReserve, IdlePlateLock.edge(22, 70, 80, false, 0.0))
        snap = IdlePlateLock.applyEvent(IdlePlateLock.Event.lowReserve, snap, day)
        assertEquals(25, snap.plate)
        assertEquals(25, IdlePlateLock.applyEvent(IdlePlateLock.Event.bandAway, snap, day).plate)
        assertEquals(IdlePlateLock.Event.lowBandCharge, IdlePlateLock.edge(60, 70, 12, false, 0.0))
        assertNull(IdlePlateLock.edge(60, 70, 12, true, 0.0))
        val now = Instant.ofEpochSecond(1_800_000_000)
        val dt = IdlePlateLock.disconnectedFor(true, false, now.minusSeconds(4 * 3600), now)
        assertEquals(IdlePlateLock.Event.bandAway, IdlePlateLock.edge(60, 70, 80, false, dt))
        assertEquals(0.0, IdlePlateLock.disconnectedFor(false, false, now.minusSeconds(36000), now), 0.0)
        assertNull(IdlePlateLock.edge(25, 20, 80, false, 0.0))
        val visit = IdlePlateLock.Snapshot(day, 4, IdlePlateLock.LockedBy.visit)
        assertEquals(visit, IdlePlateLock.applyEvent(IdlePlateLock.Event.lowReserve, visit, day))
    }

    @Test fun advanceVisitWalksRoster() {
        var previous: Int? = null
        val seen = (1..28).map { previous = IdlePlateLock.advanceVisit(previous); previous!! }
        assertEquals((1..28).toList(), seen)
        assertEquals(1, IdlePlateLock.advanceVisit(28))
        assertEquals(1, IdlePlateLock.advanceVisit(99))
    }

    @Test fun motionHoldPoseIsStable() {
        assertEquals(IdlePlateMotion.samples(2, 1.0, false), IdlePlateMotion.samples(2, 5.0, false))
        assertEquals(0.0, IdlePlateMotion.orbitProgress(0.0), 1e-9)
        assertEquals(0.5, IdlePlateMotion.orbitProgress(0.5), 1e-9)
        assertEquals(0.0, IdlePlateMotion.flicker(0.0, 3.0), 1e-12)
    }

    @Test fun glitterIsDeterministic() {
        val a = GlitterWrapField(seed = 42uL); val b = GlitterWrapField(seed = 42uL)
        a.step(1.0 / 60); b.step(1.0 / 60)
        assertEquals(a.samples(), b.samples())
        val frozen = a.samples(); a.step(1.0 / 60, moving = false)
        assertEquals(frozen, a.samples())
    }

    // Notifications
    private val utc = ZoneOffset.UTC
    private fun date(y: Int, m: Int, d: Int, h: Int, min: Int = 0) = LocalDateTime.of(y, m, d, h, min).toInstant(utc)
    private fun snap(now: Instant, quiet: Boolean = false, morningOn: Boolean = false, mealsOn: Boolean = false,
                     trainingOn: Boolean = false, wrapOn: Boolean = false, wakePeak: Instant? = null,
                     meals7: Int = 0, breakfast: Boolean = false, moved: Boolean = false, load: Double? = null,
                     target: Double? = null, reserveNow: Int? = null, prev: Int? = null, wake: Int? = null,
                     dayHigh: Int? = null, nightCharge: Boolean = false, weekRolled: Boolean = false, priorDays: Int = 0) =
        NotifySnapshot(now, quiet, 0, emptySet(), NotifyPage.other, morningOn, trainingOn, mealsOn, wrapOn, false, false,
            wakePeak, false, false, meals7, breakfast, false, false, moved, load, target, reserveNow, prev, wake, dayHigh,
            false, true, nightCharge, false, weekRolled, priorDays, false, true, true, false, null, null, null)

    @Test fun deepLinks() {
        assertEquals(NotificationDeepLink.HomePanel, NotificationDeepLink.parse("nextbody://home?panel=body_battery"))
        assertEquals(NotificationDeepLink.Home, NotificationDeepLink.parse("nextbody://home"))
        assertEquals(NotificationDeepLink.Fuel("dinner"), NotificationDeepLink.parse("nextbody://fuel?slot=dinner"))
        assertEquals(NotificationDeepLink.Composition("2025-11-02"), NotificationDeepLink.parse("nextbody://composition?date=2025-11-02"))
        assertEquals(NotificationDeepLink.LogPhoto, NotificationDeepLink.parse("nextbody://log?via=photo"))
        assertNull(NotificationDeepLink.parse("nextbody://home?panel=sleep"))
        assertNull(NotificationDeepLink.parse("https://nextbody.app"))
        assertEquals("nextbody://fuel?slot=lunch", NotificationDeepLink.Fuel("lunch").url)
    }

    @Test fun quietAndMorning() {
        assertTrue(NotificationReachMath.isQuiet(date(2026, 9, 6, 22, 30), utc))
        assertTrue(NotificationReachMath.isQuiet(date(2026, 9, 6, 6, 59), utc))
        assertFalse(NotificationReachMath.isQuiet(date(2026, 9, 6, 7), utc))
        assertEquals(NotifyPlan.Later(NotifyKind.morning, date(2026, 9, 6, 7), null, false),
            NotificationReachMath.decide(snap(date(2026, 9, 6, 6, 20), quiet = true, morningOn = true, wakePeak = date(2026, 9, 6, 6, 12)), utc))
        assertEquals(NotifyPlan.Fire(NotifyKind.morning, null, false),
            NotificationReachMath.decide(snap(date(2026, 9, 6, 8, 45), morningOn = true, wakePeak = date(2026, 9, 6, 8, 40)), utc))
        assertEquals(MorningNotifyPlan.Skip("PAST_WINDOW"), NotificationReachMath.planMorning(date(2026, 9, 6, 14), date(2026, 9, 6, 7), false, true, true, utc))
        assertEquals(MorningNotifyPlan.Skip("NO_NIGHT"), NotificationReachMath.planMorning(date(2026, 9, 6, 8), null, false, true, true, utc))
        val curve = listOf(date(2026, 9, 6, 5) to 40, date(2026, 9, 6, 7, 12) to 72, date(2026, 9, 6, 16) to 30)
        assertEquals(date(2026, 9, 6, 7, 12), NotificationReachMath.wakePeak(date(2026, 9, 6, 4), curve))
    }

    @Test fun mealTrainingDaily() {
        val now = date(2026, 9, 6, 13)
        assertEquals(NotifyPlan.Fire(NotifyKind.meal, "lunch", false),
            NotificationReachMath.decide(snap(now, mealsOn = true, meals7 = 3, breakfast = true, moved = true), utc))
        assertEquals(NotifyPlan.Skip, NotificationReachMath.decide(snap(now, mealsOn = true, meals7 = 3, breakfast = true), utc))
        assertEquals(NotifyPlan.Fire(NotifyKind.training, null, false), NotificationReachMath.decide(
            snap(date(2026, 9, 6, 15), trainingOn = true, load = 3.9, target = 14.5, reserveNow = 40, prev = 55, wake = 72, dayHigh = 72), utc))
        assertEquals(NotifyPlan.Skip, NotificationReachMath.decide(
            snap(date(2026, 9, 6, 15), trainingOn = true, load = 3.9, target = 14.5, reserveNow = 70, prev = 72, wake = 72, dayHigh = 72), utc))
        assertEquals(NotifyPlan.Fire(NotifyKind.daily, null, true), NotificationReachMath.decide(
            snap(date(2026, 9, 7, 8), wrapOn = true, load = 4.0, nightCharge = true, weekRolled = true, priorDays = 5), utc))
    }

    // Widget
    @Test fun widgetFace() {
        val g = WidgetFaceMath.Glance.placeholder
        val fresh = WidgetFaceMath.today(g, BandTime.adding(g.numbersAt, 60.0), utc)
        assertEquals("72", fresh.batteryText); assertEquals("12.4", fresh.loadText)
        assertEquals("8,432", fresh.stepsText); assertEquals("6.2", fresh.distanceText)
        assertEquals("320", fresh.activeText); assertEquals("78", fresh.sleepText); assertEquals("7:12", fresh.sleepClockText)
        assertFalse(fresh.stale); assertNull(fresh.clock)
        val stale = WidgetFaceMath.today(g, BandTime.adding(g.numbersAt, 91.0 * 60), utc)
        assertTrue(stale.stale); assertEquals(WidgetFaceMath.dash, stale.loadText)
        assertEquals("72", stale.batteryText); assertTrue(stale.batteryDim)
        assertEquals("78", stale.sleepText)
        val gone = WidgetFaceMath.today(g, BandTime.adding(g.numbersAt, 6.0 * 3600), utc)
        assertEquals(WidgetFaceMath.dash, gone.batteryText)
        val out = WidgetFaceMath.today(g.copy(signedIn = false), g.numbersAt, utc)
        assertEquals(WidgetFaceMath.dash, out.sleepText); assertFalse(out.bandLit)
        assertEquals("20.9", WidgetFaceMath.loadText(25.0))
        assertEquals(BandTime.adding(g.numbersAt, 15.0 * 60), WidgetFaceMath.nextReload(g, g.numbersAt))
    }
}
