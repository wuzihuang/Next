package com.nextbody.hoop.band

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneOffset

class FindDistanceAndAlarmMathTest {
    @Test fun cutsAreDistanceNotQuality() {
        val cases = mapOf(-52 to FindDistance.near, -59 to FindDistance.near, -60 to FindDistance.close,
            -69 to FindDistance.close, -70 to FindDistance.close, -71 to FindDistance.away,
            -84 to FindDistance.away, -85 to FindDistance.away, -86 to FindDistance.far, -89 to FindDistance.far)
        cases.forEach { (rssi, d) -> assertEquals(d, FindDistance.from(rssi)) }
    }

    @Test fun lampGlowIsAFalloff() {
        assertEquals(FindLampGlow.hot, FindDistance.glow(FindDistance.near, FindDistance.near))
        assertEquals(FindLampGlow.warm, FindDistance.glow(FindDistance.close, FindDistance.near))
        assertEquals(FindLampGlow.off, FindDistance.glow(FindDistance.away, FindDistance.near))
        assertEquals(FindLampGlow.off, FindDistance.glow(FindDistance.away, FindDistance.far))
        assertEquals(FindLampGlow.off, FindDistance.glow(FindDistance.near, null))
        assertEquals("−52", FindDistance.glyph(-52))
        assertEquals(4, FindDistance.near.barsLit)
        assertEquals(1, FindDistance.far.barsLit)
        assertNotEquals("CLOSE", FindDistance.close.copyKey)
        assertEquals("Find · very near", FindDistance.near.copyKey)
    }

    @Test fun firmwarePhasesMatchVendorOrdinals() {
        assertEquals(FindHoopPhase.unsupported, FindHoopPhase.from(0))
        assertEquals(FindHoopPhase.enter, FindHoopPhase.from(1))
        assertEquals(FindHoopPhase.exit, FindHoopPhase.from(2))
        assertEquals(FindHoopPhase.timeout, FindHoopPhase.from(3))
        assertEquals(FindHoopPhase.unsupported, FindHoopPhase.from(9))
    }

    @Test fun malformedFirmwareRowIsInvalid() {
        assertFalse(BandAlarm(74, 56, 180, true, 196, "2084-06-57", 0).isValidDeviceValue)
        for (mask in listOf(0, 31, 96, 127)) assertTrue(BandAlarm(1, 7, 30, true, mask, "0000-00-00", 0).isValidDeviceValue)
    }

    @Test fun realHoopCapabilityUsesTextAlarmCommands() {
        val bytes = intArrayOf(0xa7, 1, 0, 2, 2, 2, 1, 0, 6, 20, 1, 2, 0, 0, 0, 1, 0, 6, 3, 1).map { it.toByte() }.toByteArray()
        val kind = BandAlarmProtocol.from(bytes)
        assertEquals(BandAlarmProtocol.text, kind)
        assertEquals(1, kind?.sdkMode(0)); assertEquals(3, kind?.sdkMode(2)); assertEquals(10, kind?.capacity)
        assertNull(BandAlarmProtocol.from(bytes.copyOf(17)))
        assertNull(BandAlarmProtocol.from(null))
        for (flag in 1..7) {
            val d = bytes.copyOf(); d[17] = flag.toByte()
            assertEquals(if (flag < 5) BandAlarmProtocol.scene else BandAlarmProtocol.text, BandAlarmProtocol.from(d))
        }
    }

    @Test fun weekBitsAndPhrases() {
        assertEquals(1, BandAlarmMath.Weekday.monday.bit)
        assertEquals(64, BandAlarmMath.Weekday.sunday.bit)
        assertEquals(31, BandAlarmMath.weekdaysMask)
        assertEquals(127, BandAlarmMath.everyDayMask)
        assertEquals("ONCE", BandAlarmMath.phrase(0))
        assertEquals("EVERY DAY", BandAlarmMath.phrase(127))
        assertEquals("WEEKDAYS", BandAlarmMath.phrase(31))
        assertEquals("WEEKEND", BandAlarmMath.phrase(BandAlarmMath.weekendMask))
        assertEquals("MON · WED", BandAlarmMath.phrase(1 or 4))
        assertFalse(BandAlarm.emptyRead().showsSwitch)
    }

    @Test fun nextIDSkipsUsedSlots() {
        assertEquals(1, BandAlarmMath.nextID(emptyList()))
        assertNull(BandAlarmMath.nextID(emptyList(), ceiling = 0))
        val alarms = listOf(BandAlarm(0, 7, 30, true, 31, BandAlarm.onceDatePlaceholder, 0),
            BandAlarm(2, 8, 45, true, 31, BandAlarm.onceDatePlaceholder, 0))
        assertEquals(1, BandAlarmMath.nextID(alarms))
        val full = (1..20).map { BandAlarm(it, 7, 0, true, 31, BandAlarm.onceDatePlaceholder, 0) }
        assertNull(BandAlarmMath.nextID(full))
        assertTrue(BandAlarmMath.isFull(full))
        assertEquals(20, BandAlarmMath.nextID(full.dropLast(1)))
        assertEquals(7, BandAlarmMath.nextID(full.filter { it.id != 7 }))
    }

    @Test fun onceDateAndPrepared() {
        val utc = ZoneOffset.UTC
        val morning = LocalDateTime.of(2026, 9, 6, 8, 0).toInstant(utc)
        assertEquals("2026-09-07", BandAlarmMath.onceDate(7, 30, morning, utc))
        assertEquals("2026-09-06", BandAlarmMath.onceDate(9, 0, morning, utc))
        val draft = BandAlarm(1, 7, 30, true, 31, "1999-01-01", 7)
        val repeating = BandAlarmMath.prepared(draft, morning, utc)
        assertEquals(0, repeating.scene)
        assertEquals(BandAlarm.onceDatePlaceholder, repeating.date)
        val once = BandAlarmMath.prepared(draft.copy(repeatMask = 0), morning, utc)
        assertEquals("2026-09-07", once.date)
        assertEquals("07:30", once.clock)
    }
}
