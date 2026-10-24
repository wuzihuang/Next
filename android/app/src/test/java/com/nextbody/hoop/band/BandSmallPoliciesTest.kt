package com.nextbody.hoop.band

import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.Instant
import java.util.UUID

class BandSmallPoliciesTest {
    @Test fun autoMeasurementIntervalOptions() {
        assertEquals((0..180).toList(), AutoMeasurementIntervalPolicy.options(0))
        val five = AutoMeasurementIntervalPolicy.options(5)
        assertEquals(listOf(1, 2, 3, 4, 5, 10), five.take(6))
        assertEquals(180, five.last())
        assertTrue(AutoMeasurementIntervalPolicy.options(-1).isEmpty())
        assertTrue(AutoMeasurementIntervalPolicy.options(181).isEmpty())
        assertTrue(AutoMeasurementIntervalPolicy.isValid(30, 10))
        assertFalse(AutoMeasurementIntervalPolicy.isValid(35, 10))
    }

    @Test fun autoMeasurementSwitchFallback() {
        val switchData = MutableList(20) { 0 }.also { it[4] = 1; it[5] = 2; it[12] = 7; it[16] = 1 }
        val two = MutableList(12) { 0 }.also { it[4] = 2; it[9] = 1 }
        assertTrue(AutoMeasurementSwitchFallback.hasSwitchTables(switchData, emptyList()))
        val r = AutoMeasurementSwitchFallback.readings(switchData, two, oxygenSupported = true, oxygenOn = false)
        assertEquals(listOf(AutoMeasurementSwitchFallback.Kind.heartRate to true, AutoMeasurementSwitchFallback.Kind.bloodPressure to false, AutoMeasurementSwitchFallback.Kind.scientificSleep to true,
            AutoMeasurementSwitchFallback.Kind.bloodOxygen to false, AutoMeasurementSwitchFallback.Kind.temperature to false, AutoMeasurementSwitchFallback.Kind.stress to true), r.map { it.kind to it.on })
    }

    @Test fun originObservationPolicy() {
        val start = Instant.ofEpochSecond(1_788_235_200)
        fun accepts(slot: Instant, now: Instant) = OriginObservationPolicy.accepts(slot, start, start.plusSeconds(86400), now)
        val now = start.plusSeconds(12 * 3600 + 120)
        assertTrue(accepts(start.plusSeconds(11 * 3600 + 55 * 60), now))
        assertFalse(accepts(start.plusSeconds(12 * 3600), now))
        val end = start.plusSeconds(86400)
        assertTrue(accepts(end.minusSeconds(300), end))
        assertFalse(accepts(end, end.plusSeconds(300)))
        val midnight = start.plusSeconds(86400)
        assertEquals(midnight.minusSeconds(60), OriginObservationPolicy.coverageEnd(start, midnight, midnight.plusSeconds(600), midnight.minusSeconds(60)))
        assertNull(OriginObservationPolicy.coverageEnd(midnight, midnight.plusSeconds(86400), midnight.plusSeconds(600), midnight.minusSeconds(60)))
    }

    @Test fun backgroundRefreshPolicy() {
        val now = Instant.ofEpochSecond(1_800_000_000)
        assertEquals("com.nextbody.hoop.refresh", BackgroundRefreshPolicy.taskIdentifier)
        assertTrue(BackgroundRefreshPolicy.shouldSchedule(1, true, true))
        assertFalse(BackgroundRefreshPolicy.shouldSchedule(0, true, true))
        assertEquals(now.plusSeconds(20 * 60), BackgroundRefreshPolicy.nextBeginDate(now, now.minusSeconds(600)))
        assertEquals(now, BackgroundRefreshPolicy.nextBeginDate(now, now.minusSeconds(7200)))
        assertEquals(now.plusSeconds(1800), BackgroundRefreshPolicy.nextBeginDate(now, null))
        assertEquals(now.plusSeconds(1800), BackgroundRefreshPolicy.nextBeginDate(now, now.plusSeconds(60)))
        assertTrue(BackgroundRefreshPolicy.completed(BandRefreshResult.Status.throttled))
        assertFalse(BackgroundRefreshPolicy.completed(BandRefreshResult.Status.cancelled))
    }

