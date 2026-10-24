package com.nextbody.hoop.band

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class VeepooMappingTest {
    private fun slot(rate: Int = 0, ppgs: List<Int> = emptyList(), ecgs: List<Int> = emptyList(),
                     km: Double = 0.0, pressure: Int? = null, temp: Double? = null) =
        VeepooMapping.OriginSlot(time = "07:05", rateValue = rate, ppgs = ppgs, ecgs = ecgs, steps = 0,
            calories = 3.7, distanceKm = km, pressure = pressure, temperature = temp)

    @Test fun heartPrefersTheRateThenPpgsThenEcgs() {
        assertEquals(64, VeepooMapping.point(slot(rate = 64, ppgs = listOf(80))).heart)
        assertEquals(71, VeepooMapping.point(slot(ppgs = listOf(70, 0, 72))).heart)
        assertEquals(55, VeepooMapping.point(slot(ecgs = listOf(55))).heart)
    }

    @Test fun zeroIsTheBandSayingNothingNotAReading() {
        val p = VeepooMapping.point(slot(ppgs = listOf(0, 0), pressure = 0, temp = 0.0))
        assertNull(p.heart)
        assertNull(p.stress)
        assertNull(p.temperature)
        // Steps keep their zeros: a still hour is a fact.
        assertEquals(0, p.step)
        assertEquals(3, p.cal)
    }

    @Test fun distanceArrivesInKilometresAndIsStoredInMetres() {
        assertEquals(1250, VeepooMapping.point(slot(km = 1.25)).distance)
        assertEquals(1000, VeepooMapping.point(slot(km = 1.0)).distance)
        assertEquals(0, VeepooMapping.point(slot(km = 0.0)).distance)
    }

    @Test fun repeatStringIsTheMaskRightToLeftMondayFirst() {
        // 1100000 · Sunday, Saturday · 0000011 · Tuesday, Monday (vendor doc)
        assertEquals(0b1100000, VeepooMapping.repeatMask("1100000"))
        assertEquals(0b0000011, VeepooMapping.repeatMask("0000011"))
        assertEquals("0011111", VeepooMapping.repeatString(BandAlarmMath.weekdaysMask))
        for (mask in 0..127) assertEquals(mask, VeepooMapping.repeatMask(VeepooMapping.repeatString(mask)))
        assertNull(VeepooMapping.repeatMask("12"))
    }

    @Test fun pulseIntervalsReadTheUnitOffTheNumbers() {
        val ms = List(10) { 850.0 + it }
        assertEquals(PulseStudy.Source.intervals, VeepooMapping.pulseIntervals(ms, emptyList()).second)
        assertEquals(10, VeepooMapping.pulseIntervals(ms, emptyList()).first.size)
        val hundredths = List(10) { 85.0 + it }
        val scaled = VeepooMapping.pulseIntervals(hundredths, emptyList())
        assertEquals(850.0, scaled.first.first(), 0.001)
        val counts = List(10) { 0.2 }
        val rates = VeepooMapping.pulseIntervals(counts, List(10) { 60.0 })
        assertEquals(PulseStudy.Source.perSecondRates, rates.second)
        assertEquals(1000.0, rates.first.first(), 0.001)
        assertTrue(VeepooMapping.pulseIntervals(emptyList(), emptyList()).first.isEmpty())
    }

    @Test fun preciseSleepKeepsItsMinuteLineAndWakeDay() {
        val zone = ZoneId.systemDefault()
        val wakeDay = java.time.LocalDate.now(zone).minusDays(1)
        val start = wakeDay.minusDays(1).atTime(23, 30)
        val end = start.plusMinutes(10)
        fun stamp(t: LocalDateTime) = VeepooMapping.stamp(t.year, t.monthValue, t.dayOfMonth, t.hour, t.minute)
        val input = VeepooMapping.SleepInput(sleepStamp = stamp(start), wakeStamp = stamp(end),
            total = 10, deep = 4, light = 4, other = 0, wakes = 0, line = "0000111122", precise = true)
        val night = VeepooMapping.night(listOf(input), morning = wakeDay.toString())
        // The night woke the day before wakeDay+… : it ended on start's calendar date, not wakeDay.
        assertNull(night)
        val night2 = VeepooMapping.night(listOf(input), morning = start.toLocalDate().toString())
        assertNotNull(night2)
        assertEquals(10, night2!!.totalMinutes)
        assertEquals(listOf(0, 1, 2), night2.line.map { it.stage })
        assertEquals(listOf(4, 4, 2), night2.line.map { it.minutes })
        assertEquals(start.atZone(zone).toInstant(), night2.sleepStart)
    }

    @Test fun plainSleepCarriesTotalsWithoutAnInventedLine() {
        val zone = ZoneId.systemDefault()
        val wake = java.time.LocalDate.now(zone).minusDays(1).atTime(7, 0)
        val start = wake.minusHours(7)
        fun stamp(t: LocalDateTime) = VeepooMapping.stamp(t.year, t.monthValue, t.dayOfMonth, t.hour, t.minute)
        val input = VeepooMapping.SleepInput(stamp(start), stamp(wake), total = 400, deep = 120, light = 280,
            other = 0, wakes = 2, line = "0011", precise = false)
        val night = VeepooMapping.night(listOf(input), morning = wake.toLocalDate().toString())!!
        assertEquals(400, night.totalMinutes)
        assertEquals(2, night.wakeCount)
        assertTrue(night.line.isEmpty())
    }

    @Test fun hrvRowsFeedTheSharedRmssdMapping() {
        val row = VeepooMapping.hrvRow("02:10", VeepooMapping.hearts("80,82,79", null), 41)
        val sample = HealthSampleMapping.hrv(row)!!
        assertEquals(3, sample.rrCount)
        assertNotNull(sample.rmssdMS)
        assertEquals(41.0, sample.vendorValue!!, 0.0)
    }

    @Test fun hrvHeartsStayInTenMillisecondUnitsWhicheverFieldArrives() {
        // The SDK fills rrValue with rate x 10 (already ms); rate is the iOS x10 ms unit.
        assertEquals(listOf(80, 82, 79), VeepooMapping.hearts("80,82,79", intArrayOf(800, 820, 790)))
        assertEquals(listOf(80, 82, 79), VeepooMapping.hearts(null, intArrayOf(800, 820, 790)))
        assertEquals(listOf(80, 82, 79), VeepooMapping.hearts("", intArrayOf(800, 820, 790)))
        val sample = HealthSampleMapping.hrv(VeepooMapping.hrvRow("02:10",
            VeepooMapping.hearts(null, intArrayOf(800, 820, 790)), 41))!!
        assertEquals(3, sample.rrCount)
    }

    @Test fun bodyCompositionProgressIsAlwaysPercent() {
        assertEquals(0.01, VeepooMapping.percentFraction(1), 1e-9)
        assertEquals(0.5, VeepooMapping.percentFraction(50), 0.0)
        assertEquals(1.0, VeepooMapping.percentFraction(100), 0.0)
        assertEquals(1.0, VeepooMapping.percentFraction(140), 0.0)
        assertEquals(0.0, VeepooMapping.percentFraction(-3), 0.0)
    }

    @Test fun sportModeLabelReadsTheSameBytesAsIos() {
        assertEquals("NONE", VeepooMapping.sportModeLabel(null, null))
        assertEquals("NONE", VeepooMapping.sportModeLabel(0, 1))
        assertEquals("SINGLE", VeepooMapping.sportModeLabel(3, 0))
        assertEquals("10 TYPES", VeepooMapping.sportModeLabel(3, 1))
        assertEquals("T224 · UNDOCUMENTED", VeepooMapping.sportModeLabel(3, 224))
    }

    @Test fun oxygenRowsCarryRespirationToo() {
        val row = VeepooMapping.oxygenRow("03:00", 96, 14)
        assertEquals(96, HealthSampleMapping.oxygen(row)!!.percent)
        assertEquals(14.0, HealthSampleMapping.respiration(row)!!.breathsPerMinute, 0.0)
        assertNull(HealthSampleMapping.oxygen(VeepooMapping.oxygenRow("03:05", 0, 0)))
    }

    @Test fun statusesAreCarriedThroughVerbatim() {
        assertEquals(FunctionStatus.unsupported, VeepooMapping.functionStatus("UNSUPPORT"))
        assertEquals(FunctionStatus.open, VeepooMapping.functionStatus("SUPPORT_OPEN"))
        assertEquals(FunctionStatus.unknown, VeepooMapping.functionStatus(null))
        assertEquals(BandBattery.ChargeState.charging, VeepooMapping.chargeState(1))
        assertEquals(BandBattery.ChargeState.full, VeepooMapping.chargeState(3))
        assertEquals(BandHealthLightState.continuousFlashing, VeepooMapping.healthLight("RAPID_FLASHING"))
        for (s in BandHealthLightState.entries) assertEquals(s, VeepooMapping.healthLight(VeepooMapping.healthLightVendorName(s)))
    }

    @Test fun healthFunctionFlagsAreTheIosTypesPlusOne() {
        val rows = VeepooMapping.healthFunctions(mapOf(1 to "SUPPORT", 6 to "SUPPORT_OPEN", 9 to "UNSUPPORT"))
        assertEquals(17, rows.size)
        assertTrue(rows[0].support && !rows[0].open)          // blood glucose
        assertTrue(rows[5].support && rows[5].open)           // stress
        assertFalse(rows[8].support)                          // body composition, a definite no
        assertFalse(rows[16].support)
    }

    @Test fun autoSlotsUseTheBandsOwnWindowAndStep() {
        val slot = VeepooMapping.autoSlot(AutoMonitorSlot.Kind.bloodOxygen, on = true, slotModify = true,
            intervalModify = true, startMinute = 22 * 60, endMinute = 24 * 60, interval = 30, stepUnit = 5)
        assertEquals(22, slot.startHour)
        assertEquals(24, slot.endHour)
        assertEquals(5, slot.intervalStepMinutes)
        val lorenz = VeepooMapping.autoSlot(AutoMonitorSlot.Kind.lorentz, true, false, true, 0, 1440, 10, 1)
        assertFalse(lorenz.intervalModifiable)
        assertEquals(AutoMonitorSlot.Kind.hrv, VeepooMapping.autoMeasureKind("HRV"))
    }

    @Test fun firmwareNotesSplitOnDollar() {
        assertEquals(listOf("Better sleep", "Battery"), VeepooMapping.firmwareNotes(" Better sleep $ Battery $ "))
        assertEquals(0.5, VeepooMapping.progressFraction(50.0), 0.0)
        assertEquals(0.5, VeepooMapping.progressFraction(0.5), 0.0)
    }

    @Test fun anEmptyBodyCompositionFieldIsADashNotANumber() {
        val r = VeepooMapping.bodyComposition(bmi = 21.3f, bodyFatRate = 14.8f, fatMass = 11.2f, ffm = 64.4f,
            muscleRate = 0f, muscleMass = 47f, subcutaneousFat = 18.9f, bodyWater = 55.2f, waterContent = 0f,
            skeletalMuscleRate = 42.1f, boneMass = 2.7f, proteinProportion = 17.6f, proteinMass = 13.3f,
            bmr = 1710f, inputWeightKg = 75.6)
        assertEquals(14.8, r.bodyFatPercent, 0.01)
        assertNull(r.muscleRatePercent)
        assertNull(r.waterKg)
        assertEquals(1710, r.bmrKcal)
        assertEquals(75.6, r.inputWeightKg, 0.0)
    }
}
