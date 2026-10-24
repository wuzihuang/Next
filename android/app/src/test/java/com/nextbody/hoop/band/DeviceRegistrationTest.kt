package com.nextbody.hoop.band

import com.nextbody.hoop.services.SupabaseFailure
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.IOException
import kotlin.coroutines.cancellation.CancellationException

/** ADR 0003 · one band, one account. How a registration reads the server's refusal and what
 *  it may write about the band on the link. */
class DeviceRegistrationTest {
    private val seed = "C4-2E-8F-1A-73-9D"

    private fun postgrest(message: String, hint: String? = null) = SupabaseFailure.Http(409,
        JSONObject().put("code", "23505").put("details", JSONObject.NULL)
            .put("hint", hint ?: JSONObject.NULL).put("message", message).toString())

    @Test fun theTriggerNamesAreReadFromTheErrorBody() {
        assertEquals(DeviceRegistration.ownedElsewhere, DeviceRegistration.refusal(postgrest("DEVICE_OWNED_ELSEWHERE",
            hint = "The band is bound to another account. It has to be released there first.")))
        assertEquals(DeviceRegistration.alreadyInSet, DeviceRegistration.refusal(postgrest("DEVICE_ALREADY_IN_SET")))
    }

    @Test fun theNameAnywhereElseIsNotARefusal() {
        assertEquals("only the raised message counts", DeviceRegistration.failed,
            DeviceRegistration.refusal(postgrest("duplicate key value violates unique constraint", hint = "DEVICE_OWNED_ELSEWHERE")))
        assertEquals("a body that is not PostgREST's error object says nothing", DeviceRegistration.failed,
            DeviceRegistration.refusal(SupabaseFailure.Http(502, "DEVICE_OWNED_ELSEWHERE")))
        assertEquals(DeviceRegistration.failed, DeviceRegistration.refusal(postgrest("device_owned_elsewhere")))
        assertEquals(DeviceRegistration.failed,
            DeviceRegistration.refusal(SupabaseFailure.Http(409, """{"message":null,"hint":"DEVICE_OWNED_ELSEWHERE"}""")))
    }

    @Test fun transportAndOtherErrorsFail() {
        assertEquals(DeviceRegistration.failed, DeviceRegistration.refusal(SupabaseFailure.Transport(IOException("timeout"))))
        assertEquals(DeviceRegistration.failed, DeviceRegistration.refusal(CancellationException("DEVICE_OWNED_ELSEWHERE")))
        assertEquals(DeviceRegistration.failed, DeviceRegistration.refusal(IllegalStateException("HTTP 409: DEVICE_OWNED_ELSEWHERE")))
    }

    @Test fun aRefreshNeverPointsTheRowAtAnotherBand() {
        // An old row's CoreBluetooth alias stays: nothing proves the linked band is that band.
        assertNull(DeviceRegistration.bleIdentifierWrite(false, "6F1C2C9E-3A4B-4C5D-8E9F-0A1B2C3D4E5F", "AA:BB:CC:DD:EE:01", seed))
        assertNull(DeviceRegistration.bleIdentifierWrite(false, "AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02", seed))
        assertNull(DeviceRegistration.bleIdentifierWrite(false, null, "AA:BB:CC:DD:EE:01", seed))
    }

    @Test fun pairingPointsTheRowAtTheChosenBand() {
        assertEquals("AA:BB:CC:DD:EE:02", DeviceRegistration.bleIdentifierWrite(true, "AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02", seed))
        assertNull("the same band writes nothing", DeviceRegistration.bleIdentifierWrite(true, "AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:01", seed))
        assertNull("the emulator seed never replaces a binding", DeviceRegistration.bleIdentifierWrite(true, "AA:BB:CC:DD:EE:01", seed, seed))
        assertNull(DeviceRegistration.bleIdentifierWrite(true, "AA:BB:CC:DD:EE:01", null, seed))
    }
}