    @Test fun metadataRefreshPolicy() {
        val policy = BandMetadataRefreshPolicy()
        val key = BandMetadataRefreshPolicy.Key("a", "b", "d", "f")
        assertTrue(policy.needsRefresh(key))
        policy.complete(key, success = false)
        assertTrue(policy.needsRefresh(key))
        policy.complete(key, success = true)
        assertFalse(policy.needsRefresh(key))
        assertTrue(policy.needsRefresh(key.copy(firmware = "g")))
        assertTrue(policy.needsRefresh(null))
    }

    @Test fun wearTimeline() {
        fun at(h: Double) = Instant.ofEpochSecond(1_800_000_000 + (h * 3600).toLong())
        val set = listOf(SlotBinding(HoopSlot.a, "band-A", boundAt = at(0.0)), SlotBinding(HoopSlot.b, "band-B", boundAt = at(6.0)))
        assertEquals(HoopSlot.a, WearTimeline(bindings = set).wearer(at(8.0)))
        val t = WearTimeline(bindings = set).declaring(HoopSlot.b, at(8.5), at(9.0), "op-1")
        assertEquals(HoopSlot.a, t.wearer(at(8.0)))
        assertEquals(HoopSlot.b, t.wearer(at(9.0)))
        assertEquals(at(8.5), t.wearingSince(at(10.0)))
        val twice = t.declaring(HoopSlot.b, at(7.5), at(9.5), "op-1")
        assertEquals(1, twice.events.size)
        assertEquals(HoopSlot.b, twice.wearer(at(8.0)))
        assertEquals(3, WearTimeline.pendingDays(at(0.0), null, at(72.0), 7))
        assertEquals(7, WearTimeline.pendingDays(at(0.0), null, at(12 * 24.0), 7))
        assertEquals(0, WearTimeline.pendingDays(null, null, at(30.0), 7))
    }

    @Test fun deviceSlotsPersist() {
        DeviceSlots.forgetAll()
        DeviceSlots.set(SlotBinding(HoopSlot.b, "band-B", name = "B"))
        DeviceSlots.set(SlotBinding(HoopSlot.a, "band-A", boundAt = Instant.ofEpochSecond(100)))
        assertEquals(listOf(HoopSlot.a, HoopSlot.b), DeviceSlots.bindings.map { it.slot })
        assertEquals(Instant.ofEpochSecond(100), DeviceSlots.binding(HoopSlot.a)?.boundAt)
        assertTrue(DeviceSlots.hasSecond)
        DeviceSlots.transport = HoopSlot.b
        DeviceSlots.remove(HoopSlot.b)
        assertEquals(HoopSlot.a, DeviceSlots.transport)
        DeviceSlots.forgetAll()
        assertTrue(DeviceSlots.bindings.isEmpty())
    }

    @Test fun releaseErrorMessages() {
        assertEquals("Your last wear change is still being saved. Try again shortly.", DeviceReleaseError.message(DeviceReleaseError.PendingChanges))
        assertEquals("Your session has expired. Sign in again to remove this NEXTBODY.",
            DeviceReleaseError.message(com.nextbody.hoop.services.SupabaseFailure.Http(401, "")))
        assertEquals("Unable to reach the server. Check your internet connection and try again.",
            DeviceReleaseError.message(com.nextbody.hoop.services.SupabaseFailure.Transport(java.io.IOException())))
    }

    @Test fun activationGate() = runTest {
        val gate = DeviceActivationGate()
        val a = UUID.randomUUID(); val b = UUID.randomUUID()
        gate.prepare(a) { true }
        assertTrue(gate.isHeld)
        try { gate.prepare(b) { true }; fail() } catch (_: DeviceActivationGate.Failure) {}
        gate.release(a)
        try { gate.prepare(b, timeoutSeconds = 0.0) { false }; fail() } catch (_: DeviceActivationGate.Failure) {}
        assertFalse(gate.isHeld)
    }

    @Test fun readinessFlightSharesSameKey() = runTest {
        val flight = BandReadinessFlight(this)
        var runs = 0
        val first = async { flight.run("k") { runs++; kotlinx.coroutines.delay(10); true } }
        val second = async { flight.run("k") { runs++; false } }
        assertTrue(first.await()); assertTrue(second.await())
        assertEquals(1, runs)
        assertTrue(BandReadinessReceiptPolicy.canReuse(true, true, false, true, 2.0))
        assertFalse(BandReadinessReceiptPolicy.canReuse(true, true, false, true, 4.0))
    }
}
