package com.nextbody.hoop.band

import com.nextbody.hoop.services.SupabaseFailure
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.Instant
import java.util.UUID

class BandDomainSyncTest {
    @Test fun rrInputsRetainOriginalOrder() {
        val sample = HealthSampleMapping.hrv(mapOf("time" to "12:05", "hearts" to listOf(80, 84, 81)))!!
        assertEquals(listOf(800.0, 840.0, 810.0), sample.rrMilliseconds)
    }

    @Test fun rejectedAcknowledgmentDoesNotConfirm() {
        val ack = BandIngestionAcknowledgment.fromJson(JSONObject("""{"inserted":1,"completed":0,"unchanged":0,"rejected":1,"affected_days":["2026-09-04"]}"""))
        assertFalse(ack.confirms(2)); assertFalse(ack.confirms(1))
        val ok = BandIngestionAcknowledgment.fromJson(JSONObject("""{"inserted":0,"completed":0,"unchanged":2,"rejected":0,"affected_days":[]}"""))
        assertTrue(ok.confirms(2)); assertFalse(ok.hasChanges); assertNull(ok.receipts)
    }

    @Test fun saveMergesAcknowledgedRangesAndPurgeIsPerAccount() {
        val user = UUID.randomUUID().toString(); val other = UUID.randomUUID().toString()
        val t = Instant.ofEpochSecond(1_800_000_000)
        BandDomainSyncState.save(listOf(BandDomainSyncState("hrv", BandDomainReadStatus.complete, t, t, t.plusSeconds(60), null, null)), user, "band", "2026-09-08")
        BandDomainSyncState.save(listOf(BandDomainSyncState("hrv", BandDomainReadStatus.failed, t, null, null, t, t.plusSeconds(60))), user, "band", "2026-09-08")
        val loaded = BandDomainSyncState.load(user, "band", "2026-09-08").single()
        assertEquals(BandDomainReadStatus.failed, loaded.status)
        assertEquals(t, loaded.acknowledgedStart)
        BandPrefs.setString("nb.sync.day-outcome.v1.$user.band.2026-09-08", "success")
        BandPrefs.setString("nb.sync.day-outcome.v1.$other.band.2026-09-08", "success")
        BandDomainSyncState.purge(user)
        assertNull(BandPrefs.string("nb.sync.day-outcome.v1.$user.band.2026-09-08"))
        assertTrue(BandDomainSyncState.load(user, "band", "2026-09-08").isEmpty())
        assertEquals("success", BandPrefs.string("nb.sync.day-outcome.v1.$other.band.2026-09-08"))
        BandDomainSyncState.purge(other)
    }

    @Test fun oldServerRequestsFullValuesThenUsesLegacyRPC() = runTest {
        val calls = mutableListOf<String>()
        val transport = BandDeltaTransport(rpc = { name, args, owner ->
            calls.add(name)
            assertEquals("alice", owner)
            if (name == "ingest_band_delta") throw SupabaseFailure.Http(404, """{"code":"PGRST202"}""")
            assertNull(args["p_receipts"])
            BandIngestionAcknowledgment(1, 0, 0, 0, emptyList())
        })
        val miss = transport.ingest(mapOf("p_samples" to emptyList<Any>(), "p_receipts" to listOf(mapOf("ts" to "t", "receipt" to "token"))), "alice")
        assertEquals(listOf("t"), miss.needsSamples)
        val full = transport.ingest(mapOf("p_samples" to listOf(mapOf("ts" to "t", "heart" to 61))), "alice")
        assertTrue(full.confirms(1))
        assertEquals(listOf("ingest_band_delta", "ingest_band_domain"), calls)
    }

    @Test fun unknownFailuresNeverDowngrade() = runTest {
        for (error in listOf(SupabaseFailure.Http(403, """{"code":"42501"}"""), SupabaseFailure.Http(500, "x"), SupabaseFailure.Http(404, "other"))) {
            val calls = mutableListOf<String>()
            val transport = BandDeltaTransport(rpc = { name, _, _ -> calls.add(name); throw error })
            try { transport.ingest(mapOf("p_samples" to emptyList<Any>()), "alice"); fail() } catch (_: SupabaseFailure) {}
            assertEquals(listOf("ingest_band_delta"), calls)
        }
    }

    @Test fun bundleMissingRPCIsRememberedForFiveMinutes() = runTest {
        var now = Instant.ofEpochSecond(1_000)
        var calls = 0
        val transport = BandDeltaTransport(now = { now }, rpc = { _, _, _ -> fail(); throw IllegalStateException() },
            bundleRPC = { args, _ ->
                calls += 1
                if (calls == 1) {
                    assertEquals(1250, args["p_budget_ms"])
                    throw SupabaseFailure.Http(404, """{"code":"PGRST202"}""")
                }
                BandBundleReply(mapOf("results" to emptyList<Any>(), "sleep" to null))
            })
        assertNull(transport.bundle(listOf(mapOf("p_domain" to "origin")), mapOf("user_id" to "alice"), 1250, "alice"))
        assertNull(transport.bundle(emptyList(), null, null, "alice"))
        assertEquals(1, calls)
        now = now.plusSeconds(301)
        assertNotNull(transport.bundle(emptyList(), null, null, "alice"))
        assertEquals(2, calls)
    }

    @Test fun bundleReplyParsesEntries() {
        val reply = BandBundleReply(JSONObject("""{"results":[{"deferred":true},{"error":{"code":"X","message":"m"}},
            {"ok":{"inserted":1,"completed":0,"unchanged":0,"rejected":0,"affected_days":[]}}],"sleep":{"ok":[{"user_id":"a"}]}}"""))
        assertEquals(BandBundleReply.Entry.Deferred, reply.results[0])
        assertEquals(BandBundleReply.Entry.Error("X", "m"), reply.results[1])
        assertTrue(reply.results[2] is BandBundleReply.Entry.Ok)
        assertTrue(reply.sleep is BandBundleReply.SleepEntry.Ok)
    }
}
