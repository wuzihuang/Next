package com.nextbody.hoop.band

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.util.Base64

class HomeLaunchPolicyTest {
    private fun jwt(sub: String, email: String, exp: Long): String {
        fun encode(json: String) = Base64.getUrlEncoder().withoutPadding().encodeToString(json.toByteArray())
        return encode("""{"alg":"none","typ":"JWT"}""") + "." +
            encode("""{"sub":"$sub","email":"$email","exp":$exp}""") + ".sig"
    }

    @Test fun sameUserDaySnapshotPaintsImmediately() {
        assertTrue(HomeLaunchPolicy.shouldPaintToday("2026-09-04", "2026-09-04"))
        assertFalse(HomeLaunchPolicy.shouldPaintToday("2026-09-03", "2026-09-04"))
        assertEquals(1, HomeLaunchPolicy.fastLoadLookbackDays)
    }

    @Test fun accessTokenUsableWhenExpiryIsInTheFuture() {
        val token = jwt("user-1", "a@b.c", 2_000_000_000)
        assertTrue(HomeLaunchPolicy.isAccessTokenUsable(token, Instant.ofEpochSecond(1_900_000_000)))
        assertEquals("user-1", HomeLaunchPolicy.jwtSubject(token))
        assertEquals("a@b.c", HomeLaunchPolicy.jwtEmail(token))
    }

    @Test fun accessTokenRejectedInsideLeewayAndWhenExpired() {
        val now = Instant.ofEpochSecond(1_800_000_000)
        assertFalse(HomeLaunchPolicy.isAccessTokenUsable(jwt("u", "e", now.epochSecond + 10), now))
        assertFalse(HomeLaunchPolicy.isAccessTokenUsable(jwt("u", "e", now.epochSecond - 1), now))
        assertFalse(HomeLaunchPolicy.isAccessTokenUsable("not-a-jwt", now))
    }

    @Test fun postgrestInSkipsAnEmptyIdList() {
        assertNull(HomeLaunchPolicy.postgrestIn(emptyList()))
        assertNull(HomeLaunchPolicy.postgrestIn(listOf("", "")))
        assertEquals("in.(aaa,bbb)", HomeLaunchPolicy.postgrestIn(listOf("aaa", "bbb")))
    }

    @Test fun lateReadCannotApplyAfterAccountChangeOrNewerRefresh() {
        assertFalse(HomeLaunchPolicy.acceptsRead("a", "b", 1, 1))
        assertFalse(HomeLaunchPolicy.acceptsRead("a", "a", 1, 2))
        assertTrue(HomeLaunchPolicy.acceptsRead("a", "a", 2, 2))
        assertFalse(HomeLaunchPolicy.acceptsRead(null, null, 1, 1))
    }

    @Test fun summaryRefreshAndSettlement() {
        assertTrue(HomeLaunchPolicy.shouldRefreshSummary(null, null, false))
        assertTrue(HomeLaunchPolicy.shouldRefreshSummary(null, null, true))
        assertFalse(HomeLaunchPolicy.shouldRefreshSummary("r1", "r1", true))
        assertTrue(HomeLaunchPolicy.shouldRefreshSummary("r2", "r1", true))
        assertTrue(HomeLaunchPolicy.shouldRefreshSummary("r1", "r1", false))
        assertTrue(HomeLaunchPolicy.needsEvidenceSettlement(listOf(true)))
        assertTrue(HomeLaunchPolicy.needsEvidenceSettlement(listOf(false, true)))
        assertFalse(HomeLaunchPolicy.needsEvidenceSettlement(listOf(false)))
        assertTrue(HomeLaunchPolicy.needsEvidenceSettlement(null))
        assertTrue(HomeLaunchPolicy.needsEvidenceSettlement(emptyList()))
        assertTrue(HomeLaunchPolicy.needsEvidenceSettlement(listOf(null)))
    }
}
