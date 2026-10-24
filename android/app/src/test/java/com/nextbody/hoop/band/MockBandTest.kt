package com.nextbody.hoop.band

import com.nextbody.hoop.app.MeasureKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class MockBandTest {
    @Before fun setUp() { BandMain.dispatcher = Dispatchers.Unconfined }

    @Test fun readsAreRefusedUntilConnected() = runTest {
        val band = MockBand()
        try { band.readBattery(); fail("expected BAND OFFLINE") } catch (e: BandError.NotConnected) {}
    }

    @Test fun connectBindsTheBandAndAnswersOnRealShapes() = runTest {
        val band = MockBand()
        val progress = mutableListOf<Double>()
        band.connect(DiscoveredBand(MockBand.firstHoop, "NEXTBODY", -46, 96)) { progress.add(it) }
        assertEquals(BandConnectionState.connected, band.state)
        assertEquals(listOf(0.0, 0.25, 0.7, 1.0), progress)
        assertEquals(MockBand.firstHoop, BoundBand.identifier)
        assertEquals(82, band.readBattery().percent)
        assertEquals(288, band.readOriginData(0).size)
        val night = band.readSleep(0)!!
        assertEquals(410, night.totalMinutes)
        assertEquals(410L * 60, night.wakeAt!!.epochSecond - night.sleepStart!!.epochSecond)
        val health = band.readHealthData(0)
        assertEquals(24 * 12, health.temperatures.size)
        assertTrue(band.readCapabilities().supports(MeasureKind.bodyComposition))
    }

    @Test fun heartRateStreamFinishesWithAReading() = runTest {
        val band = MockBand()
        band.connect(DiscoveredBand(MockBand.firstHoop, "NEXTBODY", -46, 96)) {}
        val steps = band.measureHeartRate().toList()
        assertEquals(MeasurementProgress.WaitingForContact, steps.first())
        val last = steps.last() as MeasurementProgress.Finished
        assertEquals(MeasurementResult.HeartRate(62, 54, 34), last.result)
    }

    @Test fun nightPagesCoverEveryCalendarDayTheNightTouched() {
        val zone = ZoneId.of("UTC")
        val start = Instant.parse("2026-10-21T22:30:00Z")
        val wake = Instant.parse("2026-10-22T06:30:00Z")
        val now = Instant.parse("2026-10-22T09:00:00Z")
        assertEquals(listOf(1, 0), OriginDataSync.nightPageOffsets(start, wake, now, zone))
        assertEquals(emptyList<Int>(), OriginDataSync.nightPageOffsets(wake, start, now, zone))
    }
}
